#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-mac.sh"

# dependency graph:
#   lld
#     xar
#       libxml2
#         zlib
#         xc
#       openssl
#       xc
#       zlib
#

_pushd "$XAR_SRC"

CFLAGS="-I$OPENSSL_DESTDIR/include -I$ZLIB_HOST/include -I$LIBXML2_DESTDIR/include" \
CPPFLAGS="-I$OPENSSL_DESTDIR/include -I$ZLIB_HOST/include -I$LIBXML2_DESTDIR/include" \
LDFLAGS="-L$OPENSSL_DESTDIR/lib -L$ZLIB_HOST/lib -L$LIBXML2_DESTDIR/lib" \
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --with-lzma="$XC_DESTDIR" \
  --with-xml2-config=$LIBXML2_DESTDIR/bin/xml2-config \
  --without-bzip2

make -j$(nproc)

rm -rf "$XAR_DESTDIR"
mkdir -p "$XAR_DESTDIR"
make DESTDIR="$XAR_DESTDIR" install
# rm -rf "$XAR_DESTDIR/bin" "$XAR_DESTDIR/share"

echo "$XAR_VERSION" > "$XAR_DESTDIR/version"
