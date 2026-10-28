#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
CURRENT="$(command -v vantasm || true)"

[ -n "$CURRENT" ] || { echo "HOLD: existing vantasm CLI not found"; exit 4; }
mkdir -p "$H"

if [ -L "$CURRENT" ]; then
  resolved="$(readlink -f "$CURRENT" 2>/dev/null || true)"
else
  resolved="$CURRENT"
fi

if [ "$resolved" != "$H/vantasm-wrapper" ]; then
  cp -p "$resolved" "$H/vantasm-core"
  chmod 700 "$H/vantasm-core"
fi

install -m 700 "$SRC/scripts/vantasm-launch.sh" "$H/vantasm-launch"

cat >"$H/vantasm-wrapper" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
if [ "${1:-}" = "launch" ]; then
  shift
  exec "$H/vantasm-launch" "$@"
fi
exec "$H/vantasm-core" "$@"
EOF
chmod 700 "$H/vantasm-wrapper"

ln -sf "$H/vantasm-wrapper" "$BIN/vantasm"

echo "PASS: installed canonical command:"
echo "  vantasm launch"
echo "All other vantasm commands delegate unchanged to:"
echo "  $H/vantasm-core"
