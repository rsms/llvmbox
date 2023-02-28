#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

DESTDIR="$SYSROOTS_DIR/compiler-rt"

# make sure we have llvm source
[ -d "$LLVM_SRC" ] || "$BASH" "$PROJECT/025-llvm-source-stage2.sh"

_pushd "$LLVM_SRC/compiler-rt/lib/builtins"

# ————————————————————————————————————————————————————————————————————————————————————
# find & copy sources

_deps() { for f in "$1"/*.{h,inc}; do [ ! -f "$f" ] || echo $f; done; }
#
# when upgrading compiler-rt to a new version, perform these manual steps:
# - open lib/builtins/CMakeLists.txt
# - update SOURCES arrays below with GENERIC_SOURCES + GENERIC_TF_SOURCES
#
GENERIC_SOURCES=( # cmake: GENERIC_SOURCES + GENERIC_TF_SOURCES
  $(_deps .) \
  absvdi2.c \
  absvsi2.c \
  absvti2.c \
  adddf3.c \
  addsf3.c \
  addvdi3.c \
  addvsi3.c \
  addvti3.c \
  apple_versioning.c \
  ashldi3.c \
  ashlti3.c \
  ashrdi3.c \
  ashrti3.c \
  bswapdi2.c \
  bswapsi2.c \
  clzdi2.c \
  clzsi2.c \
  clzti2.c \
  cmpdi2.c \
  cmpti2.c \
  comparedf2.c \
  comparesf2.c \
  ctzdi2.c \
  ctzsi2.c \
  ctzti2.c \
  divdc3.c \
  divdf3.c \
  divdi3.c \
  divmoddi4.c \
  divmodsi4.c \
  divmodti4.c \
  divsc3.c \
  divsf3.c \
  divsi3.c \
  divti3.c \
  extendsfdf2.c \
  extendhfsf2.c \
  ffsdi2.c \
  ffssi2.c \
  ffsti2.c \
  fixdfdi.c \
  fixdfsi.c \
  fixdfti.c \
  fixsfdi.c \
  fixsfsi.c \
  fixsfti.c \
  fixunsdfdi.c \
  fixunsdfsi.c \
  fixunsdfti.c \
  fixunssfdi.c \
  fixunssfsi.c \
  fixunssfti.c \
  floatdidf.c \
  floatdisf.c \
  floatsidf.c \
  floatsisf.c \
  floattidf.c \
  floattisf.c \
  floatundidf.c \
  floatundisf.c \
  floatunsidf.c \
  floatunsisf.c \
  floatuntidf.c \
  floatuntisf.c \
  fp_mode.c \
  int_util.c \
  lshrdi3.c \
  lshrti3.c \
  moddi3.c \
  modsi3.c \
  modti3.c \
  muldc3.c \
  muldf3.c \
  muldi3.c \
  mulodi4.c \
  mulosi4.c \
  muloti4.c \
  mulsc3.c \
  mulsf3.c \
  multi3.c \
  mulvdi3.c \
  mulvsi3.c \
  mulvti3.c \
  negdf2.c \
  negdi2.c \
  negsf2.c \
  negti2.c \
  negvdi2.c \
  negvsi2.c \
  negvti2.c \
  os_version_check.c \
  paritydi2.c \
  paritysi2.c \
  parityti2.c \
  popcountdi2.c \
  popcountsi2.c \
  popcountti2.c \
  powidf2.c \
  powisf2.c \
  subdf3.c \
  subsf3.c \
  subvdi3.c \
  subvsi3.c \
  subvti3.c \
  trampoline_setup.c \
  truncdfhf2.c \
  truncdfsf2.c \
  truncsfhf2.c \
  ucmpdi2.c \
  ucmpti2.c \
  udivdi3.c \
  udivmoddi4.c \
  udivmodsi4.c \
  udivmodti4.c \
  udivsi3.c \
  udivti3.c \
  umoddi3.c \
  umodsi3.c \
  umodti3.c \
  \
  addtf3.c \
  comparetf2.c \
  divtc3.c \
  divtf3.c \
  extenddftf2.c \
  extendhftf2.c \
  extendsftf2.c \
  fixtfdi.c \
  fixtfsi.c \
  fixtfti.c \
  fixunstfdi.c \
  fixunstfsi.c \
  fixunstfti.c \
  floatditf.c \
  floatsitf.c \
  floattitf.c \
  floatunditf.c \
  floatunsitf.c \
  floatuntitf.c \
  multc3.c \
  multf3.c \
  powitf2.c \
  subtf3.c \
  trunctfdf2.c \
  trunctfhf2.c \
  trunctfsf2.c \
)
GENERIC_SOURCES+=( # cmake: if (NOT FUCHSIA) GENERIC_SOURCES+=...
  clear_cache.c \
)
# TODO:
# - if target has __bf16: GENERIC_SOURCES+=( truncdfbf2.c truncsfbf2.c )
#   e.g. if_compiles($TARGET, "__bf16 f(__bf16 x) { return x; }")
# - if target has "_Atomic" keyword: GENERIC_SOURCES+=( atomic.c )
#   e.g. if_compiles($TARGET, "int f(int x, int y) { _Atomic int r = x * y; return r;}")
DARWIN_SOURCES=( # cmake: if (APPLE) GENERIC_SOURCES+=...
  atomic_flag_clear.c \
  atomic_flag_clear_explicit.c \
  atomic_flag_test_and_set.c \
  atomic_flag_test_and_set_explicit.c \
  atomic_signal_fence.c \
  atomic_thread_fence.c \
)
X86_ARCH_SOURCES=( # these files are used on 32-bit and 64-bit x86
  cpu_model.c \
  i386/fp_mode.c \
)
# X86_80_BIT_SOURCES is ignored
X86_64_SOURCES=(
  $(_deps x86_64) \
  x86_64/floatdidf.c \
  x86_64/floatdisf.c \
  x86_64/floatundidf.S \
  x86_64/floatundisf.S \
  \
)
X86_64_SOURCES+=( # cmake: if (NOT ANDROID)
  x86_64/floatdixf.c \
  x86_64/floatundixf.S \
)
# X86_64_SOURCES_WIN32=( # cmake: if (WIN32)
#   ${X86_64_SOURCES[@]} \
#   x86_64/chkstk.S \
#   x86_64/chkstk2.S \
# )
I386_SOURCES=(
  $(_deps i386) \
  i386/ashldi3.S \
  i386/ashrdi3.S \
  i386/divdi3.S \
  i386/floatdidf.S \
  i386/floatdisf.S \
  i386/floatundidf.S \
  i386/floatundisf.S \
  i386/lshrdi3.S \
  i386/moddi3.S \
  i386/muldi3.S \
  i386/udivdi3.S \
  i386/umoddi3.S \
)
I386_SOURCES+=( # cmake: if (NOT ANDROID)
  i386/floatdixf.S \
  i386/floatundixf.S \
)
# I386_SOURCES_WIN32=( # cmake: if (WIN32)
#   ${I386_SOURCES[@]} \
#   i386/chkstk.S \
#   i386/chkstk2.S \
# )
ARM_SOURCES=(
  $(_deps arm) \
  arm/fp_mode.c \
  arm/bswapdi2.S \
  arm/bswapsi2.S \
  arm/clzdi2.S \
  arm/clzsi2.S \
  arm/comparesf2.S \
  arm/divmodsi4.S \
  arm/divsi3.S \
  arm/modsi3.S \
  arm/sync_fetch_and_add_4.S \
  arm/sync_fetch_and_add_8.S \
  arm/sync_fetch_and_and_4.S \
  arm/sync_fetch_and_and_8.S \
  arm/sync_fetch_and_max_4.S \
  arm/sync_fetch_and_max_8.S \
  arm/sync_fetch_and_min_4.S \
  arm/sync_fetch_and_min_8.S \
  arm/sync_fetch_and_nand_4.S \
  arm/sync_fetch_and_nand_8.S \
  arm/sync_fetch_and_or_4.S \
  arm/sync_fetch_and_or_8.S \
  arm/sync_fetch_and_sub_4.S \
  arm/sync_fetch_and_sub_8.S \
  arm/sync_fetch_and_umax_4.S \
  arm/sync_fetch_and_umax_8.S \
  arm/sync_fetch_and_umin_4.S \
  arm/sync_fetch_and_umin_8.S \
  arm/sync_fetch_and_xor_4.S \
  arm/sync_fetch_and_xor_8.S \
  arm/udivmodsi4.S \
  arm/udivsi3.S \
  arm/umodsi3.S \
)
# thumb1_SOURCES is ignored (<armv7)
ARM_EABI_SOURCES=(
  arm/aeabi_cdcmp.S \
  arm/aeabi_cdcmpeq_check_nan.c \
  arm/aeabi_cfcmp.S \
  arm/aeabi_cfcmpeq_check_nan.c \
  arm/aeabi_dcmp.S \
  arm/aeabi_div0.c \
  arm/aeabi_drsub.c \
  arm/aeabi_fcmp.S \
  arm/aeabi_frsub.c \
  arm/aeabi_idivmod.S \
  arm/aeabi_ldivmod.S \
  arm/aeabi_memcmp.S \
  arm/aeabi_memcpy.S \
  arm/aeabi_memmove.S \
  arm/aeabi_memset.S \
  arm/aeabi_uidivmod.S \
  arm/aeabi_uldivmod.S \
)
# TODO: win32: ARM_MINGW_SOURCES
AARCH64_SOURCES=(
  $(_deps aarch64) \
  cpu_model.c \
  aarch64/fp_mode.c \
)
# TODO: mingw: AARCH64_MINGW_SOURCES=( aarch64/chkstk.S )

# cmake: foreach(pat cas swp ldadd ldclr ldeor ldset) ...
rm -f aarch64/outline_atomic_*.S
cp aarch64/lse.S aarch64/outline_atomic.S.inc
AARCH64_SOURCES+=( aarch64/outline_atomic.S.inc )
for pat in cas swp ldadd ldclr ldeor ldset; do
  for size in 1 2 4 8 16; do
    for model in 1 2 3 4; do
      if [ $pat = cas ] || [ $size != 16 ]; then
        srcfile=aarch64/outline_atomic_${pat}${size}_${model}.S
        echo "#define L_${pat}" >> $srcfile
        echo "#define SIZE ${size}" >> $srcfile
        echo "#define MODEL ${model}" >> $srcfile
        echo '#include "outline_atomic.S.inc"' >> $srcfile
        # OBJ_CFLAGS="-DL_${pat} -DSIZE=${size} -DMODEL=${model}"
        # AARCH64_OBJECTS+=( "aarch64/lse.S.o:$OBJ_CFLAGS" )
        AARCH64_SOURCES+=( $srcfile )
      fi
    done
  done
done

RISCV_SOURCES=(
  $(_deps riscv) \
  riscv/save.S \
  riscv/restore.S \
)
RISCV32_SOURCES=( riscv/mulsi3.S )
RISCV64_SOURCES=( riscv/muldi3.S )

# EXCLUDE_BUILTINS_VARS is a list of shell vars which in turn contains
# space-separated names of builtins to be excluded.
# The var names encodes the targets,
# e.g. "EXCLUDE_BUILTINS__macos" is for macos, any arch.
# e.g. "EXCLUDE_BUILTINS__macos__i386" is for macos, i386 only.
EXCLUDE_BUILTINS_VARS=()
#
# lib/builtins/Darwin-excludes/CMakeLists.txt
# cmake/Modules/CompilerRTDarwinUtils.cmake
#   macro(darwin_add_builtin_libraries)
#   function(darwin_find_excluded_builtins_list output_var)
# Note: The resulting names match source files without filename extension.
# For example, "addtf3" matches source file "addtf3.c".
EXCLUDE_APPLE_ARCHS_TO_CONSIDER=(i386 x86_64 arm64)
for d in Darwin-excludes; do
  for os in osx ios; do  # TODO: ios
    f=$d/$os.txt
    [ -f $f ] || continue
    var=EXCLUDE_BUILTINS__${os/osx/macos}
    declare $var=
    while read -r line; do
      declare $var="${!var} $line"
    done < $f
    [ -n "$var" ] && EXCLUDE_BUILTINS_VARS+=( $var )
    for arch in ${EXCLUDE_APPLE_ARCHS_TO_CONSIDER[@]}; do
      f=$(echo $d/${os}*-$arch.txt)
      [ -f $f ] || continue
      [[ "$f" != *"iossim"* ]] || continue
      var=EXCLUDE_BUILTINS__${os/osx/macos}__${arch/arm64/aarch64}
      declare $var=
      while read -r line; do
        declare $var="${!var} $line"
      done < $f
      [ -n "$var" ] && EXCLUDE_BUILTINS_VARS+=( $var )
    done
  done
done


rm -rf "$DESTDIR"/builtins
mkdir -p "$DESTDIR"/builtins

_cpd() {
  echo "copy $(($#-1)) files to $(_relpath "${@: -1}")/"
  mkdir -p "${@: -1}"
  cp -r "$@"
}

# aarch64: GENERIC_SOURCES + AARCH64_SOURCES
# arm:     GENERIC_SOURCES + ARM_SOURCES (+ ARM_EABI_SOURCES if not win32)
# i386:    GENERIC_SOURCES + X86_ARCH_SOURCES + I386_SOURCES
# x86_64:  GENERIC_SOURCES + X86_ARCH_SOURCES + X86_64_SOURCES
# riscv32: GENERIC_SOURCES + RISCV_SOURCES + RISCV32_SOURCES
# riscv64: GENERIC_SOURCES + RISCV_SOURCES + RISCV64_SOURCES
# wasm32:  GENERIC_SOURCES
# wasm64:  GENERIC_SOURCES

_copy ../../LICENSE.TXT       "$DESTDIR"/builtins/LICENSE.TXT
_cpd "${GENERIC_SOURCES[@]}"  "$DESTDIR"/builtins
_cpd "${AARCH64_SOURCES[@]}"  "$DESTDIR"/builtins/aarch64
_cpd "${ARM_SOURCES[@]}"      "$DESTDIR"/builtins/arm
_cpd "${ARM_EABI_SOURCES[@]}" "$DESTDIR"/builtins/arm_eabi
_cpd "${X86_ARCH_SOURCES[@]}" "$DESTDIR"/builtins/x86
_cpd "${I386_SOURCES[@]}"     "$DESTDIR"/builtins/i386
_cpd "${X86_64_SOURCES[@]}"   "$DESTDIR"/builtins/x86_64
_cpd "${RISCV_SOURCES[@]}"    "$DESTDIR"/builtins/riscv
_cpd "${RISCV32_SOURCES[@]}"  "$DESTDIR"/builtins/riscv32
_cpd "${RISCV64_SOURCES[@]}"  "$DESTDIR"/builtins/riscv64
_cpd "${DARWIN_SOURCES[@]}"   "$DESTDIR"/builtins/any-macos

for var in ${EXCLUDE_BUILTINS_VARS[@]}; do
  IFS=. read -r ign sys arch <<< "${var//__/.}"
  outfile="$DESTDIR/builtins/filters/${arch:-any}-$sys.exclude"
  mkdir -p "$DESTDIR/builtins/filters"
  echo "create $(_relpath "$outfile")"
  echo ${!var} > "$outfile"
done

# ————————————————————————————————————————————————————————————————————————————————————
# generate build files

_pushd "$DESTDIR/builtins"

_gen_buildfile() { # <arch> <sys> [<sysver>]
  local arch sys sysver f name src obj var
  IFS=- read -r arch sys <<< "$1"
  IFS=. read -r sys sysver <<< "$sys"
  local triple=$arch-$sys
  case "$sys" in
    linux) triple=$arch-linux-musl ;;
    macos) triple=$arch-apple-darwin
      if [ -z "$sysver" -a "$arch" = aarch64 ]; then
        sysver=11
      elif [ -z "$sysver" ]; then
        sysver=10
      fi
      case "$sysver" in
        "") triple=${triple}19 ;;
        *)  triple=${triple}$(( ${sysver%%.*} + 9 )) ;;
      esac
      ;;
    wasi) triple=$arch-unknown-wasi ;;
  esac
  local target=$arch-$sys; [ -n "$sysver" ] && target=$target.$sysver
  # echo "arch=$arch sys=$sys sysver=$sysver triple=$triple"

  local BF="build-$target.ninja"

  echo "generating $(_relpath "$PWD/$BF")"

  # see compiler-rt/lib/builtins/CMakeLists.txt
  local CFLAGS=(
    -std=c11 -nostdinc -Os --target=$triple \
    -fPIC \
    -fno-builtin \
    -fomit-frame-pointer \
    -Wno-nullability-completeness \
    -I. \
    -I../../lib/clang/$LLVM_RELEASE/include \
  )
  # note: lib/clang/$LLVM_RELEASE/include contains headers for all supported archs

  # system and libc headers
  [ -n "$sysver" ] &&
    CFLAGS+=( -I../../targets/$arch-$sys.$sysver/include )
  CFLAGS+=( -I../../targets/$arch-$sys/include )
  CFLAGS+=( -I../../targets/any-$sys/include )
  # for f in ${CFLAGS[@]}; do echo $f; done

  # TODO: $COMPILER_RT_HAS_FLOAT16 && CFLAGS+=( -DCOMPILER_RT_HAS_FLOAT16 )

  # arch-specific flags
  case "$arch" in
    riscv32) CFLAGS+=( -fforce-enable-int128 ) ;;
  esac

  # exclude certain functions, depending on platform and arch
  for f in \
    filters/$arch-$sys.$sysver.exclude \
    filters/$arch-$sys.exclude \
    filters/any-$sys.exclude \
  ;do
    [ -f $f ] || continue
    for name in $(cat $f); do
      declare EXCLUDE_FUN__${arch//-/_}__${sys}__${name##*/}=1
    done
  done

  # generate ninja file
  cat << END > $BF
cflags = ${CFLAGS[@]}
libdir = ../../targets/$target/lib
obj = /tmp/llvmbox-$LLVM_RELEASE+$LLVMBOX_VERSION_TAG-rt-$target
rule cc
  command = ../../bin/clang -MMD -MF \$out.d \$cflags \$flags -c -o \$out \$in
  depfile = \$out.d
  description = cc \$in -> \$out
rule ar
  command = rm -f \$out && ../../bin/ar crs \$out \$in
  description = archive \$out
END

  local objects=()
  for f in *.c $arch/*.[csS] any-$sys/*.[csS] $arch-$sys/*.[csS]; do
    [ -f "$f" ] || continue
    name=${f:0:-2}
    name=${name##*/}
    var=EXCLUDE_FUN__${arch//-/_}__${sys}__${name}
    if [ -n "${!var:-}" ]; then
      # echo "excluding $f"
      continue
    fi
    obj=\$obj/${f/%.[csS]/.o}
    objects+=( "$obj" )
    echo "build $obj: cc $f" >> $BF
  done

  echo "build \$libdir/librt.a: ar ${objects[@]}" >> $BF
  echo "default \$libdir/librt.a" >> $BF
}

for target in ${SUPPORTED_DIST_TARGETS[@]}; do
  [[ "$target" == wasm* ]] && continue  # TODO wasm{32,64}-wasi
  _gen_buildfile $target &
done
wait
