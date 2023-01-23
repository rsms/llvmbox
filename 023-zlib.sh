#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

cat << _END_
TARGET                   $TARGET
TARGET_ARCH              $TARGET_ARCH
TARGET_SYS               $TARGET_SYS
TARGET_SYS_VERSION       $TARGET_SYS_VERSION
TARGET_SYS_MINVERSION    $TARGET_SYS_MINVERSION
TARGET_SYS               $TARGET_SYS
TARGET_TRIPLE            $TARGET_TRIPLE
TARGET_CMAKE_SYSTEM_NAME $TARGET_CMAKE_SYSTEM_NAME
_END_
exit

_fetch_source_tar \
  https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_SHA256" "$ZLIB_SRC"

_pushd "$ZLIB_SRC"

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
CFLAGS="${STAGE2_CFLAGS[@]} -Wno-deprecated-non-prototype" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
  ./configure --static --prefix=

make -j$(nproc)
echo "——————————————————— check ———————————————————"
make -j$(nproc) check
echo "——————————————————— install ———————————————————"
make DESTDIR="$LLVMBOX_SYSROOT" -j$(nproc) install

_popd
rm -rf "$ZLIB_SRC"
