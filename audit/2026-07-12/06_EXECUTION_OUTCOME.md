# 06 — Execution Outcome (Remediation Build)

Outcome of executing the remediation in [`04_TECHNICAL_DESIGN.md`](04_TECHNICAL_DESIGN.md) and [`05_EXECUTION_PLAN.md`](05_EXECUTION_PLAN.md). **All 22 deviations (18 MUST + 4 SHOULD) are addressed.** The work landed as six sprints, each held to a green gate (`lua tests/run.lua` + `luacheck .`) before proceeding.

**Final gate:** `lua tests/run.lua` → **41 passed, 0 failed** (exit 0). `luacheck .` → **0 errors** (9 residual warnings, all pre-existing shadowing/unused-local smells outside audit scope). Every `.lua` source syntax-checks with `luac -p`.

Decisions taken at kickoff (confirmed with the user): full 6-sprint scope incl. the namespace migration; work left in the working tree on `master` (no commits made — the user controls git); `## X-Wago-ID` omitted with a TODO until published; JetBrains Mono vendored for the debug console.

---

## Deviation closure

| ID | Sev | What was done | Where |
|----|-----|---------------|-------|
| KCD-03 | MUST | `.luacheckrc` added (std lua51, exclude libs/audit/tests/reviews, WoW-API globals, `KickCDDB`/`StaticPopupDialogs` write-globals). | `.luacheckrc` |
| KCD-04 | MUST | `.pkgmeta` added (`package-as: KickCD`, no `externals`, ignores audit/docs/tests/reviews/dotfiles). | `.pkgmeta` |
| KCD-23 | MUST | Deleted 6 unused libs (AceBucket, AceComm, AceHook, AceLocale, AceSerializer, AceTab). | `libs/` |
| KCD-11/12/18 | MUST/SHOULD | TOC rewritten into §2.1 field order; `Author: add1kted2ka0s`; `OptionalDeps`, `X-Standard`, `X-Curse-Project-ID: 1530802`; Wago as a TODO comment; single trailing newline. | `KickCD.toc` |
| KCD-15 | MUST | Logo `.tga`+`.jpg` moved to `media/logos/`; `settings/Panel.lua` texture path + comment updated. | `media/logos/`, `settings/Panel.lua` |
| KCD-02 | MUST | Headless test harness: `tests/{run,loader,wow_mock}.lua` + 7 suites. Bus mock keys callbacks by `(message, target)`. | `tests/` |
| KCD-10 | MUST | `Compat.GetSpecialization`/`GetSpecializationInfo` shims added; 10 direct call sites rerouted. | `core/Compat.lua` + 4 files |
| KCD-08 | MUST | All 5 bus messages renamed `Ka0s_KickCD_*` across senders, receivers, and docs. | all modules + docs |
| KCD-16 | MUST | Single `NS.PREFIX` (in `core/Constants.lua`); `Util.print` + Panel schema-error printer reference it. | `core/Constants.lua`, `core/Util.lua`, `settings/Panel.lua` |
| KCD-20 | SHOULD | Schema version moved to `db.global.schemaVersion`. Legacy `dbVersion` accounts are adopted once, keyed on the presence of the old per-profile field (see the review note below — AceDB backfills the global default, so a `== nil` check would be dead code). | `core/Database.lua` |
| KCD-09 | MUST | Spells panel registers on a private `NS.NewBusTarget()` target, not the shared addon object. | `core/KickCD.lua`, `settings/Spells.lua` |
| KCD-06 | MUST | On-screen debug console `modules/DebugLog.lua` (DIALOG window, `ScrollingMessageFrame`, Copy/Clear, header toggle, `SKIN`/`ApplySkin`). JetBrains Mono (OFL) vendored + `Const.FONT_MONO` + LSM register. Pure `FormatPlain`/`FormatColored` formatters. | `modules/DebugLog.lua`, `media/fonts/` |
| KCD-07 | MUST | Debug flag is session-only `NS.State.debug` (never in SV); single `DebugLog:SetEnabled` write seam; `/kcd debug on\|off\|toggle\|window`; module debug routed through the gated `NS.Debug` sink into the console. | `core/State.lua`, `core/KickCD.lua`, modules |
| KCD-05 | MUST | `modules/IconGrid.lua` (1753) peeled into `IconGrid.lua` (815) + `IconGrid_Layout.lua` (245) + `IconGrid_Render.lua` (705). Pure layout math unit-tested. | `modules/IconGrid*.lua` |
| KCD-19 | SHOULD | On-notice comments added to `Castbar.lua` (1426) and `Panel.lua` (1270) — both under the 1500 cap. | headers |
| KCD-14 | MUST | `ARCHITECTURE.md` moved to `docs/` with the §15.3 section set (Message Bus + Slash tables, Settings Schema, Event Subscriptions, Taint Notes, Known Limitations). | `docs/ARCHITECTURE.md` |
| KCD-13 | MUST | Root `CLAUDE.md` reduced to a §15.2 stub; full brief relocated to `docs/agent-context.md`. | `CLAUDE.md`, `docs/agent-context.md` |
| KCD-17 | MUST | Ka0s-Standard badge added to the README badge row. | `README.md` |
| KCD-21 | SHOULD | `## How interrupt tracking works` section added; `Critical settings` folded beneath it. | `README.md` |
| KCD-01 | MUST | Every file converted to `local addonName, NS = ...`; global `_G.KickCD` namespace removed; `NewAddon(NS, "KickCD", ...)` with no `_G` rebind. Temp luacheck `globals={"KickCD"}` removed — lint stays 0 errors, proving no stray global refs. | every source |

---

## Adversarial review pass

After the build, a multi-agent review ran four independent reviewers (namespace migration, message bus, debug/compat/schema-version, IconGrid peel), each finding independently verified before it survived.

- **Namespace, bus, and peel dimensions: clean** — no confirmed defects. The migration preserves strings/frame-names/messages, no orphaned sender/receiver pairs, the peel lost no functions and its cross-file exposures resolve.
- **One confirmed defect (major), now fixed:** the KCD-20 one-shot legacy-version adoption was **dead code**. `schemaVersion` is registered in AceDB's `global` defaults, so AceDB's `copyDefaults` backfills `db.global.schemaVersion = CURRENT_DB_VERSION` on first access — before `MigrateProfile`'s `if g.schemaVersion == nil` check. A legacy account (old per-profile `dbVersion`, no global version) would be masked as current and its future migrations skipped. **Fix:** legacy detection now keys on the presence of the old per-profile `dbVersion` field, not on `global.schemaVersion` being nil, so it works regardless of AceDB's backfill; fresh installs stay correctly born at the current version. Covered by a new regression test (`test_database.lua` — "adopts a legacy per-profile dbVersion even past AceDB backfill").

---

## Test harness (KCD-02)

A plain **Lua 5.1** headless harness — no external framework. It loads every addon source in TOC order under a WoW-API mock, builds the DB, then runs assertion suites.

### Files
- **`tests/run.lua`** — the runner + micro-framework (`test`, `assertEqual`, `assertTrue`, `assertFalse`, `assertNil`, `assertError`). Loads one shared addon instance (calls `OnInitialize`), exposes everything on the global `_G.KICKCD_TEST`, `dofile`s each suite, prints `PASS`/`FAIL`, and `os.exit(failed==0 and 0 or 1)`. A `SUITES` list registers the suites.
- **`tests/loader.lua`** — parses `KickCD.toc` for the `.lua` load order, builds ONE shared sandbox env whose `__index` resolves WoW globals to the mock first then real `_G`, sets `env._G = env`, and calls each chunk as `chunk(addonName, NS)` — reproducing the `local addonName, NS = ...` header. Exposes `loadAll(root, mocks) → (env, NS)`.
- **`tests/wow_mock.lua`** — a **builder** (`build()` → a fresh mock env per instance). Stubs a universal self-returning no-op frame, `CreateFrame`, `UIParent`, `C_Spell`, `C_SpecializationInfo`, `Unit*`, `Settings.*`, time/timer APIs (with a flushable `C_Timer.After` queue), colors, static popups, and `LibStub` with **fake AceAddon / AceDB / AceEvent / AceConsole / AceTimer / AceGUI / LSM**. The AceEvent fake keeps a **module-level registry keyed by `(message, target)`** and fans `SendMessage` out to every target — so the last-registrant-wins clobber (AP-33 / KCD-09) is actually modelled, not hidden.

### Suites (41 tests)
- `test_util.lua` — `Unpack`, `NormalizeSpecToken`, `NormalizeClassToken`, `DeepCopy`, `Throttle` (burst-coalescing via flushable timers).
- `test_schema.lua` — schema assembly, `Helpers.ValidateSchema()` returns 0, path resolution (`Resolve`/`Get`/`FindSchema`).
- `test_database.lua` — `DEFAULT_PROFILE` shape, merged profile after init, **`schemaVersion` in `db.global`** (not the profile), migration no-op + missing-version + legacy-`dbVersion` adoption.
- `test_bus.lua` — one message fans to two distinct targets; two receivers on one target clobber (proves `(message,target)` keying); addon `SendMessage` reaches a registered target; `NewBusTarget` gives independent targets that both fire (KCD-09).
- `test_compat.lua` — spec shims prefer `C_SpecializationInfo` and fall back to the deprecated globals (mocked).
- `test_debuglog.lua` — pure `FormatPlain`/`FormatColored` (no colour drift), flag defaults **off** and is never in SV, `SetEnabled` is the single seam, `NS.Debug` is a no-op when disabled and captures when enabled.
- `test_icongrid_layout.lua` — the peeled pure geometry: `parseAnchor`/`parseGrow` token normalisation, `placeBlock` RIGHT/TOP/CENTER geometry.

### Commands
```sh
cd <repo root>
lua tests/run.lua      # unit tests — exits non-zero on any failure
luacheck .             # lint — 0 errors required
luac -p path/to/x.lua  # syntax-check a single file
```
Local toolchain: `sudo apt-get install -y lua5.1 luarocks && sudo luarocks install luacheck` (§14A.3).

---

## Manual smoke tests (run in-game)

Do these after copying the folder into `Interface/AddOns/KickCD/`. They target the remediation specifically; the full end-to-end matrix is in [`docs/smoke-tests.md`](../../docs/smoke-tests.md). Expect **zero Lua errors** throughout (enable `/console scriptErrors 1` or BugSack).

### S1 — Cold load & namespace privacy (KCD-01, KCD-11/12/18)
1. `/reload` on a fresh install. Addon loads; no errors; `Ka0s KickCD` shows in the addon list and Settings.
2. Run `/dump KickCD` — **should print `nil`** (the Lua namespace is now private). The addon still works.
3. Run `/dump KickCDIconGrid` and `/dump KickCDDB` — these **should exist** (global frame name + SavedVariables are intentionally still `KickCD`-prefixed).
4. Open Settings → the **landing page logo renders** (KCD-15 path move).

### S2 — Debug console & session-only flag (KCD-06, KCD-07)
1. `/kcd debug` — the **debug console window opens** (dark DIALOG-strata frame titled "KickCD — Debug"), and the verb list prints in chat. Header shows **`Debug: OFF`** in red.
2. Click the header toggle (or `/kcd debug on`) → it flips to **`Debug: ON`** in green and a chat ack prints. Text is **monospace** (JetBrains Mono).
3. With debug on, change target / spec / a setting so modules emit debug lines → **lines appear in the console** (`<HH:MM:SS> | [Tag] …`), **not** in the chat frame.
4. Click **Copy** → a highlighted read-only edit box with the plain (un-coloured) log for `Ctrl+C`. Click **Clear** → both views empty.
5. `/reload` → reopen the console → **`Debug: OFF`** again (flag reset; it was never saved). Confirm no `debugLog` key exists in `KickCDDB` (session-only).

### S3 — Message bus end-to-end (KCD-08) — proves the rename didn't orphan any receiver
1. Change specialization → the **icon grid rebuilds** to the new spec's spells (Cooldowns → `Ka0s_KickCD_SPELL_STATE` → IconGrid).
2. Change a setting via the panel (e.g. Icons → primary size) → grid **relayouts live** (`Ka0s_KickCD_CONFIG_CHANGED`).
3. Switch profiles (Profiles tab) → grid + cast bar **re-anchor and re-skin** (`Ka0s_KickCD_PROFILE_CHANGED`).
4. Enter/leave combat with visibility `in_combat` → both show/hide together (`Ka0s_KickCD_COMBAT_STATE`).

### S4 — Spells panel private receiver (KCD-09)
1. Open Settings → **Spells** tab (leave it open).
2. In chat run `/kcd spells add <spellID>` for the shown class/spec → the **open panel's row list refreshes live** (the private `__ev` target received `Ka0s_KickCD_CONFIG_CHANGED`). Before the fix this could silently fail after a `/reload`.

### S5 — Compat spec routing (KCD-10)
1. On a multi-spec class, swap specs a few times → the tracked spell list follows each spec correctly (all spec lookups now go through `Compat.GetSpecialization*`).

### S6 — Icon grid peel — no visual/behaviour regression (KCD-05)
1. Unlock (`/kcd unlock`) → drag the grid → it moves and the drag box hugs the visible icons.
2. Icons → change **secondary anchor** (try several of the 13 points) and **grow direction** (several of the 8) → the secondary block re-places correctly around the primary.
3. Put a watched spell on cooldown → its **swipe + countdown text** render; when a glow trigger is met the **ready glow** fires. Re-lock (`/kcd lock`).

### S7 — Schema version migration (KCD-20)
1. Fresh `KickCDDB` (delete the SV file, `/reload`) → after login, `/dump KickCDDB.global` shows `schemaVersion = 1` and the active profile has **no** `dbVersion` field.
2. (Optional, simulates an upgrade) Before login, hand-edit the SV so a profile has `dbVersion = 1` and `global` is absent → `/reload` → `global.schemaVersion` becomes 1 and the profile's `dbVersion` is cleared (one-shot adoption).

### S8 — Slash parity & docs
1. `/kcd list`, `/kcd get <path>`, `/kcd set <path> <value>` still work for every schema row.
2. Confirm root ships only `README.md`, `CLAUDE.md` (a short stub), and `LICENSE`; `docs/ARCHITECTURE.md` and `docs/agent-context.md` exist.

---

## Residual notes & follow-ups
- **`## X-Wago-ID`** is omitted (commented TODO in the TOC) per the kickoff decision — add it once the addon is published to Wago.
- **KCD-19 (SHOULD)**: `Castbar.lua` and `Panel.lua` remain in the 1000–1500 "on notice" band (under the 1500 cap) with justifying header comments; a future peel is noted but not urgent.
- **No git operations were performed** — all changes are in the working tree on `master` for the user to review, stage, and commit.
- **Version was not bumped** — the TOC/`NS.VERSION`/README still read `1.1.0`; bump is a deliberate release-time decision.
- In-game smoke tests above are **manual** (headless tests cannot exercise frame rendering or taint); run them before tagging a release.
