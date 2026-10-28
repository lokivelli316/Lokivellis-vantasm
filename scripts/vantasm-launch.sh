#!/data/data/com.termux/files/usr/bin/bash
set -u

H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
CORE="${VANTASM_CORE_BIN:-$H/vantasm-core}"
BRIDGE="${VANTASM_BRIDGE_BIN:-$H/vantasm-bridge-up}"
PACK_ROOT="${VANTASM_PACK_ROOT:-$HOME/nemotron-v0451-live}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CANONICAL_SURGEON_PORT=8765
export FORGE_SURGEON_PORT="$CANONICAL_SURGEON_PORT"
SURGEON_PORT="$CANONICAL_SURGEON_PORT"
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
  if "$CORE" up >"$UP_LOG" 2>&1; then
    control_ok=1; ok "Surgeon reconciled/restarted"
  else
    bad "Surgeon restart failed"
    cat "$UP_LOG" 2>/dev/null || true
  fi
else
  if curl -fsS --max-time 5 http://127.0.0.1:$SURGEON_PORT/healthz >/dev/null 2>&1; then
    control_ok=1; ok "Surgeon already healthy"
  elif "$CORE" up >"$UP_LOG" 2>&1; then
    control_ok=1; ok "Surgeon started"
  else
    bad "Surgeon unavailable"
  fi
fi

say "2) Tunnel + stable bridge"
if [ -x "$BRIDGE" ]; then
  if "$BRIDGE" >"$BRIDGE_LOG" 2>&1; then
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
  if (cd "$PACK_ROOT" && python pack_activation.py --apply --start) >"$PACK_LOG" 2>&1; then
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
  name="$1"; url="$2"; tries="${3:-5}"
  i=1
  while [ "$i" -le "$tries" ]; do
    if curl -fsS --max-time 8 "$url" >/dev/null 2>&1; then
      ok "$name -> $url"
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  bad "$name not answering after $tries probes -> $url"
  return 1
}

probe_tcp(){
  name="$1"; port="$2"
  if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then ok "$name listening on 127.0.0.1:$port"; else bad "$name not listening on 127.0.0.1:$port"; fi
}

probe_http "Vantasm" "http://127.0.0.1:$SURGEON_PORT/healthz"

if curl -fsS --max-time 8 http://127.0.0.1:8788/health >/dev/null 2>&1 ||    curl -fsS --max-time 8 http://127.0.0.1:8788/ready >/dev/null 2>&1; then
  ok "LokivelliSpeech answering on 8788"
else
  bad "LokivelliSpeech not answering on 8788"
fi

probe_tcp "T3MP3ST" 3333
probe_tcp "Dragon Ball" 8790

fi

say "5) Generator + live Speech smoke"

GEN_PORT=8795
gen_up=0
if (echo >/dev/tcp/127.0.0.1/"$GEN_PORT") >/dev/null 2>&1; then
  gen_up=1
else
  if [ -d "$PACK_ROOT" ]; then
    if [ -x "$PACK_ROOT/start.sh" ]; then
      (cd "$PACK_ROOT" && nohup ./start.sh >"$RUN_DIR/generator.log" 2>&1 </dev/null &) || true
    elif [ -x "$PACK_ROOT/GO.sh" ]; then
      (cd "$PACK_ROOT" && nohup ./GO.sh >"$RUN_DIR/generator.log" 2>&1 </dev/null &) || true
    fi
    i=1
    while [ "$i" -le 8 ]; do
      if (echo >/dev/tcp/127.0.0.1/"$GEN_PORT") >/dev/null 2>&1; then gen_up=1; break; fi
      sleep 1
      i=$((i+1))
    done
  fi
fi
if [ "$gen_up" -eq 1 ]; then ok "Generator listening on 127.0.0.1:$GEN_PORT"; else bad "Generator not listening on 127.0.0.1:$GEN_PORT"; fi

SPEECH_ROOT="${VANTASM_SPEECH_ROOT:-$HOME/forge-pack/Lokivellispeech}"
speech_smoke_ok=0

if [ -d "$SPEECH_ROOT" ]; then
  if (cd "$SPEECH_ROOT" && python3 -m lokivellispeech smoke --base http://127.0.0.1:8788/) >"$RUN_DIR/speech-smoke.log" 2>&1; then
    cat "$RUN_DIR/speech-smoke.log" 2>/dev/null || true
    speech_smoke_ok=1
    ok "LokivelliSpeech canonical smoke test passed"
  else
    say "         canonical smoke failed:"
    sed "s/^/         /" "$RUN_DIR/speech-smoke.log" 2>/dev/null | tail -n 20
  fi
fi

if [ "$speech_smoke_ok" -ne 1 ]; then
  speech_wav="$RUN_DIR/speech-smoke.wav"
  speech_hdr="$RUN_DIR/speech-smoke.headers"
  speech_err="$RUN_DIR/speech-smoke.error"
  rm -f "$speech_wav" "$speech_hdr" "$speech_err"

  http_code="$(curl -sS --max-time 45 \
    -D "$speech_hdr" \
    -o "$speech_wav" \
    -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d '{"model":"kokoro","voice":"af_heart","input":"Vantasm live speech smoke test."}' \
    http://127.0.0.1:8788/v1/audio/speech \
    2>"$speech_err" || true)"

  if [ "$http_code" = "200" ] && python - "$speech_wav" <<'PY'
import sys, wave, math, struct
p=sys.argv[1]
with wave.open(p,'rb') as w:
    n=w.getnframes()
    sw=w.getsampwidth()
    ch=w.getnchannels()
    rate=w.getframerate()
    data=w.readframes(n)
if n <= 0 or sw != 2:
    raise SystemExit(1)
vals=struct.unpack("<%dh"%(len(data)//2),data)
rms=math.sqrt(sum(v*v for v in vals)/max(1,len(vals)))
dur=n/float(rate)
if rms <= 1 or dur <= 0.05:
    raise SystemExit(1)
print(f"speech smoke: {dur:.2f}s {rate}Hz ch={ch} rms={rms:.1f}")
PY
  then
    speech_smoke_ok=1
    ok "Live /v1/audio/speech synthesis produced non-silent WAV"
  else
    say "         speech smoke fallback HTTP=$http_code"
    [ -s "$speech_err" ] && sed 's/^/         /' "$speech_err" | head -n 5
    if [ -s "$speech_wav" ]; then
      say "         response body:"
      head -c 800 "$speech_wav" 2>/dev/null | sed 's/^/         /'
      say ""
    fi
  fi
fi

if [ "$speech_smoke_ok" -ne 1 ]; then
  if grep -q "No module named 'phonemizer'" "$RUN_DIR/speech-smoke.log" 2>/dev/null || \
     grep -q "No module named 'phonemizer'" "$speech_wav" 2>/dev/null; then
    say "         detected incomplete Kokoro worker environment; reconciling local worker venv"
    if [ -f "$SPEECH_ROOT/scripts/install-worker.sh" ]; then
      (cd "$SPEECH_ROOT" && python3 -m lokivellispeech workers stop kokoro >/dev/null 2>&1 || true)
      if (cd "$SPEECH_ROOT" && bash scripts/install-worker.sh kokoro) >"$RUN_DIR/speech-repair.log" 2>&1; then
        (cd "$SPEECH_ROOT" && python3 -m lokivellispeech workers start kokoro) >>"$RUN_DIR/speech-repair.log" 2>&1 || true
        sleep 2
        if (cd "$SPEECH_ROOT" && python3 -m lokivellispeech smoke --base http://127.0.0.1:8788/) >"$RUN_DIR/speech-smoke-retry.log" 2>&1; then
          cat "$RUN_DIR/speech-smoke-retry.log" 2>/dev/null || true
          speech_smoke_ok=1
          ok "Kokoro worker environment repaired and live Speech smoke passed"
        else
          say "         repair completed but smoke retry still failed:"
          sed "s/^/         /" "$RUN_DIR/speech-smoke-retry.log" 2>/dev/null | tail -n 20
        fi
      else
        say "         worker installer failed:"
        sed "s/^/         /" "$RUN_DIR/speech-repair.log" 2>/dev/null | tail -n 30

        VENV="$HOME/.local/share/lokivellispeech/workers/kokoro/.venv"
        if [ -x "$VENV/bin/pip" ] && [ -x "$VENV/bin/python" ]; then
          say "         attempting bounded phonemizer-fork repair"
          "$VENV/bin/pip" install --force-reinstall --no-deps phonemizer-fork==3.3.1 \
            >"$RUN_DIR/phonemizer-repair.log" 2>&1 || true

          if (cd "$SPEECH_ROOT/workers/kokoro" && \
              "$VENV/bin/python" -c "import worker; worker.termux_compat(); import phonemizer, kokoro_onnx, colorlog; print('PASS phonemizer import')" ) \
              >>"$RUN_DIR/phonemizer-repair.log" 2>&1; then
            (cd "$SPEECH_ROOT" && python3 -m lokivellispeech workers stop kokoro >/dev/null 2>&1 || true)
            (cd "$SPEECH_ROOT" && python3 -m lokivellispeech workers start kokoro) \
              >>"$RUN_DIR/phonemizer-repair.log" 2>&1 || true
            sleep 2
            if (cd "$SPEECH_ROOT" && python3 -m lokivellispeech smoke --base http://127.0.0.1:8788/) \
                >"$RUN_DIR/speech-smoke-retry.log" 2>&1; then
              cat "$RUN_DIR/speech-smoke-retry.log" 2>/dev/null || true
              speech_smoke_ok=1
              ok "phonemizer-fork restored; Kokoro restarted; live Speech smoke passed"
            else
              say "         phonemizer repaired but smoke retry still failed:"
              sed "s/^/         /" "$RUN_DIR/speech-smoke-retry.log" 2>/dev/null | tail -n 20
            fi
          else
            say "         phonemizer-fork repair verification failed:"
            sed "s/^/         /" "$RUN_DIR/phonemizer-repair.log" 2>/dev/null | tail -n 30
          fi
        fi
      fi
    else
      say "         worker installer missing: $SPEECH_ROOT/scripts/install-worker.sh"
    fi
  fi
fi

if [ "$speech_smoke_ok" -ne 1 ]; then
  bad "Speech live smoke failed; service health remains independently READY"
fi

say "6) Watcher"
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
