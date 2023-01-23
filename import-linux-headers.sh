#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$HOST_SYS" = Linux ] || _err "must run this script on Linux"

_fetch_source_tar \
  https://mirrors.kernel.org/pub/linux/kernel/v${LINUX_VERSION_MAJOR}.x/linux-${LINUX_VERSION}.tar.xz \
  "$LINUX_SHA256" "$LINUX_SRC"

_pushd "$LINUX_SRC"

for arch in arm arm64 riscv x86; do
  llvm_arch=${arch/arm64/aarch64}
  llvm_arch=${llvm_arch/x86/x86_64}
  DESTDIR="$SYSROOTS_DIR"/include/${llvm_arch}-linux
  rm -rf "$DESTDIR.tmp"
  echo make ARCH=$arch INSTALL_HDR_PATH="$DESTDIR.tmp" headers_install
       make ARCH=$arch INSTALL_HDR_PATH="$DESTDIR.tmp" headers_install
  rm -rf "$DESTDIR"
  mv "$DESTDIR.tmp/include" "$DESTDIR"
  rm -rf "$DESTDIR.tmp"
done

_popd
rm -rf "$LINUX_SRC"
