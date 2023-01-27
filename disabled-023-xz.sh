#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

# xar DEPENDS_ON xz

_fetch_source_tar https://tukaani.org/xz/xz-$XZ_VERSION.tar.xz "$XZ_SHA256" "$XZ_SRC"

_pushd "$XZ_SRC"

CC="$STAGE2_CC" \
LD="$STAGE2_LD" \
AR="$STAGE2_AR" \
RANLIB="$STAGE2_RANLIB" \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
./configure \
  --prefix= \
  --with-sysroot="$LLVMBOX_SYSROOT" \
  --enable-static \
  --disable-shared \
  --disable-rpath \
  --disable-werror \
  --disable-doc \
  --disable-nls \
  --disable-dependency-tracking \
  --disable-xz \
  --disable-xzdec \
  --disable-lzmadec \
  --disable-lzmainfo \
  --disable-lzma-links \
  --disable-scripts \
  --disable-doc

make -j$NCPU
LD_LIBRARY_PATH="$PWD/src/liblzma/.libs" make -j$NCPU check

# make DESTDIR="$LLVMBOX_SYSROOT" -j$NCPU install
rm -rf "$XZ_STAGE2"
mkdir -p "$XZ_STAGE2"/{lib,include}
make DESTDIR="$XZ_STAGE2" -j$NCPU install

# remove libtool file which is just going to confuse libxml2
rm -fv "$XZ_STAGE2"/lib/*.la

_popd
rm -rf "$XZ_SRC"
