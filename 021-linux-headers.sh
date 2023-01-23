#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

LINUX_VERSION_MAJOR=${LINUX_VERSION%%.*}  # e.g. "6"

_fetch_source_tar \
  https://mirrors.kernel.org/pub/linux/kernel/v${LINUX_VERSION_MAJOR}.x/linux-${LINUX_VERSION}.tar.xz \
  "$LINUX_SHA256" "$LINUX_SRC"

_pushd "$LINUX_SRC"

mkdir -p "$LLVMBOX_SYSROOT"
make \
  ARCH=$TARGET_ARCH \
  INSTALL_HDR_PATH="$LLVMBOX_SYSROOT" \
  headers_install

_popd
rm -rf "$LINUX_SRC"
