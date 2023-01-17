#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

_fetch_source_tar \
  https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
  $ZSTD_SHA256 "$ZSTD_SRC"

_pushd "$ZSTD_SRC"

CC=$HOST_CC \
LD=$HOST_LD \
CFLAGS="${TARGET_CFLAGS[@]} -O2" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
make ZSTD_LIB_MINIFY=1 prefix= -j$(nproc) lib-mt

rm -rf "$ZSTD_DESTDIR"
mkdir -p "$ZSTD_DESTDIR"/{lib,include}
cp -va lib/zstd.h "$ZSTD_DESTDIR"/include/zstd.h
cp -va lib/libzstd.a "$ZSTD_DESTDIR"/lib/libzstd.a

echo "$ZSTD_VERSION" > "$ZSTD_DESTDIR/version"
