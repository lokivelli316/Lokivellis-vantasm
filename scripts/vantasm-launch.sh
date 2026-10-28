#!/data/data/com.termux/files/usr/bin/bash
set -u

H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
CORE="${VANTASM_CORE_BIN:-$H/vantasm-core}"
BRIDGE="${VANTASM_BRIDGE_BIN:-$H/vantasm-bridge-up}"
PACK_ROOT="${VANTASM_PACK_ROOT:-$HOME/nemotron-v0451-live}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_DIR="${VANTASM_RUN_DIR:-$H/runtime/launch}"
mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR" 2>/dev/null || true
UP_LOG="$RUN_DIR/up.log"
BRIDGE_LOG="$RUN_DIR/bridge.log"
PACK_LOG="$RUN_DIR/pack.log"

pass=0
hold=0
control_ok=0
bridge_ok=0
pack_ok=0

say(){ printf '%s\n' "$*"; }
ok(){ pass=$((pass+1)); say "  [PASS] $*"; }
bad(){ hold=$((hold+1)); say "  [HOLD] $*"; }

say "VANTASM LAUNCH — $STAMP"

if [ ! -x "$CORE" ]; then
  bad "Core CLI missing at $CORE"
  say "RESULT: HOLD"
  exit 4
fi

say "1) Control plane"
config="$H/config.json"
restart_needed=0
pid="$(pgrep -f 'surgeon.server' | head -n1 || true)"

if [ -z "$pid" ]; then
  restart_needed=1
elif [ -f "$config" ] && command -v stat >/dev/null 2>&1; then
  cfg_m="$(stat -c %Y "$config" 2>/dev/null || echo 0)"
  proc_start="$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)"
  [ "$cfg_m" -gt "$proc_start" ] && restart_needed=1
fi

if [ "$restart_needed" -eq 1 ]; then
  if [ -x "$H/stop.sh" ]; then
    "$H/stop.sh" >/dev/null 2>&1 || true
  else
    pkill -f 'surgeon.server' >/dev/null 2>&1 || true
  fi
  sleep 1
  if "$CORE" up >$UP_LOG 2>&1; then
    control_ok=1; ok "Surgeon reconciled/restarted"
  else
    bad "Surgeon restart failed"
    cat "$UP_LOG" 2>/dev/null || true
  fi
else
  if curl -fsS --max-time 5 http://127.0.0.1:8765/healthz >/dev/null 2>&1; then
    control_ok=1; ok "Surgeon already healthy"
  elif "$CORE" up >$UP_LOG 2>&1; then
    control_ok=1; ok "Surgeon started"
  else
    bad "Surgeon unavailable"
  fi
fi

say "2) Tunnel + stable bridge"
if [ -x "$BRIDGE" ]; then
  if "$BRIDGE" >$BRIDGE_LOG 2>&1; then
    bridge_ok=1; ok "Tunnel published and stable bridge verified"
  else
    bad "Tunnel/bridge reconciliation failed"
    tail -n 20 "$BRIDGE_LOG" 2>/dev/null || true
  fi
else
  bad "Bridge publisher missing at $BRIDGE"
fi

say "3) Pack activation"
if [ -d "$PACK_ROOT" ] && [ -f "$PACK_ROOT/pack_activation.py" ]; then
  if (cd "$PACK_ROOT" && python pack_activation.py --apply --start) >$PACK_LOG 2>&1; then
    pack_ok=1; ok "pack_activation.py --apply --start completed"
  else
    bad "Pack activation returned non-zero"
  fi
  cat "$PACK_LOG" 2>/dev/null || true
else
  bad "Pack root or pack_activation.py missing: $PACK_ROOT"
fi

say "4) Runtime probes"
if [ "$control_ok" -ne 1 ]; then
  bad "Primary control-plane failure; runtime probes skipped to avoid cascade noise"
else
probe_http(){
  name="$1"; url="$2"
  if curl -fsS --max-time 8 "$url" >/dev/null 2>&1; then ok "$name -> $url"; else bad "$name not answering -> $url"; fi
}

probe_tcp(){
  name="$1"; port="$2"
  if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then ok "$name listening on 127.0.0.1:$port"; else bad "$name not listening on 127.0.0.1:$port"; fi
}

probe_http "Vantasm" "http://127.0.0.1:8765/healthz"

if curl -fsS --max-time 8 http://127.0.0.1:8788/health >/dev/null 2>&1 ||    curl -fsS --max-time 8 http://127.0.0.1:8788/ready >/dev/null 2>&1; then
  ok "LokivelliSpeech answering on 8788"
else
  bad "LokivelliSpeech not answering on 8788"
fi

probe_tcp "T3MP3ST" 3333
probe_tcp "Dragon Ball" 8790

fi

say "5) Watcher"
if pgrep -f 'vantasm.*watch' >/dev/null 2>&1; then
  ok "Watcher already running"
else
  nohup "$CORE" up --watch >"$H/logs/vantasm-watch.log" 2>&1 </dev/null &
  sleep 1
  if pgrep -f 'vantasm.*watch' >/dev/null 2>&1; then ok "Watcher started"; else bad "Watcher did not stay running"; fi
fi

say
say "SUMMARY: PASS=$pass HOLD=$hold"
if [ "$hold" -eq 0 ]; then
  say "RESULT: PASS — Forge converged to live state"
  exit 0
else
  say "RESULT: HOLD — launch completed with $hold unresolved item(s)"
  exit 4
fi
