#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

TARGET_ARCH=${1:-$TARGET_ARCH}
TARGET_SYS=${2:-linux}
TARGET_SYS_VERSION_MAJOR=10
TARGET_TRIPLE=
case "$TARGET_SYS" in
  macos) TARGET_TRIPLE=$TARGET_ARCH-apple-darwin ;;
  linux) TARGET_TRIPLE=$TARGET_ARCH-$TARGET_SYS-musl ;;
  *)     TARGET_TRIPLE=$TARGET_ARCH-$TARGET_SYS ;;
esac

_pushd "$PROJECT/out/llvmbox/src/builtins"

LLVMBOX=../..
DESTDIR="$LLVMBOX/targets/$TARGET_ARCH-$TARGET_SYS/lib"
BUILDDIR="$LLVMBOX/cache/builtins-$TARGET_ARCH-$TARGET_SYS"

# see compiler-rt/lib/builtins/CMakeLists.txt
CFLAGS=(
  -std=c11 -nostdinc -Os --target=$TARGET_TRIPLE \
  -fPIC \
  -fno-builtin \
  -fomit-frame-pointer \
  -Wno-nullability-completeness \
  -I. \
  -I$LLVMBOX/lib/clang/$LLVM_RELEASE/include \
)
ASFLAGS=(
  -nostdinc -Os --target=$TARGET_TRIPLE \
  -fPIC \
  -fno-builtin \
  -fomit-frame-pointer \
  -I. \
)
# note: lib/clang/$LLVM_RELEASE/include contains headers for all supported archs

# system and libc headers
for d in \
  $LLVMBOX/targets/$TARGET_ARCH-$TARGET_SYS.$TARGET_SYS_VERSION_MAJOR/include \
  $LLVMBOX/targets/$TARGET_ARCH-$TARGET_SYS/include \
  $LLVMBOX/targets/any-$TARGET_SYS/include \
;do
  [ -d "$d" ] && CFLAGS+=( "-I$d" )
done

# $COMPILER_RT_HAS_FLOAT16 && CFLAGS+=( -DCOMPILER_RT_HAS_FLOAT16 )

# arch-specific flags
case "$TARGET_ARCH" in
  riscv32) CFLAGS+=( -fforce-enable-int128 ) ;;
esac

# exclude certain functions, depending on platform and arch
for f in \
  filters/any-$TARGET_SYS.exclude \
  filters/$TARGET_ARCH-$TARGET_SYS.exclude \
;do
  [ -f $f ] || continue
  for name in $(cat $f); do
    declare EXCLUDE_FUN_${name##*/}=1
  done
done
echo EXCLUDE_FUNCTIONS=${EXCLUDE_FUNCTIONS[@]}

# build directory
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
BF="$BUILDDIR/build.ninja"

# generate build.ninja file
cat << END > $BF
cflags = ${CFLAGS[@]}
asflags = ${ASFLAGS[@]}

rule cc
  command = ../../bin/clang -MMD -MF \$out.d \$cflags \$flags -c \$in -o \$out
  depfile = \$out.d
  description = compile \$in

rule as
  command = ../../bin/clang -MMD -MF \$out.d \$asflags \$flags -c \$in -o \$out
  depfile = \$out.d
  description = compile \$in

rule ar
  command = ../../bin/ar crs \$out \$in
  description = archive \$out

END

# add sources
SOURCES=( *.c $TARGET_ARCH/*.{c,S} )
OBJECTS=()
for f in ${SOURCES[@]}; do
  [ -f "$f" ] || continue
  funname=${f:0:-2}
  funname=${funname##*/}
  funname_var=EXCLUDE_FUN_${funname}
  if [ -n "${!funname_var:-}" ]; then
    echo "excluding $f"
    continue
  fi
  obj=$BUILDDIR/$f.o
  OBJECTS+=( $obj )
  case $f in
    *.c)     echo "build $obj: cc $f" >> $BF ;;
    *.S|*.s) echo "build $obj: as $f" >> $BF ;;
    *)       _err "unexpected file type: $f" ;;
  esac
done

echo "build $DESTDIR/librt.a: ar ${OBJECTS[@]}" >> $BF
echo "default $DESTDIR/librt.a" >> $BF

# realpath $BF
../../bin/ninja -j$NCPU -f $BF
