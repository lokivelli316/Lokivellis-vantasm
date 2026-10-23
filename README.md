# Lokivelli's Vantasm

Vendor-neutral Termux control plane and visual control room built around Forge Surgeon.

Vantasm is intended to be installable on another person's Android/Termux device without inheriting any paths, credentials, PIDs, tunnel URLs, project names, or machine state from the development phone.

## What it is

- Forge Surgeon MCP control plane for Termux
- per-seat authentication and permissions
- expected-state protection
- hierarchical HOLDs
- crash-safe receipts and reconciliation
- quarantine instead of destructive deletion
- registered safe execution profiles
- Cloudflare tunnel connection manager
- watchdog / wake-lock / health reporting
- Vantasm control-room UI
- optional integrations such as EAR-REA-CHA-CHA-CHA

## Portability rule

Runtime values are discovered or configured on the target device.

The public source must not depend on:
- a developer's `$HOME`
- personal repository names
- personal project roots
- static seat credentials
- specific PIDs
- a specific Quick Tunnel URL
- a specific Android device model
- live storage values from another phone
- private receipts or screenshots

The default control root is:

```text
$FORGE_SURGEON_HOME
```

falling back to:

```text
$HOME/.forge-surgeon
```

The example seat root is `~/vantasm-workspace`; owners should replace it with the directories they actually authorize.

## Install target

The current implementation targets Termux on Android.

```sh
pkg update
pkg install -y python git cloudflared
mkdir -p ~/vantasm-workspace
bash scripts/install.sh
vantasm doctor
vantasm up --watch
```

The installer generates seat credentials locally. Do not commit generated credentials.

## UI

`ui/` contains the public control-room frontend. It ships with clearly labeled demo/fallback state until connected to live Surgeon data. No demo PID, path, port, storage amount, receipt number, or project name is authoritative.

Brand artwork/video can be supplied separately in `ui/assets/`; the public core does not require a specific developer-phone artifact to function.

## EAR-REA-CHA-CHA-CHA

See `integrations/EAR_REA_CHA_CHA_CHA.md`.

Vantasm should expose Surgeon state and receipts that an EAR-REA-CHA-CHA-CHA workflow can inspect without hard-coding that workflow into the Surgeon core.

## Status

This repository is the public-portability line. Device-specific development evidence and private receipts are intentionally excluded.

## License

No open-source license has been selected yet. The repository may be public, but reuse rights should be clarified by the owner before calling it an open-source release.
