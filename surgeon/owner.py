from __future__ import annotations

import argparse
import json
import secrets
from pathlib import Path

from .config import load_settings
from .util import write_json_atomic


def main() -> None:
    s = load_settings()
    p = argparse.ArgumentParser(description="LOCAL-ONLY Forge Surgeon owner management")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show-seats")
    r = sub.add_parser("rotate-token"); r.add_argument("seat")
    roots = sub.add_parser("set-roots"); roots.add_argument("seat"); roots.add_argument("roots", nargs="+")
    args = p.parse_args()
    cfg = s.data
    if args.cmd == "show-seats":
        print(json.dumps({k:{"permissions":v.get("permissions",[]),"allowed_roots":v.get("allowed_roots",[]),"credential":"[REDACTED]"} for k,v in cfg.get("seats",{}).items()}, indent=2)); return
    if args.seat not in cfg.get("seats", {}): raise SystemExit("unknown seat")
    if args.cmd == "rotate-token":
        tok = secrets.token_urlsafe(48); cfg["seats"][args.seat]["credential"] = tok; write_json_atomic(s.config_path, cfg); print(tok); return
    if args.cmd == "set-roots":
        cfg["seats"][args.seat]["allowed_roots"] = [str(Path(x).expanduser().resolve(strict=False)) for x in args.roots]; write_json_atomic(s.config_path, cfg); print("updated"); return

if __name__ == "__main__": main()
