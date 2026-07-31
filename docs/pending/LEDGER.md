# Pending-items ledger

Maintained by `/wow-addon:pending-audit`. Each row records a decision the user
made about one pending item — a TODO/FIXME marker, an unexecuted audit or review
plan step, a doc open question, an open GitHub issue, or a recorded-but-unacted
Claude memory.

The ledger's job is to make decisions **stick**: a settled item must not come
back and ask again, and a "not now" must stay visible without nagging. Items are
matched on **ID + evidence hash** (first 8 chars of `sha1` over the verbatim
evidence text), so if the underlying evidence text changes the item correctly
re-surfaces for a fresh decision even though its ID is unchanged.

## Decision values

| Marker | Value | Meaning | Re-surfaces? |
|---|---|---|---|
| 🟢 | `done` | Implemented this run | No — closed |
| 🔵 | `wont-do` | User decided it will never be done | No — closed |
| 🟡 | `deferred` | Not now; still on the books | Yes, as a collapsed count |

Green is resolved. Blue is a deliberate, settled close — declining to do
something is a decision, not a failure. Yellow is the only row type still asking
for attention, so a column of yellow is this file telling you what's left. There
is deliberately no red: nothing here is an error state.

Always read the **word**, not the marker — the word is the data (and what
`grep wont-do` finds), the marker is just the affordance.

## Decisions

| ID | Evidence hash | Source | Decision | Date | Rationale |
|---|---|---|---|---|---|
| PLAN-01 | `b4620abd` | `docs/audits/2026-07-18/05_EXECUTION_PLAN.md` (KCD-29) | 🟢 done | 2026-07-31 | Pruned `libs/AceTimer-3.0/`, the audit's recommendation. Unloaded and unreferenced — scheduling is `C_Timer.After` throughout — so `library-stack-§3` ("vendor what you use") wins the §1-vs-§3 tension. `docs/ARCHITECTURE.md` and `docs/module-map.md` updated to record why. |
| PLAN-02 | `f300d1f6` | `docs/audits/2026-07-18/05_EXECUTION_PLAN.md` (KCD-25) | 🟢 done | 2026-07-31 | Added `tests/test_slash_style.lua` (6 cases) asserting no `/kcd` help or sub-header line ends in `:`. Drives the real verbs, so new sub-headers are covered automatically. Mutation-tested: reintroducing a colon fails the suite. Closes the last open piece of KCD-25. |
| PLAN-03 | `1cc69107` | `docs/audits/2026-07-18/05_EXECUTION_PLAN.md` (KCD-19) | 🟢 done | 2026-07-31 | Peeled `modules/Castbar.lua` at 1489/1500 LOC. `Castbar:Reskin` moved to the new `modules/Castbar_Skin.lua`; Castbar.lua is now 1239. Seam chosen was the one its own header comment nominated. **Needs an in-game smoke test** before merging. |
| CODE-02 | `98da22ee` | `modules/Castbar.lua:628` (F-015) | 🟢 done | 2026-07-31 | User chose to implement during the peel rather than keep deferring. `Reskin` split into `ReskinStructure` (guarded by a signature over exactly the config fields it reads) and `ReskinColors` (always runs), so a 50 ms colour-picker drag no longer re-runs ~40 structural widget calls. Signature folds in the resolved dimensions so auto-size keeps working. |
| CODE-01 | `a029cfb9` | `modules/IconGrid_Render.lua:51` (F-016) | 🟢 done | 2026-07-31 | Cache-and-compare added: `BuildCurves` now skips a unit whose `readyAlpha` / `cooldownAlpha` / `cooldownTint` are unchanged, so a border / font / layout / glow edit stops recreating three curves. |
| CODE-03 | `faf336d5` | `modules/IconGrid_Render.lua:56-58` | 🟢 done | 2026-07-31 | Curves promoted from module-level to per-unit (`_curves[unit]`, resolved via `curvesFor`). Closes a real gap: an **unlinked** focus was silently rendering with target's alpha/tint despite the issue #6 design promising independent appearance. `curvesFor` deliberately does not fall back to target. |
| ISS-04 | `dcb99cd4` | GitHub issue #4 — "Icon Zoom" | 🟡 deferred | 2026-07-31 | "Defer for now, augment the github issue description." Code untouched. Issue body expanded with the current `SetTexCoord` implementation, the schema row, and two concrete suspects (per-side vs total crop convention; the `0.10` schema default vs `0.08` in-code fallback), so the next pass starts from evidence rather than a two-word title. |
| ISS-07 | `4242f403` | GitHub issue #7 — non-interruptible casts showing in "target casting interruptible" mode | 🟡 deferred | 2026-07-31 | Not now. Cost stated at decision time: the bug stays live for users. |
| ISS-03 | `141ffefc` | GitHub issue #3 — "Partial Charge Swipe" | 🟡 deferred | 2026-07-31 | Not now. Charge-aware swipe would have to route through `SetCooldownFromDurationObject` (secret-value territory). |
| ISS-08 | `19700487` | GitHub issue #8 — Elemental Shaman / French client | 🟡 deferred | 2026-07-31 | "Leave open, waiting for the user to respond on the github issue." The code fix already shipped in `0a696cf` (numeric specID keys) and the rule is codified in `docs/agent-context.md`; only the reporter's confirmation is outstanding. Do **not** close it unprompted. |
| ISS-09 | `a1507973` | GitHub issue #9 — move time-varying icon render onto the cooldown ticker | 🟡 deferred | 2026-07-31 | Not now — the issue is itself titled `[Optional]` and argues the case is structural rather than framerate, and this run already had the Castbar peel plus three `IconGrid_Render` changes touching the same ticker code. |
| ISS-05 | `d9b40779` | GitHub issue #5 — track items alongside spells | 🟡 deferred | 2026-07-31 | Not now. Genuine scope expansion (parallel `C_Item` cooldown path + DB shape change). `README.md:171` already tells users it's spells-only, so no doc drift meanwhile. |
| ISS-02 | `ee855b62` | GitHub issue #2 — cast bar background animation | 🟡 deferred | 2026-07-31 | Not now. Lands squarely in `modules/Castbar.lua`, whose seam was being cut in this same run — cleaner to land the peel first and build into the settled layout. |
| ISS-01 | `3c6acbaf` | GitHub issue #1 — more glow customization | 🟡 deferred | 2026-07-31 | Not now. The issue has no stated requirement beyond its title, so any implementation would be a guess at which LibCustomGlow knobs to surface. |
