#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
VM_DIR="${APPWRITE_VM_DIR:-$ROOT/appwrite-vm}"
ENV_FILE="$VM_DIR/vm.env"
PIDFILE="$VM_DIR/qemu.pid"

[ -f "$ENV_FILE" ] || { echo "HOLD: VM not prepared"; exit 4; }
. "$ENV_FILE"

echo "=== APPWRITE QEMU VM STATUS ==="
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "qemu: RUNNING pid=$(cat "$PIDFILE")"
else
  echo "qemu: STOPPED"
  exit 4
fi

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -i "$SSH_KEY" -p 2222 vantasm@127.0.0.1)
"${SSH[@]}" 'echo "guest: $(uname -m) $(uname -r)"; sudo docker info --format "docker: {{.ServerVersion}}" 2>/dev/null; sudo docker compose version 2>/dev/null; if test -f /var/lib/vantasm-docker-appwrite-ready; then echo "appwrite-image: READY"; else echo "appwrite-image: PREPARING"; fi' || {
  echo "guest_ssh: NOT_READY"
  exit 4
}

if curl -fsS --max-time 5 http://127.0.0.1:18080/v1/health >/dev/null 2>&1; then
  echo "appwrite_http: PASS"
  exit 0
fi
if curl -fsS --max-time 5 http://127.0.0.1:18080/ >/dev/null 2>&1; then
  echo "appwrite_http: RESPONDING"
  exit 0
fi

echo "appwrite_http: NOT_YET_LIVE"
exit 4
