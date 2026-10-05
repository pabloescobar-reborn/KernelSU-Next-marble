#!/usr/bin/env bash
# package.sh single     env SHORT MANAGER  -> one zip with one kernel:  <short>-<manager>-marble-DATE.zip
# package.sh combined   artifacts/bin_<short>_<manager>/ -> one zip with aosp/ + clo/ folders (menu)
set -euo pipefail
shopt -s nullglob
mode="${1:?usage: package.sh single|combined}"
date="$(date +%Y.%m.%d)"
work="$(mktemp -d)"
cp -r ak3/. "${work}/"; rm -f "${work}/README.md"
cp LICENSE "${work}/LICENSE"

copy_dt() { # <from-dir> <to-dir>
  for f in dtb dtbo; do
    if [[ -s "$1/${f}" && ! -e "$2/${f}" ]]; then cp "$1/${f}" "$2/${f}"; fi
  done
}

case "${mode}" in
  single)
    : "${SHORT:?}" "${MANAGER:?}"
    d="dist/${SHORT}/${MANAGER}"
    [[ -s "${d}/Image" ]] || { echo "::error::missing ${d}/Image"; exit 1; }
    cp "${d}/Image" "${work}/Image"
    copy_dt "${d}" "${work}"
    echo "${SHORT} ${MANAGER}" > "${work}/variant"
    zip_name="${SHORT}-${MANAGER}-marble-${date}.zip"
    ;;
  combined)
    count=0
    for d in artifacts/bin_*/; do
      n="$(basename "${d}")"; n="${n#bin_}"; src="${n%%_*}"; mgr="${n#*_}"
      [[ -s "${d}Image" ]] || continue
      mkdir -p "${work}/${src}"
      cp "${d}Image" "${work}/${src}/${mgr}"
      copy_dt "${d%/}" "${work}/${src}"
      count=$((count+1)); echo "packed ${src}/${mgr}"
    done
    (( count > 0 )) || { echo "::error::no kernels to package"; exit 1; }
    zip_name="marble-kernel-${date}.zip"
    ;;
  *) echo "::error::unknown mode ${mode}"; exit 1 ;;
esac

mkdir -p release
(cd "${work}" && zip -r9q "${OLDPWD}/release/${zip_name}" . -x ".git/*" "*placeholder*")
(cd release && sha256sum "${zip_name}" > "${zip_name}.sha256")
unzip -l "release/${zip_name}" | grep -vE '/$' | tail -n +4 | head -n 30
echo "zip_name=${zip_name}" >> "${GITHUB_OUTPUT:-/dev/null}"
