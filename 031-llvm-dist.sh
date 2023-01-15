#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

# useful documentation
#   https://llvm.org/docs/HowToCrossCompileLLVM.html#hacks
#   https://libcxx.llvm.org/BuildingLibcxx.html
#   https://libcxx.llvm.org/UsingLibcxx.html#alternate-libcxx

LLVM_DIST_COMPONENTS=(
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


LLVM_CFLAGS=( "${TARGET_CFLAGS[@]}" \
  -I"$ZLIB_DIST/include" \
)
LLVM_CXXFLAGS=( "${TARGET_CXXFLAGS[@]}" \
  -I"$ZLIB_DIST/include" \
)
LLVM_LDFLAGS=( "${TARGET_CXX_LDFLAGS[@]}" \
  -L"$ZLIB_DIST/lib" \
  -L"$LLVM_HOST/lib/$TARGET" \
)


echo LLVM_CFLAGS=${LLVM_CFLAGS[@]}
echo LLVM_CXXFLAGS=${LLVM_CXXFLAGS[@]}
echo LLVM_LDFLAGS=${LLVM_LDFLAGS[@]}


EXTRA_CMAKE_ARGS=()  # extra args added to cmake invocation (depending on target)
LLVM_RUNTIME_TARGETS=$TARGET

case "$TARGET_SYS" in
  apple|darwin|macos|ios)
    LLVM_RUNTIME_TARGETS=$TARGET_ARCH-apple-darwin
    EXTRA_CMAKE_ARGS+=( -DRUNTIMES_BUILD_ALLOW_DARWIN=ON )
    ;;
  linux)
    LLVM_LDFLAGS+=( -static )
    ;;
esac


mkdir -p "$BUILD_DIR/llvm-dist-build"
_pushd "$BUILD_DIR/llvm-dist-build"

LLVM_CFLAGS="${LLVM_CFLAGS[@]}"
LLVM_CXXFLAGS="${LLVM_CXXFLAGS[@]}"
LLVM_LDFLAGS="${LLVM_LDFLAGS[@]}"



CMAKE_C_COMPILER="$TARGET_CC;$(_array_join ";" "${LLVM_CFLAGS[@]}")"
CMAKE_CXX_COMPILER="$TARGET_CXX;$(_array_join ";" "${LLVM_CXXFLAGS[@]}")"
CMAKE_ASM_COMPILER="$TARGET_ASM;$(_array_join ";" "${LLVM_LDFLAGS[@]}")"

# note: for darwin target,
# LLVM_RUNTIME_TARGETS seem to conflict with LLVM_DEFAULT_TARGET_TRIPLE

cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_SYSTEM_NAME="$TARGET_CMAKE_SYSTEM_NAME" \
  -DCMAKE_INSTALL_PREFIX="$LLVM_DIST" \
  -DCMAKE_PREFIX_PATH="$LLVM_DIST" \
  \
  -DCMAKE_C_COMPILER="$CMAKE_C_COMPILER" \
  -DCMAKE_CXX_COMPILER="$CMAKE_CXX_COMPILER" \
  -DCMAKE_ASM_COMPILER="$CMAKE_ASM_COMPILER" \
  -DCMAKE_RC_COMPILER="$TARGET_RC" \
  -DCMAKE_AR="$TARGET_AR" \
  -DCMAKE_RANLIB="$TARGET_RANLIB" \
  \
  -DCMAKE_C_FLAGS="$LLVM_CFLAGS" \
  -DCMAKE_CXX_FLAGS="$LLVM_CXXFLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$LLVM_LDFLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$LLVM_LDFLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$LLVM_LDFLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;Mips;RISCV;WebAssembly;X86" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_RUNTIME_TARGETS="$LLVM_RUNTIME_TARGETS" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_DIST_COMPONENTS[@]}")" \
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
  -DLLVM_TABLEGEN="$LLVM_HOST/bin/llvm-tblgen" \
  \
  -DLLVM_ENABLE_ZLIB=1 \
  -DZLIB_LIBRARY="$ZLIB_DIST/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_DIST/include" \
  -DLLVM_ENABLE_ZSTD=OFF \
  \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_ENABLE_OBJC_REWRITER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_TABLEGEN="$LLVM_HOST/bin/clang-tblgen" \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DLIBCLANG_BUILD_STATIC=ON \
  \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
  -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
  -DLIBCXX_ENABLE_RTTI=OFF \
  -DLIBCXX_ENABLE_EXCEPTIONS=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_LINK_TESTS_WITH_SHARED_LIBCXX=OFF \
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
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]}"


ninja distribution


rm -rf "$LLVM_DIST"
mkdir -p "$LLVM_DIST"

echo "installing -> ${LLVM_DIST##$PWD0/}"
ninja \
  install-distribution \
  install-lld \
  install-builtins \
  install-compiler-rt \
  install-llvm-objcopy \
  install-llvm-libraries \
  install-llvm-headers \
  install-libclang \
  install-clang-libraries \
  install-clang-headers
