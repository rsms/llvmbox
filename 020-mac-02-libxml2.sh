#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-mac.sh"

# xar     DEPENDS_ON libxml2
# libxml2 DEPENDS_ON zlib
# libxml2 DEPENDS_ON lzma/xc

_fetch_source_tar \
  https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz \
  $LIBXML2_SHA256 "$LIBXML2_SRC"

_pushd "$LIBXML2_SRC"

rm -f python/setup.py          # setup.py is generated
rm -f test/icu_parse_test.xml  # we don't build libxml2 with icu

# note: need to use --prefix instead of DESTDIR during install
# for xml2-config to function properly
./configure \
  "--prefix=$LIBXML2_DESTDIR" \
  --enable-static \
  --disable-shared \
  --disable-dependency-tracking \
  \
  --without-catalog      \
  --without-debug        \
  --without-docbook      \
  --without-ftp          \
  --without-http         \
  --without-html         \
  --without-html-dir     \
  --without-html-subdir  \
  --without-iconv        \
  --without-history      \
  --without-legacy       \
  --without-python       \
  --without-readline     \
  --without-modules      \
  "--with-lzma=$XC_DESTDIR" \
  "--with-zlib=$ZLIB_HOST" \

make -j$(nproc)

rm -rf "$LIBXML2_DESTDIR"
mkdir -p "$LIBXML2_DESTDIR"
make install

echo "$LIBXML2_VERSION" > "$LIBXML2_DESTDIR/version"
