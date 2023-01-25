#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

rm -rf "$LLVMBOX_DESTDIR"
mkdir -p "$LLVMBOX_DESTDIR"

_copyinto() {
  echo "rsync $1 -> $(_relpath "$2")"
  rsync -a --exclude "*.DS_Store" "$1" "$2"
}

for src in \
  "$LLVM_STAGE2" \
;do
  _copyinto "$src/" "$LLVMBOX_DESTDIR/"
done

mkdir -p "$LLVMBOX_DESTDIR/sysroot/$TARGET"
for src in \
  "$LLVMBOX_SYSROOT" \
  "$ZLIB_STAGE2" \
  "$ZSTD_STAGE2" \
  "$LIBXML2_STAGE2" \
  "$LIBCXX_STAGE2" \
;do
  _copyinto "$src/" "$LLVMBOX_DESTDIR/sysroot/$TARGET/"
done
ln -s "$TARGET" "$LLVMBOX_DESTDIR/sysroot/host"

# _copyinto "$SYSROOTS_DIR/lib/" "$LLVMBOX_DESTDIR/sysroot/lib/"
# _copyinto "$SYSROOTS_DIR/include/" "$LLVMBOX_DESTDIR/sysroot/include/"
# for dir in include lib; do
#   if [ -d "$LLVMBOX_DESTDIR/sysroot/$dir/$TARGET" ]; then
#     ln -vs "$TARGET" "$LLVMBOX_DESTDIR/sysroot/$dir/llvm-native"
#   else
#     mkdir -v "$LLVMBOX_DESTDIR/sysroot/$dir/llvm-native"
#   fi
# done
