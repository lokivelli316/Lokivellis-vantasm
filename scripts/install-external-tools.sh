#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
SRC="$ROOT/src"
VENVS="$ROOT/venvs"
NPM_ROOT="$ROOT/npm"
CARGO_HOME="$ROOT/cargo"
BIN="$ROOT/bin"
RECEIPTS="$ROOT/receipts"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RECEIPT="$RECEIPTS/install-$STAMP.tsv"
mkdir -p "$SRC" "$VENVS" "$NPM_ROOT" "$CARGO_HOME" "$BIN" "$RECEIPTS"
chmod 700 "$ROOT" "$RECEIPTS" 2>/dev/null || true

export PATH="$BIN:$NPM_ROOT/bin:$CARGO_HOME/bin:$HOME/.local/bin:$PATH"
export CARGO_HOME
export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

MIN_FREE_KB="${LOKIVELLI_MIN_EXTERNAL_FREE_KB:-2097152}"
FREE_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
  printf 'HOLD: insufficient free space for external-tool install: %s KiB free; require at least %s KiB.\n' "$FREE_KB" "$MIN_FREE_KB"
  printf 'Run: bash %s/cleanup-external-build-space.sh\n' "$(cd "$(dirname "$0")" && pwd)"
  exit 4
fi

printf 'timestamp_utc\ttool\tstatus\tdetail\n' > "$RECEIPT"

say() { printf '%s\n' "$*"; }
record() {
  local tool="$1" status="$2" detail="$3"
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool" "$status" "$detail" >> "$RECEIPT"
  say "[$status] $tool — $detail"
}
have() { command -v "$1" >/dev/null 2>&1; }

clone_or_update() {
  local tool="$1" url="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    if git -C "$dir" fetch --prune origin && git -C "$dir" merge --ff-only "origin/$(git -C "$dir" remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')" >/dev/null 2>&1; then
      record "$tool" PASS "source updated: $(git -C "$dir" rev-parse HEAD)"
      return 0
    fi
    record "$tool" HOLD "existing checkout preserved; fast-forward update failed"
    return 1
  fi
  if git clone --depth 1 "$url" "$dir"; then
    record "$tool" PASS "source cloned: $(git -C "$dir" rev-parse HEAD)"
    return 0
  fi
  record "$tool" HOLD "git clone failed"
  return 1
}

pkg_install() {
  if ! have pkg; then return 1; fi
  pkg install -y "$@" >/dev/null 2>&1
}

# Base tools. Install only missing dependencies; do not run a blanket pkg upgrade.
for p in git curl python nodejs rust clang make pkg-config ffmpeg unzip poppler tesseract; do
  if ! have "$p"; then
    pkg_install "$p" || true
  fi
done

# Termux packages Rust host static std libraries separately; cargo build scripts/proc-macros need them.
pkg_install rust-std-aarch64-linux-android || true
pkg_install python-cryptography maturin || true

# uv — prefer a Termux-native package. Do not pull a glibc standalone binary onto Android.
if have uv; then
  record "uv" PASS "$(uv --version 2>&1 | head -n1)"
elif pkg_install uv && have uv; then
  record "uv" PASS "$(uv --version 2>&1 | head -n1)"
else
  record "uv" HOLD "no Termux-native uv found; standalone Linux binaries are not assumed Android/Bionic compatible"
fi

# md-anything — isolated npm prefix, with both CLI and MCP binaries.
if have npm; then
  if npm install -g --prefix "$NPM_ROOT" md-anything@latest >/dev/null 2>&1 && [ -x "$NPM_ROOT/bin/mda" ]; then
    ln -sf "$NPM_ROOT/bin/mda" "$BIN/mda"
    [ -x "$NPM_ROOT/bin/md-anything-mcp" ] && ln -sf "$NPM_ROOT/bin/md-anything-mcp" "$BIN/md-anything-mcp"
    record "md-anything" PASS "$($BIN/mda --version 2>/dev/null || $BIN/mda --help 2>/dev/null | head -n1)"
    "$BIN/mda" doctor >/dev/null 2>&1 || record "md-anything" HOLD "installed; doctor reports optional capability gaps"
  else
    record "md-anything" HOLD "npm install failed"
  fi
else
  record "md-anything" HOLD "npm unavailable"
fi

# download-anything — Termux-native cryptography + final-path system-site venv.
DA_SRC="$SRC/download-anything"
if clone_or_update "download-anything-source" "https://github.com/nengong/download-anything.git" "$DA_SRC"; then
  rm -rf "$VENVS/download-anything" 2>/dev/null || true
  if python3 -m venv --system-site-packages "$VENVS/download-anything" >/dev/null 2>&1 &&
     "$VENVS/download-anything/bin/python" -m pip install -U pip setuptools wheel >/dev/null 2>&1 &&
     "$VENVS/download-anything/bin/python" -m pip install --no-build-isolation "$DA_SRC" >/dev/null 2>&1; then
    [ -x "$VENVS/download-anything/bin/da" ] && ln -sf "$VENVS/download-anything/bin/da" "$BIN/da"
    [ -x "$VENVS/download-anything/bin/dl" ] && ln -sf "$VENVS/download-anything/bin/dl" "$BIN/dl"
    if "$VENVS/download-anything/bin/da" doctor --json > "$RECEIPTS/download-anything-doctor-$STAMP.json" 2>/dev/null; then
      record "download-anything" PASS "CLI installed with Termux-native cryptography; doctor receipt written"
    else
      record "download-anything" HOLD "CLI installed but doctor did not return a clean result"
    fi
  else
    record "download-anything" HOLD "Termux-native venv/source install failed"
  fi
fi

# lemmeknow — Rust CLI.
if have cargo; then
  if cargo install lemmeknow --locked >/dev/null 2>&1 || cargo install lemmeknow >/dev/null 2>&1; then
    [ -x "$CARGO_HOME/bin/lemmeknow" ] && ln -sf "$CARGO_HOME/bin/lemmeknow" "$BIN/lemmeknow"
    record "lemmeknow" PASS "$($BIN/lemmeknow --version 2>&1 | head -n1)"
  else
    record "lemmeknow" HOLD "cargo install failed on this Android/Termux environment"
  fi
else
  record "lemmeknow" HOLD "cargo unavailable"
fi

# CLI-Anything consumer hub + agent meta-skill.
CLI_VENV="$VENVS/cli-anything-hub"
if python3 -m venv "$CLI_VENV" >/dev/null 2>&1 &&
   "$CLI_VENV/bin/python" -m pip install -U pip cli-anything-hub >/dev/null 2>&1; then
  for x in "$CLI_VENV"/bin/cli-*; do [ -x "$x" ] && ln -sf "$x" "$BIN/$(basename "$x")"; done
  record "CLI-Anything-hub" PASS "cli-anything-hub installed in isolated venv"
else
  record "CLI-Anything-hub" HOLD "Python hub install failed"
fi
if have npx; then
  if npx -y skills add HKUDS/CLI-Anything --skill cli-hub-meta-skill -g -y >/dev/null 2>&1; then
    record "CLI-Anything-skill" PASS "global cli-hub meta-skill installed"
  else
    record "CLI-Anything-skill" HOLD "npx skills installation failed"
  fi
else
  record "CLI-Anything-skill" HOLD "npx unavailable"
fi
clone_or_update "CLI-Anything-source" "https://github.com/HKUDS/CLI-Anything.git" "$SRC/CLI-Anything" || true

# CLI-Anything-WEB has no single universal runtime package; preserve full source and Playwright CLI entrypoint.
clone_or_update "CLI-Anything-WEB-source" "https://github.com/ItamarZand88/CLI-Anything-WEB.git" "$SRC/CLI-Anything-WEB" || true
if have npx && npx -y @playwright/cli@latest --version >/dev/null 2>&1; then
  record "CLI-Anything-WEB-playwright" PASS "Playwright CLI entrypoint available through npx"
else
  record "CLI-Anything-WEB-playwright" HOLD "Playwright CLI unavailable; web harness generation not runtime-ready"
fi

# rust-anything — install binary then run its own config-preserving setup.
if have cargo; then
  if cargo install rust-anything >/dev/null 2>&1; then
    [ -x "$CARGO_HOME/bin/rust-anything" ] && ln -sf "$CARGO_HOME/bin/rust-anything" "$BIN/rust-anything"
    record "rust-anything" PASS "$($BIN/rust-anything --version 2>&1 | head -n1)"
    if "$BIN/rust-anything" setup >/dev/null 2>&1; then
      record "rust-anything-setup" PASS "agent MCP/skill setup completed using upstream backup behavior"
    else
      record "rust-anything-setup" HOLD "binary installed; agent setup failed or no supported agent config was found"
    fi
  else
    record "rust-anything" HOLD "cargo install failed on this Android/Termux environment"
  fi
else
  record "rust-anything" HOLD "cargo unavailable"
fi

# OpenClaude — current upstream requires Node >=24.22.1.
if have node && have npm; then
  NODE_VER="$(node -p 'process.versions.node' 2>/dev/null || echo 0.0.0)"
  if node -e 'const [a,b,c]=process.versions.node.split(".").map(Number);process.exit(a>24||(a===24&&(b>22||(b===22&&c>=1)))?0:1)'; then
    if npm install -g --prefix "$NPM_ROOT" @twigpine/openclaude@latest >/dev/null 2>&1; then
      [ -x "$NPM_ROOT/bin/openclaude" ] && ln -sf "$NPM_ROOT/bin/openclaude" "$BIN/openclaude"
      record "OpenClaude" PASS "$($BIN/openclaude --version 2>&1 | head -n1)"
    else
      record "OpenClaude" HOLD "npm installation failed"
    fi
  else
    record "OpenClaude" HOLD "Node $NODE_VER is below upstream minimum 24.22.1; existing Node was not silently replaced"
  fi
else
  record "OpenClaude" HOLD "node/npm unavailable"
fi

# NVIDIA SkillEvaluator base install. Full Tier 3 remains separately gated by Docker/provider access.
PY_MM="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo 0.0)"
if python3 -c 'import sys; raise SystemExit(0 if (3,12) <= sys.version_info[:2] <= (3,14) else 1)' 2>/dev/null; then
  SE_VENV="$VENVS/skillevaluator"
  if python3 -m venv "$SE_VENV" >/dev/null 2>&1 &&
     "$SE_VENV/bin/python" -m pip install -U pip skillevaluator >/dev/null 2>&1; then
    [ -x "$SE_VENV/bin/skillevaluator" ] && ln -sf "$SE_VENV/bin/skillevaluator" "$BIN/skillevaluator"
    record "NVIDIA-SkillEvaluator" PASS "$($BIN/skillevaluator --version 2>&1 | head -n1)"
  else
    record "NVIDIA-SkillEvaluator" HOLD "base package failed to install under Python $PY_MM"
  fi
else
  record "NVIDIA-SkillEvaluator" HOLD "Python $PY_MM outside supported 3.12-3.14 range"
fi

# Agent skill/reference collections.
if have npx; then
  if npx -y skills add google-labs-code/stitch-skills -g -y >/dev/null 2>&1; then
    record "stitch-skills" PASS "global Stitch skill collection installed"
  else
    record "stitch-skills" HOLD "npx skills install failed"
  fi
  if npx -y skills add appwrite/agent-skills -g -y >/dev/null 2>&1; then
    record "Appwrite-agent-skills" PASS "agent skills installed"
  else
    record "Appwrite-agent-skills" HOLD "agent skill install failed"
  fi
else
  record "stitch-skills" HOLD "npx unavailable"
  record "Appwrite-agent-skills" HOLD "npx unavailable"
fi

# Claude-BugHunter: install its skill bundle only; no target actions are executed.
CBH_SRC="$SRC/Claude-BugHunter"
if clone_or_update "Claude-BugHunter-source" "https://github.com/elementalsouls/Claude-BugHunter.git" "$CBH_SRC"; then
  if bash "$CBH_SRC/scripts/install.sh" --all --no-shell >/dev/null 2>&1; then
    record "Claude-BugHunter" PASS "skill bundle installed into detected supported agent harnesses"
  else
    record "Claude-BugHunter" HOLD "source present; multi-harness installer failed"
  fi
fi

# Source/reference collections — useful locally, but not falsely promoted to executable runtimes.
clone_or_update "harness-anything-source" "https://github.com/yb2460/harness-anything.git" "$SRC/harness-anything" || true
record "harness-anything" HOLD "source installed; many harnesses require desktop apps/Windows COM and have no universal Termux runtime"

clone_or_update "awesome-mcp-servers" "https://github.com/punkpeye/awesome-mcp-servers.git" "$SRC/awesome-mcp-servers" || true
record "awesome-mcp-servers-runtime" HOLD "catalog source installed; catalog itself is not an MCP server"

clone_or_update "cursor-plugins" "https://github.com/cursor/plugins.git" "$SRC/cursor-plugins" || true
record "cursor-plugins-runtime" HOLD "catalog/source installed; Cursor desktop runtime is not provided by this Termux installer"

clone_or_update "jquery-source" "https://github.com/jquery/jquery.git" "$SRC/jquery" || true
record "jquery-runtime" HOLD "source installed only; jQuery belongs in individual web projects, not a global Termux runtime"

clone_or_update "Appwrite-source" "https://github.com/appwrite/appwrite.git" "$SRC/appwrite" || true
if have docker; then
  record "Appwrite-server" HOLD "Docker command exists, but server installation is intentionally not launched without validating a working Docker daemon and persistent volumes"
else
  record "Appwrite-server" HOLD "self-hosted Appwrite requires Docker; no Docker daemon is available in ordinary Termux"
fi

# stitch-skills source is also retained for inspectable provenance.
clone_or_update "stitch-skills-source" "https://github.com/google-labs-code/stitch-skills.git" "$SRC/stitch-skills" || true
clone_or_update "md-anything-source" "https://github.com/ojspace/md-anything.git" "$SRC/md-anything" || true
clone_or_update "openclaude-source" "https://github.com/Twigpine/openclaude.git" "$SRC/openclaude" || true
clone_or_update "SkillEvaluator-source" "https://github.com/NVIDIA/SkillEvaluator.git" "$SRC/SkillEvaluator" || true
clone_or_update "rust-anything-source" "https://github.com/erkamyaman/rust-anything.git" "$SRC/rust-anything" || true
clone_or_update "uv-source" "https://github.com/astral-sh/uv.git" "$SRC/uv" || true

record "installer" PASS "receipt: $RECEIPT"
say
say "External tool receipt: $RECEIPT"
say "Run: bash $(cd "$(dirname "$0")" && pwd)/verify-external-tools.sh"
