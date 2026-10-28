#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
CFG="${FORGE_SURGEON_CONFIG:-$H/config.json}"
PACK="${VANTASM_PACK_ROOT:-$HOME/nemotron-v0451-live}"
SPEECH="${VANTASM_SPEECH_ROOT:-$HOME/forge-pack/Lokivellispeech}"
VANTASM_REPO="${VANTASM_REPO_ROOT:-$HOME/forge-pack/Lokivellis-vantasm}"
T3MP3ST="${VANTASM_T3MP3ST_ROOT:-$HOME/forge-repos/T3MP3ST}"

[ -f "$CFG" ] || { echo "HOLD missing config: $CFG"; exit 4; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$CFG.operator-mode.$STAMP.bak"
cp "$CFG" "$BACKUP"
chmod 600 "$BACKUP" 2>/dev/null || true

python3 - "$CFG" "$PACK" "$SPEECH" "$VANTASM_REPO" "$T3MP3ST" <<'PY'
import json, os, sys
from pathlib import Path

cfg_path, pack, speech, vantasm_repo, t3mp3st = sys.argv[1:]
p=Path(cfg_path)
cfg=json.loads(p.read_text())

seat=cfg.setdefault("seats",{}).setdefault("builder-seat",{})
perms=set(seat.get("permissions",[]))
perms.update(["read","inspect","diff","patch","write","execute","test","restart","rollback"])
seat["permissions"]=sorted(perms)

roots=[pack,speech,vantasm_repo,t3mp3st]
existing=[str(Path(x).expanduser()) for x in seat.get("allowed_roots",[])]
for root in roots:
    root=str(Path(root).expanduser())
    if root not in existing:
        existing.append(root)
seat["allowed_roots"]=existing

cmd=cfg.setdefault("commands",{})

def add(name, argv, timeout=180, mutating=False, affected=None, extra=None):
    d={"argv":argv,"timeout":timeout,"mutating":mutating,"affected_paths":affected or []}
    if extra:
        d["extra_arg_pattern"]=extra
    cmd[name]=d

add("vantasm_launch", ["bash", str(Path.home()/".forge-surgeon"/"vantasm-launch")], 600, True, roots)
add("pack_activation_apply_start", ["python3", str(Path(pack)/"pack_activation.py"), "--apply", "--start"], 600, True, [pack])
add("speech_install_kokoro", ["bash", str(Path(speech)/"scripts"/"install-worker.sh"), "kokoro"], 900, True, [speech])
add("speech_start_kokoro", ["python3","-m","lokivellispeech","workers","start","kokoro"], 300, True, [speech])
add("speech_stop_kokoro", ["python3","-m","lokivellispeech","workers","stop","kokoro"], 120, True, [speech])
add("speech_smoke", ["python3","-m","lokivellispeech","smoke","--base","http://127.0.0.1:8788/"], 360, False, [speech])
add("speech_doctor", ["python3","-m","lokivellispeech","doctor","--json"], 120, False, [speech])
add("pytest", ["python3","-m","pytest"], 900, False, [], r"^[A-Za-z0-9_./:=+@%,-]*$")
add("python_unittest", ["python3","-m","unittest"], 900, False, [], r"^[A-Za-z0-9_./:=+@%,-]*$")
add("git_status", ["git","status","--short","--branch"], 30, False, [])
add("git_diff", ["git","diff","--no-ext-diff","--"], 60, False, [])
add("git_add_all", ["git","add","-A"], 60, True, roots)
add("git_commit", ["git","commit"], 120, True, roots, r"^[A-Za-z0-9_./:=+@%,' -]*$")

tmp=p.with_suffix(".tmp")
tmp.write_text(json.dumps(cfg,indent=2)+"\n")
os.replace(tmp,p)
os.chmod(p,0o600)
PY

echo "PASS operator mode configured"
echo "backup: $BACKUP"
echo "builder roots:"
python3 - "$CFG" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1]))
for x in cfg["seats"]["builder-seat"]["allowed_roots"]:
    print(" -",x)
print("profiles:")
for x in sorted(cfg.get("commands",{})):
    print(" -",x)
PY

# Restart only the control plane. Do not expose credentials.
if [ -x "$H/stop.sh" ]; then
  "$H/stop.sh" >/dev/null 2>&1 || true
else
  pkill -f 'surgeon.server' >/dev/null 2>&1 || true
fi
sleep 1

CORE="$H/vantasm-core"
if [ -x "$CORE" ]; then
  "$CORE" up >/dev/null
elif command -v vantasm >/dev/null 2>&1; then
  vantasm up >/dev/null
else
  echo "HOLD config written, but Vantasm CLI not found for restart"
  exit 4
fi

curl -fsS --max-time 5 http://127.0.0.1:8765/healthz >/dev/null
echo "PASS Surgeon restarted on 8765"
echo "RESULT: PASS — Claude builder seat has bounded end-to-end repair profiles"
