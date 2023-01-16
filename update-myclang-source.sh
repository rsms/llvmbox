#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

# copy clang driver impl for myclang

_pushd "$PROJECT"

cp -v "$LLVM_SRC"/clang/tools/driver/driver.cpp     myclang/driver.cc
cp -v "$LLVM_SRC"/clang/tools/driver/cc1_main.cpp   myclang/driver_cc1_main.cc
cp -v "$LLVM_SRC"/clang/tools/driver/cc1as_main.cpp myclang/driver_cc1as_main.cc

for f in $(echo myclang-$LLVM_RELEASE-*.patch | sort); do
  [ -e "$f" ] || _err "no patches found at $PROJECT/llvm-$LLVM_RELEASE-*.patch"
  [ -f "$f" ] || _err "$f is not a file"
  if ! patch -p0 < "$f"; then
    cat << END
To make a new patch:
  cp '$LLVM_SRC/clang/tools/driver/driver.cpp' myclang/driver.cc
  cp myclang/driver.cc myclang/driver.cc.orig
  # edit myclang/driver.cc
  diff -u myclang/driver.cc.orig myclang/driver.cc > myclang-'$LLVM_RELEASE'-001-driver.patch
END
    exit 1
  fi
done
