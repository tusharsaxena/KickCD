# 05 — Execution Plan (Remediation)

**Addon:** Ka0s KickCD · **Date:** 2026-07-18 · **Standard:** v2.7.0 (2026-07-17)

Ordered, checkable steps to close `02_DEVIATIONS.md`, grouped into sprints. Each step names its deviation ID(s). This is the hand-off to the separate remediation engagement — the audit itself changes no code.

**Global gate (every sprint):** `lua tests/run.lua` green **and** `luacheck .` clean before the sprint is considered done (testing, versioning-git). No commits on red. Do **not** bump the version or touch git staging unless the user asks (repo hard rules).

Ordered cheapest-first so the quick MUST wins land before the larger peel.

---

## Sprint 1 — Chat-line + notice text fixes (cheap MUST wins)

- [ ] **KCD-25** — `core/KickCD.lua:227` remove trailing `:` and the ` — `; render the canonical `<tag> v<version> slash commands (…)` header.
- [ ] **KCD-25** — `core/KickCD.lua:243` → `"debug subcommands"` (no colon).
- [ ] **KCD-25** — `core/KickCD.lua:860` → `"spells subcommands"` (no colon).
- [ ] **KCD-25** — add a headless test asserting no help/subheader line ends in `:`.
- [ ] **KCD-28** — `locales/enUS.lua:165` set the canonical text `cannot open settings during combat — Blizzard's category-switch is protected`; grey-code the body (keep the cyan `[KCD]` tag).
- [ ] Gate: tests green, lint clean.

## Sprint 2 — Standards-reference placements (docs-only MUST)

- [ ] **KCD-26** — `CLAUDE.md`: rename heading to `## Standards compliance (read first)`; append the "when in doubt…" closing line; keep it right after the adherence line.
- [ ] **KCD-27** — `docs/agent-context.md`: add the conform-to-standard rule as the **first** `## Hard rules` bullet (linking `../CLAUDE.md` "Standards compliance"); retitle the H1 to an agent-context title.
- [ ] Verify all four documentation-§6 places now read consistently (TOC `X-Standard`, README badge, CLAUDE.md section, agent-context first hard rule).
- [ ] Gate: lint clean (docs-only; tests unaffected).

## Sprint 3 — Peel `settings/Panel.lua` under the cap (larger MUST)

- [ ] **KCD-24** — create `settings/Panel_Widgets.lua`; move the widget-maker helpers + their `refreshers` registrations verbatim (published on the same `NS.Panel`/`Helpers` table).
- [ ] **KCD-24** — create `settings/Panel_Render.lua`; move `RenderUnitPanel`, group rendering, two-column pairing, and the schema-error printer.
- [ ] **KCD-24** — `settings/Panel.lua` retains register + landing page + header (AceGUI Defaults button) + `RefreshAllPanels` + `RestoreDefaults`/`RestoreAllDefaults`.
- [ ] **KCD-24** — add both new files to the TOC `# Settings` block **before** the per-tab files (dependency order, toc-file-§5).
- [ ] **KCD-24** — confirm each resulting file is under 1500 LOC (`wc -l settings/*.lua`); add/keep covering tests for any pure helper moved.
- [ ] Gate: tests green (panel + schema suites), lint clean; in-game smoke of the settings panel per `docs/smoke-tests.md` (frame render + Defaults reset are not headless-coverable).

## Sprint 4 — Library hygiene (SHOULD; user decision)

- [ ] **KCD-29** — surface the `library-stack-§1`-vs-`§3` call to the user. On approval, **prune** `libs/AceTimer-3.0/` (recommended) or adopt+load AceTimer.
- [ ] **KCD-19** — no action; confirm the on-notice header comments on `modules/Castbar.lua` and `modules/IconGrid.lua` are still accurate; note the Castbar peel as a future item if it approaches 1500.
- [ ] Gate: tests green, lint clean.

---

## Done criteria

- MUST deviations KCD-24, KCD-25, KCD-26, KCD-27, KCD-28 closed and evidenced.
- KCD-29 resolved per the user's §1-vs-§3 decision; KCD-19 confirmed as a documented watch item.
- `lua tests/run.lua` green, `luacheck .` clean, `docs/test-cases.md` regenerated and the README `[tests]` badge updated in the same change **if** the suite count moved (testing-§5).
- A fresh `standards-audit` run (new dated folder) shows no open MUST deviations.
