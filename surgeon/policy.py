from __future__ import annotations

import hmac
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .util import path_within, read_json, write_json_atomic


class PolicyError(RuntimeError):
    pass


@dataclass(frozen=True)
class Seat:
    name: str
    permissions: frozenset[str]
    roots: tuple[Path, ...]
    approval_requirements: dict[str, str]


class Policy:
    def __init__(self, control_root: Path, cfg: dict[str, Any]):
        self.control_root = control_root.resolve(strict=False)
        self.cfg = cfg
        self.seats = self._load_seats(cfg)
        self.holds_path = control_root / "state" / "holds.json"
        self.holds_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.holds_path.exists():
            write_json_atomic(self.holds_path, {"holds": []})

    def _load_seats(self, cfg: dict[str, Any]) -> dict[str, Seat]:
        seats = {}
        for name, raw in cfg.get("seats", {}).items():
            roots = tuple(Path(p).expanduser().resolve(strict=False) for p in raw.get("allowed_roots", []))
            seats[name] = Seat(
                name=name,
                permissions=frozenset(raw.get("permissions", [])),
                roots=roots,
                approval_requirements=dict(raw.get("approval_requirements", {})),
            )
        return seats

    def get_seat(self, name: str) -> Seat:
        if name not in self.seats:
            raise PolicyError(f"Unknown seat: {name}")
        return self.seats[name]

    def require_perm(self, seat: Seat, permission: str) -> None:
        if permission not in seat.permissions:
            raise PolicyError(f"Seat {seat.name!r} lacks permission {permission!r}")

    def normalize(self, path: str) -> Path:
        p = Path(path).expanduser().resolve(strict=False)
        if path_within(p, self.control_root):
            raise PolicyError("Control-plane paths are not accessible to MCP seats")
        return p

    def require_path(self, seat: Seat, path: str) -> Path:
        p = self.normalize(path)
        if not seat.roots or not any(path_within(p, root) for root in seat.roots):
            raise PolicyError(f"Path outside allowed roots: {p}")
        return p

    def load_holds(self) -> list[dict[str, Any]]:
        return list(read_json(self.holds_path, {"holds": []}).get("holds", []))

    def save_holds(self, holds: list[dict[str, Any]]) -> None:
        write_json_atomic(self.holds_path, {"holds": holds})

    def active_holds_for(self, path: Path) -> list[dict[str, Any]]:
        out = []
        for h in self.load_holds():
            if not h.get("active", True):
                continue
            hp = Path(h["path"]).expanduser().resolve(strict=False)
            if path_within(path, hp) or path_within(hp, path):
                out.append(h)
        return out

    def require_not_held(self, path: Path) -> None:
        holds = self.active_holds_for(path)
        if holds:
            raise PolicyError(f"Path is held: {holds[0].get('hold_id')}")

    def add_hold(self, path: Path, hold: dict[str, Any]) -> None:
        holds = self.load_holds()
        holds.append(hold)
        self.save_holds(holds)

    def release_hold(self, hold_id: str, released_by: str, decision: str, note: str) -> dict[str, Any]:
        holds = self.load_holds()
        found = None
        for h in holds:
            if h.get("hold_id") == hold_id and h.get("active", True):
                h["active"] = False
                h["released_by"] = released_by
                h["decision"] = decision
                h["release_note"] = note
                found = h
                break
        if not found:
            raise PolicyError(f"Unknown or inactive hold: {hold_id}")
        self.save_holds(holds)
        return found


def compare_token(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())
