# Ka0s KickCD — Execution Plan

**Version:** 0.1 (draft, awaiting sign-off)
**Companion docs:** [REQUIREMENTS.md](REQUIREMENTS.md) · [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) · [RESEARCH.md](RESEARCH.md)

---

## 1. Goal

Ship a working v0.1 of KickCD into `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD/` (the repo root *is* the addon folder) such that:

- Dropping the folder into `Interface/AddOns/` and launching WoW Midnight 12.0.5 produces a loadable, error-free addon.
- All 12 acceptance criteria in REQUIREMENTS.md §6 can be verified manually via UAT.md.

The orchestrator (me) splits the work into **four phases** dispatched to **parallel sub-agents**. Each agent owns a disjoint slice of the file tree so they cannot conflict.

---

## 2. Phase overview

| Phase | Mode | Agents | Approx wall-time | Output |
| --- | --- | --- | --- | --- |
| **0 — Scaffolding** | Orchestrator (sequential) | — | ~3 min | Folder tree, TOC, empty Lua stubs, LICENSE, .gitignore |
| **1 — Foundation** | 4 agents in parallel | A1, A2, A3, A4 | ~10 min | Libs vendored, core+db+locales written, full spell defaults, media placeholders |
| **2 — Runtime modules** | 3 agents in parallel | B1, B2, B3 | ~15 min | Tracker+Cooldowns+TestMode, IconGrid, Castbar |
| **3 — Settings panel** | 2 agents in parallel | C1, C2 | ~10 min | General/Icons/Castbar tabs, Spells editor, Profiles tab |
| **4 — Integration** | Orchestrator (sequential) | — | ~5 min | TOC verification, Lua syntax sweep, version stamp, README |

**Critical path:** Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4. Phases are strictly serial; agents within a phase are strictly parallel.

---

## 3. Phase 0 — Scaffolding (orchestrator)

Steps the orchestrator performs before dispatching any agent:

1. Create folder tree exactly as in TECHNICAL_DESIGN §2.
2. Write `KickCD.toc` with the full file list at root, pinned to `Interface: 120005`.
3. Write `LICENSE` (MIT, Author: Ka0s, Year: 2026).
4. Write `.gitignore` (`.wago_ignore`, OS junk, build artifacts).
5. Write **empty stub** for every `.lua` file referenced in the TOC. Each stub contains:
   ```lua
   -- <filename> — KickCD v0.1
   -- See docs/TECHNICAL_DESIGN.md §<section>
   ```
   Empty stubs ensure WoW can load the addon even if an agent fails midway.
6. Write `media/README.txt` describing required asset filenames.

**Phase 0 acceptance:** every file listed in the TOC exists on disk, even if empty.

---

## 4. Phase 1 — Foundation (4 parallel agents)

### Agent A1 — Library vendor

**Owns:** `libs/**`
**Inputs:** TECHNICAL_DESIGN §2 (lib list)
**Tasks:**
1. Fetch the latest stable release tarballs of:
   - `LibStub`
   - `CallbackHandler-1.0`
   - `Ace3` (bundle: AceAddon, AceEvent, AceDB, AceDBOptions, AceConsole, AceGUI, AceConfig, AceConfigDialog, AceConfigRegistry)
   - `LibSharedMedia-3.0`
2. Try `curl` first; on failure, write `libs/MANUAL_INSTALL.md` listing the exact URLs and target paths so the user can drop them in.
3. For each lib, write the directory layout (`libs/<LibName>/<files>`) so the TOC `xml`/`lua` includes resolve.
4. Update the TOC if any lib uses an `.xml` manifest instead of a single `.lua`.

**Deliverables:** populated `libs/` tree OR a clean `MANUAL_INSTALL.md` with all download URLs.

**Done when:** running `lua -p` (if available) or visual inspection shows no missing-file paths in the TOC.

---

### Agent A2 — Core, database, locales

**Owns:** `core/**`, `locales/**`
**Inputs:** TECHNICAL_DESIGN §3.1–3.3, §4
**Tasks:**
1. `core/KickCD.lua` — `LibStub("AceAddon-3.0"):NewAddon("KickCD", "AceConsole-3.0", "AceEvent-3.0")`. Implement `OnInitialize`, `OnEnable`, `OpenSettings`, slash commands `/kickcd`, `/kcd`, `/kickcd debug`.
2. `core/Database.lua` — AceDB init, defaults skeleton (defer the `spells` sub-table to A3's defaults file via a deferred-merge), profile callbacks, migration table (LATEST_VERSION = 1, no-op).
3. `core/Compat.lua` — wrappers for `C_Spell.GetSpellCooldown`, `GetSpellTexture`, `GetSpellInfo`, `GetSpellCharges`, `IsSpellUsable`, and a thin shim around `Settings.RegisterAddOnSetting` that handles the 10.x/11.x signature variants.
4. `core/Util.lua` — color helpers, anchor (point/relativePoint/x/y) save+restore, debounce.
5. `locales/enUS.lua` — `L = setmetatable({}, { __index = function(_, k) return k end })`. Populate ~30 user-facing strings used across modules+settings.

**Deliverables:** all five files compile and `KickCD:OnInitialize` runs cleanly when stubbed modules load.

**Done when:** in WoW, `/run print(KickCD)` returns a non-nil table after `/reload`.

---

### Agent A3 — Default spell sets

**Owns:** `defaults/Spells.lua`
**Inputs:** RESEARCH.md §6.1–6.4, REQUIREMENTS.md FR-5
**Tasks:**
1. Build a complete `KickCD.DefaultSpells[CLASS][SPEC] = { {spellID, category, enabled=true}, ... }` table for **every** class+spec in WoW Midnight 12.0.5.
2. Categories use the closed set: `interrupt | stun | knockback | incapacitate | silence | root | fear | racial`.
3. Order each spec list with primary interrupt at index 1, then 3–5 cast-stopping CCs in priority order (PvE bias per FR-5.1).
4. Handle the DK Asphyxiate spec-split (Blood vs Frost/Unholy spellIDs).
5. Add a `KickCD.RaceCastStoppers[race] = spellID` table for War Stomp / Quaking Palm / Bull Rush / Haymaker / Arcane Pulse.
6. Each entry includes a `-- Spell Name (English)` comment for human review.
7. Mark every entry the research flagged TBD with a `-- TBD: verify in 12.0.5` comment.

**Deliverables:** one file, ~300 lines, no Lua errors.

**Done when:** `/run for k,v in pairs(KickCD.DefaultSpells) do print(k, #v) end` prints all 13 classes after `/reload`.

---

### Agent A4 — Media + license

**Owns:** `media/**`, `LICENSE`, root `README.md` (minimal)
**Inputs:** REQUIREMENTS.md NFR-8
**Tasks:**
1. Generate a 64×64 placeholder addon icon (`media/icon.tga`) — a green "K" on dark background. Either generate via ImageMagick if available, or document the placeholder requirement.
2. Generate a flat 1×8 statusbar texture (`media/statusbar-flat.tga`) for default castbar texture.
3. Write `media/README.txt` listing texture sources + license.
4. Confirm `LICENSE` (MIT) at root is correct.
5. Write a short root `README.md` (yes — this one is justified): name, one-paragraph description, install instructions, link to docs/.

**Deliverables:** two TGA files (or clear instructions if generation isn't possible), README, LICENSE.

**Done when:** `media/icon.tga` exists and is referenced by `## IconTexture:` in the TOC without warning.

---

### Phase 1 acceptance

After all four A-agents finish, the orchestrator verifies:

- [ ] No file referenced by TOC is missing.
- [ ] No Lua file has a syntax error (`luac -p` if available, otherwise visual sweep).
- [ ] `KickCD.DefaultSpells` and `KickCD.RaceCastStoppers` exist as globals after `defaults/Spells.lua` loads.
- [ ] `core/KickCD.lua` calls `Database:Init()` from `OnInitialize` and that runs without error.

If anything fails, the orchestrator dispatches a **fix agent** scoped to the failing file before proceeding.

---

## 5. Phase 2 — Runtime modules (3 parallel agents)

All B-agents depend on Phase 1 being complete and assume the message contracts in TECHNICAL_DESIGN §1.

### Agent B1 — Tracker + Cooldowns + TestMode

**Owns:** `modules/Tracker.lua`, `modules/Cooldowns.lua`, `modules/TestMode.lua`
**Inputs:** TECHNICAL_DESIGN §3.4, §3.5, §3.8
**Tasks:**
1. **Tracker.lua** — implement the state machine in §3.4: dedicated raw frame for `RegisterUnitEvent("..., "target")`, `Evaluate()` function, message dispatching for `KickCD_TARGET_CAST_START/UPDATE/END`. Filter `_DELAYED` to `_UPDATE` only.
2. **Cooldowns.lua** — implement the watched-spell observer in §3.5: rebuild watch list on profile change / spec change / config change; poll on `SPELL_UPDATE_COOLDOWN/USABLE/CHARGES`; only fire `KickCD_SPELL_STATE` when state actually changes.
3. **TestMode.lua** — synthesize fake `KickCD_TARGET_CAST_START` / `END` on a 5-second loop; auto-disable on `PLAYER_REGEN_DISABLED`. Expose `KickCD:ToggleTestMode()`.

**Done when:** `/kickcd debug target` prints sane state when targeting a casting unit; `/kickcd debug spells` prints cooldown state for all watched spells.

---

### Agent B2 — IconGrid

**Owns:** `modules/IconGrid.lua`
**Inputs:** TECHNICAL_DESIGN §3.6, REQUIREMENTS FR-2
**Tasks:**
1. Build the `KickCDIconGrid` parent frame anchored per `db.profile.anchors.icons`.
2. Per-icon widget pool: create on first need, reuse on rebuild. Each icon has icon texture, `CooldownFrameTemplate` swipe, optional cooldown text, optional charges badge.
3. Layout algorithm respecting `layout`, `primaryAnchor`, `gap`, `primarySize`, `secondarySize`.
4. State application from `KickCD_SPELL_STATE` per §3.6 code shape.
5. Drag handlers gated on `db.profile.locked == false`. Anchor persistence on drag stop.
6. Re-layout on `KickCD_CONFIG_CHANGED { section = "icons" }` or `"spells"` — without re-creating widgets.
7. Show on `KickCD_TARGET_CAST_START`, hide on `_END`.

**Done when:** in test mode, the grid renders with the active spec's spell list, swipes activate when those spells are used, and dragging persists across `/reload`.

---

### Agent B3 — Castbar

**Owns:** `modules/Castbar.lua`
**Inputs:** TECHNICAL_DESIGN §3.7, REQUIREMENTS FR-3
**Tasks:**
1. Build the `KickCDCastbar` `StatusBar` frame: bar, spark, icon texture, name text, time-left text, border, background.
2. Support fill direction: left-to-right for casts, right-to-left for channels (FR-3.4).
3. OnUpdate handler set/cleared on show/hide. Compute `pct` from `startMS`, `endMS`, `GetTime()`.
4. Restyle (texture, font, colors, dimensions) on `KickCD_CONFIG_CHANGED { section = "castbar" }` without recreate.
5. Drag handlers gated on `db.profile.locked == false`.
6. Sub to `KickCD_TARGET_CAST_START/UPDATE/END`.

**Done when:** in test mode, the castbar shows a 5s loop animating smoothly; in real combat against a casting hostile, the bar tracks the cast accurately within 50 ms drift.

---

### Phase 2 acceptance

- [ ] Test mode (`/kickcd test`) shows both icons and castbar with realistic animations.
- [ ] Real-target test: targeting a hostile NPC casting an interruptible spell shows both UIs within 100 ms.
- [ ] No Lua errors when changing target rapidly or switching specs.

---

## 6. Phase 3 — Settings panel (2 parallel agents)

### Agent C1 — Native settings tabs

**Owns:** `settings/Panel.lua`, `settings/General.lua`, `settings/Icons.lua`, `settings/Castbar.lua`
**Inputs:** TECHNICAL_DESIGN §5.1–5.2, REQUIREMENTS FR-6.2.{1,2,3}
**Tasks:**
1. **Panel.lua** — register the main category via `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`. Expose `KickCD:OpenSettings`.
2. **General.lua** — checkboxes (enabled, locked, testMode), sliders (scale, alpha), reset-position button.
3. **Icons.lua** — sliders (primary size, secondary %, gap), dropdowns (layout, primary anchor), color pickers (cooldown tint), checkboxes (charges, cooldown text), font dropdown via LibSharedMedia.
4. **Castbar.lua** *(settings file, not module)* — sliders (width, height), font + size + texture (LibSharedMedia), border dropdown, color pickers (interruptible, not-interruptible), checkboxes (spark, icon).
5. Every setter fires `KickCD_CONFIG_CHANGED` with the right `section` so modules restyle live.

**Done when:** opening Settings shows all four subcategories with working widgets, and changes apply without `/reload`.

---

### Agent C2 — Spells editor + Profiles

**Owns:** `settings/Spells.lua`, `settings/Profiles.lua`
**Inputs:** TECHNICAL_DESIGN §5.3–5.4, REQUIREMENTS FR-6.2.{4,5}, FR-7, FR-10.4
**Tasks:**
1. **Spells.lua** — register a Settings canvas subcategory; embed an AceGUI `ScrollFrame`; build one row per spell with `[icon][name+ID][enabled toggle][category dropdown][▲][▼][✕]`. Top of panel: class+spec selector, "Add spell..." button (opens AceGUI modal with spellID/name input, validates via `C_Spell.GetSpellInfo`), "Reset to defaults" button (StaticPopup confirmation). Debounced writes (50 ms) → `KickCD_CONFIG_CHANGED { section = "spells" }`.
2. **Profiles.lua** — wire `AceDBOptions-3.0`:
   ```lua
   local opts = LibStub("AceDBOptions-3.0"):GetOptionsTable(KickCD.db)
   LibStub("AceConfig-3.0"):RegisterOptionsTable("KickCD-Profiles", opts)
   LibStub("AceConfigDialog-3.0"):AddToBlizOptions("KickCD-Profiles", "Profiles", "Ka0s KickCD")
   ```

**Done when:** all UAT scenarios for FR-7 and FR-10.4 pass.

---

### Phase 3 acceptance

- [ ] All five subcategories visible under "Ka0s KickCD" in Blizzard Settings.
- [ ] `/kickcd` and `/kcd` open the panel.
- [ ] Adding/removing/reordering a spell live-updates the icon grid.
- [ ] Creating a new profile, switching to it, and editing it independently works without `/reload`.

---

## 7. Phase 4 — Integration (orchestrator)

1. **TOC verification** — confirm every Lua/XML referenced exists on disk.
2. **Lua syntax sweep** — `find . -name '*.lua' -exec luac -p {} \;` if `luac` is available; else visual.
3. **Version stamp** — confirm `## Version: 0.1.0` and `KickCD.VERSION = "0.1.0"` are consistent.
4. **README polish** — add UAT pointer, screenshot placeholders, "known issues" pulled from research §9.
5. Update `MEMORY.md` if new project memories surfaced during build.

---

## 8. Dependency graph

```
Phase 0  ─┐
          ▼
       ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐
       │ A1  │  │ A2  │  │ A3  │  │ A4  │     (Phase 1, parallel)
       │libs │  │core │  │spells│ │media│
       └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘
          └────────┼────────┴────────┘
                   ▼
       ┌─────┐  ┌─────┐  ┌─────┐
       │ B1  │  │ B2  │  │ B3  │              (Phase 2, parallel)
       │track│  │icons│  │bar  │
       └──┬──┘  └──┬──┘  └──┬──┘
          └────────┼────────┘
                   ▼
              ┌─────┐  ┌─────┐
              │ C1  │  │ C2  │                 (Phase 3, parallel)
              │tabs │  │spell│
              └──┬──┘  └──┬──┘
                 └────────┘
                      ▼
                  Phase 4 ─▶ Done
```

Hard dependencies:
- **B1/B2/B3** all need A1 (libs) + A2 (Compat, Util, KickCD bootstrap) + A3 (DefaultSpells).
- **C1/C2** all need A1 + A2 + everything from Phase 2 (settings live-update messages target running modules).

---

## 9. Inter-agent contracts (the "API")

To make parallelism safe, every agent assumes these are stable and ships unchanged:

1. **`KickCD` AceAddon object** is global after `core/KickCD.lua` loads.
2. **`KickCD.db`** is the AceDB instance after `OnInitialize`.
3. **`KickCD.Compat.{GetSpellCooldown,GetSpellTexture,GetSpellInfo,GetSpellCharges,IsSpellUsable}`** signatures match TECHNICAL_DESIGN §3.3.
4. **Internal messages** are exactly the seven listed in TECHNICAL_DESIGN §1 — no agent invents new ones without an addendum here.
5. **`KickCD.DefaultSpells[CLASS][SPEC]`** is an array of `{spellID, category, enabled}` tables.
6. **`db.profile`** structure matches TECHNICAL_DESIGN §4.

If an agent needs to break a contract, it must stop and surface that to the orchestrator before continuing.

---

## 10. Risks & mitigations

| ID | Risk | Mitigation |
| --- | --- | --- |
| E-1 | Network access denied during Phase 1 (libs can't curl) | A1 falls back to writing `libs/MANUAL_INSTALL.md` with explicit URLs; orchestrator surfaces this so user drops libs manually before continuing |
| E-2 | Two agents stomp the same file | Eliminated by disjoint file ownership in §3–§6 |
| E-3 | TOC drift between scaffolding and reality | TOC written once in Phase 0; every subsequent file write must match a TOC entry. Phase 4 verifies this. |
| E-4 | An agent invents a new internal message | Hard rule §9; agents are briefed with the closed list and instructed to stop if they need a new one |
| E-5 | DefaultSpells has wrong spellIDs | A3 marks every TBD entry; UAT validates per-class behavior in WoW; user can edit defaults via the editor |
| E-6 | Settings API signature shift between Midnight builds | All Settings calls go through `core/Compat.lua` |

---

## 11. Done definition (whole project)

- All files in TECHNICAL_DESIGN §2 file layout exist and load without Lua errors.
- All 12 acceptance criteria in REQUIREMENTS §6 are testable.
- UAT.md exists with step-by-step scenarios and the user has executed at least the smoke path (AC-1 through AC-7).

---

## 12. Sign-off

**Status:** ⏳ Awaiting user sign-off

Reply with:
- ✅ "Approved — proceed to UAT"
- 🔧 "Changes needed: ..." (with specifics)
