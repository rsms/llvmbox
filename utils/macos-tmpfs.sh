#!/bin/bash
set -e

if [ "$1" = "-h" -o "$1" = "--help" ]; then
  echo "usage: $0 <mountpoint> [sizemb]"
  exit 0
fi
if [ -z "$1" ]; then
  echo "$0: missing <mountpoint>" >&2
  exit 1
fi

mountpoint=$1
ramfs_size_mb=${2:-16384}  # 16GB by default

sectors=$(( ${ramfs_size_mb} * 1024 * 1024 / 512 ))
dev=$(hdid -nomount ram://$sectors)

newfs_hfs -v "$(basename "$mountpoint")" $dev
mkdir -p "$mountpoint"
mount -o noatime -t hfs $dev "$mountpoint"

echo "ramfs mounted at $mountpoint; to unmount:"
echo "umount '$mountpoint' && diskutil eject $dev"
