#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

set -x
rm -rf "$LLVMBOX_SYSROOT"
mkdir -p "$LLVMBOX_SYSROOT"/{lib,include}
