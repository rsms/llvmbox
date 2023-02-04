#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  "$MUSL_SHA256" "$MUSL_SRC"

_pushd "$MUSL_SRC"

for arch in aarch64 arm i386 riscv64 x86_64; do
  DESTDIR=$SYSROOTS_DIR/include/$arch-linux-libc
  echo "make install-headers $arch -> $(_relpath "$DESTDIR")"
  rm -rf obj destdir
  make DESTDIR=destdir install-headers -j$NCPU ARCH=$arch prefix= >/dev/null
  rm -rf "$DESTDIR"
  mkdir -p "$(dirname "$DESTDIR")"
  mv destdir/include "$DESTDIR"
done

_popd
rm -rf "$MUSL_SRC"
