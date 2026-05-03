# Ka0s KickCD — Proposed Changes (HLD + LLD)

Companion to `01_FINDINGS.md`. Findings collapse into five themes; each theme has an HLD section explaining the rationale and an LLD section with concrete change-sets keyed by finding ID.

---

## HLD — Themes

### Theme A: Tighten the combat-state ownership boundary
**Covers:** F-001, F-002, F-018.

The addon currently owns combat state in `core/State.lua` via a bootstrap CreateFrame; modules `Castbar` and `IconGrid` independently register `PLAYER_REGEN_*` for their own side effects and read `KickCD.State.inCombat` from the handler. The flag is updated *before* the modules see it only because of TOC load order — a fragile invariant.

**Proposed direction.** Consolidate the regen events behind a single State-owned message (`KickCD_COMBAT_STATE`). Modules subscribe to the message and never hook the raw events; State is the only file with `RegisterEvent("PLAYER_REGEN_*")`. The dispatch order becomes explicit (the message fires from inside State's handler, after the flag write) and the codebase has one obvious place to add new combat-state side effects.

**Alternatives considered.**
- *Inline `InCombatLockdown()` in each handler.* Rejected — the codebase explicitly rejects this pattern (one-frame lag).
- *Move State.lua's bootstrap into an AceEvent module.* Rejected — `KickCD.State.inCombat` is read at file-load time by some helpers (e.g. inside `shouldBeVisible` closures), so wiring it into the AceAddon lifecycle changes initialisation ordering and risks `nil` reads on the seam.

**Trade-off.** One additional message on the bus (the closed bus contract from CLAUDE.md grows from 4 messages to 5 — `docs/message-bus.md` updates). Cost: low; benefit: ordering-correct by construction, single registration site.

### Theme B: Reduce per-event handler load via UnitEvent filtering
**Covers:** F-003.

Both `Castbar` and `IconGrid` register UNIT_SPELLCAST_* for all units, then early-return on `unit ~= "target"` inside the handler. AceEvent does not expose `RegisterUnitEvent`, so the workaround is a private CreateFrame frame using `Frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")`, which the dispatcher turns into a method call back into the AceEvent module.

**Proposed direction.** Add a small helper in `core/Util.lua` (`Util.RegisterTargetEvent(module, eventName, methodName)`) that creates a private dispatch frame, calls `RegisterUnitEvent`, and forwards into `module[methodName](module, event, unit, ...)`. Both modules adopt the helper for their UNIT_SPELLCAST_* registrations.

**Alternatives considered.**
- *Patch AceEvent.* Rejected — vendored library; we don't own the upstream.
- *Switch off Ace3 entirely.* Rejected — premature; the rest of the addon benefits from AceAddon/AceEvent/AceDB.

**Trade-off.** A small bit of API surface in Util; one place to test.

### Theme C: Remove dead surface, fix locale drift
**Covers:** F-004, F-005, F-006, F-011, F-018.

Three `KickCD.Settings*` exports, two `:Register()` shims, one missing locale key, ~14 unused locale strings, and one bootstrap inconsistency. All are independent local fixes.

**Proposed direction.** Direct removal / addition. Each finding is a one-or-two-line edit.

**Trade-off.** None — pure cleanup.

### Theme D: Comment + naming refresh
**Covers:** F-007, F-008, F-009, F-010, F-012, F-013, F-019.

A scattered set of stale-comment / inconsistent-naming / unused-record-field findings. None affects behaviour. Best handled as one focused pass when a contributor is already in the file for unrelated reasons (i.e. defer; don't open a dedicated PR).

**Proposed direction.** Make the cleanup a milestone in the execution plan with explicit "do this opportunistically" framing.

### Theme E: Defer perf optimizations until measured
**Covers:** F-015, F-016.

Two perf-leaning findings. Both call out unnecessary work; both are documented as "low-impact" by the existing comments and the review. Profiling first is the right move.

**Proposed direction.** Capture as TODO-level notes in the relevant files (a one-liner comment), not a code change. If a frame-rate report comes in, the work is then de-blocked.

### Theme F: Schema helper relocation (deferred)
**Covers:** F-017.

A structural niggle: `Helpers.SetAndRefresh` is the canonical write path but lives in a file that loads after its callers. The fallback path works, so this is not blocking. Capture as a doc note in `docs/conventions.md` so future contributors understand the load-order subtlety.

---

## LLD — Per-finding change sets

### F-001 + F-002 + F-018 — Combat-state message bus consolidation

**Files touched:** `core/State.lua`, `modules/IconGrid.lua`, `modules/Castbar.lua`, `docs/message-bus.md` (or wherever the four-message contract is documented).

**State.lua change.** Inside the bootstrap `OnEvent` handler, after `State.SetInCombat`, `KickCD:SendMessage("KickCD_COMBAT_STATE", { inCombat = State.inCombat })` (with a nil-guard for the LSM-style "before AceAddon mixes in" race — `KickCD.SendMessage and KickCD:SendMessage(...)`). Keep the PLAYER_LOGIN handling unchanged. After PLAYER_LOGIN fires once, `boot:UnregisterEvent("PLAYER_LOGIN")` to mirror `core/LSMPatch.lua`'s pattern.

**Module change.** Replace `RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")` and `..._ENABLED` lines in both modules with a single `RegisterMessage("KickCD_COMBAT_STATE", "OnCombatStateChanged")`. The handler reads `payload.inCombat` and dispatches to the existing `RefreshVisibility` (IconGrid) / `Reevaluate` or `Stop` (Castbar) logic.

**Documentation.** `docs/message-bus.md` adds the fifth message with sender/listeners/payload-shape entry.

**Risk.** Low. The current code already takes the message-driven path for every other state change; combat is the outlier.

**Tests.** Smoke-test cold-login → enter combat → leave combat → /reload → verify icon grid + cast bar show/hide on each transition.

### F-003 — Target-unit-event filtering helper

**Files touched:** `core/Util.lua`, `modules/Castbar.lua`, `modules/IconGrid.lua`.

**Util.lua change.**
```lua
-- core/Util.lua
function Util.RegisterTargetEvent(module, eventName, handlerName)
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent(eventName, "target")
    f:SetScript("OnEvent", function(_, event, unit, ...)
        local fn = module[handlerName]
        if fn then fn(module, event, unit, ...) end
    end)
    return f
end
```

**Module change.** In `Castbar:OnEnable`, replace the per-event `RegisterEvent` lines for the UNIT_SPELLCAST_* family with `Util.RegisterTargetEvent(self, "UNIT_SPELLCAST_START", "OnCastStart")` (and similarly for STOP, FAILED, INTERRUPTED, DELAYED, CHANNEL_*, INTERRUPTIBLE/NOT_INTERRUPTIBLE). Same for `IconGrid:OnEnable`'s UNIT_SPELLCAST_* lines.

**Risk.** Medium. AceEvent's UnregisterAllEvents won't release these private frames; if the addon is disabled at runtime they'll keep firing into a possibly-disabled module. Mitigation: keep frame references on the module (`self._targetEventFrames = {}`) and run `f:UnregisterAllEvents()` on `OnDisable`.

**Tests.** UNIT_SPELLCAST_START on a party member should NOT trigger Castbar:OnCastStart anymore — verify by `/kcd debug log` showing no spurious dispatches in a 5-man.

### F-004 — Drop dead exports

**Files touched:** `settings/Spells.lua`, `settings/Profiles.lua`, `settings/Panel.lua`.

**Change.** Delete `KickCD.SettingsSpells = Spells` (settings/Spells.lua:20), `KickCD.SettingsProfiles = Profiles` (settings/Profiles.lua:14), and `KickCD.SettingsCategoryID = main:GetID()` (settings/Panel.lua:1230). Update the doc comment in `core/KickCD.lua:835-840` to drop the `KickCD.SettingsCategoryID` mention.

**Risk.** None. Confirmed zero readers via grep.

### F-005 — Drop back-compat `:Register()` shims

**Files touched:** `settings/Spells.lua`, `settings/Profiles.lua`.

**Change.** Delete `function Spells:Register()` (settings/Spells.lua:957-961) and `function Profiles:Register()` (settings/Profiles.lua:77-90), plus their explanatory comments.

**Risk.** None. Zero callers in the codebase.

### F-006 — Add missing locale key

**Files touched:** `locales/enUS.lua`.

**Change.** Add the line `L["Cannot open settings during combat."] = "Cannot open settings during combat."` next to other slash-command strings (around line 154).

**Risk.** None.

### F-007 — Drop `_maxC` from the watched-state record

**Files touched:** `modules/Cooldowns.lua`.

**Change.** Delete `_maxC = maxC,` from the return table in `Cooldowns:PollSpell` (line 183). If a future "show n/MAX charges" feature wants this, surface it through a deliberate field rename.

**Risk.** None. Field is write-only.

### F-008 — Document `state.charges` semantics or rename

**Files touched:** `modules/Cooldowns.lua` (header comment near line 38).

**Change.** Add a one-line note to the message contract in the header: `charges` is the raw `currentCharges` from `C_Spell.GetSpellCharges` (or nil for uncharged spells); a value of `0` means "no charges available right now" — the IconGrid renders it as a "0" badge but `state.ready` is false. Alternative: don't rename; the comment is enough.

**Risk.** None.

### F-009 — Localise the remaining slash output

**Files touched:** `core/KickCD.lua`, `locales/enUS.lua`.

**Change.** Wrap each bare-English `p(self, "...")` in `L[...]` and add the keys to `enUS.lua`. Examples: `"icon grid locked"`, `"icon grid unlocked"`, `"db not initialized yet"`, `"unknown command '%s'"`, `"unknown debug subcommand '%s'"`, etc. (~20 keys.)

**Risk.** Low; the metatable fallback ensures missing translations still render the literal key.

**Defer:** README states "English only" — the user may not want this until a translation effort starts. Capture as a one-off pass and don't ship in a feature PR.

### F-010 — Refresh stale per-file version stamps

**Files touched:** Every file with a "KickCD v0.1" header comment.

**Change.** Either (a) drop the per-file version stamp, or (b) point at `KickCD.VERSION` (e.g. "see core/KickCD.lua for the canonical version"). Option (a) is cheaper.

**Risk.** None.

### F-011 — Remove unused locale strings

**Files touched:** `locales/enUS.lua`.

**Change.** Delete the 14 confirmed-unused string definitions enumerated in F-011. KEEP the category strings (`L["interrupt"]`, etc.) — those are accessed via dynamic key.

**Risk.** None.

### F-012 — Update or delete the `OpenSettings` doc comment

**Files touched:** `core/KickCD.lua` lines 835-840.

**Change.** The comment claims `OpenSettings` waits on `KickCD.SettingsCategoryID + KickCD.Settings.main`; in fact it only checks `self.Settings.main`. Drop the `SettingsCategoryID` half of the sentence. Combined with F-004 this becomes obvious.

**Risk.** None.

### F-013 — Document `current` in the Castbar header

**Files touched:** `modules/Castbar.lua` near lines 60-72.

**Change.** Add a 2-line comment documenting that `current` is a record from `Compat.GetCastingInfo` / `Compat.GetChannelInfo` and that it is mutated in place by `OnInterruptibilityChanged` (the "plain-after-flip invariant"). The existing line-1162-1171 comment block could be the canonical reference; the file header should cross-link to it.

**Risk.** None.

### F-014 — Adopt `KickCD:GetModule("IconGrid", true)` in Castbar's accessor fallback

**Files touched:** `modules/Castbar.lua` lines 96-112.

**Change.** Replace `KickCD.IconGrid and KickCD.IconGrid.GetGridFrame` with `local m = KickCD:GetModule("IconGrid", true); return m and m:GetGridFrame()`. Keeps the same null-tolerant shape; aligns with AceAddon idiom; removes the need for `IconGrid` to publish itself on `KickCD.IconGrid` at module load.

After this is in, also consider dropping `KickCD.IconGrid = IconGrid` at `modules/IconGrid.lua:1727` — a quick grep shows only the Castbar accessor and the slash dispatcher's debug commands (`KickCD.Compat.DebugInterrupt` etc., not `KickCD.IconGrid`) reference it.

**Risk.** Low. `GetModule(name, true)` is silent on missing modules.

### F-015, F-016 — Defer; capture as TODO

**Files touched:** `modules/Castbar.lua` (above `Reskin`), `modules/IconGrid.lua` (above `BuildCurves`).

**Change.** Add a `-- TODO(perf): only re-skin / rebuild curves when relevant config keys actually changed.` one-liner.

**Risk.** None.

### F-017 — Document the load-order subtlety

**Files touched:** `docs/conventions.md`.

**Change.** Add a section note: "`Helpers.SetAndRefresh` lives in `settings/Panel.lua` (loaded last). Slash commands that fire before settings/ has loaded (i.e. between OnInitialize and PLAYER_LOGIN) hit the documented fallback path that writes directly to `db.profile` and emits `KickCD_CONFIG_CHANGED`."

**Risk.** None.

### F-019 — Disambiguate `/kcd reset spells` vs panel "Defaults"

**Files touched:** `core/KickCD.lua` (the `COMMANDS` "reset" entry's description string).

**Change.** Update the description from `"Reset a panel to defaults — \`/kcd reset <general|icons|castbar|spells>\`"` to `"Reset a panel to defaults. \`/kcd reset spells\` rebuilds EVERY spec's list — for one spec, use \`/kcd spells reset\`."` Or split into separate entries (`reset` for the schema-driven panels and a different name for the all-spells reset).

**Risk.** None — pure UX clarification.
