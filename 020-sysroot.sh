#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
#
# usage 1/2: $0  # use TARGET from config.sh
# usage 2/2: $0 <arch> <sys> <sysversion>
#
ARCH=${1:-$TARGET_ARCH}
SYS=${2:-$TARGET_SYS}
SYSVER=${3:-$TARGET_SYS_VERSION}
SYSVER_MAJOR=${SYSVER%%.*}
SYSROOT=$LLVMBOX_SYSROOT_BASE/$TARGET_ARCH-$TARGET_SYS-$SYSVER

echo "mkdir $(_relpath "$SYSROOT")"
rm -rf "$SYSROOT"
mkdir -p "$SYSROOT"/{lib,include}

_pushd "$SYSROOTS_DIR"

for key in \
  any-any \
  $ARCH-any \
  any-$SYS \
  any-$SYS.$SYSVER_MAJOR \
  any-$SYS.$SYSVER \
  $ARCH-$SYS \
  $ARCH-$SYS.$SYSVER_MAJOR \
  $ARCH-$SYS.$SYSVER \
;do
  include_dir=libc/include/$key
  lib_dir=libc/lib/$key
  if [ -d "$include_dir" ]; then
    echo "rsync $include_dir/ -> $(_relpath "$SYSROOT")/include/"
    rsync -a "$include_dir/" "$SYSROOT/include/"
  fi
  if [ -d "$lib_dir" ]; then
    echo "rsync $lib_dir/ -> $(_relpath "$SYSROOT")/lib/"
    rsync -a "$lib_dir/" "$SYSROOT/lib/"
  fi
done

# echo "creating sysroot base snapshot $(_relpath "$SYSROOT").tar.xz"
# XZ_OPT='-T0' tar -C "$SYSROOT" -cJpf "$SYSROOT.tar.xz" .
