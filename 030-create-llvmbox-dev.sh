#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"


_create_prelinked_obj_macos() { # <outfile> <srclib> ...
  # Creates a prelinked archive in a way that doesn't require linker support.
  # Note: LLVM 15's lld does not yet support -r, so we use apple ld.
  # Note: Apple ld can not read lto .bc inputs; must feed it code objects, so we
  # compile any bitcode files before passing them to ld.
  local outfile="$1" ; shift
  local ofiles=()
  local tmpfiles=()
  local tmpdir=$BUILD_DIR/prelink-tmp${outfile//\//.}
  local ofile
  local has_bc_compile=

  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"
  pushd "$tmpdir" >/dev/null

  for f in "$@"; do
    [ -n "$f" ] || continue
    case "$f" in
      *.o)
        ofiles+=( "$f" )
        ;;
      *.bc)
        ofile="$tmpdir/${f//\//.}.o"
        ofiles+=( "$ofile" )
        _bc_compile "$ofile" "$f" &
        has_bc_compile=1
        ;;
      *) _err "unexpected filename extension $(_relpath "$f")" ;;
    esac
  done
  [ -n "$has_bc_compile" ] && echo "compiling bc to mc"
  wait

  echo "prelinking $(_relpath "$outfile")"
  mkdir -p "$(dirname "$outfile")"
  /usr/bin/ld \
    -r \
    -o "$outfile" \
    -cache_path_lto "$STAGE2_LTO_CACHE" \
    -arch ${TARGET_ARCH/aarch64/arm64} \
    -keep_private_externs \
    -merge_zero_fill_sections \
    -no_eh_labels \
    -platform_version macos $TARGET_SYS_MINVERSION $TARGET_SYS_VERSION \
    "${ofiles[@]}"

  popd >/dev/null
  rm -rf "$tmpdir"
}


_create_prelinked_obj_linux() { # <outfile> <input> ...
  local outfile="$1" ; shift
  local inputs=()
  for f in "$@"; do
    [ -n "$f" ] || continue
    inputs+=( "$f" )
  done
  echo "prelinking $(_relpath "$outfile")"
  mkdir -p "$(dirname "$outfile")"
  local target_emu
  # see https://github.com/llvm/llvm-project/blob/llvmorg-15.0.7/lld/ELF/Driver.cpp#L131
  case "$TARGET_ARCH" in
    x86_64|i386)   target_emu=elf_${TARGET_ARCH} ;;
    aarch64|arm64) target_emu=aarch64elf ;;
    riscv64)       target_emu=elf64lriscv ;;
    riscv32)       target_emu=elf32lriscv ;;
    arm*)          target_emu=armelf ;;
    *)             _err "don't know -m value for $TARGET_ARCH"
  esac
  [ $TARGET_SYS = freebsd ] && target_emu=${target_emu}_fbsd
  "$LLVM_STAGE1"/bin/ld.lld \
    -r -o "$outfile" \
    --lto-O3 \
    --threads=$NCPU \
    --no-call-graph-profile-sort \
    --no-lto-legacy-pass-manager \
    --as-needed \
    --thinlto-cache-dir="$STAGE2_LTO_CACHE" \
    -m $target_emu \
    -z noexecstack \
    -z relro \
    -z now \
    -z defs \
    -z notext \
    \
    "${inputs[@]}"
}


_create_prelinked_obj() { # <outfile> <infile> ...
  case "$TARGET_SYS" in
    linux) _create_prelinked_obj_linux "$@" ;;
    macos) _create_prelinked_obj_macos "$@" ;;
    *)     _err "prelinking not implemented for $TARGET_SYS"
  esac
}


_extract_objects() { # <outdir> <srclib> ...
  # extract objects from archives
  local outdir="$1" ; shift
  local name
  echo "extracting objects from $# archives -> $(_relpath "$outdir")"
  rm -rf "$outdir"
  mkdir -p "$outdir"
  for f in "$@"; do
    name=$(basename "$f" .a)
    #echo "ar x $(_relpath "$f")"
    ( mkdir "$outdir/$name"
      cd "$outdir/$name"
      "$STAGE2_AR" x "$f"
      for f in $(find . -type f -name '*.o'); do
        # rename LLVM bitcode files to .bc to make file selection easier
        if [ "$(head -c4 "$f")" = "$(printf "\xde\xc0\x17\x0b")" ]; then
          mv "$f" "$(dirname "$f")/$(basename "$f" .o).bc"
        fi
      done
    ) &
  done
  wait
}


_find_objects() { # <dir> <bash-var-prefix>
  local dir=$1
  local varprefix=$2
  echo "finding objects in $(_relpath "$dir")"
  pushd "$dir" > /dev/null
  for f in $(find . -type f -name '*.o'); do
    f=${f:2} # ./libz.a => libz.a
    # if [[ "$(file "$f")" == *": LLVM"* ]]; then
    if [ "$(head -c4 "$f")" = "$(printf "\xde\xc0\x17\x0b")" ]; then
      eval "${varprefix}_bcfiles+=( '$dir/$f' )"
    else
      eval "${varprefix}_ofiles+=( '$dir/$f' )"
    fi
  done
  popd >/dev/null
}


_optimize_mc_archive() { # <afile>
  [ "$TARGET_SYS" = linux ] || return 0
  local origsize=$(_human_filesize "$1")
  echo "optimize $(_relpath "$1")"
  "$LLVM_STAGE1/bin/llvm-objcopy" \
    --strip-unneeded \
    --compress-debug-sections=zlib \
    "$1"
  echo "archive optimized: $origsize -> $(_human_filesize "$1")"
}


_create_archive() { # <outfile> [-thin] <infile> ...
  local outfile="$1" ; shift
  local opt_thin=false
  local name
  if [ "$1" = "-thin" ]; then
    shift
    opt_thin=true
  fi

  [ $# -gt 0 ] || _err "_create_archive: no inputs"
  echo "archiving $(_relpath "$outfile")"

  # must do this in a temp dir since pathnames are included in archive index
  local tmpdir="$BUILD_DIR/ar-tmp${outfile//\//.}"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"
  pushd "$tmpdir" >/dev/null

  if $opt_thin; then
    echo "CREATETHIN out.a" > script.mri
  else
    echo "CREATE out.a" > script.mri
  fi

  for f in "$@"; do
    [ -n "$f" ] || continue
    [[ "$f" != "$tmpdir/"* ]] || continue
    if [[ "$f" == *".a" ]]; then
      name="$(basename "$f")"
      [ ! -f "$name" ] || _err "duplicate $name"
      cp -a "$f" "$name"
      echo "ADDLIB $name" >> script.mri
    else
      name="$(basename "$(dirname "$f")")/$(basename "$f")"
      mkdir -p "$(dirname "$name")"
      [ ! -f "$name" ] || _err "duplicate $name"
      cp -a "$f" "$name"
      echo "ADDMOD $name" >> script.mri
    fi
  done

  echo "SAVE" >> script.mri
  echo "END" >> script.mri
  "$STAGE2_AR" -M < script.mri
  "$STAGE2_RANLIB" out.a

  mkdir -p "$(dirname "$outfile")"
  mv out.a "$outfile"

  popd >/dev/null
  rm -rf "$tmpdir"
}


_bc_link() { # <outfile.bc> <infile.bc> ...
  local outfile="$1" ; shift
  echo "linking $(_relpath "$outfile")"
  mkdir -p "$(dirname "$outfile")"
  "$STAGE2_LLVM_LINK" -o "$outfile" "$@"
}


_bc_opt() { # <infile.bc> [<outfile.bc>]
  local infile="$1"
  local outfile="${2:-}"
  if [ -z "${2:-}" ]; then
    echo "optimizing $(_relpath "$infile")"
    outfile=$BUILD_DIR/${infile//\//.}.bc-opt-tmp.bc
  else
    echo "optimizing $(_relpath "$infile") -> $(_relpath "$outfile")"
  fi
  mkdir -p "$(dirname "$outfile")"
  "$STAGE2_OPT" -passes='default<Os>' --code-model=small --thread-model=posix \
    -o "$outfile" "$infile"
  [ -n "${2:-}" ] || mv -f "$outfile" "$infile"
}


_bc_compile() { # <outfile.o> <infile.bc>
  local llc_args=(
    -o "$1" \
    --filetype=obj \
    --code-model=small \
    --frame-pointer=none \
    --thread-model=posix \
  )
  # --relocation-model=pic
  [ "$TARGET_SYS" = linux ] && llc_args+=( --mtriple=$TARGET_ARCH-linux-musl )
  # echo "compiling $(_relpath "$1")"
  "$STAGE2_LLC" "${llc_args[@]}" "$2"
}


trap 'rm -rf "$BUILD_DIR"/*-$$.tmp' EXIT

DESTDIR="${DESTDIR:-$LLVMBOX_DEV_DESTDIR}"
PRELINK_DIR="$BUILD_DIR/prelink-$$.tmp"

_process_lib() { # <libfile>
  local infile="$1"
  local name=$(basename "$infile")

  if ! $LLVMBOX_ENABLE_LTO; then
    # copy MC library
    echo "install $(_relpath "$DESTDIR/lib/$name")"
    install -m 0644 "$infile" "$DESTDIR/lib/$name"
    return 0
  fi

  # copy LTO library
  echo "install $(_relpath "$DESTDIR/lib-lto/$name")"
  install -m 0644 "$infile" "$DESTDIR/lib-lto/$name"

  # extract .o and .bc objects from $infile archive
  local bcfiles=() # LLVM bitcode files
  local ofiles=()  # precompiled target code object files
  local extractdir=$BUILD_DIR/ar_x-$name
  _extract_objects "$extractdir" "$infile"
  pushd "$extractdir" > /dev/null
  # :2 for "./libz.a" => "libz.a"
  for f in $(find . -type f -name '*.o'); do ofiles+=( "$extractdir/${f:2}" ); done
  for f in $(find . -type f -name '*.bc'); do bcfiles+=( "$extractdir/${f:2}" ); done
  popd >/dev/null

  # # merge all bc files into one (doesn't save time nor space)
  # if [ "${#bcfiles[@]}" -gt 0 ]; then
  #   _bc_link "$extractdir/$name.bc" "${bcfiles[@]}"
  #   bcfiles=( "$extractdir/$name.bc" )
  # fi

  _create_prelinked_obj "$PRELINK_DIR/$name.o" "${ofiles[@]:-}" "${bcfiles[@]:-}"
  _create_archive "$DESTDIR/lib/$name" "$PRELINK_DIR/$name.o"
  _optimize_mc_archive "$DESTDIR/lib/$name"
  rm -rf "$extractdir"
}

# create directories
rm -rf "$DESTDIR" "$PRELINK_DIR"
mkdir -p "$DESTDIR"/{bin,lib,include} "$PRELINK_DIR"
$LLVMBOX_ENABLE_LTO && mkdir -p "$DESTDIR/lib-lto"

# install llvm-config
install -m0755 "$LLVM_STAGE2/bin/llvm-config" "$DESTDIR/bin/llvm-config"

# copy headers
for src in \
  "$LLVM_STAGE2" \
  "$ZLIB_STAGE2" \
  "$ZSTD_STAGE2" \
  "$LIBXML2_STAGE2" \
;do
  _copyinto "$src/include/" "$DESTDIR/include/"
done

# compile LTO libs to MC libs (also copy LTO libs)
for lib in \
  "$LLVM_STAGE2"/lib/lib*.a \
  "$ZLIB_STAGE2"/lib/lib*.a \
  "$ZSTD_STAGE2"/lib/lib*.a \
  "$LIBXML2_STAGE2"/lib/lib*.a \
;do
  _process_lib "$lib" &
done
wait

# create one unified lib out of all libs, for derivative clang & lld (e.g. "myclang")
if $LLVMBOX_ENABLE_LTO; then
  _create_prelinked_obj "$PRELINK_DIR/liball_llvm_clang_lld.o" "$PRELINK_DIR"/*.o
  _create_archive       "$DESTDIR/lib/liball_llvm_clang_lld.a" \
                        "$PRELINK_DIR/liball_llvm_clang_lld.o"
  _optimize_mc_archive  "$DESTDIR/lib/liball_llvm_clang_lld.a"
else
  echo "WARNING! liball_llvm_clang_lld.a not implemented for LLVMBOX_ENABLE_LTO=0" >&2
fi

# create symlink for development
if [ "$(dirname "$DESTDIR")" = "$OUT_DIR" ]; then
  _symlink "$OUT_DIR/llvmbox-dev" "$(basename "$DESTDIR")"
fi

# create .tar.xz archive out of the result
if [ "${1:-}" != "--no-tar" ]; then
  echo "creating $(_relpath "$DESTDIR.tar.xz")"
  _create_tar_xz_from_dir "$DESTDIR" "$DESTDIR.tar.xz"
fi
