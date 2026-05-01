# Changes — KickCD PE review

Companion to [`PE_REVIEW.md`](PE_REVIEW.md). Each entry below is a
discrete change set (CR-N) with: scope, files touched, description,
acceptance criteria, dependencies on other CRs.

Severities mirror the review:
- **Critical** — fixes correctness defects (CR-1 … CR-4)
- **High** — fixes architectural drift / perf hotspots (CR-5 … CR-14)
- **Medium** — local correctness / hygiene issues (CR-15 … CR-24)
- **Low** — comment, locale, and naming cleanups (CR-25 … CR-39)

Verification rule for every CR: there is **no Lua compiler / unit-test
harness** in this environment. Every "verify" step is a manual
inspection / in-game smoke test list. Sub-agents must surface diffs
clearly so a human reviewer can spot mistakes.

Conventions:
- Every CR lists `Files` (the files it modifies, exclusively — used by
  the execution plan to detect file-level conflicts between
  parallelised CRs).
- `Depends on:` names hard prerequisites (must land first).
- `Soft-conflict:` names CRs that touch the same file in non-trivial
  ways — those CRs should be sequenced or merged into one workstream.

---

## Critical

### CR-1 — Spec-key normalizer
**Refs:** PE_REVIEW §2.1
**Files:** `core/Util.lua`, `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `core/KickCD.lua`, `settings/Spells.lua`
**Description:**
Add `Util.NormalizeSpecToken(specName)` returning
`(specName or ""):upper():gsub("%s+", "")`. Add
`Util.NormalizeClassToken(classFile)` for symmetry (no-op today, but
defends against future locale quirks). Route every spec/class-key
build through the helpers:
- `modules/Cooldowns.lua:73-77` — `ResolveClassSpec`.
- `modules/IconGrid.lua:248-253` — `getActiveSpecKey`.
- `core/KickCD.lua:499-502` — already correct, refactor to call helper.
- `settings/Spells.lua:546` (`buildSpecIconCache`) — already correct,
  refactor to call helper.
**Acceptance:**
- `grep -nR "specName:upper()" --include='*.lua' .` returns 0 matches in
  active code.
- `grep -nR "string.upper(specName)" --include='*.lua' .` returns 0
  matches in active code.
- All five paths route through `Util.NormalizeSpecToken`.
- A Beast Mastery hunter (English client) gets the same spell list as
  Marksmanship, post-fix (manual smoke test).
**Depends on:** none.
**Soft-conflict:** CR-6 (also touches `Cooldowns.lua` / `IconGrid.lua`).

---

### CR-2 — Stale-watched cleanup in `Cooldowns:Refresh`
**Refs:** PE_REVIEW §2.2
**Files:** `modules/Cooldowns.lua`
**Description:**
When `PollSpell(id)` returns `nil` for a previously-watched spell,
emit a final `KickCD_SPELL_STATE { spellID = id, ready = false,
isActive = false, cdObject = nil, chargeCdObject = nil, charges = nil }`
and `self.watched[id] = nil`. The IconGrid's `OnSpellState` already
handles the no-cdObject branch (renders ready visuals), but it never
removes the icon — that's `Rebuild`'s job. So the message is the
"force ready" signal; the next `Rebuild` will drop the now-orphaned
spell out of `ordered[]`.
Update the message bus contract doc (`docs/CLAUDE_MESSAGE_BUS.md`)
with one line noting the "spell-disappeared" sentinel payload.
**Acceptance:**
- `Refresh()` no longer leaves stale entries when a watched spell
  becomes unavailable.
- Manual smoke: dismiss Hunter pet mid-combat, Counter Shot icon
  reverts to ready / disappears on the next event tick (without
  needing a `/reload`).
**Depends on:** none.
**Soft-conflict:** CR-1 (same file, different sites).

---

### CR-3 — Drop double-dispatch in schema `onChange`
**Refs:** PE_REVIEW §2.3
**Files:** `settings/Castbar.lua`
**Description:**
Remove the manual `KickCD.Castbar:OnConfigChanged(nil, …)` call in the
`castbar.enabled` row's onChange (lines 29-34) — `Helpers.Set` already
fires `KickCD_CONFIG_CHANGED { section = "castbar" }`, which the
Castbar module already subscribes to.
For `castbar.orientation`'s onChange (lines 134-141), the issue is
threefold:
1. The `H.Set("castbar.growDirection", "castbar", newGrow)` call already
   fires CONFIG_CHANGED.
2. The trailing `reskin()` runs `ApplyConfig` directly, *bypassing the
   bus*.
3. The CONFIG_CHANGED dispatch will then run `ApplyConfig` again.
Drop the `reskin()` call. Leave the `H.RefreshAllPanels()` call (it
re-evaluates the `growDirection` dropdown's `values` function — a
panel concern, not a module concern).
For every other row whose `onChange` is just `reskin`, delete the
`onChange = reskin` line entirely (the bus handles it).
**Acceptance:**
- `grep -nR "reskin\|OnConfigChanged" settings/Castbar.lua` shows only
  `H.RefreshAllPanels` survivors and the central
  `KickCD_CONFIG_CHANGED` listener registration.
- Toggling any castbar row in the panel triggers exactly one
  `Castbar:OnConfigChanged` invocation (verify via `/kcd debug log`
  + a counter print).
**Depends on:** none.
**Soft-conflict:** CR-7 (both touch settings/Castbar.lua's onChange wiring).

---

### CR-4 — Scope `Add spell` cooldown-manager validation correctly
**Refs:** PE_REVIEW §2.4
**Files:** `settings/Spells.lua`
**Description:**
The `getCooldownManagerSpellSet` API returns the set for the LOGGED-IN
PLAYER's active spec. The Add-spell popup's OnAccept handler currently
applies that set as a hard gate regardless of which (`selectedClass`,
`selectedSpec`) the user is editing — blocking valid additions on any
non-active spec.
Fix: only apply the cooldown-manager gate when `selectedClass` and
`selectedSpec` match the player's current class+spec. Otherwise fall
through to the lenient `validateSpellInput` path (which only checks
the spell DB).
**Acceptance:**
- A Mage editing `HUNTER / BEASTMASTERY` can add Counter Shot (spell
  147362) without a "not tracked by Cooldown Manager" rejection.
- The same Mage editing their own `MAGE / FROST` list is still gated
  by the cooldown manager (existing behaviour preserved).
**Depends on:** none.
**Soft-conflict:** CR-13 (both touch `getCooldownManagerSpellSet` users).

---

## High

### CR-5 — Hoist `_inCombat` to shared state
**Refs:** PE_REVIEW §3.1
**Files:** `core/Util.lua` (or new `core/State.lua`), `modules/IconGrid.lua`, `modules/Castbar.lua`
**Description:**
Add a tiny shared `KickCD.State` namespace:
```lua
KickCD.State = { inCombat = false }
function KickCD.State.SetInCombat(v) KickCD.State.inCombat = v and true or false end
```
Register a single bootstrap frame at file load (or in
`KickCD:OnInitialize`) that listens to `PLAYER_REGEN_DISABLED` /
`PLAYER_REGEN_ENABLED` and seeds from `InCombatLockdown()` once on
`PLAYER_LOGIN`. Both modules read `KickCD.State.inCombat` instead of
their own `_inCombat`.
Modules still register their own regen-event listeners for **side
effects** (e.g., `IconGrid:RefreshVisibility`), but they no longer
maintain the flag themselves — they just read the central one.
**Acceptance:**
- `grep -nR "_inCombat" --include='*.lua' .` returns 0 matches outside
  `core/State.lua`.
- Both modules read `KickCD.State.inCombat` for visibility decisions.
- Manual: enter/leave combat with both grid and castbar in
  `in_combat` visibility; both transitions stay synchronised.
**Depends on:** none.
**Soft-conflict:** CR-6 (both files), CR-9 (touches IconGrid).

---

### CR-6 — Centralise spell-list traversal in `Database`
**Refs:** PE_REVIEW §3.2
**Files:** `core/Database.lua`, `core/KickCD.lua`, `modules/Cooldowns.lua`, `modules/IconGrid.lua`, `settings/Spells.lua`
**Description:**
Add to `core/Database.lua`:
```lua
function Database:GetSpellList(class, spec)
    -- read-only; returns nil when no list exists; never lazy-creates.
end
function Database:EnsureSpellList(class, spec)
    -- lazy-creates and returns; for mutators only.
end
```
Replace every site that does
`profile.spells[class] and profile.spells[class][spec]` (or a
mutating equivalent) with a call to one of the two helpers:
- `core/KickCD.lua:531-552` (`getProfileSpells`, `getSpellList`,
  `ensureSpellList`).
- `modules/Cooldowns.lua:236-250`.
- `modules/IconGrid.lua:854-861`.
- `settings/Spells.lua:72-86`.
- `core/Database.lua:274-291` (`BuildSpells`).
**Acceptance:**
- `grep -nR "profile.spells\[" --include='*.lua' .` shows only the two
  Database helpers.
- All callers use `GetSpellList` (read-only) where appropriate; only
  `KickCD_ADD_SPELL` / `runSpellsAdd` / `BuildSpells` call
  `EnsureSpellList`.
**Depends on:** none.
**Soft-conflict:** CR-1, CR-2, CR-5 (all touch the same modules).

---

### CR-7 — Route Settings panels via bus only
**Refs:** PE_REVIEW §3.3
**Files:** `core/KickCD.lua`, `settings/Castbar.lua`, `settings/Spells.lua`
**Description:**
Remove every direct cross-module call from settings/* and from the
slash-command layer. Instead, have each settings module subscribe to
the relevant bus message and refresh itself.
- In `settings/Spells.lua`: register the existing `RefreshRows`
  listener for `KickCD_CONFIG_CHANGED { section = "spells" }`.
- In `core/KickCD.lua:558-569` (`commitSpellsChange`): drop the
  direct `KickCD.SettingsSpells.RefreshRows(...)` call. The bus
  message is sufficient.
- In `settings/Castbar.lua`: drop `reskin` (consumed by CR-3).
- Same for any analogous `KickCD.IconGrid:OnConfigChanged(nil, …)`
  surface — none today, but verify no new direct call has crept in.
**Acceptance:**
- `grep -nR "KickCD.SettingsSpells\.\|KickCD.Castbar\.\|KickCD.IconGrid\." --include='*.lua' settings/ core/` shows no direct module-method calls
  outside lifecycle boundaries (i.e., `Build`/`Register` paths).
- Manual: `/kcd spells add 1766 ROGUE OUTLAW` from chat with the
  Spells panel open immediately re-renders the row list.
**Depends on:** CR-3 (consumes the same files).
**Soft-conflict:** CR-22 (also touches `settings/Spells.lua`).

---

### CR-8 — Delete dead `Compat.RegisterAddOnSetting`
**Refs:** PE_REVIEW §3.4
**Files:** `core/Compat.lua`
**Description:**
Delete lines 458-528 (the entire `Settings.RegisterAddOnSetting` shim
section). Confirm via `grep -nR "RegisterAddOnSetting" --include='*.lua' .`
that no caller exists. Update `docs/ARCHITECTURE_COMPAT_LAYER.md` to
remove its mention.
**Acceptance:**
- `grep -nR "RegisterAddOnSetting\|Compat\._registerWarned" --include='*.lua' .`
  returns 0 matches.
- Addon loads and the General / Icons / Cast bar / Spells / Profiles
  panels all render (manual reload).
**Depends on:** none.
**Soft-conflict:** CR-27 (also touches `core/Compat.lua`).

---

### CR-9 — Single shared cooldown-text ticker
**Refs:** PE_REVIEW §3.5
**Files:** `modules/IconGrid.lua`
**Description:**
Replace the per-icon `OnUpdate` (`Icon:StartCooldownText`,
`Icon:StopCooldownText`) with a module-level ticker maintained by
`IconGrid`:
- Module-level `_textIcons = {}` set keyed by widget reference.
- One `C_Timer.NewTicker(0.1, ...)` (or one frame's `OnUpdate`)
  iterates the set and calls a per-icon `:_RenderCooldownText()`.
- `Icon:StartCooldownText` adds to the set; `Icon:StopCooldownText`
  removes.
- Pause the ticker (call `:Cancel()` or short-circuit the OnUpdate)
  when the set is empty.
**Acceptance:**
- `grep -n "SetScript(\"OnUpdate\"" modules/IconGrid.lua` shows only
  the single module-level ticker (no per-icon OnUpdates remain).
- The Icon widgets still expose `StartCooldownText` / `StopCooldownText`
  for compatibility with `Apply`'s call sites (just retargeted
  internally).
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-23 (all touch IconGrid).

---

### CR-10 — Fix Castbar `onUpdate` redundancy
**Refs:** PE_REVIEW §3.6
**Files:** `modules/Castbar.lua`
**Description:**
Stop calling `SetMinMaxValues` and re-reading config every frame.
Concretely:
- In `Castbar:Start`, call `SetMinMaxValues(0, d:GetTotalDuration())`
  on both bars once. The duration object's max only changes on
  `UNIT_SPELLCAST_DELAYED` / `UNIT_SPELLCAST_CHANNEL_UPDATE` — the
  module already has handlers for those (`OnCastDelayed`); add the
  re-set there.
- Cache `cfg().showTime` on cast start (`current.showTime = ...`); use
  it in `onUpdate` instead of the table lookup.
- Inside `onUpdate`, only call SetValue + (conditional)
  SetFormattedText; the per-frame work shrinks from
  6+ method calls to 3.
**Acceptance:**
- `onUpdate` in modules/Castbar.lua makes at most 3 method calls
  (SetValue × 2 + SetFormattedText × 1) per frame on the hot path.
- Manual: cast bar still tracks delayed / haste-modified casts
  correctly (via `OnCastDelayed`).
**Depends on:** none.
**Soft-conflict:** CR-17 (also restructures Castbar lifecycle).

---

### CR-11 — `Util.Debounce` rename + true debounce
**Refs:** PE_REVIEW §3.7
**Files:** `core/Util.lua`, `settings/Spells.lua`
**Description:**
Rename current `Util.Debounce` (leading-edge throttle) to
`Util.Throttle`. Add a *real* debounce:
```lua
function Util.Debounce(ms, fn)
    -- Reset the timer on every call; fire only after the burst stops.
end
```
Update `settings/Spells.lua:167-171` to use whichever semantic it
actually wants. Reading the current consumer it wants throttle (the
50 ms is "coalesce a burst of edits" not "wait for typing to stop"),
so it should call `Util.Throttle`.
Update the docstring on both functions to describe their semantic
unambiguously.
**Acceptance:**
- `grep -n "Util.Debounce\|Util.Throttle" --include='*.lua' .` finds
  one consumer (`settings/Spells.lua`) and that consumer calls
  `Util.Throttle`.
- Both helper functions exist and are documented in `core/Util.lua`.
**Depends on:** none.
**Soft-conflict:** CR-18 (also adds a Throttle consumer).

---

### CR-12 — Warn on layout truncation
**Refs:** PE_REVIEW §3.8
**Files:** `modules/IconGrid.lua`
**Description:**
In `layoutBlock`, when `#secondaries > rows*cols - 1` (the cap minus
primary), print a one-time warning via `KickCD.Util.print` mentioning
the count and the configured cap. Suppress repeats by tracking
`_truncationWarnedFor = "<class>/<spec>/<cap>"` on the module.
**Acceptance:**
- A user with 10 enabled spells and `secondaryRows=1, secondaryCols=4`
  (cap = 5; 1 primary + 4 secondaries) sees a chat warning once
  with the truncation count (5).
- Resetting the cap or changing spec re-arms the warning.
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-23 (all touch IconGrid).

---

### CR-13 — Cache `getCooldownManagerSpellSet`
**Refs:** PE_REVIEW §3.9
**Files:** `settings/Spells.lua`
**Description:**
Memoise the cooldown-manager set in a module-local
`_cmCache = nil` field. Compute on first `Add spell…` open after
login; invalidate (`_cmCache = nil`) on `TRAIT_CONFIG_UPDATED` and
`PLAYER_SPECIALIZATION_CHANGED`.
**Acceptance:**
- The `Add spell…` popup OnAccept walks `Enum.CooldownViewerCategory`
  at most once per (login × spec change).
**Depends on:** CR-4 (changes the gating logic).
**Soft-conflict:** CR-4, CR-7, CR-22 (all touch settings/Spells.lua).

---

### CR-14 — `Util.DeepCopy` and use in `RestoreDefaults`
**Refs:** PE_REVIEW §3.10
**Files:** `core/Util.lua`, `core/Database.lua`, `settings/Panel.lua`, `settings/Spells.lua`
**Description:**
Promote `core/Database.lua:234-239`'s `deepCopy` to `Util.DeepCopy`.
Replace:
- `core/Database.lua:234-239` (`deepCopy`).
- `settings/Spells.lua:56-61` (`deepCopy`).
- `settings/Panel.lua:879-885` (the shallow copy in `RestoreDefaults`).
**Acceptance:**
- One `Util.DeepCopy` definition in `core/Util.lua`.
- `grep -nR "function deepCopy\|local deepCopy" --include='*.lua' .`
  returns 0 matches.
**Depends on:** none.
**Soft-conflict:** CR-22 (touches settings/Spells.lua).

---

## Medium

### CR-15 — Drop redundant `icons` fire on `/kcd resetposition`
**Refs:** PE_REVIEW §4.1
**Files:** `settings/Panel.lua`
**Description:**
In `Helpers.ResetIconPosition` (line 946-958), remove the
`Helpers.FireConfigChanged("icons")` call. The `general` fire is
sufficient (`IconGrid:OnConfigChanged`'s `general` branch re-anchors).
**Acceptance:**
- `Helpers.ResetIconPosition` fires `general` exactly once.
- `/kcd resetposition` repositions the grid (manual).
**Depends on:** none.
**Soft-conflict:** none.

---

### CR-16 — Dedupe spellID at `BuildActiveList`
**Refs:** PE_REVIEW §4.2
**Files:** `modules/IconGrid.lua`
**Description:**
In `IconGrid:BuildActiveList`, track a local `_seen = {}` set; skip
entries whose `spellID` is already in the set, with a debug log
when `KickCD._debugLog` is on. Keeps `pool.active` strictly 1:1 with
spellID.
**Acceptance:**
- A profile with `{ {spellID=6552}, {spellID=6552} }` produces
  exactly one icon, with a debug-log "duplicate spellID" message.
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-12, CR-23.

---

### CR-17 — Split `Castbar:Reskin` from `Castbar:RenderCast`
**Refs:** PE_REVIEW §4.3
**Files:** `modules/Castbar.lua`
**Description:**
Refactor `Castbar:ApplyConfig` so that:
- `Castbar:Reskin()` (renamed) handles config-driven work
  (orientation, size, child anchors, fonts, backdrops, spark
  rotation). Called from `OnConfigChanged` / `OnGridLayout` /
  `OnProfileChanged`.
- `Castbar:RenderCast(rec)` handles per-cast work (set texture, set
  name, seed bar values, ApplyState). Called from `Start`.
`Castbar:Start` calls `RenderCast(rec)` only — not `Reskin`.
**Acceptance:**
- Cast start no longer recomputes orientation / fonts / anchors.
- Per-cast render path makes < 8 widget calls (vs ~40 in
  `ApplyConfig` today).
- Config-changed path still runs the full re-skin.
**Depends on:** CR-10 (also restructures Castbar runtime).
**Soft-conflict:** CR-3, CR-10.

---

### CR-18 — Throttle ColorPicker writes
**Refs:** PE_REVIEW §4.4
**Files:** `settings/Panel.lua`
**Description:**
Wrap the `commit(r,g,b,a)` closure in `makeColorPicker` (line 666-671)
in `Util.Throttle(50, ...)`. The `OnValueConfirmed` write path stays
immediate (it only fires on Cancel; the user expects a snap-back).
**Acceptance:**
- Dragging a color slider fires `KickCD_CONFIG_CHANGED` at most ~20
  times/sec (verified via `/kcd debug log` or a counter).
- Clicking OK / Cancel still commits / reverts immediately.
**Depends on:** CR-11 (introduces `Util.Throttle`).
**Soft-conflict:** none.

---

### CR-19 — Tooltip ownership check on icon `OnLeave`
**Refs:** PE_REVIEW §4.5
**Files:** `modules/IconGrid.lua`
**Description:**
In the icon's `OnLeave` script (line 359-361), guard
`GameTooltip:Hide()` with `if GameTooltip:GetOwner() == self then …`.
**Acceptance:**
- Hovering off a KickCD icon doesn't dismiss tooltips owned by other
  addons (manual: hover over an action bar with a tooltip, then move
  mouse over a KickCD icon and back — the action bar tooltip should
  reappear/persist correctly).
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-12, CR-16, CR-23.

---

### CR-20 — Drop `_G.KickCD` fallback in late settings files
**Refs:** PE_REVIEW §4.6
**Files:** `settings/Spells.lua`, `settings/Profiles.lua`
**Description:**
Replace the `LibStub … or _G.KickCD` boilerplate at the top of both
files with a clean `LibStub("AceAddon-3.0"):GetAddon("KickCD")` (no
fallback). If LibStub is somehow missing, the addon is in an
unrecoverable state — failing fast is better than silent fallback.
**Acceptance:**
- Both files show the canonical
  `local KickCD = LibStub("AceAddon-3.0"):GetAddon("KickCD")`.
- `grep -n "or _G.KickCD" --include='*.lua' .` returns 0 matches.
**Depends on:** none.
**Soft-conflict:** CR-7, CR-13, CR-14, CR-22 (all touch
settings/Spells.lua).

---

### CR-21 — `OpenSettings` defers when subcategory not yet built
**Refs:** PE_REVIEW §4.7
**Files:** `core/KickCD.lua`
**Description:**
In `KickCD:OpenSettings` (line 810-826), if the General subcategory
isn't registered yet AND we have no fallback to open, print an
"opening shortly" message and schedule a one-shot retry via
`C_Timer.After(0.5, function() self:OpenSettings(input) end)` (max
3 retries). Do not fall through to `SettingsCategoryID` — that lands
on the empty parent.
**Acceptance:**
- Manual: `/kcd config` immediately after login (before the
  subcategory builders fire) lands on the General page once the
  subcategory completes registration. No blank page.
**Depends on:** none.
**Soft-conflict:** none.

---

### CR-22 — Read-only `getActiveList`; `ensureSpellList` for mutators
**Refs:** PE_REVIEW §4.8
**Files:** `settings/Spells.lua`
**Description:**
Subsumes CR-6's `Database:GetSpellList` / `EnsureSpellList` for this
file specifically. Walk every call site of `getActiveList` (used in
`buildSpellsHeader`, `RefreshRows`, `KICKCD_ADD_SPELL` OnAccept,
`KICKCD_RESET_SPELLS` OnAccept) and replace with the read-only or
mutator helper as appropriate. Remove the local `getActiveList` and
`getProfileSpells` helpers.
**Acceptance:**
- Browsing class/spec dropdowns no longer pollutes
  `KickCDDB.profiles.<name>.spells` with empty class/spec tables
  (verify by inspecting the saved-vars file after a session of
  dropdown-only browsing).
**Depends on:** CR-6.
**Soft-conflict:** CR-7, CR-13, CR-14, CR-20.

---

### CR-23 — Short-circuit `RefreshAllGlows` when condition unchanged
**Refs:** PE_REVIEW §4.9
**Files:** `modules/IconGrid.lua`
**Description:**
Maintain `_lastGlowGate = { hostileCasting, interruptible }` at the
module level. `RefreshAllGlows` skips iteration when neither field
moved. Recompute on every event the function is called from.
**Acceptance:**
- A boss casting many short abilities doesn't trigger N icon
  re-evaluations per cast event when the gate state is unchanged.
- Glow still flips correctly when the gate moves (manual: target a
  caster mob, watch glow on/off as casts start/stop).
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-12, CR-16, CR-19.

---

### CR-24 — Schema-shape validation at file load
**Refs:** PE_REVIEW §4.10
**Files:** `settings/Panel.lua`
**Description:**
Add `Helpers.ValidateSchema()` that asserts every Schema row has:
- `def.panel` ∈ `{ general, icons, castbar, spells, profiles }`.
- `def.path` non-empty string.
- `def.section` ∈ `{ general, icons, castbar, spells, debug }`.
- `def.type` ∈ `{ bool, number, string, color }`.
Wire it into the bootstrap registration code: print clear
`|cffff0000KickCD schema error|r:` lines, but don't refuse to load.
**Acceptance:**
- A deliberately-broken schema row triggers a chat error at load.
- A correct schema loads silently.
**Depends on:** none.
**Soft-conflict:** none.

---

## Low (cleanup, hygiene, doc)

### CR-25 — Rewrite stale doc references in module headers
**Refs:** PE_REVIEW §5.1
**Files:** `core/KickCD.lua`, `core/Compat.lua`, `core/Util.lua`,
`core/Database.lua`, `defaults/Spells.lua`, `modules/Cooldowns.lua`,
`modules/IconGrid.lua`, `modules/Castbar.lua`, every `settings/*.lua`
**Description:**
Replace every reference to `docs/TECHNICAL_DESIGN.md`,
`docs/RESEARCH.md`, `docs/REQUIREMENTS.md`, `docs/EXECUTION_PLAN.md`
with the per-section file under `docs/ARCHITECTURE_*.md` or
`docs/CLAUDE_*.md` that's now canonical. Use prose where no
direct mapping exists.
**Acceptance:**
- `grep -nR "TECHNICAL_DESIGN\|RESEARCH.md\|REQUIREMENTS.md\|EXECUTION_PLAN.md" --include='*.lua' .` returns 0 matches outside `docs/legacy/`.
**Depends on:** none.
**Soft-conflict:** every CR (this touches almost every file). Land last.

---

### CR-26 — Drop FR/NFR tags from comments
**Refs:** PE_REVIEW §5.2
**Files:** module + settings files where they appear
**Description:**
Find and replace comment references to `FR-N.N` / `NFR-N` with prose
where the comment is still useful, delete where it's not. Sample list:
- `core/Database.lua:14` `(DEFAULT_PROFILE shape per TECHNICAL_DESIGN §4)` → drop.
- `defaults/Spells.lua:2-3` (legacy doc refs) → drop.
- `modules/IconGrid.lua` numerous `FR-2.6` / `FR-2.7` / `FR-2.8` /
  `FR-8.2` / `FR-8.4` references → replace with prose like "see
  per-icon cooldown text behaviour" / inline the rationale.
- `core/Database.lua:372` `(FR-10.2)` → drop.
- `modules/Cooldowns.lua` `FR-2.8` → prose.
- `defaults/Spells.lua` `FR-7.6` → drop (categories are obvious from
  the table).
- `locales/enUS.lua:3` `REQUIREMENTS NFR-7` → drop.
**Acceptance:**
- `grep -nR "FR-[0-9]\|NFR-[0-9]" --include='*.lua' .` returns 0
  matches.
**Depends on:** none.
**Soft-conflict:** every CR — land alongside CR-25.

---

### CR-27 — Move `IsHostileUnitCasting` into a shared helper
**Refs:** PE_REVIEW §5.3
**Files:** `core/Compat.lua`, new `core/State.lua` (or
`modules/Visibility.lua`), `modules/IconGrid.lua`, `modules/Castbar.lua`
**Description:**
Move `Compat.IsHostileUnitCasting` and `Compat.ApplyInterruptibleAlpha`
out of `Compat` (their job isn't API normalisation; it's the addon's
visibility decision) into a shared visibility helper. `Compat` keeps
the raw `GetCastingInfo` / `GetChannelInfo` shims.
Rename: `KickCD.Visibility.IsHostileUnitCasting` (or under
`KickCD.State.IsHostileUnitCasting` if CR-5 lands first and we extend
the state namespace).
**Acceptance:**
- `Compat` exports only API-shape normalisers, no feature decisions.
- All call sites are updated (one in IconGrid, one in Castbar, one
  in `core/KickCD.lua` debug surface).
**Depends on:** CR-5 (shared state namespace), CR-8 (clean Compat).
**Soft-conflict:** CR-5, CR-8.

---

### CR-28 — Standardise `_G.X` vs bare `X` lookups
**Refs:** PE_REVIEW §5.4
**Files:** `modules/IconGrid.lua`, `modules/Castbar.lua`, `core/Compat.lua`
**Description:**
Pick one (recommendation: bare for Blizzard globals known to always
exist, `_G.` for those guarded by an existence check). Document the
rule in `docs/CLAUDE_CONVENTIONS.md`. Sweep the three files for
inconsistencies.
**Acceptance:**
- Convention is documented and applied uniformly across the modules.
**Depends on:** none.
**Soft-conflict:** every IconGrid / Castbar / Compat CR — land late.

---

### CR-29 — Enrich `KickCD_GRID_LAYOUT` payload
**Refs:** PE_REVIEW §5.5
**Files:** `modules/IconGrid.lua`, `modules/Castbar.lua`,
`docs/CLAUDE_MESSAGE_BUS.md`, `docs/ARCHITECTURE_MESSAGE_CONTRACT.md`
**Description:**
Change `IconGrid` to send
`{ gridFrame = grid, primaryIcon = ordered[1], width, height }` in
`KickCD_GRID_LAYOUT` instead of `{}`. Update `Castbar:OnGridLayout` to
prefer the payload over `KickCD.IconGrid:GetGridFrame` /
`GetPrimaryIcon`. Keep the public accessors for backwards-compat (no
breaking external API).
Update both message-contract docs.
**Acceptance:**
- `Castbar:OnGridLayout` no longer reaches back through
  `KickCD.IconGrid` if the payload is populated.
- `KickCD_GRID_LAYOUT` payload documented in both docs.
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-10, CR-12, CR-16, CR-17, CR-19, CR-23.

---

### CR-30 — Promote magic constants
**Refs:** PE_REVIEW §5.6
**Files:** new `core/Constants.lua`, `modules/IconGrid.lua`,
`modules/Castbar.lua`, `settings/Panel.lua`
**Description:**
Add `core/Constants.lua` (loaded after `core/Compat.lua` per the TOC)
with named constants:
- `KickCD.Const.GCD_UPPER = 1.6`
- `KickCD.Const.CASTBAR_INSIDE_INSET = 4`
- `KickCD.Const.CASTBAR_OUTSIDE_INSET = 4`
- `KickCD.Const.PANEL_HEADER_TOP = 20`
- `KickCD.Const.PANEL_HEADER_HEIGHT = 54`
- `KickCD.Const.PANEL_PADDING_X = 16`
- `KickCD.Const.PANEL_DEFAULTS_W = 110`
Update consumers. Keep this CR optional — it's pure refactoring;
delivers no behaviour change. Mark "ok to skip" in EXECUTION_PLAN.
**Acceptance:**
- All listed constants live in one file; consumers reference them.
**Depends on:** none.
**Soft-conflict:** every IconGrid / Castbar / Panel CR.

---

### CR-31 — Add missing locale keys
**Refs:** PE_REVIEW §5.7
**Files:** `locales/enUS.lua`
**Description:**
Add explicit en-US entries for every user-visible string used in
`settings/Castbar.lua`, `settings/Icons.lua` (anchor labels), and
`settings/General.lua` (visibility-mode labels). Currently these
fall through to the metatable's identity return; making them
explicit gives translators a starting point.
**Acceptance:**
- Every `L["..."]` in active settings code has a matching entry in
  `locales/enUS.lua`. (Verify by extracting all `L["..."]` keys and
  diffing against the locale file.)
**Depends on:** none.
**Soft-conflict:** none.

---

### CR-32 — `LCG_KEY` scoping
**Refs:** PE_REVIEW §5.8
**Files:** `modules/IconGrid.lua`
**Description:**
Add a constant for "primary slot" / "secondary slot" so that future
combined-glow scenarios (interruptible-target-cast PLUS spell-ready)
can run two glows on one icon with distinct keys. Today, ship with
just one key (`"KickCD"`) but document the namespacing convention so
the next contributor knows where to extend.
**Acceptance:**
- Comment on `LCG_KEY` explains the single-key constraint and how to
  add a second key safely.
**Depends on:** none.
**Soft-conflict:** CR-1, CR-5, CR-9, CR-12, CR-16, CR-19, CR-23, CR-29.

---

### CR-33 — Drop dead `Profiles._registered` / `_panel` fields
**Refs:** PE_REVIEW §5.9
**Files:** `settings/Profiles.lua`
**Description:**
Delete `Profiles._registered` and `Profiles._panel`. The `Register`
shim (lines 82-92) becomes a no-op or returns the result of `Build`
without caching.
**Acceptance:**
- `grep -n "_registered\|_panel" settings/Profiles.lua` returns only
  the `Build` return value.
**Depends on:** none.
**Soft-conflict:** CR-20.

---

### CR-34 — Fire `KickCD_CONFIG_CHANGED` after `OnDragStop`
**Refs:** PE_REVIEW §5.11
**Files:** `modules/IconGrid.lua`, `modules/Castbar.lua`
**Description:**
After persisting the dragged anchor, fire
`KickCD_CONFIG_CHANGED { section = "general" }` (for icons) /
`{ section = "castbar" }` (for the cast bar). Today nothing listens
to that signal, but firing it makes the bus contract complete and
defends against a future "anchor-aware" subscriber.
**Acceptance:**
- Both modules' `OnDragStop` handlers fire the relevant message.
- Drag-and-release still produces only one CONFIG_CHANGED event
  (the modules' own handlers are idempotent).
**Depends on:** none.
**Soft-conflict:** CR-1, CR-3, CR-5, CR-9, CR-10, CR-12, CR-16, CR-17, CR-19, CR-23, CR-29.

---

### CR-35 — Helper for "first return of `UnitCastingInfo`"
**Refs:** PE_REVIEW §5.12
**Files:** `core/Compat.lua`
**Description:**
Add `Compat._firstReturn(fn, ...)` that returns the first return of
`fn(...)` (or `nil` if `fn` is missing). Use it where the current
code wraps the call in `(...)` to collapse multi-returns. The helper
makes the intent explicit. Apply at:
- `core/Compat.lua:299-300` (`UnitCastingInfo` truthy check).
- `core/Compat.lua:327-335` (cast / channel name checks).
- `modules/IconGrid.lua:115-119` (`isTargetCasting`).
**Acceptance:**
- `grep -n "(_G.UnitCastingInfo(unit))" --include='*.lua' .` 0 matches
  (replaced by helper-call form).
**Depends on:** none.
**Soft-conflict:** CR-8 (also touches Compat.lua), CR-27.

---

### CR-36 — Document `notInterruptible` plain-after-flip invariant
**Refs:** PE_REVIEW §5.13
**Files:** `modules/Castbar.lua`, `docs/CLAUDE_CASTBAR.md`,
`docs/CLAUDE_SECRET_VALUES.md`
**Description:**
One-paragraph note in both docs and at line 1062 of Castbar:
`OnInterruptibilityChanged` writes a plain bool to
`current.notInterruptible`, replacing whatever secret-tainted value
came from `UnitCastingInfo`. After the flip, `ApplyState` runs against
a plain bool — still safe (the curve evaluator accepts both forms).
**Acceptance:**
- Both docs mention the plain-after-flip invariant.
- A code comment at the assignment site cross-references the doc.
**Depends on:** none.
**Soft-conflict:** CR-3, CR-10, CR-17, CR-29, CR-34.

---

### CR-37 — Document `BuildSpells` "no re-seed if non-empty" intent
**Refs:** PE_REVIEW §5.15
**Files:** `core/Database.lua`, `docs/CLAUDE_OVERVIEW.md` (or a new
`docs/CLAUDE_SPELL_LIFECYCLE.md`)
**Description:**
Per user direction, this behaviour is **intentional** — a user who
clears every row has done so deliberately and shouldn't be re-seeded
on next login. Add a docstring paragraph at `Database:BuildSpells`
making the policy explicit, and a small note in the user-facing
docs explaining how to recover defaults if the user changes their
mind (`/kcd reset spells` for everything; `/kcd spells reset` for
just the active spec).
**Acceptance:**
- The docstring explains "no re-seed unless the table is fully
  empty" and points users at the two reset commands.
**Depends on:** CR-6 (uses centralised list helpers).
**Soft-conflict:** CR-6.

---

### CR-38 — Improve gating-error messages for slash `set`
**Refs:** PE_REVIEW §5.16
**Files:** `core/KickCD.lua`
**Description:**
The `def.valueGate` plumbing already exists at line 318-323 — extend
it: when set, also include the gate's *valid options* in the error
message:
```
Allowed values: UP, DOWN (depends on castbar.orientation = VERTICAL;
flip orientation to HORIZONTAL for RIGHT/LEFT)
```
**Acceptance:**
- A `/kcd set castbar.growDirection LEFT` while orientation=VERTICAL
  prints a message that explains the dependency AND tells the user
  which gate value enables which option set.
**Depends on:** none.
**Soft-conflict:** none.

---

### CR-39 — `db.profile.dbVersion` + migrator scaffold
**Refs:** PE_REVIEW §5.17
**Files:** `core/Database.lua`
**Description:**
Add `DEFAULT_PROFILE.dbVersion = 1` and a `Database:MigrateProfile()`
hook. For v0.1.0 the migrator is a no-op (`if v == 1 then return end`),
but the scaffold lets a future schema change ship a migrator next to
the change. Run `MigrateProfile` at `Init` after `BuildSpells`, and
on `OnProfileChanged`.
**Acceptance:**
- Existing profiles load without change of behaviour.
- A second `dbVersion = 2` migrator can be added in one place
  without touching the bootstrap.
**Depends on:** none.
**Soft-conflict:** CR-6, CR-37.

---

## Out-of-scope (deferred)

These review findings are intentionally NOT executed under this plan
and are listed here for traceability:

| Ref | Finding | Reason |
|-----|---------|--------|
| §5.10 | Frame names are global (`KickCDIconGrid` / `KickCDCastbar`) | User decision: leave as-is (`/framestack` ergonomics). |
| §5.14 | No automated test scaffold | No Lua compiler available in this environment. Re-open when one is. |
| §5.15 | `BuildSpells` no-reseed intentional | Documented under CR-37 instead of changed. |

---

## Summary of file impact

A grep-friendly reverse index (file → CRs that touch it). Used by
`EXECUTION_PLAN_PE_REVIEW.md` to detect cross-stream conflicts.

| File | CRs |
|------|-----|
| `core/Util.lua` | CR-1, CR-5, CR-11, CR-14 |
| `core/Compat.lua` | CR-8, CR-25, CR-27, CR-28, CR-35 |
| `core/Database.lua` | CR-6, CR-14, CR-25, CR-26, CR-37, CR-39 |
| `core/KickCD.lua` | CR-1, CR-6, CR-7, CR-21, CR-25, CR-26, CR-38 |
| `core/State.lua` (new) | CR-5, CR-27 |
| `core/Constants.lua` (new) | CR-30 |
| `modules/Cooldowns.lua` | CR-1, CR-2, CR-6, CR-25, CR-26, CR-28 |
| `modules/IconGrid.lua` | CR-1, CR-5, CR-6, CR-9, CR-12, CR-16, CR-19, CR-23, CR-25, CR-26, CR-28, CR-29, CR-30, CR-32, CR-34, CR-35 |
| `modules/Castbar.lua` | CR-3, CR-5, CR-10, CR-17, CR-25, CR-26, CR-27, CR-28, CR-29, CR-30, CR-34, CR-35, CR-36 |
| `defaults/Spells.lua` | CR-25, CR-26 |
| `locales/enUS.lua` | CR-26, CR-31 |
| `settings/Panel.lua` | CR-14, CR-15, CR-18, CR-24, CR-25, CR-26, CR-30 |
| `settings/General.lua` | CR-25, CR-26 |
| `settings/Icons.lua` | CR-25, CR-26 |
| `settings/Castbar.lua` | CR-3, CR-7, CR-25, CR-26 |
| `settings/Spells.lua` | CR-1, CR-4, CR-6, CR-7, CR-13, CR-14, CR-20, CR-22, CR-25, CR-26 |
| `settings/Profiles.lua` | CR-20, CR-25, CR-33 |
| `docs/CLAUDE_*.md`, `docs/ARCHITECTURE_*.md` | CR-2, CR-8, CR-25, CR-29, CR-36, CR-37 |
