#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://github.com/michaelforney/samurai/releases/download/1.2/samurai-1.2.tar.gz \
  3b8cf51548dfc49b7efe035e191ff5e1963ebc4fe8f6064a5eefc5343eaf78a5 \
  "$BUILD_DIR/src/samurai"

_pushd "$BUILD_DIR/src/samurai"

patch -p1 < "$PROJECT/patches/samurai-CVE-2021-30218.patch"
patch -p1 < "$PROJECT/patches/samurai-CVE-2021-30219.patch"

CC="$STAGE2_CC" \
LD="$STAGE2_LD" \
AR="$STAGE2_AR" \
RANLIB="$STAGE2_RANLIB" \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
make -j$NCPU

"$STAGE2_STRIP" samu
mkdir -p "$LLVMBOX_DESTDIR"/{bin,share/man/man1}
install -v -m0755 samu "$LLVMBOX_DESTDIR/bin/samu"
ln -vsf samu "$LLVMBOX_DESTDIR/bin/ninja"

_popd
rm -rf "$BUILD_DIR/src/samurai"
