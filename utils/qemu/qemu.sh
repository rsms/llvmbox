#!/bin/bash
set -euo pipefail
ORIG_PWD=$PWD
cd "$(dirname "$0")"
_err() { echo "$0:" "$@" >&2; exit 1; }

HOST_ARCH=$(uname -m) ; HOST_ARCH=${HOST_ARCH/arm64/aarch64}
HOST_SYS=$(uname -s)
GUEST_ARCH=${GUEST_ARCH:-aarch64}
INSTANCE_DIR=${INSTANCE_DIR:-instance-$GUEST_ARCH}
PRINT_INSTEAD_OF_EXEC=false
SSH_PORT=10022
LOADVM=
QEMU_SMP=${QEMU_SMP:-}
QEMU_CMD=qemu-system-$GUEST_ARCH
QEMU_ARGS=(
  -nodefaults \
  -nographic \
  -device virtio-rng-pci \
  -device virtio-balloon \
  -m "${QEMU_MEM:-32G}" \
  -rtc base=utc,clock=host,driftfix=slew \
  -D "${INSTANCE_DIR##$PWD/}/qemu.log" \
  -monitor "unix:${INSTANCE_DIR##$PWD/}/qemu-monitor.sock,server,nowait" \
  -serial mon:stdio \
)

# command line
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help) cat << EOF
Run qemu-system-ARCH
usage: $0 [options] [<snapshot-name>] [-- <qemu-arg> ...]
options:
  -arch=ARCH   Run qemu-system-ARCH (default: $GUEST_ARCH)
  -ssh=PORT    Make SSHD listen on PORT (default: $SSH_PORT)
  -print-cmd   Print QEMU command on stdout instead of executing it
  -h, --help   Show help on stdout and exit
<snapshot-name>
  If provided, restore the VM from the named snapshot, previously
  saved via "savevm" in the qemu monitor.
<qemu-arg>
  Arguments passed on to qemu-system-ARCH
EOF
    exit 0 ;;
  -arch=*)      GUEST_ARCH=${1:6}; shift ;;
  -ssh=*)       SSH_PORT=${1:5}; shift ;;
  -print-cmd)   PRINT_INSTEAD_OF_EXEC=true; shift ;;
  --)           shift; break ;;
  -*)           _err "unknown option $1" ;;
  *)            [ -n "$LOADVM" ] _err "unexpected argument $1"
                LOADVM="$1"; shift ;;
esac; done

# disk image
DISK0_IMG="${INSTANCE_DIR##$PWD/}/disk0.qcow2"
QEMU_ARGS+=( -drive "if=virtio,file=${DISK0_IMG##$PWD/},index=0" )
mkdir -p "$INSTANCE_DIR"
[[ "$DISK0_IMG" == *","* ]] && _err "Invalid filename (contains \",\"): $DISK0_IMG"
if [ -f "$DISK0_IMG" ]; then
  echo "Using ${DISK0_IMG##$PWD/}"
  qemu-img check -q -r leaks "$DISK0_IMG"
else
  if [ -f res/userdisk-$GUEST_ARCH.qcow2 ]; then
    echo "Creating ${DISK0_IMG##$PWD/} from template res/userdisk-$GUEST_ARCH.qcow2"
    cp -v res/userdisk-$GUEST_ARCH.qcow2 "$DISK0_IMG"
  else
    echo "Creating new blank image -- manual setup required" >&2
    ALPINE_VERSION=3.17.1
    # ALPINE_IMG_FILE=alpine-virt-$ALPINE_VERSION-$GUEST_ARCH.iso
    ALPINE_IMG_FILE=alpine-standard-$ALPINE_VERSION-$GUEST_ARCH.iso
    ALPINE_IMG_URL=https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}
    ALPINE_IMG_URL=$ALPINE_IMG_URL/releases/$GUEST_ARCH/$ALPINE_IMG_FILE
    qemu-img create -f qcow2 -o compression_type=zlib "$DISK0_IMG" 64G
    qemu-img create -f qcow2 -o compression_type=zlib "$INSTANCE_DIR/setup.qcow2" 64G
    [ -f "$ALPINE_IMG_FILE" ] || wget "$ALPINE_IMG_URL"
    QEMU_ARGS+=( \
      -cdrom "$ALPINE_IMG_FILE" \
      -drive "if=virtio,file=${INSTANCE_DIR##$PWD/}/setup.qcow2" \
    )
  fi
  chmod 0600 "$DISK0_IMG"
fi

# processors
if [ -z "$QEMU_SMP" ]; then
  CPU_N=$(nproc)
  CPU_CORES=$CPU_N
  CPU_THREADS=1
  [ $CPU_CORES -gt 255 ] && CPU_CORES=255  # limit in qemu 7
  case "$HOST_SYS" in
    Linux)
      CPU_CORES=$(grep -m1 -E 'cpu cores\b' /proc/cpuinfo | cut -d' ' -f3)
      CPU_THREADS=$(( $CPU_N / $CPU_CORES ))
      ;;
    Darwin)
      if [ $CPU_N -gt 8 ]; then
        # limitation on macOS
        CPU_CORES=8
      else
        # note: -1 because qemu on macOS bugs out when smp>=NPROC
        CPU_CORES=$(( $(sysctl -n hw.physicalcpu) - 1 ))
        CPU_THREADS=$(( $CPU_N / $CPU_CORES ))
      fi
      ;;
    *)
  esac
  if [ $CPU_N -gt 8 -a "$HOST_ARCH" != "$GUEST_ARCH" ]; then
    # limitation when not virtualizing cpu
    CPU_CORES=8
    CPU_THREADS=1
  fi
  CPU_N=$(( $CPU_CORES * $CPU_THREADS ))
  if [ $CPU_N -gt 1 ]; then
    QEMU_ARGS+=( -smp "$CPU_N,sockets=1,cores=$CPU_CORES,threads=$CPU_THREADS" )
  fi
fi

# EFI (required for aarch64)
if [ "$GUEST_ARCH" = aarch64 ]; then
  EFI_BIOS=$INSTANCE_DIR/efibios.fd
  EFI_IMAGE=$INSTANCE_DIR/efi.img
  EFI_DISK=$INSTANCE_DIR/efidata.qcow2
  [ -f "$EFI_BIOS" ]  || gunzip -c -d res/efi-$GUEST_ARCH-bios.fd.gz > "$EFI_BIOS"
  [ -f "$EFI_IMAGE" ] || gunzip -c -d res/efi-$GUEST_ARCH.img.gz > "$EFI_IMAGE"
  [ -f "$EFI_DISK" ]  && { qemu-img check -q -r leaks "$EFI_DISK" || rm "$EFI_DISK"; }
  [ -f "$EFI_DISK" ]  || qemu-img create -f qcow2 "$EFI_DISK" 64M
  # Source of the EFI image & bios:
  # ( cd res
  #   wget http://snapshots.linaro.org/components/kernel/leg-virt-tianocore-edk2-upstream/4782/QEMU-AARCH64/RELEASE_GCC5/QEMU_EFI.img.gz
  #   wget http://snapshots.linaro.org/components/kernel/leg-virt-tianocore-edk2-upstream/4782/QEMU-AARCH64/RELEASE_GCC5/QEMU_EFI.fd
  #   mv QEMU_EFI.img.gz efi-aarch64.img.gz
  #   mv QEMU_EFI.fd efi-aarch64-bios.fd
  #   gzip -9 efi-aarch64-bios.fd
  # )
  QEMU_ARGS+=(
    -drive "if=pflash,format=raw,file=${EFI_IMAGE##$PWD/}" \
    -drive "if=pflash,file=${EFI_DISK##$PWD/}" \
  )
fi

# network
# QEMU_ARGS+=(
#   -netdev "user,id=net1,hostname=llvmbox" \
#   -device virtio-net,netdev=net1 \
# )
# QEMU_ARGS+=(
#   -netdev "user,id=net1,hostname=llvmbox,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
#   -device "virtio-net-pci,netdev=net1" \
# )
QEMU_ARGS+=(
  -netdev "user,id=net1,hostname=llvmbox,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
  -device "virtio-net,netdev=net1" \
)

# change qemu text-mode key control sequence from the default ^A to ^T
# See https://www.qemu.org/docs/master/system/invocation.html?highlight=echr
QEMU_ARGS+=( -echr 0x14 )

# loadvm
[ -n "$LOADVM" ] &&
  QEMU_ARGS+=( -loadvm "$LOADVM" )

# host-system + guest-arch specific configuration
case "$HOST_SYS-$HOST_ARCH/$GUEST_ARCH" in
  # qemu-system-aarch64 -cpu help
  # qemu-system-aarch64 -machine help
  Darwin-x86_64/x86_64)   QEMU_ARGS+=( -cpu host -accel hvf );;
  Darwin-aarch64/aarch64) QEMU_ARGS+=( -cpu host -machine virt,accel=hvf,highmem=on );;
  Darwin-aarch64/x86_64)  QEMU_ARGS+=( -cpu max -machine virt,accel=hvf,highmem=on );;
  Darwin-x86_64/aarch64)  QEMU_ARGS+=( -cpu cortex-a76 -machine virt,highmem=on );;
  Linux-x86_64/x86_64)    QEMU_ARGS+=( -cpu host -accel kvm );;
  Linux-aarch64/x86_64)   QEMU_ARGS+=( -cpu host -accel kvm );;
  Linux-x86_64/aarch64)   QEMU_ARGS+=( -cpu max -machine virt,highmem=on );;
  *)
    _err "not implemented for: host=$HOST_SYS-$HOST_ARCH guest=$GUEST_ARCH"
    ;;
esac

#——————————————————————————————————————————————————————————————————————————————————————

if $PRINT_INSTEAD_OF_EXEC; then
  for arg in "${QEMU_ARGS[@]}" "$@"; do
    case "$arg" in
      *" "*|*"&"*|*";"*|*"?"*) QEMU_CMD="$QEMU_CMD '$arg'" ;;
      *) QEMU_CMD="$QEMU_CMD $arg" ;;
    esac
  done
  [ "$PWD" != "$ORIG_PWD" ] && echo -n "cd '$PWD' && "
  echo $QEMU_CMD
  exit 0
fi


# raise file descriptors limit
ulimit -n 4096

exec "$QEMU_CMD" "${QEMU_ARGS[@]}" "$@"





# echo "You can connect to the QEMU monitor at $PWD/monitor.sock like this:"
# echo "  rlwrap socat -,echo=0,icanon=0 unix-connect:monitor.sock"

# first argument to this script is an optional vm snapshot to start from
[ -z "$1" ] || QEMU_ARGS+=( -loadvm "$1" )

exec qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -smp 4 \
  -m 2048 \
  -rtc base=utc,clock=host,driftfix=slew \
  \
  -bios QEMU_EFI.fd \
  \
  -device virtio-rng-pci \
  -device virtio-balloon \
  -nographic \
  -no-reboot \
  -serial mon:stdio \
  \
  -drive "if=virtio,file=$DISK0_IMG" \
  \
  -monitor "unix:monitor.sock,server,nowait" \
  \
  -netdev "user,id=net1,hostfwd=tcp:127.0.0.1:10022-:22" \
  -device "virtio-net-pci,netdev=net1" \
  \
  "${QEMU_ARGS[@]}"
