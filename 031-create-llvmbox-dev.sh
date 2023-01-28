#!/bin/bash
#
# llvmbox-dev contains a complete toolchain, libs and headers for llvm, clang and lld.
# It llows creating programs using llvm libs and even your own clang or lld.
#
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="$LLVMBOX_DESTDIR_DEV" \
exec bash "$(dirname "$0")/030-create-llvmbox.sh" --include-dev "$@"

exit 1




DESTDIR="$LLVMBOX_DESTDIR_DEV"
CREATE_TAR=true
CREATE_LLVMBOXDIR=true

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
usage: $0 [options]
options:
  --no-tar         Don't create .tar.xz archive
  --no-llvmboxdir  Don't create merged llvbox dir for testing
  -h, --help       Print help on stdout and exit
<prefix>
  If set, only run scripts with this prefix. If empty or not set, all scripts
  are run. Example: "02"
EOF
    exit ;;
  --no-tar)        CREATE_TAR=false; shift ;;
  --no-llvmboxdir) CREATE_LLVMBOXDIR=false; shift ;;
  -*) _err "Unknown option $1" ;;
  *)  _err "Unexpected argument $1" ;;
esac; done


rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"

for src in \
  "$LLVM_STAGE2" \
  "$ZLIB_STAGE2" \
  "$ZSTD_STAGE2" \
  "$LIBXML2_STAGE2" \
;do
  _copyinto "$src/" "$DESTDIR/"
done

mkdir -p "$DESTDIR/sysroot/$TARGET"
rm -f "$DESTDIR/sysroot/host"
ln -sv "$TARGET" "$DESTDIR/sysroot/host"
for src in \
  "$LLVMBOX_SYSROOT" \
  "$LIBCXX_STAGE2" \
;do
  _copyinto "$src/" "$DESTDIR/sysroot/$TARGET/"
done

# _copyinto "$LLVM_STAGE2/include/" "$DESTDIR/include/"
# _copyinto --exclude "*/lib/clang/*" "$LLVM_STAGE2/lib/" "$DESTDIR/lib/"
# for src in \
#   "$ZLIB_STAGE2" \
#   "$ZSTD_STAGE2" \
#   "$LIBXML2_STAGE2" \
# ;do
#   _copyinto "$src/include/" "$DESTDIR/include/"
#   _copyinto "$src/lib/"     "$DESTDIR/lib/"
# done

# merge libc++abi.a into libc++.a
echo "merge sysroot/TARGET/ libc++abi.a + libc++.a => libc++.a"
_pushd "$DESTDIR/sysroot/$TARGET"
cat << END | "$STAGE2_AR" -M -
create lib/libc++_all.a
addlib lib/libc++.a
addlib lib/libc++abi.a
save
end
END
mv lib/libc++_all.a lib/libc++.a
"$STAGE2_RANLIB" lib/libc++.a
_popd

# clang's darwin driver seems to not respect our C_INCLUDE_DIRS but looks for
# <sysroot>/usr/{include,lib}
if [ "$TARGET_SYS" = macos ]; then
  mkdir -pv "$LLVMBOX_DESTDIR/sysroot/$TARGET/usr"
  ln -sv ../include "$LLVMBOX_DESTDIR/sysroot/$TARGET/usr/include"
  ln -sv ../lib "$LLVMBOX_DESTDIR/sysroot/$TARGET/usr/lib"
fi

# create .tar.xz archive out of the result
if $CREATE_TAR; then
  echo "creating $(_relpath "$DESTDIR.tar.xz")"
  _create_tar_xz_from_dir "$DESTDIR" "$DESTDIR.tar.xz"
fi

echo "creating symlink $(_relpath "$OUT_DIR/llvmbox") -> $(_relpath "$DESTDIR")"
rm -f "$(basename "$DESTDIR")" "$OUT_DIR/llvmbox"

# # create merged dir for tests
# if $CREATE_LLVMBOXDIR; then
#   echo "creating merged dir $(_relpath "$OUT_DIR/llvmbox")"
#   rm -rf "$OUT_DIR/llvmbox"
#   mkdir -p "$OUT_DIR/llvmbox"
#   _copyinto "$LLVMBOX_DESTDIR/" "$OUT_DIR/llvmbox/"
#   _copyinto "$LLVMBOX_DESTDIR_DEV/" "$OUT_DIR/llvmbox/"
# fi
