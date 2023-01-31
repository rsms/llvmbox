#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

[ "$TARGET_SYS" != macos ] ||
  patch -p1 < "$PROJECT/patches/zlib-macos-ar.patch"

CC="$STAGE2_CC" \
LD="$STAGE2_LD" \
AR="$STAGE2_AR" \
RANLIB="$STAGE2_RANLIB" \
CFLAGS="${STAGE2_CFLAGS[@]} ${STAGE2_LTO_CFLAGS[@]} -Wno-deprecated-non-prototype" \
LDFLAGS="${STAGE2_LDFLAGS[@]} ${STAGE2_LTO_LDFLAGS[@]}" \
  ./configure --static --prefix=

echo "——————————————————— build ———————————————————"
make -j$NCPU

echo "——————————————————— check ———————————————————"
make -j$NCPU check

echo "——————————————————— install ———————————————————"
rm -rf "$ZLIB_STAGE2"
mkdir -p "$ZLIB_STAGE2"/{lib,include}
make DESTDIR="$ZLIB_STAGE2" -j$NCPU install

_popd
rm -rf "$ZLIB_SRC"
