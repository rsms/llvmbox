#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

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

LLVM_DIST_BUILD=$BUILD_DIR/llvm-dist-build
mkdir -p "$LLVM_DIST_BUILD"
_pushd "$LLVM_DIST_BUILD"

# see https://llvm.org/docs/HowToCrossCompileLLVM.html#hacks

LLVM_CFLAGS=( "${TARGET_CFLAGS[@]}" -I"$ZLIB_DIST/include" )
LLVM_CXXFLAGS=( "${TARGET_CXXFLAGS[@]}" -I"$ZLIB_DIST/include" )
LLVM_LDFLAGS=( "${TARGET_CXX_LDFLAGS[@]}" -L"$ZLIB_DIST/lib" )

EXTRA_CMAKE_ARGS=()  # extra args added to cmake invocation (depending on target)

case "$TARGET_SYS" in
  linux)
    # LLVM_LDFLAGS+=( -static )
    ;;
  macos)
    # # TODO: do like zig and copy the headers we need into the repo so a build
    # # targeting apple platforms can be done anywhere
    # command -v xcrun >/dev/null || _err "xcrun not found in PATH"
    # EXTRA_CMAKE_ARGS+=( -DDEFAULT_SYSROOT="$(xcrun --show-sdk-path)" )
    ;;
esac


cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$TARGET_CMAKE_SYSTEM_NAME" \
  -DCMAKE_INSTALL_PREFIX="$LLVM_HOST" \
  -DCMAKE_PREFIX_PATH="$LLVM_HOST" \
  \
  -DCMAKE_C_COMPILER="$TARGET_CC;-target;$TARGET" \
  -DCMAKE_CXX_COMPILER="$TARGET_CXX;-target;$TARGET" \
  -DCMAKE_ASM_COMPILER="$TARGET_ASM;-target;$TARGET" \
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
  -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
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
  -DLLVM_ENABLE_PIC=False \
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
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \

