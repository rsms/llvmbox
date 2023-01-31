#!/bin/bash
set -e
PWD0=${PWD0:-$PWD}
SELF_SCRIPT=$(realpath "$0")
cd "$(dirname "$0")"
PROJECT=$(realpath "$PWD/..")
ENABLE_LTO=false
LLVM_CONFIG="$PROJECT/out/llvmbox-dev/bin/llvm-config"

_err() { echo -e "$0:" "$@" >&2 ; exit 1; }
_usage() { echo "usage: $0 [--lto] <llvmroot>"; }

while [[ $# -gt 0 ]]; do case "$1" in
  -h*|--help) _usage; exit 0 ;;
  --lto|-lto) ENABLE_LTO=true; shift ;;
  *)
    [ -z "$LLVM_ROOT" ] || _err "unexpected extra argument \"$1\""
    LLVM_ROOT=`cd "$PWD0"; realpath "$1"`; shift
    ;;
esac; done
if [ -z "$LLVM_ROOT" ]; then
  echo "$0: <llvmroot> not provided" >&2
  _usage >&2
  exit 1
fi

SOURCES=( $(echo *.{c,cc}) )
BUILD_DIR=build
C_AND_CXX_FLAGS=(
  -Os \
  -I"$PROJECT"/out/llvmbox-dev/include \
  -DMYCLANG_SYSROOT="\"$LLVM_ROOT/sysroot\"" \
)
CFLAGS=( $("$LLVM_CONFIG" --cflags) )
CXXFLAGS=( $("$LLVM_CONFIG" --cxxflags) )
LDFLAGS=( -gz=zlib )

# ——————————————————————————————————————————————————————————————————————————————————————
# LTO enabled (using individual ThinLTO libs directly from llvm build)
# macos: 1m37.833s (0m9.439s incremental)   90,186,136 B (70,756,788 stripped)
# linux: 8m42.924s (0m11.473s incremental)  94,244,048 B (73,746,312 stripped)
#
# LTO disabled (link with liball_llvm_clang_lld.a)
# macos: 0m0.887s  120,090,320 B (89,755,888 stripped)
# linux: 0m0.486s  116,912,576 B (96,382,304 stripped)
#
if $ENABLE_LTO; then
  CFLAGS+=( -flto=thin )
  CXXFLAGS+=( -flto=thin )
  LDFLAGS+=( -flto=thin -L"$PROJECT"/out/llvmbox-dev/lib-lto )
  case "$(uname -s)" in
    Linux)  LDFLAGS+=( "-Wl,--thinlto-cache-dir=$BUILD_DIR/lto-cache" ) ;;
    Darwin) LDFLAGS+=( "-Wl,-cache_path_lto,$BUILD_DIR/lto-cache" ) ;;
  esac
  LDFLAGS+=( "$PROJECT"/out/llvmbox-dev/lib-lto/lib{clang,lld,LLVM}*.a )
else
  LDFLAGS+=(
    -L"$PROJECT"/out/llvmbox-dev/lib \
    "$PROJECT"/out/llvmbox-dev/lib/liball_llvm_clang_lld.a \
  )
fi

LDFLAGS+=( $("$LLVM_CONFIG" --system-libs) )

CFLAGS=( "${C_AND_CXX_FLAGS[@]}" "${CFLAGS[@]}" )
CXXFLAGS=( "${C_AND_CXX_FLAGS[@]}" "${CXXFLAGS[@]}" )
[ "$(uname -s)" = Linux ] && LDFLAGS+=( -static )

mkdir -p "$BUILD_DIR"
echo "target $(uname -ms)"      > "$BUILD_DIR/config.tmp"
echo "CFLAGS ${CFLAGS[@]}"     >> "$BUILD_DIR/config.tmp"
echo "CXXFLAGS ${CXXFLAGS[@]}" >> "$BUILD_DIR/config.tmp"
# echo "LDFLAGS ${LDFLAGS[@]}"   >> "$BUILD_DIR/config.tmp"
echo "SRC ${SOURCES[@]}"       >> "$BUILD_DIR/config.tmp"
if ! diff -q "$BUILD_DIR/config" "$BUILD_DIR/config.tmp" >/dev/null 2>&1; then
  [ -e "$BUILD_DIR/config" ] && echo "build configuration changed"
  mv "$BUILD_DIR/config.tmp" "$BUILD_DIR/config"
  rm -rf "$BUILD_DIR/lto-cache" "$BUILD_DIR"/*.o
else
  rm "$BUILD_DIR/config.tmp"
fi

OBJECTS=()
for f in "${SOURCES[@]}"; do
  obj=$BUILD_DIR/$f.o
  OBJECTS+=( "$obj" )
  [ -e "$obj" -a "$obj" -nt "$f" ] && continue
  if [[ "$f" == *.cc ]]; then
    echo "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $obj $f
         "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $obj $f &
  else
    echo "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $obj $f
         "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $obj $f &
  fi
done
wait

echo "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang
time "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang

[ -L ld64.lld ] || ln -sfv myclang ld64.lld
[ -L ld.lld ] || ln -sfv myclang ld.lld
