#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

# dependency graph:
#   lld
#     xar
#       libxml2
#         zlib
#         xc
#       openssl
#       xc
#       zlib
#       musl-fts [linux]
#

TARGET_CFLAGS+=(
  -I"$ZLIB_DIST/include" \
  -I"$XC_DESTDIR/include" \
  -I"$OPENSSL_DESTDIR/include" \
  -I"$MUSLFTS_DESTDIR/include" \
)
TARGET_LDFLAGS+=(
  -L"$ZLIB_DIST/lib" \
  -L"$XC_DESTDIR/lib" \
  -L"$OPENSSL_DESTDIR/lib" \
  -L"$MUSLFTS_DESTDIR/lib" -lfts \
)


# Workaround for a bug in xar's build process which generates incorrect paths to
# libxml2 headers in xar/src/xar.d.
# Instead of e.g. /tmp/libxml2-TARGET/include/libxml2/libxml/xmlreader.h
# it writes e.g. /tmp/libxml2/include/libxml2/libxml/xmlreader.h
# The bug manifests itself like this during a build:
#   make: *** No rule to make target `/tmp/libxml2/include/libxml2/libxml/xmlreader.h',
#   needed by `src/xar.o'.  Stop.
#
rm -f "$(dirname "$LIBXML2_DESTDIR")/libxml2"
ln -s "$(basename "$LIBXML2_DESTDIR")" "$(dirname "$LIBXML2_DESTDIR")/libxml2"

rm -rf "$XAR_SRC"
mkdir -p "$(dirname "$XAR_SRC")"
cp -a "$PROJECT/xar" "$XAR_SRC"

_pushd "$XAR_SRC"

CC=$HOST_CC \
CXX=$HOST_CXX \
AR=$HOST_AR \
LD=$HOST_LD \
RANLIB=$HOST_RANLIB \
CFLAGS="${TARGET_CFLAGS[@]}" \
CPPFLAGS="${TARGET_CFLAGS[@]}" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
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

