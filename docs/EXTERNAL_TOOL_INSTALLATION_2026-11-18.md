# External Tool Installation — 2026-11-18

This is the executable companion to the external-tool registry. It preserves the existing Vantasm authority model and does not claim phone installation until the installer is actually executed on the target Termux runtime.

## One-command phone path

From the existing Vantasm checkout:

```sh
bash scripts/install-external-tools.sh
bash scripts/verify-external-tools.sh
```

The installer writes timestamped receipts under:

```text
~/forge-tools/receipts/
```

and keeps third-party source checkouts under:

```text
~/forge-tools/src/
```

Python tools use dedicated virtual environments under `~/forge-tools/venvs/`; npm tools use a private prefix under `~/forge-tools/npm/`; Rust tools use `~/forge-tools/cargo/`. The script does not perform a blanket `pkg upgrade` and does not overwrite the system Node runtime to satisfy one package.

## Install targets

The installer attempts executable installation and verification for:

- uv, using a Termux-native package when available;
- md-anything CLI/MCP;
- Download Anything CLI;
- lemmeknow;
- CLI-Anything Hub plus its global meta-skill;
- CLI-Anything-WEB source plus Playwright CLI availability;
- rust-anything plus its upstream config-preserving `setup`;
- OpenClaude when Node satisfies upstream minimum 24.22.1;
- NVIDIA SkillEvaluator base package when Python is 3.12–3.14;
- Google Stitch skills;
- Appwrite agent skills;
- Claude-BugHunter skill bundle into detected supported agent harnesses.

It also keeps local inspectable source copies for the reference/catalog projects and the above tools.

## Expected HOLDs are explicit

Some entries are not universal Termux executables:

- **Appwrite server**: self-hosting requires a working Docker daemon. Appwrite agent skills can be installed independently, but that is not the Appwrite server.
- **harness-anything**: source can be installed locally, but several harnesses depend on desktop applications or Windows COM.
- **awesome-mcp-servers**: a catalog, not one MCP server.
- **cursor/plugins**: a plugin catalog/source tree; Cursor desktop is not supplied by Termux.
- **jQuery**: belongs inside individual web projects. The installer preserves source but does not inject it globally into unrelated repos.
- **OpenClaude**: upstream currently requires Node >=24.22.1. If the phone has an older Node, the installer records HOLD rather than silently replacing a runtime other projects may depend on.
- **SkillEvaluator full Tier 3**: base CLI installation is separate from Docker/provider-backed live evaluation.

## Vantasm profiles

After the scripts are present on the phone, register bounded profiles with:

```sh
bash scripts/enable-external-tool-profiles.sh
```

This adds `external_tools_install` and `external_tools_verify` to the existing builder seat and adds `~/forge-tools` as an authorized root. It does not grant arbitrary shell access.

## Certification rule

`verify-external-tools.sh` exits nonzero while any required executable/runtime check remains HOLD. Source clone presence is recorded separately from executable runtime readiness. No source-only checkout is labeled installed/live as a runtime.
