#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

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

rm -rf "$XAR_SRC"
mkdir -p "$(dirname "$XAR_SRC")"
cp -a "$PROJECT/xar" "$XAR_SRC"
_pushd "$XAR_SRC"

# # fix for -lfts on macos
# if [ "$TARGET_SYS" = macos ]; then
#   mkdir libtmp
#   ln -s "$LLVMBOX_SYSROOT/lib/libSystem.tbd" libtmp/libfts.tbd
# fi

# # Workaround for a bug in xar's build process which generates incorrect paths to
# # libxml2 headers in xar/src/xar.d.
# # Instead of e.g. /tmp/libxml2-TARGET/include/libxml2/libxml/xmlreader.h
# # it writes e.g. /tmp/libxml2/include/libxml2/libxml/xmlreader.h
# # The bug manifests itself like this during a build:
# #   make: *** No rule to make target `/tmp/libxml2/include/libxml2/libxml/xmlreader.h',
# #   needed by `src/xar.o'.  Stop.
# #
# rm -f "$(dirname "$LIBXML2_DESTDIR")/libxml2"
# ln -s "$(basename "$LIBXML2_DESTDIR")" "$(dirname "$LIBXML2_DESTDIR")/libxml2"


CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
RANLIB=$STAGE2_RANLIB \
CFLAGS="${STAGE2_CFLAGS[@]}" \
CPPFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --with-lzma="$LLVMBOX_SYSROOT" \
  --with-xml2-config=$LLVMBOX_SYSROOT/bin/xml2-config \
  --without-bzip2

make -j$(nproc)

rm -rf "$LLVMBOX_SYSROOT"
mkdir -p "$LLVMBOX_SYSROOT"
make DESTDIR="$LLVMBOX_SYSROOT" install
# rm -rf "$LLVMBOX_SYSROOT/bin" "$LLVMBOX_SYSROOT/share"

_popd
rm -rf "$XAR_SRC"
