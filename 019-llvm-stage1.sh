#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVM_SRC="$LLVM_SRC_STAGE1"

LLVM_STAGE1_COMPONENTS=(
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

mkdir -p "$BUILD_DIR/llvm-stage1-build"
_pushd "$BUILD_DIR/llvm-stage1-build"

CMAKE_C_FLAGS=( -w -I"$ZLIB_STAGE1/include" )
CMAKE_LD_FLAGS=( -L"$ZLIB_STAGE1/lib" )
EXTRA_CMAKE_ARGS=()

case "$HOST_SYS" in
  Darwin)
    LLVM_STAGE1_COMPONENTS+=( llvm-libtool-darwin )
    EXTRA_CMAKE_ARGS+=( \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$STAGE1_MACOS_VERSION \
      -DCMAKE_SYSROOT=$HOST_MACOS_SDK \
      -DCMAKE_OSX_SYSROOT=$HOST_MACOS_SDK \
      -DDEFAULT_SYSROOT=$HOST_MACOS_SDK \
    )
    ;;
  Linux)
    # -fcompare-debug-second silences "note: ..." in GCC
    [[ "$STAGE1_CC" == *"gcc" ]] && CMAKE_C_FLAGS+=(
      -fcompare-debug-second -Wno-misleading-indentation \
    )
    EXTRA_CMAKE_ARGS+=(
      -DLIBUNWIND_HAS_NODEFAULTLIBS_FLAG=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=OFF \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    )
    # -D_GLIBCXX_USE_CXX11_ABI=1
    # EXTRA_CMAKE_ARGS+=( -DLLVM_DEFAULT_TARGET_TRIPLE=$HOST_ARCH-linux-musl )
    #
    # COMPILER_RT_USE_BUILTINS_LIBRARY
    #   Use compiler-rt builtins instead of libgcc.
    #   Must be OFF during stage 1 since we don't have builtins_* yet.
    #   Test is in llvm/compiler-rt/cmake/Modules/AddCompilerRT.cmake:285
    # COMPILER_RT_BUILD_MEMPROF=OFF
    #   if left enabled, the memprof cmake will try to unconditionally create a shared
    #   lib which will fail with errors like "undefined reference to '_Unwind_GetIP'".
    # LLVM_ENABLE_PER_TARGET_RUNTIME_DIR
    #   When on (default for linux, but not mac), rt libs are installed at
    #   lib/clang/$LLVM_RELEASE/lib/$HOST_ARCH-unknown-linux-gnu/ with plain names
    #   like "libclang_rt.builtins.a".
    #   When off, libs have an arch suffix, e.g. "libclang_rt.builtins-x86_64.a" and
    #   are installed in lib/clang/$LLVM_RELEASE/lib/.
    ;;
esac

CMAKE_C_FLAGS="$STAGE1_CFLAGS ${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="$STAGE1_LDFLAGS ${CMAKE_LD_FLAGS[@]:-}"

# try: build libcxx;libcxxabi;libunwind as projects instead of runtimes
# -DCMAKE_SYSTEM_NAME="$TARGET_CMAKE_SYSTEM_NAME"

cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_STAGE1" \
  -DCMAKE_PREFIX_PATH="$LLVM_STAGE1" \
  \
  -DCMAKE_C_COMPILER="$STAGE1_CC" \
  -DCMAKE_CXX_COMPILER="$STAGE1_CXX" \
  -DCMAKE_ASM_COMPILER="$STAGE1_ASM" \
  -DCMAKE_AR="$STAGE1_AR" \
  -DCMAKE_RANLIB="$STAGE1_RANLIB" \
  -DCMAKE_LINKER="$STAGE1_LD" \
  \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD=Native \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_STAGE1_COMPONENTS[@]}")" \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_GO_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF \
  -DLLVM_BUILD_LLVM_C_DYLIB=OFF \
  -DLLVM_ENABLE_PIC=OFF \
  \
  -DLLVM_ENABLE_ZLIB=1 \
  -DZLIB_LIBRARY="$ZLIB_STAGE1/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_STAGE1/include" \
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
  -DCLANG_VENDOR=llvmbox \
  \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
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
  -DCOMPILER_RT_BUILD_CRT=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
  -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]:-}"

# note: the "distribution" target builds LLVM_DISTRIBUTION_COMPONENTS
ninja -j$NCPU \
  distribution \
  lld \
  builtins \
  compiler-rt \
  llvm-objcopy \
  llvm-tblgen \
  llvm-libraries \
  llvm-headers \
  cxxabi

rm -rf "$LLVM_STAGE1"
mkdir -p "$LLVM_STAGE1"

ninja -j$NCPU \
  install-distribution-stripped \
  install-lld-stripped \
  install-builtins-stripped \
  install-compiler-rt-stripped \
  install-llvm-objcopy-stripped \
  install-llvm-tblgen-stripped \
  install-llvm-libraries-stripped \
  install-llvm-headers \
  install-cxxabi-stripped

cp -av bin/clang-tblgen "$LLVM_STAGE1/bin/clang-tblgen"
ln -fsv llvm-objcopy "$LLVM_STAGE1/bin/llvm-strip"

# cp -av "$ZLIB_STAGE1"/include/{zconf,zlib}.h "$LLVM_STAGE1"/include/
# cp -av "$ZLIB_STAGE1"/lib/libz.a "$LLVM_STAGE1"/lib/

if [ "$HOST_SYS" = "Linux" ]; then
  # [linux] Somehow clang looks for compiler-rt builtins lib in a different place
  # than where it actually installs it. This is an ugly workaround.
  CLANG_LIB_DIR="$LLVM_STAGE1/lib/clang/$LLVM_RELEASE/lib"
  mkdir -p "$CLANG_LIB_DIR/linux"

  # Fix for LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF
  _pushd "$CLANG_LIB_DIR"
  for lib in *.a; do
    ln -vs "../${lib}" "$CLANG_LIB_DIR/linux/$lib"
  done

  # Fix for LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
  # # [linux] Somehow clang looks for compiler-rt builtins lib in a different place
  # # than where it actually installs it. This is an ugly workaround.
  # _pushd "$CLANG_LIB_DIR/${HOST_ARCH}-unknown-linux-gnu"
  # for lib in *.a; do
  #   ln -vs "../${HOST_ARCH}-unknown-linux-gnu/${lib}" \
  #     "$CLANG_LIB_DIR/linux/$(basename "$lib" .a)-${HOST_ARCH}.a"
  # done
fi
