#!/bin/bash
set -eo pipefail
source "$(dirname "$0")/config.sh"

DRYRUN=false
VERBOSE=false
PREFIX=

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
Builds the entire thing; runs all build scripts
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
  mkdir -p "$LLVMBOX_BUILD_DIR/log"
fi

INTERRUPTED=
trap "INTERRUPTED=1" SIGINT

# run each prefix in order, all scripts per prefix concurrently
for prefix in "${prefixes[@]}"; do
  for script in $(echo $prefix*.sh | sort); do
    outlog=$LLVMBOX_BUILD_DIR/log/$(basename $script .sh).out.log
    errlog=$LLVMBOX_BUILD_DIR/log/$(basename $script .sh).err.log
    if $DRYRUN; then
      echo "bash '$script' > '$(_relpath "$outlog")' 2> '$(_relpath "$errlog")'"
    else
      printf "bash %-25s > %s\n" \
        "$script" \
        "$(_relpath "$LLVMBOX_BUILD_DIR/log/$(basename "$script" .sh)").{out,err}.log"
      err=
      if $VERBOSE; then
        (bash "$script" | tee "$outlog") 3>&1 1>&2 2>&3 | tee "$errlog" || err=1
      else
        bash "$script" > "$outlog" 2> "$errlog" || err=1
      fi
      if [ -n "$err" -a -z "$INTERRUPTED" ]; then
        echo "$script failed:" >&2
        echo "—————————————————————— first 10 lines of stderr ——————————————————————" >&2
        head -n10 "$errlog" >&2
        echo "——————————————————————————————————————————————————————————————————————" >&2
        echo "Full output in log files:" >&2
        echo "  $outlog" >&2
        echo "  $errlog" >&2
      fi
      [ -z "$err" ] || exit 1
    fi
  done
done

