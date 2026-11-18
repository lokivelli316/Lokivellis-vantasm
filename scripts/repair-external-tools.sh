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
pkg_try clang make cmake pkg-config rust git python openssl libffi libjpeg-turbo libpng freetype ffmpeg unzip || true

# 1) Download Anything — preserve upstream install first, then source-install fallback.
DA_SRC="$SRC/download-anything"
if [ -d "$DA_SRC" ]; then
  rm -rf "$VENVS/download-anything.repair" 2>/dev/null || true
  if python3 "$DA_SRC/skills/download-anything/scripts/install.py"       --yes --venv "$VENVS/download-anything.repair" >"$LOGS/download-anything.log" 2>&1; then
    rm -rf "$VENVS/download-anything"
    mv "$VENVS/download-anything.repair" "$VENVS/download-anything"
  else
    rm -rf "$VENVS/download-anything.repair" 2>/dev/null || true
    python3 -m venv "$VENVS/download-anything.repair" >>"$LOGS/download-anything.log" 2>&1 || true
    if [ -x "$VENVS/download-anything.repair/bin/python" ]; then
      "$VENVS/download-anything.repair/bin/python" -m pip install -U pip setuptools wheel >>"$LOGS/download-anything.log" 2>&1 || true
      "$VENVS/download-anything.repair/bin/python" -m pip install "$DA_SRC" >>"$LOGS/download-anything.log" 2>&1 || true
      if [ -x "$VENVS/download-anything.repair/bin/da" ]; then
        rm -rf "$VENVS/download-anything"
        mv "$VENVS/download-anything.repair" "$VENVS/download-anything"
      fi
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

# 4) NVIDIA SkillEvaluator — system Python 3.14 is allowed upstream; build dependencies locally if wheels are absent.
SE_SRC="$SRC/SkillEvaluator"
SE_VENV="$VENVS/skillevaluator"
rm -rf "$SE_VENV.repair" 2>/dev/null || true
if python3 -m venv "$SE_VENV.repair" >"$LOGS/skillevaluator.log" 2>&1; then
  "$SE_VENV.repair/bin/python" -m pip install -U pip setuptools wheel >>"$LOGS/skillevaluator.log" 2>&1 || true
  "$SE_VENV.repair/bin/python" -m pip install "$SE_SRC" >>"$LOGS/skillevaluator.log" 2>&1 || true
fi
if [ -x "$SE_VENV.repair/bin/skillevaluator" ]; then
  rm -rf "$SE_VENV"
  mv "$SE_VENV.repair" "$SE_VENV"
  ln -sf "$SE_VENV/bin/skillevaluator" "$BIN/skillevaluator"
  say "[PASS] NVIDIA SkillEvaluator base CLI built/installed"
else
  rm -rf "$SE_VENV.repair" 2>/dev/null || true
  say "[HOLD] NVIDIA SkillEvaluator repair failed"
  tail_log "$LOGS/skillevaluator.log"
fi

# 5) Playwright CLI — attempt package resolution only. Browser runtime support is separately verified.
if have npx; then
  if npx -y @playwright/cli@latest --version >"$LOGS/playwright-cli.log" 2>&1; then
    say "[PASS] Playwright CLI package resolves"
  else
    say "[HOLD] Playwright CLI package does not run on this Android environment"
    tail_log "$LOGS/playwright-cli.log"
  fi
fi

say
say "Repair attempt finished. Logs: $LOGS"
say "Next: bash $(cd "$(dirname "$0")" && pwd)/verify-external-tools.sh"
