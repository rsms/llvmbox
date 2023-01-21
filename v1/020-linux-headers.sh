#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

LINUX_VERSION_MAJOR=${LINUX_VERSION%%.*}  # e.g. "6"

_fetch_source_tar \
  https://mirrors.kernel.org/pub/linux/kernel/v${LINUX_VERSION_MAJOR}.x/linux-${LINUX_VERSION}.tar.xz \
  "$LINUX_SHA256" "$LINUX_SRC"

_pushd "$LINUX_SRC"

make headers_install INSTALL_HDR_PATH="$LINUX_HEADERS_DESTDIR"
