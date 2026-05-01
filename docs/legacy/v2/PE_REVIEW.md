# Principal-Engineer Review — KickCD v0.1.0

Reviewer perspective: senior Lua/WoW addon author auditing a ~8.5k-LoC,
single-folder addon. Focus areas: architectural coherence, design
consistency, anti-patterns, logic gaps, performance, and bugs.

Citations are `path:line` against the tree at HEAD (`52b86a9`). Findings
are ordered by severity within each section.

---

## 0. Executive summary

KickCD is a thoughtfully engineered v0.1 with a clear sense of identity:
a closed message bus, a schema-driven settings layer that auto-wires CLI
+ panel UI, a clean Compat shim isolating WoW 12.0's "secret value"
protected-spell quirks, and pooled icon widgets. The two long modules
(`IconGrid`, `Castbar`) read well, and the secret-value strategy
(curve-evaluated alpha/tint, `SetAlphaFromBoolean` for boolean gates) is
the correct approach for 12.0.

That said, the codebase has measurable gaps:

- A **critical correctness bug** in spec-key normalisation that breaks
  the addon for every spec whose localised name contains whitespace
  (Beast Mastery in English; more in non-English locales).
- Several **architectural drifts** from the documented "closed message
  bus": modules reach across each other directly, the schema's
  `onChange` redundantly duplicates bus dispatch, and `Compat`
  exports a 70-line shim that nothing calls.
- **Duplicated mutable state** (`_inCombat` lives in both `IconGrid` and
  `Castbar`) and a **duplicated 5-place spec-list path traversal** that
  needs a single owner.
- **Per-frame Lua work** in `Castbar:onUpdate` that re-reads config,
  re-resolves duration, and writes both stacked bars unconditionally;
  in `IconGrid` per-icon `OnUpdate` rather than a single shared ticker.
- A handful of smaller logic gaps: stale `watched[]` after a poll
  returns nil, layout cap silently truncating, `Add spell` validating
  against the wrong spec's cooldown manager, the `Util.Debounce`
  semantics being closer to throttle than debounce.

None of the issues block ship for a v0.1 alpha, but the spec-key bug
and the message-bus drift should be addressed before any external user
testing. Total estimated effort to land everything in this review:
~3–4 days of focused work, parallelisable across 3 workstreams (see
`EXECUTION_PLAN_PE_REVIEW.md`).

---

## 1. Strengths (worth preserving)

These are working well and should not be lost during refactoring.

- **Closed message bus contract** (4 messages, documented payloads).
  `docs/CLAUDE_MESSAGE_BUS.md` and module headers stay in sync. The
  `KickCD_GRID_LAYOUT` empty-payload broadcast lets `Castbar` track
  `IconGrid` geometry without hard coupling.
- **Schema-driven settings layer** (`settings/Panel.lua` +
  `settings/General.lua` / `Icons.lua` / `Castbar.lua`) wires CLI and
  panel widgets from one source of truth. Adding a new option = one
  schema row. This is the right shape.
- **12.0 secret-value strategy** (`core/Compat.lua:28-67`,
  `modules/IconGrid.lua:195-240`, `modules/Castbar.lua:776-789`):
  curves evaluated C-side, secrets passed straight to Blizzard C
  methods (`SetCooldownFromDurationObject`, `SetFormattedText`,
  `SetAlphaFromBoolean`, `EvaluateColorValueFromBoolean`), never bound
  to Lua locals. This is the supported pattern.
- **Pooled icon widgets** (`modules/IconGrid.lua:803-837`) avoid frame
  churn on every spec change / spell-list edit.
- **`Mixin` over `setmetatable` on Blizzard frames**
  (`modules/IconGrid.lua:262, 364`) — correct.
- **Per-state stacked widgets in `Castbar`** with alpha-curve
  switching driven by the secret `notInterruptible` boolean. The
  approach is unusual but justified by the secret-value protection;
  it's a deliberate tradeoff that the alternatives can't match.
- **AceDB profiles** with per-character default scope and racial
  appending on first creation.

---

## 2. Critical findings

### 2.1 Spec-key normalisation drops whitespace at default-build time but not at lookup time
**Severity:** critical (functional regression for at least one spec).

`defaults/Spells.lua` keys specs with a no-whitespace upper-case token:
`BEASTMASTERY`, `MARKSMANSHIP`, `MISTWEAVER`, … (no spec key in the
defaults file contains whitespace). The seeded profile inherits that
shape via `Database:BuildSpells` (`core/Database.lua:274-291`).

But the runtime lookup paths uppercase the localised spec name without
stripping whitespace:

- `modules/Cooldowns.lua:73-77` — `specName:upper()`.
- `modules/IconGrid.lua:248-253` — `string.upper(specName)`.

`GetSpecializationInfo`'s second return is the **localised display
name**: in English that includes "Beast Mastery" (with a space). So
Beast Mastery hunters get:

- Default seeded at `profile.spells.HUNTER.BEASTMASTERY`.
- Runtime lookup tries `profile.spells.HUNTER["BEAST MASTERY"]` → `nil`
  → empty `Cooldowns.watched` → empty `IconGrid.ordered` → blank grid.

Three other places in the codebase do the right thing
(`settings/Spells.lua:546` / `core/KickCD.lua:499-502` /
`settings/Spells.lua:578`), all with `:upper():gsub("%s+", "")`.

**Fix:** introduce a single `Util.NormalizeSpecToken(specName)` and
route every spec-key build through it. (`Util.NormalizeClassToken` for
symmetry — class file tokens never have spaces today, but factoring
out keeps the boundary single.)

**Impact in non-en locales:** several languages produce multi-word spec
names where English uses single tokens; the bug is broader than just
BM Hunter outside English clients.

### 2.2 `Cooldowns:Refresh` retains stale state for spells that disappear mid-fight
**Severity:** critical for talent/pet swaps.

`modules/Cooldowns.lua:279-303`: when `PollSpell` returns `nil` (e.g.
the player's pet was just dismissed and a pet-only ability is no longer
`IsSpellAvailable`), the loop short-circuits without updating
`self.watched[id]`. The icon stays rendered with whatever the last
non-nil state was, and **no `KickCD_SPELL_STATE` is fired**, so
`IconGrid` never learns the spell is gone. Only `Rebuild` cleans this
up — and `Rebuild` only runs on `SPELLS_CHANGED` /
`TRAIT_CONFIG_UPDATED` / `PLAYER_SPECIALIZATION_CHANGED` /
`KickCD_PROFILE_CHANGED` / `KickCD_CONFIG_CHANGED { spells | general }`.

Pet summon/dismiss does fire `SPELLS_CHANGED` in modern clients, so the
common case is covered; but anything that flips availability without
those events (e.g., a spell removed by `RemoveSpell` from an addon, an
encounter mechanic that suppresses a spell) leaves a phantom icon in
the grid.

**Fix:** when `PollSpell` returns `nil` for a watched id, emit a
`KickCD_SPELL_STATE` with `ready = false, isActive = false, cdObject = nil,
chargeCdObject = nil` (or equivalent "force full rebuild" signal) and
remove the entry from `watched[]`.

### 2.3 The schema's `onChange` for `castbar.enabled` doubles the bus dispatch
**Severity:** correctness-adjacent (not a bug today, but a sign of
architectural drift the next change will trip on).

`settings/Castbar.lua:29-34`:

```lua
onChange = function()
    if KickCD.Castbar and KickCD.Castbar.OnConfigChanged then
        KickCD.Castbar:OnConfigChanged(nil, { section = "castbar" })
    end
end,
```

`Helpers.Set` (called immediately before the schema's `onChange`)
already fires `KickCD_CONFIG_CHANGED { section = "castbar" }`, which
the Castbar module already subscribes to. Toggling `Enable cast bar`
runs the entire `OnConfigChanged` pipeline twice per click. Same issue
in `settings/Castbar.lua:134-141` (orientation onChange explicitly
calls `H.Set` for `growDirection` which fires CONFIG_CHANGED, then
calls `reskin()` which runs `ApplyConfig` directly, then the
CONFIG_CHANGED dispatch eventually runs `ApplyConfig` again).

The pattern is `Helpers.Set` dispatches via the bus; schema rows that
*also* directly call into the live module bypass and double the bus.
The bypass is also a bus contract violation per
`docs/CLAUDE_MESSAGE_BUS.md`.

**Fix:** drop the manual `OnConfigChanged` / `reskin` calls. The bus is
the single dispatch; if a section's bus payload should also rebuild
something the module doesn't currently rebuild, fix the module's
`OnConfigChanged` listener instead.

### 2.4 `Add spell…` validates against the logged-in player's cooldown manager set, regardless of which class/spec the user is editing
**Severity:** functional regression for cross-class editing.

`settings/Spells.lua:122-148`, `202-213`: `getCooldownManagerSpellSet`
walks every `CooldownViewerCategory` enum value via `C_CooldownViewer`,
which returns the data **for the logged-in player's currently-active
spec**. There is no class/spec parameter on the API. A Mage editing
the `HUNTER / BEASTMASTERY` list cannot add a Hunter spell because it's
not in the Mage's cooldown viewer.

**Fix:** either drop the cooldown-manager validation entirely (the
fallback `validateSpellInput` is enough — it confirms the spell exists
in the spell DB), OR gate the cooldown-manager check to only apply
when the editor's selected class/spec matches the player's active
class/spec.

---

## 3. High-priority issues

### 3.1 Module-local mutable state duplicated across modules
`_inCombat` lives independently in `modules/IconGrid.lua:138` and
`modules/Castbar.lua:69`. Both flip on `PLAYER_REGEN_DISABLED` /
`PLAYER_REGEN_ENABLED`, and both are seeded from `InCombatLockdown()`
in their respective `OnEnable`. The values stay in lockstep today by
construction, but:

- A future module that needs combat state has to add its own copy.
- A bug in one's seeding (e.g., a bad `OnEnable` ordering) silently
  diverges from the other.

**Fix:** hoist combat state to a tiny shared "AddonState" namespace
(can live in `core/Util.lua` or a new `core/State.lua`) with one
seed/listen pair, and have both modules read from it.

### 3.2 Spec-list path traversal duplicated 5 times
The `db.profile.spells[CLASS][SPEC]` walk appears in:
- `core/KickCD.lua:531-552` (slash command helpers)
- `modules/Cooldowns.lua:236-250`
- `modules/IconGrid.lua:854-861`
- `settings/Spells.lua:72-86`
- `core/Database.lua:274-291`

Each variant has subtly different defensive guards (`type(...) == "table"`
vs `if not ... then return end` vs `parent[key] = parent[key] or {}`)
and the path gets re-built five times whenever a spell is mutated.

**Fix:** centralise on `Database:GetSpellList(class, spec)` and
`Database:EnsureSpellList(class, spec)` (read-only and lazy-create
variants). Every consumer goes through these.

### 3.3 Direct cross-module reach-around violates the closed-bus contract
- `core/KickCD.lua:558-569` (`commitSpellsChange`) calls
  `KickCD.SettingsSpells.RefreshRows` directly to nudge the open
  panel after a slash mutation.
- `settings/Castbar.lua` `reskin()` (line 16-20) calls
  `KickCD.Castbar:ApplyConfig()` directly on every onChange.
- `settings/Spells.lua` calls `Spells:RefreshRows()` from inside
  StaticPopup OnAccept handlers, etc.

These bypasses are working today but contradict the documented
"closed message bus" contract (`docs/CLAUDE_MESSAGE_BUS.md`). The
right shape is:

- `Cooldowns` and `IconGrid` already listen for
  `KickCD_CONFIG_CHANGED { section = "spells" }`.
- Have **`SettingsSpells`** listen for the same message and rebuild
  its own rows.
- Slash mutations only need to fire the bus message; no direct
  RefreshRows call.

This makes adding a new spells-listener (e.g., a future "spell list
preview" module) a one-liner instead of requiring updates to every
mutation site.

### 3.4 `Compat.RegisterAddOnSetting` is dead code
`core/Compat.lua:458-528` (~70 lines) implements a three-signature shim
for `Settings.RegisterAddOnSetting`. **Nothing calls it.** Every
settings panel uses `Helpers.Get/Set` directly against `db.profile`.
This is leftover from an earlier design (visible in the pre-history of
the file). It's a maintenance liability — a reader has to puzzle out
why it exists, and someone may "fix" the schema layer to use it,
introducing a real bug.

**Fix:** delete the function and its imports.

### 3.5 `IconGrid` `OnUpdate` per icon for cooldown text
`modules/IconGrid.lua:395-437`: every icon with `showCooldownText` on
runs its own per-frame `OnUpdate` ticking at 0.1s, each calling
`SetFormattedText` plus a `Compat.GetSpellCooldown` re-poll on the
full-cooldown branch. With 7 cooldowns active this is 7 OnUpdate
scripts, 70 calls/sec, 7 plain-API spell polls/sec.

Single shared ticker (one `C_Timer.NewTicker` at module level + a
`tickingIcons` set) cuts the per-frame fixed cost ~7×. Not urgent,
but worth doing before adding more icons or features (e.g., dual
charges support).

### 3.6 `Castbar:onUpdate` does redundant per-frame work
`modules/Castbar.lua:763-792`:

```lua
frame.bar.interruptible:SetMinMaxValues(0, d:GetTotalDuration())
frame.bar.uninterruptible:SetMinMaxValues(0, d:GetTotalDuration())
```

`SetMinMaxValues` is called twice (once per stacked bar) **every
frame**, but `d:GetTotalDuration()` only changes on cast start /
`UNIT_SPELLCAST_DELAYED` / `UNIT_SPELLCAST_CHANNEL_UPDATE`. Setting
the same range every frame is pure waste. Same for `cfg().showTime`
re-read every frame.

The per-frame Lua-local cache is forbidden by secret-value rules for
`d:GetTotalDuration()` itself, but you can:

- Set the range once on cast start / delayed, then leave it alone.
- Cache `cfg().showTime` and the per-state alpha decision on cast
  start (or on `KickCD_CONFIG_CHANGED { castbar }`).

### 3.7 `Util.Debounce` is mislabelled — it's a leading-edge throttle, not a debounce
`core/Util.lua:109-130`: the implementation schedules the callback on
the FIRST call and ignores subsequent calls within the window
(updating `pendingArgs` only). A canonical debounce resets the timer
on every call so the callback only fires after the burst stops. The
current implementation fires every 50 ms during a sustained burst —
which matches a leading-edge throttle.

The current consumer (`settings/Spells.lua:167-171`) treats it as a
"coalesce 50 ms of work" coalescer, and that works fine with either
semantic. But the docstring (`-- Wrap a function so rapid successive
calls collapse into a single delayed execution. The trailing call wins
(latest args used).`) is misleading.

**Fix:** rename to `Util.Throttle` (or implement true debounce — a
one-line change to reschedule on each call). Don't leave the misleading
name in place.

### 3.8 `IconGrid:layoutBlock` silently truncates when `visibleCount > rows*cols`
`modules/IconGrid.lua:1141-1143`: overflow secondaries are
`:Hide()`'d. The user gets a smaller grid than they configured with no
indication that some spells are dropped.

**Fix:** either (a) emit a `Util.print` warning when truncation occurs,
or (b) auto-expand `rows` to fit. Probably (a) — the user explicitly
chose `rows × cols`.

### 3.9 `getCooldownManagerSpellSet` not cached
`settings/Spells.lua:122-148`: walks every `CooldownViewerCategory`
enum value on every `Add spell` click. Not catastrophic, but trivially
cacheable (invalidate on `TRAIT_CONFIG_UPDATED` /
`PLAYER_SPECIALIZATION_CHANGED`).

### 3.10 `Helpers.RestoreDefaults` shallow-copies arrays only
`settings/Panel.lua:872-894`: `for i, vv in ipairs(v) do copy[i] = vv end`
fails for nested tables. Today every default that is a table is a flat
RGBA array, but `castbar.interruptible` / `castbar.uninterruptible` are
nested tables in the database — they aren't flagged as schema rows
(individual leaf paths are), so the shallow copy never touches them.
Fine today, fragile if a future schema row uses a nested-table
default.

**Fix:** generic deep copy (already exists in
`core/Database.lua:234-239`; promote it to `Util.DeepCopy` and reuse).

---

## 4. Medium-priority issues

### 4.1 Duplicate calls / wasted dispatch on `/kcd resetposition`
`settings/Panel.lua:946-958`: fires both `general` and `icons` config
changes. `IconGrid:OnConfigChanged` runs `BuildCurves` + `Layout` +
`ApplyLock` on `icons`, and re-anchor + `RefreshVisibility` +
`ApplyLock` on `general`. The icons section didn't actually change —
only `general`'s anchor sub-key did. `Layout` is cheap, but it's still
unnecessary work.

**Fix:** route through `general` only; `IconGrid:OnConfigChanged`'s
`general` branch already re-anchors.

### 4.2 `pool.active` keyed by `spellID` clobbers on duplicate enables
`modules/IconGrid.lua:803-816`: if a user adds the same spell ID twice
(e.g. `/kcd spells add 6552; /kcd spells add 6552` with the second one
hand-edited into the saved-vars), `AcquireIcon(spellID)` returns a
fresh widget but writes `pool.active[spellID] = btn` — orphaning the
prior assignment. The orphan widget still lives, will get released
correctly on `ReleaseAll`, but in the meantime a `KickCD_SPELL_STATE`
update only refreshes one of the two visible widgets.

**Fix:** either dedupe at `BuildActiveList` time (skip duplicate IDs
with a debug-log warning), or move pool keying off spellID to a
stable handle.

### 4.3 `Castbar:Start` runs the heavy `ApplyConfig` on every cast
`modules/Castbar.lua:856-899`: `ApplyConfig` recomputes orientation,
size, child anchors, font lookups, backdrop tables, spark rotation —
all on every cast start. The expensive parts only depend on profile
config, not on the cast itself. Per-cast work should be limited to
"set texture, set name, seed bar values, ApplyState".

**Fix:** split `Castbar:Reskin` (config-driven, runs on
`OnConfigChanged` / `OnGridLayout`) from `Castbar:RenderCast` (cast
record-driven, runs on Start).

### 4.4 `ColorPicker` `OnValueChanged` fires per-frame during drag
`settings/Panel.lua:670`: drag a color slider and you fire
`KickCD_CONFIG_CHANGED { castbar }` per frame, which runs
`Castbar:OnConfigChanged` → `ApplyAnchor` + `ApplyConfig` per frame.
On low-end systems this thrashes the UI.

**Fix:** wrap color writes in `Util.Throttle(50ms)`.

### 4.5 `OnLeave` on icons hides any active GameTooltip indiscriminately
`modules/IconGrid.lua:359-361`: `GameTooltip:Hide()` on every icon
leave. If another addon owns the tooltip (e.g., the user is moving
their mouse off the KickCD grid into a tooltip-owning frame), this
hides a tooltip the icon never set.

**Fix:** `if GameTooltip:GetOwner() == self then GameTooltip:Hide() end`.

### 4.6 `_G.KickCD = addon` rebinding relies on load order
`core/KickCD.lua:21-32`: at promotion time, every prior file that
captured `KickCD = KickCD or {}` and stamped fields onto it is
preserved (AceAddon mutates in place). But two settings files have a
fallback path:

- `settings/Spells.lua:13-15`
- `settings/Profiles.lua:9-11`

```lua
local KickCD = LibStub and LibStub("AceAddon-3.0", true)
                  and LibStub("AceAddon-3.0"):GetAddon("KickCD", true)
                  or _G.KickCD
```

If `LibStub` is missing the file falls back to `_G.KickCD` — at which
point we're either in a broken state (no Ace3 at all) or a real-time
race. The fallback adds bug-camouflage and shouldn't exist; both
files run after `core/KickCD.lua` per the TOC, so AceAddon must be
present.

**Fix:** drop the `or _G.KickCD` fallback; assert the addon resolves
or no-op the file.

### 4.7 `Settings.OpenToCategory` may land on the empty parent
`core/KickCD.lua:810-826`: tries the General subcategory first and
falls back to `SettingsCategoryID` (the parent). Per Blizzard 12.0,
the parent category is hidden when it has children. If the General
subcategory hasn't registered yet (race at PLAYER_LOGIN), the user
gets a blank page instead of an error.

**Fix:** if no subcategory is yet available, defer the open to
`PLAYER_LOGIN` or print a "settings still loading, try again" message.

### 4.8 `db.profile.spells` lazy-creation pollutes the saved vars
`settings/Spells.lua:78-86`: every `getActiveList()` call creates
empty class/spec tables for the currently-selected dropdown class+spec
even when no spells are added. Browse the dropdown across 13 classes
× 4 specs = 52 empty tables persisted in `KickCDDB`. Profile bloat
over time and a behavioural surprise (a user expects "do nothing"
when browsing).

**Fix:** make `getActiveList` read-only; add `ensureSpellList` for
mutators only.

### 4.9 `IconGrid:RefreshAllGlows` re-runs glow logic for every cast event
`modules/IconGrid.lua:1437-1450`: every `UNIT_SPELLCAST_*` triggers
`RefreshAllGlows`, which iterates every active icon. With 7 icons
and a hostile boss casting frequent abilities, this is per-icon
`StartGlow / StopGlow` cycles every cast event. The idempotency
gate at `Icon:StartGlow` (line 498-503) helps but doesn't prevent the
full Stop+Start path on a glow-kind change.

**Fix:** maintain a single `_glowsActive` flag at the module level;
short-circuit `RefreshAllGlows` if the trigger condition hasn't
materially changed (no target swap, no new cast start, …).

### 4.10 No schema-shape validation
`settings/Panel.lua:803-859`: `RenderSchema` happily renders a row
with a misspelled `panel` field, a missing `path`, or a `type` it
doesn't know. Silent visual gap rather than a clear failure.

**Fix:** at file load, assert `def.panel`, `def.path`, `def.type ∈
{bool, number, string, color}`, `def.section` resolves to a known
listener.

---

## 5. Low-priority / nits

### 5.1 Stale doc references in module headers
`core/KickCD.lua:2`, `core/Compat.lua:2`, `core/Util.lua:2`,
`defaults/Spells.lua:2`, `core/Database.lua:1`, `modules/Cooldowns.lua`
docstrings reference `docs/TECHNICAL_DESIGN.md §3.1 / §3.3 / §4 /
§7.4` and `RESEARCH.md §6`. These docs are flagged stale per
`docs/CLAUDE_DOCS_STALE.md` and the canonical references now live in
the per-section files indexed from `ARCHITECTURE.md` / `CLAUDE.md`.

### 5.2 FR/NFR tags scattered through comments
Comments cite `FR-2.6`, `FR-2.7`, `FR-2.8`, `FR-7.6`, `FR-8.2`,
`FR-8.4`, `FR-10.2`, `NFR-7`. These map back to
`docs/legacy/v1/REQUIREMENTS.md` which is no longer the source of
truth. Replace with prose where the comment is still useful, drop
where it's not.

### 5.3 `Compat.IsHostileUnitCasting` is a feature decision masquerading as a Compat shim
`core/Compat.lua:296-302`: combines `UnitExists`, `UnitCanAttack`,
`UnitCastingInfo`, `UnitChannelInfo` truthy checks. That's two
modules' shared visibility decision, not an API normalisation. It
belongs in a shared helper, not in the layer whose job is to
abstract API churn.

### 5.4 Inconsistent `_G.X` vs bare `X` lookups
`modules/IconGrid.lua:113-119` uses `_G.UnitCastingInfo`;
`modules/IconGrid.lua:1289-1298` uses bare `InCombatLockdown`. WoW's
`_G` resolves identically either way, but the inconsistency is
distracting.

### 5.5 `KickCD_GRID_LAYOUT` payload is empty
`modules/IconGrid.lua:1186-1188`: subscribers (`Castbar`) reach back
through `KickCD.IconGrid:GetGridFrame()` /
`KickCD.IconGrid:GetPrimaryIcon()`. Including `{ gridFrame,
primaryIcon, w, h }` in the payload would make the bus self-contained
and remove one of the few cross-module direct accesses.

### 5.6 Magic constants
`GCD_UPPER = 1.6` (`modules/IconGrid.lua:80`), `INSIDE_INSET / OUTSIDE_INSET = 4`
(`modules/Castbar.lua:476-477`), `HEADER_TOP / HEADER_HEIGHT = 20 / 54`
(`settings/Panel.lua:149-154`). Acceptable for an addon this size,
but worth promoting to a single `core/Constants.lua` if the codebase
grows.

### 5.7 Locale completeness
`locales/enUS.lua` is missing keys for Cast bar, Visibility,
Anchor mode, the 13 anchor labels, etc. — the metatable fall-through
makes them work, but translators have nothing to translate against.

### 5.8 `LCG_KEY` is a single global key
`modules/IconGrid.lua:468`: `"KickCD"` is fine for v0.1 but locks the
addon out of running multiple coexisting glows on the same icon
(future "interruptible-target-cast PLUS spell-ready" combined glow).

### 5.9 `Profiles._registered` / `Profiles._panel` are unused
`settings/Profiles.lua:70-72`: written but never read outside the
`Register` shim. Dead state.

### 5.10 Frame names are global
`KickCDIconGrid`, `KickCDCastbar` — collision risk. Probably fine in
practice; could be unnamed (use the local `frame` reference) since no
external addon needs to find them by name.

### 5.11 `OnDragStop` writes `db.profile.anchors.icons` without firing CONFIG_CHANGED
`modules/IconGrid.lua:1227-1233`: silent write. No module currently
needs the signal (the icon grid already moved itself), but if
`Castbar` ever adds an "anchor to free position of grid" mode, the
silence becomes a bug.

### 5.12 `UnitCastingInfo` callers wrap the call in extra parens
`core/Compat.lua:299-300, 327-335`,
`modules/IconGrid.lua:115-119`: the parens collapse the multi-return
to a single value. Works as intended but reads as defensive
boilerplate that begs explanation; a one-liner comment or a
`firstReturnOf(_G.UnitCastingInfo, unit)` helper would help.

### 5.13 `Castbar:OnInterruptibilityChanged` clobbers the secret-tainted bool
`modules/Castbar.lua:1062-1086`: writes
`current.notInterruptible = (evt == "...NOT_INTERRUPTIBLE")` — a plain
boolean. The CLAUDE_CASTBAR.md comment elsewhere says "may be plain
or secret"; after this handler runs, it's plain. Not a bug (the
`ApplyState` path handles plain bools fine), but the invariant
documentation is now subtly wrong post-flip. Worth a one-line note.

### 5.14 No automated test scaffold
`docs/CLAUDE_TESTING.md` is purely manual. Even a spec-key
normalisation unit test (`util_spec.lua` running headless via a Lua
51 + WoW API stub harness) would have caught finding 2.1. WoW
addons can be tested with `LuaUnit` + a small WoW-API stub
(`UnitClass`, `UnitRace`, `GetSpecialization`, `_G.issecretvalue =
function() return false end`, etc.).

### 5.15 `Database:BuildSpells` only seeds when `next(profile.spells) == nil`
`core/Database.lua:259-261`: a user who clears every spell row from
the UI and reloads gets `profile.spells = { CLASS = { SPEC = {} } }`,
which is non-empty but functionally bare. Subsequent logins won't
re-seed even though the user might expect them to.

Borderline: this is also the *correct* behaviour if "empty spec list"
is intentional. Document the trade-off; consider a "Reseed defaults"
button at the spec level.

### 5.16 `applyFromText` (slash `set`) bypasses dropdown's `valueGate`
`core/KickCD.lua:308-326`: validates against the current
`def.values()` return — which honours `valueGate`. But the user's
error message merely says "Allowed values: …" without exposing why
those are the allowed values when `valueGate` is set. There's a
fallback that *does* expose this (line 318-323), but only fires when
`def.valueGate` is set in the schema. `castbar.growDirection`'s
schema sets `valueGate = "castbar.orientation"` so the message is
helpful there; other dropdowns gated by sibling settings (none today)
won't get the same helpful suffix.

### 5.17 No version/migration field in `db.profile`
`core/Database.lua:18-213`: AceDB's defaults handle additive changes
fine. Renames or restructures need explicit migration; there's no
`db.profile.dbVersion` and no `OnProfileLoaded` migrator. Add one
proactively before the schema evolves further.

---

## 6. Recommendations summary

| Priority | Theme | Fixes |
|----------|-------|-------|
| Critical | Spec-key normalisation | One shared normaliser; route every spec-key build through it |
| Critical | Stale `Cooldowns.watched` | Emit `SPELL_STATE` and unwatch when `PollSpell` returns nil |
| Critical | Schema/bus dispatch doubling | Drop manual `OnConfigChanged` / `reskin` calls; route through bus |
| Critical | Add-spell validation across class/spec | Drop or scope cooldown-manager check |
| High | Shared mutable state | Hoist `_inCombat` to a single owner |
| High | Spec-list path traversal | Centralise on `Database:GetSpellList` / `EnsureSpellList` |
| High | Cross-module reach-around | Route through bus (every consumer subscribes to `KickCD_CONFIG_CHANGED`) |
| High | Dead `Compat.RegisterAddOnSetting` | Delete |
| High | Per-icon `OnUpdate` thrash | One module-level ticker |
| High | Per-frame Castbar work | Cache `cfg().showTime`; set range only on duration change |
| High | `Util.Debounce` mislabelled | Rename to `Throttle` or implement true debounce |
| High | Layout truncation silent | Warn when `visibleCount > rows*cols` |
| High | Cooldown-manager set not cached | Cache + invalidate on talent / spec events |
| Medium | Various small bugs (5 items) | See §4 |
| Low | Doc / comment hygiene + nits (~17 items) | See §5 |

`CHANGES_PE_REVIEW.md` enumerates each fix as a discrete change set
with files, scope, and acceptance criteria.
`EXECUTION_PLAN_PE_REVIEW.md` groups them into parallelisable
workstreams.
