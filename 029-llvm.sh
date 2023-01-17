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


# echo LLVM_CFLAGS=${LLVM_CFLAGS[@]}
# echo LLVM_CXXFLAGS=${LLVM_CXXFLAGS[@]}
# echo LLVM_LDFLAGS=${LLVM_LDFLAGS[@]}


EXTRA_CMAKE_ARGS=()  # extra args added to cmake invocation (depending on target)
# LLVM_RUNTIME_TARGETS seem to conflict with LLVM_DEFAULT_TARGET_TRIPLE

case "$TARGET_SYS" in
  apple|darwin|macos|ios)
    EXTRA_CMAKE_ARGS+=(
      -DRUNTIMES_BUILD_ALLOW_DARWIN=ON \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=10.10 \
      -DCMAKE_LIBTOOL="$LLVM_HOST/bin/llvm-libtool-darwin" \
      \
      -DCOMPILER_RT_ENABLE_TVOS=OFF \
      -DCOMPILER_RT_ENABLE_WATCHOS=OFF \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      \
      -DLLVM_BUILTIN_TARGETS=default \
      -DLLVM_RUNTIME_TARGETS=default \
      \
      -DLIBUNWIND_ENABLE_SHARED=OFF \
      -DLIBUNWIND_USE_COMPILER_RT=ON \
      -DLIBCXXABI_ENABLE_SHARED=OFF \
      -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
      -DLIBCXXABI_INSTALL_LIBRARY=OFF \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DLIBCXX_ABI_VERSION=2 \
      -DLIBCXX_ENABLE_SHARED=OFF \
      -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DLIBCXX_USE_COMPILER_RT=ON \
      \
      -DRUNTIMES_CMAKE_ARGS="-DCMAKE_OSX_DEPLOYMENT_TARGET=10.10;-DCMAKE_OSX_ARCHITECTURES=arm64|x86_64" \
    )
    ;;
  linux)
    LLVM_LDFLAGS+=( -static )
    # EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LLD=ON )
    ;;
esac


mkdir -p "$BUILD_DIR/llvm-dist-build"
_pushd "$BUILD_DIR/llvm-dist-build"

LLVM_CFLAGS="${LLVM_CFLAGS[@]}"
LLVM_CXXFLAGS="${LLVM_CXXFLAGS[@]}"
LLVM_LDFLAGS="${LLVM_LDFLAGS[@]}"


# # force flags to be used by adding them to compiler commands
# CMAKE_C_COMPILER="$TARGET_CC;$(_array_join ";" "${LLVM_CFLAGS[@]}")"
# CMAKE_CXX_COMPILER="$TARGET_CXX;$(_array_join ";" "${LLVM_CXXFLAGS[@]}")"
# CMAKE_ASM_COMPILER="$TARGET_ASM;$(_array_join ";" "${LLVM_LDFLAGS[@]}")"
CMAKE_C_COMPILER="$TARGET_CC"
CMAKE_CXX_COMPILER="$TARGET_CXX"
CMAKE_ASM_COMPILER="$TARGET_ASM"


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
  -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64;RISCV;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_DIST_COMPONENTS[@]}")" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_STATIC_LINK_CXX_STDLIB=ON \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_PIC=OFF \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_ENABLE_LTO=ON \
  -DLLVM_ENABLE_UNWIND_TABLES=OFF \
  -DLLVM_USE_RELATIVE_PATHS_IN_FILES=ON \
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
  -DCLANG_ENABLE_STATIC_ANALYZER=ON \
  -DCLANG_TABLEGEN="$LLVM_HOST/bin/clang-tblgen" \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_LINKER=lld \
  -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
  -DCLANG_PLUGIN_SUPPORT=OFF \
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
  \
  -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_CAN_EXECUTE_TESTS=OFF \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
  \
  -DENABLE_X86_RELAX_RELOCATIONS=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]}"


ninja
rm -rf "$LLVM_DIST" ; mkdir -p "$LLVM_DIST"
ninja install

# ninja distribution
# rm -rf "$LLVM_DIST" ; mkdir -p "$LLVM_DIST"
# ninja \
#   install-distribution \
#   install-lld \
#   install-builtins \
#   install-compiler-rt \
#   install-llvm-objcopy \
#   install-llvm-libraries \
#   install-llvm-headers \
#   install-libclang \
#   install-clang-libraries \
#   install-clang-headers

# copy-merge dependencies into llvm root
for lib in \
  "$ZLIB_DIST" \
  "$ZSTD_DESTDIR" \
  "$XC_DESTDIR" \
  "$OPENSSL_DESTDIR" \
  "$LIBXML2_DESTDIR" \
  "$XAR_DESTDIR"
do
  [ -d "$lib" ] || continue
  echo "installing $lib -> $LLVM_DIST"
  rsync -au "$lib/" "$LLVM_DIST/"
done
