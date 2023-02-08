#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

TARGET_ARCH=${1:-$TARGET_ARCH}
ENABLE_LTO=false
LLVM_ROOT="$PROJECT/out/llvmbox"

_pushd "$LLVM_ROOT/src/musl"

LLVMBOX=../..
DESTDIR="$LLVMBOX/targets/$TARGET_ARCH-linux/lib"
BUILDDIR="$LLVMBOX/cache/musl-$TARGET_ARCH-linux"


# [for testing] build using musl's makefile:
# ( cd out/llvmbox/src/musl-1 && rm -rf obj && CC=../../bin/clang AR=../../bin/ar RANLIB=../../bin/ranlib CFLAGS='--target=x86_64-linux-musl' ./configure --disable-shared && make -j$(nproc) )
if false; then
  rm -rf obj

  CC=$LLVMBOX/bin/clang \
  AR=$LLVMBOX/bin/ar \
  RANLIB=$LLVMBOX/bin/ranlib \
  CFLAGS=--target=x86_64-linux-musl \
  ./configure --disable-shared

  make -j$(nproc)
  cp lib/libc.a $DESTDIR/libc.a
  exit
fi


# flags from running 022-musl-libc.sh, then inspecting config.mak & Makefile
CFLAGS=(
  -std=c99 \
  -nostdinc \
  -ffreestanding \
  -frounding-math \
  -Wa,--noexecstack \
  -D_XOPEN_SOURCE=700 \
  \
  -Os \
  -pipe \
  -fomit-frame-pointer \
  -fno-unwind-tables \
  -fno-asynchronous-unwind-tables \
  -ffunction-sections \
  -fdata-sections \
  \
  --target=$TARGET_ARCH-linux-musl \
  -w \
  \
  -Iarch/$TARGET_ARCH \
  -Iarch/generic \
  -Isrc/include \
  -Isrc/internal \
  \
  -I$LLVMBOX/targets/$TARGET_ARCH-linux/include \
  -I$LLVMBOX/targets/any-linux/include \
)

# generate build.ninja file
mkdir -p "$BUILDDIR"
BF="$BUILDDIR/build.ninja"
cat << END > $BF
cflags = ${CFLAGS[@]}
asflags = \$cflags

rule cc
  command = $LLVMBOX/bin/clang -MMD -MF \$out.d \$cflags \$flags -c -o \$out \$in
  depfile = \$out.d
  description = cc \$in -> \$out

rule as
  command = $LLVMBOX/bin/clang -MMD -MF \$out.d \$asflags \$flags -c -o \$out \$in
  depfile = \$out.d
  description = as \$in -> \$out

rule ar
  command = rm -f \$out && $LLVMBOX/bin/ar crs \$out \$in
  description = archive \$out

END

_buildrule() { # <src> <obj> [<flag> ...]
  local src=$1 ; shift
  local obj=$1 ; shift
  case "$src" in
    *.c)    echo "build $obj: cc $src" ;;
    *.[Ss]) echo "build $obj: as $src" ;;
    *)      _err "unexpected file type: $f" ;;
  esac
  local flags=( "$@" )
  # Makefile: NOSSP_OBJS
  case "$src" in
    crt/* | \
    */__libc_start_main.[csS] | \
    */__init_tls.[csS] | \
    */__stack_chk_fail.[csS] | \
    */__set_thread_area.[csS] | \
    */memset.[csS] | \
    */memcpy.[csS] )
      flags+=( -fno-stack-protector ) ;;
  esac
  # Makefile: OPTIMIZE_SRCS
  case "$src" in
    src/internal/*.c | \
    src/malloc/*.c | \
    src/string/*.c | \
    src/string/memcpy.c )
      flags+=( -O3 ) ;;
  esac
  if [ ${#flags[@]} -gt 0 ]; then
    echo "  flags = ${flags[@]}"
  fi
}

_crt_buildrule() { # <name> [<flag> ...]
  local name=$1 ; shift
  local obj=$DESTDIR/$name.o
  local src=crt/$TARGET_ARCH/$name.s
  [ -f "$src" ] || src=crt/$TARGET_ARCH/$name.S
  [ -f "$src" ] || src=crt/$name.c
  _buildrule "$src" "$obj" -DCRT "$@"
  ALL_TARGETS+=( "$obj" )
}

_ar_rule() { # <lib> [<src> ...]
  local lib=$1 ; shift
  ALL_TARGETS+=( "$lib" )
  echo "build $lib: ar $@"
}


OBJDIR="$BUILDDIR/.obj"
# OBJDIR=obj-$TARGET_ARCH
OBJEXT=.lo ; $ENABLE_LTO && OBJEXT=.bc
LIBC_OBJECTS=()
LIBC_SOURCES=()
ALL_TARGETS=()
EMPTY_LIBS=( m rt pthread crypt util xnet resolv dl )

echo "generating $(realpath $BF)"

_crt_buildrule crt1 >> $BF
_crt_buildrule rcrt1 -fPIC >> $BF
_crt_buildrule Scrt1 -fPIC >> $BF
_crt_buildrule crti >> $BF
_crt_buildrule crtn >> $BF
echo >> $BF


# find sources
ARCH_SOURCES=()
for f in \
  src/*/$TARGET_ARCH/*.[csS] \
  src/malloc/mallocng/$TARGET_ARCH/*.[csS] \
;do [ -f "$f" ] && ARCH_SOURCES+=( "$f" ); done
for f in \
  src/*/*.c \
  src/malloc/mallocng/*.c \
;do
  [ -f "$f" ] || continue
  name=${f:0:-2}
  # don't include generic impl if an arch-specific one is used
  exclude=
  for af in "${ARCH_SOURCES[@]}"; do
    af_name=${af:0:-2}
    af_name=${af_name//\/$TARGET_ARCH\//\/}
    if [ $name = $af_name ]; then
      exclude=1
      break
    fi
  done
  [ -z "$exclude" ] || continue
  LIBC_SOURCES+=( "$f" )
done
LIBC_SOURCES+=( "${ARCH_SOURCES[@]}" )

# Some archs need compat/time32 sources. List from:
#   mkdir musl-src
#   tar -C musl-src --strip-components 1 -xf download/musl-1.2.3.tar.gz
#   find musl-src -type f -name '*.mak' -exec sh -c \
#     "grep -q compat/time32 {} && basename \$(dirname {})" \;
[ "$TARGET_ARCH" = "arm" -o "$TARGET_ARCH" = "i386" ] &&
  LIBC_SOURCES+=( compat/time32/*.c )
# echo LIBC_SOURCES; for f in ${LIBC_SOURCES[@]}; do echo "  $f"; done

for src in ${LIBC_SOURCES[@]}; do
  obj="${src}$OBJEXT"
  # obj="${obj//\//__}"
  obj="$OBJDIR/$obj"
  # mkdir -p "$(dirname "$obj")"
  LIBC_OBJECTS+=( "$obj" )
  _buildrule "$src" "$obj" -fPIC >> $BF
done
echo >> $BF

_ar_rule $DESTDIR/libc.a "${LIBC_OBJECTS[@]}"  >> $BF
for name in "${EMPTY_LIBS[@]}"; do
  _ar_rule "$DESTDIR/lib$name.a" >> $BF
done
echo >> $BF

echo "default ${ALL_TARGETS[@]}" >> $BF

# realpath $BF
$LLVMBOX/bin/ninja -j$NCPU -f $BF





# prelinking stuff
# TARGET_EMU=
# # see https://github.com/llvm/llvm-project/blob/llvmorg-15.0.7/lld/ELF/Driver.cpp#L131
# case "$TARGET_ARCH" in
#   x86_64|i386)   TARGET_EMU=elf_${TARGET_ARCH} ;;
#   aarch64|arm64) TARGET_EMU=aarch64elf ;;
#   riscv64)       TARGET_EMU=elf64lriscv ;;
#   riscv32)       TARGET_EMU=elf32lriscv ;;
#   arm*)          TARGET_EMU=armelf ;;
#   *)             _err "don't know -m value for $TARGET_ARCH"
# esac
# $OBJDIR/libc.o: ${OBJECTS[@]}
# ${TAB}bin/ld.lld -r -o \$@ \
#   --lto-O3 \
#   --threads=$NCPU \
#   --no-call-graph-profile-sort \
#   --no-lto-legacy-pass-manager \
#   --compress-debug-sections=zlib \
#   --discard-none \
#   --nostdlib \
#   -m $TARGET_EMU \
#   -z noexecstack \
#   -z relro \
#   -z now \
#   -z defs \
#   -z notext \
#   \$^
