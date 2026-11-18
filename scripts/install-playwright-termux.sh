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

MIN_FREE_KB="${LOKIVELLI_MIN_EXTERNAL_FREE_KB:-4194304}"
FREE_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
  say "[HOLD] Chromium installed, but less than 4 GiB remains; refusing npm/browser setup"
  exit 4
fi

rm -rf "$PW_ROOT" 2>/dev/null || true
mkdir -p "$PW_ROOT"

CLI_VERSION="$(npm view @playwright/cli version --no-update-notifier 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
[ -n "$CLI_VERSION" ] || CLI_VERSION="0.1.25"

cat >"$PW_ROOT/package.json" <<EOF
{
  "name": "lokivelli-playwright-termux-adapter",
  "private": true,
  "dependencies": {
    "@playwright/cli": "$CLI_VERSION"
  }
}
EOF

if ! PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 NO_UPDATE_NOTIFIER=1 npm install --prefix "$PW_ROOT" --omit=dev >"$LOG_DIR/npm-install.log" 2>&1; then
  say "[HOLD] @playwright/cli npm install failed"
  tail_log "$LOG_DIR/npm-install.log"
  exit 4
fi

CLI_INSTALLED="$(node -p "require('$PW_ROOT/node_modules/@playwright/cli/package.json').version" 2>/dev/null || true)"
CORE_INSTALLED="$(node -p "require('$PW_ROOT/node_modules/playwright-core/package.json').version" 2>/dev/null || true)"
PLAYWRIGHT_INSTALLED="$(node -p "require('$PW_ROOT/node_modules/playwright/package.json').version" 2>/dev/null || true)"
{
  echo "@playwright/cli=$CLI_INSTALLED"
  echo "playwright=$PLAYWRIGHT_INSTALLED"
  echo "playwright-core=$CORE_INSTALLED"
} >"$LOG_DIR/versions.txt"

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

PW_PLATFORM_SHIM="$ROOT/playwright-termux-platform-shim.cjs"
cat >"$PW_PLATFORM_SHIM" <<'EOF'
const descriptor = Object.getOwnPropertyDescriptor(process, 'platform');
if (!descriptor || descriptor.configurable !== false) {
  Object.defineProperty(process, 'platform', {
    value: 'linux',
    enumerable: descriptor ? descriptor.enumerable : true,
    configurable: true
  });
}
EOF

cat >"$BIN/playwright-cli" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export PLAYWRIGHT_BROWSERS_PATH=0
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export NO_UPDATE_NOTIFIER=1
export NODE_OPTIONS="--require $PW_PLATFORM_SHIM ${NODE_OPTIONS:-}"

PW_CONFIG="$PW_CONFIG"
PW_ENTRY="$PW_ENTRY"

args=("$@")
has_config=0
is_open=0
for arg in "${args[@]}"; do
  case "$arg" in
    --config|--config=*) has_config=1 ;;
    open) is_open=1 ;;
  esac
done

if [ "$is_open" -eq 1 ] && [ "$has_config" -eq 0 ]; then
  args+=("--config=$PW_CONFIG")
fi

exec node "$PW_ENTRY" "${args[@]}"
EOF
chmod 755 "$BIN/playwright-cli"

if smoke; then
  say "[PASS] Playwright CLI Termux adapter: exact CLI dependencies + platform shim + native Chromium smoke passed"
  cat "$LOG_DIR/versions.txt"
  exit 0
fi

"$BIN/playwright-cli" -s=vantasm-smoke close >/dev/null 2>&1 || true
say "[HOLD] Playwright CLI platform-shim adapter installed but native Chromium smoke failed"
cat "$LOG_DIR/versions.txt" 2>/dev/null || true
tail_log "$LOG_DIR/version.log"
tail_log "$LOG_DIR/open.log"
tail_log "$LOG_DIR/snapshot.log"
exit 4
