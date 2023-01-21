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
  "$HOST_STAGE2_CC" --target=$TARGET -O2 -c "$f" -o "$f.o" &
done
wait

echo "create archive $LLVMBOX_SYSROOT/lib/libzstd.a"
"$HOST_STAGE2_AR" cr "$LLVMBOX_SYSROOT/lib/libzstd.a" "${OBJECTS[@]}"
"$HOST_STAGE2_RANLIB" "$LLVMBOX_SYSROOT/lib/libzstd.a"

echo "install header $LLVMBOX_SYSROOT/include/zstd.h"
cp lib/zstd.h "$LLVMBOX_SYSROOT/include/zstd.h"

# CC=$HOST_STAGE2_CC \
# LD=$HOST_STAGE2_LD \
# AR=$HOST_STAGE2_AR \
# CFLAGS="-O2 -DBACKTRACE_ENABLE=0 -flto=auto -ffat-lto-objects" \
# CXXFLAGS="-O2 -DBACKTRACE_ENABLE=0 -flto=auto -ffat-lto-objects" \
# make HAVE_PTHREAD=1 ZSTD_LIB_MINIFY=1 prefix= -j$(nproc) lib-mt
# install -vDm 0644 lib/zstd.h "$LLVMBOX_SYSROOT"/include/zstd.h
# install -vDm 0644 lib/libzstd.a "$LLVMBOX_SYSROOT"/lib/libzstd.a

_popd
rm -rf "$ZSTD_SRC"
