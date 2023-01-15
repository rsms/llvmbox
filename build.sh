#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

_pushd "$PROJECT"

for f in $(echo 0*.sh | sort); do
  echo ""
  echo "———————————————————————————————————————————"
  echo bash "$f"
       bash "$f"
done

bash test.sh $BUILD_DIR/llvm-$TARGET
