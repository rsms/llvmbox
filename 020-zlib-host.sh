#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

if [ "$(cat "$ZLIB_HOST/version" 2>/dev/null)" == "$ZLIB_VERSION" ]; then
  echo "$ZLIB_HOST: up-to-date"
  exit
fi

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_CHECKSUM" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

echo "building zlib ... (${ZLIB_HOST##$PWD0/}.log)"
( # -fPIC needed on Linux
  CFLAGS=-fPIC \
    ./configure --static --prefix=
  make -j$(nproc)
  make check
  rm -rf "$ZLIB_HOST"
  mkdir -p "$ZLIB_HOST"
  make DESTDIR="$ZLIB_HOST" install
  echo "$ZLIB_VERSION" > "$ZLIB_HOST/version"
) > $ZLIB_HOST.log
