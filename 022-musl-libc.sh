#!/bin/bash
#
# musl startfiles:
#   crt1.o  [exe]position-dependent _start
#   Scrt1.o [exe] position-Independent _start
#   crti.o  [exe, shlib] function prologs for the .init and .fini sections
#   crtn.o  [exe, shlib] function epilogs for the .init/.fini sections
#   note: musl has no crt0
#   linking order: crt1 crti [-L paths] [objects] [C libs] crtn
#
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  $MUSL_SHA256 "$MUSL_SRC"

_pushd "$MUSL_SRC"

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
RANLIB=$STAGE2_RANLIB \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
LIBCC=-lclang_rt.builtins \
./configure --target=$TARGET_TRIPLE --disable-shared --prefix=

make -j$(nproc)

mkdir -p "$LLVMBOX_SYSROOT"
DESTDIR=$LLVMBOX_SYSROOT make install
# [ -e "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1 -> /lib/libc.so" ]

# fix absoulute dynamic loader symlink (only when configured with --enable-shared)
[ -e "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1" ] &&
  ln -sf libc.so "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1"

# remove wrappers (they don't work with our setup anyways)
rm -f "$LLVMBOX_SYSROOT/bin/ld.musl-clang"
rm -f "$LLVMBOX_SYSROOT/bin/musl-clang"

_popd
rm -rf "$MUSL_SRC"
