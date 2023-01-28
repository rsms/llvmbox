#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="${DESTDIR:-$LLVMBOX_DESTDIR}"
CREATE_TAR=true
INCLUDE_DEV=false

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
usage: $0 [options]
options:
  --include-dev  Include llvm libs and headers
  --no-tar       Don't create .tar.xz archive
  -h, --help     Print help on stdout and exit
EOF
    exit ;;
  --no-tar)         CREATE_TAR=false; shift ;;
  --include-dev)    INCLUDE_DEV=true; shift ;;
  -*) _err "Unknown option $1" ;;
  *)  _err "Unexpected argument $1" ;;
esac; done

rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"/{,lib}
DESTDIR="`cd "$DESTDIR"; pwd`"

if $INCLUDE_DEV; then
  # include everything from llvm-stage2 and dependencies needed to link llvm libs
  _copyinto "$LLVM_STAGE2/" "$DESTDIR/"
  for src in \
    "$ZLIB_STAGE2" \
    "$ZSTD_STAGE2" \
    "$LIBXML2_STAGE2" \
  ;do
    _copyinto "$src/include/" "$DESTDIR/include/"
    _copyinto "$src/lib/"     "$DESTDIR/lib/"
  done
else
  # only include toolchain, no llvm libs or headers
  _copyinto "$LLVM_STAGE2/bin/"       "$DESTDIR/bin/"
  _copyinto "$LLVM_STAGE2/share/"     "$DESTDIR/share/"
  _copyinto "$LLVM_STAGE2/lib/clang/" "$DESTDIR/lib/clang/"
fi

# copy sysroot (which includes libc) and copy libc++
mkdir -p "$DESTDIR/sysroot/$TARGET"
rm -f "$DESTDIR/sysroot/host"
_symlink "$DESTDIR/sysroot/host" "$TARGET"
for src in \
  "$LLVMBOX_SYSROOT" \
  "$LIBCXX_STAGE2" \
;do
  _copyinto "$src/" "$DESTDIR/sysroot/$TARGET/"
done

# merge libc++abi.a into libc++.a
echo "merge sysroot/TARGET/ libc++abi.a + libc++.a => libc++.a"
_pushd "$DESTDIR/sysroot/$TARGET/lib"
cat << END | "$STAGE2_AR" -M -
create libc++_all.a
addlib libc++.a
addlib libc++abi.a
save
end
END
mv libc++_all.a libc++.a
"$STAGE2_RANLIB" libc++.a

# clang's darwin driver seems to not respect our C_INCLUDE_DIRS but looks for
# <sysroot>/usr/{include,lib}
if [ "$TARGET_SYS" = macos ]; then
  mkdir -pv "$DESTDIR/sysroot/$TARGET/usr"
  _symlink "$DESTDIR/sysroot/$TARGET/usr/include" ../include
  _symlink "$DESTDIR/sysroot/$TARGET/usr/lib" ../lib
fi

# create .tar.xz archive out of the result
if $CREATE_TAR; then
  echo "creating $(_relpath "$DESTDIR.tar.xz")"
  _create_tar_xz_from_dir "$DESTDIR" "$DESTDIR.tar.xz"
fi

if $INCLUDE_DEV && [ "$(dirname "$DESTDIR")" = "$OUT_DIR" ]; then
  _symlink "$OUT_DIR/llvmbox" "$(basename "$DESTDIR")"
fi
