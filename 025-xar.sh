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

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
RANLIB=$STAGE2_RANLIB \
CFLAGS="${STAGE2_CFLAGS[@]} -Wno-deprecated-declarations" \
CPPFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --with-lzma="$LLVMBOX_SYSROOT" \
  --with-xml2-config=$LLVMBOX_SYSROOT/bin/xml2-config \
  --without-bzip2

make -j$NCPU

mkdir -p out
make DESTDIR=out -j$NCPU install

mkdir -p "$LLVMBOX_SYSROOT/include/xar"
install -vm 0644 out/include/xar/xar.h "$LLVMBOX_SYSROOT/include/xar/xar.h"
install -vm 0644 out/lib/libxar.a "$LLVMBOX_SYSROOT/lib/libxar.a"

_popd
rm -rf "$XAR_SRC"
