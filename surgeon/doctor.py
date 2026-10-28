"""Vantasm machine-readable control surface: doctor / health / status / up / down.

This module is deliberately dependency-light: `doctor` must report the truth
even when the MCP stack is not installed and when the Surgeon core module is
absent. It never fabricates a READY state and never hardcodes a device path —
everything derives from $FORGE_SURGEON_HOME (default ~/.forge-surgeon) and the
on-device config.json.

It introspects install/runtime only. It is NOT the controlled-mutation engine
(that is surgeon/core.py); if that module is missing, `up` reports HOLD with the
exact reason instead of starting a broken server.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def control_root() -> Path:
    return Path(os.environ.get("FORGE_SURGEON_HOME", str(Path.home() / ".forge-surgeon"))).expanduser()


def _app_root() -> Path:
    # package may be installed editable from $H/app, or run from the source tree
    here = Path(__file__).resolve().parent.parent
    app = control_root() / "app"
    return app if (app / "surgeon").is_dir() else here


def _port(cfg: dict) -> int:
    env = os.environ.get("FORGE_SURGEON_PORT")
    if env:
        return int(env)
    return int(cfg.get("server", {}).get("port", 8765))


def _read_config() -> tuple[dict | None, Path]:
    cfg_path = Path(os.environ.get("FORGE_SURGEON_CONFIG", str(control_root() / "config.json"))).expanduser()
    if not cfg_path.is_file():
        return None, cfg_path
    try:
        return json.loads(cfg_path.read_text(encoding="utf-8")), cfg_path
    except (ValueError, OSError):
        return None, cfg_path


def _module_present(name: str) -> bool:
    try:
        return importlib.util.find_spec(name) is not None
    except (ImportError, ValueError):
        return False


def _port_open(host: str, port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


def _pidfile() -> Path:
    return control_root() / "runtime" / "server.pid"


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def doctor() -> dict:
    H = control_root()
    cfg, cfg_path = _read_config()
    app = _app_root()
    venv_py = H / "venv" / "bin" / "python"
    checks: list[dict] = []

    def chk(name, ok, detail, fatal=True):
        checks.append({"check": name, "status": "PASS" if ok else "HOLD", "detail": detail, "fatal": fatal and not ok})

    chk("control_root", H.is_dir(), str(H))
    chk("config", cfg is not None, str(cfg_path) if cfg else f"missing/invalid: {cfg_path}")
    seats = list((cfg or {}).get("seats", {}).keys())
    unresolved = [s for s, v in (cfg or {}).get("seats", {}).items()
                  if str(v.get("credential", "")) in ("", "GENERATE_AT_INSTALL")]
    chk("seat_credentials", cfg is not None and not unresolved,
        "generated on device" if cfg and not unresolved else f"not generated: {unresolved or 'no config'}")
    chk("venv", venv_py.exists(), str(venv_py), fatal=False)
    # dependency + core checks run inside the app context
    core_present = (app / "surgeon" / "core.py").is_file()
    chk("surgeon_core_module", core_present,
        "present" if core_present else f"MISSING at {app}/surgeon/core.py — server cannot start until this repo line ships it")
    mcp_ok = _module_present("mcp")
    chk("mcp_runtime", mcp_ok, "importable" if mcp_ok else "mcp[cli] not installed in this interpreter", fatal=False)
    chk("python", sys.version_info >= (3, 10), sys.version.split()[0])
    for tool in ("cloudflared", "curl"):
        ok = _tool(tool)
        chk(f"tool:{tool}", ok, "present" if ok else "not installed (optional for local start)", fatal=False)

    port = _port(cfg or {})
    fatals = [c for c in checks if c["fatal"]]
    can_start = core_present and cfg is not None and not unresolved
    return {
        "service": "vantasm", "kind": "doctor", "control_root": str(H), "app_root": str(app),
        "port": port, "seats": seats, "can_start": can_start,
        "status": "PASS" if not fatals else "HOLD",
        "blockers": [c["check"] for c in fatals],
        "checks": checks,
    }


def _tool(name: str) -> bool:
    from shutil import which
    return which(name) is not None


def status() -> dict:
    cfg, _ = _read_config()
    port = _port(cfg or {})
    pf = _pidfile()
    pid = int(pf.read_text().strip()) if pf.is_file() and pf.read_text().strip().isdigit() else 0
    alive = bool(pid and _alive(pid))
    return {"service": "vantasm", "kind": "status", "status": "PASS" if alive else "HOLD",
            "pid": pid, "alive": alive, "port": port, "listening": _port_open("127.0.0.1", port)}


def health() -> dict:
    cfg, _ = _read_config()
    port = _port(cfg or {})
    url = f"http://127.0.0.1:{port}/healthz"
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            body = json.loads(r.read() or b"{}")
            return {"service": "vantasm", "kind": "health", "status": "PASS", "http": r.status,
                    "endpoint": url, "server": body}
    except urllib.error.HTTPError as e:
        return {"service": "vantasm", "kind": "health", "status": "HOLD", "http": e.code, "endpoint": url}
    except (urllib.error.URLError, OSError, ValueError) as e:
        return {"service": "vantasm", "kind": "health", "status": "HOLD", "http": 0, "endpoint": url,
                "detail": f"server not answering: {e}"}


def up(watch: bool = False, wait_s: float = 25.0) -> dict:
    d = doctor()
    if not d["can_start"]:
        return {"service": "vantasm", "kind": "up", "status": "HOLD",
                "detail": "preflight failed; not starting a broken server", "blockers": d["blockers"],
                "doctor": d}
    st = status()
    if st["alive"]:
        return {"service": "vantasm", "kind": "up", "status": "PASS", "detail": f"already running pid {st['pid']}",
                "port": st["port"]}
    H = control_root()
    (H / "runtime").mkdir(parents=True, exist_ok=True)
    (H / "logs").mkdir(parents=True, exist_ok=True)
    venv_py = H / "venv" / "bin" / "python"
    py = str(venv_py) if venv_py.exists() else sys.executable
    log = (H / "logs" / "server.log").open("ab")
    env = dict(os.environ)
    proc = subprocess.Popen([py, "-m", "surgeon.server"], cwd=str(_app_root()), stdout=log,
                            stderr=subprocess.STDOUT, start_new_session=True, env=env)
    _pidfile().write_text(f"{proc.pid}\n")
    port = d["port"]
    deadline = time.time() + wait_s
    while time.time() < deadline:
        if proc.poll() is not None:
            return {"service": "vantasm", "kind": "up", "status": "HOLD",
                    "detail": f"server exited rc={proc.returncode}; see {H}/logs/server.log"}
        if _port_open("127.0.0.1", port):
            h = health()
            return {"service": "vantasm", "kind": "up", "status": h["status"], "pid": proc.pid,
                    "port": port, "health": h}
        time.sleep(0.4)
    return {"service": "vantasm", "kind": "up", "status": "HOLD", "pid": proc.pid,
            "detail": f"server did not answer /healthz within {wait_s}s"}


def down() -> dict:
    st = status()
    if not st["alive"]:
        _pidfile().unlink(missing_ok=True)
        return {"service": "vantasm", "kind": "down", "status": "PASS", "detail": "not running"}
    try:
        os.killpg(st["pid"], signal.SIGTERM)
    except OSError:
        try:
            os.kill(st["pid"], signal.SIGTERM)
        except OSError:
            pass
    for _ in range(20):
        if not _alive(st["pid"]):
            break
        time.sleep(0.2)
    _pidfile().unlink(missing_ok=True)
    return {"service": "vantasm", "kind": "down", "status": "PASS", "detail": f"stopped pid {st['pid']}"}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="vantasm", description="Vantasm Termux control surface")
    ap.add_argument("command", choices=["doctor", "status", "health", "up", "down"])
    ap.add_argument("--watch", action="store_true")
    ap.add_argument("--json", action="store_true", help="machine-readable output (default)")
    ap.add_argument("--text", action="store_true", help="human summary")
    a = ap.parse_args(argv)
    result = {"doctor": doctor, "status": status, "health": health,
              "up": lambda: up(a.watch), "down": down}[a.command]()
    if a.text:
        print(f"{result['kind']}: {result['status']}" + (f" — {result.get('detail','')}" if result.get("detail") else ""))
        for c in result.get("checks", []):
            print(f"  {c['check']:<22} {c['status']:<5} {c['detail']}")
    else:
        print(json.dumps(result, indent=2))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
