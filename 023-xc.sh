#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

# xar DEPENDS_ON xc

_fetch_source_tar https://tukaani.org/xz/xz-$XC_VERSION.tar.xz "$XC_SHA256" "$XC_SRC"

_pushd "$XC_SRC"

CC=$HOST_STAGE2_CC \
LD=$HOST_STAGE2_LD \
AR=$HOST_STAGE2_AR \
./configure \
  --prefix= \
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

make -j$(nproc)
LD_LIBRARY_PATH="$PWD/src/liblzma/.libs" make -j$(nproc) check
make DESTDIR="$LLVMBOX_SYSROOT" -j$(nproc) install

_popd
rm -rf "$XC_SRC"
