#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_fetch_source_tar \
  https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
  "$ZSTD_SHA256" "$ZSTD_SRC"

_pushd "$ZSTD_SRC"

patch -p0 < "$PROJECT/patches/zstd-001-disable-shlib.patch"

SOURCES=(
  lib/decompress/zstd_ddict.c \
  lib/decompress/zstd_decompress.c \
  lib/decompress/huf_decompress.c \
  lib/decompress/huf_decompress_amd64.S \
  lib/decompress/zstd_decompress_block.c \
  lib/compress/zstdmt_compress.c \
  lib/compress/zstd_opt.c \
  lib/compress/hist.c \
  lib/compress/zstd_ldm.c \
  lib/compress/zstd_fast.c \
  lib/compress/zstd_compress_literals.c \
  lib/compress/zstd_double_fast.c \
  lib/compress/huf_compress.c \
  lib/compress/fse_compress.c \
  lib/compress/zstd_lazy.c \
  lib/compress/zstd_compress.c \
  lib/compress/zstd_compress_sequences.c \
  lib/compress/zstd_compress_superblock.c \
  lib/deprecated/zbuff_compress.c \
  lib/deprecated/zbuff_decompress.c \
  lib/deprecated/zbuff_common.c \
  lib/common/entropy_common.c \
  lib/common/pool.c \
  lib/common/threading.c \
  lib/common/zstd_common.c \
  lib/common/xxhash.c \
  lib/common/debug.c \
  lib/common/fse_decompress.c \
  lib/common/error_private.c \
  lib/dictBuilder/zdict.c \
  lib/dictBuilder/divsufsort.c \
  lib/dictBuilder/fastcover.c \
  lib/dictBuilder/cover.c \
)
OBJECTS=()
for f in "${SOURCES[@]}"; do
  OBJECTS+=( "$f.o" )
  echo "compile $f"
  "$STAGE2_CC" "${STAGE2_CFLAGS[@]}" "${STAGE2_LTO_CFLAGS[@]}" -O2 -c "$f" -o "$f.o" &
done
wait

# DESTDIR="$LLVMBOX_SYSROOT"
DESTDIR="$ZSTD_STAGE2"; rm -rf "$ZSTD_STAGE2"; mkdir -p "$ZSTD_STAGE2"/{lib,include}

echo "create archive $DESTDIR/lib/libzstd.a"
"$STAGE2_AR" cr "$DESTDIR/lib/libzstd.a" "${OBJECTS[@]}"
"$STAGE2_RANLIB" "$DESTDIR/lib/libzstd.a"

echo "install header $DESTDIR/include/zstd.h"
install -m 0644 lib/zstd.h "$DESTDIR/include/zstd.h"

_popd
rm -rf "$ZSTD_SRC"
