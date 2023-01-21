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

make -j$(nproc)
make check

DESTDIR=$BUILD_DIR/stage1-zlib
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"
make DESTDIR="$DESTDIR" install
