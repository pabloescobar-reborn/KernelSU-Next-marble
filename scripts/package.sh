#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
work="$(mktemp -d)"
cp -r ak3/. "${work}/"; rm -f "${work}/README.md"
cp LICENSE "${work}/LICENSE"

count=0
for d in artifacts/*_*/; do
  n="$(basename "${d}")"; src="${n%%_*}"; mgr="${n#*_}"
  [[ -s "${d}Image" ]] || continue
  mkdir -p "${work}/${src}"
  cp "${d}Image" "${work}/${src}/${mgr}"
  # dtb/dtbo depend on the source tree only, not on the manager
  for f in dtb dtbo; do
    if [[ -s "${d}${f}" && ! -e "${work}/${src}/${f}" ]]; then cp "${d}${f}" "${work}/${src}/${f}"; fi
  done
  count=$((count+1)); echo "packed ${src}/${mgr}"
done
(( count > 0 )) || { echo "::error::no kernels to package"; exit 1; }

mkdir -p release
zip_name="marble-kernel-$(date +%Y.%m.%d).zip"
(cd "${work}" && zip -r9q "${OLDPWD}/release/${zip_name}" . -x ".git/*" "*placeholder*")
(cd release && sha256sum "${zip_name}" > "${zip_name}.sha256")
unzip -l "release/${zip_name}" | grep -E ' (aosp|clo)/'
echo "zip_name=${zip_name}" >> "${GITHUB_OUTPUT:-/dev/null}"
