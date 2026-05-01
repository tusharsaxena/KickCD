# Existing legacy docs are partially stale

`legacy/TECHNICAL_DESIGN.md`, `legacy/EXECUTION_PLAN.md`, `legacy/REQUIREMENTS.md`, `legacy/RESEARCH.md`, `legacy/UAT.md` (in this `docs/` tree under `legacy/`) predate the cast-bar removal and the 12.0 secret-value handling. They still describe the original three-module architecture (Tracker + Castbar + IconGrid) and the FR-1 / FR-3 cast-bar requirements that no longer apply. Use them for context on the original design intent, not as a source of truth for current behavior. [`ARCHITECTURE.md`](../ARCHITECTURE.md) at the repo root reflects current reality.

When updating module-level header comments, prefer accurate descriptions over `See docs/...` references that may now be wrong.

