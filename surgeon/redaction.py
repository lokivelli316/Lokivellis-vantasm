from __future__ import annotations

import re
from typing import Any

_COMMON = [
    re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+\-/=]+"),
    re.compile(r"(?i)(api[_-]?key|token|secret|password|passwd)(\s*[=:]\s*)[^\s,;\]\}\"']+"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{12,}\b"),
]


class Redactor:
    def __init__(self, literal_secrets: list[str] | None = None):
        self.literal_secrets = sorted({s for s in (literal_secrets or []) if s}, key=len, reverse=True)

    def text(self, value: str) -> str:
        out = value
        for s in self.literal_secrets:
            out = out.replace(s, "[REDACTED]")
        for rx in _COMMON:
            if rx.groups >= 2:
                out = rx.sub(lambda m: f"{m.group(1)}{m.group(2)}[REDACTED]", out)
            else:
                out = rx.sub(lambda m: f"{m.group(1)}[REDACTED]", out)
        return out

    def obj(self, value: Any) -> Any:
        if isinstance(value, str):
            return self.text(value)
        if isinstance(value, dict):
            return {str(k): self.obj(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self.obj(v) for v in value]
        if isinstance(value, tuple):
            return tuple(self.obj(v) for v in value)
        return value
