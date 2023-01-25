#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_pushd "$PROJECT"

for srcfile in \
  test/hello.cc \
  test/cxx-random-header-using-bug.cc \
;do
  prog="$OUT_DIR/${srcfile//\//.}"
  echo "build $srcfile -> $(_relpath "$prog")"
  "$LLVM_STAGE1/bin/clang++" \
    --sysroot="$LLVMBOX_SYSROOT" -isystem"$LLVMBOX_SYSROOT/include" \
    -L"$LLVMBOX_SYSROOT/lib" \
    -nostdinc++ -I"$LIBCXX_STAGE2/include/c++/v1" \
    -nostdlib++ -L"$LIBCXX_STAGE2/lib" -lc++ -lc++abi -lunwind \
    $srcfile -o "$OUT_DIR/${srcfile//\//.}"
  "$prog" && echo "$(_relpath "$prog"): ok"
done
