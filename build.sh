#!/bin/bash
set -e ; source "$(dirname "$0")/config.sh"

DRYRUN=false
VERBOSE=false

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
Builds the entire thing; runs all build scripts
usage: $0 [options]
options:
  --dryrun       Don't actually run scripts, just print what would be done
  -v, --verbose  Show all output on stdout and stderr (disables parallelism)
  -h, --help     Print help on stdout and exit
EOF
    exit ;;
  --dryrun)     DRYRUN=true; shift ;;
  -v|--verbose) VERBOSE=true; shift ;;
  -*) _err "Unexpected option $1" ;;
  *)  _err "Unexpected argument $1" ;;
esac; done


_pushd "$PROJECT"

# find all unique prefixes, e.g. 010, 011, 020, 021 ...
prefixes=()
for f in $(echo 0*.sh | sort); do
  prefix=${f:0:3}
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
        echo "bash '$script' > '$(_relpath "$outlog")' 2> '$(_relpath "$errlog")'"
      else
        echo "bash '$script' > '$(_relpath "$outlog")' 2> '$(_relpath "$errlog")' &"
      fi
    elif $VERBOSE; then
      echo bash $script
      (bash "$script" | tee "$outlog") 3>&1 1>&2 2>&3 | tee "$errlog"
    else
      printf "$script  "
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

