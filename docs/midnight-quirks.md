# Midnight quirks — secret values, frame mixin, and other 12.0 traps

Catalog of WoW Midnight (Interface 12.0.x) behaviors that bite the addon. **Read this before touching cooldown, cast, or visibility code.** When something breaks at patch time, this is where to look first.

<!-- BEGIN VENDORED: quirks catalog v2.103.1 (source: WowAddonStandards) -->
> Part of the **[Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/STANDARDS.md)** — the split standard. This section is vendored whole into every addon's `docs/midnight-quirks.md` (§1), so its links are absolute. Cross-references use the `filename-§N` form (see the index's section map).

## Client quirks

The client behaviors the collection paid for more than once. Each entry here was discovered
**independently in two or more Ka0s repositories**, written up in each, and promoted by a harvest so the
next addon reads it instead of rediscovering it. A behavior one repo found stays in that repo's
`docs/midnight-quirks.md` until a second repo meets it.

*Why this section exists.* By 2026-11-06 eleven addons kept a private `docs/midnight-quirks.md`, 2,073
lines and about 133 entries between them, and about 81 of those entries were 21 behaviors written up
independently two to eight times. Nine of the eleven opened with their own restatement of the 12.0 secret
rules. Three write-ups contradicted this standard, and one contradiction was this standard's own error
(events-frames-taint-§2, *The combat-start edge*). A catalog was proposed and deferred twice, on
2026-08-25 and 2026-09-22, because an inventory rots; the build stamp per entry (§1) is the answer to that
objection (WowAddonStandards `harvests/2026-11-06/02_FINDINGS.md`, F3-01; every write-up quoted in
`harvests/2026-11-06/03_EVIDENCE.md`, Part A).

### 1. How an entry is written, and how it expires (MUST)

Every entry **MUST** carry:

- **The behavior**, stated as what the client does, not as advice.
- **Measured:** the client build or date it was observed on, where any write-up recorded one. An entry with
  no measurement says *not measured*; that is a weaker entry, not a missing field.
- **Cost:** what happened to an addon that did not know it.
- **Client:** the client it was measured on, `Retail` or `Forever` (clients-§1). An entry that names none is a Retail entry, which is every entry written before v2.103.0; a Forever behavior is written with `Forever` and its build, and it is not assumed to hold on Retail.
- **Do:** the workaround, as a rule an addon can follow.
- **Source:** the deepest write-up — the repo and document that probed furthest — and the harvest that
  promoted it. Every version is quoted in that harvest's `03_EVIDENCE.md`.

**Expiry.** An entry describes a client, and clients move. When the retail interface number moves past the
newest *Measured* stamp in an entry and an addon observes otherwise, the entry is corrected in a standard
release — not worked around in the addon. An entry nobody can reproduce moves to §6 as an open probe rather
than being deleted, because the behavior may only have moved.

**What an addon does with this section (MUST): carry it as a vendored block.** This section is the one
part of the standard an addon carries a **copy** of, because it is reference data about the game client
that a working addon needs offline, next to the code that works around it — not a rule, which is only ever
pointed at. Every addon's `docs/midnight-quirks.md` (documentation-§3) is two parts: the vendored block,
opened by a `BEGIN VENDORED` HTML comment naming the catalog's version and source and closed by an
`END VENDORED` HTML comment, each spelled exactly as `/dev-copilot:wow-revendor-standards` writes it; then
the addon's own section. The markers are described here rather than shown, because this text travels
inside them: a literal marker in the vendored copy would give the file a second end marker for the next
re-vendor to cut at.

```markdown
[the BEGIN VENDORED comment, stamped quirks catalog v<X.Y.Z>]
… this section, whole …
[the END VENDORED comment]

## <Addon>-specific quirks

… the addon's own quirks: one no second repo has met, its per-event costs, its own probe tables …
```

- The block is **copied whole and replaced wholesale** by `/dev-copilot:wow-revendor-standards`, stamped with
  the standard version it came from, under the same discipline as `libs/LibKa0s/` (anti-pattern #45): never
  a subset, **never edited inside the markers**. A local edit inside them is reverted by the next revendor,
  and the behavior it fixed comes back with no cause in the addon's history; a correction belongs in the
  addon's own section, where the next harvest finds it.
- The addon's own section **MUST NOT** restate a behavior the block carries. When a harvest promotes an
  entry, the revendor prunes the addon's copy: the upstream entry is the deeper write-up, and two live
  copies of one finding is the shape that drifted three times into contradiction.
- An addon with no quirks of its own still carries the block, with an empty own section.

**Contested behaviors are not rules.** Where two repos recorded opposite behavior and nobody has probed
the difference, the entry goes in §6 with both sides and the probe that would settle it.

Behaviors this standard already states elsewhere are not repeated here: the unknown-event raise
(events-frames-taint-§1), `Settings.OpenToCategory`'s numeric ID and collapsed parent (options-ui-§2),
the protected category switch in combat (options-ui-§2, anti-pattern #88), a secret through `tostring` and
`..` (events-frames-taint-§8), lockdown at `PLAYER_REGEN_DISABLED` (events-frames-taint-§2), the spec
readers' move to `C_SpecializationInfo` (compat, `LibKa0s-Compat-1.0`) and `SendChatMessage`'s move to
`C_ChatInfo` (compat).

### 2. Secret values

**A secret boolean cannot be tested at all.** `if`, `not`, `==` and `and`/`or` on a secret boolean raise
("attempt to compare … (a secret boolean value)"); the value is unusable in Lua, not merely unprintable.
`DurationObject`'s `HasExpired`, `HasStarted`, `IsActive` and `IsZero` come back secret in combat, and an
engine button's `IsShown` has answered a secret boolean out of combat. *Measured:* 12.0.7 (probe table);
12.1 (`IsShown`). *Cost:* a raise on every refresh tick of the path that tests it. *Do:* check
`issecretvalue` before any test; route a secret boolean to a C-side consumer
(`C_CurveUtil.EvaluateColorValueFromBoolean`, `SetAlphaFromBoolean`), or treat it as the cautious answer
(a secret lockdown reads as locked, a secret restriction as active, a secret claim as no claim). Two repos
disagree on whether to gate before the C-side call; that disagreement is recorded in `LibKa0s`
`docs/api/Compat` and is not ruled here. *Source:* KickCD `docs/midnight-quirks.md`, "Secret booleans are
unusable"; seven repos (harvest 2026-11-06, Q6).

**A secret cannot be a table key.** Indexing or assigning with a secret key raises "attempted to perform
indexed assignment on a table that cannot be indexed with secret keys". `UnitGUID` on a follower-dungeon
pet (`party3pet`) answers a secret string. *Cost:* a raise on every refresh tick for a roster keyed by
GUID. *Do:* guard a key with `IsSafeKey` (`LibKa0s-Compat-1.0`) or `issecretvalue` before keying; a
secret GUID is never a handle. *Source:* MultiMeters `docs/midnight-quirks.md`, the follower-dungeon pet
GUID; seven repos (Q7).

**A secret never reaches SavedVariables, and one that does is written as `nil`.** A value captured as
secret stays secret after combat ends, and the client writes a secret to SavedVariables as `nil` — or,
where it was a key, loses the entry. *Measured:* a reload probe, 2026-10-25. *Cost:* silent data loss on
the next reload. *Do:* store a plain value or nothing; never store a captured secret to read later.
*Source:* DpsRace `docs/known-limitations.md`, the reload probe; three repos (Q21).

**A frame handed a secret has secret geometry, and so does everything anchored to it.** After
`StatusBar:SetValue(secret)` (or `SetAlphaFromBoolean`, or anchoring to an aura engine container) the
frame `HasSecretValues`: its width, points and frame level read secret, out of combat too, and the
taint runs down the anchor chain to every frame anchored to it; a tooltip showing hidden information has
secret geometry. A secret size's `type` is `"number"`, so a type check lets it through, and
`BackdropTemplate`'s own arithmetic on a secret size raises. *Cost:* a raise inside Blizzard code, or a
layout computed from a secret. *Do:* compute layout from configuration and never read geometry back from a
frame that was handed a value; keep a record of the alpha you set rather than calling `GetAlpha()`; read a
frame level under a restricted anchor through a secret-safe guard (frame-layering). *Source:* AuraMaster
`docs/midnight-quirks.md`, the aura engine container entries (measured and dated); six repos and
`LibKa0s` `docs/api/Widgets` (Q8).

**A restricted spell's cooldown: branch on `isActive`, paint with the duration object.** In a restricted
state `C_Spell.GetSpellCooldown`'s timings are secret while `isEnabled` and `isActive` stay plain
(documented NeverSecret). `GetSpellCooldownDuration` answers a **zeroed** object, not `nil`, when there is
no cooldown, and a fresh object per call. *Cost:* raw `SetCooldown` with a secret start or duration raises;
a nil check passes the zeroed object. *Do:* decide from `isActive`; paint with
`Cooldown:SetCooldownFromDurationObject`, which accepts the object from tainted code. *Source:* KickCD
`docs/midnight-quirks.md`, the cooldown probe table; four repos (Q9).

**`notInterruptible` is secret, and the interruptibility events make it plain.** The cast info's
`notInterruptible` is secret; `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` deliver it plain.
`CastingBarFrameTemplate`'s built-in `OnUpdate` compares `GetTime()` with a secret `maxValue` and raises
when the bar shows another unit. *Do:* split the gate — the color path takes the secret C-side, the logic
path takes the event's plain value; do not inherit `CastingBarFrameTemplate` for a unit other than the
player. *Source:* KickCD `docs/midnight-quirks.md`, "split the gate in two"; two repos (Q13).

**`InChatMessagingLockdown` can answer a secret.** *Do:* read it through a guard and treat a secret as
locked. *Source:* DropWatcher and QuickComms `core/Compat.lua` (byte-identical), DpsRace; three repos (Q27).

### 3. Events

**A valid event can register without complaint and never fire.** `GUILDBANKFRAME_OPENED` registers and
never fires (*Measured:* 12.0.7); `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts;
`UNIT_HEALTH` and `UNIT_NAME_UPDATE` never fire for compound tokens such as `party1target`;
`GET_ITEM_INFO_RECEIVED` does not fire for an item already cached. This is the inverse of the
unknown-event raise (events-frames-taint-§1) and it is silent: nothing errors. *Cost:* a feature that
never runs, with nothing in the log. *Do:* confirm a new event fires in game before building on it, and
prefer an edge with a second source (a frame's `OnShow`, a gated timer) where the event is known to be
silent. *Source:* BankLedger `docs/midnight-quirks.md`, `GUILDBANKFRAME_OPENED`; four repos (Q20).

**Client state can lag its own event, or change with no event at all.** `IsMounted()` has flipped by the
time `PLAYER_MOUNT_DISPLAY_CHANGED` arrives while `C_PlayerInfo.GetGlidingInfo`'s `canGlide` sometimes has
not; after `INSPECT_READY` some slots still answer an item id with no link; switching bank tabs fires no
event, and the live warband tab has taken over a second to catch up; chat lockdown clears with no event.
*Cost:* a read at the edge answers the old state, and the display stays wrong until the next unrelated
event. *Do:* answer at the edge **and once more after a short settle** (a fraction of a second, a bounded
retry), never a poll. *Source:* MultiMeters `docs/midnight-quirks.md`, "some client state lags its own
event"; six repos (Q19).

**An empowered cast fires `UNIT_SPELLCAST_EMPOWER_*`, not the channel events.** `UnitChannelInfo`
reports it, but `UNIT_SPELLCAST_CHANNEL_START` / `_STOP` do not fire for it, and its release fires
`UNIT_SPELLCAST_SUCCEEDED` with the same cast GUID. *Do:* register the `EMPOWER_*` events wherever channels
are tracked. *Source:* KickCD `docs/midnight-quirks.md`, empowered casts; three repos (Q12).

**`ADDON_RESTRICTION_STATE_CHANGED` fires *before* enforcement.** The `Activating` state arrives before the
restriction begins, and access is still permitted during that dispatch; a dungeon restriction type has
gone active on entry and not cleared. Read the restriction type by its `Enum.AddOnRestrictionType` member
name — a member can be missing on some builds. *Measured:* 12.1.0, 2026-09-18. *Do:* treat `Activating`
as the last moment to read, not as the start of the restriction. The payload's second argument is
contested (§6). *Source:* AuraMaster `docs/midnight-quirks.md`, the restriction types; six repos (Q10).

### 4. Combat and secure frames

**Blizzard's aura buttons are forbidden to addon code, and `IsForbidden()` can say otherwise.** In
combat every call on a Blizzard aura button's objects raises "Attempt to access forbidden object from code
tainted by an AddOn"; in an instance (seen in Mythic+) the same buttons answer `IsForbidden()` `false` and
still refuse every read, `GetChildren` included. *Do:* never read Blizzard aura buttons; where a frame
must be inspected, `pcall` the read and treat a failure as forbidden. *Source:* PartyFrameEnhanced
`docs/midnight-quirks.md`, forbidden aura buttons; three repos (Q14).

**Escape runs a protected `Hide()` in combat.** A secure or protected frame listed in `UISpecialFrames` is
hidden by `CloseSpecialWindows`, which is a protected action in combat. *Do:* list a non-secure proxy in
`UISpecialFrames` and hide the protected frame from it out of combat, or keep protected frames out of the
list. *Source:* WhatGroup `docs/midnight-quirks.md`, the escape proxy; two repos (Q24).

### 5. Item, tooltip, enum and realm data

**Item data is nil until cached, and the load event has holes.** `GetItemInfo` answers nothing for an
uncached item; `GET_ITEM_INFO_RECEIVED` does not fire on an addon's first scan for an item the client
already holds; an uncached item's tooltip is not empty but a legible `RETRIEVING_ITEM_INFO` line; a failed
load drops its wait and nothing asks again. *Cost:* a blank or wrong row that never repairs. *Do:* load
through `LibKa0s-Item-1.0`'s cache-then-callback path (library-stack-§7), treat `RETRIEVING_ITEM_INFO` as
not-yet-loaded, and re-ask after a failed load. *Source:* ConsumableMaster `docs/midnight-quirks.md`, the
first-scan hole; seven repos (Q15).

**`C_TooltipInfo` returns raw templates.** Tooltip lines can carry the unexpanded plural grammar
`|4singular:plural;` (*Measured:* 12.1.5, "for the next 3 |4hour:hrs; 49 min") and a no-break space that
Lua's `%s` does not match. *Cost:* a parser that knew only the expanded words read no duration and called a
tradeable drop expired. *Do:* expand `|4…;` before matching, and match the no-break space explicitly.
*Source:* DropWatcher `docs/midnight-quirks.md`, the trade window; two repos (Q16).

**Tooltip line text can be secret** under an addon restriction, including through `TooltipDataProcessor`.
*Do:* guard each line before matching. *Source:* DropWatcher `docs/midnight-quirks.md`; two repos (Q17).

**Blizzard renumbers enums; resolve a member by name, never by number.** One build's
`Enum.TooltipDataLineType` and bank-tab values are not the next build's, and a member can be absent on a
build. *Cost:* a numeric guess for a member the build does not expose landed on an unrelated bank
container. *Do:* read `Enum.X.Member`, and handle its absence; localization-§4 already forbids the string
spelling. *Source:* DropWatcher `docs/midnight-quirks.md`, the research's enum values; five repos (Q18).

**`GetNormalizedRealmName` is nil early in login.** *Cost:* a stored `Name-` key with no realm. *Do:* never
build a `Name-Realm` key before the realm is known; defer, or fall back to `GetRealmName` with its spaces
and hyphens removed. *Source:* DropWatcher `docs/midnight-quirks.md`, realm names; four repos (Q25).

**A template-less `FontString` with no font raises on `SetText`.** "Font not set" from a `FontString`
created without a template or `SetFontObject` takes the addon down at load; a mock that does not enforce it
passes every test. *Do:* give every bare `FontString` a font object before its first `SetText`; the kit's
mock enforces it. *Source:* MultiMeters `tests/mock_frame.lua`, the font-not-set guard; three repos and
`LibKa0s` (Q22).

### 6. Open probes — contested behaviors (not rules)

Each needs an in-game probe, recorded with the build, before any section of this standard changes.

- **WoW Forever behaviors (none recorded yet).** The catalog was written on Retail. The Forever client (build 70790) has a missing-API surface, `SetDesaturation` among it, that LibKa0s tracks in LibKa0s#44, and no quirk entry yet meets this section's two-repo bar for it. Record a Forever behavior in the repo that meets it, with the build, and promote it by a harvest like any other.

- **`string.format` on a secret.** events-frames-taint-§8 says it raises, with three repos; two say it
  works, one with a mid-combat observation. The likely difference is the specifier (`%s` against `%d` and
  `%.1f`) or that the result is itself a secret string. Probe each specifier, in combat, on a damage-meter
  value and a `UnitHealth` value. Until then §8's rule stands.
- **`ADDON_RESTRICTION_STATE_CHANGED`'s second argument.** One repo documents an
  `Enum.AddOnRestrictionState` value; three (one measured) record a boolean as well. Handle both shapes.
  The 2026-09-22 harvest called this settled, and it is not.
- **`SetAllPoints(parent)` on a secure button at load.** One repo records "Cannot anchor protected frames
  to regions" and uses the implicit-parent form; another anchors its secure rows with `SetAllPoints(row)`
  at birth and treats it as working, with its in-game smoke check still owed.
<!-- END VENDORED -->

## KickCD-specific quirks

## 12.0 secret-value protection

WoW 12.0 introduced "secret values" on certain protected API returns — notably `C_Spell.GetSpellCooldown` for interrupt spells and parts of `UnitCastingInfo` / `UnitChannelInfo`. From tainted (addon) execution, **comparison and arithmetic on a secret value raise a Lua error**, and there is no addon-side strip:

| Pattern | Result |
|---|---|
| `tonumber(secret)` | Still secret. |
| `tostring(secret)` | Still secret. |
| `secret + 0` (in addon scope) | Errors — `+` is the operation that fires. |
| `securecallfunction(fn, secret)` where `fn` is addon-defined | Still tainted; arithmetic inside still errors. |
| `:format("%.1f", secret)` | Errors. |
| Blizzard C methods (`Cooldown:SetCooldown`, `Texture:SetTexture`) with secret args | **Also rejects** — the error message says "Secret values are only allowed during untainted execution for this argument." |

**The rule:** never compare, do arithmetic on, format, or pass to most Blizzard C methods a value that might be secret. Either use a sibling field that is plain (e.g. `info.isActive` and `info.isEnabled` come back plain), or gate the operation with `NS.Compat.IsSecret(v)` and degrade gracefully (skip the op, hide the visual, etc.). `Compat.IsSecret` is `LibKa0s-Compat-1.0`'s guard over the client's `issecretvalue`, and it is the one place the addon asks: no feature module reads the global itself (see [compat-layer.md](compat-layer.md)). The unit and cast readers (`Compat.UnitCastingInfo`, `Compat.UnitChannelInfo` and their siblings) pass secrets through untouched, exactly as the inline `_G.Unit*` reads they replaced did.

**Preferred workaround for cooldown timing:** use `C_Spell.GetSpellCooldownDuration(spellID)` (wrapped as `NS.Compat.GetSpellCooldownDuration`). It returns a `CooldownDuration` object that can be:

- Passed straight to `Cooldown:SetCooldownFromDurationObject(obj)` to drive the swipe.
- Passed to `FontString:SetFormattedText("%.1f", obj:GetRemainingDuration())` to render countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `obj:EvaluateRemainingDuration(curve)` and the result passed to `Frame:SetAlphaFromBoolean(true, alpha, 0)` / `Texture:SetVertexColor(color:GetRGB())`.

**Critical caveat:** `obj:GetRemainingDuration()` returns a *secret-tainted* number in combat (plain out of combat). It is **only** safe as a direct argument to a Blizzard C method. Binding it to a Lua local for a comparison, format, tostring, or arithmetic op will error with "attempt to compare local '...' (a secret number value)" the moment combat opens. The same caveat applies to whatever `EvaluateRemainingDuration` returns — pass it through to a C method, never inspect it.

KickCD uses this API throughout: `modules/Cooldowns.lua` emits the duration object opaquely, `modules/IconGrid_Render.lua` evaluates it against step-shaped alpha/tint curves to derive GCD-vs-real-CD visuals C-side. Reach for `C_Spell.GetSpellCooldown`'s raw `startTime`/`duration` only when you genuinely need them — and even then, gate with `issecretvalue` first because in combat *every* watched spell's timings come back secret.

Why curves instead of a `UNIT_SPELLCAST_SUCCEEDED` cast tracker for GCD filtering? Blizzard suppresses that event for protected interrupts (Mind Freeze, Pummel, Kick, Spear Hand Strike, …) — the event simply does not fire when the player casts one of those spells in tainted scope. So a cast-event tracker can never flip the primary icon's state. Curve evaluation runs entirely C-side and works for protected and unprotected spells alike.

The Cell addon's PR #457 is the canonical reference for the `issecretvalue()`-based pattern; see comments in `core/Compat.lua` and `modules/IconGrid_Render.lua` for the rationale recorded in-tree.

**Do not** propose `securecallfunction` / `tonumber` / `+0` "detox" workarounds — they were tried and don't work. Comments document this so we don't re-try.

## `CooldownDuration` objects are minted fresh on every call

`C_Spell.GetSpellCooldownDuration(spellID)` returns a **brand-new object every single call**. Two calls describing the identical, unchanged cooldown are never `==`. There is no interning, and identity carries no meaning.

This bites any "did the state change?" diff that includes the handle. Until KickCD#9, `modules/Cooldowns.lua`'s `StateChanged` compared `prev.cdObject ~= next_.cdObject`, so a spell parked on an unchanged 60s cooldown compared unequal on *every* poll — with `SPELL_UPDATE_COOLDOWN` firing ~10x/sec in combat that was ~10 redundant `Ka0s_KickCD_SpellState` emits per second per spell on cooldown. Reported from the field on an Elemental Shaman with Capacitor Totem on cooldown.

**History: why the re-emit used to be load-bearing.** `Icon:Apply` evaluated the alpha, tint and GCD-suppression curves at emit time and nothing else re-ran them (the shared 0.1s ticker refreshed only the countdown *text*), and the GCD → real-cooldown transition changes the handle without changing `isActive`. So comparing handle presence alone would have left the icon on the expired GCD handle, and the fix of the day was to keep the identity compare for the emit and gate only the debug line on `MaterialChange`.

**Now: emit = state changed, ticker = time passed (KickCD#9).** The way out was not a better comparison but to stop needing one:

1. The ticker (`modules/IconGrid_Ticker.lua`) owns time. Every 0.1s it re-fetches each registered icon's handle — branch 1 after reading the plain `isActive`, branch 2 through `Cooldowns.RechargeHandle` — and re-runs the body alpha / tint curves, the GCD-suppression alpha and the countdown text. An icon on either cooldown branch is registered whatever `showCooldownText` says, so the curves keep running with the text off.
2. `StateChanged` is `MaterialChange` (`ready` / `isActive` / handle **presence** / plain charges) plus the conservative emit for a secret charge count, so the badge stays live. Handle identity is in neither gate.
3. The swipe is armed only by `Icon:Apply`'s state work: a fresh handle per tick risks restarting the animation, and the C side keeps animating the handle it was given. The GCD → real-cooldown handoff, which no plain field reveals, is caught when the GCD swipe *finishes*: the Cooldown frame's `OnCooldownDone` sets a flag and the next tick, still seeing `isActive`, re-arms once from a fresh handle. The same path rolls a recharge onto the next charge. Until that point the swipe shows the GCD while the curves and text already show the real cooldown — at most one GCD of lag, on the swipe only.
4. A recast inside `SPELL_UPDATE_COOLDOWN`'s lag (the ticker saw `isActive` false and hid the swipe; Cooldowns then sees active → active and emits nothing) is caught by the ticker too: an ended icon stays registered until `Icon:Apply` takes it to idle, and re-arms itself if `isActive` comes back.

Downstream consumers of the emit must still be idempotent — `Icon:StartGlow` carries an explicit gate because re-issuing `Stop`+`Start` replayed LibCustomGlow's animIn and produced a visible ButtonGlow pop at ~10 Hz.

`Icon:Apply` does its state work (branch choice, swipe arm, first paint, ticker registration, glow) only when `plainStateMoved` says a plain field moved; otherwise it refreshes the charges badge alone. Two rules keep that safe: a config-driven re-apply must pass `force=true` (it hands back the SAME state table, so the gate would otherwise skip exactly the work the config change needed), and the glow's other input — the unit's cast state — is covered independently by `IconGrid:OnUnitCastEvent`, which re-runs `UpdateGlow` across every icon on each `UNIT_SPELLCAST_*` transition. Charges are deliberately outside the gate: they can be secret, a secret cannot be compared, and `SetFormattedText` renders one fine, so the badge is simply always refreshed.

### Probe results: in combat, EVERY DurationObject getter is secret

Measured on a live 12.0.7 client with a one-off capability probe (since removed — it had served its purpose), Capacitor Totem on cooldown:

| Method | Out of combat | In combat |
|---|---|---|
| `HasSecretValues()` | plain `false` | **plain `true`** |
| `GetRemainingDuration()` | plain | secret |
| `GetTotalDuration()` | plain | secret |
| `GetStartTime()` / `GetEndTime()` | plain | secret |
| `GetElapsedDuration()` / `GetRemainingPercent()` | plain | secret |
| `HasExpired()` / `HasStarted()` / `IsActive()` / `IsZero()` | plain | **secret** |
| `GetModRate()` | plain | secret |
| `Copy()` / `Assign()` | ok (userdata) | ok (userdata) |

Two consequences worth internalizing:

**Secret BOOLEANS are unusable, not merely unprintable.** `HasExpired`, `HasStarted`, `IsActive` and `IsZero` all come back secret-tainted in combat. You cannot branch on one — `if hasExpired then` would reveal the entire value, so it errors in tainted scope exactly like `if notInterruptible then` does. Only `HasSecretValues()` stays plain, which makes it the one method you can safely gate on.

**There is therefore NO Lua-side way to detect "this spell's cooldown changed" in combat.** Every candidate comparator on the object is secret. The old `prev.cdObject ~= next_.cdObject` check in `Cooldowns:StateChanged` was the *only available signal*: it over-fired (a fresh object per call means it fired on every poll) but never under-fired, and nothing on the object could replace it.

KickCD#9 took the way out this table pointed to: stop needing the comparison. The 0.1s ticker re-fetches the handle and re-renders the time-varying visuals, so the emit is only needed when the *plain* state (`ready` / `isActive` / charge count / handle presence) changes. `C_Spell.GetSpellCooldown(...).isActive` stays plain in combat and is the ticker's "has it ended?" signal, and the Cooldown frame's `OnCooldownDone` is its "the swipe I armed is stale" signal.

**`GetSpellCooldownDuration` returns a ZEROED object, not nil, when nothing is on cooldown.** The out-of-combat probe above sampled a spell whose cooldown had lapsed and got a live object reporting `GetTotalDuration()==0`, `IsActive()==false`, `HasExpired()==true`. Do not treat a non-nil handle as "this spell is on cooldown" — gate on the plain `isActive` from `C_Spell.GetSpellCooldown` instead, which is what `Cooldowns:PollSpell` already does.

This table is a snapshot of 12.0.7 behavior, not a contract. After any patch that touches cooldown APIs, re-measure before trusting it: call each getter inside a `pcall` and classify the result with `issecretvalue` — never branch on a value before you know it is plain.

### The wider `DurationObject` surface (largely unused here)

The object is far richer than this addon currently uses, and several methods are worth reaching for before hand-rolling equivalents:

| Method | Why it matters |
|---|---|
| `HasSecretValues()` | First-class test for secret-tainted contents — a native replacement for the hand-rolled `issecretvalue` gating in `core/Compat.lua` / `modules/IconGrid_Render.lua`. |
| `Assign(other)` / `Copy()` | Update a held object **in place** without replacing the reference — removes the identity churn at source (though it does not remove the per-poll fetch). |
| `GetStartTime()` / `GetEndTime()` / `GetTotalDuration()` | The comparison primitives whose absence is the only reason the identity check exists. |
| `HasExpired()` / `IsActive()` / `HasStarted()` / `IsZero()` | State predicates computed natively. |
| `FormatRemainingDuration(formatter)` | Native formatting, no secret round-trip through Lua. |

**Unverified caveat:** the wiki describes these as methods that "perform calculations natively on potentially secret data and return secrets back to Lua", so assume every getter above can be secret-tainted in combat until proven otherwise in-game — the pages do not say. `HasSecretValues()` is the safe gate for finding out. Reference: [ScriptObject DurationObject](https://warcraft.wiki.gg/wiki/ScriptObject_DurationObject).

## Cast interruptibility (`UnitCastingInfo` / `UnitChannelInfo`)

`notInterruptible` (position 8 of `UnitCastingInfo`, position 7 of `UnitChannelInfo`) is **secret-tainted in 12.0** for any cast the player has a protected interrupt against. It is the same trap as cooldown timings: `not nint`, `nint == true`, `if nint then`, `tostring(nint)` all error in combat.

**Do not** try to make a Lua-side boolean decision out of it. `NS.Compat.IsCastingInterruptible` was the original attempt and silently broke the visibility / glow gates because the secret-taint branch had to conservatively return `true`, which meant uninterruptible casts were treated as interruptible.

**The 12.0-correct pattern**: split the gate in two —

1. `NS.State.IsHostileUnitCasting(unit)` — a plain truthy check on the API's `name` return (safe, even when secret) plus a `UnitCanAttack` filter. Drives `Show` / `Hide`.
2. `NS.State.ApplyInterruptibleAlpha(frame, unit, alpha)` — pulls the raw `notInterruptible` and pipes it straight into `frame:SetAlphaFromBoolean(notInterruptible, 0, alpha)`. `SetAlphaFromBoolean` is the **one** C-side method that accepts the secret-tainted bool form without erroring.

So uninterruptible casts run the full UI lifecycle (Shown frame, started glow animation, drawn cast bar) but at `alpha = 0` — the visual filter is C-side and the Lua decision is never made. `UNIT_SPELLCAST_INTERRUPTIBLE` / `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` events drive a re-application of the alpha mask mid-cast. See `modules/IconGrid_Visibility.lua` (`ApplyInterruptibilityMask`), `modules/IconGrid_Render.lua` (`Icon:UpdateGlow`), and `modules/Castbar.lua` (`ApplyVisibilityMask`).

### Plain-after-flip invariant

The Castbar caches the cast's `notInterruptible` flag on its `current` record so `ApplyState` (the secret-bool curve evaluator that runs every state change) doesn't have to re-query `UnitCastingInfo`. At cast start the cached value is whatever `UnitCastingInfo.notInterruptible` returned — plain on non-protected casts, secret-tainted in combat for casts the player has a protected interrupt against.

When `UNIT_SPELLCAST_INTERRUPTIBLE` / `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` fires mid-cast, `Castbar:OnInterruptibilityChanged` writes `current.notInterruptible = (evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")` — a plain Lua boolean derived from the event name, which replaces the (possibly secret) original. After that flip the field is plain; `ApplyState`'s `C_CurveUtil.EvaluateColorValueFromBoolean` accepts both plain and secret forms identically, so the curve still works either way.

The invariant matters only as a reminder: don't optimize the curve into a Lua-side `if not nint then ... else ... end` that "happens to work because the value's plain post-flip" — the very next `Start(rec)` puts a fresh secret-tainted bool back into the field before the next event arrives.

## Empowered casts (`UNIT_SPELLCAST_EMPOWER_*`)

An Evoker's empowered cast (Fire Breath, Eternity Surge, …) is reported by `UnitChannelInfo`, not `UnitCastingInfo`, but it does **not** fire `UNIT_SPELLCAST_CHANNEL_START` / `_STOP`: it fires `UNIT_SPELLCAST_EMPOWER_START` / `_UPDATE` / `_STOP`. A listener registered only for the cast and channel families misses an empower begun after targeting (the bar stays blank and the `*_casting` visibility and glow lag until the next unrelated refresh) and never clears on its stop. Both cast filters therefore carry the three EMPOWER events: in `Castbar` they route to `OnChannelStart` / `OnCastDelayed` / `OnCastStop`, in `IconGrid` to `OnUnitCastEvent`. Each name goes through `NS.SafeRegisterUnitEvent`, so a client that ever retires one loses only that route. Evokers empower in PvP; whether any NPC does is unconfirmed, so the in-client check is CAST-14 in [smoke-tests.md](smoke-tests.md), a duel.

## Frame mixin pattern

**Never `setmetatable(frame, t)` on a Blizzard widget.** Frame methods (`ClearAllPoints`, `Show`, `SetAlpha`, …) live on the C-side metatable, and replacing it nils them.

Use `Mixin(frame, t)` (Blizzard's global) to copy fields onto the frame without touching the metatable. See `modules/IconGrid_Render.lua` `CreateIconWidget` → `return Mixin(btn, Icon)`.

## Other Midnight fingerprints

These don't have load-bearing rules but are worth knowing about:

- **`UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts.** Mind Freeze, Pummel, Kick, Spear Hand Strike, etc. — the event simply does not fire when the player casts one of those spells in tainted scope. KickCD's GCD-vs-real-CD filter has to be C-side curves because of this; a Lua-side cast tracker can't see those events.
- **`C_Spell.GetSpellInfo(spellID).castTime`** is fully secret in combat against an interruptable target — *every* field of the returned table comes back tainted. Don't read it as a fallback timeline; use `UnitCastingDuration` instead.
- **`AceConfigDialog:AddToBlizOptions`** returns `(frame, categoryID)` on modern clients. `Settings.OpenToCategory` wants the **numeric ID**; passing the frame produces a range error. KickCD uses `Settings.RegisterCanvasLayoutSubcategory` directly and stores the resulting `categoryID` per panel.
- **Blizzard's CategoryList only auto-expands the subcategory tree when a *child* is selected.** Selecting a parent category in `Settings.OpenToCategory` leaves its subcategory tree collapsed in the left nav, hiding the sibling tabs the user is trying to navigate to. `NS:OpenSettings` opens the parent (`Settings.OpenToCategory(main:GetID())`) and then forces the tree open via `SettingsPanel:GetCategoryList():GetCategoryEntry(main):SetExpanded(true)`. The expand call is wrapped in `pcall` because `SettingsPanel.CategoryList` / `GetCategoryEntry` / `SetExpanded` are Blizzard private API that could shift between patches; if any link in the chain goes missing we silently fall through to "parent opened, tree collapsed", which is one click away from where the user wanted to be. The retry (capped at 3, 0.5 s apart) covers the early-`/kcd config` race against the `PLAYER_LOGIN`-deferred panel registration.
