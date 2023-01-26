#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_pushd "$PROJECT"

# essentially a copy of STAGE2_CFLAGS & STAGE2_LDFLAGS
# TODO: use STAGE2_LDFLAGS & STAGE2_LDFLAGS
FLAGS=(
  --sysroot="$LLVMBOX_SYSROOT" -isystem"$LLVMBOX_SYSROOT/include" \
  -L"$LLVMBOX_SYSROOT/lib" \
  -nostdinc++ -I"$LIBCXX_STAGE2/include/c++/v1" \
  -nostdlib++ -L"$LIBCXX_STAGE2/lib" -lc++ -lc++abi -lunwind \
  "${STAGE2_LTO_CFLAGS[@]}" "${STAGE2_LTO_LDFLAGS[@]}" \
)
[ "$TARGET_SYS" = linux ] && FLAGS+=( -static )

for srcfile in \
  test/hello.cc \
  test/cxx-random-header-using-bug.cc \
;do
  prog="$OUT_DIR/${srcfile//\//.}"
  echo "build $srcfile -> $(_relpath "$prog")"
  "$LLVM_STAGE1/bin/clang++" "${FLAGS[@]}" $srcfile -o "$OUT_DIR/${srcfile//\//.}"
  "$prog" && echo "$(_relpath "$prog"): ok"
done
