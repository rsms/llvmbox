#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

# note: LDFLAGS -static needed for "make check" (link test programs)
CC="$STAGE1_CC" \
LD="$STAGE1_LD" \
AR="$STAGE1_AR" \
CFLAGS="$STAGE1_CFLAGS -fPIC" \
LDFLAGS="$STAGE1_LDFLAGS" \
  ./configure --static --prefix=

make -j$NCPU
make check

rm -rf "$ZLIB_STAGE1"
mkdir -p "$ZLIB_STAGE1"
make DESTDIR="$ZLIB_STAGE1" install
