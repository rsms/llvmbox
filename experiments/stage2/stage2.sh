#!/bin/bash
set -e
cd "$(dirname "$0")"
STAGE2_PROJECT=$PWD
cd ../..
source config.sh

[ -d "$LLVM_HOST" ] || _err "llvm-host must be built before running this script"

LLVM_DESTDIR=${LLVM_DESTDIR:-$BUILD_DIR/llvm2}

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

cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
  -C "$STAGE2_PROJECT/stage1.cmake" \
  -DCMAKE_TOOLCHAIN_FILE=$STAGE2_PROJECT/toolchain.cmake \
  -DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME" \
  -DCMAKE_C_FLAGS="-w" \
  -DCMAKE_CXX_FLAGS="-w" \
  -DCMAKE_INSTALL_PREFIX= \
  -DCLANG_PREFIX="$LLVM_HOST/bin" \
  -DLLVMBOX_BUILD_DIR="$BUILD_DIR"

ninja \
  stage2-distribution \
  llvm-libraries \
  clang-libraries

rm -rf "$LLVM_DESTDIR"
mkdir -p "$LLVM_DESTDIR"
DESTDIR=${LLVM_DESTDIR} ninja \
  stage2-install-distribution-stripped \
  install-llvm-libraries \
  install-clang-libraries \
  liblldCOFF.a \
  liblldCommon.a \
  liblldELF.a \
  liblldMachO.a \
  liblldMinGW.a \
  liblldWasm.a \

# install extras not installed by stage2-install-distribution
# lib/*.a
error=
for f in \
  tools/clang/stage2-bins/bin/llvm-tblgen \
  tools/clang/stage2-bins/bin/llvm-config \
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
  if [ -e "$LLVM_DESTDIR/$dst" ]; then
    echo "SKIP DUPLICATE $LLVM_DESTDIR/$dst"
    continue
  fi
  echo "install $LLVM_DESTDIR/$dst"
  cp -a $f "$LLVM_DESTDIR/$dst" &
done
wait
[ -z "$error" ] || exit 1

for f in \
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
  [ -e "$LLVM_DESTDIR/$f" ] || _err "$LLVM_DESTDIR/$f: missing"
  echo "$LLVM_DESTDIR/$f: ok"
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
#   echo "install-lib $lib -> $LLVM_DIST"
#   rsync -au "$lib/" "$LLVM_DIST/"
# done
