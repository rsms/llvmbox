#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

DRYRUN=false
VERBOSE=false
PREFIX=

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
Builds the entire thing; runs all build scripts with <prefix>
usage: $0 [options] [<prefix>]
options:
  --dryrun       Don't actually run scripts, just print what would be done
  -jN            Limit paralellism to N (defaults to $NCPU on this machine)
  -v, --verbose  Show all output on stdout and stderr
  -h, --help     Print help on stdout and exit
<prefix>
  If set, only run scripts with this prefix. If empty or not set, all scripts
  are run. Example: "02"
EOF
    exit ;;
  --dryrun)     DRYRUN=true; shift ;;
  -v|--verbose) VERBOSE=true; shift ;;
  -j*)          NCPU=${1:2}; [ -n "$NCPU" ] || NCPU=$(nproc); export LLVMBOX_NCPU=NCPU;;
  -*) _err "Unexpected option $1" ;;
  *)  [ -z "$PREFIX" ] || _err "Unexpected argument $1"; PREFIX=$1; shift ;;
esac; done


_pushd "$PROJECT"

# find all unique prefixes, e.g. 010, 011, 020, 021 ...
prefixes=()
for f in $(echo 0*.sh | sort); do
  prefix=${f:0:3}
  if [ -n "$PREFIX" ] && [[ "$prefix" != "$PREFIX"* ]]; then
    continue
  fi
  declare "sets_$prefix=$sets_$prefix $f"
  prefix_key="prefixes_$prefix"
  if [ -z "${!prefix_key}" ]; then
    declare "$prefix_key=1"
    prefixes+=( $prefix )
  fi
done

if $DRYRUN; then
  echo "# --dryrun is set; just printing what to do, not running any scripts"
else
  if $VERBOSE; then
    echo "stdout saved to $(_relpath "$LLVMBOX_BUILD_DIR")/log/SCRIPTNAME.out.log"
    echo "stderr saved to $(_relpath "$LLVMBOX_BUILD_DIR")/log/SCRIPTNAME.err.log"
  else
    echo "stdout redirected to $(_relpath "$LLVMBOX_BUILD_DIR")/log/SCRIPTNAME.out.log"
    echo "stderr redirected to $(_relpath "$LLVMBOX_BUILD_DIR")/log/SCRIPTNAME.err.log"
  fi
  mkdir -p "$LLVMBOX_BUILD_DIR/log"
fi

# run each prefix in order, all scripts per prefix concurrently
for prefix in "${prefixes[@]}"; do
  $DRYRUN || $VERBOSE || printf "bash "
  for script in $(echo $prefix*.sh | sort); do
    outlog=$LLVMBOX_BUILD_DIR/log/$(basename $script .sh).out.log
    errlog=$LLVMBOX_BUILD_DIR/log/$(basename $script .sh).err.log
    if $DRYRUN; then
      x=( $(echo $prefix*.sh | sort) )
      if [ ${#x[@]} -eq 1 ]; then
        echo "run '$script' > '$(_relpath "$outlog")' 2> '$(_relpath "$errlog")'"
      else
        echo "run '$script' > '$(_relpath "$outlog")' 2> '$(_relpath "$errlog")' &"
      fi
    elif $VERBOSE; then
      echo "run $script"
      (bash "$script" | tee "$outlog") 3>&1 1>&2 2>&3 | tee "$errlog"
    else
      printf "$script "
      bash "$script" > "$outlog" 2> "$errlog" &
    fi
  done
  if $DRYRUN; then
    [ ${#x[@]} -eq 1 ] || echo wait
  elif ! $VERBOSE; then
    echo "..."
    wait
  fi
done

