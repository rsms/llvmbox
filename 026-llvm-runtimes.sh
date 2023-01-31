#!/bin/bash
set -euo pipefail
SELF_SCRIPT="$(realpath "$0")"
source "$(dirname "$0")/config.sh"

CMAKE_C_FLAGS=()
CMAKE_LD_FLAGS=()
EXTRA_CMAKE_ARGS=( -Wno-dev )

IS_STEP1=true ; [ "${1:-}" = "-step2" ] && IS_STEP1=false

if ! $IS_STEP1; then
  CMAKE_C_FLAGS+=( "${STAGE2_LTO_CFLAGS[@]}" )
  CMAKE_LD_FLAGS+=( "${STAGE2_LTO_LDFLAGS[@]}" )
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LTO=Thin )
fi

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
      -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET_ARCH-linux-musl" \
    )
    CMAKE_C_FLAGS+=( --target=$TARGET_ARCH-linux-musl )
    CMAKE_LD_FLAGS+=( -L"$LLVM_STAGE1"/lib/$TARGET_ARCH-unknown-linux-gnu )
    ;;
esac

CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

$LLVMBOX_ENABLE_LTO &&
  rm -rf "$BUILD_DIR/llvm-runtimes"

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
  -DCMAKE_COMPILE_FLAGS="$CMAKE_C_FLAGS" \
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
  \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBUNWIND_USE_COMPILER_RT=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]}"


echo "———————————————————————— build ————————————————————————"
ninja cxx cxxabi unwind

if $IS_STEP1; then
  # verify non-lto
  ( rm -rf x && mkdir x && cd x && ar x ../lib/libc++.a
    file regex.cpp.o | grep -qv "LLVM" || _err "non-lto build is actually LTO" )
  echo "———————————————————————— install ————————————————————————"
  rm -rf "$LIBCXX_STAGE2"
  mkdir -p "$LIBCXX_STAGE2"
  DESTDIR="$LIBCXX_STAGE2" ninja install-cxx install-cxxabi install-unwind
  rm -f "$LIBCXX_STAGE2/lib/libc++experimental.a"
  if $LLVMBOX_ENABLE_LTO; then
    _popd
    echo "———————————————————————— step2 ————————————————————————"
    exec bash "$SELF_SCRIPT" -step2
  fi
else
  # verify lto
  ( rm -rf x && mkdir x && cd x && ar x ../lib/libc++.a
    file regex.cpp.o | grep -q "LLVM" || _err "lto build is not LTO" )
  echo "———————————————————————— install lib-lto ————————————————————————"
  rm -rf "$LIBCXX_STAGE2/lib-lto"
  mkdir -p "$LIBCXX_STAGE2/lib-lto"
  install -vm 0644 lib/libc++.a    "$LIBCXX_STAGE2/lib-lto/"
  install -vm 0644 lib/libc++abi.a "$LIBCXX_STAGE2/lib-lto/"
  install -vm 0644 lib/libunwind.a "$LIBCXX_STAGE2/lib-lto/"
fi
