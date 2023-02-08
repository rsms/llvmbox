#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
# Note: This script can run on any posix system (host doesn't need to be linux)

SUPPORTED_ARCHS=( aarch64 arm i386 riscv64 x86_64 )

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  "$MUSL_SHA256" "$MUSL_SRC"

_pushd "$MUSL_SRC"

# copy headers
for arch in "${SUPPORTED_ARCHS[@]}"; do
  HEADERS_DESTDIR=$SYSROOTS_DIR/include/$arch-linux-libc
  echo "make install-headers $arch -> $(_relpath "$HEADERS_DESTDIR")"
  rm -rf obj destdir
  make DESTDIR=destdir install-headers -j$NCPU ARCH=$arch prefix= >/dev/null
  rm -rf "$HEADERS_DESTDIR"
  mkdir -p "$(dirname "$HEADERS_DESTDIR")"
  mv destdir/include "$HEADERS_DESTDIR"
done

# copy sources (from musl Makefile)
SOURCE_DESTDIR="$SYSROOTS_DIR/libc/musl"
for f in "$SOURCE_DESTDIR"/*; do [ -d "$f" ] && rm -rf "$f"; done
mkdir -p "$SOURCE_DESTDIR/arch"

for f in \
  $(find src -type f -name '*.h') \
  compat/time32/*.c \
  crt/*.c \
  ldso/*.c \
  src/*/*.c \
  src/malloc/mallocng/*.c \
;do
  [ -f "$f" ] || continue
  mkdir -p $(dirname "$SOURCE_DESTDIR/$f")
  cp $f "$SOURCE_DESTDIR/$f"
done &

for arch in "${SUPPORTED_ARCHS[@]}"; do
  for f in \
    crt/$arch/*.[csS] \
    ldso/$arch/*.[csS] \
    src/*/$arch/*.[csS] \
    src/malloc/mallocng/$arch/*.[csS] \
  ;do
    [ -f "$f" ] || continue
    mkdir -p $(dirname "$SOURCE_DESTDIR/$f")
    cp $f "$SOURCE_DESTDIR/$f"
  done &
  # internal headers
  [ -d "arch/$arch" ] &&
    _copy "arch/$arch" "$SOURCE_DESTDIR/arch/$arch"
done
_copy "arch/generic" "$SOURCE_DESTDIR/arch/generic" &
wait

# copy license statement
_copy COPYRIGHT "$SOURCE_DESTDIR"

# create version.h, needed by version.c (normally created by musl's makefile)
echo "generate $(_relpath "$SOURCE_DESTDIR/src/internal/version.h")"
echo "#define VERSION \"$MUSL_VERSION\"" > "$SOURCE_DESTDIR/src/internal/version.h"

_popd

# remove unused files
find "$(_relpath "$SOURCE_DESTDIR")" \
  -type f -name '*.mak' -or -name '*.in' -delete -exec echo "remove unused {}" \;

# remove empty directories
find "$(_relpath "$SOURCE_DESTDIR")" \
  -empty -type d -delete -exec echo "remove empty directory {}" \;

rm -rf "$MUSL_SRC"
