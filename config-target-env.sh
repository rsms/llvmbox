# TODO: consider using --sysroot
#   --sysroot effectively changes the logical root for headers and libraries
#
# see https://libcxx.llvm.org/UsingLibcxx.html#alternate-libcxx

TARGET_CC=$HOST_CC
TARGET_CXX=$HOST_CXX
TARGET_ASM=$HOST_ASM
TARGET_LD=$HOST_LD
TARGET_RC=$HOST_RC
TARGET_AR=$HOST_AR
TARGET_RANLIB=$HOST_RANLIB

# case "$TARGET_SYS" in
#   linux) TARGET_LLD=$LLVM_HOST/bin/ld.lld ;;
#   macos) TARGET_LLD=$LLVM_HOST/bin/ld64.lld ;;
# esac

TARGET_CFLAGS=(
  --target="$TARGET" \
)
TARGET_LDFLAGS=(
  -fuse-ld=lld \
  -L"$LLVM_HOST"/lib \
)

TARGET_CXXFLAGS=(
  -nostdinc++ \
  -isystem "$LLVM_HOST/include/c++/v1" \
  -I"$LLVM_HOST/include/c++/v1" \
)
TARGET_CXX_LDFLAGS=(
  -nostdlib++ \
  -lc++ \
)

# note: for dylib linking to work, set '-Wl,-rpath,"$LLVM_HOST/lib"' in LDFLAGS

# on linux, a c++ __config_site header is placed in a subdirectory
# "include/HOST_TRIPLE/c++/v1/__config_site"
# e.g. include/x86_64-unknown-linux-gnu/c++/v1/__config_site
[ "$HOST_SYS" = "Linux" ] &&
[ -d "$(echo "$LLVM_HOST/include/$HOST_ARCH-"*)" ] &&
  TARGET_CXXFLAGS+=( -I"$(echo "$LLVM_HOST/include/$HOST_ARCH-"*)/c++/v1" )
# same goes for lib
[ "$HOST_SYS" = "Linux" ] &&
[ -d "$(echo "$LLVM_HOST/lib/$HOST_ARCH-"*)" ] &&
  TARGET_LDFLAGS+=( -L"$(echo "$LLVM_HOST/lib/$HOST_ARCH-"*)" )


case "$TARGET_SYS" in
  linux)
    TARGET_LDFLAGS=( -static "${TARGET_LDFLAGS[@]}" )
    ;;
  apple|darwin|macos|ios)
    [ -d /Library/Developer/CommandLineTools/SDKs ] ||
      _err "missing /Library/Developer/CommandLineTools/SDKs; try running: xcode-select --install"
    MACOS_SDK=$(
      /bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk |
      sort -V | head -n1)
    [ -d "$MACOS_SDK" ] ||
      _err "macos sdk not found at $MACOS_SDK; try running: xcode-select --install"
    TARGET_CFLAGS+=(
      -isystem "$MACOS_SDK/usr/include" \
      -Wno-nullability-completeness \
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
      -mmacosx-version-min=10.10 \
    )
    TARGET_LDFLAGS+=( \
      -mmacosx-version-min=10.10 \
    )
    ;;
esac

# note: -nostdinc++ must come first, TARGET_CFLAGS must be appended to TARGET_CXXFLAGS
TARGET_CXXFLAGS+=( "${TARGET_CFLAGS[@]}" )
TARGET_CXX_LDFLAGS+=( "${TARGET_LDFLAGS[@]}" )


TARGET_CMAKE_SYSTEM_NAME=$TARGET_SYS  # e.g. linux, macos
case $TARGET_CMAKE_SYSTEM_NAME in
  apple|macos|darwin) TARGET_CMAKE_SYSTEM_NAME="Darwin";;
  freebsd)            TARGET_CMAKE_SYSTEM_NAME="FreeBSD";;
  windows)            TARGET_CMAKE_SYSTEM_NAME="Windows";;
  linux)              TARGET_CMAKE_SYSTEM_NAME="Linux";;
  native)             TARGET_CMAKE_SYSTEM_NAME="";;
esac
