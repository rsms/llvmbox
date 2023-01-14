#!/bin/bash
# 
# test if a compiler can build programs
#
set -e

_err() { echo "$SCRIPTNAME:" "$@" >&2; exit 1; }

_print_exe_links() { # <exefile>
  local OUT
  local objdump="$CCROOT"/bin/llvm-objdump
  [ -f "$objdump" ] || objdump=llvm-objdump
  local PAT='NEEDED|RUNPATH|RPATH'
  case "$HOST_SYS" in
    Darwin) PAT='RUNPATH|RPATH|\.dylib' ;;
  esac
  OUT=$( "$objdump" -p "$1" | grep -E "$PAT" | awk '{printf $1 " " $2 "\n"}' )
  if [ -n "$OUT" ]; then
    echo "$1 is dynamically linked:"
    echo "$OUT"
  else
    echo "$1 is statically linked"
  fi
}

# ————————————————————————————————————————————————————————————————————————————————————
# main

PWD0=${PWD0:-$PWD}
SCRIPTNAME=${0##*/}
HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)
CCROOT=$1
PROJECT=$(dirname "$0")
EXIT_STATUS=0

if [[ "$1" == "--h"* || "$1" == "-h"* ]]; then
  echo "usage: $0 <path-to-llvm>"
  echo "example: $0 $HOME/llvm/build/llvm-host"
  exit
fi
[ -n "$CCROOT" ] || _err "missing <path-to-llvm>"
PREVDIR=$PWD; cd "$PROJECT"; PROJECT=$PWD; cd "$PREVDIR"
PREVDIR=$PWD; cd "$CCROOT"; CCROOT=$PWD; cd "$PREVDIR"

cd "$PROJECT"

# ————————————————————————————————————————————————————————————————————————————————————
# target
if [ -z "$TARGET" ]; then
  TARGET=$HOST_ARCH-unknown-unknown
  case "$HOST_SYS" in
    Linux)  TARGET=$HOST_ARCH-unknown-linux-gnu ;;
    Darwin) TARGET=$HOST_ARCH-macos-none ;;
    *)      _err "cannot infer TARGET; please set TARGET=arch-sys-flavor in env"
  esac
fi

# # ————————————————————————————————————————————————————————————————————————————————————

# C_CFLAGS=()
# C_LFLAGS=()
# CXX_CFLAGS=(
#   -nostdinc++ \
#   -I"$CCROOT"/include/c++/v1 \
# )
# CXX_LFLAGS=(
#   -fuse-ld=lld \
#   -nostdlib++ \
#   -L"$CCROOT"/lib \
#   -lc++ \
#   -lc++abi \
# )
# # -Wl,--push-state -Wl,-Bstatic -lc++ -lc++abi -Wl,--pop-state
# case "$HOST_SYS" in
#   Linux)
#     CXX_CFLAGS+=(
#       -static \
#       -I"$CCROOT"/include/x86_64-unknown-linux-gnu/c++/v1 \
#     )
#     CXX_LFLAGS+=(
#       -L"$CCROOT"/lib/x86_64-unknown-linux-gnu \
#     )
#     ;;
#   Darwin)
#     CXX_CFLAGS+=(
#       -I/Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include \
#     )
#     CXX_LFLAGS+=(
#       -lSystem \
#     )
#     ;;
# esac

# set -x
# "$CCROOT"/bin/clang++ "${CXX_CFLAGS[@]}" "${CXX_LFLAGS[@]}" \
#   -std=c++14 -o hello_cc hello.cc
# ./hello_cc
# set +x
# _print_exe_links hello_cc
# exit

# /Users/rsms/src/llvm/build/llvm-host/bin/clang++
#   -nostdinc++
#   -I/Users/rsms/src/llvm/build/llvm-host/include/c++/v1
#   -I/Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include
#   -fuse-ld=lld
#   -nostdlib++
#   -L/Users/rsms/src/llvm/build/llvm-host/lib
#   -lc++
#   -lc++abi
#   -lSystem
#   -std=c++14 -o hello_cc hello.cc

# /Users/rsms/src/llvm/build/llvm-host/bin/clang++
#   -nostdinc++
#   -I/Users/rsms/src/llvm/build/llvm-host/include/c++/v1
#   -I/Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include
#   -fuse-ld=lld
#   -nostdlib++
#   -L/Users/rsms/src/llvm/build/llvm-host/lib
#   -lc++
#   -lc++abi
#   -lSystem
#   -std=c++14 -o hello_cc hello.cc

# /Users/rsms/src/llvm/build/llvm-host/bin/clang
#   -I/Library/Developer/CommandLineTools/SDKs/MacOSX10.15.sdk/usr/include
#   -Wno-nullability-completeness
#   -fuse-ld=lld
#   -L/Users/rsms/src/llvm/build/llvm-host/lib
#   -lSystem
#   -std=c17 -o hello_c hello.c

# ————————————————————————————————————————————————————————————————————————————————————
# compiler and linker flags
CFLAGS=(
$CFLAGS )

LDFLAGS=(
  -fuse-ld=lld \
  -L"$CCROOT"/lib \
$LDFLAGS )

CXXFLAGS=(
  -nostdinc++ \
  -I"$CCROOT"/include/c++/v1 \
$CXXFLAGS )

CXX_LDFLAGS=(
  -nostdlib++ \
  -lc++ \
  -lc++abi \
$CXX_LDFLAGS )

[ -d "$CCROOT/include/$TARGET/c++/v1" ] &&
  CXXFLAGS+=( "-I$CCROOT/include/$TARGET/c++/v1" )

[ -d "$CCROOT/lib/$TARGET" ] &&
  LDFLAGS+=( "-L$CCROOT/lib/$TARGET" )

case "$HOST_SYS" in
  Linux)
    LDFLAGS=( -static "${LDFLAGS[@]}" )
    ;;
  Darwin)
    [ -d /Library/Developer/CommandLineTools/SDKs ] ||
      _err "missing /Library/Developer/CommandLineTools/SDKs; try running: xcode-select --install"
    MACOS_SDK=$(
      /bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk |
      sort -V | head -n1)
    [ -d "$MACOS_SDK" ] ||
      _err "macos sdk not found at $MACOS_SDK; try running: xcode-select --install"
    CFLAGS+=(
      "-I$MACOS_SDK/usr/include" \
      -Wno-nullability-completeness \
      -DTARGET_OS_EMBEDDED=0 \
    )
    LDFLAGS+=( -lSystem )
    ;;
esac

# note: -nostdinc++ must come first, CFLAGS must be appended to CXXFLAGS
CXXFLAGS+=( "${CFLAGS[@]}" )
CXX_LDFLAGS+=( "${LDFLAGS[@]}" )


echo "--------------------------------------------------------------------------------"
echo "building a simple C program (libc)"
echo "$CCROOT"/bin/clang "${CFLAGS[@]}" "${LDFLAGS[@]}" -std=c17 -o hello_c hello.c
     "$CCROOT"/bin/clang "${CFLAGS[@]}" "${LDFLAGS[@]}" -std=c17 -o hello_c hello.c &&
       ./hello_c &&
       _print_exe_links hello_c ||
       EXIT_STATUS=1


echo "--------------------------------------------------------------------------------"
echo "building a simple C++ program (libc, libc++)"
echo "$CCROOT"/bin/clang++ "${CXXFLAGS[@]}" "${CXX_LDFLAGS[@]}" \
     "$CCROOT"/bin/clang++ "${CXXFLAGS[@]}" "${CXX_LDFLAGS[@]}" \
       -std=c++14 -o hello_cc hello.cc &&
       ./hello_cc &&
       _print_exe_links hello_cc ||
       EXIT_STATUS=1


echo "--------------------------------------------------------------------------------"
echo "building myclang (libc, libc++, llvm, clang, lld)"

ZLIB="$(dirname "$CCROOT")"/zlib-host  # TODO FIXME

MYCLANG_CXXFLAGS=( "${CXXFLAGS[@]}" \
  $("$CCROOT"/bin/llvm-config --cxxflags) \
)
MYCLANG_LDFLAGS=( "${CXX_LDFLAGS[@]}" \
  $("$CCROOT"/bin/llvm-config --ldflags) \
  $("$CCROOT"/bin/llvm-config --link-static --libfiles all) \
  "$CCROOT"/lib/libclang*.a \
  "$ZLIB/lib/libz.a" \
)

MYCLANG_SOURCES=( $(echo myclang/*.{c,cc}) )
MYCLANG_OBJECTS=()
for f in "${MYCLANG_SOURCES[@]}"; do MYCLANG_OBJECTS+=( $f.o ); done

for f in "${MYCLANG_SOURCES[@]}"; do
  [ "$f" -nt "$f.o" ] || continue
  if [[ "$f" == *.cc ]]; then
    echo "$CCROOT"/bin/clang++ "${MYCLANG_CXXFLAGS[@]}" -c -o $f.o $f
         "$CCROOT"/bin/clang++ "${MYCLANG_CXXFLAGS[@]}" -c -o $f.o $f
  else
    echo "$CCROOT"/bin/clang "${CFLAGS[@]}" -c -o $f.o $f
         "$CCROOT"/bin/clang "${CFLAGS[@]}" -c -o $f.o $f
  fi
done

echo "$CCROOT"/bin/clang++ "${MYCLANG_LDFLAGS[@]}" "${MYCLANG_OBJECTS[@]}" \
       -o myclang/myclang
     "$CCROOT"/bin/clang++ "${MYCLANG_LDFLAGS[@]}" "${MYCLANG_OBJECTS[@]}" \
       -o myclang/myclang


exit $EXIT_STATUS
