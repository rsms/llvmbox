#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"

ZIGBS_GIT=960661847143ebdcac4728472169f8acf0851b6f
ZIGBS_SHA256=fb5208bed8ecd738f8916bfb797c0511c2c81f64f6b0bae119c5d32ca8d256f6
ZIGBS_SRC=${ZIGBS_SRC:-$BUILD_DIR/src/zig-bootstrap}
ZIGBS_BUILD_DIR=${ZIGBS_BUILD_DIR:-$BUILD_DIR/zig}

_fetch_source_tar \
  https://github.com/ziglang/zig-bootstrap/archive/$ZIGBS_GIT.tar.gz \
  "$ZIGBS_SHA256" "$ZIGBS_SRC" "$DOWNLOAD_DIR/zig-$ZIGBS_GIT.tar.gz"

_pushd "$ZIGBS_SRC"

# TARGET examples: riscv64-linux-gnu
# MCPU examples: baseline, native, generic+v7a, arm1176jzf_s
TARGET="${1:-$HOST_ARCH-linux-gnu}"
MCPU="${2:-baseline}"
NPROC=${NPROC:-$(nproc)}

# x86_64 mcpu:
#   nocona, core2, penryn, bonnell, atom, silvermont, slm, goldmont, goldmont-plus,
#   tremont, nehalem, corei7, westmere, sandybridge, corei7-avx, ivybridge,
#   core-avx-i, haswell, core-avx2, broadwell, skylake, skylake-avx512, skx,
#   cascadelake, cooperlake, cannonlake, icelake-client, rocketlake,
#   icelake-server, tigerlake, sapphirerapids, alderlake, knl, knm, k8, athlon64,
#   athlon-fx, opteron, k8-sse3, athlon64-sse3, opteron-sse3, amdfam10, barcelona,
#   btver1, btver2, bdver1, bdver2, bdver3, bdver4, znver1, znver2, znver3, x86-64,
#   x86-64-v2, x86-64-v3, x86-64-v4

ROOTDIR="$(pwd)"

# ZIG_VERSION="0.11.0-dev.995+7350f0d9b"
eval $(grep '^ZIG_VERSION=' build)
[ -n "$ZIG_VERSION" ] || _err "ZIG_VERSION not set from ./build"

TARGET_OS_AND_ABI=${TARGET#*-} # Example: linux-gnu

# Here we map the OS from the target triple to the value that CMake expects.
TARGET_OS_CMAKE=${TARGET_OS_AND_ABI%-*} # Example: linux
case $TARGET_OS_CMAKE in
  macos) TARGET_OS_CMAKE="Darwin";;
  freebsd) TARGET_OS_CMAKE="FreeBSD";;
  windows) TARGET_OS_CMAKE="Windows";;
  linux) TARGET_OS_CMAKE="Linux";;
  native) TARGET_OS_CMAKE="";;
esac

# First build the libraries for Zig to link against, as well as native `llvm-tblgen`.
mkdir -p "$ZIGBS_BUILD_DIR/build-llvm-host"
cd "$ZIGBS_BUILD_DIR/build-llvm-host"
cmake "$ROOTDIR/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ZIGBS_BUILD_DIR/host" \
  -DCMAKE_PREFIX_PATH="$ZIGBS_BUILD_DIR/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="lld;clang" \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_GO_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
  -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
  -DLLVM_TOOL_LTO_BUILD=OFF \
  -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
  -DCLANG_BUILD_TOOLS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
  -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
  -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
  -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
  -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
  -DCLANG_TOOL_LIBCLANG_BUILD=OFF
cmake --build . --target install -j $NPROC

# Now we build Zig, still with system C/C++ compiler, linking against LLVM,
# Clang, LLD we just built from source.
mkdir -p "$ZIGBS_BUILD_DIR/build-zig-host"
cd "$ZIGBS_BUILD_DIR/build-zig-host"
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ZIGBS_BUILD_DIR/host" \
  -DCMAKE_PREFIX_PATH="$ZIGBS_BUILD_DIR/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install -j $NPROC

# Now we have Zig as a cross compiler.
ZIG="$ZIGBS_BUILD_DIR/host/bin/zig"

# First cross compile zlib for the target, as we need the LLVM linked into
# the final zig binary to have zlib support enabled.
mkdir -p "$ZIGBS_BUILD_DIR/build-zlib-$TARGET-$MCPU"
cd "$ZIGBS_BUILD_DIR/build-zlib-$TARGET-$MCPU"
cmake "$ROOTDIR/zlib" \
  -DCMAKE_INSTALL_PREFIX="$ZIGBS_BUILD_DIR/$TARGET-$MCPU" \
  -DCMAKE_PREFIX_PATH="$ZIGBS_BUILD_DIR/$TARGET-$MCPU" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
  -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_RC_COMPILER="$ZIGBS_BUILD_DIR/host/bin/llvm-rc" \
  -DCMAKE_AR="$ZIGBS_BUILD_DIR/host/bin/llvm-ar" \
  -DCMAKE_RANLIB="$ZIGBS_BUILD_DIR/host/bin/llvm-ranlib"
cmake --build . --target install -j $NPROC

# Same deal for zstd.
# The build system for zstd is whack so I just put all the files here.
mkdir -p "$ZIGBS_BUILD_DIR/$TARGET-$MCPU/lib"
cp "$ROOTDIR/zstd/lib/zstd.h" "$ZIGBS_BUILD_DIR/$TARGET-$MCPU/include/zstd.h"
cd "$ZIGBS_BUILD_DIR/$TARGET-$MCPU/lib"
$ZIG build-lib \
  --name zstd \
  -target $TARGET \
  -mcpu=$MCPU \
  -fstrip -OReleaseFast \
  -lc \
  "$ROOTDIR/zstd/lib/decompress/zstd_ddict.c" \
  "$ROOTDIR/zstd/lib/decompress/zstd_decompress.c" \
  "$ROOTDIR/zstd/lib/decompress/huf_decompress.c" \
  "$ROOTDIR/zstd/lib/decompress/huf_decompress_amd64.S" \
  "$ROOTDIR/zstd/lib/decompress/zstd_decompress_block.c" \
  "$ROOTDIR/zstd/lib/compress/zstdmt_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_opt.c" \
  "$ROOTDIR/zstd/lib/compress/hist.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_ldm.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_fast.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_literals.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_double_fast.c" \
  "$ROOTDIR/zstd/lib/compress/huf_compress.c" \
  "$ROOTDIR/zstd/lib/compress/fse_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_lazy.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_sequences.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_superblock.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_compress.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_decompress.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_common.c" \
  "$ROOTDIR/zstd/lib/common/entropy_common.c" \
  "$ROOTDIR/zstd/lib/common/pool.c" \
  "$ROOTDIR/zstd/lib/common/threading.c" \
  "$ROOTDIR/zstd/lib/common/zstd_common.c" \
  "$ROOTDIR/zstd/lib/common/xxhash.c" \
  "$ROOTDIR/zstd/lib/common/debug.c" \
  "$ROOTDIR/zstd/lib/common/fse_decompress.c" \
  "$ROOTDIR/zstd/lib/common/error_private.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/zdict.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/divsufsort.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/fastcover.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/cover.c"

# Rebuild LLVM with Zig.
mkdir -p "$ZIGBS_BUILD_DIR/build-llvm-$TARGET-$MCPU"
cd "$ZIGBS_BUILD_DIR/build-llvm-$TARGET-$MCPU"
cmake "$ROOTDIR/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ZIGBS_BUILD_DIR/$TARGET-$MCPU" \
  -DCMAKE_PREFIX_PATH="$ZIGBS_BUILD_DIR/$TARGET-$MCPU" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
  -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_RC_COMPILER="$ZIGBS_BUILD_DIR/host/bin/llvm-rc" \
  -DCMAKE_AR="$ZIGBS_BUILD_DIR/host/bin/llvm-ar" \
  -DCMAKE_RANLIB="$ZIGBS_BUILD_DIR/host/bin/llvm-ranlib" \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_ENABLE_PROJECTS="lld;clang" \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_ENABLE_ZLIB=FORCE_ON \
  -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -DLLVM_USE_STATIC_ZSTD=ON \
  -DLLVM_TABLEGEN="$ZIGBS_BUILD_DIR/host/bin/llvm-tblgen" \
  -DLLVM_BUILD_TOOLS=OFF \
  -DLLVM_BUILD_STATIC=ON \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_GO_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
  -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
  -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
  -DLLVM_TOOL_LTO_BUILD=OFF \
  -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
  -DCLANG_TABLEGEN="$ZIGBS_BUILD_DIR/build-llvm-host/bin/clang-tblgen" \
  -DCLANG_BUILD_TOOLS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_ENABLE_ARCMT=ON \
  -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
  -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
  -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
  -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
  -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
  -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
  -DLIBCLANG_BUILD_STATIC=ON
cmake --build . --target install -j $NPROC

# Finally, we can cross compile Zig itself, with Zig.
cd "$ROOTDIR/zig"
$ZIG build \
  --prefix "$ZIGBS_BUILD_DIR/zig-$TARGET-$MCPU" \
  --search-prefix "$ZIGBS_BUILD_DIR/$TARGET-$MCPU" \
  -Dstatic-llvm \
  -Drelease \
  -Dstrip \
  -Dtarget="$TARGET" \
  -Dcpu="$MCPU" \
  -Dversion-string="$ZIG_VERSION"
