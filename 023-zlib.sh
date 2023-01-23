#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
CFLAGS="${STAGE2_CFLAGS[@]} -Wno-deprecated-non-prototype" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
  ./configure --static --prefix=

make -j$NCPU
echo "——————————————————— check ———————————————————"
make -j$NCPU check
echo "——————————————————— install ———————————————————"
make DESTDIR="$LLVMBOX_SYSROOT" -j$NCPU install

_popd
rm -rf "$ZLIB_SRC"
