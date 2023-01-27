#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

echo "creating $(_relpath "$LLVMBOX_DESTDIR.tar.xz")"
_create_tar_xz_from_dir "$LLVMBOX_DESTDIR" "$LLVMBOX_DESTDIR.tar.xz"
