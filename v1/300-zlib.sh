#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"

LLVM_STAGE2=${LLVM_STAGE2:-$BUILD_DIR/llvm2}
ZLIB_DESTDIR=$BUILD_DIR/stage2-zlib

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_CHECKSUM" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

CC="$LLVM_STAGE2/bin/clang" \
LD="$LLVM_STAGE2/bin/clang" \
CFLAGS="-w" \
LDFLAGS="" \
./configure --static --prefix=

make -j$(nproc)
make check

rm -rf "$ZLIB_DESTDIR"
mkdir -p "$ZLIB_DESTDIR"
make DESTDIR="$ZLIB_DESTDIR" install
