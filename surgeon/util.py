from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any


def utc_now() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def state_token(path: Path) -> str:
    if not path.exists() and not path.is_symlink():
        return "MISSING"
    if path.is_file():
        return "sha256:" + sha256_file(path)
    if path.is_symlink():
        return "symlink:" + os.readlink(path)
    if path.is_dir():
        rows: list[tuple[str, str]] = []
        for p in sorted(path.rglob("*")):
            try:
                rel = str(p.relative_to(path))
            except Exception:
                continue
            if p.is_symlink():
                tok = "symlink:" + os.readlink(p)
            elif p.is_file():
                tok = "sha256:" + sha256_file(p)
            elif p.is_dir():
                tok = "dir"
            else:
                tok = "other"
            rows.append((rel, tok))
        raw = json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode()
        return "tree:" + hashlib.sha256(raw).hexdigest()
    st = path.stat()
    return f"other:{st.st_mode}:{st.st_size}:{st.st_mtime_ns}"


def read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json_atomic(path: Path, data: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def path_within(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False
