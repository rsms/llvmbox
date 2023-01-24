# 
# should source this file
#
set -euo pipefail

# note: zig on macOS 10 is broken starting with zig 0.10.0
ZIGVER=0.10.1
ZIGSRC_SHA256=69459bc804333df077d441ef052ffa143d53012b655a51f04cfef1414c04168c
ZIGSRC=$OUT_DIR/src/zig-$ZIGVER
ZIGSYS=
case "$HOST_SYS" in
  Darwin)  ZIGSYS=macos ;;
  Linux)   ZIGSYS=linux ;;
  Windows) _err "windows not supported" ;;
  *)       _err "zig is not available for HOST_SYS=$HOST_SYS"
esac
ZIGBIN=$BUILD_DIR/zig-$ZIGSYS-$HOST_ARCH-$ZIGVER

export PATH=$ZIGBIN:$PATH

[ -x $ZIGBIN/zig ] || _fetch_source_tar \
  https://ziglang.org/download/$ZIGVER/zig-$ZIGSYS-$HOST_ARCH-$ZIGVER.tar.xz \
  "" "$ZIGBIN"
