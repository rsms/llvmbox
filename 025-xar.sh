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

CFLAGS=(
  "${STAGE2_CFLAGS[@]}" \
  -Wno-deprecated-declarations \
  -I$ZLIB_STAGE2/include \
  -I$OPENSSL_STAGE2/include \
)
LDFLAGS=(
  "${STAGE2_LDFLAGS[@]}" \
  -L$ZLIB_STAGE2/lib \
  -L$OPENSSL_STAGE2/lib \
)

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
RANLIB=$STAGE2_RANLIB \
CFLAGS="${CFLAGS[@]}" \
CPPFLAGS="${CFLAGS[@]}" \
LDFLAGS="${LDFLAGS[@]}" \
./configure \
  --prefix= \
  --enable-static \
  --disable-shared \
  --with-lzma="$XC_STAGE2" \
  --with-xml2-config=$LIBXML2_STAGE2/bin/xml2-config \
  --without-bzip2

make -j$NCPU lib_static

mkdir -p "$XAR_STAGE2/lib" "$XAR_STAGE2/include/xar"
install -vm 0644 include/xar.h "$XAR_STAGE2/include/xar/xar.h"
install -vm 0644 lib/libxar.a "$XAR_STAGE2/lib/libxar.a"

# _popd
# rm -rf "$XAR_SRC"
