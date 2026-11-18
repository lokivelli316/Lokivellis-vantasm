#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
H="${FORGE_SURGEON_HOME:-$HOME/.forge-surgeon}"
CFG="${FORGE_SURGEON_CONFIG:-$H/config.json}"
VANTASM_REPO="${VANTASM_REPO_ROOT:-$HOME/forge-pack/Lokivellis-vantasm}"
EXT_ROOT="${LOKIVELLI_EXTERNAL_ROOT:-$HOME/forge-tools}"
[ -f "$CFG" ] || { echo "HOLD missing config: $CFG"; exit 4; }
[ -f "$VANTASM_REPO/scripts/install-external-tools.sh" ] || { echo "HOLD missing installer in $VANTASM_REPO"; exit 4; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
cp "$CFG" "$CFG.external-tools.$STAMP.bak"
chmod 600 "$CFG.external-tools.$STAMP.bak" 2>/dev/null || true

python3 - "$CFG" "$VANTASM_REPO" "$EXT_ROOT" <<'PY'
import json, os, sys
from pathlib import Path
cfg_path, repo, ext = sys.argv[1:]
p=Path(cfg_path)
cfg=json.loads(p.read_text())
seat=cfg.setdefault("seats",{}).setdefault("builder-seat",{})
perms=set(seat.get("permissions",[]))
perms.update(["read","inspect","diff","patch","write","execute","test","restart","rollback"])
seat["permissions"]=sorted(perms)
roots=[str(Path(repo).expanduser()), str(Path(ext).expanduser())]
allowed=[str(Path(x).expanduser()) for x in seat.get("allowed_roots",[])]
for root in roots:
    if root not in allowed: allowed.append(root)
seat["allowed_roots"]=allowed
cmd=cfg.setdefault("commands",{})
cmd["external_tools_install"]={
  "argv":["bash",str(Path(repo)/"scripts"/"install-external-tools.sh")],
  "timeout":7200,
  "mutating":True,
  "affected_paths":[str(Path(ext).expanduser()),str(Path.home()/".agents"/"skills"),str(Path.home()/".claude"/"skills"),str(Path.home()/".codex"),str(Path.home()/".cursor"),str(Path.home()/".gemini"),str(Path.home()/".hermes")]
}
cmd["external_tools_verify"]={
  "argv":["bash",str(Path(repo)/"scripts"/"verify-external-tools.sh")],
  "timeout":1800,
  "mutating":False,
  "affected_paths":[]
}
tmp=p.with_suffix(".tmp")
tmp.write_text(json.dumps(cfg,indent=2)+"\n")
os.replace(tmp,p)
os.chmod(p,0o600)
PY

echo "PASS external tool profiles registered"
echo "profiles: external_tools_install, external_tools_verify"
echo "root: $EXT_ROOT"
