# EAR-REA-CHA-CHA-CHA integration

EAR-REA-CHA-CHA-CHA is an optional workflow consumer of Vantasm / Forge Surgeon.

The Surgeon core remains vendor-neutral and workflow-neutral.

## Intended relationship

EAR / REA stages can use Surgeon to:
- inspect authorized project roots,
- read dependency and runtime state,
- collect receipts and diffs,
- freeze candidate artifacts,
- test candidate states,
- record reproducible evidence.

CHA stages can use the same safe boundary to:
- select candidate features,
- reinforce weak points using separately authorized software,
- finalize and verify a chosen candidate.

## Boundary

Do not hard-code EAR-REA-CHA-CHA-CHA project paths into Vantasm.
A user supplies or authorizes roots on their own device.

Do not give the workflow unrestricted shell access.
Use the same registered tools, expected-state protection, HOLD rules, redaction, quarantine, receipts, and rollback controls as every other seat/workflow.

## Portable adapter target

A future adapter may map EAR / REA / CHA stage events onto Surgeon receipts and Vantasm UI nodes. That adapter belongs under `integrations/`, not inside the Surgeon authorization core.
