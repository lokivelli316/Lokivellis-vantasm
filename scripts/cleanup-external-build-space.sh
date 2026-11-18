#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail

ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"

say(){ printf '%s\n' "$*"; }
size(){ du -sh "$1" 2>/dev/null || true; }

say "=== BEFORE ==="
df -h "$HOME" || true

say
say "Rebuildable artifacts selected for cleanup:"
for p in \
  "$HOME/.cache/uv/builds-v0" \
  "$HOME/.cache/uv/sdists-v10" \
  "$HOME/.npm/_npx" \
  "$HOME/.npm/_cacache" \
  "$ROOT/src/lemmeknow/target" \
  "$ROOT/src/rust-anything/target" \
  "$ROOT/venvs/download-anything" \
  "$ROOT/venvs/download-anything.repair" \
  "$ROOT/venvs/skillevaluator" \
  "$ROOT/venvs/skillevaluator.repair"
do
  [ -e "$p" ] && size "$p"
done

# Only rebuildable caches/build trees and failed/incomplete venvs.
rm -rf \
  "$HOME/.cache/uv/builds-v0" \
  "$HOME/.cache/uv/sdists-v10" \
  "$HOME/.npm/_npx" \
  "$HOME/.npm/_cacache" \
  "$ROOT/src/lemmeknow/target" \
  "$ROOT/src/rust-anything/target" \
  "$ROOT/venvs/download-anything" \
  "$ROOT/venvs/download-anything.repair" \
  "$ROOT/venvs/skillevaluator" \
  "$ROOT/venvs/skillevaluator.repair"

# Stale wrappers from failed venvs are rebuildable too.
rm -f "$ROOT/bin/da" "$ROOT/bin/dl" "$ROOT/bin/skillevaluator"

mkdir -p "${PREFIX:-/data/data/com.termux/files/usr}/tmp" "$ROOT/receipts" 2>/dev/null || true

say
say "=== AFTER ==="
df -h "$HOME" || true
say
say "Preserved: source repos, git histories, receipts, Vantasm config/profiles, agent skills, and git stash."
