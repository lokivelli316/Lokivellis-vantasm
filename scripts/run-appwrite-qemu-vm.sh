#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
VM_DIR="${APPWRITE_VM_DIR:-$ROOT/appwrite-vm}"
ENV_FILE="$VM_DIR/vm.env"
PIDFILE="$VM_DIR/qemu.pid"
SERIAL_LOG="$VM_DIR/serial.log"
MONITOR="$VM_DIR/qemu-monitor.sock"

say(){ printf '%s\n' "$*"; }
hold(){ say "HOLD: $*"; exit 4; }

[ -f "$ENV_FILE" ] || hold "VM not prepared; run scripts/prepare-appwrite-qemu-vm.sh first"
. "$ENV_FILE"

MEM_KB="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"
MIN_MEM_KB="${APPWRITE_VM_MIN_MEM_KB:-5242880}"
if [ -n "${MEM_KB:-}" ] && [ "$MEM_KB" -lt "$MIN_MEM_KB" ]; then
  hold "only $MEM_KB KiB MemAvailable; need at least $MIN_MEM_KB KiB before starting 4 GiB guest"
fi

if [ -f "$PIDFILE" ]; then
  OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    say "PASS: Appwrite VM already running pid=$OLD_PID"
    exit 0
  fi
  rm -f "$PIDFILE"
fi

rm -f "$MONITOR"
ACCEL_ARGS=(-accel tcg,thread=multi -cpu max)
if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL_ARGS=(-accel kvm -cpu host)
fi

qemu-system-aarch64 \
  -name vantasm-appwrite \
  -machine virt,gic-version=max \
  "${ACCEL_ARGS[@]}" \
  -smp 4 \
  -m 4096 \
  -bios "$FIRMWARE" \
  -drive if=none,file="$DISK_IMG",format=qcow2,id=vd0,cache=writeback \
  -device virtio-blk-pci,drive=vd0 \
  -drive if=none,file="$SEED_ISO",format=raw,readonly=on,id=seed \
  -device virtio-blk-pci,drive=seed \
  -netdev user,id=n1,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:20080-:20080,hostfwd=tcp:127.0.0.1:18080-:80,hostfwd=tcp:127.0.0.1:18443-:443 \
  -device virtio-net-pci,netdev=n1 \
  -display none \
  -serial "file:$SERIAL_LOG" \
  -monitor "unix:$MONITOR,server,nowait" \
  -pidfile "$PIDFILE" \
  -daemonize || hold "QEMU failed to start"

sleep 2
PID="$(cat "$PIDFILE" 2>/dev/null || true)"
[ -n "$PID" ] && kill -0 "$PID" 2>/dev/null || hold "QEMU exited immediately; inspect $SERIAL_LOG"

say "PASS: Appwrite VM started pid=$PID"
say "ssh: ssh -i \"$SSH_KEY\" -p 2222 vantasm@127.0.0.1"
say "installer when cloud-init finishes: bash scripts/start-appwrite-vm-installer.sh"
say "phone browser installer URL: http://127.0.0.1:20080"
say "Appwrite HTTP after install: http://127.0.0.1:18080"
