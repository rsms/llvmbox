#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

CMAKE_C_FLAGS=()
CMAKE_LD_FLAGS=()
EXTRA_CMAKE_ARGS=( -Wno-dev )

case "$HOST_SYS" in
  Darwin)
    EXTRA_CMAKE_ARGS+=(
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET_SYS_VERSION \
      -DCMAKE_OSX_SYSROOT="$LLVMBOX_SYSROOT" \
    )
    CMAKE_C_FLAGS+=(
      -I"$LLVMBOX_SYSROOT/include" \
      -w \
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
    )
    CMAKE_LD_FLAGS+=(
      -L"$LLVMBOX_SYSROOT/lib" \
      -L"$LLVM_STAGE1/lib" \
    )
    ;;
  Linux)
    EXTRA_CMAKE_ARGS+=(
      -DLIBCXX_HAS_MUSL_LIBC=ON \
    )
    ;;
esac

CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$BUILD_DIR/llvm-runtimes"
_pushd "$BUILD_DIR/llvm-runtimes"

cmake -G Ninja "$LLVM_SRC/runtimes" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX= \
  -DCMAKE_SYSROOT="$LLVMBOX_SYSROOT" \
  \
  -DCMAKE_C_COMPILER="$STAGE2_CC" \
  -DCMAKE_CXX_COMPILER="$STAGE2_CXX" \
  -DCMAKE_ASM_COMPILER="$STAGE2_ASM" \
  -DCMAKE_AR="$STAGE2_AR" \
  -DCMAKE_RANLIB="$STAGE2_RANLIB" \
  -DCMAKE_LINKER="$STAGE2_LD" \
  \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_DIR="$LLVM_SRC/llvm" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXX_ABI_VERSION=1 \
  -DLIBCXX_USE_COMPILER_RT=ON \
  \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBUNWIND_USE_COMPILER_RT=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]}"


echo "———————————————————————— build ————————————————————————"
ninja cxx cxxabi unwind

echo "———————————————————————— install ————————————————————————"
rm -rf "$LIBCXX_STAGE2"
mkdir -p "$LIBCXX_STAGE2"
DESTDIR="$LIBCXX_STAGE2" ninja install-cxx install-cxxabi install-unwind
