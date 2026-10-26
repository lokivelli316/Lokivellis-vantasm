#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BK="$H/backups/vantasm-connect-$STAMP"

echo "Vantasm connection manager installer — $(cat "$SRC/VERSION" 2>/dev/null)"
[ -f "$H/config.json" ] || { echo "FAIL: no Surgeon config at $H/config.json — install Forge Surgeon first (bash scripts/install.sh)."; exit 1; }
[ -x "$H/venv/bin/python" ] || { echo "FAIL: no Surgeon venv at $H/venv — run bash scripts/repair-existing.sh first."; exit 1; }

need=()
command -v cloudflared >/dev/null 2>&1 || need+=(cloudflared)
command -v curl >/dev/null 2>&1 || need+=(curl)
command -v termux-wake-lock >/dev/null 2>&1 || need+=(termux-tools)
if [ "${#need[@]}" -gt 0 ]; then
  if [ -n "${VANTASM_SKIP_PKG:-}" ]; then echo "skipping pkg install of: ${need[*]}"
  else echo "Installing: ${need[*]}"; pkg install -y "${need[@]}"; fi
fi

if ! "$H/venv/bin/python" -I -c 'import httpx2, mcp.client.streamable_http' 2>/dev/null; then
  echo "FAIL: Surgeon venv cannot import the MCP 2.x client (httpx2 / mcp). Run bash scripts/repair-existing.sh."
  exit 1
fi

mkdir -p "$BK" "$H/tools"
chmod 700 "$BK" "$H/tools"
for f in "$H/vantasm" "$H/tools/vantasm_probe.py" "$H/start-tunnel.sh"; do
  [ -e "$f" ] && cp -p "$f" "$BK/" && echo "backed up $f"
done

install -m 700 "$SRC/connect/vantasm" "$H/vantasm"
install -m 600 "$SRC/connect/vantasm_probe.py" "$H/tools/vantasm_probe.py"
install -m 700 "$SRC/scripts/vantasm-bridge-up.sh" "$H/vantasm-bridge-up"
cat >"$H/start-tunnel.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "$H/vantasm-bridge-up" "\$@"
EOF
chmod 700 "$H/start-tunnel.sh"
if [ -d "$BIN" ] && [ -w "$BIN" ]; then
  ln -sf "$H/vantasm" "$BIN/vantasm"
  ln -sf "$H/vantasm-bridge-up" "$BIN/vantasm-bridge-up"
  echo "linked $BIN/vantasm"
  echo "linked $BIN/vantasm-bridge-up"
fi

{
  echo "{"
  echo "  \"receipt\": \"vantasm-connect-install-$STAMP\","
  echo "  \"version\": \"$(cat "$SRC/VERSION" 2>/dev/null)\","
  echo "  \"installed\": [\"$H/vantasm\", \"$H/vantasm-bridge-up\", \"$H/tools/vantasm_probe.py\", \"$H/start-tunnel.sh\"],"
  echo "  \"sha256\": {"
  echo "    \"vantasm\": \"$(sha256sum "$H/vantasm" | cut -d' ' -f1)\","
  echo "    \"vantasm_probe.py\": \"$(sha256sum "$H/tools/vantasm_probe.py" | cut -d' ' -f1)\""
  echo "  },"
  echo "  \"backup_dir\": \"$BK\""
  echo "}"
} >"$BK/INSTALL_RECEIPT.json"
chmod 600 "$BK/INSTALL_RECEIPT.json"

echo "PASS: vantasm installed. Receipt: $BK/INSTALL_RECEIPT.json"
echo "Next:"
echo "  vantasm doctor"
echo "  vantasm-bridge-up"
echo "  vantasm-bridge-up --watch"
