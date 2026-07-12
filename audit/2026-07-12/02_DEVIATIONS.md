# 02 — Deviations

**Addon:** Ka0s KickCD · **Date:** 2026-07-12 · **Standard:** v1.0.0 (2026-07-12) · **Prefix:** `KCD-`

Severity: **MUST** = non-negotiable (bug); **SHOULD** = strongly preferred (deviation needs a code comment justifying it). IDs are stable across runs — a recurring deviation keeps its ID. Evidence for every row is in `03_EVIDENCE.md`; remediation is keyed to these IDs in `04`/`05`.

## MUST failures

| ID | § | Severity | Deviation | Fix direction |
|----|----|----------|-----------|---------------|
| KCD-01 | §4.1, AP-1 | MUST | Global `_G.KickCD` used as the addon namespace; every file does `KickCD = KickCD or {}`, no `local addonName, NS = ...` header. | Migrate to the private `NS` bootstrap (`local addonName, NS = ...`); drop the `_G[addonName]` table. Large, cross-cutting — treat as its own sprint. |
| KCD-02 | §14A, AP-24 | MUST | No `tests/` harness; no headless TDD substrate; §14A/§17 commit gate unsatisfiable. | Add `tests/{run.lua,loader.lua,wow_mock.lua,test_*.lua}` per §14A.1; cover schema validation, migrations, spec-token normalization, formatters. Bus mock MUST key by target (§4.4/AP-33). |
| KCD-03 | §14 | MUST | No `.luacheckrc` at repo root. | Add the standard `.luacheckrc` (std lua51, exclude `libs/ audit/ tests/`, per-repo globals incl. `KickCDDB`); run `luacheck .` to 0 errors. |
| KCD-04 | §13, AP-7 | MUST | No `.pkgmeta` at repo root. | Add `.pkgmeta` with `package-as: KickCD`, no `externals:`, ignore `audit/ docs/ tests/ .luacheckrc` etc. |
| KCD-05 | §1.2, AP-16 | MUST | `modules/IconGrid.lua` = 1753 LOC, over the 1500 hard cap. | Peel into cohesive sub-files (e.g. layout / anchor math / render) staying flat in `modules/`. |
| KCD-06 | §12, AP-18 | MUST | No on-screen debug console; all debug output goes to the chat frame, but the addon has on-screen displays. | Build a `modules/DebugLog.lua` console (§12.1–12.6): DIALOG-strata window, monospace font, timestamped `[tag]` lines, Copy/Clear, gated zero-alloc sink. |
| KCD-07 | §12.5 | MUST | Debug enabled-state persisted in SavedVariables (`db.profile.debugLog`), seeded into `self._debugLog`. | Move the flag to session-only `NS.State.debug` (default off, never in SV, reset each `/reload`); route all writes through one `SetEnabled` seam. |
| KCD-08 | §4.4 | MUST | Bus messages lack the `Ka0s_<Addon>_` prefix (`KickCD_SPELL_STATE`, `_CONFIG_CHANGED`, `_PROFILE_CHANGED`, `_GRID_LAYOUT`, `_COMBAT_STATE`). | Rename to `Ka0s_KickCD_*`; update every sender, every `RegisterMessage`, and `docs/message-bus.md`. |
| KCD-09 | §4.4, AP-32 | MUST | `settings/Spells.lua` registers `KickCD_PROFILE_CHANGED` / `KickCD_CONFIG_CHANGED` on the shared `KickCD` addon object as `self` — the last-registrant-wins clobber shape. | Give the Spells panel its own receiver target via a `NS.NewBusTarget()` factory (or a dedicated AceEvent embed); never register on the shared addon object. |
| KCD-10 | §11, AP-10 | MUST | Deprecated `GetSpecialization` / `GetSpecializationInfo` / `GetSpellInfo` called directly outside Compat in 4 files. | Add `Compat.GetSpecialization()` / `Compat.GetSpecializationInfo()` shims; route all call sites through `Compat.*`. |
| KCD-11 | §2.1, AP-28 | MUST | TOC missing `## X-Standard:` (declares adherence to the standard). | Add `## X-Standard: https://github.com/tusharsaxena/WowAddonStandards` in the §2.1 field order. |
| KCD-12 | §2.1 | MUST | Addon is published (CurseForge 1530802) but TOC lacks `## X-Curse-Project-ID:` and `## X-Wago-ID:`. | Add both IDs (Wago too, or publish there); place per §2.1 order. |
| KCD-13 | §15.2, AP-26 | MUST | Root `CLAUDE.md` is the full agent brief, not a stub. | Move the brief into `docs/` (e.g. `docs/agent-context.md` / expand `docs/ARCHITECTURE.md`); replace root `CLAUDE.md` with a short stub naming the tier + standard URL + pointer into `docs/`. |
| KCD-14 | §15, §15.3 | MUST | Root ships `ARCHITECTURE.md`; root should ship only README + CLAUDE stub + LICENSE. | Move to `docs/ARCHITECTURE.md` with the §15.3 section set (incl. bus-message table, slash table from COMMANDS). |
| KCD-15 | §1.4, §6.5, AP-25 | MUST | Runtime logo `.tga` + source `.jpg` live in `media/screenshots/`, not the typed `media/logos/`. | Create `media/logos/`, move `kickcd.logo.tga` + `kickcd.logo.jpg` there; update the `MAIN_LOGO` path in `settings/Panel.lua`. |
| KCD-16 | §7.4 | MUST | Chat tag is a file-local `PREFIX` in `Util.lua` and hand-duplicated in `settings/Panel.lua`, not a single shared `NS.PREFIX`. | Expose `NS.PREFIX` (or `KickCD.PREFIX`) once; have `Util.print` and every call site reference it; delete the duplicate literal. |
| KCD-17 | §15.1 | MUST | README badge row omits the Ka0s WoW Addon Standard badge/link. | Add a standard badge/line linking `https://github.com/tusharsaxena/WowAddonStandards` in the badge row. |
| KCD-23 | §3.3 | MUST | `libs/` vendors 6 libs never loaded/`LibStub`'d — AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab (dead weight §3.3 names explicitly). | Delete the unused lib folders; keep only what the TOC loads. |

## SHOULD failures

| ID | § | Severity | Deviation | Fix direction |
|----|----|----------|-----------|---------------|
| KCD-18 | §2.1, §2.5 | SHOULD | TOC omits `## OptionalDeps:`; `## Author: Ka0s` instead of canonical `add1kted2ka0s`; trailing blank lines after the file listing. | Add `## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0`; set Author; end file with a single trailing newline. |
| KCD-19 | §1.2 | SHOULD | `modules/Castbar.lua` (1422) and `settings/Panel.lua` (1266) are in the 1000–1500 "on notice" band. | Plan a peel (Panel → `Panel.lua` + widget primitives; Castbar → widget build vs. update). Not urgent; keep under 1500. |
| KCD-20 | §5.1, §2.2 | SHOULD | Schema-version integer is named `dbVersion` and stored per-profile, not `schemaVersion` in the global namespace. | Rename to `schemaVersion`, move to `db.global`; keep the (already-present) `Database` migration runner reading it. |
| KCD-21 | §15.1 | SHOULD | README has no `## How it works` section (uses custom `## Critical settings` blocks); relative order of canonical optional sections is otherwise preserved. | Add a `## How interrupt tracking works` narrative (visibility gate + secret-value pipeline); keep or fold the `Critical settings` prose beneath it. |

**Counts — MUST: 18 · SHOULD: 4.**

Anti-pattern list (§19) coverage: hits on AP-1, AP-7, AP-10, AP-16, AP-18, AP-24, AP-25, AP-26, AP-28, AP-32. Not triggered: AP-2/3/4/5/6 (localization + options + slash patterns are compliant), AP-8/9/11/12/13/14/15/17/19/20/21/22/23/27/29/30/31/33.
