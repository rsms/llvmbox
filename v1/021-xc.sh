#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

# xar DEPENDS_ON xc

_fetch_source_tar https://tukaani.org/xz/xz-$XC_VERSION.tar.xz $XC_SHA256 "$XC_SRC"

_pushd "$XC_SRC"

CC=$HOST_CC \
LD=$HOST_LD \
CFLAGS="${TARGET_CFLAGS[@]}" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
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
LD_LIBRARY_PATH="$PWD/src/liblzma/.libs" make check

rm -rf "$XC_DESTDIR"
mkdir -p "$XC_DESTDIR"
make DESTDIR="$XC_DESTDIR" install
rm -rf "$XC_DESTDIR/bin"

_popd
rm -rf "$XC_SRC"
echo "$XC_VERSION" > "$XC_DESTDIR/version"
