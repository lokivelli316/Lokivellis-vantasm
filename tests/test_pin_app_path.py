"""pin-app-path.sh: the venv must resolve `surgeon` to $H/app with PYTHONPATH unset,
even when an older non-editable copy sits in site-packages."""
import os
import subprocess
import sys
import venv
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def test_pin_makes_app_win_over_stale_site_packages(tmp_path):
    h = tmp_path / ".forge-surgeon"
    venv.EnvBuilder(with_pip=False).create(h / "venv")
    py = h / "venv" / "bin" / "python"
    site = subprocess.check_output([str(py), "-c", "import sysconfig;print(sysconfig.get_paths()['purelib'])"], text=True).strip()
    stale = Path(site) / "surgeon"                       # the old installed copy (no core.py)
    stale.mkdir(parents=True)
    (stale / "__init__.py").write_text("STALE = True\n")
    app = h / "app" / "surgeon"
    app.mkdir(parents=True)
    (app / "__init__.py").write_text("")
    (app / "core.py").write_text("# real core\n")
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    env["FORGE_SURGEON_HOME"] = str(h)
    before = subprocess.check_output([str(py), "-c", "import surgeon;print(surgeon.__file__)"], text=True, env=env, cwd="/")
    assert str(stale) in before                          # reproduces the bug
    r = subprocess.run(["bash", str(REPO / "scripts" / "pin-app-path.sh")], env=env, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "PASS: no PYTHONPATH needed" in r.stdout
    after = subprocess.check_output([str(py), "-c", "import surgeon.core;print(surgeon.core.__file__)"], text=True, env=env, cwd="/")
    assert after.strip() == str(app / "core.py")
    snap = REPO / "_installed"
    assert (snap / "app" / "surgeon" / "core.py").is_file()
    assert not list(snap.rglob("config.json"))
    subprocess.run(["rm", "-rf", str(snap)])
