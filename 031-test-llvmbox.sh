#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVM_ROOT="${1:-$LLVMBOX_DESTDIR}"
LLVM_ROOT="`cd "$LLVM_ROOT"; pwd`"

LLVM_DEV_ROOT="${2:-$LLVMBOX_DEV_DESTDIR}"
LLVM_DEV_ROOT="`cd "$LLVM_DEV_ROOT"; pwd`"

LLVM_CONFIG="$LLVM_DEV_ROOT/bin/llvm-config"

CC="$LLVM_ROOT/bin/clang"
CXX="$LLVM_ROOT/bin/clang++"
CFLAGS=( "${STAGE2_LTO_CFLAGS[@]:-}" ${CFLAGS:--O2} )
CXXFLAGS=( "${CFLAGS[@]:-}" )
LDFLAGS=( "${STAGE2_LTO_LDFLAGS[@]:-}" ${LDFLAGS:-} )

[ "$TARGET_SYS" = macos ] || LDFLAGS=-static

_cc()  { echo "$(_relpath "$CC")" "$@" ; time "$CC" "$@"; }
_cxx() { echo "$(_relpath "$CXX")" "$@" ; time "$CXX" "$@"; }

_pushd "$PROJECT/test"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello_c"
_cc "${CFLAGS[@]:-}" "${LDFLAGS[@]:-}" hello.c -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello_cc"
_cxx "${CXXFLAGS[@]:-}" "${LDFLAGS[@]:-}" -std=c++14 hello.cc -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello-llvm_c"
_cc $("$LLVM_CONFIG" --cflags) -c hello-llvm.c -o "$out.o"
_cxx \
  $("$LLVM_CONFIG" --ldflags --system-libs --libs core native) \
  "$out.o" -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello-llvm_c_lto"
_cc $("$LLVM_CONFIG" --cflags) -flto=thin -c hello-llvm.c -o "$out.o"
_cxx \
  -L"$LLVM_DEV_ROOT/lib-lto" \
  -nostdlib++ -L"$LLVM_ROOT/sysroot/lib-lto" -lc++ \
  $("$LLVM_CONFIG" --system-libs --libs core native) \
  "$out.o" -o "$out"
_print_linking "$out" ; "$out"
