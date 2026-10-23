#!/usr/bin/env python3
"""Vantasm connection probe — a vendor-neutral MCP *client* used to prove the
connection chain end to end. It is not part of the Surgeon core.

It reads seat credentials straight from the Surgeon config (the authoritative
source; SEAT_TOKENS.txt can go stale after `owner.sh rotate-token`) and never
prints them.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
import socket
import sys
from ipaddress import ip_address
from pathlib import Path
from urllib.parse import urlsplit

INIT_BODY = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "vantasm-probe", "version": "0.1.4"},
    },
}
HEADERS = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}


def install_dns_override(url: str, resolve_ip: str | None) -> dict | None:
    if not resolve_ip:
        return None
    ip_address(resolve_ip)
    host = urlsplit(url).hostname
    if not host:
        raise ValueError("MCP URL has no hostname")
    target = host.lower()
    original = socket.getaddrinfo

    def forced_getaddrinfo(name, port, family=0, type=0, proto=0, flags=0):
        n = name.decode() if isinstance(name, (bytes, bytearray)) else str(name)
        if n.lower() == target:
            return original(resolve_ip, port, family, type, proto, flags)
        return original(name, port, family, type, proto, flags)

    socket.getaddrinfo = forced_getaddrinfo
    return {"hostname": host, "ip": resolve_ip, "mode": "socket-getaddrinfo override; TLS hostname preserved"}


def load_credentials(config_path: Path, seats: list[str]) -> dict[str, str]:
    cfg = json.loads(config_path.read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for s in seats:
        tok = cfg.get("seats", {}).get(s, {}).get("credential")
        if tok and tok not in {"REPLACE_ME", "GENERATE_AT_INSTALL"}:
            out[s] = str(tok)
    return out


async def raw_auth_check(httpx2, url: str, token: str | None, timeout: float) -> dict:
    headers = dict(HEADERS)
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    try:
        async with httpx2.AsyncClient(timeout=timeout) as hc:
            r = await hc.post(url, headers=headers, json=INIT_BODY)
        return {"http_status": r.status_code, "pass": r.status_code == 401}
    except Exception as e:
        return {"http_status": None, "pass": False, "error": f"{type(e).__name__}: {e}"[:300]}


async def seat_check(httpx2, Client, streamable_http_client, url: str, seat: str, token: str, timeout: float) -> dict:
    res: dict = {"seat": seat, "pass": False}
    try:
        async with httpx2.AsyncClient(headers={"Authorization": f"Bearer {token}"}, timeout=timeout) as hc:
            async with Client(streamable_http_client(url, http_client=hc)) as client:
                res["protocol"] = getattr(client, "protocol_version", None)
                tools = await client.list_tools()
                names = sorted(getattr(t, "name", str(t)) for t in getattr(tools, "tools", tools))
                res["tool_count"] = len(names)
                res["tools"] = names
                if "forge_health" not in names:
                    res["error"] = "forge_health not exposed"
                    return res
                call = await client.call_tool("forge_health", {})
                sc = getattr(call, "structured_content", None) or {}
                res["health_status"] = sc.get("status")
                res["resolved_seat"] = sc.get("seat")
                for k in ("daemon", "tunnel", "wake_lock", "watchdog"):
                    if k in sc:
                        res[k] = sc[k]
                res["pass"] = (not getattr(call, "is_error", False)) and sc.get("status") == "PASS" and sc.get("seat") == seat
                if not res["pass"] and sc.get("seat") != seat:
                    res["error"] = "Surgeon resolved a different seat than the credential belongs to"
    except BaseException as e:
        msg = f"{type(e).__name__}: {e}"
        subs = getattr(e, "exceptions", None)
        if subs:
            msg += " | " + "; ".join(f"{type(x).__name__}: {x}" for x in subs)
        res["error"] = msg[:500]
    return res


async def main_async(args) -> int:
    try:
        import httpx2
        from mcp import Client
        from mcp.client.streamable_http import streamable_http_client
    except Exception as e:
        print(json.dumps({"overall": "FAIL", "error": f"MCP client libraries unavailable in this Python: {e}"}))
        return 2

    try:
        dns_override = install_dns_override(args.url, args.resolve_ip)
    except Exception as e:
        print(json.dumps({"overall": "FAIL", "error": f"invalid DNS override: {e}"}))
        return 2

    creds = load_credentials(Path(args.config).expanduser(), args.seats)
    missing = [s for s in args.seats if s not in creds]
    report: dict = {"url": args.url, "seats_requested": args.seats, "seats_missing_credential": missing}
    if dns_override:
        report["dns_override"] = dns_override

    report["no_auth"] = await raw_auth_check(httpx2, args.url, None, args.timeout)
    report["bad_auth"] = await raw_auth_check(httpx2, args.url, "vantasm-invalid-" + secrets.token_urlsafe(16), args.timeout)

    seat_results = []
    for s in args.seats:
        if s in creds:
            seat_results.append(await seat_check(httpx2, Client, streamable_http_client, args.url, s, creds[s], args.timeout))
    report["seats"] = seat_results

    tool_sets = [tuple(r.get("tools", [])) for r in seat_results if r.get("pass")]
    report["same_core_tools"] = len(tool_sets) >= 1 and len(set(tool_sets)) == 1
    for r in seat_results:
        r.pop("tools", None)

    ok = (
        report["no_auth"]["pass"]
        and report["bad_auth"]["pass"]
        and not missing
        and len(seat_results) == len(args.seats)
        and all(r["pass"] for r in seat_results)
        and report["same_core_tools"]
    )
    report["overall"] = "PASS" if ok else "FAIL"
    text_out = json.dumps(report, indent=2)
    for tok in creds.values():
        text_out = text_out.replace(tok, "[REDACTED]")
    print(text_out)
    return 0 if ok else 1


def main() -> None:
    p = argparse.ArgumentParser(description="Vantasm MCP connection probe")
    p.add_argument("--url", required=True, help="full MCP endpoint, ending in /mcp")
    p.add_argument("--config", default=os.path.join(os.environ.get("FORGE_SURGEON_HOME", "~/.forge-surgeon"), "config.json"))
    p.add_argument("--seats", nargs="+", default=["auditor-seat", "builder-seat"])
    p.add_argument("--timeout", type=float, default=30.0)
    p.add_argument("--resolve-ip", default=None, help="force the MCP hostname to this proven edge IP while preserving TLS hostname/SNI")
    args = p.parse_args()
    sys.exit(asyncio.run(main_async(args)))


if __name__ == "__main__":
    main()
