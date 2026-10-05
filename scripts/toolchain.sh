#!/usr/bin/env bash
# usage: toolchain.sh <llvm-22.1.8|android-rNNNNNN>  -> exports CLANG_BIN to GITHUB_ENV
set -euo pipefail
source config/marble.env
tc="${1:?toolchain id}"
mkdir -p toolchain

case "${tc}" in
  llvm-22.1.8)
    dest="${PWD}/toolchain/llvm-22.1.8"
    if [[ ! -x "${dest}/bin/clang" ]]; then
      curl -fL --retry 3 --retry-delay 10 -o /tmp/llvm.tar.xz "${LLVM_22_1_8_URL}"
      echo "${LLVM_22_1_8_SHA256}  /tmp/llvm.tar.xz" | sha256sum -c -
      mkdir -p "${dest}"
      tar -xJf /tmp/llvm.tar.xz -C "${dest}" --strip-components=1
    fi
    ;;
  android-r*)
    ver="clang-${tc#android-}"
    dest="${PWD}/toolchain/${ver}"
    if [[ ! -x "${dest}/bin/clang" ]]; then
      repo="$(mktemp -d)"; found=""
      for ref in ${ANDROID_CLANG_REFS}; do
        rm -rf "${repo}"
        git clone -q --filter=blob:none --no-checkout --depth=1 --branch "${ref}" \
          "${ANDROID_CLANG_REPO}" "${repo}" 2>/dev/null || continue
        if git -C "${repo}" ls-tree --name-only HEAD | grep -qx "${ver}"; then found="${ref}"; break; fi
        echo "${ver} not in ${ref} (has: $(git -C "${repo}" ls-tree --name-only HEAD | grep '^clang-r' | tr '\n' ' '))"
      done
      [[ -n "${found}" ]] || { echo "::error::${ver} not found in any of: ${ANDROID_CLANG_REFS}"; exit 1; }
      echo "Using ${ver} from ${found}"
      git -C "${repo}" sparse-checkout set "${ver}"
      git -C "${repo}" checkout -q
      mv "${repo}/${ver}" "${dest}"
      rm -rf "${repo}"
    fi
    ;;
  *) echo "::error::Unsupported toolchain ${tc}"; exit 1 ;;
esac

test -x "${dest}/bin/clang"
"${dest}/bin/clang" --version | head -n1
echo "CLANG_BIN=${dest}/bin" >> "${GITHUB_ENV}"
