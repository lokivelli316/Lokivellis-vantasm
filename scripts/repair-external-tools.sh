#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
SRC="$ROOT/src"
VENVS="$ROOT/venvs"
BIN="$ROOT/bin"
CARGO_HOME="$ROOT/cargo"
LOGS="$ROOT/receipts/repair-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$SRC" "$VENVS" "$BIN" "$CARGO_HOME" "$LOGS"
export PATH="$BIN:$ROOT/npm/bin:$CARGO_HOME/bin:$HOME/.local/bin:$PATH"
export CARGO_HOME
export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

say(){ printf '%s\n' "$*"; }
tail_log(){ [ -f "$1" ] && tail -n 20 "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }

clone_or_update(){
  local name="$1" url="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --prune origin >/dev/null 2>&1 || true
    local branch
    branch="$(git -C "$dir" remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')"
    [ -n "$branch" ] && git -C "$dir" merge --ff-only "origin/$branch" >/dev/null 2>&1 || true
    return 0
  fi
  git clone --depth 1 "$url" "$dir"
}

pkg_try(){
  have pkg || return 1
  pkg install -y "$@" >/dev/null 2>&1
}

say "Repair receipts: $LOGS"

# Build prerequisites commonly needed by Android source builds.
pkg_try clang make cmake pkg-config rust rust-std-aarch64-linux-android git python openssl libffi libjpeg-turbo libpng freetype ffmpeg unzip || true

# Termux splits host Rust static standard libraries from rustc. Keep them version-matched.
if have rustc; then
  {
    echo "rustc: $(rustc --version)"
    dpkg-query -W -f='rust: ${Version}\n' rust 2>/dev/null || true
    dpkg-query -W -f='rust-std-aarch64-linux-android: ${Version}\n' rust-std-aarch64-linux-android 2>/dev/null || true
    SYSROOT="$(rustc --print sysroot 2>/dev/null || true)"
    if [ -n "$SYSROOT" ]; then
      echo "host rlibs: $(find "$SYSROOT/lib/rustlib/aarch64-linux-android/lib" -maxdepth 1 -name '*.rlib' 2>/dev/null | wc -l)"
    fi
  } | tee "$LOGS/rust-toolchain.txt"
fi

# 1) Download Anything — rebuild directly at the final venv path so console-script shebangs stay valid.
DA_SRC="$SRC/download-anything"
if [ -d "$DA_SRC" ]; then
  rm -f "$BIN/da" "$BIN/dl" 2>/dev/null || true
  rm -rf "$VENVS/download-anything" "$VENVS/download-anything.repair" 2>/dev/null || true
  if python3 "$DA_SRC/skills/download-anything/scripts/install.py" \
      --yes --venv "$VENVS/download-anything" >"$LOGS/download-anything.log" 2>&1; then
    :
  else
    # Source fallback, still directly into the final path — never move a venv after creation.
    rm -rf "$VENVS/download-anything" 2>/dev/null || true
    python3 -m venv "$VENVS/download-anything" >>"$LOGS/download-anything.log" 2>&1 || true
    if [ -x "$VENVS/download-anything/bin/python" ]; then
      "$VENVS/download-anything/bin/python" -m pip install -U pip setuptools wheel >>"$LOGS/download-anything.log" 2>&1 || true
      "$VENVS/download-anything/bin/python" -m pip install "$DA_SRC" >>"$LOGS/download-anything.log" 2>&1 || true
    fi
  fi
  if [ -x "$VENVS/download-anything/bin/da" ]; then
    ln -sf "$VENVS/download-anything/bin/da" "$BIN/da"
    [ -x "$VENVS/download-anything/bin/dl" ] && ln -sf "$VENVS/download-anything/bin/dl" "$BIN/dl"
    if "$BIN/da" doctor --json >"$LOGS/download-anything-doctor.json" 2>&1; then
      say "[PASS] download-anything repaired"
    else
      say "[HOLD] download-anything CLI exists but doctor still reports failure"
      tail_log "$LOGS/download-anything-doctor.json"
    fi
  else
    say "[HOLD] download-anything repair failed"
    tail_log "$LOGS/download-anything.log"
  fi
fi

# 1b) md-anything — upstream is Bun-targeted; use an inspectable Node/tsx adapter on Android.
MDA_SRC="$SRC/md-anything"
if have npm && have node && [ -f "$MDA_SRC/package.json" ]; then
  if npm install --prefix "$MDA_SRC" --omit=dev >"$LOGS/md-anything-node.log" 2>&1 &&
     npm install -g --prefix "$ROOT/npm" tsx >>"$LOGS/md-anything-node.log" 2>&1; then
    TSX="$ROOT/npm/bin/tsx"
    BOOT="$ROOT/md-anything-node-bootstrap.mjs"
    cat >"$BOOT" <<EOF
globalThis.Bun = globalThis.Bun || { argv: process.argv };
const target = process.env.MDA_NODE_TARGET;
if (!target) throw new Error("MDA_NODE_TARGET missing");
await import(target);
EOF
    cat >"$BIN/mda" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export MDA_NODE_TARGET="$MDA_SRC/src/cli.ts"
exec "$TSX" "$BOOT" "\$@"
EOF
    cat >"$BIN/md-anything-mcp" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export MDA_NODE_TARGET="$MDA_SRC/src/mcp.ts"
exec "$TSX" "$BOOT" "\$@"
EOF
    chmod 755 "$BIN/mda" "$BIN/md-anything-mcp"
    if "$BIN/mda" doctor >"$LOGS/md-anything-doctor.txt" 2>&1; then
      say "[PASS] md-anything Node/tsx Termux adapter works"
    else
      say "[HOLD] md-anything Node/tsx adapter still failed"
      tail_log "$LOGS/md-anything-doctor.txt"
    fi
  else
    say "[HOLD] md-anything Node/tsx adapter dependency install failed"
    tail_log "$LOGS/md-anything-node.log"
  fi
fi

# 2) lemmeknow — build current source on Android instead of relying on a stale locked dependency set.
LEM_SRC="$SRC/lemmeknow"
clone_or_update "lemmeknow" "https://github.com/swanandx/lemmeknow.git" "$LEM_SRC" >"$LOGS/lemmeknow-clone.log" 2>&1 || true
if have cargo && [ -f "$LEM_SRC/Cargo.toml" ]; then
  if cargo install --path "$LEM_SRC" --root "$CARGO_HOME" --force >"$LOGS/lemmeknow.log" 2>&1; then
    ln -sf "$CARGO_HOME/bin/lemmeknow" "$BIN/lemmeknow"
    say "[PASS] lemmeknow built from source"
  else
    say "[HOLD] lemmeknow source build failed"
    tail_log "$LOGS/lemmeknow.log"
  fi
fi

# 3) rust-anything — report the hard Rust-version gate explicitly, then build if possible.
RA_SRC="$SRC/rust-anything"
if have rustc; then
  rustc --version | tee "$LOGS/rustc-version.txt"
fi
if have cargo && [ -f "$RA_SRC/Cargo.toml" ]; then
  if cargo install --path "$RA_SRC" --root "$CARGO_HOME" --force >"$LOGS/rust-anything.log" 2>&1; then
    ln -sf "$CARGO_HOME/bin/rust-anything" "$BIN/rust-anything"
    if "$BIN/rust-anything" setup >"$LOGS/rust-anything-setup.log" 2>&1; then
      say "[PASS] rust-anything built and setup completed"
    else
      say "[HOLD] rust-anything built; setup still failed"
      tail_log "$LOGS/rust-anything-setup.log"
    fi
  else
    say "[HOLD] rust-anything source build failed"
    tail_log "$LOGS/rust-anything.log"
  fi
fi

# 4) NVIDIA SkillEvaluator — prefer normal dependency install after Rust std repair.
# If PyPI's uv package still has no Android wheel, install the remaining declared base deps and
# use the already-working native uv executable on PATH; upstream resolves PATH uv before importing Python uv.
SE_SRC="$SRC/SkillEvaluator"
SE_VENV="$VENVS/skillevaluator"
rm -rf "$SE_VENV" "$SE_VENV.repair" 2>/dev/null || true
python3 -m venv "$SE_VENV" >"$LOGS/skillevaluator.log" 2>&1 || true
if [ -x "$SE_VENV/bin/python" ]; then
  "$SE_VENV/bin/python" -m pip install -U pip setuptools wheel >>"$LOGS/skillevaluator.log" 2>&1 || true
  if ! "$SE_VENV/bin/python" -m pip install "$SE_SRC" >>"$LOGS/skillevaluator.log" 2>&1; then
    "$SE_VENV/bin/python" -m pip install \
      'bandit>=1.9.4' 'click>=8.3.3,<9' 'idna>=3.10,<4' 'jinja2>=3.1' \
      'markdown-it-py>=4.2,<5' 'packaging>=24' 'pydantic>=2.11.0' 'pyyaml>=6.0' \
      'regex>=2024.11.6' 'rich>=13.5.0' >>"$LOGS/skillevaluator.log" 2>&1 || true
    "$SE_VENV/bin/python" -m pip install --no-deps "$SE_SRC" >>"$LOGS/skillevaluator.log" 2>&1 || true
  fi
fi
if [ -x "$SE_VENV/bin/skillevaluator" ]; then
  ln -sf "$SE_VENV/bin/skillevaluator" "$BIN/skillevaluator"
  if "$BIN/skillevaluator" --version >"$LOGS/skillevaluator-version.txt" 2>&1; then
    say "[PASS] NVIDIA SkillEvaluator base CLI installed"
  else
    say "[HOLD] NVIDIA SkillEvaluator console script exists but does not start"
    tail_log "$LOGS/skillevaluator-version.txt"
  fi
else
  say "[HOLD] NVIDIA SkillEvaluator repair failed"
  tail_log "$LOGS/skillevaluator.log"
fi

# 5) Playwright CLI — attempt package resolution only. Browser runtime support is separately verified.
if have npx; then
  if PLAYWRIGHT_BROWSERS_PATH=0 npx -y @playwright/cli@latest --version >"$LOGS/playwright-cli.log" 2>&1; then
    say "[PASS] Playwright CLI package resolves"
  else
    say "[HOLD] Playwright CLI package does not run on this Android environment"
    tail_log "$LOGS/playwright-cli.log"
  fi
fi

say
say "Repair attempt finished. Logs: $LOGS"
say "Next: bash $(cd "$(dirname "$0")" && pwd)/verify-external-tools.sh"
