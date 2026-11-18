# External Tool Integration Plan — 2026-11-18

This is additive to the existing Vantasm architecture. It does not replace Forge Surgeon, its seat authorization, expected-state checks, HOLD hierarchy, receipts, quarantine, or registered safe-execution profiles.

The machine-readable source for this pass is `integrations/external-tool-registry-2026-11-18.json`.

## Placement rule

External projects fall into five lanes:

1. **Acquisition / identification / normalization** — `download-anything`, `lemmeknow`, and `md-anything` may feed staged inputs to controlled workflows. They do not authorize execution or overwrite source authority.
2. **Adapter generation** — `CLI-Anything` and experimental `CLI-Anything-WEB` can produce operator-facing adapters. Generated adapters remain behind explicit Vantasm safe profiles and existing application contracts.
3. **Runtime / verification** — `uv` is a candidate Python environment/tool substrate and NVIDIA SkillEvaluator is a candidate skill quality/security/compatibility gate. A partial SkillEvaluator run is not a Vantasm PASS when required scanners or live evaluation are unavailable.
4. **Optimization** — `rust-anything` may be used on staging/copies to record behavior, port selected paths, diff behavior, benchmark, shadow, and gate. The original remains the source of truth until equivalence evidence is complete.
5. **Operators / references / architecture candidates** — OpenClaude is a replaceable operator/client; Cursor plugins and Stitch skills are packaging references; awesome-mcp-servers is a discovery catalog; harness-anything is an architecture reference; Claude-BugHunter belongs in an authorized security lane; Appwrite requires a separate backend architecture decision; jQuery is conditional only.

## Required adoption sequence

`need -> discover -> inspect upstream -> license/maintenance review -> isolate -> configure a bounded profile -> test -> verify -> receipt -> ACCEPT/HOLD/REJECT`

Discovery is never authority. Installation is never proof of integration. A passing upstream test suite is never proof that a tool is live on the target Termux device.

## Current Vantasm source HOLD found during this audit

On the current default branch, `surgeon/server.py` imports `from .core import SurgeonCore`, while `surgeon/core.py` is absent from the repository tree. The existing `fix/install-source-parity` branch adds installer/doctor/parity files but does not add `surgeon/core.py`.

Therefore the public repository source is **HOLD for clean-source runtime certification** until the missing core implementation is restored from an authoritative donor or otherwise reconstructed and the full tests/runtime probes are rerun. This finding does not rewrite or invalidate device-local evidence from a separate installed copy.

## No automatic install in this pass

This pass records the integration map only. None of the listed upstream tools is claimed installed, configured, wired, live, or tested on the target phone by this document.
