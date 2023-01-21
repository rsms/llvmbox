#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
  $ZSTD_SHA256 "$ZSTD_SRC"

_pushd "$ZSTD_SRC"

ZSTD_DESTDIR=$BUILD_DIR/zstd-host

patch -p0 < "$PROJECT/zstd-001-disable-shlib.patch"

CFLAGS="-O2 -DBACKTRACE_ENABLE=0 -flto=auto -ffat-lto-objects" \
CXXFLAGS="-O2 -DBACKTRACE_ENABLE=0 -flto=auto -ffat-lto-objects" \
make HAVE_PTHREAD=1 ZSTD_LIB_MINIFY=1 prefix= -j$(nproc) lib-mt

rm -rf "$ZSTD_DESTDIR"
mkdir -p "$ZSTD_DESTDIR"/{lib,include}
cp -va lib/zstd.h "$ZSTD_DESTDIR"/include/zstd.h
cp -va lib/libzstd.a "$ZSTD_DESTDIR"/lib/libzstd.a

_popd
rm -rf "$ZSTD_SRC"
