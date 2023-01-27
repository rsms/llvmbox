#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

FLAGS=
[ "$TARGET_SYS" = macos ] || FLAGS=-static

set -x
bash myclang/build.sh "$LLVMBOX_DESTDIR"
myclang/myclang cc $FLAGS test/hello.c -o out/hello
out/hello
