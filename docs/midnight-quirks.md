# Midnight quirks — secret values, frame mixin, and other 12.0 traps

Catalog of WoW Midnight (Interface 12.0.x) behaviors that bite the addon. **Read this before touching cooldown, cast, or visibility code.** When something breaks at patch time, this is where to look first.

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

**The rule:** never compare, do arithmetic on, format, or pass to most Blizzard C methods a value that might be secret. Either use a sibling field that is plain (e.g. `info.isActive` and `info.isEnabled` come back plain), or gate the operation with `NS.Compat.IsSecret(v)` and degrade gracefully (skip the op, hide the visual, etc.). `Compat.IsSecret` is `LibKa0s-Compat-1.0`'s guard over the client's `issecretvalue`, and it is the one place the addon asks: no feature module reads the global itself (see [compat-layer.md](compat-layer.md)).

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
