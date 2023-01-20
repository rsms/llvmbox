#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  $MUSL_SHA256 "$MUSL_SRC"

_pushd "$MUSL_SRC"

./configure --disable-shared --prefix="$MUSL_HOST"

make -j$(nproc)

mkdir -p "$MUSL_HOST"
make install


# gcc
#   -std=c99
#   -nostdinc
#   -ffreestanding
#   -fexcess-precision=standard
#   -frounding-math
#   -Wa,--noexecstack
#   -D_XOPEN_SOURCE=700
#   -I./arch/x86_64
#   -I./arch/generic
#   -Iobj/src/internal
#   -I./src/include
#   -I./src/internal
#   -Iobj/include
#   -I./include
#   -Os
#   -pipe
#   -fomit-frame-pointer
#   -fno-unwind-tables
#   -fno-asynchronous-unwind-tables
#   -ffunction-sections
#   -fdata-sections
#   -Wno-pointer-to-int-cast
#   -Werror=implicit-function-declaration
#   -Werror=implicit-int
#   -Werror=pointer-sign
#   -Werror=pointer-arith
#   -Werror=int-conversion
#   -Werror=incompatible-pointer-types
#   -Werror=discarded-qualifiers
#   -Werror=discarded-array-qualifiers
#   -Waddress
#   -Warray-bounds
#   -Wchar-subscripts
#   -Wduplicate-decl-specifier
#   -Winit-self
#   -Wreturn-type
#   -Wsequence-point
#   -Wstrict-aliasing
#   -Wunused-function
#   -Wunused-label
#   -Wunused-variable
#   -fPIC
#   -c
#   -o obj/src/network/ether.lo src/network/ether.c
