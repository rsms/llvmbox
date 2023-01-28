#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = macos ] || { echo "$0: skipping (not targeting macos)"; exit; }

OUT_LIBLLVM=$LLVMBOX_DESTDIR/lib/libllvm.a
MRIFILE=$BUILD_DIR/$(basename "$OUT_LIBLLVM").mri

_pushd "$LLVMBOX_DESTDIR/lib"
mkdir -p "$(dirname "$MRIFILE")"
echo "create $OUT_LIBLLVM" > "$MRIFILE"
for f in lib*.a; do
  echo "addlib $f" >> "$MRIFILE"
done
echo "save" >> "$MRIFILE"
echo "end" >> "$MRIFILE"

cat "$MRIFILE"

"$LLVMBOX_DESTDIR/bin/llvm-ar" -M < "$MRIFILE"
"$LLVMBOX_DESTDIR/bin/llvm-ranlib" "$OUT_LIBLLVM"
