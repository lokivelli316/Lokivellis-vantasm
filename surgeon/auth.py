from __future__ import annotations

from mcp.server.auth.provider import AccessToken, TokenVerifier

from .policy import compare_token


class SeatTokenVerifier(TokenVerifier):
    def __init__(self, seats: dict):
        self._rows = []
        for seat, raw in seats.items():
            token = raw.get("credential")
            if token:
                self._rows.append((seat, token, list(raw.get("permissions", []))))

    async def verify_token(self, token: str) -> AccessToken | None:
        for seat, expected, scopes in self._rows:
            if compare_token(token, expected):
                return AccessToken(token=token, client_id=seat, subject=seat, scopes=scopes)
        return None
