#!/bin/bash
# libxml2 depends on zlib and xc
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz \
  $LIBXML2_SHA256 "$LIBXML2_SRC"

_pushd "$LIBXML2_SRC"

rm -f python/setup.py          # setup.py is generated
rm -f test/icu_parse_test.xml  # we don't build libxml2 with icu

# note: need to use --prefix instead of DESTDIR during install
# for xml2-config to function properly
CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --disable-dependency-tracking \
  --without-catalog \
  --without-debug \
  --without-ftp \
  --without-http \
  --without-html \
  --without-iconv \
  --without-history \
  --without-legacy \
  --without-python \
  --without-readline \
  --without-modules \
  --without-lzma \
  --with-zlib="$ZLIB_STAGE2"

make -j$NCPU

# install
rm -rf "$LIBXML2_STAGE2"
mkdir -p "$LIBXML2_STAGE2"
make DESTDIR="$LIBXML2_STAGE2" install # don't use -j here

# rewrite bin/xml2-config to be relative to its install location
cp "$LIBXML2_STAGE2/bin/xml2-config" xml2-config
sed -E -e \
  's/^prefix=.*/prefix="`cd "$(dirname "$0")\/.."; pwd`"/' \
  xml2-config > "$LIBXML2_STAGE2/bin/xml2-config"

# remove unwanted programs
# (can't figure out how to disable building and/or installing these)
rm -f "$LIBXML2_STAGE2/bin/xmlcatalog" "$LIBXML2_STAGE2/bin/xmllint"

# remove libtool file
rm -f "$LIBXML2_STAGE2/lib/libxml2.la"

# # remove cmake and pkgconfig dirs
# rm -rf "$LIBXML2_STAGE2/lib/cmake" "$LIBXML2_STAGE2/lib/pkgconfig"

_popd
rm -rf "$LIBXML2_SRC"
