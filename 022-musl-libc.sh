#!/bin/bash
#
# musl startfiles:
#   crt1.o  [exe] position-dependent _start
#   rcrt1.o [exe] position-independent _start, static libc
#   Scrt1.o [exe] position-independent _start, shared libc
#   crti.o  [exe, shlib] function prologs for the .init and .fini sections
#   crtn.o  [exe, shlib] function epilogs for the .init/.fini sections
#   note: musl has no crt0
#   linking order: crt1 crti [-L paths] [objects] [C libs] crtn
#   See https://www.openwall.com/lists/musl/2015/06/01/12 re. rcrt1.o
#
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

# comment this out to enable building libc-shared.so in addition to libc.a
CONFIG_ARGS="--disable-shared"

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  "$MUSL_SHA256" "$MUSL_SRC"

_pushd "$MUSL_SRC"

# note: do NOT include STAGE2_LTO_*FLAGS for musl; the LTO gains are basically zero
# and would just complect the build setup.

CC=$STAGE2_CC \
LD=$STAGE2_LD \
AR=$STAGE2_AR \
RANLIB=$STAGE2_RANLIB \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
LIBCC="-L$LLVM_STAGE1/lib/clang/$LLVM_RELEASE/lib/linux -lclang_rt.builtins-$TARGET_ARCH" \
./configure --target=$TARGET_TRIPLE --prefix= ${CONFIG_ARGS:-}

make -j$NCPU

mkdir -p "$LLVMBOX_SYSROOT"
DESTDIR=$LLVMBOX_SYSROOT make install
# [ -e "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1 -> /lib/libc.so" ]

rm -f "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1"

# Move shared lib aside (for now) to prevent other tools from linking against it.
# To successfully run an exe linked against musl libc.so we have to use a custom
# "interpreter" by passing "-dynamic-linker <path>" to ld. However we can't simply
# add that to STAGE2_LDFLAGS since it would break linking libs.
if [ -e "$LLVMBOX_SYSROOT/lib/libc.so" ]; then
  mv -v "$LLVMBOX_SYSROOT/lib/libc.so" "$LLVMBOX_SYSROOT/lib/libc-shared.so"
  ln -sv libc-shared.so "$LLVMBOX_SYSROOT/lib/ld-musl-$TARGET_ARCH.so.1"
fi

# remove wrappers (they don't work with our setup anyways)
rm -f "$LLVMBOX_SYSROOT/bin/ld.musl-clang"
rm -f "$LLVMBOX_SYSROOT/bin/musl-clang"

_popd
rm -rf "$MUSL_SRC"
