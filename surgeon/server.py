from __future__ import annotations

from typing import Any

from pydantic import AnyHttpUrl
from starlette.requests import Request
from starlette.responses import JSONResponse

from mcp.server.mcpserver import MCPServer
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.settings import AuthSettings
from mcp.server.transport_security import TransportSecuritySettings

from .auth import SeatTokenVerifier
from .config import load_settings
from .core import SurgeonCore
from .redaction import Redactor

settings = load_settings()
secrets = [str(v.get("credential")) for v in settings.data.get("seats", {}).values() if v.get("credential")]
redactor = Redactor(secrets)
core = SurgeonCore(settings, redactor)
reconciled = core.reconcile_open_receipts()

mcp = MCPServer(
    "Forge Surgeon",
    token_verifier=SeatTokenVerifier(settings.data.get("seats", {})),
    auth=AuthSettings(
        issuer_url=AnyHttpUrl(settings.issuer_url),
        resource_server_url=AnyHttpUrl(settings.resource_url),
        required_scopes=[],
        validate_token_resource=False,
    ),
)


def seat() -> str:
    tok = get_access_token()
    if not tok or not tok.client_id:
        raise RuntimeError("Authenticated seat unavailable")
    return tok.client_id


@mcp.tool(name="forge_scan")
def forge_scan() -> dict[str, Any]: return core.scan(seat())

@mcp.tool(name="forge_tree")
def forge_tree(path: str, max_depth: int = 3, max_entries: int = 500) -> dict[str, Any]: return core.tree(seat(), path, max_depth, max_entries)

@mcp.tool(name="forge_read")
def forge_read(path: str, max_bytes: int = 256000) -> dict[str, Any]: return core.read(seat(), path, max_bytes)

@mcp.tool(name="forge_search")
def forge_search(root: str, pattern: str, max_results: int = 200) -> dict[str, Any]: return core.search(seat(), root, pattern, max_results)

@mcp.tool(name="forge_stat")
def forge_stat(path: str) -> dict[str, Any]: return core.stat(seat(), path)

@mcp.tool(name="forge_git_status")
def forge_git_status(repo: str) -> dict[str, Any]: return core.git_status(seat(), repo)

@mcp.tool(name="forge_git_diff")
def forge_git_diff(repo: str) -> dict[str, Any]: return core.git_diff(seat(), repo)

@mcp.tool(name="forge_snapshot")
def forge_snapshot(path: str, reason: str) -> dict[str, Any]: return core.snapshot(seat(), path, reason)

@mcp.tool(name="forge_mkdir")
def forge_mkdir(path: str, reason: str, expected_state: str) -> dict[str, Any]: return core.mkdir(seat(), path, reason, expected_state)

@mcp.tool(name="forge_copy")
def forge_copy(src: str, dst: str, reason: str, expected_dst_state: str) -> dict[str, Any]: return core.copy(seat(), src, dst, reason, expected_dst_state)

@mcp.tool(name="forge_move")
def forge_move(src: str, dst: str, reason: str, expected_src_state: str, expected_dst_state: str) -> dict[str, Any]: return core.move(seat(), src, dst, reason, expected_src_state, expected_dst_state)

@mcp.tool(name="forge_patch")
def forge_patch(path: str, replacements: list[dict[str, str]], reason: str, expected_state: str) -> dict[str, Any]: return core.patch(seat(), path, replacements, reason, expected_state)

@mcp.tool(name="forge_write")
def forge_write(path: str, content: str, reason: str, expected_state: str) -> dict[str, Any]: return core.write(seat(), path, content, reason, expected_state)

@mcp.tool(name="forge_quarantine")
def forge_quarantine(path: str, reason: str, expected_state: str) -> dict[str, Any]: return core.quarantine_remove(seat(), path, reason, expected_state)

@mcp.tool(name="forge_exec_safe")
def forge_exec_safe(profile: str, cwd: str, reason: str, args: list[str] | None = None, expected_states: dict[str, str] | None = None) -> dict[str, Any]: return core.exec_safe(seat(), profile, cwd, args, reason, expected_states)

@mcp.tool(name="forge_package_status")
def forge_package_status(package: str) -> dict[str, Any]: return core.package_status(seat(), package)

@mcp.tool(name="forge_install_package")
def forge_install_package(package: str, reason: str, owner_approved: bool = False) -> dict[str, Any]: return core.install_package(seat(), package, reason, owner_approved)

@mcp.tool(name="forge_process_status")
def forge_process_status(match: str = "") -> dict[str, Any]: return core.process_status(seat(), match)

@mcp.tool(name="forge_service_status")
def forge_service_status(service: str) -> dict[str, Any]: return core.service_status(seat(), service)

@mcp.tool(name="forge_restart_service")
def forge_restart_service(service: str, reason: str, owner_approved: bool = False) -> dict[str, Any]: return core.restart_service(seat(), service, reason, owner_approved)

@mcp.tool(name="forge_test")
def forge_test(profile: str, cwd: str, args: list[str] | None = None) -> dict[str, Any]: return core.test(seat(), profile, cwd, args)

@mcp.tool(name="forge_health")
def forge_health() -> dict[str, Any]: return core.health(seat())

@mcp.tool(name="forge_diff")
def forge_diff(path_a: str, path_b: str) -> dict[str, Any]: return core.diff(seat(), path_a, path_b)

@mcp.tool(name="forge_rollback")
def forge_rollback(receipt_id: str, reason: str, hold_id: str | None = None) -> dict[str, Any]: return core.rollback(seat(), receipt_id, reason, hold_id)

@mcp.tool(name="forge_receipt")
def forge_receipt(receipt_id: str) -> dict[str, Any]: return core.receipt(seat(), receipt_id)

@mcp.tool(name="forge_receipts_since")
def forge_receipts_since(since: str | None = None, target_seat: str | None = None, path: str | None = None) -> list[dict[str, Any]]: return core.receipts_since(seat(), since, target_seat, path)

@mcp.tool(name="forge_hold")
def forge_hold(path: str, reason: str, receipt_id: str | None = None) -> dict[str, Any]: return core.hold(seat(), path, reason, receipt_id)

@mcp.tool(name="forge_release_hold")
def forge_release_hold(hold_id: str, decision: str, note: str) -> dict[str, Any]: return core.release_hold(seat(), hold_id, decision, note)


@mcp.custom_route("/healthz", methods=["GET"])
async def healthz(request: Request) -> JSONResponse:
    return JSONResponse({
        "service": "forge-surgeon",
        "status": "PASS",
        "port": settings.port,
        "startup_reconciled": len(reconciled),
    })


transport_security = TransportSecuritySettings(enable_dns_rebinding_protection=False)
app = mcp.streamable_http_app(
    host=settings.host,
    json_response=True,
    stateless_http=True,
    transport_security=transport_security,
)


def main() -> None:
    import uvicorn
    uvicorn.run(app, host=settings.host, port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
