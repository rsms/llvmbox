#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="${DESTDIR:-$LLVMBOX_DESTDIR}"

rm -rf "$DESTDIR/targets"
mkdir -p "$(dirname "$DESTDIR/targets")"

_copy "$SYSROOTS_DIR/include" "$DESTDIR/targets"

echo make -C "$PROJECT/llvmbox-tools"
     make -C "$PROJECT/llvmbox-tools" -j$NCPU

"$PROJECT/llvmbox-tools/dedup-target-files" "$DESTDIR/targets"

# remove "-suffix" dirs by merging with corresponding non-suffix dirs.
# e.g. "any-linux-libc" -> "any-linux"
for suffix in "-libc"; do
  for f in "$DESTDIR/targets"/*${suffix}; do
    [ -d "$f" ] || continue
    dstdir=${f%*${suffix}}
    echo "merge $(_relpath "$f") -> $(_relpath "$dstdir")"
    mkdir -p "$dstdir"
    "$PROJECT/llvmbox-tools/llvmbox-cpmerge" -v "$f" "$dstdir"
    rm -rf "$f"
  done
done

# rename targets/{target} -> targets/{target}/include
for d in "$DESTDIR/targets"/*; do
  [ -d "$d" ] || continue
  mv "$d" "$d.tmp"
  mkdir "$d"
  mv "$d.tmp" "$d/include"
done

# FIXME: There's a bug in dedup-target-files where it doesn't always succeed in
# removing empty directories, so we run a second pass here to catch any of those.
# In addition, we run this at the end, on the whole HEADERS_DESTDIR, to clean up
# any accidental empty dirs.
find "$(_relpath "$DESTDIR/targets")" \
  -empty -type d -delete -exec echo "remove empty dir {}" \;

mkdir -p "$DESTDIR/src"

# copy libc sources
rm -rf "$DESTDIR/src/musl"
_copy "$SYSROOTS_DIR/libc/musl" "$DESTDIR/src/musl"
# Some musl source files will do: #include "../../include/features.h"
# so setup a symlink to the arch-less include dir.
ln -s ../../targets/any-linux/include "$DESTDIR/src/musl/include"

# copy compiler-rt sources
rm -rf "$DESTDIR/src/builtins"
_copy "$SYSROOTS_DIR/compiler-rt/builtins" "$DESTDIR/src/builtins"

# install llvmbox-mksysroot
mkdir -p "$DESTDIR/bin"
install -v -m755 "$PROJECT/llvmbox-tools/llvmbox-mksysroot" "$DESTDIR/bin"

