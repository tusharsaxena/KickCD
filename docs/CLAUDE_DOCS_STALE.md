# Existing legacy docs are partially stale

`legacy/v1/TECHNICAL_DESIGN.md`, `legacy/v1/EXECUTION_PLAN.md`, `legacy/v1/REQUIREMENTS.md`, `legacy/v1/RESEARCH.md`, `legacy/v1/UAT.md` (in this `docs/` tree under `legacy/v1/`) predate the cast-bar removal and the 12.0 secret-value handling. They still describe the original three-module architecture (Tracker + Castbar + IconGrid) and the FR-1 / FR-3 cast-bar requirements that no longer apply. Use them for context on the original design intent, not as a source of truth for current behavior. [`ARCHITECTURE.md`](../ARCHITECTURE.md) at the repo root reflects current reality.

The `legacy/v2/` companion docs (`PE_REVIEW.md`, `CHANGES_PE_REVIEW.md`, `EXECUTION_PLAN_PE_REVIEW.md`) capture the principal-engineer review that drove the v2 refactor — they are also historical record at this point; the changes have all landed.

When updating module-level header comments, prefer accurate descriptions over `See docs/...` references that may now be wrong.

