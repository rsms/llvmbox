#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

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

ZLIB=$BUILD_DIR/stage1-zlib
CMAKE_C_FLAGS=( -w -I"$ZLIB/include" )
CMAKE_LD_FLAGS=( -L"$ZLIB/lib" )

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
    CMAKE_C_FLAGS+=(
      -fPIC \
      --sysroot="$OUT_DIR/gcc-musl" \
    )
    CMAKE_LD_FLAGS+=(
      --sysroot="$OUT_DIR/gcc-musl" \
    )
    EXTRA_CMAKE_ARGS+=(
      -DCMAKE_SYSROOT="$OUT_DIR/gcc-musl" \
      -DCMAKE_FIND_ROOT_PATH="$OUT_DIR/gcc-musl" \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLIBUNWIND_HAS_NODEFAULTLIBS_FLAG=OFF \
      -DLLVM_DEFAULT_TARGET_TRIPLE=$HOST_ARCH-linux-musl \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    )
    # COMPILER_RT_BUILD_MEMPROF=OFF
    #   if left enabled, the memprof cmake will try to unconditionally create a shared
    #   lib which will fail with errors like "undefined reference to '_Unwind_GetIP'".
    ;;
esac

CMAKE_C_FLAGS="$STAGE1_CFLAGS ${CMAKE_C_FLAGS[@]}"
CMAKE_LD_FLAGS="$STAGE1_LDFLAGS ${CMAKE_LD_FLAGS[@]}"

if [ -n "${EXTRA_CMAKE_EXE_LINKER_FLAGS:-}" ]; then
  EXTRA_CMAKE_EXE_LINKER_FLAGS="${EXTRA_CMAKE_EXE_LINKER_FLAGS[@]}"
else
  EXTRA_CMAKE_EXE_LINKER_FLAGS=
fi

LLVMBOX_SYSROOT=$OUT_DIR/gcc-musl \
cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX="$LLVM_HOST" \
  -DCMAKE_PREFIX_PATH="$LLVM_HOST" \
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
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS $EXTRA_CMAKE_EXE_LINKER_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;Mips;RISCV;X86" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_HOST_COMPONENTS[@]}")" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  -DLLVM_ENABLE_ASSERTIONS=ON \
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
  \
  -DLLVM_ENABLE_ZLIB=1 \
  -DZLIB_LIBRARY="$ZLIB/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB/include" \
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
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=OFF \
  \
  "${EXTRA_CMAKE_ARGS[@]}"

# -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON  works on macos, not ubuntu
  # -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON

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

# TODO: consider installing *-stripped targets instead

cp -a bin/clang-tblgen "$LLVM_HOST/bin/clang-tblgen"
ln -s llvm-objcopy "$LLVM_HOST/bin/llvm-strip"

# _pushd $PROJECT
# set -x
# utils/musl-clang -v -static test/hello.c -o test/hello_c_musl
# test/hello_c_musl
