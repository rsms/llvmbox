#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

if [ "${1:-}" != "-f" ] &&
   [ "$(cat "$LLVM_SRC_STAGE1/version" 2>/dev/null)" = "$LLVM_RELEASE" ]
then
  echo "up to date (\`$0 -f\` to force re-creation)"
  exit
fi

_fetch_source_tar "$LLVM_SRC_URL" "$LLVM_SHA256" "$LLVM_SRC_STAGE1"

# apply patches
cd "$PROJECT"/patches
PATCHFILES=(
  $(echo {,stage1-,$TARGET_SYS-,stage1-$TARGET_SYS-}llvm-$LLVM_RELEASE-*.patch | sort) )
_pushd "$LLVM_SRC_STAGE1"
for f in "${PATCHFILES[@]}"; do
  f="$PROJECT/patches/$f"
  [ -e "$f" ] || continue
  echo "patch -p1 < $f"
  patch -p1 < "$f"
done

printf "%s" "$LLVM_RELEASE" > "$LLVM_SRC_STAGE1/version"

# note: linux patches adopted from
# https://git.alpinelinux.org/aports/tree/main/llvm-runtimes
