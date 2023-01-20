#!/bin/bash
set -e
PWD0=${PWD0:-$PWD}
SELF_SCRIPT=$(realpath "$0")
cd "$(dirname "$0")"
PROJECT=$(realpath "$PWD/..")

if [ -z "$LLVM_ROOT" ]; then
  echo "LLVM_ROOT not set in env (e.g. LLVM_ROOT=/path/to/llvm so that \$LLVM_ROOT/bin/clang is found)" >&2
  exit 1
fi

LLVM_COMPONENTS=(
  engine \
  option \
  passes \
  all-targets \
  libdriver \
  lto \
  linker \
  debuginfopdb \
  debuginfodwarf \
  windowsmanifest \
  orcjit \
  mcjit \
  coverage \
)

SOURCES=( $(echo *.{c,cc}) )
OBJECTS=()
for f in "${SOURCES[@]}"; do OBJECTS+=( $f.o ); done

CFLAGS=(
  $("$PROJECT"/utils/config --cflags) \
)
CXXFLAGS=(
  $("$PROJECT"/utils/config --cxxflags) \
  $("$LLVM_ROOT"/bin/llvm-config --cxxflags) \
)
LDFLAGS=(
  $("$PROJECT"/utils/config --ldflags-cxx) \
  $("$LLVM_ROOT"/bin/llvm-config --ldflags) \
  $("$LLVM_ROOT"/bin/llvm-config --link-static --libfiles "${LLVM_COMPONENTS[@]}") \
  "$LLVM_ROOT"/lib/libclang*.a \
  "$LLVM_ROOT"/lib/liblld*.a \
)
# LDFLAGS+=( "$LLVM_ROOT"/lib/libz.a )
LDFLAGS+=( $HOME/tmp/stage2-zlib/lib/libz.a ) # FIXME TODO

for f in "${SOURCES[@]}"; do
  [ "$f" -nt "$f.o" -o "$SELF_SCRIPT" -nt "$f.o" ] || continue
  if [[ "$f" == *.cc ]]; then
    echo "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $f.o $f
         "$LLVM_ROOT"/bin/clang++ "${CXXFLAGS[@]}" -c -o $f.o $f
  else
    echo "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $f.o $f
         "$LLVM_ROOT"/bin/clang "${CFLAGS[@]}" -c -o $f.o $f
  fi
done

echo "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang/myclang
     "$LLVM_ROOT"/bin/clang++ "${LDFLAGS[@]}" "${OBJECTS[@]}" -o myclang/myclang
