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
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --disable-dependency-tracking \
  --without-catalog \
  --without-debug \
  --without-docbook \
  --without-ftp \
  --without-http \
  --without-html \
  --without-html-dir \
  --without-html-subdir \
  --without-iconv \
  --without-history \
  --without-legacy \
  --without-python \
  --without-readline \
  --without-modules \
  --with-lzma="$LLVMBOX_SYSROOT" \
  --with-zlib="$LLVMBOX_SYSROOT" \

make -j$(nproc)
make DESTDIR="$LLVMBOX_SYSROOT" -j$(nproc) install

# rewrite bin/xml2-config to be relative to its install location
cp "$LLVMBOX_SYSROOT/bin/xml2-config" xml2-config
sed -E -e \
  's/^prefix=.*/prefix="`cd "$(dirname "$0")\/.."; pwd`"/' \
  xml2-config > "$LLVMBOX_SYSROOT/bin/xml2-config"

# remove unwanted programs
# (can't figure out how to disable building and/or installing these)
rm -f "$LLVMBOX_SYSROOT/bin/xmlcatalog" "$LLVMBOX_SYSROOT/bin/xmllint"

_popd
rm -rf "$LIBXML2_SRC"
