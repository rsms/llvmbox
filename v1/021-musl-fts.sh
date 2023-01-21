#!/bin/bash
set -e
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/config-target-env.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

# This builds a pre-configured version of the musl-fts distribution
# which uses a mess of a build system (autotools, ugh).
# To update a new dist:
#   Step 1:
#     wget https://github.com/void-linux/musl-fts/archive/refs/tags/v1.2.7.tar.gz
#     tar -xf musl-fts-1.2.7.tar
#     rm -rf /tmp/new-musl-fts
#     mv musl-fts /tmp/new-musl-fts
#     cd /tmp/new-musl-fts
#     # apt install autoconf automake libtool
#     ./bootstrap.sh
#   Step 2: uncomment the following lines
#     cd /tmp/new-musl-fts
#     CC=$HOST_CC \
#     AR=$HOST_AR \
#     RANLIB=$HOST_RANLIB \
#     CFLAGS="${TARGET_CFLAGS[@]}" \
#     ./configure --prefix= && make clean && make
#     cp -a config.h fts.c fts.h /PATH/TO/SRC/llvm/musl-fts
#     exit
#   Step 3:
#     bash 021-musl-fts.sh
#   Step 4: Restore above lines ^ by commenting them out again
#   Step 5: Update the rest of this script based on make commands
#

rm -rf "$MUSLFTS_SRC"
mkdir -p "$(dirname "$MUSLFTS_SRC")"
cp -a "$PROJECT/musl-fts" "$MUSLFTS_SRC"

_pushd "$MUSLFTS_SRC"

set -x
"$HOST_CC" -DHAVE_CONFIG_H -I. "${TARGET_CFLAGS[@]}" -c fts.c -o fts.o
"$HOST_AR" cr libfts.a fts.o
"$HOST_RANLIB" libfts.a
install -D libfts.a "$MUSLFTS_DESTDIR/lib/libfts.a"
install -D fts.h "$MUSLFTS_DESTDIR/include/fts.h"
