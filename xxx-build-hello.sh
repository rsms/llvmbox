#!/bin/bash
#
# usage: $0 [<target>]
# example: $0 aarch64-linux
#
set -euo pipefail
source "$(dirname "$0")/config.sh"

TARGET=${1:-$ARCH-$SYS}
IFS=- read -r ARCH SYS <<< "$TARGET"
IFS=. read -r SYS SYSVER <<< "$SYS"
ARCH=${ARCH:-$TARGET_ARCH} # default from config.sh
SYS=${SYS:-$TARGET_SYS} # default from config.sh
TRIPLE=$ARCH-$SYS
case "$SYS" in
  linux) TRIPLE=$ARCH-linux-musl ;;
  macos) TRIPLE=$ARCH-apple-darwin
    if [ -z "$SYSVER" -a "$ARCH" = aarch64 ]; then
      SYSVER=11
    elif [ -z "$SYSVER" ]; then
      SYSVER=10
    fi
    case "$SYSVER" in
      "") TRIPLE=${TRIPLE}19 ;;
      *)  TRIPLE=${TRIPLE}$(( ${SYSVER%%.*} + 9 )) ;;
    esac
    ;;
esac
# echo "ARCH=$ARCH SYS=$SYS SYSVER=$SYSVER TRIPLE=$TRIPLE"

_pushd "$PROJECT/out/llvmbox"

cat << END > ../hello.c
#include <stdio.h>
int main(int argc, char* argv[]) {
  // puts("Hello world!");
  printf("Hello world from %s\n", argv[0]);
  return 0;
}
END

LDFLAGS= ; [ "$SYS" = linux ] && LDFLAGS=-static
LIBDIR=targets/$ARCH-$SYS.$SYSVER/lib
[ -d "$LIBDIR" ] || LIBDIR=targets/$ARCH-$SYS/lib

set -x
cat ../hello.c
bin/clang \
  --target=$TRIPLE \
  --sysroot=$(dirname $LIBDIR) \
  -nostdinc -nostdlib -nostartfiles -ffreestanding \
  -Itargets/$ARCH-$SYS.$SYSVER/include \
  -Itargets/$ARCH-$SYS/include \
  -Itargets/any-$SYS/include \
  -L$LIBDIR \
  -lc -lrt -fPIE $LDFLAGS \
  -o ../hello-$ARCH-$SYS \
  targets/$ARCH-$SYS/lib/crt1.o \
  ../hello.c
