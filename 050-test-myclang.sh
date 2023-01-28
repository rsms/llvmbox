#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVMBOX_DIR=${1:-}
if [ -z "$LLVMBOX_DIR" ]; then
  LLVMBOX_DIR="$OUT_DIR/llvmbox"
  [ -d "$LLVMBOX_DIR" ] ||
    _err "$(_relpath "$LLVMBOX_DIR") not found. Specify path to complete llvmbox dir with an argument, i.e. $0 <llvmboxdir>"
fi

FLAGS=
[ "$TARGET_SYS" = macos ] || FLAGS=-static

set -x
bash myclang/build.sh "$LLVMBOX_DIR"
myclang/myclang cc $FLAGS test/hello.c -o out/hello
out/hello
