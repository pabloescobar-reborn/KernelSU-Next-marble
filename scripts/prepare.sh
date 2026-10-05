#!/usr/bin/env bash
set -euo pipefail
source config/marble.env
: "${SOURCE:?}" "${MANAGER:?}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
ROOT="${PWD}"; K="${ROOT}/kernel-source"
J="${ROOT}/config/kernel-sources.json"; MJ="${ROOT}/config/managers.json"

branch="$(jq -r --arg s "${SOURCE}" '.[$s].branch' "${J}")"
clone() { git clone -q --depth=1 -b "${branch}" "https://github.com/${SOURCE}/$1" "$2"; }
rm -rf "${K}"
clone "$(jq -r --arg s "${SOURCE}" '.[$s].kernel.repo' "${J}")" "${K}"
for pair in "modules:modules" "devicetrees:sm8450-devicetrees"; do
  repo="$(jq -r --arg s "${SOURCE}" --arg k "${pair%%:*}" '.[$s][$k].repo // empty' "${J}")"
  if [[ -n "${repo}" ]]; then clone "${repo}" "${K}/${pair##*:}"; fi
done

case "${MANAGER}" in
  kernelsu)      dir=KernelSU ;;
  kernelsu-next) dir=KernelSU-Next ;;
  *) echo "::error::Unknown manager ${MANAGER}"; exit 1 ;;
esac
m() { jq -r --arg m "${MANAGER}" "$1" "${MJ}"; }
mrepo="$(m '.[$m].repo')"; mref="$(m '.[$m].ref // empty')"
if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  o="$(m '.[$m].susfs.repo? // empty')"; [[ -z "${o}" ]] || mrepo="${o}"
  o="$(m '.[$m].susfs.ref? // empty')";  [[ -z "${o}" ]] || mref="${o}"
fi
url="https://github.com/${mrepo}"

cd "${K}"
rm -rf drivers/kernelsu
if git ls-files -s -- "${dir}" | grep -q '^160000' \
   && git submodule update --init --recursive -- "${dir}"; then
  echo "${dir}: initialised as submodule"
  if [[ -n "${mref}" ]]; then
    git -C "${dir}" fetch -q --tags "${url}" "${mref}"
    git -C "${dir}" checkout -qf FETCH_HEAD
  fi
else
  echo "${dir}: cloning ${url}"
  rm -rf "${dir}"
  git clone -q --filter=blob:none "${url}" "${dir}"
  [[ -z "${mref}" ]] || git -C "${dir}" checkout -qf "${mref}"
fi
echo "${dir} @ $(git -C "${dir}" rev-parse --short HEAD) ($(git -C "${dir}" rev-list --count HEAD) commits)"

ln -sfn "../${dir}/kernel" drivers/kernelsu
grep -q 'kernelsu' drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig \
  || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
[[ -f drivers/kernelsu/Kconfig ]] || { echo "::error::drivers/kernelsu/Kconfig missing"; exit 1; }

if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  grep -q 'KSU_SUSFS' drivers/kernelsu/Kconfig \
    || { echo "::error::${MANAGER}@${mref:-default} has no KSU_SUSFS symbol - wrong ref for SUSFS"; exit 1; }
  tmp="$(mktemp -d)"
  git clone -q --filter=blob:none --no-checkout "${SUSFS_REPO}" "${tmp}"
  git -C "${tmp}" checkout -q "${SUSFS_BRANCH}"
  p="${tmp}/kernel_patches"
  patch -p1 --no-backup-if-mismatch < "$(ls "${p}"/50_add_susfs_in_*.patch | head -n1)"
  cp "${p}"/fs/*.c fs/
  cp "${p}"/include/linux/*.h include/linux/
  echo "SUSFS applied"
fi

need="$(grep -rhoE '\bksu_[a-z0-9_]+\(' fs kernel security drivers/input mm 2>/dev/null | tr -d '(' | sort -u || true)"
missing=""
for sym in ${need}; do
  grep -rqw "${sym}" drivers/kernelsu/ || missing="${missing} ${sym}"
done
if [[ -n "${missing}" && "${ENABLE_SUSFS}" != "true" ]]; then
  echo "::warning::kernel calls ksu symbols that ${MANAGER} does not define:${missing}"
elif [[ -n "${missing}" ]]; then
  echo "::error::kernel calls ksu symbols that ${MANAGER}@${mref:-default} does not define:${missing}"
  echo "::error::SUSFS branch ${SUSFS_BRANCH} and the manager ref are out of sync (pin SUSFS_BRANCH or change the manager ref)"
  exit 1
fi
echo "hook symbols OK: $(echo ${need})"

