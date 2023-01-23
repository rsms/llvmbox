#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/config.sh"

_strset_add() { # <setvar> <value>
  local setvar=$1
  local valkey=$2
  local re='(.*)[\.\-](.*)'  # e.g. "macos.10.15" => "macos_10_15"
  while [[ $valkey =~ $re ]]; do
    valkey=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
  done
  local key="keyset_${setvar}_${valkey}"
  if [ -z "${!key:-}" ]; then
    eval "$key=1" # can't use 'declare -rg "$key=1"' in bash<4
    eval "$setvar+=( $2 )"
  fi
}

_strset_has() { # <setvar> <value>
  local setvar=$1
  local valkey=$2
  re='(.*)\.(.*)'  # e.g. "macos.10.15" => "macos_10_15"
  while [[ $valkey =~ $re ]]; do
    valkey=${BASH_REMATCH[1]}_${BASH_REMATCH[2]}
  done
  local key="keyset_${setvar}_${valkey}"
  [ -n "${!key:-}" ] || return 1
}

_scan_targets() { # <dir>
  pushd "$1" >/dev/null
  for f in *; do
    [ -d "$f" ] || continue
    IFS=- read -r arch sysver <<< "$f"
    IFS=. read -r sys sysver <<< "$sysver"
    [ -n "$sysver" -a "$arch" != "any" ] || continue
    # echo "($arch, $sys, $sysver)"
    _strset_add targets "${arch}-${sys}.${sysver}"
  done
  popd >/dev/null
}

_rsync_if_exist() { # <srcdir> <destdir>
  local srcdir=$1
  local destdir=$2
  [ -d "$srcdir" ] || return 0
  echo "  rsync $(_relpath "$srcdir")/ -> $(_relpath "$destdir")/"
  rsync -a "$srcdir/" "$destdir/"
}

_build_sysroot() { # <arch> <sys> <sysversion>
  local arch=$1
  local sys=$2
  local sysver=$3
  local sysver_major=${sysver%%.*}
  local key
  local destdir
  local combinations=( $(sort -u << END
    any-any
    $arch-any
    any-$sys
    any-$sys.$sysver_major
    any-$sys.$sysver
    $arch-$sys
    $arch-$sys.$sysver_major
    $arch-$sys.$sysver
END
  ))
  for key in "${combinations[@]}"; do
    include_dir="$SYSROOT_TEMPLATE/libc/include/$key"
    lib_dir="$SYSROOT_TEMPLATE/libc/lib/$key"
    [ -d "$include_dir" -o -d "$lib_dir" ] || continue
    if [ -z "$destdir" ]; then
      destdir=$DESTDIR/${arch}-${sys}.${sysver}
      echo "  mkdir $(_relpath "$destdir")"
      rm -rf "$destdir"
      mkdir -p "$destdir"/{lib,include}
    fi
    _rsync_if_exist "$include_dir" "$destdir/include"
    _rsync_if_exist "$lib_dir" "$destdir/lib"
  done
}

# ————————————————————————————————————————————————————————————————————————————————————

DESTDIR=$OUT_DIR/all-sysroots
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"

targets=()

_scan_targets "$SYSROOT_TEMPLATE"/libc/include
_scan_targets "$SYSROOT_TEMPLATE"/libc/lib

for target in "${targets[@]:-}"; do
  # parse e.g. "x86_64-macos.10" => (x86_64, macos, 10)
  IFS=- read -r arch sysver <<< "$target"
  IFS=. read -r sys sysver <<< "$sysver"
  echo "$target ($arch, $sys, $sysver)"
  _build_sysroot $arch $sys $sysver
done

# # create tar archives
# for dir in "$DESTDIR"/*; do
#   [ -d "$dir" ] || continue
#   echo "creating $(_relpath "$dir").tar.xz"
#   XZ_OPT='-T0' tar -C "$dir" -cJpf "$dir.tar.xz" . &
# done
# printf "..."
# wait
# echo " done"
