#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="${DESTDIR:-$LLVMBOX_DESTDIR}"
CROSS_DESTDIR="$DESTDIR/cross"

rm -rf "$CROSS_DESTDIR"
mkdir -p "$CROSS_DESTDIR"

_copy "$SYSROOTS_DIR/include" "$CROSS_DESTDIR/include"

echo make -C "$PROJECT/llvmbox-tools"
     make -C "$PROJECT/llvmbox-tools" -j$NCPU

"$PROJECT/llvmbox-tools/dedup-target-files" "$CROSS_DESTDIR/include"

# remove "-suffix" dirs by merging with corresponding non-suffix dirs.
# e.g. "any-linux-libc" -> "any-linux"
for suffix in "-libc"; do
  for f in "$CROSS_DESTDIR/include"/*${suffix}; do
    [ -d "$f" ] || continue
    dstdir=${f%*${suffix}}
    echo "merge $(_relpath "$f") -> $(_relpath "$dstdir")"
    mkdir -p "$dstdir"
    "$PROJECT/llvmbox-tools/llvmbox-cpmerge" -v "$f" "$dstdir"
    rm -rf "$f"
  done
done

# FIXME: There's a bug in dedup-target-files where it doesn't always succeed in
# removing empty directories, so we run a second pass here to catch any of those.
# In addition, we run this at the end, on the whole CROSS_DESTDIR, to clean up
# any accidental empty dirs.
echo "removing any empty directories"
find "$CROSS_DESTDIR" -empty -type d -delete -print

# copy libc sources
mkdir -p "$CROSS_DESTDIR/libc"
_copy "$SYSROOTS_DIR/libc/musl" "$CROSS_DESTDIR/libc/musl"

# Some musl source files will do: #include "../../include/features.h"
# so setup a symlink to the arch-less include dir.
rm -f "$CROSS_DESTDIR/libc/musl/include"
ln -s ../../include/any-linux "$CROSS_DESTDIR/libc/musl/include"

# install llvmbox-mksysroot
mkdir -p "$DESTDIR/bin"
install -v -m755 "$PROJECT/llvmbox-tools/llvmbox-mksysroot" "$DESTDIR/bin"
