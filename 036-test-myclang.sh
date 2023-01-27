#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

FLAGS=
[ "$TARGET_SYS" = macos ] || FLAGS=-static

set -x

LLVM_ROOT="$LLVMBOX_DESTDIR" bash myclang/build.sh

myclang/myclang cc -flto $FLAGS test/hello.c -o out/hello

out/hello
