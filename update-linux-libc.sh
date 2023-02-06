#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

SUPPORTED_ARCHS=( aarch64 arm i386 riscv64 x86_64 )

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  "$MUSL_SHA256" "$MUSL_SRC"

_pushd "$MUSL_SRC"

# headers
for arch in "${SUPPORTED_ARCHS[@]}"; do
  HEADERS_DESTDIR=$SYSROOTS_DIR/include/$arch-linux-libc
  echo "make install-headers $arch -> $(_relpath "$HEADERS_DESTDIR")"
  rm -rf obj destdir
  make DESTDIR=destdir install-headers -j$NCPU ARCH=$arch prefix= >/dev/null
  rm -rf "$HEADERS_DESTDIR"
  mkdir -p "$(dirname "$HEADERS_DESTDIR")"
  mv destdir/include "$HEADERS_DESTDIR"
done

# sources
SOURCE_DESTDIR="$SYSROOTS_DIR/libc/musl"
mkdir -p "$SOURCE_DESTDIR"
for dir in arch compat crt src; do
  rm -rf "$SOURCE_DESTDIR/$dir"
  _copy "$dir" "$SOURCE_DESTDIR/$dir"
done
_copy COPYRIGHT "$SOURCE_DESTDIR"
mkdir "$SOURCE_DESTDIR/ldso"
_copy ldso/dlstart.c "$SOURCE_DESTDIR/ldso"

# create version.h, needed by version.c (normally created by musl's makefile)
echo "generate $(_relpath "$SOURCE_DESTDIR/src/internal/version.h")"
echo "#define VERSION \"$MUSL_VERSION\"" > "$SOURCE_DESTDIR/src/internal/version.h"

# remove unused dirs
for arch_dir in "$SOURCE_DESTDIR"/arch/* "$SOURCE_DESTDIR"/crt/*; do
  [ -d "$arch_dir" ] || continue
  arch=$(basename "$arch_dir")
  [ "$arch" != generic ] || continue
  is_supported=
  for supported_arch in "${SUPPORTED_ARCHS[@]}"; do
    if [ "$arch" = "$supported_arch" ]; then
      is_supported=1
      break
    fi
  done
  if [ -z "$is_supported" ]; then
    echo "remove unused $(_relpath "$arch_dir")"
    rm -rf "$arch_dir"
  fi
done

_popd

# remove unused files
find "$(_relpath "$SOURCE_DESTDIR")" \
  -type f -name '*.mak' -or -name '*.in' -delete -exec echo "remove unused {}" \;

rm -rf "$MUSL_SRC"
