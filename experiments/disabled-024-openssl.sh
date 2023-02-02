#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"
#
# see https://wiki.openssl.org/index.php/Compilation_and_Installation
#

_fetch_source_tar \
  https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz \
  "$OPENSSL_SHA256" "$OPENSSL_SRC"

_pushd "$OPENSSL_SRC"

CC="$STAGE2_CC" \
LD="$STAGE2_LD" \
AR="$STAGE2_AR" \
RANLIB="$STAGE2_RANLIB" \
CFLAGS="${STAGE2_CFLAGS[@]}" \
LDFLAGS="${STAGE2_LDFLAGS[@]}" \
./config \
  --prefix=/ \
  --libdir=lib \
  --openssldir=/etc/ssl \
  no-zlib \
  no-shared \
  no-async \
  no-comp \
  no-idea \
  no-mdc2 \
  no-rc5 \
  no-ec2m \
  no-sm2 \
  no-sm4 \
  no-ssl2 \
  no-ssl3 \
  no-seed \
  no-weak-ssl-ciphers \
  -Wa,--noexecstack

make -j$NCPU

rm -rf "$OPENSSL_STAGE2"
mkdir -p "$OPENSSL_STAGE2"
make DESTDIR="$OPENSSL_STAGE2" -j$NCPU install_sw

rm -rf "$OPENSSL_STAGE2"/bin "$OPENSSL_STAGE2"/lib/pkgconfig

_popd
rm -rf "$OPENSSL_SRC"
