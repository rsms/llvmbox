#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

CC=$HOST_STAGE2_CC \
LD=$HOST_STAGE2_LD \
AR=$HOST_STAGE2_AR \
CFLAGS="-Wno-deprecated-non-prototype" \
  ./configure --static --prefix=

make -j$(nproc)
echo "——————————————————— check ———————————————————"
make -j$(nproc) check
echo "——————————————————— install ———————————————————"
make DESTDIR="$LLVMBOX_SYSROOT" -j$(nproc) install

_popd
rm -rf "$ZLIB_SRC"
