#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  $MUSL_SHA256 "$MUSL_SRC"

_pushd "$MUSL_SRC"

CC=$HOST_CC \
LD=$HOST_LD \
AR=$HOST_AR \
RANLIB=$HOST_RANLIB \
CFLAGS="${TARGET_CFLAGS[@]} -I$LINUX_HEADERS_DESTDIR/include" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
./configure --target=$TARGET --disable-shared --prefix="$MUSL_DESTDIR"

make -j$(nproc)

mkdir -p "$MUSL_DESTDIR"
make install
