#!/usr/bin/env bash
# env: SOURCE SHORT MANAGER ENABLE_SUSFS LTO USE_CCACHE TOOLCHAIN CLANG_BIN
set -euo pipefail
source config/marble.env
: "${SOURCE:?}" "${SHORT:?}" "${MANAGER:?}" "${CLANG_BIN:?}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"; LTO="${LTO:-thin}"; USE_CCACHE="${USE_CCACHE:-true}"
ROOT="${PWD}"; OUT="${ROOT}/out"; DIST="${ROOT}/dist/${SHORT}/${MANAGER}"
J="${ROOT}/config/kernel-sources.json"
mkdir -p "${OUT}" "${DIST}"

JOBS="$(nproc)"
# LLVM 22 links OOM on ~16 GiB runners at full parallelism
if [[ "${TOOLCHAIN:-}" == "llvm-22.1.8" ]] && (( JOBS > 2 )); then JOBS=2; fi

export PATH="${CLANG_BIN}:${PATH}" ARCH SUBARCH="${ARCH}"
export KBUILD_BUILD_USER=marble KBUILD_BUILD_HOST=github-actions
CC=clang
if [[ "${USE_CCACHE}" == "true" ]] && command -v ccache >/dev/null; then
  export CCACHE_DIR="${HOME}/.ccache" CCACHE_COMPILERCHECK=content CCACHE_NOHASHDIR=true
  ccache -M 2G; ccache -o compression=true; ccache -z || true
  CC="ccache clang"
fi
clang --version | head -n1

cd kernel-source
M=(O="${OUT}" ARCH="${ARCH}" LLVM=1 LLVM_IAS=1 CC="${CC}")

# defconfig + fragments from the preset
base="$(jq -r --arg s "${SOURCE}" '.[$s].kernel.defconfig' "${J}")"
mapfile -t frags < <(jq -r --arg s "${SOURCE}" '.[$s].kernel.config_fragments[]' "${J}")
make "${M[@]}" "${base}"
paths=()
for f in "${frags[@]}"; do
  [[ -f "arch/${ARCH}/configs/${f}" ]] || { echo "::error::missing fragment ${f}"; exit 1; }
  paths+=("arch/${ARCH}/configs/${f}")
done
./scripts/kconfig/merge_config.sh -O "${OUT}" -m "${OUT}/.config" "${paths[@]}"

cfg() { scripts/config --file "${OUT}/.config" "$@" || true; }
cfg -e KSU
if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  cfg -e KSU_SUSFS
  # the SUSFS kernel patch inserts the ksu_* hooks by hand, so the manager must be built in
  # manual-hook mode (kprobe mode does not define ksu_handle_*_sucompat -> undefined symbol at link)
  if grep -rqE '^config KSU_MANUAL_HOOK' drivers/kernelsu/; then cfg -e KSU_MANUAL_HOOK; fi
  if grep -rqE '^config KSU_KPROBES_HOOK' drivers/kernelsu/; then cfg -d KSU_KPROBES_HOOK; fi
fi
case "${LTO}" in
  none) cfg -d LTO_CLANG -d LTO_CLANG_THIN -d LTO_CLANG_FULL -e LTO_NONE ;;
  thin) cfg -d LTO_NONE -d LTO_CLANG_FULL -e LTO_CLANG -e LTO_CLANG_THIN ;;
  full) cfg -d LTO_NONE -d LTO_CLANG_THIN -e LTO_CLANG -e LTO_CLANG_FULL ;;
esac
make "${M[@]}" olddefconfig
grep '^CONFIG_KSU' "${OUT}/.config" || true
grep -q '^CONFIG_KSU=y$' "${OUT}/.config" || { echo "::error::CONFIG_KSU not enabled"; exit 1; }
if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  grep -q '^CONFIG_KSU_SUSFS=y$' "${OUT}/.config" || { echo "::error::CONFIG_KSU_SUSFS not enabled"; exit 1; }
fi

# Cap ThinLTO codegen parallelism + persistent cache. Passed on the make command line
# (an env LD= is ignored when LLVM=1 sets LD itself).
extra=()
if [[ "${LTO}" == "thin" ]]; then
  mkdir -p "${HOME}/.cache/thinlto"
  extra=(LDFLAGS_vmlinux="--thinlto-jobs=2 --thinlto-cache-dir=${HOME}/.cache/thinlto")
fi

make -j"${JOBS}" "${M[@]}" "${extra[@]}" Image dtbs

img="${OUT}/arch/arm64/boot/Image"
[[ -s "${img}" && "$(stat -c%s "${img}")" -gt 5000000 ]] || { echo "::error::Image missing/too small"; exit 1; }
cp "${img}" "${DIST}/Image"
dts="${OUT}/arch/arm64/boot/dts"
find "${dts}" -name '*.dtb'  -exec cat {} + > "${DIST}/dtb"
find "${dts}" -name '*.dtbo' -exec cat {} + > "${DIST}/dtbo" || true
ls -l "${DIST}"
[[ "${USE_CCACHE}" != "true" ]] || ccache -s || true
