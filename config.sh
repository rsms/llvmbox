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
[ -n "$LLVMBOX_BUILD_DIR" ] || _err "LLVMBOX_BUILD_DIR is not set in env"

PROJECT=$(realpath -s "$(dirname "$0")")
BUILD_DIR=$(realpath -s "$LLVMBOX_BUILD_DIR")
DOWNLOAD_DIR=$(realpath -s "${LLVMBOX_DOWNLOAD_DIR:-$PROJECT/download}")
mkdir -p "$DOWNLOAD_DIR" "$BUILD_DIR"
# ————————————————————————————————————————————————————————————————————————————————————

HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)

TARGET=$LLVMBOX_TARGET  # e.g. x86_64-macos-none, aarch64-linux-gnu
if [ -z "$TARGET" ]; then
  case "$HOST_SYS" in
    Darwin) TARGET=$HOST_ARCH-macos-none ;;
    Linux)  TARGET=$HOST_ARCH-linux-gnu ;;
    *)      _err "couldn't guess TARGET from $HOST_SYS"
  esac
fi
TARGET_SYS_AND_ABI=${TARGET#*-} # e.g. linux-musl
TARGET_SYS=${TARGET_SYS_AND_ABI%-*} # e.g. linux
TARGET_ARCH=${TARGET%%-*} # e.g. x86_64

# ————————————————————————————————————————————————————————————————————————————————————

LLVM_RELEASE=15.0.7
LLVM_SHA256=42a0088f148edcf6c770dfc780a7273014a9a89b66f357c761b4ca7c8dfa10ba
LLVM_SRC=$BUILD_DIR/llvm-src
LLVM_HOST=$BUILD_DIR/llvm-host
LLVM_DIST=$BUILD_DIR/llvm-$TARGET

ZLIB_VERSION=1.2.13
ZLIB_CHECKSUM=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30
ZLIB_SRC=$BUILD_DIR/zlib-src
ZLIB_HOST=$BUILD_DIR/zlib-host
ZLIB_DIST=$BUILD_DIR/zlib-$TARGET

HOST_CC="$LLVM_HOST/bin/clang"
HOST_CXX="$LLVM_HOST/bin/clang++"
HOST_ASM=$HOST_CC
HOST_LD=$HOST_CC
HOST_RC="$LLVM_HOST/bin/llvm-rc"
HOST_AR="$LLVM_HOST/bin/llvm-ar"
HOST_RANLIB="$LLVM_HOST/bin/llvm-ranlib"

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
  local tarfile=$DOWNLOAD_DIR/$(basename "$url")
  local stampfile=$tarfile.sha256
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
