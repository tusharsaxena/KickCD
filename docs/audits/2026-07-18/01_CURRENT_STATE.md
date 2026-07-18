# 01 — Current State

**Addon:** Ka0s KickCD · **Date:** 2026-07-18 · **Prefix:** `KCD-`
**Audited against:** Ka0s WoW Addon Standard **v2.7.0 (2026-07-17)** — `standards/STANDARDS.md` and every section file it links, plus the `anti-patterns` list.
**Playbook:** `AUDIT.md` (fetched from the standards repo at runtime).
**Prior run:** `docs/audits/2026-07-12/` (audited against v1.0.0; all 22 deviations remediated per that run's `06_EXECUTION_OUTCOME.md`). This run re-measures against the current v2.7.0 standard and reuses the `KCD-` prefix and existing IDs.

This is a **read-only** snapshot. No addon source was modified.

---

## Snapshot by standard section

### layout
- Modular layout present: `core/`, `defaults/`, `settings/`, `locales/`, `modules/`, `media/`, `libs/`, `tests/`, `docs/`. No loose source at root (root = `README.md`, `CLAUDE.md`, `LICENSE`, dotfiles, `KickCD.toc`).
- Casing correct: `libs/` lowercase, Lua files PascalCase, media typed subfolders (`media/logos/`, `media/screenshots/`, `media/fonts/`).
- **LOC cap:** `settings/Panel.lua` = **1641 LOC**, over the 1500 hard cap (KCD-24). `modules/Castbar.lua` = 1473 and `modules/IconGrid.lua` = 1007 sit in the 1000–1500 "on notice" band, both carrying justifying header comments (KCD-19). All other files under 1000.

### toc-file
- Field order matches toc-file-§1: `Interface` (single `120007`), `Title`, `Notes`, `Author: add1kted2ka0s`, `Version`, `IconTexture`, `SavedVariables`, `OptionalDeps`, `DefaultState`, `Category-enUS`, `X-License: MIT`, `X-Standard`, `X-Curse-Project-ID: 1530802`. `X-Wago-ID` is a commented TODO (addon published on CurseForge; not yet on Wago).
- File listing uses `#` section headers in order Libraries → Locales → Core → Defaults → Modules → Settings. Libraries listed **directly** (no `embeds.xml`), compliant with the v2.5.0 rule / anti-pattern #38.

### library-stack
- Mandatory Ace3 libs vendored under `libs/` and committed. `AceTimer-3.0` is vendored but **not** listed in the TOC and **not** used anywhere — the addon schedules via `C_Timer.After` directly (KCD-29).
- Optional libs present and justified: LibSharedMedia-3.0, AceDBOptions/AceConfig (Profiles page), LibCustomGlow-1.0 (ready glow), AceGUI SharedMedia widgets.

### architecture
- Namespace bootstrap: every file opens `local addonName, NS = ...`; no `_G.KickCD` table. `core/KickCD.lua:28` does `NewAddon(NS, "KickCD", …)`.
- Custom printer survives the AceConsole embed: printing routes through `NS.Util.print` (naming-cheatsheet convention), not a bare `NS.Print`.
- Closed message bus: five `Ka0s_KickCD_*` messages; the Spells panel owns a private `NS.NewBusTarget()` receiver.
- Schema-as-single-source present (`NS.Settings.Schema`).

### savedvariables
- `KickCDDB` single global; `schemaVersion` in `db.global`; `core/Database.lua` migration runner with a legacy-`dbVersion` adoption path.

### options-ui
- `Settings.RegisterCanvasLayoutCategory` landing page + subcategories; lazy body build in `OnShow` (`settings/Panel.lua:1607`).
- Defaults button built as an **AceGUI `Button`** (`settings/Panel.lua:346`) — compliant with the v2.7.0 options-ui-§5 rule.
- Panel refresh uses per-widget **updater closures** (`ctx.refreshers`) run by `Helpers.RefreshAllPanels` (`settings/Panel.lua:1300`) — the in-place path of options-ui-§11 (v2.7.0); no full teardown/rebuild-all on mutation.
- **Combat lockdown:** `NS:OpenSettings` gates on combat and refuses (`core/KickCD.lua:917-924`), but the refusal notice is neither grey-coded nor the canonical wording (KCD-28).

### standalone-windows / preview-mode
- Only standalone window is the debug console. Cast bar ships a placeholder preview while unlocked (preview-mode compliant).

### slash-commands
- AceConsole registration; schema-driven `COMMANDS` dispatch; `version` verb reads TOC metadata via `C_AddOns.GetAddOnMetadata`.
- `list`/`get`/`set` use the mandated colour scheme (green header, azure `[page]`, gold key, white value) via a shared `FormatKV`.
- **Trailing colons:** the help header (`core/KickCD.lua:227`), `"debug subcommands:"` (`:243`) and `"spells subcommands:"` (`:860`) end with `:`, violating the no-trailing-colon rule (KCD-25).

### localization
- `NS.L` metatable-fallback module; enUS only; game data matched on `spellID`, not localized names. No localized-string logic branches found.

### events-frames-taint
- AceEvent throughout; combat visibility driven off `PLAYER_REGEN_DISABLED/_ENABLED` (a single-owner flag in `core/State.lua`), per the endorsed transition pattern; secret-safe printer/sink in place.

### compat
- `core/Compat.lua` owns spell/spec/cast-info shims; deprecated spec/spell APIs routed through it.

### debug-logging
- On-screen `modules/DebugLog.lua` console (DIALOG strata, JetBrains Mono, Copy/Clear, header toggle). Session-only `NS.State.debug`. `SetEnabled` seam emits colour-coded ON/OFF ack and an `[Init]` session summary on enable. Settings changes logged once at the schema write seam (`[Set]`, `settings/Panel.lua:100`).

### packaging / lint / testing
- `.pkgmeta` (no `externals:`, ignores docs/tests/dotfiles), `.luacheckrc` present. Headless harness: `lua tests/run.lua` → **108 passed, 0 failed**; `docs/test-cases.md` generated inventory shows **Total 108**, matching the README `Tests-108/108` badge.

### documentation
- Root ships `README.md` (player-facing, canonical section order, five-badge row in correct order), `CLAUDE.md` (stub), `LICENSE`. `docs/` carries the full quartet (`agent-context.md`, `ARCHITECTURE.md`, `testing.md`, `smoke-tests.md`) plus generated `docs/test-cases.md` and topic-detail docs. No `TODO.md`.
- **Standards reference (documentation-§6, four places):** TOC `X-Standard` ✓, README badge ✓. Root `CLAUDE.md` carries the substance but under the heading `## The standard is the source of truth` instead of the canonical `## Standards compliance (read first)` (KCD-26). `docs/agent-context.md` `## Hard rules` does **not** open with the conform-to-the-standard rule pointing back to the CLAUDE.md section (KCD-27).

### audit-review-history / versioning-git
- Frozen dated bundles under `docs/audits/` and `docs/reviews/`. Semver TOC `## Version: 1.2.0`. Trunk-based workflow noted in the brief.

---

## Overall

The addon is **substantially compliant** with v2.7.0 — the v1.0.0 remediation plus later work (schema colour scheme, secret-safe printer, on-screen console with `[Init]` summary, AceGUI Defaults button, in-place panel refresh) already satisfies most of the rules added between v1.1.0 and v2.7.0. The remaining gaps are: one file that has grown back over the LOC cap, three trailing-colon chat lines, the combat-refuse notice styling/wording, and two of the four standards-reference placements using non-canonical headings/ordering. Details in `02_DEVIATIONS.md`; evidence in `03_EVIDENCE.md`.
