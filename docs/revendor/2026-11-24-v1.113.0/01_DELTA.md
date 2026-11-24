Delta: LibKa0s v1.112.0 -> v1.113.0

Recorded with the re-vendor commit. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.113.0 LibKa0s testkit tools` (tag commit cded10bb, a local tag, not yet on origin; expected for this run). Run under Ka0sAddonsCommonTasks `docs/2026-11-24-FEEDBACK_BATCH/R2_SMOKE_FEEDBACK.md`, item FB2-KC-01 (the copy, provenance, icon-declaration and prune mechanics of `/dev-copilot:wow-revendor-libka0s`; the adoption interview and issue filing are skipped by the run's instructions, and its decisions D1-D3 pre-decide adoption).

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.112.0 before the roll.
- Library range: `git -C ../LibKa0s diff --stat v1.112.0 v1.113.0 -- LibKa0s testkit`: `LibKa0s/Sim.lua` and `LibKa0s/WidgetsDropdown.lua` only; the kit did not move.

## 3b/3c Per-file minors that moved (old = this addon, new = v1.113.0)
```
Sim.lua               old: MINOR 4            new: MINOR 5
WidgetsDropdown.lua   old: DROPDOWN_MINOR = 3 new: DROPDOWN_MINOR = 4
```
Kit revision: 60 -> 60.

## Blockers (fixed in the re-vendor commit)
- Sim minor 5 shows the step panel on every successful Start, after prepare. `Host.Prepare` (modules/Sim.lua) opened it itself, so a start asked twice: `tests/test_sim_session.lua`'s "Sim start" case (the panel asked once) went red at 2. Prepare no longer shows it, and the pin (close mark hidden, off UISpecialFrames) rides a listener on the start's notify, the first moment the frame exists on every start path.

## 3i Icons
- `LibKa0s icons:` line kept as written. Prune: the undeclared icons and the 362 sound files (no `LibKa0s sounds:` line, so none).
