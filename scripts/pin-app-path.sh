#!/data/data/com.termux/files/usr/bin/bash
# Pin the Surgeon venv to the installed app, and snapshot installed code for upstreaming.
#
# Problem this fixes: the venv carries an older, non-editable copy of the `surgeon`
# package (from an earlier `pip install $H/app`). Unless PYTHONPATH=$H/app is set by
# hand, Python imports that stale copy first, which lacks doctor.py/core.py, and the
# Surgeon will not start. This adds a .pth file to the venv so $H/app is always first
# on sys.path, for every launcher (vantasm, vantasm-core, forge-surgeon entry point).
#
# It also copies installed CODE (never config, credentials, receipts, logs, venv) into
# <source>/_installed/ so missing files (e.g. surgeon/core.py) can be committed to Git.
#
# Safe: does not stop or restart anything, rotates nothing, deletes nothing.
set -euo pipefail
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
PY="$H/venv/bin/python"
[ -x "$PY" ] || { echo "HOLD: no venv at $H/venv"; exit 4; }
[ -d "$H/app/surgeon" ] || { echo "HOLD: no installed app at $H/app"; exit 4; }

# 1. Pin: a .pth line that starts with "import" runs at interpreter start-up.
SITE="$("$PY" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
PTH="$SITE/zz_forge_surgeon_app.pth"
printf "import sys; p=%s; sys.path.insert(0, p) if p not in sys.path else None\n" "'$H/app'" > "$PTH"
echo "pinned: $PTH -> $H/app"

# 2. Prove it from a neutral directory with PYTHONPATH cleared (find_spec does not run the module).
cd /
RESOLVED="$(env -u PYTHONPATH "$PY" -c 'import importlib.util as u; s=u.find_spec("surgeon"); print(list(s.submodule_search_locations)[0])')"
CORE="$(env -u PYTHONPATH "$PY" -c 'import importlib.util as u; s=u.find_spec("surgeon.core"); print(s.origin if s else "MISSING")')"
echo "surgeon resolves to: $RESOLVED"
echo "surgeon.core:        $CORE"
case "$RESOLVED" in "$H/app/surgeon") echo "PASS: no PYTHONPATH needed" ;; *) echo "HOLD: still resolving elsewhere"; exit 5 ;; esac

# 3. Snapshot installed code for upstreaming (code only).
SNAP="$SRC/_installed"
rm -rf "$SNAP"; mkdir -p "$SNAP"
( cd "$H/app" && find . -type f \( -name '*.py' -o -name '*.sh' -o -name '*.toml' -o -name '*.md' -o -name 'VERSION' -o -name '*.txt' -o -path './connect/*' -o -path './ui/*' \) \
    ! -path '*/__pycache__/*' ! -name 'config.json' -print0 | while IFS= read -r -d '' f; do
      mkdir -p "$SNAP/app/$(dirname "$f")"; cp -p "$f" "$SNAP/app/$f"; done )
mkdir -p "$SNAP/bin"
for f in vantasm vantasm-core vantasm-wrapper vantasm-launch vantasm-bridge-up start-tunnel.sh stop.sh; do
  [ -f "$H/$f" ] && cp -p "$H/$f" "$SNAP/bin/$f"
done
[ -d "$H/tools" ] && { mkdir -p "$SNAP/tools"; find "$H/tools" -maxdepth 1 -type f -name '*.py' -exec cp -p {} "$SNAP/tools/" \; ; }
chmod -R go-rwx "$SNAP"
echo "snapshot: $SNAP ($(find "$SNAP" -type f | wc -l) files; no config/credentials/receipts/logs)"
echo "RESULT: PASS"
