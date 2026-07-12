# 03 — Evidence

`file:line` citations backing every deviation in `02_DEVIATIONS.md` and the key compliance claims in `01_CURRENT_STATE.md`. Line numbers are against commit `554de43`.

## KCD-01 — global `_G.KickCD` namespace (§4.1, AP-1)

- `core/Compat.lua:19` — `KickCD = KickCD or {}` (creates the global table; comment at `:14-18` states core/Compat.lua establishes the global namespace).
- `core/Constants.lua:14`, `core/State.lua:22`, `core/Database.lua:9`, `core/Util.lua:10`, `defaults/Spells.lua:20`, `locales/enUS.lua:12` — each file re-grabs the global `KickCD`.
- `core/KickCD.lua:21` `local existing = _G.KickCD or {}` → `:23-27` `NewAddon(existing, "KickCD", ...)` → `:32` `_G.KickCD = addon`. No `local addonName, NS = ...` header exists in any source file.
- `settings/Panel.lua:19` `local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")` — settings layer reaches the addon through the global registry, not an NS upvalue.

## KCD-02 — no tests harness (§14A, AP-24)

- No `tests/` directory in the repo tree (confirmed absent; `find` shows `core/ defaults/ locales/ modules/ settings/ libs/ media/ docs/ reviews/` only). No `run.lua`/`loader.lua`/`wow_mock.lua`.
- `settings/Panel.lua:131-161` `Helpers.ValidateSchema()` returns an error count "exposed for the test harness" — a harness the schema code anticipates but that does not exist.

## KCD-03 — no `.luacheckrc` (§14)

- Repo root listing contains `.gitattributes`, `.gitignore` but no `.luacheckrc`.

## KCD-04 — no `.pkgmeta` (§13, AP-7)

- Repo root has no `.pkgmeta`.

## KCD-05 — IconGrid over 1500 LOC (§1.2, AP-16)

- `modules/IconGrid.lua` — 1753 lines (`wc -l`). Over the 1500 hard cap.

## KCD-06 — debug output to chat, no console (§12, AP-18)

- `core/KickCD.lua:150-188` `DEBUG_COMMANDS` — `spells`/`castbar` call `m:DebugDump()`, `interrupt` calls `Compat.DebugInterrupt`, `log` toggles logging; every path prints via `p(self, ...)` → `Util.print`.
- `core/Util.lua:215-228` `Util.print` writes to `DEFAULT_CHAT_FRAME:AddMessage` — chat frame, not a console.
- `core/Compat.lua:330-414` `DebugInterrupt` writes exclusively through `KickCD.Util.print`.
- On-screen displays that make §12 apply: `modules/IconGrid.lua` (icon grid), `modules/Castbar.lua` (cast bar). No `DebugLog.lua`/`DebugWindow` frame anywhere.

## KCD-07 — debug flag persisted in SV (§12.5)

- `core/Database.lua:36` `debugLog = false` inside `DEFAULT_PROFILE` (a SavedVariables profile field).
- `core/KickCD.lua:52-55` seeds `self._debugLog` from `self.db.profile.debugLog` on init.
- `core/KickCD.lua:171-187` the `log` debug command writes `db.profile.debugLog` back through the schema path. §12.5 requires the enabled-state be session-only in `NS.State.debug`, never in SV.

## KCD-08 — bus messages missing `Ka0s_` prefix (§4.4)

- Message literals (grep, unique): `"KickCD_COMBAT_STATE"`, `"KickCD_CONFIG_CHANGED"`, `"KickCD_GRID_LAYOUT"`, `"KickCD_PROFILE_CHANGED"`, `"KickCD_SPELL_STATE"`.
- Senders: `core/State.lua:150` (`KickCD_COMBAT_STATE`), `settings/Panel.lua:62` (`KickCD_CONFIG_CHANGED`), `core/KickCD.lua:103` and `:595-597`. §4.4 requires `Ka0s_KickCD_*`.

## KCD-09 — Spells panel registers on shared addon object (§4.4, AP-32)

- `settings/Spells.lua:916-917` `KickCD:RegisterMessage("KickCD_PROFILE_CHANGED", function() ... end)` and `:925` `KickCD:RegisterMessage("KickCD_CONFIG_CHANGED", ...)` — receiver registered on the shared `KickCD` (AceAddon) object as `self`.
- Contrast the correct shape: modules own their target — `modules/Cooldowns.lua:60` / `Castbar.lua:55` / `IconGrid.lua:53` use `KickCD:NewModule("X", "AceEvent-3.0")` then register on `self` (`Cooldowns.lua:357-358`, `Castbar.lua:1118-1121`, `IconGrid.lua:1475-1481`). The Spells panel is a plain table and should own a private `NS.NewBusTarget()` embed instead.

## KCD-10 — direct deprecated API calls outside Compat (§11, AP-10)

- `core/KickCD.lua:555` `GetSpecialization()`, `:557` `GetSpecializationInfo(idx)`.
- `modules/Cooldowns.lua:78` `GetSpecialization()`, `:81` `GetSpecializationInfo(idx)`.
- `modules/IconGrid.lua:286` `GetSpecialization()`, `:288` `GetSpecializationInfo(specIdx)`.
- `settings/Spells.lua:88,90` and `:332,334` `GetSpecialization()` / `GetSpecializationInfo(idx)`.
- `core/Compat.lua` shims `GetSpellInfo`/cast APIs but has **no** `GetSpecialization`/`GetSpecializationInfo` shim — the standard's §11 example explicitly calls these out as the ones to route through Compat.

## KCD-11 / KCD-12 / KCD-18 — TOC fields (§2.1, §2.5)

- `KickCD.toc:1-10` metadata block: `Interface, Title, Notes, Author, Version, IconTexture, SavedVariables, DefaultState, Category-enUS, X-License`. Absent: `X-Standard` (KCD-11), `X-Curse-Project-ID` / `X-Wago-ID` (KCD-12), `OptionalDeps` (KCD-18).
- `KickCD.toc:4` `## Author: Ka0s` (canonical is `add1kted2ka0s`, KCD-18).
- Published evidence: `README.md:4` `![CurseForge Version](https://img.shields.io/curseforge/v/1530802)` — CurseForge project 1530802 (KCD-12).
- `KickCD.toc:53-54` trailing blank lines after the last file-listing entry (KCD-18, §2.5 single-trailing-newline).

## KCD-13 — root CLAUDE.md is a full brief (§15.2, AP-26)

- `CLAUDE.md:1-79` — "working notes for future sessions": What this addon is, Hard rules, Module publishing pattern, Working environment, Doc index table. This is the full agent brief, not a stub.

## KCD-14 — ARCHITECTURE.md at root (§15, §15.3)

- Root `ARCHITECTURE.md` exists (9.9 KB). No `docs/ARCHITECTURE.md`. §15 requires root to ship only README + CLAUDE stub + LICENSE; §15.3 puts ARCHITECTURE under `docs/`.

## KCD-15 — logo in wrong media subfolder (§1.4, §6.5, AP-25)

- Files present: `media/screenshots/kickcd.logo.tga` and `media/screenshots/kickcd.logo.jpg`. No `media/logos/` folder.
- `settings/Panel.lua:1113` comment: "exact native size of media/screenshots/kickcd.logo.tga" — the runtime path resolves the logo from `screenshots/`.

## KCD-16 — no shared `NS.PREFIX` (§7.4)

- `core/Util.lua:211` `local PREFIX = "|cff00ffff[KCD]|r"` — file-local, not exposed on the namespace.
- `settings/Panel.lua:123` hand-writes the same literal `"|cff00ffff[KCD]|r ..."` — the per-call-site duplication §7.4 forbids.

## KCD-17 — README missing standard badge (§15.1)

- `README.md:3-5` badge row: `![wow]`, `![CurseForge Version]`, `![license]`. No badge/line linking the Ka0s WoW Addon Standard.

## KCD-19 — files in the on-notice band (§1.2)

- `modules/Castbar.lua` 1422 LOC; `settings/Panel.lua` 1266 LOC (`wc -l`).

## KCD-20 — schemaVersion naming/location (§5.1, §2.2)

- `core/Database.lua:24` `local CURRENT_DB_VERSION = 1`; `:31` `dbVersion = CURRENT_DB_VERSION` inside `DEFAULT_PROFILE` (per-profile, named `dbVersion`). Migration runner referenced at `:23` (`Database:MigrateProfile`). §5.1 wants `schemaVersion` in `db.global`.

## KCD-21 — README missing "How it works" (§15.1)

- `README.md` headers: `# Ka0s KickCD` → `## Screenshots` → `## Usage` → `## Critical settings` (+ subsections) → `## FAQ` → `## Troubleshooting` → `## Issues and feature requests` → `## Testing` → `## Version History`. No `## How it works`; `## Critical settings` is a non-canonical section.

## KCD-23 — unused vendored libs (§3.3)

- `libs/` contains `AceBucket-3.0`, `AceComm-3.0`, `AceHook-3.0`, `AceLocale-3.0`, `AceSerializer-3.0`, `AceTab-3.0`. None appear in `KickCD.toc` (verified: each `grep` against the TOC returns "NOT loaded"). §3.3 requires vendoring only libs actually `LibStub`'d.

---

## Compliance evidence (claims of conformance in 01)

- **Schema-as-single-source (§4.5):** `settings/Panel.lua:28` `KickCD.Settings.Schema`, `:66-71` `Helpers.Set` (write + notify), `:131-161` `ValidateSchema`; `core/KickCD.lua:389-443` `/kcd list|get|set` walk the schema.
- **Eager-register / lazy-body Settings (§6.1/§6.9):** `settings/Panel.lua:1206` `RegisterPanel`, `:1258-1262` bootstrap frame on `PLAYER_LOGIN` + `ADDON_LOADED(Blizzard_Settings)`; subcategory registration in `settings/{General,Icons,Castbar,Spells,Profiles}.lua`.
- **Combat-gated open (§6.2):** `core/KickCD.lua:860-895` `OpenSettings` checks `State.inCombat`/`InCombatLockdown` and defers.
- **Preview mode (§6B):** `modules/Castbar.lua:369-374`, `:1011-1047` `ShowPreview` while unlocked.
- **Slash help generated (§7.3/7.4):** `core/KickCD.lua:196-201` `printHelp` iterates `COMMANDS`; `:222-239` `OnSlashCommand` prints help on unknown verb; `:117-148` `COMMANDS` table.
- **Locale metatable (§8.1/8.2):** `locales/enUS.lua:12` global grab + `NS.L` metatable returning key on miss.
- **Modules own AceEvent targets (§4.4 receiver rule):** `modules/Cooldowns.lua:60`, `Castbar.lua:55`, `IconGrid.lua:53` `NewModule(..., "AceEvent-3.0")`.
- **Secret-value discipline (repo-critical):** `core/Compat.lua:53-127`, `core/State.lua:94-113` `ApplyInterruptibleAlpha` feeds `notInterruptible` to `SetAlphaFromBoolean`.
- **Single SV global (§2.2):** `KickCD.toc:7` `## SavedVariables: KickCDDB`.
- **MIT license (§2.1):** `LICENSE:1` "MIT License"; `KickCD.toc:10` `## X-License: MIT`.
