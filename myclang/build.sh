#!/bin/bash
set -e
PWD0=${PWD0:-$PWD}
SELF_SCRIPT=$(realpath "$0")
cd "$(dirname "$0")"
PROJECT=$(realpath "$PWD/..")

if [ -z "$LLVM_ROOT" ]; then
  echo "LLVM_ROOT not set in env (e.g. LLVM_ROOT=/path/to/llvm so that \$LLVM_ROOT/bin/clang is found)" >&2
  exit 1
fi
LLVM_ROOT=`cd "$PWD0"; realpath "$LLVM_ROOT"`
SOURCES=( $(echo *.{c,cc}) )
BUILD_DIR=build-$(uname -m)-$(uname -s)
LTO_CACHE=$BUILD_DIR/lto-cache
CFLAGS=( \
  -flto=thin \
  $("$LLVM_ROOT"/bin/llvm-config --cflags) \
  -DMYCLANG_SYSROOT="\"$LLVM_ROOT/sysroot/host\"" \
)
CXXFLAGS=(
  -flto=thin \
  $("$LLVM_ROOT"/bin/llvm-config --cxxflags) \
)
LDFLAGS=( -flto=thin )
if [ -e "$LLVM_ROOT"/lib/libllvm.a ]; then
  LDFLAGS+=( "$LLVM_ROOT"/lib/libllvm.a )
else
  LDFLAGS+=(
    $("$LLVM_ROOT"/bin/llvm-config --ldflags --system-libs --link-static --libs) \
    "$LLVM_ROOT"/lib/libclang*.a \
    "$LLVM_ROOT"/lib/liblld*.a \
    "$LLVM_ROOT"/lib/libz.a \
  )
fi
case "$(uname -s)" in
  Linux)  LDFLAGS+=( -static "-Wl,--thinlto-cache-dir=$LTO_CACHE" ) ;;
  Darwin) LDFLAGS+=( "-Wl,-cache_path_lto,$LTO_CACHE" ) ;;
esac

OBJECTS=()
mkdir -p "$BUILD_DIR"
for f in "${SOURCES[@]}"; do
  obj=$BUILD_DIR/$f.o
  OBJECTS+=( "$obj" )
  [ "$f" -nt "$obj" -o "$SELF_SCRIPT" -nt "$obj" ] || continue
  if [[ "$f" == *.cc ]]; then
    echo "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $obj $f
         "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $obj $f
  else
    echo "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $obj $f
         "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $obj $f
  fi
done

echo "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang
     "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang

[ -L ld64.lld ] || ln -sfv myclang ld64.lld
[ -L ld.lld ] || ln -sfv myclang ld.lld
