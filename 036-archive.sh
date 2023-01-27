#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

TARFILE="$LLVMBOX_DESTDIR.tar.xz"
echo "creating $(_relpath "$TARFILE")"
XZ_OPT='-T0' tar \
  -C "$(dirname "$LLVMBOX_DESTDIR")" \
  -cJpf "$TARFILE" \
  "$(basename "$LLVMBOX_DESTDIR")"
