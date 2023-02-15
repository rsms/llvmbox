#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="${DESTDIR:-$LLVMBOX_DESTDIR}"
LLVMBOXID=llvmbox-$LLVM_RELEASE+$LLVMBOX_VERSION_TAG

# ————————————————————————————————————————————————————————————————————————————————————
# create "targets" dir, containing system headers & libs

rm -rf "$DESTDIR/targets"
mkdir -p "$(dirname "$DESTDIR/targets")"

_copy "$SYSROOTS_DIR/include" "$DESTDIR/targets/"

rm -rf "$PROJECT/llvmbox-tools/.obj"
echo make -C "$PROJECT/llvmbox-tools"
     make -C "$PROJECT/llvmbox-tools" -j$NCPU \
      LLVM_VERSION=$LLVM_RELEASE \
      LLVMBOX_VERSION=$LLVMBOX_VERSION_TAG

"$PROJECT/llvmbox-tools/dedup-target-files" "$DESTDIR/targets"

# remove "-suffix" dirs by merging with corresponding non-suffix dirs.
# e.g. "any-linux-libc" -> "any-linux"
for suffix in "-libc"; do
  for f in "$DESTDIR/targets"/*${suffix}; do
    [ -d "$f" ] || continue
    dstdir=${f%*${suffix}}
    echo "merge $(_relpath "$f") -> $(_relpath "$dstdir")"
    mkdir -p "$dstdir"
    "$PROJECT/llvmbox-tools/llvmbox-cpmerge" -v "$f" "$dstdir"
    rm -rf "$f"
  done
done

# rename targets/{target} -> targets/{target}/include
for d in "$DESTDIR/targets"/*; do
  [ -d "$d" ] || continue
  mv "$d" "$d.tmp"
  mkdir "$d"
  mv "$d.tmp" "$d/include"
done

# FIXME: There's a bug in dedup-target-files where it doesn't always succeed in
# removing empty directories, so we run a second pass here to catch any of those.
# In addition, we run this at the end, on the whole HEADERS_DESTDIR, to clean up
# any accidental empty dirs.
find "$(_relpath "$DESTDIR/targets")" \
  -empty -type d -delete -exec echo "remove empty dir {}" \;

# ————————————————————————————————————————————————————————————————————————————————————
# copy any .tbd lib files, per target, into "targets" dir

for d in "$SYSROOTS_DIR"/lib/*; do
  [ -d "$d" ] || continue
  target=$(basename "$d")
  mkdir -p "$DESTDIR/targets/$target"
  _copy "$d" "$DESTDIR/targets/$target/lib" &
done
wait

# ————————————————————————————————————————————————————————————————————————————————————
# add libraries to "src" dir
mkdir -p "$DESTDIR/src"

# copy libc sources
rm -rf "$DESTDIR/src/musl"
_copy "$SYSROOTS_DIR/libc/musl" "$DESTDIR/src/musl"
# Some musl source files will do: #include "../../include/features.h"
# so setup a symlink to the arch-less include dir.
ln -s ../../targets/any-linux/include "$DESTDIR/src/musl/include"

# copy compiler-rt sources
rm -rf "$DESTDIR/src/builtins"
_copy "$SYSROOTS_DIR/compiler-rt/builtins" "$DESTDIR/src/builtins"

# install llvmbox-tools
mkdir -p "$DESTDIR/bin"
install -v -m755 "$PROJECT/llvmbox-tools/llvmbox-config" "$DESTDIR/bin"
install -v -m755 "$PROJECT/llvmbox-tools/llvmbox-mksysroot" "$DESTDIR/bin"

# ————————————————————————————————————————————————————————————————————————————————————
# generate bin/clang-TARGET wrappers
EXTRA_DIST_TARGETS_U=()
EXTRA_DIST_TARGETS=()

_gen_clang_wrapper() { # <target>
  local target=$1 arch sys sysver target2 found triple
  local CFLAGS LDFLAGS USER_START= USER_END=
  IFS=- read -r arch sys <<< "$target"
  IFS=. read -r sys sysver <<< "$sys"
  triple=$(_fmt_triple $arch $sys $sysver)

  CFLAGS=( -fPIC )
  LDFLAGS=()

  # including TargetConditionals.h prevents "error: TARGET_OS_EMBEDDED is not defined"
  [ "$sys" = macos ] && CFLAGS+=(
    -Wno-nullability-completeness \
    -include TargetConditionals.h \
  )

  [ -d "$DESTDIR/targets/$arch-$sys.$sysver/include" ] &&
    CFLAGS+=( "-I\$LLVMBOX/targets/$arch-$sys.$sysver/include" )
  [ -d "$DESTDIR/targets/$arch-$sys/include" ] &&
    CFLAGS+=( "-I\$LLVMBOX/targets/$arch-$sys/include" )
  [ -d "$DESTDIR/targets/any-$sys/include" ] &&
    CFLAGS+=( "-I\$LLVMBOX/targets/any-$sys/include" )

  if [ -n "$sysver" ]; then
    [ -d "$DESTDIR/targets/any-$sys.$sysver/lib" ] &&
      LDFLAGS+=( "-L\$LLVMBOX/targets/any-$sys.$sysver/lib" )
    [ -d "$DESTDIR/targets/$arch-$sys/lib" ] &&
      LDFLAGS+=( "-L\$LLVMBOX/targets/$arch-$sys/lib" )
    found=
    for target2 in "${EXTRA_DIST_TARGETS_U[@]}"; do
      if [ "$target2" = "$arch-$sys" ]; then found=1; break; fi
    done
    if [ -z "$found" ]; then
      EXTRA_DIST_TARGETS_U+=( "$arch-$sys" )
      EXTRA_DIST_TARGETS+=( "$target" )
    fi
  fi

  [ -d "$DESTDIR/targets/any-$sys/lib" ] &&
    LDFLAGS+=( "-L\$LLVMBOX/targets/any-$sys/lib" )

  LDFLAGS+=( -lc -lrt -fPIE )

  if [ $sys = linux ]; then
    LDFLAGS+=( -nostartfiles -static \$LIB/crt1.o )
    USER_START=-L-user-start
    USER_END=-L-user-end
  fi

  echo "generate $(_relpath "$DESTDIR/bin/clang-$target")"
  sed -e "s!@LLVMBOXID@!$LLVMBOXID!g" \
      -e "s!@ARCH@!$arch!g" \
      -e "s!@SYS@!$sys!g" \
      -e "s!@TARGETID@!$target!g" \
      -e "s!@TRIPLE@!$triple!g" \
      -e "s!@CFLAGS@!${CFLAGS[*]}!g" \
      -e "s!@LDFLAGS@!${LDFLAGS[*]}!g" \
      -e "s!@USER_START@!$USER_START!g" \
      -e "s!@USER_END@!$USER_END!g" \
      "$PROJECT/utils/clang-TARGET.in" > "$DESTDIR/bin/clang-$target"
  chmod 0755 "$DESTDIR/bin/clang-$target"
  _symlink "$DESTDIR/bin/clang++-$target" "clang-$target"
}

IFS=$'\n' SUPPORTED_DIST_TARGETS=(
  $(sort -u -V <<< "${SUPPORTED_DIST_TARGETS[*]}") ); unset IFS
for target in ${SUPPORTED_DIST_TARGETS[@]}; do
  case "$target" in wasm*) continue ;; esac # wasm targets not yet supported
  _gen_clang_wrapper $target
done

for target in "${EXTRA_DIST_TARGETS[@]}"; do
  case "$target" in wasm*) continue ;; esac # wasm targets not yet supported
  IFS=- read -r arch sys <<< "$target"
  IFS=. read -r sys sysver <<< "$sys"
  _symlink "$DESTDIR/bin/clang-$arch-$sys" "clang-$target"
  _symlink "$DESTDIR/bin/clang++-$arch-$sys" "clang++-$target"
done
