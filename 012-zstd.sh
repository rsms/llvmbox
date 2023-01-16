#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
  $ZSTD_SHA256 "$ZSTD_SRC"

_pushd "$ZSTD_SRC"

if [ "$HOST_SYS" = "Darwin" ]; then
  CFLAGS="$CFLAGS -mmacosx-version-min=10.10"
  LDFLAGS="$LDFLAGS -mmacosx-version-min=10.10"
fi

CFLAGS="$CFLAGS -O2" \
LDFLAGS="$LDFLAGS" \
make ZSTD_LIB_MINIFY=1 prefix= -j$(nproc) lib-mt

rm -rf "$ZSTD_DESTDIR"
mkdir -p "$ZSTD_DESTDIR"/{lib,include}
cp -va lib/zstd.h "$ZSTD_DESTDIR"/include/zstd.h
cp -va lib/libzstd.a "$ZSTD_DESTDIR"/lib/libzstd.a

echo "$ZSTD_VERSION" > "$ZSTD_DESTDIR/version"
