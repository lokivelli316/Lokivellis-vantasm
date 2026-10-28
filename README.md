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


## One-command convergence

On an existing Vantasm installation, install the additive launch wrapper:

```sh
bash scripts/install-launch.sh
```

Normal recovery/activation then becomes:

```sh
vantasm launch
```

`vantasm launch` is intentionally a convergence command, not merely a process starter. It:

- reloads the Surgeon when the local authority/config map changed
- verifies or starts the control plane
- reconciles the Cloudflare tunnel and stable bridge publication
- runs the Generator pack's real `pack_activation.py --apply --start` when present
- probes Vantasm, LokivelliSpeech, T3MP3ST, and Dragon Ball
- ensures the Vantasm watcher remains active
- exits PASS only when all required probes pass; unresolved items remain truthful HOLDs

The wrapper preserves the pre-existing Vantasm CLI as `$FORGE_SURGEON_HOME/vantasm-core`. Every command other than `launch` is delegated unchanged to that existing CLI. This avoids overwriting a newer device-local control implementation.

The command is designed to be idempotent: repeated runs reconcile current state rather than intentionally duplicating services or configuration.


## Bounded operator mode

For an owner-authorized device where an MCP builder seat is expected to carry repairs through to completion, Vantasm can install a bounded operator profile:

```sh
bash scripts/enable-operator-mode.sh
```

This does **not** grant arbitrary shell access and does not expose the Vantasm control directory to the MCP seat. It authorizes the configured Forge roots and registers explicit safe execution profiles for:

- `vantasm launch`
- Generator pack activation
- LokivelliSpeech Kokoro install/start/stop/doctor/smoke
- pytest / unittest
- local git status, diff, add, and commit

The intended operator loop is:

```text
inspect -> snapshot -> repair -> restart -> test -> verify -> reconcile -> receipt
```

The builder should continue that loop without owner handoff while actions remain inside authorized roots and registered profiles.

Owner interaction is reserved for boundaries that genuinely require it, including external credentials or OAuth, Android permissions, destructive/high-impact changes, expansion of authorized roots, and publication/push decisions.

`git push` is intentionally not registered by operator mode. Local source repair and commit may be completed autonomously; publication remains an explicit owner boundary.
