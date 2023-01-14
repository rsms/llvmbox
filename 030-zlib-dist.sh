#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_CHECKSUM" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

CC=$HOST_CC \
LD=$HOST_LD \
CFLAGS="${TARGET_CFLAGS[@]} -w" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
./configure --static --prefix=

make -j$(nproc)
make check

rm -rf "$ZLIB_DIST"
mkdir -p "$ZLIB_DIST"
make DESTDIR="$ZLIB_DIST" install

echo "$ZLIB_VERSION" > "$ZLIB_DIST/version"
