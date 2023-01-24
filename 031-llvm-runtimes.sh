#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

CMAKE_C_FLAGS=( "${STAGE2_CFLAGS[@]}" )
CMAKE_LD_FLAGS=( "${STAGE2_LDFLAGS[@]}" )
EXTRA_CMAKE_ARGS=( -Wno-dev )

# CMAKE_LD_FLAGS+=( -nostdlib++ -L"$LLVM_STAGE1/lib" -lc++ -lc++abi )


CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$BUILD_DIR/llvm-runtimes"
_pushd "$BUILD_DIR/llvm-runtimes"

cmake -G Ninja "$LLVM_SRC/runtimes" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX= \
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
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLIBCXX_HAS_MUSL_LIBC=ON \
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
  \
  "${EXTRA_CMAKE_ARGS[@]}"


echo "———————————————————————— cxx ————————————————————————"
ninja cxx
echo "———————————————————————— cxxabi ————————————————————————"
ninja cxxabi
echo "———————————————————————— unwind ————————————————————————"
ninja unwind

echo "———————————————————————— install ————————————————————————"
DESTDIR=$OUT_DIR/libcxx-stage2
mkdir -p "$DESTDIR"
DESTDIR=$DESTDIR ninja install-cxx install-cxxabi install-unwind

# $ git clone https://github.com/llvm/llvm-project.git
# $ cd llvm-project
# $ mkdir build
# $ cmake -G Ninja -S runtimes -B build -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" # Configure
# $ ninja -C build cxx cxxabi unwind                                                        # Build
# $ ninja -C build check-cxx check-cxxabi check-unwind                                      # Test
# $ ninja -C build install-cxx install-cxxabi install-unwind                                # Install
