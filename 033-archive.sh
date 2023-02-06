#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

for dir in "$LLVMBOX_DESTDIR" "$LLVMBOX_DEV_DESTDIR"; do
  echo "creating $(_relpath "$dir.tar.xz")"
  _create_tar_xz_from_dir "$dir" "$dir.tar.xz"
done
