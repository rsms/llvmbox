#!/bin/bash
set -e
# D=$PWD; cd "$(dirname "$0")"; PROJECT=$PWD; cd "$D"
if [ -z "$LLVM_ROOT" ]; then
  echo "LLVM_ROOT not set in env (e.g. LLVM_ROOT=/path/to/llvm so that \$LLVM_ROOT/bin/clang is found)" >&2
  exit 1
fi

D=$PWD; cd "$LLVM_ROOT"; LLVM_ROOT=$PWD; cd "$D"

CLANG=$LLVM_ROOT/bin/clang
CFLAGS=()
LDFLAGS=( -fuse-ld=lld "-L$LLVM_ROOT/lib" )

# c++ (note: -nostdinc++ must come first, before other -I or -isystem args)
if [ "${0##*/}" = "c++" ]; then
  CLANG=$LLVM_ROOT/bin/clang++
  CFLAGS+=(
    -nostdinc++ \
    -isystem "$LLVM_ROOT/include/c++/v1" \
    -I"$LLVM_ROOT/include/c++/v1" \
  )
  LDFLAGS+=(
    -nostdlib++ \
    -lc++ -lc++abi \
  )
  # on linux, a c++ __config_site header is placed in a subdirectory
  # "include/HOST_TRIPLE/c++/v1/__config_site"
  # e.g. include/x86_64-unknown-linux-gnu/c++/v1/__config_site
  HOST_SYS=$(uname -s)
  HOST_ARCH=$(uname -m)
  [ "$HOST_SYS" = "Linux" ] &&
  [ -d "$(echo "$LLVM_ROOT/include/$HOST_ARCH-"*)" ] &&
    CFLAGS+=( -I"$(echo "$LLVM_ROOT/include/$HOST_ARCH-"*)/c++/v1" )
  # same goes for lib
  [ "$HOST_SYS" = "Linux" ] &&
  [ -d "$(echo "$LLVM_ROOT/lib/$HOST_ARCH-"*)" ] &&
    LDFLAGS+=( -L"$(echo "$LLVM_ROOT/lib/$HOST_ARCH-"*)" )
fi

case "${TARGET:-$(uname -s)}" in
  Darwin|darwin|macos)
    [ -d /Library/Developer/CommandLineTools/SDKs ] ||
      _err "missing /Library/Developer/CommandLineTools/SDKs; try running: xcode-select --install"
    MACOS_SDK=$(
      /bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk |
      sort -V | head -n1)
    [ -d "$MACOS_SDK" ] ||
      _err "macos sdk not found at $MACOS_SDK; try running: xcode-select --install"
    CFLAGS+=(
      -isystem "$MACOS_SDK/usr/include" \
      -Wno-nullability-completeness \
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
    )
    # LDFLAGS+=( -lSystem )
    ;;
esac

if [ "$1" = "--print-cmd" ]; then
  shift
  echo "$CLANG" "${CFLAGS[@]}" "${LDFLAGS[@]}" "$@"
  exit
fi

exec "$CLANG" "${CFLAGS[@]}" "${LDFLAGS[@]}" "$@"
