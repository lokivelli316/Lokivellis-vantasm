#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
VM_DIR="${APPWRITE_VM_DIR:-$ROOT/appwrite-vm}"
ENV_FILE="$VM_DIR/vm.env"

say(){ printf '%s\n' "$*"; }
hold(){ say "HOLD: $*"; exit 4; }

[ -f "$ENV_FILE" ] || hold "VM not prepared"
. "$ENV_FILE"

SSH=(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -i "$SSH_KEY" -p 2222 vantasm@127.0.0.1)

say "Checking guest..."
"${SSH[@]}" 'uname -a' || hold "guest SSH not ready yet"

if ! "${SSH[@]}" 'test -f /var/lib/vantasm-docker-appwrite-ready'; then
  say "HOLD: guest is up but cloud-init has not finished Docker/Appwrite preparation."
  say "Check cloud-init status over SSH."
  exit 4
fi

"${SSH[@]}" 'sudo docker --version && sudo docker compose version && sudo docker image inspect appwrite/appwrite:'"$APPWRITE_VERSION"' >/dev/null'
say
say "PASS: guest Docker/Compose and Appwrite ARM64 image are ready."
say "Launching official Appwrite web installer."
say "Phone installer bridge: http://127.0.0.1:20080"
exec "${SSH[@]}" -t 'sudo /usr/local/bin/start-appwrite-installer'
