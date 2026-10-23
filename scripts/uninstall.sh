#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
HOME_DIR="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
echo "This preserves receipts/backups by default."
[ -x "$HOME_DIR/stop.sh" ] && "$HOME_DIR/stop.sh" || true
if [ -f "$HOME_DIR/tunnel.pid" ]; then kill "$(cat "$HOME_DIR/tunnel.pid")" 2>/dev/null || true; rm -f "$HOME_DIR/tunnel.pid"; fi
rm -rf "$HOME_DIR/app" "$HOME_DIR/venv"
echo "Removed executable runtime only. Control-plane records remain at $HOME_DIR"
