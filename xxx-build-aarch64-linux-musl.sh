#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_pushd "$PROJECT/out/llvmbox"

TARGET_ARCH=aarch64
MUSL_ARCH=$TARGET_ARCH  # spelling may vary
DESTDIR=$PWD/lib/$TARGET_ARCH-linux

CFLAGS=(
  -std=c99 -ffreestanding -nostdinc -Os -w \
  -D_XOPEN_SOURCE=700 \
  -Wa,--noexecstack \
  -fPIC \
  "--target=$TARGET_ARCH-linux-musl" \
  \
  "-Icross/libc/musl/arch/$MUSL_ARCH" \
  "-Icross/libc/musl/arch/generic" \
  "-Icross/libc/musl/src/include" \
  "-Icross/libc/musl/src/internal" \
  \
  "-Icross/include/$TARGET_ARCH-linux" \
  "-Icross/include/any-linux" \
  \
  "-fomit-frame-pointer" \
  "-fno-unwind-tables" \
  "-fno-asynchronous-unwind-tables" \
  "-ffunction-sections" \
  "-fdata-sections" \
)

SOURCES=( $(echo cross/libc/musl/src/**/*.c) )

# Some archs need compat/time32 sources
# List from:
#   mkdir musl-src
#   tar -C musl-src --strip-components 1 -xf download/musl-1.2.3.tar.gz
#   find musl-src -type f -name '*.mak' -exec sh -c \
#     "grep -q compat/time32 {} && basename \$(dirname {})" \;
[ "$TARGET_ARCH" = "arm" -o "$TARGET_ARCH" = "i386" ] &&
  SOURCES+=( $(echo cross/libc/musl/compat/time32/*.c) )

ENABLE_LTO=false

OBJDIR="$DESTDIR/.obj"
if $ENABLE_LTO; then
  OBJECTS=( "${SOURCES[@]/%.c/.bc}" )
else
  OBJECTS=( "${SOURCES[@]/%.c/.o}" )
fi
OBJECTS=( "${OBJECTS[@]/#cross\/libc\//$OBJDIR/}" )

[ "${1:-}" = "clean" ] && rm -rf "$OBJDIR"

mkdir -p "$DESTDIR"

TAB=$(printf "\t")

TARGET_EMU=
# see https://github.com/llvm/llvm-project/blob/llvmorg-15.0.7/lld/ELF/Driver.cpp#L131
case "$TARGET_ARCH" in
  x86_64|i386)   TARGET_EMU=elf_${TARGET_ARCH} ;;
  aarch64|arm64) TARGET_EMU=aarch64elf ;;
  riscv64)       TARGET_EMU=elf64lriscv ;;
  riscv32)       TARGET_EMU=elf32lriscv ;;
  arm*)          TARGET_EMU=armelf ;;
  *)             _err "don't know -m value for $TARGET_ARCH"
esac

#$DESTDIR/libc.a: ${OBJECTS[@]}

cat << END | make -j$NCPU -f -
all: $DESTDIR/libc.a $DESTDIR/crti.o $DESTDIR/crtn.o \\
     $DESTDIR/crt1.o $DESTDIR/rcrt1.o $DESTDIR/Scrt1.o

# $DESTDIR/libc.a: $OBJDIR/libc.o
$DESTDIR/libc.a: ${OBJECTS[@]}
${TAB}@echo "create archive \$@"
${TAB}bin/ar rcs \$@ \$^

$OBJDIR/libc.o: ${OBJECTS[@]}
${TAB}bin/ld.lld -r -o \$@ \
  --lto-O3 \
  --threads=$NCPU \
  --no-call-graph-profile-sort \
  --no-lto-legacy-pass-manager \
  --compress-debug-sections=zlib \
  --discard-none \
  --nostdlib \
  -m $TARGET_EMU \
  -z noexecstack \
  -z relro \
  -z now \
  -z defs \
  -z notext \
  \$^

$DESTDIR/crti.o: cross/libc/musl/crt/$MUSL_ARCH/crti.s
${TAB}bin/clang ${CFLAGS[@]} -c \$< -o \$@

$DESTDIR/crtn.o: cross/libc/musl/crt/$MUSL_ARCH/crtn.s
${TAB}bin/clang ${CFLAGS[@]} -c \$< -o \$@

$DESTDIR/crt1.o: cross/libc/musl/crt/crt1.c
${TAB}bin/clang ${CFLAGS[@]} -fno-stack-protector -DCRT -c \$< -o \$@

$DESTDIR/rcrt1.o: cross/libc/musl/crt/rcrt1.c
${TAB}bin/clang ${CFLAGS[@]} -fno-stack-protector -DCRT -fPIC -c \$< -o \$@

$DESTDIR/Scrt1.o: cross/libc/musl/crt/Scrt1.c
${TAB}bin/clang ${CFLAGS[@]} -fno-stack-protector -DCRT -fPIC -c \$< -o \$@

$OBJDIR/%.o: cross/libc/%.c
${TAB}@mkdir -p \$(dir \$@)
${TAB}@echo "compile \$<"
${TAB}@bin/clang ${CFLAGS[@]} -c \$< -o \$@

$OBJDIR/%.bc: cross/libc/%.c
${TAB}@mkdir -p \$(dir \$@)
${TAB}@echo "compile \$<"
${TAB}@bin/clang ${CFLAGS[@]} -flto=thin -c \$< -o \$@

END

# TODO: compiler_rt
# The following will fail to link with "error: undefined symbol: __addtf3"

bin/clang \
  --target=$TARGET_ARCH-linux-musl \
  --sysroot=out/llvmbox/lib/aarch64-linux \
  -nostdinc -nostdlib \
  -Icross/include/$TARGET_ARCH-linux \
  -Icross/include/any-linux \
  -Llib/$TARGET_ARCH-linux \
  -lc \
  ../../test/hello.c -o ../hello_c

