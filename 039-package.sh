#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVMBOX_DESTDIR=${LLVMBOX_DESTDIR:-$OUT_DIR/llvmbox-$LLVM_RELEASE-$TARGET}

rm -rf "$LLVMBOX_DESTDIR"
mkdir -p "$LLVMBOX_DESTDIR"

_copyinto() {
  echo "rsync $1 -> $(_relpath "$2")"
  rsync -a --exclude "*.DS_Store" "$1" "$2"
}

for src in \
  "$LLVM_STAGE2" \
  "$ZLIB_STAGE2" \
  "$ZSTD_STAGE2" \
  "$LIBXML2_STAGE2" \
;do
  _copyinto "$src/" "$LLVMBOX_DESTDIR/"
done

mkdir -p "$LLVMBOX_DESTDIR/sysroot/$TARGET"
for src in \
  "$LLVMBOX_SYSROOT" \
  "$LIBCXX_STAGE2" \
;do
  _copyinto "$src/" "$LLVMBOX_DESTDIR/sysroot/$TARGET/"
done

# _copyinto "$SYSROOTS_DIR/lib/" "$LLVMBOX_DESTDIR/sysroot/lib/"
# _copyinto "$SYSROOTS_DIR/include/" "$LLVMBOX_DESTDIR/sysroot/include/"
# for dir in include lib; do
#   if [ -d "$LLVMBOX_DESTDIR/sysroot/$dir/$TARGET" ]; then
#     ln -vs "$TARGET" "$LLVMBOX_DESTDIR/sysroot/$dir/llvm-native"
#   else
#     mkdir -v "$LLVMBOX_DESTDIR/sysroot/$dir/llvm-native"
#   fi
# done

# merge libc++abi.a into libc++.a
echo "merge sysroot/TARGET/ libc++abi.a + libc++.a => libc++.a"
_pushd "$LLVMBOX_DESTDIR/sysroot/$TARGET"
cat << END | "$STAGE2_AR" -M -
create lib/libc++_all.a
addlib lib/libc++.a
addlib lib/libc++abi.a
save
end
END
mv lib/libc++_all.a lib/libc++.a


TARFILE="$LLVMBOX_DESTDIR.tar.xz"
echo "creating $(_relpath "$TARFILE")"
XZ_OPT='-T0' tar \
  -C "$(dirname "$LLVMBOX_DESTDIR")" \
  -cJpf "$TARFILE" \
  "$(basename "$LLVMBOX_DESTDIR")"
