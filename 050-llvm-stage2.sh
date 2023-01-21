#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ -d "$LLVM_HOST" ] ||
  _err "llvm-host must be built before running this script (LLVM_HOST=$LLVM_HOST)"

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

LLVMBOX_BUILD_DIR=$LLVMBOX_BUILD_DIR \
LLVMBOX_SYSROOT=$LLVMBOX_SYSROOT \
LLVM_HOST=$LLVM_HOST \
cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -C "$PROJECT/stage1.cmake" \
  -DCMAKE_TOOLCHAIN_FILE=$PROJECT/toolchain.cmake \
  -DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME" \
  -DCMAKE_C_FLAGS="-w" \
  -DCMAKE_CXX_FLAGS="-w" \
  -DCMAKE_INSTALL_PREFIX= \
  -DCLANG_PREFIX="$LLVM_HOST/bin" \
  -DLLVMBOX_BUILD_DIR="$BUILD_DIR"

ninja \
  stage2-distribution \
  llvm-libraries \
  clang-libraries \
  clang-resource-headers \

DESTDIR=$LLVMBOX_SYSROOT ninja \
  stage2-install-distribution-stripped \
  install-llvm-libraries \
  install-clang-libraries \
  install-clang-resource-headers \
  install-builtins \
  install-compiler-rt \
  liblldCOFF.a \
  liblldCommon.a \
  liblldELF.a \
  liblldMachO.a \
  liblldMinGW.a \
  liblldWasm.a \

# move lib/TARGET/ files to lib/
LIB_FOR_TARGET="$(echo "$LLVMBOX_SYSROOT"/lib/$TARGET_ARCH-*linux-*)"
if [ -d "$LIB_FOR_TARGET" ]; then
  mv "$LIB_FOR_TARGET"/*.* "$LLVMBOX_SYSROOT/lib/"
  rmdir "$LIB_FOR_TARGET" # rmdir instead of "rm -rf" so we get an error if non-empty
fi

# install extras not installed by stage2-install-distribution
# TODO: consider: tools/clang/stage2-bins/lib/clang/15.0.7/include/*.h + dirs
error=
for f in \
  tools/clang/stage2-bins/bin/llvm-tblgen \
  tools/clang/stage2-bins/bin/clang-tblgen \
  tools/clang/stage2-bins/lib/liblld*.a \
  tools/clang/stage2-bins/lib/libLLVMWebAssembly*.a \
;do
  dst=$(basename "$(dirname "$f")")/$(basename "$f") # e.g. /a/b/c/d => c/d
  if [ ! -e "$f" ]; then
    echo "MISSING: $PWD/$f" >&2
    error=1
    continue
  fi
  if [ -e "$LLVMBOX_SYSROOT/$dst" ]; then
    echo "SKIP DUPLICATE $LLVMBOX_SYSROOT/$dst"
    continue
  fi
  echo "install $LLVMBOX_SYSROOT/$dst"
  cp -a $f "$LLVMBOX_SYSROOT/$dst" &
done
wait
[ -z "$error" ] || exit 1

# verify that required components were installed
for f in \
  bin/llvm-config \
  lib/libLLVMOrcShared.a \
  lib/libLLVMOrcTargetProcess.a \
  lib/libLLVMRuntimeDyld.a \
  lib/libLLVMExecutionEngine.a \
  lib/libLLVMInterpreter.a \
  lib/libLLVMMCA.a \
  lib/libLLVMX86TargetMCA.a \
  lib/libLLVMJITLink.a \
  lib/libLLVMOrcJIT.a \
  lib/libLLVMMCJIT.a \
;do
  [ -e "$LLVMBOX_SYSROOT/$f" ] || _err "$LLVMBOX_SYSROOT/$f: missing"
  echo "$LLVMBOX_SYSROOT/$f: ok"
done

# TODO: (when _DIST & _DESTDIR paths are correct)
# # copy-merge dependencies into llvm root
# for lib in \
#   "$ZLIB_DIST" \
#   "$ZSTD_DIST" \
#   "$XC_DESTDIR" \
#   "$OPENSSL_DESTDIR" \
#   "$LIBXML2_DESTDIR" \
#   "$XAR_DESTDIR"
# do
#   [ -d "$lib" ] || continue
#   echo "install-lib $lib -> $LLVMBOX_SYSROOT"
#   rsync -au "$lib/" "$LLVMBOX_SYSROOT/"
# done
