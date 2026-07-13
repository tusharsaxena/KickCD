# 05 — Execution Plan

Ordered, checkable remediation steps grouped into sprints, each tied to its deviation ID(s). This is the hand-off to the separate remediation engagement. Sprints are ordered by dependency: scaffolding first (so the commit gate becomes real), the big namespace migration last. Each step is a green unit — land it only with `lua tests/run.lua` passing and `luacheck .` clean once those exist (§14A/§17).

Suggested commit granularity: one bullet ≈ one commit (or a tight cluster), except the namespace migration which is staged by file group.

---

## Sprint 0 — Scaffolding & metadata (no runtime change) → KCD-03, KCD-04, KCD-11, KCD-12, KCD-15, KCD-18, KCD-23

- [ ] **KCD-03** Add root `.luacheckrc` (§14 template + this addon's globals; temporary `globals = { "KickCD" }` with a remove-after-KCD-01 comment). Run `luacheck .` and drive to 0 errors.
- [ ] **KCD-04** Add root `.pkgmeta` (`package-as: KickCD`, no `externals:`, ignore `audit/ docs/ tests/ reviews/ .luacheckrc`).
- [ ] **KCD-23** Delete `libs/{AceBucket-3.0,AceComm-3.0,AceHook-3.0,AceLocale-3.0,AceSerializer-3.0,AceTab-3.0}`; confirm nothing loads them.
- [ ] **KCD-11 / KCD-12 / KCD-18** Rewrite `KickCD.toc` metadata into §2.1 order; add `X-Standard`, `X-Curse-Project-ID: 1530802`, `X-Wago-ID`, `OptionalDeps`; set `Author: add1kted2ka0s`; single trailing newline.
- [ ] **KCD-15** `git mv` logo `.tga` + `.jpg` to `media/logos/`; update the path + comment in `settings/Panel.lua`; verify the landing-page logo renders in-game.

**Exit:** `luacheck .` clean; addon loads; logo renders; TOC validates in-game.

## Sprint 1 — Test harness & lint gate → KCD-02

- [ ] **KCD-02** Add `tests/{run.lua,loader.lua,wow_mock.lua}` per §14A.1. `loader.lua` loads sources in TOC order with a mock env; `wow_mock.lua` stubs `C_Spell`, `Unit*`, `Settings.*`, `LibStub`(AceDB/AceAddon), and a self-returning no-op frame.
- [ ] **KCD-02** Write first suites: `test_util.lua` (color unpack, `NormalizeSpecToken`, throttle), `test_schema.lua` (`ValidateSchema` count, path resolution), `test_database.lua` (defaults shape, migration no-op).
- [ ] **KCD-02 / AP-33** Bus mock in `wow_mock.lua` MUST key callbacks by `(message, target)` and fan `SendMessage` to all targets; add `test_bus.lua` asserting two receivers of one message both fire.
- [ ] Wire `lua tests/run.lua` (exit non-zero on failure) into the pre-commit routine alongside `luacheck .`.

**Exit:** `lua tests/run.lua` green; the §17 commit gate is now enforceable for every later sprint.

## Sprint 2 — Compat routing & conventions (test-first) → KCD-10, KCD-08, KCD-16, KCD-20

- [ ] **KCD-10** Add `Compat.GetSpecialization` / `Compat.GetSpecializationInfo`; repoint the 10 direct call sites (`core/KickCD.lua:555,557`; `modules/Cooldowns.lua:78,81`; `modules/IconGrid.lua:286,288`; `settings/Spells.lua:88,90,332,334`). Cover with `test_compat.lua` (mocked `C_SpecializationInfo`).
- [ ] **KCD-08** Rename all five bus messages to `Ka0s_KickCD_*` across senders, receivers, and `docs/message-bus.md`, in one atomic commit. Bus test asserts no orphaned receiver.
- [ ] **KCD-16** Expose `KickCD.PREFIX` once; `Util.print` + `settings/Panel.lua:123` reference it; delete the duplicate literal.
- [ ] **KCD-20** Move the schema version to `db.global.schemaVersion` (rename from per-profile `dbVersion`); one-shot migration copies existing value; point `MigrateProfile` at it. Cover with a migration test.

**Exit:** tests green; message rename verified end-to-end; single-source prefix.

## Sprint 3 — Message-bus receiver & debug console → KCD-09, KCD-06, KCD-07

- [ ] **KCD-09** Add `NS.NewBusTarget()`; move `settings/Spells.lua:916-925` registrations onto a Spells-owned `__ev` target. Bus test proves Spells + a module both receive the same message.
- [ ] **KCD-06** New `modules/DebugLog.lua` console (§12.1–12.6): DIALOG window, `ScrollingMessageFrame`, Copy/Clear, header toggle, `SKIN`/`ApplySkin` seam. Ship JetBrains Mono under `media/fonts/` (+ license), register with LSM, `FONT_MONO` constant. Add `FormatPlain`/`FormatColored` + `test_debuglog.lua`.
- [ ] **KCD-07** Introduce session-only `KickCD.State.debug`; route writes through `DebugLog:SetEnabled`; remove `debugLog` from `DEFAULT_PROFILE` and the `self._debugLog` SV seeding (`core/KickCD.lua:52-55,171-187`); repoint `/kcd debug on|off|toggle` and the General checkbox. Redirect existing `/kcd debug spells|castbar|interrupt` dumps into the console.

**Exit:** debug output lands in the on-screen console, flag resets each `/reload`, Spells panel owns its bus target.

## Sprint 4 — File peel → KCD-05 (and opportunistic KCD-19)

- [ ] **KCD-05** Peel `modules/IconGrid.lua` (1753) into flat siblings (`IconGrid.lua` + `IconGrid_Layout.lua` + `IconGrid_Render.lua`); add to TOC in order; publish each via `NS.IconGrid or {}`. Add unit coverage for the extracted pure layout math; re-run `docs/smoke-tests.md`.
- [ ] **KCD-19 (SHOULD)** If in scope, peel `settings/Panel.lua` and `modules/Castbar.lua` toward < ~1000; otherwise leave a code comment noting the on-notice status.

**Exit:** no source file > 1500 LOC; smoke tests pass.

## Sprint 5 — Docs restructure → KCD-13, KCD-14, KCD-17, KCD-21

- [ ] **KCD-14** `git mv ARCHITECTURE.md docs/ARCHITECTURE.md`; ensure §15.3 sections incl. bus-message table + slash table from `COMMANDS`; fix links.
- [ ] **KCD-13** Move the working-notes brief into `docs/`; replace root `CLAUDE.md` with the §15.2 stub (tier + standard URL + docs pointer).
- [ ] **KCD-17** Add the Ka0s-Standard badge/line to the README badge row.
- [ ] **KCD-21** Add `## How interrupt tracking works`; nest/keep `Critical settings` beneath it in canonical order.

**Exit:** root ships only README + CLAUDE stub + LICENSE (+ dotfiles); README matches §15.1.

## Sprint 6 — Namespace migration (largest, last) → KCD-01

- [ ] **KCD-01** Convert to private `NS`, file-group by file-group behind green tests: (a) `core/*`, (b) `defaults/` + `locales/`, (c) `modules/*`, (d) `settings/*`. Each file: `local addonName, NS = ...` header; `KickCD.Foo` → `NS.Foo`; drop `KickCD = KickCD or {}` and `_G.KickCD = addon`. `NewAddon(NS, addonName, ...)`, keep `NS.addon`.
- [ ] Remove the temporary `globals = { "KickCD" }` from `.luacheckrc`; `luacheck .` clean.
- [ ] Run the full `docs/smoke-tests.md` matrix (cold install, visibility modes, lock/drag, cast bar, spec/talent/pet rebuild, secret-value safety, profiles).

**Exit:** no `_G[addonName]` namespace; tests + lint green; smoke suite passes.

---

## Traceability

| Sprint | Deviation IDs |
|--------|---------------|
| 0 | KCD-03, KCD-04, KCD-11, KCD-12, KCD-15, KCD-18, KCD-23 |
| 1 | KCD-02 |
| 2 | KCD-10, KCD-08, KCD-16, KCD-20 |
| 3 | KCD-09, KCD-06, KCD-07 |
| 4 | KCD-05, KCD-19 |
| 5 | KCD-13, KCD-14, KCD-17, KCD-21 |
| 6 | KCD-01 |

All 22 deviations (18 MUST + 4 SHOULD) are scheduled. Sprints 0–1 are prerequisites; 2–5 are largely independent of each other; 6 is deliberately last.
