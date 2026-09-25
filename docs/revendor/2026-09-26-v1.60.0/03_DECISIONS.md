# 03 — Decisions: LibKa0s v1.58.0 -> v1.60.0

No interview was held. Every candidate was decided in advance by the diagnostics rollout plan
(`Ka0sAddonsCommonTasks/docs/2026-09-25-DIAGNOSTICS_COMMAND/03_EXECUTION_PLAN.md`, M3) and its owner
rulings (`OWNER_RULINGS.md`, DR-OW-01 Q1 and DR-OW-03). The plan says to file no decline issue for
these, so none is filed.

| # | Candidate | Decision | Where it lands |
|---|---|---|---|
| B1 | The diagnostics helper | **adopt**, later in this pass | DR-KC-03 (`modules/Diagnostics.lua` on the helper) |
| B2 | `diagnostics` as a registered verb | **adopt**, later in this pass | DR-KC-03 |
| B3 | DragHandle close mark | **never** for KickCD, by owner ruling (Q1, X-03). No issue filed, per the plan | none |

The buffer change is not an adoption: it reached the addon on the copy (class A).
