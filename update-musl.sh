#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
# Note: This script can run on any posix system (host doesn't need to be linux)

SUPPORTED_ARCHS=( aarch64 arm i386 riscv64 x86_64 )

_fetch_source_tar \
  https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz \
  "$MUSL_SHA256" "$MUSL_SRC"

_pushd "$MUSL_SRC"

# ————————————————————————————————————————————————————————————————————————————————————
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

# ————————————————————————————————————————————————————————————————————————————————————
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

# ————————————————————————————————————————————————————————————————————————————————————
# generate build files

# musl provides the following libs in libc.
# We generate empty libs so that e.g. -lm doesn't fail.
EMPTY_LIBS=( m pthread crypt util xnet resolv dl )

_pushd "$SOURCE_DESTDIR"

_cc_rule() { # <src> <obj> [<flag> ...]
  local src=$1 ; shift
  local obj=$1 ; shift
  case "$src" in
    *.[csS]) echo "build $obj: cc $src" ;;
    *)       _err "unexpected file type: $f" ;;
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

_gen_buildfile() { # <arch>
  local arch=$1 ; shift
  local BF="build-$arch.ninja"
  local ARCH_SOURCES=()
  local LIBC_OBJECTS=()
  local LIBC_SOURCES=()
  local ALL_TARGETS=()
  local f name src obj exclude af_name

  echo "generating $(_relpath "$PWD/$BF")"

  # flags from running 022-musl-libc.sh, then inspecting config.mak & Makefile
  local CFLAGS=(
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
    --target=$arch-linux-musl \
    -w \
    \
    -Iarch/$arch \
    -Iarch/generic \
    -Isrc/include \
    -Isrc/internal \
    \
    -I../../targets/$arch-linux/include \
    -I../../targets/any-linux/include \
  )

  # find sources
  for f in \
    src/*/$arch/*.[csS] \
    src/malloc/mallocng/$arch/*.[csS] \
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
      af_name=${af_name//\/$arch\//\/}
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
  [ "$arch" = "arm" -o "$arch" = "i386" ] &&
    LIBC_SOURCES+=( compat/time32/*.c )
  # echo LIBC_SOURCES; for f in ${LIBC_SOURCES[@]}; do echo "  $f"; done

  # generate ninja file
  cat << END > $BF
cflags = ${CFLAGS[@]}
libdir = ../../targets/$arch-linux/lib
obj = /tmp/llvmbox-$LLVM_RELEASE+$LLVMBOX_VERSION_TAG-musl-$arch
rule cc
  command = ../../bin/clang -MMD -MF \$out.d \$cflags \$flags -c -o \$out \$in
  depfile = \$out.d
  description = cc \$in -> \$out
rule ar
  command = rm -f \$out && ../../bin/ar crs \$out \$in
  description = archive \$out
END

  # crt (C runtime) objects
  printf "\n# crt\n" >> $BF
  for name in crt1 rcrt1 Scrt1 crti crtn; do
    src=crt/$arch/$name.s
    [ -f "$src" ] || src=crt/$arch/$name.S
    [ -f "$src" ] || src=crt/$name.c
    obj=\$libdir/$name.o
    flags=; [ $name = rcrt1 -o $name = Scrt1 ] && flags=-fPIC
    _cc_rule "$src" "$obj" -DCRT $flags >> $BF
    ALL_TARGETS+=( "$obj" )
  done

  # libc
  printf "\n# libc\n" >> $BF
  for src in ${LIBC_SOURCES[@]}; do
    obj="\$obj/${src}.o"
    LIBC_OBJECTS+=( "$obj" )
    _cc_rule "$src" "$obj" -fPIC >> $BF
  done
  echo "build \$libdir/libc.a: ar ${LIBC_OBJECTS[@]}" >> $BF
  ALL_TARGETS+=( "\$libdir/libc.a" )

  # empty libs
  printf "\n# empty libs\n" >> $BF
  for name in "${EMPTY_LIBS[@]}"; do
    echo "build \$libdir/lib$name.a: ar" >> $BF
    ALL_TARGETS+=( "\$libdir/lib$name.a" )
  done

  echo >> $BF
  echo "default ${ALL_TARGETS[@]}" >> $BF
}


for arch in "${SUPPORTED_ARCHS[@]}"; do
  _gen_buildfile $arch &
done
wait
