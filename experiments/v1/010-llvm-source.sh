#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive

if (echo "$LLVM_RELEASE" | grep -qE '[0-9]+\.'); then
  # release version
  LLVM_SRC_URL=$LLVM_SRC_URL/llvmorg-${LLVM_RELEASE}.tar.gz
else
  # git hash
  LLVM_SRC_URL=$LLVM_SRC_URL/${LLVM_RELEASE}.tar.gz
fi

_fetch_source_tar "$LLVM_SRC_URL" "$LLVM_SHA256" "$LLVM_SRC"

_pushd "$LLVM_SRC"

for f in $(echo "$PROJECT"/llvm-$LLVM_RELEASE-*.patch | sort); do
  [ -e "$f" ] || _err "no patches found at $PROJECT/llvm-$LLVM_RELEASE-*.patch"
  [ -f "$f" ] || _err "$f is not a file"
  patch -p1 < "$f"
done
