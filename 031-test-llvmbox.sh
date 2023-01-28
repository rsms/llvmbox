#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVM_ROOT="${1:-$LLVMBOX_DESTDIR}"
LLVM_ROOT="`cd "$LLVM_ROOT"; pwd`"

CC="$LLVM_ROOT/bin/clang"
CXX="$LLVM_ROOT/bin/clang++"
CFLAGS=( "${STAGE2_LTO_CFLAGS[@]:-}" ${CFLAGS:--O2} )
CXXFLAGS=( "${CFLAGS[@]:-}" )
LDFLAGS=( "${STAGE2_LTO_LDFLAGS[@]:-}" ${LDFLAGS:-} )

[ "$TARGET_SYS" = macos ] || LDFLAGS=-static

_cc() {  echo "$(_relpath "$CC")" "${CFLAGS[@]:-}" "${LDFLAGS[@]:-}" "$@"
         time "$CC" "${CFLAGS[@]:-}" "${LDFLAGS[@]:-}" "$@"; }

_cxx() { echo "$(_relpath "$CXX")" "${CXXFLAGS[@]:-}" "${LDFLAGS[@]:-}" "$@"
         time "$CXX" "${CXXFLAGS[@]:-}" "${LDFLAGS[@]:-}" "$@"; }

_pushd "$PROJECT/test"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello_c"
_cc hello.c -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
out="$BUILD_DIR/hello_cc"
_cxx -std=c++17 hello.cc -o "$out"
_print_linking "$out" ; "$out"
