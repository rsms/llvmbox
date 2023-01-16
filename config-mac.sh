# Host compiler location; prefer clang, fall back to $CC ("cc" in PATH as last resort)
# HOST_CC=${HOST_CC}
# HOST_CXX=${HOST_CXX}
# HOST_ASM=${HOST_ASM}
# HOST_AR=${HOST_AR}
# HOST_RANLIB=${HOST_RANLIB}
HOST_CC=
HOST_CXX=
HOST_ASM=
HOST_AR=
HOST_RANLIB=

if [ -z "$HOST_CC" ]; then
  f="$(command -v clang || true)"
  if [ -n "$f" ]; then
    HOST_CC=$f
    HOST_CXX=$(command -v clang++)
  elif command -v gcc >/dev/null && command -v g++ >/dev/null; then
    HOST_CC=$(command -v gcc)
    HOST_CXX=$(command -v g++)
  else
    HOST_CC=$(command -v "${CC:-cc}" || true)
    HOST_CXX=$(command -v "${CXX:-c++}" || true)
    [ -x "$HOST_CC" -a -x "$HOST_CXX" ] ||
      _err "no host compiler found. Set HOST_CC or add clang or cc to PATH"
  fi
fi
[ -z "$HOST_ASM" ] && HOST_ASM=$HOST_CC
[ -x "$HOST_CC" ] || _err "${HOST_CC} is not an executable file"


if [[ "$HOST_CC" == */clang ]]; then
  HOST_LLVM_BINDIR=${HOST_CC:0:$(( ${#HOST_CC} - 6 ))}

  if ! [ -x $HOST_LLVM_BINDIR/llvm-ar -a -x $HOST_LLVM_BINDIR/llvm-ranlib ]; then
    # echo "host clang installation at $HOST_LLVM_BINDIR is lacking llvm-ar and/or llvm-ranlib"
    # echo "trying to find another installation..."
    SEARCH_PATHS=(
      /usr/local/opt/llvm/bin \
      /opt/homebrew/opt/llvm/bin \
    )
    for d in ${SEARCH_PATHS[@]}; do
      [ -d "$d" ] || continue
      # echo "  trying $d"
      if [ -x "$d"/clang -a \
           -x "$d"/clang++ -a \
           -x "$d"/llvm-ranlib -a \
           -x "$d"/llvm-ar ]
      then
        HOST_CC=$d/clang
        HOST_CXX=$d/clang++
        HOST_LLVM_BINDIR=$d
        break
      fi
    done
    if ! [ -x $HOST_LLVM_BINDIR/llvm-ar ]; then
      echo "no better clang found"
      echo "note: set HOST_CC to absolute path to fully-featured clang"
    fi
  fi
  if [ -x $HOST_LLVM_BINDIR/llvm-ranlib ]; then
    HOST_RANLIB=$HOST_LLVM_BINDIR/llvm-ranlib
  fi
  if [ -x $HOST_LLVM_BINDIR/llvm-ar ]; then
    HOST_AR=$HOST_LLVM_BINDIR/llvm-ar
  fi
fi

unset f


export CC=${HOST_CC}
export CXX=${HOST_CXX}
export ASM=${HOST_ASM}
export AR=${HOST_AR}
export RANLIB=${HOST_RANLIB}
