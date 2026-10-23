# Public portability boundary

Public Vantasm must be target-device driven.

## Never commit

- generated seat credentials
- OAuth client secrets
- Cloudflare tunnel credentials
- temporary Quick Tunnel URLs
- developer-specific `$HOME` paths
- personal project roots
- actual PIDs
- private IP/device identifiers
- real receipt stores
- screenshots containing private machine state
- private Git remotes or tokens

## Allowed examples

Examples may use:
- `$HOME`
- `$PREFIX`
- `$FORGE_SURGEON_HOME`
- `127.0.0.1`
- example ports clearly marked as defaults
- `~/vantasm-workspace`
- reserved example domains such as `.invalid`

## Discovery

Machine-specific values should come from:
1. local discovery,
2. owner configuration,
3. runtime state produced by Vantasm/Surgeon.

Do not make development-machine values the fallback source of truth.
