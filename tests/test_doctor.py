"""Vantasm control-surface tests. No MCP stack required."""
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))
from surgeon import doctor  # noqa: E402


@pytest.fixture
def home(tmp_path, monkeypatch):
    h = tmp_path / ".forge-surgeon"
    monkeypatch.setenv("FORGE_SURGEON_HOME", str(h))
    monkeypatch.delenv("FORGE_SURGEON_PORT", raising=False)
    return h


def install(tmp_path):
    env = dict(os.environ, FORGE_SURGEON_HOME=str(tmp_path / ".forge-surgeon"),
               VANTASM_WORKSPACE=str(tmp_path / "ws"), VANTASM_SKIP_PKG="1", VANTASM_SKIP_VENV="1")
    r = subprocess.run(["bash", str(REPO / "scripts" / "install.sh")], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return env


def test_install_generates_device_local_credentials(tmp_path):
    install(tmp_path)
    cfg = json.loads((tmp_path / ".forge-surgeon" / "config.json").read_text())
    creds = [v["credential"] for v in cfg["seats"].values()]
    assert all(c not in ("", "GENERATE_AT_INSTALL") for c in creds)
    assert len(set(creds)) == len(creds)              # each seat unique
    assert all(len(c) >= 40 for c in creds)           # real entropy, generated on device
    # allowed_roots point at the chosen workspace, not a developer path
    for v in cfg["seats"].values():
        assert v["allowed_roots"] == [str(tmp_path / "ws")]


def test_install_is_idempotent_and_does_not_rotate_creds(tmp_path):
    install(tmp_path)
    before = (tmp_path / ".forge-surgeon" / "config.json").read_text()
    install(tmp_path)
    after = (tmp_path / ".forge-surgeon" / "config.json").read_text()
    assert before == after  # re-run must not rotate credentials


def test_doctor_holds_when_core_module_absent(tmp_path, home):
    install(tmp_path)
    d = doctor.doctor()
    assert d["status"] == "HOLD" and d["can_start"] is False
    assert "surgeon_core_module" in d["blockers"]
    assert d["port"] == 8765


def test_up_refuses_to_start_without_core(tmp_path, home):
    install(tmp_path)
    r = doctor.up()
    assert r["status"] == "HOLD" and "surgeon_core_module" in r["blockers"]
    assert doctor.status()["alive"] is False  # nothing was launched


def test_no_hardcoded_device_paths_in_shipped_files():
    offenders = []
    for f in list((REPO / "surgeon").glob("*.py")) + [REPO / "connect" / "vantasm", REPO / "scripts" / "install.sh"]:
        t = f.read_text()
        for bad in ("/data/data/com.termux/files/home/", "/sdcard/", "/storage/emulated/0/"):
            if bad in t:
                offenders.append((f.name, bad))
        # the Termux shebang path is allowed; a hardcoded personal home is not
    assert offenders == [], offenders


def test_up_starts_when_a_core_is_present(tmp_path, home, monkeypatch):
    """Prove the start path itself is sound: with a minimal stand-in server that
    answers /healthz, `up` reaches PASS. This is a TEST stub, not surgeon/core."""
    h = tmp_path / ".forge-surgeon"
    app = h / "app"
    (app / "surgeon").mkdir(parents=True)
    (app / "surgeon" / "__init__.py").write_text("")
    (app / "surgeon" / "core.py").write_text("# test stand-in so can_start is True\n")
    (app / "VERSION").write_text("test\n")
    port = 8799
    monkeypatch.setenv("FORGE_SURGEON_PORT", str(port))
    # minimal server module answering /healthz on the configured port
    (app / "surgeon" / "server.py").write_text(
        "import os, json\n"
        "from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer\n"
        "class H(BaseHTTPRequestHandler):\n"
        "    def do_GET(self):\n"
        "        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()\n"
        "        self.wfile.write(json.dumps({'service':'forge-surgeon','status':'PASS'}).encode())\n"
        "    def log_message(self,*a): pass\n"
        "ThreadingHTTPServer(('127.0.0.1', int(os.environ['FORGE_SURGEON_PORT'])), H).serve_forever()\n")
    # config with resolved creds
    (h).mkdir(exist_ok=True)
    (h / "config.json").write_text(json.dumps({
        "server": {"host": "127.0.0.1", "port": port},
        "seats": {"architect-seat": {"credential": "x" * 48, "permissions": [], "allowed_roots": [str(tmp_path)]}},
    }))
    try:
        r = doctor.up(wait_s=15)
        assert r["status"] == "PASS", r
        assert doctor.health()["status"] == "PASS"
    finally:
        doctor.down()
