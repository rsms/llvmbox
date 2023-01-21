#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

_fetch_source_tar \
  https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
  $ZSTD_SHA256 "$ZSTD_SRC"

_pushd "$ZSTD_SRC"

patch -p0 < "$PROJECT/zstd-001-disable-shlib.patch"

CC=$HOST_CC \
LD=$HOST_LD \
CFLAGS="${TARGET_CFLAGS[@]} -O2" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
make ZSTD_LIB_MINIFY=1 prefix= -j$(nproc) lib-mt

rm -rf "$ZSTD_DIST"
mkdir -p "$ZSTD_DIST"/{lib,include}
cp -va lib/zstd.h "$ZSTD_DIST"/include/zstd.h
cp -va lib/libzstd.a "$ZSTD_DIST"/lib/libzstd.a

echo "$ZSTD_VERSION" > "$ZSTD_DIST/version"
