#!/bin/bash
set -e
PWD0=${PWD0:-$PWD}
SELF_SCRIPT=$(realpath "$0")
cd "$(dirname "$0")"
PROJECT=$(realpath "$PWD/..")

_usage() {
  echo "usage: $0 <llvmroot>"
}

case "${1:-}" in
  "")
    echo "$0: <llvmroot> not provided" >&2
    _usage >&2
    exit 1
    ;;
  -h*|--help) _usage; exit 0 ;;
  *) LLVM_ROOT=`cd "$PWD0"; realpath "$1"` ;;
esac

SOURCES=( $(echo *.{c,cc}) )
BUILD_DIR=build-$(sha1sum "$LLVM_ROOT/bin/clang" | cut -d' ' -f1)
LTO_CACHE=$BUILD_DIR/lto-cache
CFLAGS=( \
  $("$LLVM_ROOT"/bin/llvm-config --cflags) \
  -DMYCLANG_SYSROOT="\"$LLVM_ROOT/sysroot/host\"" \
)
CXXFLAGS=(
  $("$LLVM_ROOT"/bin/llvm-config --cxxflags) \
)
LDFLAGS=( \
  $("$LLVM_ROOT"/bin/llvm-config --ldflags --system-libs)
)
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
[ "$(uname -s)" = Linux ] && LDFLAGS+=( -static )
# # LTO
# CFLAGS+=( -flto=thin )
# CXXFLAGS+=( -flto=thin )
# LDFLAGS+=( -flto=thin )
# case "$(uname -s)" in
#   Linux)  LDFLAGS+=( "-Wl,--thinlto-cache-dir=$LTO_CACHE" ) ;;
#   Darwin) LDFLAGS+=( "-Wl,-cache_path_lto,$LTO_CACHE" ) ;;
# esac

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
