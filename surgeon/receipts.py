from __future__ import annotations

import json
import os
import threading
import uuid
from pathlib import Path
from typing import Any, Iterable

from .redaction import Redactor
from .util import utc_now


class ReceiptStore:
    def __init__(self, control_root: Path, redactor: Redactor):
        self.root = control_root / "receipts"
        self.root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        self.path = self.root / "receipts.jsonl"
        self.redactor = redactor
        self._lock = threading.RLock()

    def _append(self, receipt: dict[str, Any]) -> dict[str, Any]:
        receipt = self.redactor.obj(receipt)
        with self._lock:
            with self.path.open("a", encoding="utf-8") as f:
                f.write(json.dumps(receipt, sort_keys=True) + "\n")
                f.flush()
                os.fsync(f.fileno())
        return receipt

    def open(self, *, seat: str, operation: str, reason: str, affected_paths: list[str], pre_state: dict[str, str], rollback_class: str, rollback_info: dict[str, Any] | None = None) -> dict[str, Any]:
        rid = str(uuid.uuid4())
        return self._append({
            "receipt_id": rid,
            "timestamp": utc_now(),
            "seat_identity": seat,
            "operation": operation,
            "reason": reason,
            "affected_paths": affected_paths,
            "pre_state": pre_state,
            "post_state": {},
            "command_test_performed": None,
            "result": None,
            "rollback_class": rollback_class,
            "rollback_information": rollback_info or {},
            "state": "OPEN",
            "status": "UNKNOWN",
            "event": "OPEN",
        })

    def event(self, receipt_id: str, event: str, **fields: Any) -> dict[str, Any]:
        return self._append({"receipt_id": receipt_id, "timestamp": utc_now(), "event": event, **fields})

    def close(self, receipt_id: str, *, result: Any, status: str, post_state: dict[str, str] | None = None, test: Any = None) -> dict[str, Any]:
        return self.event(receipt_id, "CLOSED", state="CLOSED", result=result, status=status, post_state=post_state or {}, command_test_performed=test)

    def reject(self, *, seat: str, operation: str, reason: str, affected_paths: list[str], detail: str, status: str = "REJECT") -> dict[str, Any]:
        rid = str(uuid.uuid4())
        return self._append({
            "receipt_id": rid,
            "timestamp": utc_now(),
            "seat_identity": seat,
            "operation": operation,
            "reason": reason,
            "affected_paths": affected_paths,
            "result": detail,
            "rollback_class": "NONE",
            "state": "CLOSED",
            "status": status,
            "event": "REJECT",
        })

    def all_events(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        rows = []
        with self.path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    rows.append(json.loads(line))
        return rows

    def materialize(self) -> dict[str, dict[str, Any]]:
        materialized: dict[str, dict[str, Any]] = {}
        for ev in self.all_events():
            rid = ev.get("receipt_id")
            if not rid:
                continue
            base = materialized.setdefault(rid, {})
            base.update({k: v for k, v in ev.items() if k not in {"event"}})
            base.setdefault("events", []).append(ev)
        return materialized

    def open_receipts(self) -> list[dict[str, Any]]:
        return [r for r in self.materialize().values() if r.get("state") == "OPEN"]

    def query(self, *, seat: str | None = None, since: str | None = None, path_prefixes: Iterable[str] | None = None) -> list[dict[str, Any]]:
        out = []
        prefixes = tuple(path_prefixes or ())
        for r in self.materialize().values():
            if seat and r.get("seat_identity") != seat:
                continue
            if since and str(r.get("timestamp", "")) < since:
                continue
            if prefixes:
                aps = [str(x) for x in r.get("affected_paths", [])]
                if not any(any(p.startswith(prefix) for prefix in prefixes) for p in aps):
                    continue
            out.append(self.redactor.obj(r))
        out.sort(key=lambda x: x.get("timestamp", ""))
        return out
