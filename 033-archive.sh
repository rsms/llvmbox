#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

for dir in "$LLVMBOX_DESTDIR" "$LLVMBOX_DEV_DESTDIR"; do
  # remove any unwanted files
  find "$(_relpath "$dir")" -type f -name '.DS_Store' -delete -exec echo "rm {}" \;
  echo "creating $(_relpath "$dir.tar.xz")"
  _create_tar_xz_from_dir "$dir" "$dir.tar.xz"
done
