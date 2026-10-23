#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
[ -x "$HOME_DIR/venv/bin/python" ] || { echo "No existing Surgeon venv at $HOME_DIR/venv"; exit 1; }
[ -f "$HOME_DIR/config.json" ] || { echo "No existing Surgeon config at $HOME_DIR/config.json"; exit 1; }
[ -x "$HOME_DIR/stop.sh" ] && "$HOME_DIR/stop.sh" || true
rm -rf "$HOME_DIR/app"
mkdir -p "$HOME_DIR/app" "$HOME_DIR/runtime" "$HOME_DIR/logs"
cp -R "$SRC"/. "$HOME_DIR/app"/
exec "$SRC/scripts/install.sh"
