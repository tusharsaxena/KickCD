# 04 — Technical Design (Remediation)

How to close each deviation. Grouped by the kind of change and ordered by dependency; each block names the files to touch, the shape of the change, and risks. Deviation IDs are the shared key with `02` and `05`. **This is a plan; the audit changes no code.**

---

## A. Scaffolding & metadata (low-risk, no runtime behavior change)

Do these first — they unblock the commit gate (§14A/§17) that every later sprint depends on.

### KCD-03 `.luacheckrc`
Add at root. Base on §14 template: `std = "lua51"`, `max_line_length = false`, `exclude_files = { "libs/", "audit/", "_dev/", "tests/" }`, ignore `212/self` + `212/event`. `read_globals` gets the WoW API surface this addon uses (`C_Spell`, `C_Timer`, `UnitCastingInfo`, `UnitChannelInfo`, `UnitCanAttack`, `UnitExists`, `IsPlayerSpell`, `IsSpellKnown`, `Settings`, `SettingsPanel`, `DEFAULT_CHAT_FRAME`, `issecretvalue`, `securecallfunction`, `GetSpecialization`, `GetSpecializationInfo`, LSM widget globals, `LibStub`, `CreateFrame`, …). **`globals` (write) gets `KickCDDB`.** While KCD-01 is unresolved, also add `globals = { "KickCD" }` with a justifying comment (remove it once the namespace goes private). Iterate to 0 errors.

### KCD-04 `.pkgmeta`
Add at root: `package-as: KickCD`, no `externals:` block (comment that libs are vendored), `ignore:` list covering `audit/`, `docs/`, `tests/`, `reviews/`, `.luacheckrc`, `.gitignore`, `_dev`, `*.bak`.

### KCD-11 / KCD-12 / KCD-18 TOC fields
Edit `KickCD.toc` metadata block into exact §2.1 order. Add `## OptionalDeps: Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0`, `## X-Standard: https://github.com/tusharsaxena/WowAddonStandards`, `## X-Curse-Project-ID: 1530802`, `## X-Wago-ID: <id>` (obtain or publish on Wago). Set `## Author: add1kted2ka0s`. Ensure a single trailing newline after the last file-listing line.

### KCD-23 prune unused libs
Delete `libs/{AceBucket-3.0,AceComm-3.0,AceHook-3.0,AceLocale-3.0,AceSerializer-3.0,AceTab-3.0}`. Confirm no `LibStub("Ace…")` references them first (grep already shows none loaded in TOC). Risk: none — they are never loaded.

### KCD-15 logo into `media/logos/`
`git mv media/screenshots/kickcd.logo.tga media/logos/` and the `.jpg` beside it. Update `settings/Panel.lua` logo path + the `:1113` comment. Risk: broken texture if the path string isn't updated — verify in-game (logo renders on the landing page).

### KCD-13 / KCD-14 docs restructure
- Move the working-notes brief out of root `CLAUDE.md` into `docs/` (fold into a new `docs/agent-context.md`, or merge into the moved `docs/ARCHITECTURE.md`). Replace root `CLAUDE.md` with a §15.2 stub: tier (Tier 2), "adheres to the Ka0s WoW Addon Standard (URL)", pointer into `docs/`.
- `git mv ARCHITECTURE.md docs/ARCHITECTURE.md`; ensure it carries the §15.3 sections (Overview, Module Map, Settings Schema, **Message Bus table**, Slash Commands table from `COMMANDS`, Event Subscriptions, Taint Notes, Known Limitations). Fix any relative links in README/CLAUDE that pointed at root `ARCHITECTURE.md`.

### KCD-17 / KCD-21 README
- Add the Ka0s-Standard badge/line to the badge row (`README.md:3-5`).
- Add a `## How interrupt tracking works` narrative (visibility-mode gate → `State.IsHostileUnitCasting` → secret-value cooldown/cast pipeline → render). Keep the `Critical settings` prose or nest it beneath the new section; preserve canonical relative order of the optional sections.

---

## B. Naming conventions (mechanical, but touch many call sites)

### KCD-08 bus-message prefix
Rename all five messages to `Ka0s_KickCD_*`. Touch: senders (`core/State.lua:150`, `settings/Panel.lua:62`, `core/KickCD.lua:103,595`), every `RegisterMessage` (`modules/Cooldowns.lua`, `Castbar.lua`, `IconGrid.lua`, `settings/Spells.lua`), and `docs/message-bus.md`. Mechanical find-replace; do it as one atomic commit so no sender/receiver pair drifts. Cover with a bus test (KCD-02) that asserts a rename didn't orphan a receiver.

### KCD-16 shared `NS.PREFIX`
Expose `KickCD.PREFIX = "|cff00ffff[KCD]|r"` once (in `core/Constants.lua` or at the top of `Util.lua` but on the namespace). Have `Util.print` reference it; replace the hand-written literal at `settings/Panel.lua:123` with `KickCD.PREFIX`. After KCD-01 this becomes `NS.PREFIX`.

### KCD-20 `schemaVersion` in global
Rename `DEFAULT_PROFILE.dbVersion` → a `schemaVersion` integer in `db.global` (add a `global` defaults sub-table if none exists). Point `Database:MigrateProfile` (and any `dbVersion` read) at `db.global.schemaVersion`. Ship a one-shot migration that copies an existing per-profile `dbVersion` into `global.schemaVersion` so live profiles aren't re-migrated. Cover with a migration test.

---

## C. Compat routing (§11)

### KCD-10 route spec APIs through Compat
Add to `core/Compat.lua`:
```lua
function Compat.GetSpecialization()
  return (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()) or GetSpecialization()
end
function Compat.GetSpecializationInfo(i)
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
    return C_SpecializationInfo.GetSpecializationInfo(i)
  end
  return GetSpecializationInfo(i)
end
```
Replace the direct calls at `core/KickCD.lua:555,557`, `modules/Cooldowns.lua:78,81`, `modules/IconGrid.lua:286,288`, `settings/Spells.lua:88,90,332,334`. `GetSpellInfo` is already shimmed; audit for any remaining direct `GetSpellInfo` call and route it too. Risk: low — behavior identical; the shim just centralizes the API. Add a Compat test with mocked `C_SpecializationInfo`.

---

## D. Debug console (§12)

### KCD-06 / KCD-07 on-screen console + session-only flag
New `modules/DebugLog.lua`:
- DIALOG-strata `BackdropTemplate` window `KickCDDebugWindow`, 700×344, movable, `SetClampedToScreen`, registered in `UISpecialFrames`, title "KickCD — Debug", divider, close glyph, header state-toggle (`Debug: ON`/`OFF`).
- `ScrollingMessageFrame`, `SetMaxLines(500)`, mouse-wheel scroll.
- **Ship a monospace TTF** under `media/fonts/` (JetBrains Mono, OFL + license file) and register with LSM; expose `KickCD.Const.FONT_MONO`; `SetFont(FONT_MONO, 10, "")` on log + Copy edit box.
- Two pure formatters `FormatPlain` / `FormatColored` (§12.3) — unit-tested.
- `NS.Debug(tag, fmt, ...)` sink gated on `NS.State.debug` first line (zero-alloc when off), appends to console (not chat).
- Copy/Clear buttons (§12.6).

Flag relocation (KCD-07): add `KickCD.State.debug = false` (session-only), route all writes through `DebugLog:SetEnabled(on)` (set flag → refresh header → print ack). Remove `debugLog` from `DEFAULT_PROFILE` and the `self._debugLog`/`db.profile.debugLog` seeding at `core/KickCD.lua:52-55,171-187`; repoint the `debug` schema row / `/kcd debug on|off|toggle` at the new seam. Migrate the General-panel "Debug" checkbox to reflect the session flag (or drop it, since §12.5 wants session-only). Reuse the existing `SKIN`/`ApplySkin` seam if one exists in the window code; otherwise introduce one (§6A).

Risk: medium — new UI surface + font shipping. Keep the existing `/kcd debug spells|castbar|interrupt` dumps but redirect their output into the console via `NS.Debug`.

---

## E. Message-bus receiver target (§4.4)

### KCD-09 Spells panel private target
Add a `NS.NewBusTarget()` factory (fresh AceEvent-embedded table) per §4.4. In `settings/Spells.lua`, replace the two `KickCD:RegisterMessage(...)` calls (`:916-925`) with registrations on a module-owned `NS.Spells.__ev = NS.NewBusTarget()`. Bus test (KCD-02) MUST key callbacks by `(message, target)` so two receivers of one message both fire — proving the fix and guarding regression (AP-33).

---

## F. File peels (§1.2)

### KCD-05 IconGrid (>1500, MUST)
Peel `modules/IconGrid.lua` (1753) into 2–3 flat sibling files, e.g. `IconGrid.lua` (module + lifecycle + message handlers), `IconGrid_Layout.lua` (anchor parsing + grid geometry), `IconGrid_Render.lua` (per-icon texture/cooldown/glow). Publish each via `NS.IconGrid = NS.IconGrid or {}`. Add to TOC in load order. Risk: medium — large mechanical split; lean on the smoke tests (`docs/smoke-tests.md`) plus new unit coverage of the pure layout math.

### KCD-19 on-notice files (SHOULD)
Plan (not urgent) a peel of `settings/Panel.lua` (1266 → Panel + widget-primitive file) and `modules/Castbar.lua` (1422 → build vs. update). Keep both under 1500 meanwhile.

---

## G. Namespace migration (§4.1) — largest, do last

### KCD-01 `_G.KickCD` → private `NS`
Convert every file to the `local addonName, NS = ...` header; replace `KickCD = KickCD or {}` and `_G.KickCD` reads with `NS`. `core/KickCD.lua` passes `NS` to `NewAddon(NS, addonName, ...)` and keeps `NS.addon = addon` — **no** `_G.KickCD = addon` rebind. Settings files replace `LibStub("AceAddon-3.0"):GetAddon("KickCD")` with the `NS` upvalue from their file header. Global frame names may stay `KickCD*` (cosmetic), but the Lua namespace must be private.

Risk: **high, cross-cutting** — every file, every `KickCD.Foo` reference. Sequence it last so the test harness (KCD-02) and lint (KCD-03) are already green to catch regressions; drop the temporary `globals = { "KickCD" }` luacheck entry at the end. Consider doing it file-group by file-group (core → defaults/locales → modules → settings) behind the harness.

---

## Ordering constraints (summary)

1. **A + KCD-03 first** — lint config + `.pkgmeta` + metadata unblock nothing downstream but are cheap and make the gate real.
2. **KCD-02 (tests) before B/C/E/F/G** — everything else should land test-first; the bus mock (AP-33 shape) is a prerequisite for verifying KCD-08/KCD-09.
3. **KCD-08 before/with KCD-09** — rename messages, then fix the receiver target, in one coherent bus pass.
4. **KCD-01 last** — the namespace migration is safest once tests + lint are green and the smaller refactors have settled.
