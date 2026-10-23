from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .util import read_json


@dataclass(frozen=True)
class Settings:
    control_root: Path
    config_path: Path
    data: dict[str, Any]

    @property
    def host(self) -> str:
        return str(self.data.get("server", {}).get("host", "127.0.0.1"))

    @property
    def port(self) -> int:
        override = os.environ.get("FORGE_SURGEON_PORT")
        if override:
            return int(override)
        return int(self.data.get("server", {}).get("port", 8765))

    @property
    def resource_url(self) -> str:
        override = os.environ.get("FORGE_SURGEON_RESOURCE_URL")
        if override:
            return override
        if os.environ.get("FORGE_SURGEON_PORT"):
            return f"http://127.0.0.1:{self.port}/mcp"
        configured = self.data.get("server", {}).get("resource_url")
        if configured and configured != "auto":
            return str(configured)
        return f"http://127.0.0.1:{self.port}/mcp"

    @property
    def issuer_url(self) -> str:
        return str(self.data.get("server", {}).get("issuer_url", "https://forge-surgeon.invalid/"))


def load_settings() -> Settings:
    control_root = Path(os.environ.get("FORGE_SURGEON_HOME", str(Path.home() / ".forge-surgeon"))).expanduser()
    config_path = Path(os.environ.get("FORGE_SURGEON_CONFIG", str(control_root / "config.json"))).expanduser()
    data = read_json(config_path, default=None)
    if not isinstance(data, dict):
        raise RuntimeError(f"Missing or invalid Surgeon config: {config_path}")
    return Settings(control_root=control_root, config_path=config_path, data=data)
