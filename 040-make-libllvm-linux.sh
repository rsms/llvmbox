#!/bin/bash
#
# build a prelinked relocatable object as a static library (.a archive)
#
set -euo pipefail
source "$(dirname "$0")/config.sh"

[ "$TARGET_SYS" = linux ] || { echo "$0: skipping (not targeting linux)"; exit; }

OUT_LIBLLVM=$LLVMBOX_DESTDIR/lib/libllvm.a
PRELINK_FILE=$BUILD_DIR/libllvm.o
OBJDIR=$BUILD_DIR/libllvm-obj

# extract objects from archives
rm -rf "$OBJDIR"
mkdir -p "$OBJDIR"
_pushd "$OBJDIR"
for f in "$LLVMBOX_DESTDIR"/lib/*.a; do
  name=$(basename "$f" .a)
  [ "$name" != libllvm ] || continue
  mkdir "$name"
  echo "ar x $(_relpath "$f")"
  (cd "$name" && "$LLVMBOX_DESTDIR"/bin/llvm-ar x "$f") &
done
wait

OBJFILES=( $(echo */*.o) )
# echo "${OBJFILES[@]}" > "$OBJDIR/index.txt"

echo "link objects into $PRELINK_FILE (LTO)"
"$LLVMBOX_DESTDIR"/bin/ld.lld -r -o "$PRELINK_FILE" \
  --lto-O3 \
  --no-call-graph-profile-sort \
  --as-needed \
  --thinlto-cache-dir="$STAGE2_LTO_CACHE" \
  --discard-locals \
  -m elf_${TARGET_ARCH} \
  -z noexecstack \
  -z relro \
  -z now \
  -z defs \
  -z notext \
  \
  "${OBJFILES[@]}"

echo "ar crs $(_relpath "$OUT_LIBLLVM") $(_relpath "$PRELINK_FILE")"
rm -f "$OUT_LIBLLVM"
"$LLVMBOX_DESTDIR"/bin/llvm-ar crs "$OUT_LIBLLVM" "$PRELINK_FILE"
rm "$PRELINK_FILE"

echo "optimize $OUT_LIBLLVM"
"$LLVMBOX_DESTDIR"/bin/llvm-objcopy \
  --localize-hidden \
  --strip-unneeded \
  --compress-debug-sections=zlib \
  "$OUT_LIBLLVM"

echo "$OUT_LIBLLVM: $(_human_filesize "$OUT_LIBLLVM")"
