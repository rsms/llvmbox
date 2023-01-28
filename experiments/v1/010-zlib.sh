#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

if [ "$HOST_SYS" = "Darwin" ]; then
  CFLAGS="$CFLAGS -mmacosx-version-min=10.10"
  LDFLAGS="$LDFLAGS -mmacosx-version-min=10.10"
fi

CFLAGS="$CFLAGS -fPIC" \
LDFLAGS=$LDFLAGS \
  ./configure --static --prefix=

make -j$(nproc)
make check

rm -rf "$ZLIB_HOST"
mkdir -p "$ZLIB_HOST"
make DESTDIR="$ZLIB_HOST" install

echo "$ZLIB_VERSION" > "$ZLIB_HOST/version"
