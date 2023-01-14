#!/bin/bash
#
# Speed things up by building in a ramfs:
#   Linux:
#     ./build.sh /dev/shm/llvm
#   Linux: (alt: tmpfs)
#     mkdir -p build && sudo mount -o size=16G -t tmpfs none build
#     ./build.sh build
#   macOS:
#     mkdir -p build && ./macos-tmpfs.sh build
#     ./build.sh ./build
#
set -e

LLVM_RELEASE=15.0.7
LLVM_SHA256=42a0088f148edcf6c770dfc780a7273014a9a89b66f357c761b4ca7c8dfa10ba
# LLVM_RELEASE=eb4aa6c7a5f22583e319aaaae3f6ee73cbc5464a
# LLVM_SHA256=7c6919bde160a94a5f9c1f93c337fb6fdb9215571a8bbb385aed598763ff59ab

ZLIB_VERSION=1.2.13
ZLIB_CHECKSUM=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30


PWD0=${PWD0:-$PWD}
SCRIPTNAME=${0##*/}
BUILD_DIR=$1
PREVDIR=$PWD
cd "$(dirname "$0")"; PROJECT=$PWD ; cd "$PREVDIR"
HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)

# ————————————————————————————————————————————————————————————————————————————————————
# functions

_err() { echo "$0:" "$@" >&2; exit 1; }

_relpath() { # <path>
  case "$1" in
    "$PWD0/"*) echo "${1##${2:-$PWD0}/}" ;;
    "$PWD0")   echo "." ;;
    *)         echo "$1" ;;
  esac
}

_pushd() {
  pushd "$1" >/dev/null
  [ "$PWD" = "$PWD0" ] || echo "cd $(_relpath "$PWD")"
}

_popd() {
  popd >/dev/null
  [ "$PWD" = "$PWD0" ] || echo "cd $(_relpath "$PWD")"
}

_array_join() { # <gluechar> <element> ...
  local IFS="$1"; shift; echo "$*"
};

_sha256_test() { # <file> <sha256>
  [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ] || return 1
}

_sha256_verify() { # <file> <sha256>
  local file=$1
  local expected_sha256=$2
  local actual_sha256=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "$file: SHA-256 sum mismatch:" >&2
    echo "  actual:   $actual_sha256" >&2
    echo "  expected: $expected_sha256" >&2
    return 1
  fi
}

_download() { # <url> <outfile> [<sha256>]
  local url=$1
  local outfile=$2
  local sha256=$3
  if [ -f "$outfile" ] && ([ -z "$sha256" ] || _sha256_test "$outfile" "$sha256"); then
    return 0
  fi
  rm -f "$outfile"
  echo "${outfile##$PWD0/}: fetch $url"
  command -v wget >/dev/null &&
    wget -q --show-progress -O "$outfile" "$url" ||
    curl -L '-#' -o "$outfile" "$url"
  [ -z "$sha256" ] || _sha256_verify "$outfile" "$sha256"
}

_extract_tar() { # <file> <outdir>
  [ $# -eq 2 ] || _err "_extract_tar"
  local tarfile=$1
  local outdir=$2
  [ -e "$tarfile" ] || _err "$tarfile not found"

  local extract_dir="${outdir%/}-extract-$(basename "$tarfile")"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  echo "${outdir##$PWD0/}: extract ${tarfile##$PWD0/}"
  if ! XZ_OPT='-T0' tar -C "$extract_dir" -xf "$tarfile"; then
    rm -rf "$extract_dir"
    return 1
  fi
  rm -rf "$outdir"
  mkdir -p "$(dirname "$outdir")"
  mv -f "$extract_dir"/* "$outdir"
  rm -rf "$extract_dir"
}

_fetch_source_tar() { # <url> <sha256> <outdir>
  [ $# -eq 3 ] || _err "_fetch_source_tar ($#)"
  local url=$1
  local sha256=$2
  local outdir=$3
  local tarfile=${url##*/}
  tarfile="$(basename "$outdir").${tarfile#*.}" # e.g. foo.tar.gz, foo.tgz
  local stampfile=$outdir/_download_tar_source.sha256
  if [ "$(cat "$stampfile" 2>/dev/null)" = "$sha256" ]; then
    echo "${outdir##$PWD0/}: up-to-date"
  else
    _download    "$url" "$tarfile" "$sha256"
    _extract_tar "$tarfile" "$outdir"
    echo "$sha256" > "$outdir/_download_tar_source.sha256"
  fi
}

_print_exe_links() { # <exefile>
  local OUT
  local objdump="$LLVM_HOST"/bin/llvm-objdump
  [ -f "$objdump" ] || objdump=llvm-objdump
  local PAT='NEEDED|RUNPATH|RPATH'
  case "$HOST_SYS" in
    Darwin) PAT='RUNPATH|RPATH|\.dylib' ;;
  esac
  OUT=$( "$objdump" -p "$1" | grep -E "$PAT" | awk '{printf $1 " " $2 "\n"}' )
  if [ -n "$OUT" ]; then
    echo "$1: dynamically linked:"
    echo "$OUT"
  else
    echo "$1: statically linked"
  fi
}

# ————————————————————————————————————————————————————————————————————————————————————
# main

if [[ "$1" == "--h"* || "$1" == "-h"* ]]; then
  echo "usage: $0 <builddir>"
  exit
fi
[ -n "$BUILD_DIR" ] || _err "missing <builddir>"
mkdir -p "$BUILD_DIR"
PREVDIR=$PWD; cd "$BUILD_DIR"; BUILD_DIR=$PWD; cd "$PREVDIR"


# ————————————————————————————————————————————————————————————————————————————————————
# llvm source

LLVM_SRC=$BUILD_DIR/llvm-$LLVM_RELEASE
LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive
if (echo "$LLVM_RELEASE" | grep -qE '[0-9]+\.'); then
  # release version
  LLVM_SRC_URL=$LLVM_SRC_URL/llvmorg-${LLVM_RELEASE}.tar.gz
else
  # git hash
  LLVM_SRC_URL=$LLVM_SRC_URL/${LLVM_RELEASE}.tar.gz
fi
_fetch_source_tar "$LLVM_SRC_URL" "$LLVM_SHA256" "$LLVM_SRC"

# ————————————————————————————————————————————————————————————————————————————————————
# zlib for host compiler

ZLIB_SRC=$BUILD_DIR/zlib-src
ZLIB_HOST=$BUILD_DIR/zlib-host
if [ "$(cat "$ZLIB_HOST/version" 2>/dev/null)" != "$ZLIB_VERSION" ]; then
  _fetch_source_tar \
    https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_CHECKSUM" "$ZLIB_SRC"
  _pushd "$ZLIB_SRC"
  echo "building zlib ... (${ZLIB_HOST##$PWD0/}.log)"
  ( # -fPIC needed on Linux
    CFLAGS=-fPIC \
      ./configure --static --prefix=
    make -j$(nproc)
    make check
    rm -rf "$ZLIB_HOST"
    mkdir -p "$ZLIB_HOST"
    make DESTDIR="$ZLIB_HOST" install
    echo "$ZLIB_VERSION" > "$ZLIB_HOST/version"
  ) > $ZLIB_HOST.log
  _popd
  DEPS_CHANGED=1
fi

# ————————————————————————————————————————————————————————————————————————————————————
# build llvm host compiler
# https://llvm.org/docs/BuildingADistribution.html

# TODO: consider a "stage2" build a la clang/cmake/caches/Fuchsia.cmake
#       see experiments/stage2.sh

LLVM_HOST=$BUILD_DIR/llvm-host
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
else
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

  _popd
fi


# ————————————————————————————————————————————————————————————————————————————————————
# build zlib for "distribution" using "host" compiler

ZLIB_DIST=$BUILD_DIR/zlib-dist

if [ "$(cat "$ZLIB_DIST/version" 2>/dev/null)" != "$ZLIB_VERSION" ]; then
  _fetch_source_tar \
    https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz "$ZLIB_CHECKSUM" "$ZLIB_SRC"
  _pushd "$ZLIB_SRC"
  echo "building zlib ... (${ZLIB_DIST##$PWD0/}.log)"
  ( # -fPIC needed on Linux
    CFLAGS="-fPIC" \
      ./configure --static --prefix=
    make -j$(nproc)
    make check
    rm -rf "$ZLIB_DIST"
    mkdir -p "$ZLIB_DIST"
    make DESTDIR="$ZLIB_DIST" install
    echo "$ZLIB_VERSION" > "$ZLIB_DIST/version"
  ) > $ZLIB_DIST.log
  _popd
fi


exit


# ————————————————————————————————————————————————————————————————————————————————————
# build second "distribution" llvm using the "host" llvm

LLVM_DIST=$BUILD_DIR/llvm-dist
LLVM_DIST_BUILD=$BUILD_DIR/llvm-dist-build
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

# TODO: make this a cli option for cross compiling
# for now, match host
TARGET=
case "$HOST_SYS" in
  Darwin) TARGET=$HOST_ARCH-macos-none ;;
  Linux)  TARGET=$HOST_ARCH-linux-musl ;;
  *)      _err "unsupported target system $HOST_SYS"
esac


TARGET_OS_AND_ABI=${TARGET#*-} # Example: linux-gnu
CMAKE_SYSTEM_NAME=${TARGET_OS_AND_ABI%-*} # Example: linux
case $CMAKE_SYSTEM_NAME in
  macos)   CMAKE_SYSTEM_NAME="Darwin";;
  freebsd) CMAKE_SYSTEM_NAME="FreeBSD";;
  windows) CMAKE_SYSTEM_NAME="Windows";;
  linux)   CMAKE_SYSTEM_NAME="Linux";;
  native)  CMAKE_SYSTEM_NAME="";;
esac

if [ "$(cat "$LLVM_DIST/version" 2>/dev/null)" = "$LLVM_RELEASE" ] &&
   [ "$LLVM_DIST/version" -nt "$LLVM_HOST/version" ]
then
  echo "${LLVM_DIST##$PWD0/}: up-to-date"
else
  mkdir -p "$LLVM_DIST_BUILD"
  _pushd "$LLVM_DIST_BUILD"

  # see https://llvm.org/docs/HowToCrossCompileLLVM.html#hacks

  CMAKE_C_COMPILER="$LLVM_HOST/bin/clang"
  CMAKE_CXX_COMPILER="$LLVM_HOST/bin/clang++"
  CMAKE_ASM_COMPILER="$CMAKE_C_COMPILER"
  CMAKE_RC_COMPILER="$LLVM_HOST/bin/llvm-rc"
  CMAKE_AR="$LLVM_HOST/bin/llvm-ar"
  CMAKE_RANLIB="$LLVM_HOST/bin/llvm-ranlib"

  LLVM_CFLAGS=( -target $TARGET -w -I"$ZLIB_DIST/include" )
  LLVM_LDFLAGS=( -L"$ZLIB_DIST/lib" )

  EXTRA_CMAKE_ARGS=()  # extra args added to cmake invocation (depending on target)

  CMAKE_EXE_LINKER_FLAGS=()
  # case "$HOST_SYS" in
  #   Linux) CMAKE_EXE_LINKER_FLAGS+=( -static ) ;;
  # esac

  CMAKE_C_FLAGS="-target $TARGET -w"

  case "$HOST_SYS" in
    Darwin)
      # TODO: do like zig and copy the headers we need into the repo so a build
      # targeting apple platforms can be done anywhere.
      if [ "$HOST_SYS" =  ]
      command -v xcrun >/dev/null || _err "xcrun not found in PATH"
      EXTRA_CMAKE_ARGS+=( -DDEFAULT_SYSROOT="$(xcrun --show-sdk-path)" )
      ;;
  esac


  echo "configuring llvm ... (${PWD##$PWD0/}/cmake-config.log)"
  cmake -G Ninja -Wno-dev "$LLVM_SRC/llvm" \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_INSTALL_PREFIX="$LLVM_HOST" \
    -DCMAKE_PREFIX_PATH="$LLVM_HOST" \
    \
    -DCMAKE_C_COMPILER="$CMAKE_C_COMPILER" \
    -DCMAKE_CXX_COMPILER="$CMAKE_CXX_COMPILER" \
    -DCMAKE_ASM_COMPILER="$CMAKE_ASM_COMPILER" \
    -DCMAKE_RC_COMPILER="$CMAKE_RC_COMPILER" \
    -DCMAKE_AR="$CMAKE_AR" \
    -DCMAKE_RANLIB="$CMAKE_RANLIB" \
    \
    -DCMAKE_C_FLAGS="$LLVM_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$LLVM_CFLAGS" \
    \
    -DCMAKE_EXE_LINKER_FLAGS="$LLVM_LDFLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LLVM_LDFLAGS" \
    -DCMAKE_MODULE_LINKER_FLAGS="$LLVM_LDFLAGS" \
    \
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
    \
    # > cmake-config.log || _err "cmake failed. See $PWD/cmake-config.log"

  _popd
fi



exit



# ————————————————————————————————————————————————————————————————————————————————————
# copy clang driver impl for myclang

_pushd "$PROJECT"
cp -v "$LLVM_SRC"/clang/tools/driver/driver.cpp     myclang/driver.cc
cp -v "$LLVM_SRC"/clang/tools/driver/cc1_main.cpp   myclang/driver_cc1_main.cc
cp -v "$LLVM_SRC"/clang/tools/driver/cc1as_main.cpp myclang/driver_cc1as_main.cc
for f in $(echo myclang-$LLVM_RELEASE-*.patch | sort); do
  [ -e "$f" ] || _err "no patches found at $PROJECT/llvm-$LLVM_RELEASE-*.patch"
  [ -f "$f" ] || _err "$f is not a file"
  if ! patch -p0 < "$f"; then
    cat << END
To make a new patch:
  cp '$LLVM_SRC/clang/tools/driver/driver.cpp' myclang/driver.cc
  cp myclang/driver.cc myclang/driver.cc.orig
  # edit myclang/driver.cc
  diff -u myclang/driver.cc.orig myclang/driver.cc > myclang-'$LLVM_RELEASE'-001-driver.patch
END
    exit 1
  fi
done
_popd


# ————————————————————————————————————————————————————————————————————————————————————
# test the compiler

bash "$PROJECT/test.sh" "$LLVM_HOST"
