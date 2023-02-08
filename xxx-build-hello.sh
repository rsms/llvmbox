#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

TARGET_ARCH=${1:-$TARGET_ARCH}
# PROG=hello_puts
PROG=hello

_pushd "$PROJECT/out/llvmbox"

set -x
bin/clang \
  --target=$TARGET_ARCH-linux-musl \
  --sysroot=out/llvmbox/lib/$TARGET_ARCH-linux \
  -nostdinc -nostdlib -nostartfiles -ffreestanding \
  -Itargets/$TARGET_ARCH-linux/include \
  -Itargets/any-linux/include \
  \
  -Ltargets/$TARGET_ARCH-linux/lib \
  -lc -static \
  -o ../../out/$PROG-$TARGET_ARCH-linux \
  targets/$TARGET_ARCH-linux/lib/crt1.o \
  ../../test/$PROG.c
