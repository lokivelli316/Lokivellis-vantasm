#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail
ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
export PATH="$ROOT/bin:$ROOT/npm/bin:$ROOT/cargo/bin:$HOME/.local/bin:$PATH"
export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

pass=0
hold=0
check() {
  local name="$1"; shift
  local tmp
  tmp="$(mktemp "$TMPDIR/vantasm-ext-check.XXXXXX" 2>/dev/null || mktemp "$HOME/.vantasm-ext-check.XXXXXX")" || {
    printf 'HOLD  %-28s cannot allocate writable temp file\n' "$name"
    hold=$((hold+1))
    return
  }
  if "$@" >"$tmp" 2>&1; then
    printf 'PASS  %-28s %s\n' "$name" "$(head -n1 "$tmp")"
    pass=$((pass+1))
  else
    printf 'HOLD  %-28s %s\n' "$name" "$(head -n1 "$tmp")"
    hold=$((hold+1))
  fi
  rm -f "$tmp"
}
cmdv() { command -v "$1"; }
mcp_smoke() {
  command -v md-anything-mcp >/dev/null 2>&1 || return 1
  timeout 3 md-anything-mcp </dev/null >/dev/null 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]
}
playwright_smoke() {
  PLAYWRIGHT_BROWSERS_PATH=0 npx -y @playwright/cli@latest --version
}

check "uv" uv --version
check "md-anything" mda --help
check "md-anything-mcp" mcp_smoke
check "download-anything" da doctor --json
check "lemmeknow" lemmeknow --version
check "CLI-Anything hub" sh -c 'command -v cli-hub || command -v cli-anything-hub || command -v cli-anything'
check "Playwright CLI" playwright_smoke
check "rust-anything" rust-anything --version
check "OpenClaude" openclaude --version
check "SkillEvaluator" skillevaluator --version

for d in \
  CLI-Anything CLI-Anything-WEB harness-anything awesome-mcp-servers cursor-plugins \
  jquery appwrite stitch-skills md-anything openclaude SkillEvaluator rust-anything uv \
  download-anything Claude-BugHunter
do
  if [ -d "$ROOT/src/$d/.git" ]; then
    printf 'PASS  %-28s %s\n' "source:$d" "$(git -C "$ROOT/src/$d" rev-parse --short HEAD 2>/dev/null)"
    pass=$((pass+1))
  else
    printf 'HOLD  %-28s missing checkout\n' "source:$d"
    hold=$((hold+1))
  fi
done

if [ -d "$HOME/.agents/skills" ]; then
  printf 'PASS  %-28s %s\n' "agent-skills-root" "$HOME/.agents/skills"
  pass=$((pass+1))
else
  printf 'HOLD  %-28s not present\n' "agent-skills-root"
  hold=$((hold+1))
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  printf 'PASS  %-28s daemon reachable\n' "Docker/Appwrite substrate"
  pass=$((pass+1))
else
  printf 'HOLD  %-28s Docker daemon unavailable; Appwrite self-host remains blocked\n' "Docker/Appwrite substrate"
  hold=$((hold+1))
fi

printf '\nRESULT: PASS=%d HOLD=%d\n' "$pass" "$hold"
if [ "$hold" -gt 0 ]; then
  exit 4
fi
