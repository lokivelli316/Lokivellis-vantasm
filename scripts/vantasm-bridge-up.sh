#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
BRIDGE_URL="${VANTASM_BRIDGE_URL:-https://vantasm-bridge.vercel.app}"
PAGES_REPO="${VANTASM_PAGES_REPO:-https://github.com/lokivelli316/EARLYWINE-PRESIDENTIAL-BLUEPRINT.git}"
PUBLISH_DIR="${VANTASM_PUBLISH_DIR:-$HOME/.local/share/vantasm/pages-publisher}"
DISCOVERY_REL="vantasm/endpoint.json"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

want_watch=0
args=()
for a in "$@"; do
  if [ "$a" = "--watch" ]; then want_watch=1; else args+=("$a"); fi
done

set +e
vantasm up "${args[@]}" 2>&1 | tee "$TMP"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" -eq 0 ] || exit "$rc"

url="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TMP" | tail -n1 || true)"
if [ -z "$url" ]; then
  url="$(grep -RhoE 'https://[a-z0-9-]+\.trycloudflare\.com' "$H/logs" "$H/runtime" 2>/dev/null | tail -n1 || true)"
fi
[ -n "$url" ] || { echo "HOLD: Vantasm started but no current trycloudflare URL could be discovered."; exit 4; }

if ! curl -fsS --max-time 20 "$url/healthz" >/dev/null; then
  echo "WARN: discovered tunnel failed /healthz; recycling stale Quick Tunnel once."

  SURGEON_PORT="${FORGE_SURGEON_PORT:-8765}"
  TUN_LOG="$H/logs/cloudflared-quick.log"
  TUN_PID="$H/runtime/cloudflared-quick.pid"
  mkdir -p "$H/logs" "$H/runtime"

  if [ -f "$TUN_PID" ]; then
    oldpid="$(cat "$TUN_PID" 2>/dev/null || true)"
    if [ -n "$oldpid" ]; then
      kill "$oldpid" >/dev/null 2>&1 || true
    fi
    rm -f "$TUN_PID"
  fi
  pkill -f "cloudflared.*tunnel.*--url.*127\\.0\\.0\\.1:${SURGEON_PORT}" >/dev/null 2>&1 || true
  sleep 1

  : >"$TUN_LOG"
  nohup cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${SURGEON_PORT}" \
    >"$TUN_LOG" 2>&1 </dev/null &
  echo $! >"$TUN_PID"

  url=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    url="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUN_LOG" | tail -n1 || true)"
    [ -n "$url" ] && break
    sleep 1
  done

  [ -n "$url" ] || {
    echo "HOLD: fresh cloudflared process did not emit a trycloudflare URL."
    tail -n 30 "$TUN_LOG" 2>/dev/null || true
    exit 5
  }

  echo "INFO: fresh Quick Tunnel discovered -> $url"
  ok=0
  for _ in 1 2 3 4 5 6; do
    if curl -fsS --max-time 20 "$url/healthz" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 2
  done
  [ "$ok" -eq 1 ] || { echo "HOLD: fresh tunnel still failed /healthz; refusing to publish."; exit 5; }

  echo "PASS: stale Quick Tunnel recycled and fresh /healthz verified."
fi

if [ ! -d "$PUBLISH_DIR/.git" ]; then
  mkdir -p "$(dirname "$PUBLISH_DIR")"
  git clone --depth=1 "$PAGES_REPO" "$PUBLISH_DIR" >/dev/null
else
  git -C "$PUBLISH_DIR" fetch origin main --depth=1 >/dev/null
  git -C "$PUBLISH_DIR" reset --hard origin/main >/dev/null
fi

mkdir -p "$PUBLISH_DIR/vantasm"
python3 - "$PUBLISH_DIR/$DISCOVERY_REL" "$url" "$BRIDGE_URL" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
base = sys.argv[2].rstrip("/")
bridge = sys.argv[3].rstrip("/")
payload = {
    "service": "vantasm",
    "base_url": base,
    "bridge_url": bridge,
    "health_path": "/healthz",
    "mcp_path": "/mcp",
    "updated_at": datetime.now(timezone.utc).isoformat(),
    "note": "Public routing metadata only. No credentials or seat tokens."
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

git -C "$PUBLISH_DIR" add "$DISCOVERY_REL"
if ! git -C "$PUBLISH_DIR" diff --cached --quiet; then
  git -C "$PUBLISH_DIR" -c user.name="Vantasm Endpoint Publisher" -c user.email="vantasm-endpoint@users.noreply.github.com"     commit -m "Refresh Vantasm tunnel endpoint" >/dev/null
  git -C "$PUBLISH_DIR" push origin HEAD:main >/dev/null
  echo "PASS: published current Vantasm tunnel for Vercel bridge."
else
  echo "PASS: discovery record already current."
fi

for _ in 1 2 3 4 5; do
  if curl -fsS --max-time 20 "$BRIDGE_URL/healthz" >/dev/null; then
    echo "PASS: stable bridge health -> $BRIDGE_URL/healthz"
    break
  fi
  sleep 2
done

if [ "$want_watch" -eq 1 ]; then
  exec vantasm up --watch "${args[@]}"
fi
