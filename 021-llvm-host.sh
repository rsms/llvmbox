#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

# build llvm host compiler
# https://llvm.org/docs/BuildingADistribution.html

# TODO: consider a "stage2" build a la clang/cmake/caches/Fuchsia.cmake
#       see experiments/stage2.sh

LLVM_HOST_BUILD=$BUILD_DIR/llvm-host-build
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
  clang-format \
  clang-resource-headers \
  builtins \
  runtimes \
)

if [ "$(cat "$LLVM_HOST/version" 2>/dev/null)" = "$LLVM_RELEASE" ]; then
  echo "${LLVM_HOST##$PWD0/}: up-to-date"
  exit
fi

mkdir -p "$LLVM_HOST_BUILD"
_pushd "$LLVM_HOST_BUILD"

CMAKE_EXE_LINKER_FLAGS=()
# case "$HOST_SYS" in
#   Linux) CMAKE_EXE_LINKER_FLAGS+=( -static ) ;;
# esac

CMAKE_C_FLAGS="-w"
# note: -w silences warnings (nothing we can do about those)
# -fcompare-debug-second silences "note: ..." in GCC.
case "$(${CC:-cc} --version || true)" in
  *'Free Software Foundation'*) # GCC
    CMAKE_C_FLAGS="$CMAKE_C_FLAGS -fcompare-debug-second"
    CMAKE_C_FLAGS="$CMAKE_C_FLAGS -Wno-misleading-indentation"
    ;;
esac

CMAKE_ARGS=()
if [ "$HOST_SYS" = "Darwin" ]; then
  CMAKE_ARGS+=( -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON )
fi

echo "configuring llvm ... (${PWD##$PWD0/}/cmake-config.log)"
cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_HOST" \
  -DCMAKE_PREFIX_PATH="$LLVM_HOST" \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="${CMAKE_EXE_LINKER_FLAGS[@]}" \
  \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;Mips;RISCV;WebAssembly;X86" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_HOST_COMPONENTS[@]}")" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
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
  -DLLVM_ENABLE_ZSTD=OFF \
  \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_ENABLE_OBJC_REWRITER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DLIBCLANG_BUILD_STATIC=ON \
  -DLIBCLANG_BUILD_STATIC=ON \
  -DENABLE_SHARED=OFF \
  \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXX_LINK_TESTS_WITH_SHARED_LIBCXX=OFF \
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
  "${CMAKE_ARGS[@]}" \
  > cmake-config.log || _err "cmake failed. See $PWD/cmake-config.log"

# echo "building libc++ ..."
# # ninja cxx cxxabi
# ninja install-cxx-stripped install-cxxabi-stripped

# -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON  works on macos, not ubuntu

echo "building llvm ..."
ninja distribution
# note: the "distribution" target builds only LLVM_DISTRIBUTION_COMPONENTS

rm -rf "$LLVM_HOST"
mkdir -p "$LLVM_HOST"

echo "installing llvm -> ${LLVM_HOST##$PWD0/} ..."
ninja install-distribution install-lld \
  install-builtins \
  install-compiler-rt \
  install-llvm-objcopy

echo "installing llvm libs -> ${LLVM_HOST##$PWD0/} ..."
ninja install-llvm-libraries install-llvm-headers

echo "installing clang libs -> ${LLVM_HOST##$PWD0/} ..."
ninja install-libclang install-clang-libraries install-clang-headers

echo "$LLVM_RELEASE" > "$LLVM_HOST/version"

