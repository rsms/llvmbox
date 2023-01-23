#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$PROJECT/utils/require-zig-src.sh"

LINUX_HEADERS=$BUILD_DIR/linux-headers

[ "$HOST_SYS" = Linux ] || _err "must run this script on Linux"

# —————————————————————————————————————————————————————————————————————————————————————

_fetch_source_tar \
  https://mirrors.kernel.org/pub/linux/kernel/v${LINUX_VERSION_MAJOR}.x/linux-${LINUX_VERSION}.tar.xz \
  "$LINUX_SHA256" "$LINUX_SRC"

_pushd "$LINUX_SRC"

rm -rf "$LINUX_HEADERS"
mkdir -p "$LINUX_HEADERS"

for arch in arm arm64 riscv x86; do
  echo make ARCH=$arch INSTALL_HDR_PATH="$LINUX_HEADERS/$arch" headers_install
       make ARCH=$arch INSTALL_HDR_PATH="$LINUX_HEADERS/$arch" headers_install
done

_popd
rm -rf "$LINUX_SRC"

# echo "creating $LINUX_HEADERS.tar.xz"
# XZ_OPT='-T0' tar \
#   -C "$LINUX_HEADERS" \
#   -cJpf "$LINUX_HEADERS.tar.xz" \
#   --checkpoint=1000 --checkpoint-action=echo="%T" --totals .

# —————————————————————————————————————————————————————————————————————————————————————
# use zig's tools (see https://github.com/ziglang/zig/wiki/Updating-libc)

_pushd "$ZIGSRC"

rm -rf "$SYSROOT_TEMPLATE"/libc/include/*-linux
zig run tools/update-linux-headers.zig -- \
  --search-path "$LINUX_HEADERS" \
  --out "$SYSROOT_TEMPLATE"/libc/include

# x-linux-any -> x-linux
_pushd "$SYSROOT_TEMPLATE"/libc/include
for f in *-linux-any; do mv -v $f ${f/-any/}; done
