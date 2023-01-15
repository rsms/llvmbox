# ————————————————————————————————————————————————————————————————————————————————————
# build llvm host compiler (stage2)
#
# this works on ubuntu, but not mac

LLVM_STAGE2=$BUILD_DIR/llvm-stage2
LLVM_STAGE2_BUILD=$LLVM_STAGE2/build

if [ ! -x "$LLVM_STAGE2/bin/clang" ] ||
   [ "$PROJECT/stage1.cmake" -nt "$LLVM_STAGE2/bin/clang" ] ||
   [ "$PROJECT/stage2.cmake" -nt "$LLVM_STAGE2/bin/clang" ]
then
  if [ "$PROJECT/stage1.cmake" -nt "$LLVM_STAGE2/bin/clang" ] ||
     [ "$PROJECT/stage2.cmake" -nt "$LLVM_STAGE2/bin/clang" ]
  then
    rm -rf "$LLVM_STAGE2_BUILD"
  fi
  mkdir -p "$LLVM_STAGE2_BUILD"
  _pushd "$LLVM_STAGE2_BUILD"

  STAGE1_CMAKE_C_FLAGS="-w"
  # note: -w silences warnings (nothing we can do about those)
  # -fcompare-debug-second silences "note: ..." in GCC.
  case "$(${CC:-cc} --version || true)" in
    *'Free Software Foundation'*) # GCC
      STAGE1_CMAKE_C_FLAGS="$STAGE1_CMAKE_C_FLAGS -fcompare-debug-second"
      STAGE1_CMAKE_C_FLAGS="$STAGE1_CMAKE_C_FLAGS -Wno-misleading-indentation"
      ;;
  esac

  echo "cmake ... ($PWD/cmake-config.log)"
  cmake -G Ninja "$LLVM_SRC/llvm" \
    -C "$PROJECT/stage1.cmake" \
    -DCMAKE_C_FLAGS="$STAGE1_CMAKE_C_FLAGS" \
    -DCMAKE_CXX_FLAGS="$STAGE1_CMAKE_C_FLAGS" \
    -DCMAKE_INSTALL_PREFIX="$LLVM_STAGE2" \
    -DCMAKE_PREFIX_PATH="$LLVM_STAGE2" \
    > cmake-config.log ||
    _err "cmake failed. See $PWD/cmake-config.log"

  echo ninja stage2-distribution
  ninja stage2-distribution

  echo ninja stage2-install-distribution
  ninja stage2-install-distribution

  cp -a "$LLVM_STAGE2_BUILD"/bin/llvm-{ar,ranlib,tblgen} "$LLVM_STAGE2"/bin
  cp -a "$LLVM_STAGE2_BUILD"/bin/clang-tblgen            "$LLVM_STAGE2"/bin

  cp -a "$LLVM_STAGE2_BUILD"/bin/lld   "$LLVM_STAGE2"/bin
  ln -fs "$LLVM_STAGE2_BUILD"/bin/lld  "$LLVM_STAGE2"/bin/ld64.lld
  ln -fs "$LLVM_STAGE2_BUILD"/bin/lld  "$LLVM_STAGE2"/bin/ld.lld

  touch "$LLVM_STAGE2/bin/clang"

  _popd
fi
