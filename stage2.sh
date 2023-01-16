#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
SELF_SCRIPT=$(realpath -s "$0")

INSTALL_DIR="$BUILD_DIR/llvm2"

CMAKE_SYSTEM_NAME=$TARGET_SYS  # e.g. linux, macos
case $CMAKE_SYSTEM_NAME in
  apple|macos|darwin) CMAKE_SYSTEM_NAME="Darwin";;
  freebsd)            CMAKE_SYSTEM_NAME="FreeBSD";;
  windows)            CMAKE_SYSTEM_NAME="Windows";;
  linux)              CMAKE_SYSTEM_NAME="Linux";;
  native)             CMAKE_SYSTEM_NAME="";;
esac

LLVM_STAGE2_BUILD_DIR=${LLVM_STAGE2_BUILD_DIR:-$BUILD_DIR/llvm-stage2}
mkdir -p "$LLVM_STAGE2_BUILD_DIR"
_pushd "$LLVM_STAGE2_BUILD_DIR"

cmake -G Ninja "$LLVM_SRC/llvm" \
  -C "$PROJECT/stage1.cmake" \
  -DCMAKE_TOOLCHAIN_FILE=$PROJECT/toolchain.cmake \
  -DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME" \
  -DCMAKE_C_FLAGS="-w" \
  -DCMAKE_CXX_FLAGS="-w" \
  -DCMAKE_INSTALL_PREFIX= \
  -DCLANG_PREFIX="$LLVM_HOST/bin" \
  -DLLVMBOX_BUILD_DIR="$BUILD_DIR"

ninja stage2-distribution

mkdir -p "$INSTALL_DIR"
DESTDIR=${INSTALL_DIR} ninja stage2-install-distribution-stripped





exit

# cmake -GNinja \
#   -DCMAKE_TOOLCHAIN_FILE=${FUCHSIA_DIR}/scripts/clang/ToolChain.cmake \
#   -DUSE_GOMA=ON \
#   -DCMAKE_INSTALL_PREFIX= \
#   -DSTAGE2_LINUX_aarch64-unknown-linux-gnu_SYSROOT=${SYSROOT_DIR} \
#   -DSTAGE2_LINUX_x86_64-unknown-linux-gnu_SYSROOT=${SYSROOT_DIR} \
#   -DSTAGE2_FUCHSIA_SDK=${IDK_DIR} \
#   -C ${LLVM_SRCDIR}/clang/cmake/caches/Fuchsia.cmake \
#   ${LLVM_SRCDIR}/llvm
# ninja stage2-distribution -j1000
# DESTDIR=${INSTALL_DIR} ninja stage2-install-distribution-stripped -j1000



echo ninja stage2-distribution
ninja stage2-distribution

echo ninja stage2-install-distribution
ninja stage2-install-distribution

cp -a "$LLVM_STAGE2_BUILD"/bin/llvm-{ar,ranlib,tblgen} "$LLVM_STAGE2"/bin
cp -a "$LLVM_STAGE2_BUILD"/bin/clang-tblgen            "$LLVM_STAGE2"/bin

cp -a "$LLVM_STAGE2_BUILD"/bin/lld   "$LLVM_STAGE2"/bin
ln -fs "$LLVM_STAGE2_BUILD"/bin/lld  "$LLVM_STAGE2"/bin/ld64.lld
ln -fs "$LLVM_STAGE2_BUILD"/bin/lld  "$LLVM_STAGE2"/bin/ld.lld

touch "$LLVM_STAGE2/bin/clang"

