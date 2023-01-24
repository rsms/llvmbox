#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
#
# usage: 020-sysroot.sh [-incr]
# -incr  Incremental; don't delete exising sysroot but instead add to it
#

echo "mkdir $(_relpath "$LLVMBOX_SYSROOT")/{lib,include}"
[ "${1:-}" = "-incr" ] || rm -rf "$LLVMBOX_SYSROOT"
mkdir -p "$LLVMBOX_SYSROOT"/{lib,include}

_pushd "$SYSROOTS_DIR"

for key in \
  any-any \
  $TARGET_ARCH-any \
  any-$TARGET_SYS \
  any-$TARGET_SYS.$TARGET_SYS_VERSION_MAJOR \
  any-$TARGET_SYS.$TARGET_SYS_VERSION \
  $TARGET_ARCH-$TARGET_SYS \
  $TARGET_ARCH-$TARGET_SYS.$TARGET_SYS_VERSION_MAJOR \
  $TARGET_ARCH-$TARGET_SYS.$TARGET_SYS_VERSION \
;do
  include_dir=include/$key
  lib_dir=lib/$key
  if [ -d "$include_dir" ]; then
    echo "rsync $include_dir/ -> $(_relpath "$LLVMBOX_SYSROOT")/include/"
    rsync -a "$include_dir/" "$LLVMBOX_SYSROOT/include/"
  fi
  if [ -d "$lib_dir" ]; then
    echo "rsync $lib_dir/ -> $(_relpath "$LLVMBOX_SYSROOT")/lib/"
    rsync -a "$lib_dir/" "$LLVMBOX_SYSROOT/lib/"
  fi
done

# echo "creating sysroot base snapshot $(_relpath "$LLVMBOX_SYSROOT").tar.xz"
# XZ_OPT='-T0' tar -C "$LLVMBOX_SYSROOT" -cJpf "$LLVMBOX_SYSROOT.tar.xz" .
