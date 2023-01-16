zfs create -V 16G -b 8192 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false rpool/swap1
mkswap -f /dev/zvol/rpool/swap1
swapon /dev/zvol/rpool/swap1

# To mount on boot, edit fstab and add:
#   /dev/zvol/rpool/swap1 none swap discard 0 0

# To remove:
#   zfs destroy rpool/swap1
