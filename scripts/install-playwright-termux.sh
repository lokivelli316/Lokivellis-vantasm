#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
BIN="$ROOT/bin"
PW_ROOT="$ROOT/playwright-cli"
PW_CONFIG="$ROOT/playwright-cli.config.json"
LOG_DIR="${1:-$ROOT/receipts/playwright-termux-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$BIN" "$LOG_DIR"

export PATH="$BIN:$ROOT/npm/bin:$ROOT/cargo/bin:$HOME/.local/bin:$PATH"
export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

say(){ printf '%s\n' "$*"; }
tail_log(){ [ -f "$1" ] && tail -n 30 "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
pkg_try(){
  have pkg || return 1
  pkg install -y "$@" >>"$LOG_DIR/pkg.log" 2>&1
}

smoke(){
  "$BIN/playwright-cli" --version >"$LOG_DIR/version.log" 2>&1 || return 1
  timeout 90 "$BIN/playwright-cli" -s=vantasm-smoke open about:blank >"$LOG_DIR/open.log" 2>&1 || return 1
  timeout 60 "$BIN/playwright-cli" -s=vantasm-smoke snapshot >"$LOG_DIR/snapshot.log" 2>&1 || {
    "$BIN/playwright-cli" -s=vantasm-smoke close >/dev/null 2>&1 || true
    return 1
  }
  "$BIN/playwright-cli" -s=vantasm-smoke close >"$LOG_DIR/close.log" 2>&1 || true
  return 0
}

if [ -x "$BIN/playwright-cli" ] && smoke; then
  say "[PASS] Playwright CLI Termux adapter already healthy"
  exit 0
fi
[ -x "$BIN/playwright-cli" ] && "$BIN/playwright-cli" -s=vantasm-smoke close >/dev/null 2>&1 || true

if ! have chromium-browser; then
  say "Installing Termux X11 Chromium substrate..."
  pkg_try x11-repo || true
  pkg_try chromium || true
fi

CHROMIUM="$(command -v chromium-browser 2>/dev/null || true)"
if [ -z "$CHROMIUM" ]; then
  say "[HOLD] Termux chromium-browser is unavailable"
  tail_log "$LOG_DIR/pkg.log"
  exit 4
fi

rm -rf "$PW_ROOT" 2>/dev/null || true
mkdir -p "$PW_ROOT"

if ! PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --prefix "$PW_ROOT" @playwright/cli@latest >"$LOG_DIR/npm-install.log" 2>&1; then
  say "[HOLD] @playwright/cli npm install failed"
  tail_log "$LOG_DIR/npm-install.log"
  exit 4
fi

CORE_BUNDLE="$PW_ROOT/node_modules/playwright-core/lib/coreBundle.js"
if [ -f "$CORE_BUNDLE" ]; then
  if ! python3 - "$CORE_BUNDLE" >"$LOG_DIR/cache-adapter.log" 2>&1 <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
start = s.find("function computeDefaultCacheDirectory()")
if start < 0:
    raise SystemExit("computeDefaultCacheDirectory() not found")
end = s.find("function defaultCacheDirectory()", start)
if end < 0:
    raise SystemExit("defaultCacheDirectory() boundary not found")
chunk = s[start:end]
if 'process.platform === "android"' not in chunk:
    old = 'process.platform === "linux"'
    if old not in chunk:
        raise SystemExit("linux cache-directory condition not found")
    chunk = chunk.replace(old, '(process.platform === "linux" || process.platform === "android")', 1)
    s = s[:start] + chunk + s[end:]
    p.write_text(s)
print("Termux cache-directory adapter applied")
PY
  then
    say "[HOLD] Playwright core cache-path adapter failed"
    tail_log "$LOG_DIR/cache-adapter.log"
    exit 4
  fi
fi

cat >"$PW_CONFIG" <<EOF
{
  "browser": {
    "browserName": "chromium",
    "isolated": true,
    "launchOptions": {
      "executablePath": "$CHROMIUM",
      "headless": true,
      "chromiumSandbox": false,
      "args": ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
    }
  }
}
EOF

PW_ENTRY="$PW_ROOT/node_modules/@playwright/cli/playwright-cli.js"
if [ ! -f "$PW_ENTRY" ]; then
  say "[HOLD] @playwright/cli entrypoint missing after npm install"
  exit 4
fi

cat >"$BIN/playwright-cli" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export PLAYWRIGHT_BROWSERS_PATH=0
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export PLAYWRIGHT_MCP_EXECUTABLE_PATH="$CHROMIUM"
export PLAYWRIGHT_MCP_CONFIG="$PW_CONFIG"
exec node "$PW_ENTRY" "\$@"
EOF
chmod 755 "$BIN/playwright-cli"

if smoke; then
  say "[PASS] Playwright CLI Termux adapter launched native Chromium and captured a snapshot"
  exit 0
fi

"$BIN/playwright-cli" -s=vantasm-smoke close >/dev/null 2>&1 || true
say "[HOLD] Playwright CLI adapter installed but native Chromium smoke failed"
tail_log "$LOG_DIR/version.log"
tail_log "$LOG_DIR/open.log"
tail_log "$LOG_DIR/snapshot.log"
exit 4
