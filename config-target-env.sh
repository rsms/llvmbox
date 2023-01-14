# TODO: consider using --sysroot
#   --sysroot effectively changes the logical root for headers and libraries

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

TARGET_CFLAGS=( --target="$TARGET" )
TARGET_LDFLAGS=( -fuse-ld=lld -L"$LLVM_HOST"/lib )

TARGET_CXXFLAGS=( -nostdinc++ -I"$LLVM_HOST"/include/c++/v1 )
TARGET_CXX_LDFLAGS=( -nostdlib++ -lc++ -lc++abi )

[ -d "$LLVM_HOST/include/$TARGET/c++/v1" ] &&
  TARGET_CXXFLAGS+=( "-I$LLVM_HOST/include/$TARGET/c++/v1" )

[ -d "$LLVM_HOST/lib/$TARGET" ] &&
  TARGET_LDFLAGS+=( "-L$LLVM_HOST/lib/$TARGET" )

case "$TARGET_SYS" in
  linux)
    TARGET_LDFLAGS=( -static "${TARGET_LDFLAGS[@]}" )
    ;;
  macos)
    [ -d /Library/Developer/CommandLineTools/SDKs ] ||
      _err "missing /Library/Developer/CommandLineTools/SDKs; try running: xcode-select --install"
    MACOS_SDK=$(
      /bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk |
      sort -V | head -n1)
    [ -d "$MACOS_SDK" ] ||
      _err "macos sdk not found at $MACOS_SDK; try running: xcode-select --install"
    TARGET_CFLAGS+=(
      "-I$MACOS_SDK/usr/include" \
      -Wno-nullability-completeness \
      -DTARGET_OS_EMBEDDED=0 \
    )
    TARGET_LDFLAGS+=( -lSystem )
    ;;
esac

# note: -nostdinc++ must come first, TARGET_CFLAGS must be appended to TARGET_CXXFLAGS
TARGET_CXXFLAGS+=( "${TARGET_CFLAGS[@]}" )
TARGET_CXX_LDFLAGS+=( "${TARGET_LDFLAGS[@]}" )


TARGET_CMAKE_SYSTEM_NAME=$TARGET_SYS  # e.g. linux, macos
case $TARGET_CMAKE_SYSTEM_NAME in
  macos)   TARGET_CMAKE_SYSTEM_NAME="Darwin";;
  freebsd) TARGET_CMAKE_SYSTEM_NAME="FreeBSD";;
  windows) TARGET_CMAKE_SYSTEM_NAME="Windows";;
  linux)   TARGET_CMAKE_SYSTEM_NAME="Linux";;
  native)  TARGET_CMAKE_SYSTEM_NAME="";;
esac
