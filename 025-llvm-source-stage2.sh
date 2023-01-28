#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar "$LLVM_SRC_URL" "$LLVM_SHA256" "$LLVM_SRC"

# apply patches
cd "$PROJECT"/patches
PATCHFILES=(
  $(echo {,stage2-,$TARGET_SYS-,stage2-$TARGET_SYS-}llvm-$LLVM_RELEASE-*.patch | sort) )
_pushd "$LLVM_SRC"
for f in "${PATCHFILES[@]}"; do
  f="$PROJECT/patches/$f"
  [ -e "$f" ] || continue
  echo "patch -p1 < $f"
  patch -p1 < "$f"
done
