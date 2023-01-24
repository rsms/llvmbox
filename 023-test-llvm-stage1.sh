#!/bin/bash
set -eo pipefail
source "$(dirname "$0")/config.sh"

# see https://libcxx.llvm.org/UsingLibcxx.html

CC="$LLVM_STAGE1/bin/clang"
CXX="$LLVM_STAGE1/bin/clang++"
CFLAGS=( -ferror-limit=1 )
LDFLAGS=()
CXXFLAGS=( -nostdinc++ -I"$LLVM_STAGE1/include/c++/v1" )
CXX_LDFLAGS=( -nostdlib++ -L"$LLVM_STAGE1/lib" -lc++ -lc++abi )

# flags for using LLVMBOX_SYSROOT instead of host system
CFLAGS_SYSROOT=( "${STAGE2_CFLAGS[@]}" )
LDFLAGS_SYSROOT=( "${STAGE2_LDFLAGS[@]}" )

# flags for linking c++ along with libs from LLVM_STAGE1 (uses host libc++)
CXX_STAGE1_LDFLAGS=()

case "$HOST_SYS" in
Darwin)
  CFLAGS+=(
    -Wno-nullability-completeness \
    -DTARGET_OS_EMBEDDED=0 \
    -DTARGET_OS_IPHONE=0 \
  )
  CFLAGS_SYSROOT+=(
    -Wno-nullability-completeness \
    -DTARGET_OS_EMBEDDED=0 \
    -DTARGET_OS_IPHONE=0 \
  )
  CXX_STAGE1_LDFLAGS+=( -lc++ -lc++abi )
  ;;
Linux)
  CXX_TARGET_I=$(echo "$LLVM_STAGE1/include/$TARGET_ARCH-"*)/c++/v1
  CXX_TARGET_L=$(echo "$LLVM_STAGE1/lib/$TARGET_ARCH-"*)
  [ -d "$CXX_TARGET_I" ] && CXXFLAGS+=( -I"$CXX_TARGET_I" )
  [ -d "$CXX_TARGET_L" ] && CXX_LDFLAGS+=( -L"$CXX_TARGET_L" )
  LIBCXX_I=$(echo | gcc -E -xc++ -Wp,-v - 2>&1 |
             grep '^ /' | head -n1 | awk '{print $1}' || true)
  [ -d "$LIBCXX_I" ] &&
    CXX_STAGE1_LDFLAGS+=( -isystem "$LIBCXX_I" )
  LIBSTDCXX=$("$STAGE1_CC" --print-file-name=libstdc++.a || true)
  if [ -e "$LIBSTDCXX" ]; then
    CXX_STAGE1_LDFLAGS+=(
      -stdlib=libstdc++ \
      -static-libstdc++ \
      -L"$(dirname "$LIBSTDCXX")" \
    )
  else
    LIBCXX=$("$STAGE1_CC" --print-file-name=libc++.a || true)
    [ -e "$LIBCXX" ] &&
      CXX_STAGE1_LDFLAGS+=( -stdlib=libc++ -L"$(dirname "$LIBCXX")" )
  fi
  ;;
esac

_cc() {
  echo "$(_relpath "$CC")" "${CFLAGS[@]}" "${LDFLAGS[@]}" "$@"
       "$CC" "${CFLAGS[@]}" "${LDFLAGS[@]}" "$@"
}

_cxx() {
  echo "$(_relpath "$CXX")" \
              "${CFLAGS[@]}" "${CXXFLAGS[@]}" "${LDFLAGS[@]}" "${CXX_LDFLAGS[@]}" "$@"
       "$CXX" "${CFLAGS[@]}" "${CXXFLAGS[@]}" "${LDFLAGS[@]}" "${CXX_LDFLAGS[@]}" "$@"
}

_ldxx_stage1() {
  echo "$(_relpath "$CXX")" \
              "${LDFLAGS[@]}" "${CXX_STAGE1_LDFLAGS[@]}" "$@"
       "$CXX" "${LDFLAGS[@]}" "${CXX_STAGE1_LDFLAGS[@]}" "$@"
}

_cc_sysroot() {
  echo "$(_relpath "$CC")" "${CFLAGS_SYSROOT[@]}" "${LDFLAGS_SYSROOT[@]}" "$@"
       "$CC" "${CFLAGS_SYSROOT[@]}" "${LDFLAGS_SYSROOT[@]}" "$@"
}

_cxx_sysroot() {
  echo "$(_relpath "$CXX")" \
              "${CFLAGS_SYSROOT[@]}" "${CXXFLAGS[@]}" \
              "${LDFLAGS_SYSROOT[@]}" "${CXX_LDFLAGS[@]}" "$@"
       "$CXX" "${CFLAGS_SYSROOT[@]}" "${CXXFLAGS[@]}" \
              "${LDFLAGS_SYSROOT[@]}" "${CXX_LDFLAGS[@]}" "$@"
}

_print_linking() { # <file>
  local OUT
  local objdump="$LLVM_STAGE1/bin/llvm-objdump"
  [ -f "$objdump" ] || objdump=llvm-objdump
  local PAT='NEEDED|RUNPATH|RPATH'
  case "$HOST_SYS" in
    Darwin) PAT='RUNPATH|RPATH|\.dylib' ;;
  esac
  OUT=$( "$objdump" -p "$1" | grep -E "$PAT" | awk '{printf $1 " " $2 "\n"}' || true )
  if [ -n "$OUT" ]; then
    echo "$(_relpath "$1") is dynamically linked:"
    echo "$OUT"
  else
    echo "$(_relpath "$1") is statically linked."
  fi
}

_pushd "$PROJECT"

echo "————————————————————————————————————————————————————————————"
echo "cc shared default libc"; out=$BUILD_DIR/_hello_c
_cc test/hello.c -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
echo "c++ shared default libc"; out=$BUILD_DIR/_hello_cc
_cxx -std=c++17 test/hello.cc -o "$out"
_print_linking "$out" ; "$out"

echo "————————————————————————————————————————————————————————————"
echo "c++ shared default libc, atomics"; out=$BUILD_DIR/_cxx-atomic_cc
_cxx -std=c++17 test/cxx-atomic.cc -o "$out"
"$out" || true ; _print_linking "$out"

# macos: building against LLVMBOX_SYSROOT works with C, but not C++
if [ "$HOST_SYS" = Darwin ]; then
  echo "————————————————————————————————————————————————————————————"
  echo "cc shared sysroot libc"; out=$BUILD_DIR/_hello_c_sysroot
  _cc_sysroot test/hello.c -o "$out"
  _print_linking "$out" ; "$out"

  echo "————————————————————————————————————————————————————————————"
  echo "cc shared sysroot libc, explicit libSystem"; out=$BUILD_DIR/_hello_c_sysroot2
  _cc_sysroot -lSystem test/hello.c -o "$out"
  _print_linking "$out" ; "$out"
fi

# linux: building against LLVMBOX_SYSROOT
if [ "$HOST_SYS" = Linux ]; then
  # Linux stage1 build is currently unable to statically link using glibc.
  # If we try the below C build, we get the following errors:
  #   $LLVM_STAGE1/bin/clang -static test/hello.c -o $BUILD_DIR/_hello_c
  #   ld.lld: error: undefined symbol: __unordtf2
  #   >>> referenced by printf_fphex.o:(__printf_fphex)
  #     in archive /lib/x86_64-linux-gnu/libc.a
  #   ...
  #
  # echo "————————————————————————————————————————————————————————————"
  # echo "cc static libc"; out=$BUILD_DIR/_hello_c_static
  # _cc -static test/hello.c -o "$out"
  # _print_linking "$out" ; "$out"
  #
  # echo "————————————————————————————————————————————————————————————"
  # echo "c++ static libc"; out=$BUILD_DIR/_hello_cc_static
  # _cxx -static -std=c++17 test/hello.cc -o "$out"
  # _print_linking "$out" ; "$out"

  # however, it works with musl (must have run 022-musl-libc.sh)
  if [ -f "$LLVMBOX_SYSROOT/lib/libc.a" ]; then
    echo "————————————————————————————————————————————————————————————"
    echo "cc shared musl libc"; out=$BUILD_DIR/_hello_c_musl
    _cc_sysroot test/hello.c -o "$out"
    _print_linking "$out" ; "$out"

    echo "————————————————————————————————————————————————————————————"
    echo "cc static musl libc"; out=$BUILD_DIR/_hello_c_musl_static
    _cc_sysroot -static test/hello.c -o "$out"
    _print_linking "$out" ; "$out"

    # We can NOT link c++ programs with musl; stage1 libc++ is built with
    # host libc which is likely glibc.
    #
    # echo "————————————————————————————————————————————————————————————"
    # echo "c++ shared musl-libc"; out=$BUILD_DIR/_hello_cc_musl
    # _cxx_sysroot test/hello.cc -o "$out"
    # _print_linking "$out" ; "$out"
    #
    # echo "————————————————————————————————————————————————————————————"
    # echo "c++ static musl-libc"; out=$BUILD_DIR/_hello_cc_musl_static
    # _cxx_sysroot -static test/hello.cc -o "$out"
    # _print_linking "$out" ; "$out"
  fi
fi

# llvm libs
echo "————————————————————————————————————————————————————————————"
echo "llvm API example (stage1 libs: libc, llvm-c, z)"; out=$BUILD_DIR/_hello_llvm_c
_cc $("$LLVM_STAGE1/bin/llvm-config" --cflags) -c test/hello-llvm.c -o "$out.o"
_ldxx_stage1 \
  $("$LLVM_STAGE1/bin/llvm-config" --cxxflags --ldflags --libs core native) \
  -I"$ZLIB_STAGE1/include" "$ZLIB_STAGE1/lib/libz.a" \
  "$out.o" -o "$out"
_print_linking "$out" ; "$out"
