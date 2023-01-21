#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

ARCHIVE=$TARGET_ARCH-linux-musl-native.tgz
echo "fetch https://musl.cc/SHA512SUMS"
SHA512=$(wget -q -O - "https://musl.cc/SHA512SUMS" | grep "$ARCHIVE" | cut -d' ' -f1)
_download "https://musl.cc/$ARCHIVE" "$DOWNLOAD_DIR/$ARCHIVE" "$SHA512"
_extract_tar "$DOWNLOAD_DIR/$ARCHIVE" "$BUILD_DIR/gcc-musl"

# # delete all .so libs that have corresponding .a libs
# _pushd "$BUILD_DIR/gcc-musl/lib"
# for n in $(find . -name '*.so'); do
#   [ -f ${n%.*}.a ] && rm -v $n
# done
