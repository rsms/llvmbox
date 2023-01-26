#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

CFLAGS=
LDFLAGS="-fuse-ld=lld --sysroot=$LLVMBOX_SYSROOT"
CXXFLAGS="-nostdinc++ -I$LLVMBOX_SYSROOT/include/c++/v1"
CXX_LDFLAGS="-nostdlib++ -lc++"
if [ "$TARGET_SYS" = "macos" ]; then
  CFLAGS="$CFLAGS -isystem$(xcrun -sdk macosx --show-sdk-path)/usr/include"
fi

set -x
"$LLVMBOX_SYSROOT/bin/clang++" \
  $CFLAGS $CXXFLAGS \
  $LDFLAGS $CXX_LDFLAGS \
  test/hello.cc -o test/hello_cc_final
test/hello_cc_final


# out/sysroot/x86_64-macos-none/bin/clang++
#   --sysroot=$(xcrun -sdk macosx --show-sdk-path)
#   -fuse-ld=lld
#   -nostdlib++
#   -Lout/sysroot/x86_64-macos-none/lib
#   -lc++ test/hello.cc
#   -o test/hello_cc_final

# /Users/rsms/src/llvm/out/sysroot/x86_64-macos-none/bin/clang++
#   -isystem /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX11.1.sdk/usr/include
#   -nostdinc++
#   -isystem /Users/rsms/src/llvm/out/sysroot/x86_64-macos-none/include/c++/v1
#   -fuse-ld=lld
#   --sysroot=/Users/rsms/src/llvm/out/sysroot/x86_64-macos-none
#   -nostdlib++
#   -lc++ test/hello.cc
#   -o test/hello_cc_final
