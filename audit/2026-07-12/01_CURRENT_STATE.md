# 01 — Current State

**Addon:** Ka0s KickCD
**Audit date:** 2026-07-12
**Repo commit:** `554de43`
**Standard audited against:** Ka0s WoW Addon Standard **v1.0.0 (2026-07-12)** — `standards/01_STANDARD.md` @ `tusharsaxena/WowAddonStandards`.
**Playbook:** `AUDIT.md` (same repo).
**Deviation-ID prefix:** `KCD-` (first standards-audit run for this addon; the `reviews/2026-05-02/` bundle is a `wow-addon:review`, not a standards audit, so it defines no reusable deviation IDs).

This is a read-only snapshot of what the addon does today, walked section-by-section against the standard. Gaps are catalogued in `02_DEVIATIONS.md`; evidence is in `03_EVIDENCE.md`.

---

## Tier & layout (§1)

Tier 2 (modular). Source tree: `core/` (Compat, Constants, State, Util, Database, LSMPatch, KickCD), `defaults/` (Spells), `locales/` (enUS), `modules/` (Cooldowns, IconGrid, Castbar), `settings/` (Panel, General, Icons, Castbar, Spells, Profiles). Casing (PascalCase files, lowercase folders) matches §1.3.

- **File-size:** `modules/IconGrid.lua` = **1753 LOC** (over the 1500 hard cap, §1.2). `modules/Castbar.lua` = 1422 and `settings/Panel.lua` = 1266 sit in the 1000–1500 "on notice" band.
- **Media:** `media/` contains only a `screenshots/` subfolder. The runtime logo (`kickcd.logo.tga`) and its source (`kickcd.logo.jpg`) live under `media/screenshots/`, not the typed `media/logos/` required by §1.4/§6.5. No loose files directly in `media/`.

## TOC (§2)

`KickCD.toc`: single `## Interface: 120007` (§2.3 ✓), `## Title: Ka0s KickCD` (✓), `## SavedVariables: KickCDDB` (✓ §2.2), `## X-License: MIT` (✓), `## Category-enUS: Combat`, `## DefaultState: enabled`, `## IconTexture` present. File listing uses the required `# Libraries → # Locales → # Core → # Defaults → # Modules → # Settings` section comments in load order (§2.5 ✓).

- **Missing MUST fields:** `## X-Standard:` (§2.1), and — the addon is published (CurseForge project **1530802**, per the README badge) — `## X-Curse-Project-ID:` and `## X-Wago-ID:` (§2.1).
- **Missing/other:** no `## OptionalDeps:` line; `## Author: Ka0s` rather than the canonical `add1kted2ka0s`; trailing blank lines after the file listing.

## Library stack (§3)

Ace3 vendored under `libs/` and committed; no `.pkgmeta externals:` (there is no `.pkgmeta` at all — see §13). TOC loads LibStub, CallbackHandler, AceAddon, AceEvent, AceDB, AceDBOptions, AceConsole, AceConfig, AceGUI, LibSharedMedia, AceGUI-SharedMediaWidgets, LibCustomGlow. AceConfig/AceDBOptions back the Profiles sub-page (§6.3 legitimate).

- **Dead weight:** `libs/` also ships **AceBucket-3.0, AceComm-3.0, AceHook-3.0, AceLocale-3.0, AceSerializer-3.0, AceTab-3.0**, none of which appear in the TOC (never loaded, never `LibStub`'d) — the exact libs §3.3 tells you to prune.

## Architecture (§4)

- **Namespace:** the addon uses a **global `_G.KickCD`** table as its namespace. Every source file starts `KickCD = KickCD or {}` (or reads `_G.KickCD`); `core/KickCD.lua` promotes it via `NewAddon(existing, ...)` and rebinds `_G.KickCD = addon`. This is the `_G[addonName]` global namespace §4.1 forbids; there is no `local addonName, NS = ...` header anywhere. (This is a deliberate documented choice per the repo's own `CLAUDE.md`, but it is a standard deviation.)
- **AceAddon:** registered with AceConsole + AceEvent embeds; feature modules are `KickCD:NewModule("X", "AceEvent-3.0")` — each module owns its own AceEvent target (§4.4 receiver rule ✓ for modules).
- **Message bus:** five named messages — `KickCD_SPELL_STATE`, `KickCD_CONFIG_CHANGED`, `KickCD_PROFILE_CHANGED`, `KickCD_GRID_LAYOUT`, `KickCD_COMBAT_STATE`. Closed bus, single sender per message, documented in `docs/message-bus.md`. **But** the names lack the required `Ka0s_<Addon>_` prefix (§4.4), and `settings/Spells.lua` registers two of them on the shared `KickCD` addon object as `self` rather than a private receiver target (§4.4 / anti-pattern 32 shape).
- **Schema-as-single-source (§4.5):** present and strong — `KickCD.Settings.Schema` drives AceGUI widgets, `/kcd get|set|list|reset`, and per-panel/all Defaults resets; `Helpers.ValidateSchema()` walks every row at registration and prints errors, returning a count for a harness (§4.5 ✓).

## SavedVariables / AceDB (§5)

Single `KickCDDB` global (✓). Defaults in `core/Database.lua` (`DEFAULT_PROFILE`). A version integer exists and a migration runner (`Database:MigrateProfile`, no-op for v1) ships (✓ intent). **Deviation:** the integer is named `dbVersion` and stored **per-profile** rather than `schemaVersion` in the **global** namespace (§5.1/§2.2).

## Options UI (§6)

Strong compliance. `Settings.RegisterCanvasLayoutCategory` + subcategories, registered **eagerly** from a bootstrap frame on `ADDON_LOADED(Blizzard_Settings)`/`PLAYER_LOGIN` (§6.1/§6.9 ✓), body built lazily on `OnShow`, raw AceGUI content, landing page with logo + tagline + slash-command list, per-tab Defaults, combat-gated open (`KickCD:OpenSettings`). Recent commits added the `0.492` button-pair inset (§6.6) and scroll-clip handling (§6.10). Preview mode ships for the cast bar while unlocked (§6B ✓). Logo asset path points into `media/screenshots/` rather than `media/logos/` (see §1.4 above).

## Slash commands (§7)

AceConsole `/kcd` + `/kickcd` alias (§7.1/7.2 ✓). Schema-driven dispatch via ordered `COMMANDS` / `DEBUG_COMMANDS` / `SPELLS_COMMANDS` tables; `get/set/list/reset/resetall` walk the schema; bare `/kcd` and unknown verbs print a generated help index (§7.3/7.4 ✓). Chat lines carry a `[KCD]` tag. **Deviation:** the tag is a **file-local** `PREFIX` in `core/Util.lua`, not an exposed shared `NS.PREFIX` constant, and it is **hand-duplicated** in `settings/Panel.lua` (§7.4).

## Localization (§8)

`locales/enUS.lua` exports `NS.L` via a key-returning metatable (§8.1 ✓), English-string keys (§8.2 ✓). enUS only (additional locales are opt-in — fine).

## Events / frames / taint (§9)

AceEvent throughout; a `RegisterTargetEvent` helper restricts `UNIT_SPELLCAST_*` to the target unit. Combat lockdown gates settings open. No Blizzard-UI replacement, no macro/protected-API writes, no chat replacement. Object-pooling not obviously required (fixed icon grid).

## Compat / deprecated APIs (§11)

`core/Compat.lua` shims spell/cast APIs well (secret-value-safe). **Deviation:** deprecated `GetSpecialization` / `GetSpecializationInfo` / `GetSpellInfo` are also called **directly** (outside Compat) in `core/KickCD.lua`, `modules/Cooldowns.lua`, `modules/IconGrid.lua`, and `settings/Spells.lua` (§11 / anti-pattern 10).

## Debug / logging (§12)

`/kcd debug` subcommands dump state, and `/kcd debug log` toggles internal-message logging. **All debug output routes to the chat frame** via `Util.print`; there is **no on-screen debug console** (§12 / anti-pattern 18, given the addon has on-screen displays). The debug enabled-state is **persisted in SavedVariables** (`db.profile.debugLog`, seeded into `self._debugLog` on init) rather than being session-only in `NS.State.debug` (§12.5). No shipped monospace font.

## Packaging & lint (§13, §14)

**No `.pkgmeta`** and **no `.luacheckrc`** at the repo root (both MUST).

## Tests (§14A)

**No `tests/` directory exists.** No headless harness, no TDD substrate. This also makes the §14A/§17 commit gate (green `lua tests/run.lua` + clean `luacheck .`) unsatisfiable as written.

## Docs (§15)

Root ships `README.md`, `CLAUDE.md`, `LICENSE` — **and also `ARCHITECTURE.md`**. `CLAUDE.md` is the **full agent brief** (~79 lines of working notes, hard rules, module-publishing idiom, doc index), not the required stub (§15.2 / anti-pattern 26). `ARCHITECTURE.md` lives at root, not `docs/ARCHITECTURE.md` (§15.3). `docs/` is otherwise rich (data-flow, message-bus, midnight-quirks, smoke-tests, testing, etc.). README follows most of the canonical order but is **missing the Ka0s-Standard badge** in its badge row (§15.1) and has no `## How it works` section (SHOULD), inserting custom `## Critical settings` subsections instead. No `TODO.md` (✓ for a released addon).

## Versioning (§17)

Semver `1.1.0` in TOC and `KickCD.VERSION`, README badge in lockstep. Trunk-based. The green-commit gate can't be honored without a harness/lint config (see §14/§14A).

---

## Summary

KickCD is a mature, well-documented Tier-2 addon that is **strong** on the high-value Ka0s patterns — schema-as-single-source, eager-register/lazy-body Settings panel, closed message bus, secret-value discipline, preview mode, generated slash help. Its deviations cluster in **project scaffolding** (no tests/lint/pkgmeta), the **global-vs-private namespace** choice, **naming conventions** (bus-message prefix, `NS.PREFIX`, `schemaVersion`), the **debug console** requirement, and **TOC/README/docs** metadata. None are architecturally deep; most are mechanical to close.
