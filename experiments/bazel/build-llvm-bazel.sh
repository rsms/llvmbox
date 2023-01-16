#!/bin/bash
set -e

PWD0=${PWD0:-$PWD}
SCRIPTNAME=${0##*/}
PROJECT=$PWD
BUILD_DIR=${BUILD_DIR:-$PROJECT/build}

# ————————————————————————————————————————————————————————————————————————————————————

LLVM_RELEASE=15.0.7
LLVM_SHA256=42a0088f148edcf6c770dfc780a7273014a9a89b66f357c761b4ca7c8dfa10ba
# LLVM_RELEASE=eb4aa6c7a5f22583e319aaaae3f6ee73cbc5464a
# LLVM_SHA256=7c6919bde160a94a5f9c1f93c337fb6fdb9215571a8bbb385aed598763ff59ab
LLVM_SRC=${LLVM_SRC:-$BUILD_DIR/llvm-$LLVM_RELEASE}

BAZEL_CACHE_DIR=${BAZEL_CACHE_DIR:-$BUILD_DIR/bazel-cache}
BAZEL_SANDBOX_BASE=${BAZEL_SANDBOX_BASE:-$BUILD_DIR/bazel-sandbox}

# ————————————————————————————————————————————————————————————————————————————————————
# functions

_err() { echo "$SCRIPTNAME:" "$@" >&2; exit 1; }

_relpath() { # <path>
  case "$1" in
    "$PWD0/"*) echo "${1##${2:-$PWD0}/}" ;;
    "$PWD0")   echo "." ;;
    *)         echo "$1" ;;
  esac
}

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
    echo "${tarfile##$PWD0/}: no longer needed"
  fi
}

# ————————————————————————————————————————————————————————————————————————————————————

# llvm source
LLVM_SRC_URL=https://github.com/llvm/llvm-project/archive
if (echo "$LLVM_RELEASE" | grep -qE '[0-9]+\.'); then
  # release version
  LLVM_SRC_URL=$LLVM_SRC_URL/llvmorg-${LLVM_RELEASE}.tar.gz
else
  # git hash
  LLVM_SRC_URL=$LLVM_SRC_URL/${LLVM_RELEASE}.tar.gz
fi
_fetch_source_tar "$LLVM_SRC_URL" "$LLVM_SHA256" "$LLVM_SRC"

# tools PATH
TOOLS_DIR=$PROJECT/tools
mkdir -p "$TOOLS_DIR"
export PATH=$TOOLS_DIR:$PATH

# bazel
BAZEL_VERSION=$(cat "$LLVM_SRC/utils/bazel/.bazelversion")
case "$(uname -s)" in
  Linux)  BAZEL_EXE=bazel-${BAZEL_VERSION}-linux-$(uname -m) ;;
  Darwin) BAZEL_EXE=bazel-${BAZEL_VERSION}-darwin-$(uname -m) ;;
  *)      _err "unsupported system: $(uname -s)"
esac
_download \
  https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/$BAZEL_EXE \
  "$TOOLS_DIR/$BAZEL_EXE"
chmod +x "$TOOLS_DIR/$BAZEL_EXE"
ln -f -s "$BAZEL_EXE" "$TOOLS_DIR/bazel"
mkdir -p "$BAZEL_CACHE_DIR" "$BAZEL_SANDBOX_BASE"
bazel --version

# build llvm with bazel
BAZEL_ARGS=()
if command -v clang >/dev/null; then
  BAZEL_ARGS+=(
    --repo_env=CC=$(command -v clang) \
    --config=generic_clang \
  )
elif command -v gcc >/dev/null; then
  BAZEL_ARGS+=(
    --repo_env=CC=$(command -v gcc) \
    --config=generic_gcc \
  )
else
  _err "no host compiler found (tried: clang, gcc)"
fi


mkdir -p "$PROJECT/out"

pushd "$LLVM_SRC/utils/bazel" >/dev/null ; pwd

# dump huge list of targets:
#bazel query @llvm-project//...

bazel \
  --output_base="$PROJECT/out" \
  build \
    --disk_cache="$BAZEL_CACHE_DIR" \
    --sandbox_base="$BAZEL_SANDBOX_BASE" \
    "${BAZEL_ARGS[@]}" \
    @llvm-project//clang
popd >/dev/null

"$PROJECT/out"/execroot/__main__/bazel-out/*/bin/external/llvm-project/clang/clang --version
