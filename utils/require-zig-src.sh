# 
# should source this file
#
source "$PROJECT/utils/require-zig.sh"
set -euo pipefail

[ -f "$ZIGSRC/build.zig" ] || _fetch_source_tar \
  https://ziglang.org/download/$ZIGVER/zig-$ZIGVER.tar.xz \
  69459bc804333df077d441ef052ffa143d53012b655a51f04cfef1414c04168c \
  "$ZIGSRC"
