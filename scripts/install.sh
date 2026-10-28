#!/data/data/com.termux/files/usr/bin/bash
# Vantasm / Forge Surgeon clean-phone installer.
#
# Portability rules (README "Portability rule"):
#   * no developer $HOME, repo names, PIDs, tunnel URLs, or device model baked in;
#   * all runtime state lives under $FORGE_SURGEON_HOME (default ~/.forge-surgeon);
#   * seat credentials are generated LOCALLY on this device, never committed;
#   * idempotent: re-running does NOT rotate existing credentials;
#   * no hidden persistence: no boot hooks, no crontab. Start with `vantasm up`.
#
# Env overrides:
#   FORGE_SURGEON_HOME   control root (default ~/.forge-surgeon)
#   VANTASM_WORKSPACE    authorized seat root (default ~/vantasm-workspace)
#   VANTASM_SKIP_PKG=1   skip `pkg install`
#   VANTASM_SKIP_VENV=1  skip venv/pip (config + creds only)
set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
WORKSPACE="${VANTASM_WORKSPACE:-$HOME/vantasm-workspace}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
VERSION="$(cat "$SRC/VERSION" 2>/dev/null || echo unknown)"
BIN="${PREFIX:-/usr}/bin"

echo "Forge Surgeon / Vantasm installer — $VERSION"
echo "control root: $H"

mkdir -p "$H" "$H/app" "$H/runtime" "$H/logs" "$H/backups" "$WORKSPACE"
chmod 700 "$H" "$H/runtime" "$H/backups" 2>/dev/null || true

# 1. Stage source into the control root (so the venv can run it from a stable path)
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude .git "$SRC"/ "$H/app"/
else
  rm -rf "$H/app"/* && cp -R "$SRC"/. "$H/app"/ && rm -rf "$H/app/.git"
fi

# 2. Package dependencies (optional/tolerant)
if [ -z "${VANTASM_SKIP_PKG:-}" ] && command -v pkg >/dev/null 2>&1; then
  pkg install -y python git cloudflared >/dev/null 2>&1 || echo "WARN: pkg install step incomplete; continuing"
fi

# 3. Isolated venv for the server (tolerant: config/creds still complete if this fails)
DEPS_STATUS="SKIPPED"
if [ -z "${VANTASM_SKIP_VENV:-}" ]; then
  python3 -m venv "$H/venv"
  "$H/venv/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
  if "$H/venv/bin/pip" install "$H/app" >/dev/null 2>&1; then
    DEPS_STATUS="OK"
  else
    DEPS_STATUS="HOLD"
    echo "WARN: dependency install failed (e.g. mcp[cli] unreachable). Config + credentials still created."
    echo "      Re-run after resolving network/deps; 'vantasm doctor' will show mcp_runtime HOLD until then."
  fi
fi

# 4. Config with device-generated seat credentials (idempotent)
CONFIG="$H/config.json"
if [ -f "$CONFIG" ]; then
  cp -p "$CONFIG" "$H/backups/config-$STAMP.json"
  echo "existing config preserved (credentials NOT rotated); backup: $H/backups/config-$STAMP.json"
else
  python3 - "$SRC/config/config.example.json" "$CONFIG" "$WORKSPACE" <<'PY'
import json, secrets, sys
from pathlib import Path
example, out, workspace = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
cfg = json.loads(Path(example).read_text())
for seat, row in cfg.get("seats", {}).items():
    if str(row.get("credential", "")) in ("", "GENERATE_AT_INSTALL"):
        row["credential"] = secrets.token_urlsafe(48)           # generated on THIS device
    row["allowed_roots"] = [str(Path(workspace).expanduser())]  # authorize the chosen workspace only
out.write_text(json.dumps(cfg, indent=2) + "\n")
out.chmod(0o600)
print(f"generated config with device-local credentials: {out}")
PY
fi
chmod 600 "$CONFIG" 2>/dev/null || true

# 5. Install the vantasm CLI + stop helper
install -m 700 "$SRC/connect/vantasm" "$H/vantasm" 2>/dev/null || { cp "$SRC/connect/vantasm" "$H/vantasm"; chmod 700 "$H/vantasm"; }
cat >"$H/stop.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "$H/vantasm" down
EOF
chmod 700 "$H/stop.sh"
if [ -d "$BIN" ] && [ -w "$BIN" ]; then ln -sf "$H/vantasm" "$BIN/vantasm" && echo "linked $BIN/vantasm"; fi

# 6. Machine-readable install receipt
RECEIPT="$H/backups/INSTALL_RECEIPT-$STAMP.json"
cat >"$RECEIPT" <<EOF
{
  "receipt": "vantasm-install-$STAMP",
  "version": "$VERSION",
  "control_root": "$H",
  "workspace": "$WORKSPACE",
  "deps": "$DEPS_STATUS",
  "config": "$CONFIG",
  "no_hidden_persistence": true
}
EOF
chmod 600 "$RECEIPT"

echo "install receipt: $RECEIPT"
echo "Next:"
echo "  vantasm doctor     # machine-readable readiness"
echo "  vantasm up         # start (HOLDs cleanly if anything is missing)"
echo "  vantasm health"
