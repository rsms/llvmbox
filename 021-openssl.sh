#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

# xar DEPENDS_ON openssl

_fetch_source_tar \
      https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz \
      $OPENSSL_SHA256 "$OPENSSL_SRC"

_pushd "$OPENSSL_SRC"

CC=$HOST_CC \
LD=$HOST_LD \
CFLAGS="${TARGET_CFLAGS[@]}" \
LDFLAGS="${TARGET_LDFLAGS[@]}" \
./config \
  --prefix=/ \
  --libdir=lib \
  --openssldir=/etc/ssl \
  no-shared \
  no-zlib \
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

make -j$(nproc)

rm -rf "$OPENSSL_DESTDIR"
mkdir -p "$OPENSSL_DESTDIR"
make DESTDIR="$OPENSSL_DESTDIR" install_sw

_popd
rm -rf "$OPENSSL_SRC"
echo "$OPENSSL_VERSION" > "$OPENSSL_DESTDIR/version"
