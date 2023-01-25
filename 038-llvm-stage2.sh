#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

LLVM_TOOLCHAIN_TOOLS=(
  llvm-ar \
  llvm-cov \
  llvm-cxxfilt \
  llvm-dwp \
  llvm-ranlib \
  llvm-lib \
  llvm-ml \
  llvm-nm \
  llvm-objcopy \
  llvm-objdump \
  llvm-pdbutil \
  llvm-rc \
  llvm-readobj \
  llvm-size \
  llvm-strings \
  llvm-strip \
  llvm-profdata \
  llvm-symbolizer \
  llvm-dwarfdump \
  llvm-config \
  dsymutil \
)
# symlink version of some of above tools that are enabled
# by LLVM_INSTALL_BINUTILS_SYMLINKS
LLVM_TOOLCHAIN_TOOLS+=(
  addr2line \
  ar \
  c++filt \
  ranlib \
  nm \
  objcopy \
  objdump \
  readelf \
  size \
  strings \
  strip \
)

LLVM_DISTRIBUTION_COMPONENTS=(
  lld
  clang
  clang-format
  clang-resource-headers
  clang-refactor
  clang-scan-deps
  libclang
  builtins
  "${LLVM_TOOLCHAIN_TOOLS[@]}" \
)

CMAKE_C_FLAGS=( \
  "-isystem=$LLVMBOX_SYSROOT/include" \
)
CMAKE_CXX_FLAGS=(
  -nostdinc++ -I"$LIBCXX_STAGE2/include/c++/v1" \
)
CMAKE_LD_FLAGS=(
  -nostdlib++ -L"$LIBCXX_STAGE2/lib" -lc++ -lc++abi \
)
EXTRA_CMAKE_ARGS=( -Wno-dev )

# zlib
EXTRA_CMAKE_ARGS+=(
  -DLLVM_ENABLE_ZLIB=FORCE_ON \
  -DZLIB_LIBRARY="$ZLIB_STAGE2/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_STAGE2/include" \
)

# zstd
EXTRA_CMAKE_ARGS+=(
  -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -DLLVM_USE_STATIC_ZSTD=TRUE \
  -Dzstd_LIBRARY="$ZSTD_STAGE2/lib/libzstd.a" \
  -Dzstd_INCLUDE_DIR="$ZSTD_STAGE2/include" \
)

# libxml2
EXTRA_CMAKE_ARGS+=( \
  -DLLVM_ENABLE_LIBXML2=FORCE_ON \
  -DLIBXML2_LIBRARY="$LIBXML2_STAGE2/lib/libxml2.a" \
  -DLIBXML2_INCLUDE_DIR="$LIBXML2_STAGE2/include" \
)

# xar (for mach-o linker)
if [ -d "$XAR_STAGE2" ]; then
  EXTRA_CMAKE_ARGS+=( -DLLVM_HAVE_LIBXAR=1 )
  CMAKE_C_FLAGS+=(
    -I"$XAR_STAGE2/include" \
    -I"$XC_STAGE2/include" \
    -I"$OPENSSL_STAGE2/include" \
  )
  COMMON_LDFLAGS+=(
    -L"$XAR_STAGE2/lib" \
    -L"$XC_STAGE2/lib" -llzma \
    -L"$OPENSSL_STAGE2/lib" -lcrypto \
  )
else
  EXTRA_CMAKE_ARGS+=( -DLLVM_HAVE_LIBXAR=0 )
fi

case "$HOST_SYS" in
  Darwin)
    EXTRA_CMAKE_ARGS+=(
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET_SYS_VERSION \
      -DCMAKE_OSX_SYSROOT="$LLVMBOX_SYSROOT" \
      -DOSX_SYSROOT="$LLVMBOX_SYSROOT" \
      -DDARWIN_osx_CACHED_SYSROOT="$LLVMBOX_SYSROOT" \
      -DDARWIN_macosx_CACHED_SYSROOT="$LLVMBOX_SYSROOT" \
      -DDARWIN_iphonesimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_iphoneos_CACHED_SYSROOT=/dev/null \
      -DDARWIN_watchsimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_watchos_CACHED_SYSROOT=/dev/null \
      -DDARWIN_appletvsimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_appletvos_CACHED_SYSROOT=/dev/null \
      -DCOMPILER_RT_ENABLE_IOS=OFF \
      -DCOMPILER_RT_ENABLE_WATCHOS=OFF \
      -DCOMPILER_RT_ENABLE_TVOS=OFF \
    )
    # to find out supported archs: ld -v 2>&1 | grep 'support archs:'
    if [ "$TARGET_ARCH" == x86_64 ]; then
      # needed to not include i386 target which won't work in our sysroot
      EXTRA_CMAKE_ARGS+=(
        -DDARWIN_osx_BUILTIN_ARCHS="x86_64;x86_64h" \
        -DDARWIN_macosx_BUILTIN_ARCHS="x86_64;x86_64h" \
      )
    # elif [ "$TARGET_ARCH" == aarch64 ]; then
    #   # needed on aarch64 since cmake will try 'clang -v' (which it expects to be ld)
    #   # to discover supported architectures.
    #   EXTRA_CMAKE_ARGS+=(
    #     -DDARWIN_osx_BUILTIN_ARCHS="arm64" \
    #     -DDARWIN_macosx_BUILTIN_ARCHS="arm64" \
    #   )
    fi
    # all: asan;dfsan;msan;hwasan;tsan;safestack;cfi;scudo;ubsan_minimal;gwp_asan
    EXTRA_CMAKE_ARGS+=(
      -DCOMPILER_RT_SANITIZERS_TO_BUILD="asan;msan;safestack;scudo;ubsan_minimal" \
    )
    # -DLLVM_BUILTIN_TARGETS=$TARGET_ARCH-darwin-apple
    CMAKE_C_FLAGS+=(
      -I"$LLVMBOX_SYSROOT/include" \
      -w \
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
    )
    CMAKE_LD_FLAGS+=(
      -L"$LLVMBOX_SYSROOT/lib" \
      -L"$LIBCXX_STAGE2/lib" \
    )
    # required for CoreFoundation/CFBase.h which is used by compiler-rt/tsan
    CMAKE_C_FLAGS+=( -Wno-elaborated-enum-base )
    ;;
  # Linux)
  #   EXTRA_CMAKE_ARGS+=(
  #     -DLIBCXX_HAS_MUSL_LIBC=ON \
  #   )
  #   ;;
esac

# EXTRA_CMAKE_ARGS+=(
#   -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${LLVM_DISTRIBUTION_COMPONENTS[@]}")" \
#   -DLLVM_TOOLCHAIN_TOOLS="$(_array_join ";" "${LLVM_TOOLCHAIN_TOOLS[@]}")" \
# )


CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS[@]:-} ${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$BUILD_DIR/llvm-stage2"
_pushd "$BUILD_DIR/llvm-stage2"

cmake -G Ninja "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
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
  -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64;RISCV;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
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
  -DLLVM_INCLUDE_TOOLS=ON \
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
  -DLLDB_ENABLE_CURSES=OFF \
  -DLLDB_ENABLE_FBSDVMCORE=OFF \
  -DLLDB_ENABLE_LIBEDIT=OFF \
  -DLLDB_ENABLE_LUA=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
  \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_CAN_EXECUTE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_CRT=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
  -DCOMPILER_RT_ENABLE_STATIC_UNWINDER=ON \
  -DCOMPILER_RT_STATIC_CXX_LIBRARY=ON \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]:-}"

# note: the "distribution" target builds LLVM_DISTRIBUTION_COMPONENTS
ninja -j$NCPU

# Having trouble?
#   Missing headers on macOS?
#     1. Open import-macos-headers.c and add them
#     2. Run ./import-macos-libc.sh on a mac with SDKs installed
#     3. Recreate your build sysroot (bash 020-sysroot.sh)
#     4. Try again

# ninja -j$NCPU \
#   distribution \
#   lld \
#   builtins \
#   compiler-rt \
#   llvm-objcopy \
#   llvm-tblgen \
#   llvm-libraries \
#   llvm-headers


exit


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

if [ "$HOST_SYS" = "Linux" ]; then
  # [linux] Sometimes(??) the rtlibs are installed at lib instead of lib/linux
  # Check for that now to pervent hard-to-debug errors later
  CLANG_LIB_DIR="$LLVM_STAGE1/lib/clang/$LLVM_RELEASE/lib"
  EXPECT_FILE="$CLANG_LIB_DIR/linux/libclang_rt.builtins-$HOST_ARCH.a"
  [ -e "$EXPECT_FILE" ] ||
    _err "expected file not found: $EXPECT_FILE"

  # Fix for LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
  # # [linux] Somehow clang looks for compiler-rt builtins lib in a different place
  # # than where it actually installs it. This is an ugly workaround.
  # mkdir -p "$CLANG_LIB_DIR/linux"
  # _pushd "$CLANG_LIB_DIR/${HOST_ARCH}-unknown-linux-gnu"
  # for lib in *.a; do
  #   ln -vs "../${HOST_ARCH}-unknown-linux-gnu/${lib}" \
  #     "$CLANG_LIB_DIR/linux/$(basename "$lib" .a)-${HOST_ARCH}.a"
  # done
fi
