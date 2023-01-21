#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

ARCHIVE=$TARGET_ARCH-linux-musl-native.tgz
echo "fetch https://musl.cc/SHA512SUMS"
SHA512=$(wget -q -O - "https://musl.cc/SHA512SUMS" | grep "$ARCHIVE" | cut -d' ' -f1)
_download "https://musl.cc/$ARCHIVE" "$DOWNLOAD_DIR/$ARCHIVE" "$SHA512"
_extract_tar "$DOWNLOAD_DIR/$ARCHIVE" "$OUT_DIR/gcc-musl"

# rm -v "$OUT_DIR"/gcc-musl/lib/*.so "$OUT_DIR"/gcc-musl/lib/*.so.*

# # delete all .so libs that have corresponding .a libs
# _pushd "$BUILD_DIR/gcc-musl/lib"
# for n in $(find . -name '*.so'); do
#   [ -f ${n%.*}.a ] && rm -v $n
# done
