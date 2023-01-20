#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

# build llvm host compiler
# https://llvm.org/docs/BuildingADistribution.html

# TODO: consider a "stage2" build a la clang/cmake/caches/Fuchsia.cmake
#       see experiments/stage2.sh

LLVM_HOST_COMPONENTS=(
  dsymutil \
  llvm-ar \
  llvm-config \
  llvm-cov \
  llvm-dwarfdump \
  llvm-nm \
  llvm-objdump \
  llvm-profdata \
  llvm-ranlib \
  llvm-size \
  llvm-rc \
  clang \
  clang-resource-headers \
  builtins \
  runtimes \
)

mkdir -p "$BUILD_DIR/llvm-host-build"
_pushd "$BUILD_DIR/llvm-host-build"

CMAKE_C_FLAGS=( -w -I"$ZLIB_HOST/include" )
CMAKE_LD_FLAGS=( -L"$ZLIB_HOST/lib" )
EXTRA_CMAKE_EXE_LINKER_FLAGS=()
EXTRA_CMAKE_ARGS=()

case "$(${CC:-cc} --version || true)" in
  *'Free Software Foundation'*) # GCC
    # -fcompare-debug-second silences "note: ..." in GCC
    CMAKE_C_FLAGS+=( -fcompare-debug-second -Wno-misleading-indentation )
    ;;
esac

case "$HOST_SYS" in
  Darwin)
    LLVM_HOST_COMPONENTS+=( llvm-libtool-darwin )
    EXTRA_CMAKE_ARGS+=( \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=10.10 \
      -DCMAKE_SYSROOT=$MACOS_SDK \
      -DCMAKE_OSX_SYSROOT=$MACOS_SDK \
      -DDEFAULT_SYSROOT=$MACOS_SDK \
    )
    ;;
  Linux)
    CMAKE_C_FLAGS+=( -fPIC )
    # EXTRA_CMAKE_EXE_LINKER_FLAGS+=( -static )
    # EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LLD=ON )
    # # musl-host
    # EXTRA_CMAKE_ARGS+=( \
    #   -DLLVM_DEFAULT_TARGET_TRIPLE=$TARGET_ARCH-linux-musl \
    # )
    # CMAKE_C_FLAGS+=( \
    #   -nostdinc \
    #   -nostdlib \
    #   -ffreestanding \
    #   -isystem $MUSL_HOST/include \
    # )
    # CMAKE_LD_FLAGS+=( \
    #   -static \
    #   -nostdlib \
    #   -nodefaultlibs \
    #   -nostartfiles \
    #   -L$MUSL_HOST/lib -lc -lm \
    # )
    # EXTRA_CMAKE_EXE_LINKER_FLAGS+=( $MUSL_HOST/lib/crt1.o )
    ;;
esac

CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]}"
EXTRA_CMAKE_EXE_LINKER_FLAGS="${EXTRA_CMAKE_EXE_LINKER_FLAGS[@]}"

cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_HOST" \
  -DCMAKE_PREFIX_PATH="$LLVM_HOST" \
  \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS $EXTRA_CMAKE_EXE_LINKER_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;Mips;RISCV;X86" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_HOST_COMPONENTS[@]}")" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_GO_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  \
  -DLLVM_ENABLE_ZLIB=1 \
  -DZLIB_LIBRARY="$ZLIB_HOST/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_HOST/include" \
  \
  -DLLVM_ENABLE_ZSTD=OFF \
  \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_ENABLE_OBJC_REWRITER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_LINKER=lld \
  -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
  -DCLANG_PLUGIN_SUPPORT=OFF \
  \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
  -DLIBCXX_ENABLE_RTTI=OFF \
  -DLIBCXX_ENABLE_EXCEPTIONS=ON \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_LINK_TESTS_WITH_SHARED_LIBCXX=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXX_ABI_VERSION=1 \
  -DLIBCXX_USE_COMPILER_RT=ON \
  \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
  -DLIBCXXABI_LINK_TESTS_WITH_SHARED_LIBCXXABI=OFF \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  \
  -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_CAN_EXECUTE_TESTS=OFF \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=OFF \
  \
  "${EXTRA_CMAKE_ARGS[@]}"

# echo "building libc++ ..."
# # ninja cxx cxxabi
# ninja install-cxx-stripped install-cxxabi-stripped

# -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON  works on macos, not ubuntu

ninja distribution
# note: the "distribution" target builds only LLVM_DISTRIBUTION_COMPONENTS

rm -rf "$LLVM_HOST"
mkdir -p "$LLVM_HOST"

ninja \
  install-distribution \
  install-lld \
  install-builtins \
  install-compiler-rt \
  install-llvm-objcopy \
  install-llvm-tblgen \
  install-cxxabi

cp -a bin/clang-tblgen "$LLVM_HOST/bin/clang-tblgen"
ln -s llvm-objcopy "$LLVM_HOST/bin/llvm-strip"

echo "$LLVM_RELEASE" > "$LLVM_HOST/version"
