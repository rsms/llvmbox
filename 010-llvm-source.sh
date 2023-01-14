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
