#
# Speed things up by building in a ramfs:
#   Linux:
#     export LLVMBOX_BUILD_DIR=/dev/shm
#   Linux: (alt: tmpfs)
#     mkdir -p ~/tmp && sudo mount -o size=16G -t tmpfs none ~/tmp
#     export LLVMBOX_BUILD_DIR=$HOME/tmp
#   macOS:
#     ./macos-tmpfs.sh ~/tmp
#     export LLVMBOX_BUILD_DIR=$HOME/tmp
#
set -e
_err() { echo "$0:" "$@" >&2; exit 1; }
PWD0=${PWD0:-$PWD}
[ -n "${LLVMBOX_BUILD_DIR:-}" ] || _err "LLVMBOX_BUILD_DIR is not set in env"

PROJECT=${LLVMBOX_PROJECT:-$(realpath "$(dirname "$0")")}
BUILD_DIR=$(realpath "$LLVMBOX_BUILD_DIR")
DOWNLOAD_DIR=$(realpath "${LLVMBOX_DOWNLOAD_DIR:-$PROJECT/download}")
OUT_DIR=$(realpath "${LLVMBOX_OUT_DIR:-$PROJECT/out}")
NCPU=${LLVMBOX_NCPU:-$(nproc)}
mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR"
# ————————————————————————————————————————————————————————————————————————————————————

HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)
HOST_TARGET=${HOST_TARGET:-}
[ -n "$HOST_TARGET" ] || case "$HOST_SYS" in
  Linux)  HOST_TARGET=$HOST_ARCH-linux-gnu ;;
  Darwin) HOST_TARGET=$HOST_ARCH-apple-darwin ;;
  *)      HOST_TARGET=$HOST_ARCH-$HOST_SYS ;;
esac

TARGET=${LLVMBOX_TARGET:-}  # e.g. x86_64-macos-none, aarch64-linux-musl
if [ -z "$TARGET" ]; then
  case "$HOST_SYS" in
    Darwin) TARGET=$HOST_ARCH-macos-none ;;
    Linux)  TARGET=$HOST_ARCH-linux-musl ;;
    *)      _err "couldn't guess TARGET from $HOST_SYS"
  esac
fi
TARGET_SYS_AND_ABI=${TARGET#*-}     # e.g. linux-musl
TARGET_SYS=${TARGET_SYS_AND_ABI%-*} # e.g. linux
TARGET_ARCH=${TARGET%%-*}           # e.g. x86_64

TARGET_CMAKE_SYSTEM_NAME=$TARGET_SYS  # e.g. linux, macos
case $TARGET_CMAKE_SYSTEM_NAME in
  apple|macos|darwin) TARGET_CMAKE_SYSTEM_NAME="Darwin";;
  freebsd)            TARGET_CMAKE_SYSTEM_NAME="FreeBSD";;
  windows)            TARGET_CMAKE_SYSTEM_NAME="Windows";;
  linux)              TARGET_CMAKE_SYSTEM_NAME="Linux";;
  native)             TARGET_CMAKE_SYSTEM_NAME="";;
esac

# ————————————————————————————————————————————————————————————————————————————————————

LLVMBOX_SYSROOT_BASE=${LLVMBOX_SYSROOT_BASE:-$OUT_DIR/sysroot}
LLVMBOX_SYSROOT=${LLVMBOX_SYSROOT:-$LLVMBOX_SYSROOT_BASE/$TARGET}
export LLVMBOX_SYSROOT

LLVM_RELEASE=15.0.7
LLVM_SHA256=42a0088f148edcf6c770dfc780a7273014a9a89b66f357c761b4ca7c8dfa10ba
LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive/llvmorg-${LLVM_RELEASE}.tar.gz
[[ "$LLVM_RELEASE" != *"."* ]] && # git snapshot
  LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive/${LLVM_RELEASE}.tar.gz
LLVM_SRC_STAGE1=${LLVM_SRC_STAGE1:-$OUT_DIR/src/llvm-stage1}
LLVM_SRC=${LLVM_SRC:-$OUT_DIR/src/llvm}
LLVM_STAGE1=${LLVM_HOST:-$OUT_DIR/llvm-stage1}
LLVM_HOST=$LLVM_STAGE1
LLVM_DESTDIR=${LLVM_DESTDIR:-$OUT_DIR/llvm-$TARGET}
export LLVMBOX_LLVM_HOST=$LLVM_HOST

ZLIB_VERSION=1.2.13
ZLIB_SHA256=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30
ZLIB_SRC=${ZLIB_SRC:-$BUILD_DIR/src/zlib}
ZLIB_STAGE1=${ZLIB_HOST:-$BUILD_DIR/zlib-stage1}
ZLIB_DIST=${ZLIB_DIST:-$BUILD_DIR/zlib-$TARGET}

ZSTD_VERSION=1.5.2
ZSTD_SHA256=7c42d56fac126929a6a85dbc73ff1db2411d04f104fae9bdea51305663a83fd0
ZSTD_SRC=${ZSTD_SRC:-$BUILD_DIR/src/zstd}
ZSTD_DIST=${ZSTD_DIST:-$BUILD_DIR/zstd-$TARGET}

XC_VERSION=5.2.5
XC_SHA256=3e1e518ffc912f86608a8cb35e4bd41ad1aec210df2a47aaa1f95e7f5576ef56
XC_SRC=${XC_SRC:-$BUILD_DIR/src/xc}
XC_DESTDIR=${XC_DESTDIR:-$BUILD_DIR/xc-$TARGET}

OPENSSL_VERSION=1.1.1s
OPENSSL_SHA256=c5ac01e760ee6ff0dab61d6b2bbd30146724d063eb322180c6f18a6f74e4b6aa
OPENSSL_SRC=${OPENSSL_SRC:-$BUILD_DIR/src/openssl}
OPENSSL_DESTDIR=${OPENSSL_DESTDIR:-$BUILD_DIR/openssl-$TARGET}

LIBXML2_VERSION=2.10.3
LIBXML2_SHA256=5d2cc3d78bec3dbe212a9d7fa629ada25a7da928af432c93060ff5c17ee28a9c
LIBXML2_SRC=${LIBXML2_SRC:-$BUILD_DIR/src/libxml2}
LIBXML2_DESTDIR=${LIBXML2_DESTDIR:-$BUILD_DIR/libxml2-$TARGET}

XAR_SRC=${XAR_SRC:-$BUILD_DIR/src/xar}
XAR_DESTDIR=${XAR_DESTDIR:-$BUILD_DIR/xar-$TARGET}

LINUX_VERSION=6.1.7
LINUX_SHA256=4ab048bad2e7380d3b827f1fad5ad2d2fc4f2e80e1c604d85d1f8781debe600f
LINUX_SRC=${LINUX_SRC:-$BUILD_DIR/src/linux}
LINUX_HEADERS_DESTDIR=${LINUX_HEADERS_DESTDIR:-$BUILD_DIR/linux-${LINUX_VERSION}-headers}

MUSLFTS_SRC=${MUSLFTS_SRC:-$BUILD_DIR/src/musl-fts}
MUSLFTS_DESTDIR=${MUSLFTS_DESTDIR:-$BUILD_DIR/musl-fts-$TARGET}

MUSL_VERSION=1.2.3
MUSL_SHA256=7d5b0b6062521e4627e099e4c9dc8248d32a30285e959b7eecaa780cf8cfd4a4
MUSL_SRC=${MUSL_SRC:-$BUILD_DIR/src/musl}
MUSL_HOST=${MUSL_HOST:-$BUILD_DIR/musl-host}
MUSL_DESTDIR=${MUSL_DESTDIR:-$BUILD_DIR/musl-$TARGET}

GCC_MUSL=${GCC_MUSL:-$BUILD_DIR/gcc-musl}

# ————————————————————————————————————————————————————————————————————————————————————

STAGE1_CC=cc
STAGE1_CXX=c++
STAGE1_AR=ar
STAGE1_RANLIB=ranlib
STAGE1_CFLAGS=
STAGE1_LDFLAGS=
if [ "$HOST_SYS" = "Linux" ]; then
  STAGE1_CC="$(command -v  gcc || true)"
  STAGE1_CXX="$(command -v g++ || true)"
  STAGE1_LDFLAGS="-static-libgcc -static"
  # STAGE1_CC="$OUT_DIR/gcc-musl/bin/gcc"
  # STAGE1_CXX="$OUT_DIR/gcc-musl/bin/g++"
  # STAGE1_AR="$OUT_DIR/gcc-musl/bin/ar"
  # STAGE1_RANLIB="$OUT_DIR/gcc-musl/bin/ranlib"
  # STAGE1_LD="$OUT_DIR/gcc-musl/bin/ld"
  # STAGE1_LDFLAGS="-static-libgcc -static"
elif [ "$HOST_SYS" = "Darwin" ]; then
  STAGE1_CC="$(command -v  clang || true)"
  STAGE1_CXX="$(command -v clang++ || true)"
  STAGE1_CFLAGS="$STAGE1_CFLAGS -mmacosx-version-min=10.10"
  STAGE1_LDFLAGS="$STAGE1_LDFLAGS -mmacosx-version-min=10.10"
fi
STAGE1_ASM=${STAGE1_ASM:-$STAGE1_CC}
STAGE1_LD=${STAGE1_LD:-$STAGE1_CXX}
# canonicalize paths and check that all tools exist
for tool in CC CXX AR RANLIB LD; do
  var=STAGE1_$tool
  tool=${!var}
  [[ "$tool" == *"/"* ]] || declare "$var=$(command -v "$tool" || true)"
  tool=${!var}
  [ -x "$tool" ] || _err "$tool not found ($var)"
done

HOST_CC="$LLVM_HOST/bin/clang"
HOST_CXX="$LLVM_HOST/bin/clang++"
HOST_ASM=$HOST_CC
HOST_LD=$HOST_CC
HOST_RC="$LLVM_HOST/bin/llvm-rc"
HOST_AR="$LLVM_HOST/bin/llvm-ar"
HOST_RANLIB="$LLVM_HOST/bin/llvm-ranlib"

HOST_STAGE2_CC=$HOST_CC
HOST_STAGE2_CXX=$HOST_CXX
HOST_STAGE2_ASM=$HOST_STAGE2_CC
HOST_STAGE2_LD=$HOST_STAGE2_CC
HOST_STAGE2_RC=$HOST_RC
HOST_STAGE2_AR=$HOST_AR
HOST_STAGE2_RANLIB=$HOST_RANLIB

# prefer clang from current system over gcc
[ -z "${CC:-}" ]  && command -v clang >/dev/null && export CC=clang
[ -z "${CXX:-}" ] && command -v clang++ >/dev/null && export CXX=clang++

# flags for compiling for target, after sysroot has been initialized
TARGET_COMMON_FLAGS=(
  -B"$LLVMBOX_SYSROOT/bin" \
  --sysroot="$LLVMBOX_SYSROOT" \
  -isystem "$LLVMBOX_SYSROOT/include" \
  --target=$TARGET \
)
TARGET_CFLAGS=(
  "${TARGET_COMMON_FLAGS[@]}" \
)
TARGET_LDFLAGS=(
  "${TARGET_COMMON_FLAGS[@]}" \
  -fuse-ld=lld \
)

case "$TARGET_SYS" in
  apple|darwin|macos)
    MACOS_SDK=$(xcrun -sdk macosx --show-sdk-path)
    [ -d "$MACOS_SDK" ] ||
      _err "macos sdk not found at $MACOS_SDK; try running: xcode-select --install"
    TARGET_CFLAGS+=( -mmacosx-version-min=10.10 )
    TARGET_LDFLAGS+=( -mmacosx-version-min=10.10 )
    ;;
  linux)
    HOST_STAGE2_CC=$PROJECT/utils/musl-clang
    HOST_STAGE2_CXX=$PROJECT/utils/musl-clang++
    HOST_STAGE2_ASM=$HOST_STAGE2_CC
    HOST_STAGE2_LD=$HOST_STAGE2_CC
    TARGET_LDFLAGS+=(\
      -static-libgcc \
    )
    ;;
esac

# ————————————————————————————————————————————————————————————————————————————————————
# functions

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
}

_relpath() { # <path>
  local f="${1/$HOME\//~/}"
  echo "${f##$PWD0/}"
}

_sha_test() { # <file> [<sha256> | <sha512>]
  local file=$1 ; local expect=$2
  [ -f "$file" ] || return 1
  case "${#expect}" in
    128) kind=512; actual=$(sha512sum "$file" | cut -d' ' -f1) ;;
    64)  kind=256; actual=$(sha256sum "$file" | cut -d' ' -f1) ;;
    *)   _err "checksum $expect has incorrect length (not sha256 nor sha512)" ;;
  esac
  [ "$actual" = "$actual" ] || return 1
}

_sha_verify() { # <file> [<sha256> | <sha512>]
  local file=$1
  local expect=$2
  local actual=
  case "${#expect}" in
    128) kind=512; actual=$(sha512sum "$file" | cut -d' ' -f1) ;;
    64)  kind=256; actual=$(sha256sum "$file" | cut -d' ' -f1) ;;
    *)   _err "checksum $expect has incorrect length (not sha256 nor sha512)" ;;
  esac
  if [ "$actual" != "$expect" ]; then
    echo "$file: SHA-$kind sum mismatch:" >&2
    echo "  actual:   $actual" >&2
    echo "  expected: $expect" >&2
    return 1
  fi
}

_download_nocache() { # <url> <outfile> [<sha256> | <sha512>]
  local url=$1 ; local outfile=$2 ; local checksum=${3:-}
  rm -f "$outfile"
  echo "${outfile##$PWD0/}: fetch $url"
  command -v wget >/dev/null &&
    wget -q --show-progress -O "$outfile" "$url" ||
    curl -L '-#' -o "$outfile" "$url"
  [ -z "$checksum" ] || _sha_verify "$outfile" "$checksum"
}

_download() { # <url> <outfile> [<sha256> | <sha512>]
  local url=$1 ; local outfile=$2 ; local checksum=${3:-}
  if [ -f "$outfile" -a -z "$checksum" ] || _sha_test "$outfile" "$checksum"; then
    return 0
  fi
  _download_nocache "$url" "$outfile" "$checksum"
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

_fetch_source_tar() { # <url> (<sha256> | <sha512> | "") <outdir> [<tarfile>]
  [ $# -gt 2 ] || _err "_fetch_source_tar ($#)"
  local url=$1
  local checksum=$2
  local outdir=$3
  local tarfile=${4:-$DOWNLOAD_DIR/$(basename "$url")}
  _download    "$url" "$tarfile" "$checksum"
  _extract_tar "$tarfile" "$outdir"
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
