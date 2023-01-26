#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

# xar DEPENDS_ON xc

_fetch_source_tar https://tukaani.org/xz/xz-$XC_VERSION.tar.xz "$XC_SHA256" "$XC_SRC"

_pushd "$XC_SRC"

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
rm -rf "$XC_STAGE2"
mkdir -p "$XC_STAGE2"/{lib,include}
make DESTDIR="$XC_STAGE2" -j$NCPU install

# remove libtool file which is just going to confuse libxml2
rm -fv "$XC_STAGE2"/lib/*.la

_popd
rm -rf "$XC_SRC"
