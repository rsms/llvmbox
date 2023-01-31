#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="${DESTDIR:-$LLVMBOX_DESTDIR}"
CREATE_TAR=true

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
usage: $0 [options]
options:
  --no-tar    Don't create .tar.xz archive
  -h, --help  Print help on stdout and exit
EOF
    exit ;;
  --no-tar) CREATE_TAR=false; shift ;;
  -*) _err "Unknown option $1" ;;
  *)  _err "Unexpected argument $1" ;;
esac; done

rm -rf "$DESTDIR"
mkdir -p "$DESTDIR/lib"
DESTDIR="`cd "$DESTDIR"; pwd`"

# only include toolchain, no llvm libs or headers
_copyinto "$LLVM_STAGE2/bin/"       "$DESTDIR/bin/"
_copyinto "$LLVM_STAGE2/share/"     "$DESTDIR/share/"
_copyinto "$LLVM_STAGE2/lib/clang/" "$DESTDIR/lib/clang/"

# remove llvm-config
rm -f "$DESTDIR/bin/llvm-config"
# # create empty files to satisfy llvm-config
# for f in "$LLVM_STAGE2"/lib/lib*.a; do
#   touch -r "$f" "$DESTDIR/lib/$(basename "$f")"
#   # ln -s "../dev/lib/$(basename "$f")" "$DESTDIR/lib/$(basename "$f")"
# done

_merge_libs() { # <targetlib> <srclib> ...
  # see https://llvm.org/docs/CommandGuide/llvm-ar.html
  echo "merge $# libs into $(_relpath "$1")"
  pushd "$(dirname "$1")" >/dev/null
  local tmpfile="$BUILD_DIR/$(basename "$1").merge.a"
  local script="$BUILD_DIR/$(basename "$1").merge.mri"
  rm -f "$tmpfile"
  echo "CREATE $tmpfile" > "$script"
  # echo "CREATETHIN $tmpfile" > "$script"
  for f in "$@"; do
    echo "ADDLIB $(basename "$f")" >> "$script"
  done
  echo "SAVE" >> "$script"
  echo "END" >> "$script"
  "$STAGE2_AR" -M < "$script"
  "$STAGE2_RANLIB" "$tmpfile"
  rm "$@" "$script"
  mv "$tmpfile" "$1"
  popd >/dev/null
}

# copy sysroot (which includes libc) and copy libc++
DEST_SYSROOT="$DESTDIR/sysroot"
mkdir -p "$DEST_SYSROOT"
for src in \
  "$LLVMBOX_SYSROOT" \
  "$LIBCXX_STAGE2" \
;do
  _copyinto "$src/" "$DEST_SYSROOT/"
done

# merge libc++abi.a -> libc++.a
_merge_libs "$DEST_SYSROOT/lib/libc++.a" "$DEST_SYSROOT/lib/libc++abi.a"

# merge lib-lto/libc++abi.a + lib-lto/libc++.a -> lib/libc++lto.a
if $LLVMBOX_ENABLE_LTO; then
  _merge_libs "$DEST_SYSROOT/lib-lto/libc++.a" "$DEST_SYSROOT/lib-lto/libc++abi.a"
elif [ -d "$DEST_SYSROOT/lib-lto" ]; then
  # sanity check
  _err "installed lib-lto at \$DESTDIR/sysroot/\$TARGET/lib-lto even though LLVMBOX_ENABLE_LTO=false"
fi

# remove unwanted dirs from deps
rm -rf "$DEST_SYSROOT/lib/cmake" "$DEST_SYSROOT/lib/pkgconfig"

# clang's darwin driver seems to not respect our C_INCLUDE_DIRS but looks for
# <sysroot>/usr/{include,lib}
if [ "$TARGET_SYS" = macos ]; then
  mkdir -pv "$DEST_SYSROOT/usr"
  _symlink "$DEST_SYSROOT/usr/include" ../include
  _symlink "$DEST_SYSROOT/usr/lib" ../lib
fi

# create symlink for development
if [ "$(dirname "$DESTDIR")" = "$OUT_DIR" ]; then
  _symlink "$OUT_DIR/llvmbox" "$(basename "$DESTDIR")"
fi

# create .tar.xz archive out of the result
if $CREATE_TAR; then
  echo "creating $(_relpath "$DESTDIR.tar.xz")"
  _create_tar_xz_from_dir "$DESTDIR" "$DESTDIR.tar.xz"
fi
