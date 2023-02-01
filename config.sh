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
NCPU=${LLVMBOX_NCPU:-$(nproc)}; [ -n "$NCPU" ] || NCPU=$(nproc)
HOST_SYS=$(uname -s)
HOST_ARCH=$(uname -m)

# apple still uses the legacy name "arm64" (renamed to aarch64 in llvm, may 2014)
[ "$HOST_ARCH" != "arm64" ] || HOST_ARCH=aarch64

# ————————————————————————————————————————————————————————————————————————————————————

_version_gte() { # <v> <minv>
  local v1 v2 v3 min_v1 min_v2 min_v3
  IFS=. read -r v1 v2 v3 <<< "$1"
  IFS=. read -r min_v1 min_v2 min_v3 <<< "$2"
  [ -n "$min_v2" ] || min_v2=0
  [ -n "$min_v3" ] || min_v3=0
  [ -n "$v2" ] || v2=$min_v2
  [ -n "$v3" ] || v3=$min_v3
  # echo "v   $v1 $v2 $v3"
  # echo "min $min_v1 $min_v2 $min_v3"
  if [ "$v1" -lt "$min_v1" ]; then return 1; fi
  if [ "$v1" -gt "$min_v1" ]; then return 0; fi
  if [ "$v2" -lt "$min_v2" ]; then return 1; fi
  if [ "$v2" -gt "$min_v2" ]; then return 0; fi
  if [ "$v3" -lt "$min_v3" ]; then return 1; fi
  if [ "$v3" -gt "$min_v3" ]; then return 0; fi
}

TARGET=${LLVMBOX_TARGET:-}  # e.g. aarch64-linux, x86_64-macos, x86_64-macos.11.7
TARGET_ARCH=                # e.g. x86_64, aarch64
TARGET_SYS=                 # e.g. linux, macos, macos.11.7
TARGET_SYS_VERSION=         # e.g. 11.7 (from macos.11.7) -- OS ABI (M.m[.p])
TARGET_SYS_VERSION_MAJOR=   # e.g. 11
TARGET_SYS_MINVERSION=      # compatibility version of OS ABI
TARGET_SYS=                 # e.g. macos (from macos.11.7)
TARGET_TRIPLE=              # e.g. x86_64-linux-gnu (for clang/llvm)
TARGET_CMAKE_SYSTEM_NAME=   # e.g. Linux
if [ -z "$TARGET" ]; then
  case "$HOST_SYS" in
    Darwin) TARGET=$HOST_ARCH-macos ;;
    Linux)  TARGET=$HOST_ARCH-linux ;;
    *)      _err "couldn't guess TARGET from $HOST_SYS"
  esac
fi
TARGET_ARCH=${TARGET%-*}
TARGET_SYS=${TARGET#*-}
if [[ "$TARGET_SYS" == *"."* ]]; then
  TARGET_SYS_VERSION=${TARGET_SYS#*.} # macos.11.7 => 11.7
  TARGET_SYS=${TARGET_SYS%%.*}        # macos.11.7 => macos
fi
[ "$TARGET_SYS" = native ] && case "$HOST_SYS" in
  Darwin) TARGET_SYS=macos ;;
  Linux)  TARGET_SYS=linux ;;
  *) _err "$TARGET: couldn't guess TARGET_SYS from HOST_SYS=$HOST_SYS"
esac
case "$TARGET_SYS" in
  macos)
    TARGET_CMAKE_SYSTEM_NAME="Darwin"
    TARGET_TRIPLE=$TARGET_ARCH-apple-darwin ;;
  freebsd)
    TARGET_CMAKE_SYSTEM_NAME="FreeBSD"
    TARGET_TRIPLE=$TARGET_ARCH-freebsd-gnu ;;
  windows)
    TARGET_CMAKE_SYSTEM_NAME="Windows"
    TARGET_TRIPLE=$TARGET_ARCH-windows-gnu ;;
  linux)
    TARGET_CMAKE_SYSTEM_NAME="Linux"
    TARGET_TRIPLE=$TARGET_ARCH-linux-gnu ;; # gotta be "gnu" until after stage2
  *) _err "unsupported TARGET system '$TARGET_SYS' in '$TARGET'"
esac
# set TARGET_SYS_MINVERSION (oldest OS ABI we support.)
# Note: macOS SDKs didn't ship with complete libSystem.tbd files until 10.15
case "$TARGET_ARCH-$TARGET_SYS" in
  x86_64-macos)  TARGET_SYS_MINVERSION=10.15 ;;
  aarch64-macos) TARGET_SYS_MINVERSION=11.0 ;;
  *)             TARGET_SYS_MINVERSION=0.0 ;;
esac

# check so that TARGET_SYS_VERSION >= TARGET_SYS_MINVERSION
if [ -z "$TARGET_SYS_VERSION" ]; then
  TARGET_SYS_VERSION=$TARGET_SYS_MINVERSION
elif [[ "$TARGET_SYS_VERSION" =~ ^[0-9]+(\.[0-9]+(\.[0-9]+)?)?$ ]]; then
  _version_gte "$TARGET_SYS_VERSION" "$TARGET_SYS_MINVERSION" ||
    _err "TARGET version $TARGET_SYS_VERSION too old, older than the minimum $TARGET_SYS_MINVERSION"
else
  _err "invalid TARGET version format '$TARGET_SYS_VERSION'; expected M[.m[.p]]"
fi
TARGET_SYS_VERSION_MAJOR=${TARGET_SYS_VERSION%%.*}  # e.g. 1 in 1.2.3

# TARGET_DARWIN_VERSION is the darwin version corresponding to the os version.
# See: https://en.wikipedia.org/wiki/Darwin_(operating_system)#Release_history
TARGET_DARWIN_VERSION=
[ "$TARGET_SYS" != macos ] || case "$TARGET_SYS_VERSION" in
  10.15) TARGET_DARWIN_VERSION=19.0.0 ;;
  11.5)  TARGET_DARWIN_VERSION=20.6.0 ;;
  12.5)  TARGET_DARWIN_VERSION=21.6.0 ;;
  *)
    # default to major version (macos 10.x = darwin 19.x, 11.x = 20.x, ...)
    TARGET_DARWIN_VERSION=$(( $TARGET_SYS_VERSION_MAJOR + 9 )) ;;
esac

# rewrite TARGET to canonical form arch-sysname-sysversionmajor
TARGET=$TARGET_ARCH-$TARGET_SYS
[ "$TARGET_SYS_VERSION_MAJOR" = 0 ] || TARGET=$TARGET.$TARGET_SYS_VERSION_MAJOR

SYSROOTS_DIR=$PROJECT/sysroots
LLVMBOX_SYSROOT_BASE=${LLVMBOX_SYSROOT_BASE:-$OUT_DIR/sysroot}
LLVMBOX_SYSROOT=${LLVMBOX_SYSROOT:-$LLVMBOX_SYSROOT_BASE/$TARGET}
export LLVMBOX_SYSROOT

# ————————————————————————————————————————————————————————————————————————————————————

LLVM_RELEASE=15.0.7  # reset LLVMBOX_VERSION_TAG when upgrading
LLVM_SHA256=42a0088f148edcf6c770dfc780a7273014a9a89b66f357c761b4ca7c8dfa10ba
LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive/llvmorg-${LLVM_RELEASE}.tar.gz
[[ "$LLVM_RELEASE" != *"."* ]] && # git snapshot
  LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive/${LLVM_RELEASE}.tar.gz
LLVM_SRC_STAGE1=${LLVM_SRC_STAGE1:-$OUT_DIR/src/llvm-stage1}
LLVM_SRC=${LLVM_SRC:-$OUT_DIR/src/llvm}
LLVM_STAGE1=${LLVM_STAGE1:-$OUT_DIR/llvm-stage1}
LIBCXX_STAGE2=${LIBCXX_STAGE2:-$OUT_DIR/libcxx-stage2}
LLVM_STAGE2=${LLVM_STAGE2:-$OUT_DIR/llvm-stage2}

LLVMBOX_VERSION_TAG=1
LLVMBOX_RELEASE_ID=$LLVM_RELEASE+$LLVMBOX_VERSION_TAG-$TARGET_ARCH-$TARGET_SYS
LLVMBOX_DESTDIR=${LLVMBOX_DESTDIR:-$OUT_DIR/llvmbox-$LLVMBOX_RELEASE_ID}
LLVMBOX_DEV_DESTDIR=${LLVMBOX_DEV_DESTDIR:-$OUT_DIR/llvmbox-dev-$LLVMBOX_RELEASE_ID}

ZLIB_VERSION=1.2.13
ZLIB_SHA256=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30
ZLIB_SRC=${ZLIB_SRC:-$BUILD_DIR/src/zlib}
ZLIB_STAGE1=${ZLIB_HOST:-$OUT_DIR/zlib-stage1}
ZLIB_STAGE2=${ZLIB_DIST:-$OUT_DIR/zlib-$TARGET}

ZSTD_VERSION=1.5.2
ZSTD_SHA256=7c42d56fac126929a6a85dbc73ff1db2411d04f104fae9bdea51305663a83fd0
ZSTD_SRC=${ZSTD_SRC:-$BUILD_DIR/src/zstd}
ZSTD_STAGE2=${ZSTD_DIST:-$OUT_DIR/zstd-$TARGET}

XZ_VERSION=5.2.5
XZ_SHA256=3e1e518ffc912f86608a8cb35e4bd41ad1aec210df2a47aaa1f95e7f5576ef56
XZ_SRC=${XZ_SRC:-$BUILD_DIR/src/xc}
XZ_STAGE2=${XZ_DESTDIR:-$OUT_DIR/xc-$TARGET}

LIBXML2_VERSION=2.10.3
LIBXML2_SHA256=5d2cc3d78bec3dbe212a9d7fa629ada25a7da928af432c93060ff5c17ee28a9c
LIBXML2_SRC=${LIBXML2_SRC:-$BUILD_DIR/src/libxml2}
LIBXML2_STAGE2=${LIBXML2_DESTDIR:-$OUT_DIR/libxml2-$TARGET}

OPENSSL_VERSION=1.1.1s
OPENSSL_SHA256=c5ac01e760ee6ff0dab61d6b2bbd30146724d063eb322180c6f18a6f74e4b6aa
OPENSSL_SRC=${OPENSSL_SRC:-$BUILD_DIR/src/openssl}
OPENSSL_STAGE2=${OPENSSL_DESTDIR:-$OUT_DIR/openssl-$TARGET}

XAR_SRC=${XAR_SRC:-$BUILD_DIR/src/xar}
XAR_STAGE2=${XAR_DESTDIR:-$OUT_DIR/xar-$TARGET}

LINUX_VERSION=6.1.7
LINUX_VERSION_MAJOR=${LINUX_VERSION%%.*}
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
  STAGE1_LDFLAGS="-static-libgcc"
elif [ "$HOST_SYS" = "Darwin" ]; then
  HOST_MACOS_SDK=$(xcrun -sdk macosx --show-sdk-path)
  [ -d "$HOST_MACOS_SDK" ] || _err "macOS SDK not found. Try: xcode-select --install"
  STAGE1_CC="$(command -v  clang || true)"
  STAGE1_CXX="$(command -v clang++ || true)"
  STAGE1_MACOS_VERSION=10.10
  [ "$HOST_ARCH" != x86_64 ] && STAGE1_MACOS_VERSION=11.7
  STAGE1_CFLAGS="$STAGE1_CFLAGS -mmacosx-version-min=$TARGET_SYS_MINVERSION"
  STAGE1_LDFLAGS="$STAGE1_LDFLAGS -mmacosx-version-min=$TARGET_SYS_MINVERSION"
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

# ————————————————————————————————————————————————————————————————————————————————————

STAGE2_CC="$LLVM_STAGE1/bin/clang"
STAGE2_CXX="$LLVM_STAGE1/bin/clang++"
STAGE2_ASM=$STAGE2_CC
STAGE2_LD=$STAGE2_CC
STAGE2_RC="$LLVM_STAGE1/bin/llvm-rc"
STAGE2_AR="$LLVM_STAGE1/bin/llvm-ar"
STAGE2_RANLIB="$LLVM_STAGE1/bin/llvm-ranlib"
STAGE2_LIBTOOL="$LLVM_STAGE1/bin/llvm-libtool-darwin"
STAGE2_OPT="$LLVM_STAGE1/bin/opt"
STAGE2_LLC="$LLVM_STAGE1/bin/llc"
STAGE2_LLVM_LINK="$LLVM_STAGE1/bin/llvm-link"

STAGE2_CFLAGS=(
  --target=$TARGET_TRIPLE \
  --sysroot="$LLVMBOX_SYSROOT" \
  -isystem"$LLVMBOX_SYSROOT/include" \
)
STAGE2_LDFLAGS=(
  --target=$TARGET_TRIPLE \
  --sysroot="$LLVMBOX_SYSROOT" \
  --rtlib=compiler-rt \
  -L"$LLVMBOX_SYSROOT/lib" \
  -Wl,-rpath,"$LLVMBOX_SYSROOT/lib" \
)
STAGE2_LDFLAGS_EXE=()

# Set LLVMBOX_ENABLE_LTO=1 or 0 to enable or disable ThinLTO.
# See file lto.md
# See https://clang.llvm.org/docs/ThinLTO.html
case "${LLVMBOX_ENABLE_LTO:-}" in
  1|true|yes|"") LLVMBOX_ENABLE_LTO=true ;;
  0|false|no)    LLVMBOX_ENABLE_LTO=false ;;
  *) _err "unexpected value of LLVMBOX_ENABLE_LTO \"$LLVMBOX_ENABLE_LTO\"" ;;
esac
STAGE2_LTO_CACHE="$BUILD_DIR/lto-cache"
STAGE2_LTO_CFLAGS=
STAGE2_LTO_LDFLAGS=
if $LLVMBOX_ENABLE_LTO; then
  # note: do NOT set --target for STAGE2_LDFLAGS
  STAGE2_LTO_CFLAGS=( -flto=thin )
  STAGE2_LTO_LDFLAGS=( -flto=thin )
  case "$TARGET_SYS" in
    macos)
      STAGE2_LTO_LDFLAGS+=( "-Wl,-cache_path_lto,$STAGE2_LTO_CACHE" )
      ;;
    linux)
      STAGE2_LTO_CFLAGS+=( --target=$TARGET_ARCH-unknown-linux-musl )
      STAGE2_LTO_LDFLAGS+=( "-Wl,--thinlto-cache-dir=$STAGE2_LTO_CACHE" )
      ;;
    *)
      echo "disabling LLVMBOX_ENABLE_LTO; not supported for $TARGET_SYS" >&2
      LLVMBOX_ENABLE_LTO=false
      STAGE2_LTO_CFLAGS=
      STAGE2_LTO_LDFLAGS=
      ;;
  esac
fi

case "$TARGET_SYS" in
  macos)
    STAGE2_CFLAGS+=(
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
      -mmacosx-version-min=$TARGET_SYS_VERSION \
    )
    STAGE2_LDFLAGS+=( -mmacosx-version-min=$TARGET_SYS_VERSION )
    # STAGE2_LDFLAGS+=( -L"$HOST_MACOS_SDK/usr/lib" )
    # STAGE2_CFLAGS+=( -mmacosx-version-min=$TARGET_SYS_MINVERSION \
    #   -isystem"$HOST_MACOS_SDK/usr/include" )
    # STAGE2_LDFLAGS+=( -mmacosx-version-min=$TARGET_SYS_MINVERSION )
    # STAGE2_CFLAGS+=( -I"$LLVMBOX_SYSROOT/include" )
    # STAGE2_LDFLAGS+=( -L"$LLVMBOX_SYSROOT/lib" )
    ;;
  linux)
    STAGE2_LDFLAGS_EXE+=( \
      -nostartfiles "$LLVMBOX_SYSROOT/lib/crt1.o" \
    )
    ;;
esac
STAGE2_LDFLAGS_EXE=( "${STAGE2_LDFLAGS[@]}" "${STAGE2_LDFLAGS_EXE[@]:-}" )

# ————————————————————————————————————————————————————————————————————————————————————
# functions

_relpath() { # <path>
  case "$1" in
    "$PWD0/"*) echo "${1##$PWD0/}" ;;
    "$PWD0")   echo "." ;;
    "$HOME/"*) echo "~${1:${#HOME}}" ;;
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

_sha_test() { # <file> [<sha256> | <sha512>]
  local file=$1 ; local expect=$2
  [ -f "$file" ] || return 1
  case "${#expect}" in
    128) kind=512; actual=$(sha512sum "$file" | cut -d' ' -f1) ;;
    64)  kind=256; actual=$(sha256sum "$file" | cut -d' ' -f1) ;;
    *)   _err "checksum $expect has incorrect length (not sha256 nor sha512)" ;;
  esac
  [ "$actual" = "$expect" ] || return 1
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
  mkdir -p "$(dirname "$outfile")"
  echo "${outfile##$PWD0/}: fetch $url"
  command -v wget >/dev/null &&
    wget -O "$outfile" "$url" ||
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

_create_tar_xz_from_dir() { # <srcdir> <dstfile>
  command -v tar >/dev/null || _err "can't find \"tar\" in PATH"
  [[ "$2" == *".tar.xz" ]] || _err "$2 doesn't end with .tar.xz" # avoid ambiguity
  local srcdir="$(realpath "$1")"
  if command -v xz >/dev/null; then
    tar -C "$(dirname "$srcdir")" -c "$(basename "$srcdir")" | xz -9 -f -T0 -v > "$2"
  else
    XZ_OPT='-9 -T0' tar -C "$(dirname "$srcdir")" -cJpf "$2" "$(basename "$srcdir")"
  fi
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

_copyinto() {
  echo "rsync $(_relpath "$1") -> $(_relpath "$2")"
  rsync -a \
    --exclude "*.DS_Store" \
    --exclude "*/.git*" \
    --exclude ".git*" \
    "$@"
}

_symlink() { # <linkfile-to-create> <target>
  echo "symlink $(_relpath "$1") -> $(_relpath "$2")"
  [ ! -e "$1" ] || [ -L "$1" ] || _err "$(_relpath "$1") exists (not a link)"
  rm -f "$1"
  ln -fs "$2" "$1"
}

_human_filesize() { # <file>
  local Z
  if [ "$HOST_SYS" = "Darwin" ]; then
    Z=$(stat -f "%z" "$1")
  else
    Z=$(stat -c "%s" "$1")
  fi
  if [ $Z -gt 1073741824 ]; then
    awk "BEGIN{printf \"%.1f GB\n\", $Z / 1073741824}"
  elif [ $Z -gt 1048575 ]; then
    awk "BEGIN{printf \"%.1f MB\n\", $Z / 1048576}"
  elif [ $Z -gt 1023 ]; then
    awk "BEGIN{printf \"%.1f kB\n\", $Z / 1024}"
  else
    awk "BEGIN{printf \"%.0f B\n\", $Z}"
  fi
  shift
}

_print_linking() { # <file>
  local OUT
  local objdump="$LLVM_STAGE1/bin/llvm-objdump"
  [ -f "$objdump" ] || objdump=objdump
  local PAT='NEEDED|RUNPATH|RPATH'
  case "$HOST_SYS" in
    Darwin) PAT='RUNPATH|RPATH|\.dylib' ;;
  esac
  OUT=$( "$objdump" -p "$1" | grep -E "$PAT" | awk '{printf $1 " " $2 "\n"}' || true )
  if [ -n "$OUT" ]; then
    echo "$(_relpath "$1") is dynamically linked:"
    echo "$OUT"
  else
    echo "$(_relpath "$1") is statically linked."
  fi
}
