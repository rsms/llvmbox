#!/bin/bash
set -euo pipefail
_err() { echo "$0:" "$@" >&2; exit 1; }
PROJECT="`cd "$(dirname "$0")"; pwd`"

MB=${1:-16384}  # default to 16G

[ -n "${LLVMBOX_BUILD_DIR:-}" ] || _err "LLVMBOX_BUILD_DIR is not set"

# make sure LLVMBOX_BUILD_DIR is a dir and is empty, if it exists (else error)
[ -e "$LLVMBOX_BUILD_DIR" ] && rmdir "$LLVMBOX_BUILD_DIR" ||
  _err "LLVMBOX_BUILD_DIR is not an empty directory"
mkdir "$LLVMBOX_BUILD_DIR"

case "$(uname -s)" in
  Darwin)
    set -x
    "$PROJECT/utils/macos-tmpfs.sh" "$LLVMBOX_BUILD_DIR" $MB
    ;;
  Linux)
    if [ "$(id -u || true)" = "0" ]; then
      set -x
      mount -t tmpfs -o size=${MB}M tmpfs "$LLVMBOX_BUILD_DIR"
    else
      set -x
      exec sudo mount -t tmpfs -o size=${MB}M tmpfs "$LLVMBOX_BUILD_DIR"
    fi
    ;;
  *)
    echo "$0: don't know how to make tmpfs on $(uname -s)" >&2
    exit 1
    ;;
esac
