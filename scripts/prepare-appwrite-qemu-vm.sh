#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
VM_DIR="${APPWRITE_VM_DIR:-$ROOT/appwrite-vm}"
BASE_DIR="$VM_DIR/base"
CLOUD_DIR="$VM_DIR/cloud-init"
KEY_DIR="$VM_DIR/keys"
LOG_DIR="$VM_DIR/logs"

IMAGE_NAME="${APPWRITE_VM_IMAGE_NAME:-noble-server-cloudimg-arm64.img}"
IMAGE_BASE_URL="${APPWRITE_VM_IMAGE_BASE_URL:-https://cloud-images.ubuntu.com/noble/current}"
IMAGE_URL="$IMAGE_BASE_URL/$IMAGE_NAME"
SUMS_URL="$IMAGE_BASE_URL/SHA256SUMS"

BASE_IMG="$BASE_DIR/$IMAGE_NAME"
DISK_IMG="$VM_DIR/appwrite-vm.qcow2"
SEED_ISO="$VM_DIR/seed.iso"
SSH_KEY="$KEY_DIR/id_ed25519"

MIN_FREE_KB="${APPWRITE_VM_MIN_FREE_KB:-12582912}"
MIN_MEM_KB="${APPWRITE_VM_MIN_MEM_KB:-5242880}"
VM_DISK_SIZE="${APPWRITE_VM_DISK_SIZE:-20G}"
APPWRITE_VERSION="${APPWRITE_VERSION:-2.7.2}"

say(){ printf '%s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
hold(){ say "HOLD: $*"; exit 4; }

mkdir -p "$VM_DIR" "$BASE_DIR" "$CLOUD_DIR" "$KEY_DIR" "$LOG_DIR"

say "=== APPWRITE QEMU VM PREPARER ==="
say "target: phone-local AArch64 VM -> Docker/Compose -> Appwrite $APPWRITE_VERSION"
say

FREE_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
MEM_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"

say "free_disk_kib=${FREE_KB:-UNKNOWN}"
say "mem_available_kib=${MEM_KB:-UNKNOWN}"

if [ -n "${FREE_KB:-}" ] && [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
  NEED=$((MIN_FREE_KB - FREE_KB))
  hold "need at least $MIN_FREE_KB KiB free before VM preparation; short by $NEED KiB. No VM image was downloaded."
fi

if [ -n "${MEM_KB:-}" ] && [ "$MEM_KB" -lt "$MIN_MEM_KB" ]; then
  hold "need at least $MIN_MEM_KB KiB MemAvailable before provisioning/running a 4 GiB Appwrite guest. Close memory-heavy apps/models first."
fi

have pkg || hold "Termux pkg command unavailable"

say "Installing/verifying QEMU VM prerequisites..."
pkg install -y qemu-system-aarch64-headless qemu-utils xorriso openssh curl >/dev/null 2>&1 || \
  hold "Termux QEMU/xorriso prerequisites failed to install"

for cmd in qemu-system-aarch64 qemu-img xorriso ssh ssh-keygen curl sha256sum; do
  have "$cmd" || hold "required command missing after package install: $cmd"
done

FW=""
for candidate in \
  "${PREFIX:-/data/data/com.termux/files/usr}/share/qemu/edk2-aarch64-code.fd" \
  "${PREFIX:-/data/data/com.termux/files/usr}/share/qemu/edk2-arm-code.fd" \
  "${PREFIX:-/data/data/com.termux/files/usr}/share/qemu/QEMU_EFI.fd"
do
  if [ -f "$candidate" ]; then FW="$candidate"; break; fi
done
if [ -z "$FW" ]; then
  FW="$(find "${PREFIX:-/data/data/com.termux/files/usr}/share/qemu" -maxdepth 2 -type f \
    \( -iname '*aarch64*code*.fd' -o -iname 'QEMU_EFI.fd' \) -print -quit 2>/dev/null || true)"
fi
[ -n "$FW" ] || hold "AArch64 QEMU firmware was not found under \$PREFIX/share/qemu"
printf '%s\n' "$FW" > "$VM_DIR/firmware.path"
say "firmware=$FW"

if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -q -t ed25519 -N "" -f "$SSH_KEY" || hold "failed to generate VM SSH key"
fi
PUBKEY="$(cat "$SSH_KEY.pub")"

if [ ! -f "$BASE_IMG" ]; then
  say "Downloading Ubuntu ARM64 cloud image..."
  curl -fL --retry 3 -o "$BASE_IMG.part" "$IMAGE_URL" || hold "Ubuntu cloud image download failed"
  curl -fL --retry 3 -o "$BASE_DIR/SHA256SUMS" "$SUMS_URL" || hold "Ubuntu checksum download failed"
  EXPECTED="$(awk -v f="$IMAGE_NAME" '$2==f || $2=="*"f {print $1; exit}' "$BASE_DIR/SHA256SUMS")"
  [ -n "$EXPECTED" ] || hold "checksum for $IMAGE_NAME not found"
  ACTUAL="$(sha256sum "$BASE_IMG.part" | awk '{print $1}')"
  [ "$ACTUAL" = "$EXPECTED" ] || hold "Ubuntu cloud image SHA256 mismatch"
  mv "$BASE_IMG.part" "$BASE_IMG"
fi

if [ ! -f "$DISK_IMG" ]; then
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$DISK_IMG" >/dev/null || hold "failed to create qcow2 overlay"
  qemu-img resize "$DISK_IMG" "$VM_DISK_SIZE" >/dev/null || hold "failed to resize VM disk"
fi

cat >"$CLOUD_DIR/meta-data" <<EOF
instance-id: vantasm-appwrite-vm-01
local-hostname: appwrite-vm
EOF

cat >"$CLOUD_DIR/user-data" <<EOF
#cloud-config
hostname: appwrite-vm
manage_etc_hosts: true
users:
  - default
  - name: vantasm
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $PUBKEY
package_update: true
packages:
  - ca-certificates
  - curl
  - gnupg
  - openssh-server
write_files:
  - path: /usr/local/sbin/vantasm-install-docker-appwrite
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc
      . /etc/os-release
      echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      systemctl enable --now docker
      usermod -aG docker vantasm
      docker info >/var/log/vantasm-docker-info.txt
      docker compose version >/var/log/vantasm-docker-compose.txt
      docker pull appwrite/appwrite:$APPWRITE_VERSION
      mkdir -p /opt/appwrite
      cat >/usr/local/bin/start-appwrite-installer <<'APPWRITE'
      #!/bin/bash
      set -euo pipefail
      cd /opt/appwrite
      exec docker run -it --rm \
        --name appwrite-installer \
        --publish 0.0.0.0:20080:20080 \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --volume /opt/appwrite:/usr/src/code/appwrite:rw \
        --entrypoint=install \
        appwrite/appwrite:$APPWRITE_VERSION
      APPWRITE
      chmod 0755 /usr/local/bin/start-appwrite-installer
      touch /var/lib/vantasm-docker-appwrite-ready
runcmd:
  - [ bash, /usr/local/sbin/vantasm-install-docker-appwrite ]
final_message: "VANTASM_APPWRITE_VM_CLOUD_INIT_COMPLETE"
EOF

rm -f "$SEED_ISO"
xorriso -as mkisofs -quiet -output "$SEED_ISO" -volid cidata -joliet -rock \
  "$CLOUD_DIR/user-data" "$CLOUD_DIR/meta-data" || hold "failed to build cloud-init seed ISO"

cat >"$VM_DIR/vm.env" <<EOF
VM_DIR=$VM_DIR
BASE_IMG=$BASE_IMG
DISK_IMG=$DISK_IMG
SEED_ISO=$SEED_ISO
FIRMWARE=$FW
SSH_KEY=$SSH_KEY
APPWRITE_VERSION=$APPWRITE_VERSION
EOF

say
say "PREPARED: $VM_DIR"
say "guest_arch=aarch64"
say "guest_disk=$VM_DISK_SIZE"
say "appwrite=$APPWRITE_VERSION"
say "next: bash scripts/run-appwrite-qemu-vm.sh"
