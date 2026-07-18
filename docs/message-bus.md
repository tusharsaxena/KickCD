# Closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set. New entries belong here, in module headers, and in [data-flow.md](data-flow.md). **Don't invent new messages without a reason** — the closed list is what keeps cross-module coupling auditable.

## The five messages

| Message | Sender | Listeners | Payload |
|---|---|---|---|
| `Ka0s_KickCD_SPELL_STATE` | `Cooldowns:Rebuild` / `Refresh` | `IconGrid` | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` |
| `Ka0s_KickCD_CONFIG_CHANGED` | `settings/Panel.lua Helpers.Set` (every schema-row write); `core/KickCD.lua` (lock/unlock); `settings/Panel_Render.lua Helpers.ResetIconPosition`; `settings/Panel_Render.lua Helpers.RenderUnitPanel` (focus link toggle / copy-styling button → `units`); `settings/Spells.lua` (debounced editor commits); `modules/IconGrid.lua OnDragStop` (anchor save → `general`); `modules/Castbar.lua OnDragStop` (anchor save → `castbar`) | `IconGrid`, `Cooldowns`, `Castbar` | `{ section = "general"\|"icons"\|"castbar"\|"spells"\|"units" }` |
| `Ka0s_KickCD_PROFILE_CHANGED` | `Database:OnProfileChanged` (AceDB callback for `OnProfileChanged` / `Copied` / `Reset`) | `IconGrid`, `Cooldowns`, `Castbar`, `settings/Spells.lua` | `{ newProfileKey }` |
| `Ka0s_KickCD_GRID_LAYOUT` | `IconGrid:Layout` (every pass, including the empty-list case — one instance per unit, `IconGrid`'s target and focus instance managers each fire their own) | `Castbar` | `{ unit, gridFrame, primaryIcon, width, height }` |
| `Ka0s_KickCD_COMBAT_STATE` | `core/State.lua` bootstrap frame (the only `PLAYER_REGEN_*` registration in the addon) | `IconGrid`, `Castbar` | `{ inCombat }` |

## `Ka0s_KickCD_SPELL_STATE` payload

`cdObject` is the secret-aware `CooldownDuration` handle from `C_Spell.GetSpellCooldownDuration`, non-nil whenever the legacy `isActive` flag is true (real CD or just-GCD; the IconGrid disambiguates downstream). `chargeCdObject` is a separate handle on the same API, set when the spell has charges and at least one is missing while `isActive=false` — i.e. a recharge timer is ticking but the spell is still castable. The IconGrid renders the recharge swipe + countdown text from `chargeCdObject` without applying the cooldown alpha/tint (the spell IS castable; `state.ready` stays true).

Both handles can be:

- Passed to `Cooldown:SetCooldownFromDurationObject` for the swipe.
- Passed to `FontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())` for countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `cdObj:EvaluateRemainingDuration(curve)` to produce alpha / color values that ride through `Frame:SetAlphaFromBoolean(true, alpha, 0)` and `Texture:SetVertexColor(color:GetRGB())`.

The legacy `start` / `duration` raw timings are NOT in the payload precisely because they go secret in combat for every watched spell and break arithmetic in tainted scope. **`cdObject:GetRemainingDuration()` is also secret in combat** — only ever pass it directly to a C method as an argument; never hold it in a Lua local for compare / format / tostring. The full secret-value rules live in [midnight-quirks.md](midnight-quirks.md).

The GCD-vs-real-CD visual filter lives entirely in `modules/IconGrid.lua` as a step-shaped alpha/tint curve evaluated C-side: `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts (Mind Freeze, Pummel, Kick, …) so a cast-event tracker would never flip the primary icon's state — the curve sidesteps that by reading remaining only inside Blizzard's curve evaluator.

A separate `gcdSuppressCurve` (also built in `IconGrid.BuildCurves`) drives the cooldown swipe + countdown text alpha when the instance's `icons.suppressGCDSwipe` (`units.<unit>.icons.suppressGCDSwipe`, resolved via `NS.Units.Icons(unit)`) is on. Same shape as the alpha/tint curves — 0 below `GCD_UPPER`, 1 above — fed through `Frame:SetAlphaFromBoolean(true, value, 0)` on the cooldown frame and the cooldownText FontString. Default-on; users can flip it off in Settings → Icons → Visual states. The cooldown-text OnUpdate also re-polls the plain `Compat.GetSpellCooldown` `isActive` boolean as an early-exit so SPELL_UPDATE_COOLDOWN's lag doesn't leave the text stuck at "0.0" after the cooldown ends — only valid for full-cooldown drives, not the chargeCdObject path.

### Spell-disappeared sentinel

When `Cooldowns:Refresh` finds a previously-watched `spellID` no longer available (pet dismissed, talent untrained, encounter mechanic suppresses the spell), it emits one final `Ka0s_KickCD_SPELL_STATE` with `ready = false, isActive = false, cdObject = nil, chargeCdObject = nil, charges = nil` and drops the id from its `watched` table. The IconGrid's `OnSpellState` no-cdObject branch already renders ready visuals correctly for this payload; the next `Rebuild` (fired by `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED`, both of which fire on the same triggers) trims the now-orphaned icon out of `ordered[]`. Without the sentinel the icon would linger with the last-known state until a `/reload`.

## `Ka0s_KickCD_CONFIG_CHANGED` payload

Section-keyed for cheap dispatch. `Cooldowns` only acts on `"general"` (master enable) and `"spells"` (rebuild watched list); `IconGrid` acts on `"general"` / `"icons"` / `"spells"` / `"units"`; `Castbar` acts on `"general"` / `"castbar"` / `"units"`. There is no `"debug"` section — the debug enabled-flag is the session-only `NS.State.debug` (never in SavedVariables), toggled via `DebugLog:SetEnabled` / `/kcd debug on|off|toggle`, and it does **not** broadcast on the bus at all, so flipping it never cascades into a `Cooldowns:Rebuild` / `IconGrid` relayout.

The `"units"` section (target/focus dual tracking) covers per-unit `enabled` toggles, `label.show`/`label.text`, and the focus `link` flag / "Copy styling from Target" action. `IconGrid`/`Castbar` react by calling their `ReconcileUnits()` (enabling/disabling the affected unit's instance), and `UnitLabel` re-applies the identity label; it is a section value on the existing payload shape, not a new message.

## `Ka0s_KickCD_GRID_LAYOUT` payload

`IconGrid:Layout` fires `{ unit, gridFrame, primaryIcon, width, height }` after every layout pass, once per enabled unit instance (target and/or focus each have their own `IconGrid:Layout` call site inside their instance). `unit` is `"target"` or `"focus"`; `gridFrame` is that unit's parent frame (`KickCDIconGrid` for target, `KickCDIconGridFocus` for focus); `primaryIcon` is the first laid-out icon button or `nil` when the active spell list is empty; `width` / `height` are the post-layout bounding box of that unit's grid.

Subscribers (today: `Castbar:OnGridLayout`) filter on `payload.unit` and resolve their own same-unit instance (`instances[payload.unit]`) before acting — a target-instance cast bar ignores a focus-instance `GRID_LAYOUT` and vice versa — then prefer the payload over reaching back through `NS:GetModule("IconGrid", true):GetGridFrame` / `:GetPrimaryIcon`. The Castbar uses this to re-anchor under `castbar.anchorMode = "PRIMARY"` (the primary icon button reference may have moved when the grid rebuilds against a new spec) and to re-run `Castbar:Reskin` (and `RenderCast` when a cast is active) when `castbar.autoSize` is on (the grid frame's footprint may have changed). Public accessors `IconGrid:GetGridFrame` / `:GetPrimaryIcon` remain available via `NS:GetModule("IconGrid", true)` for callers that haven't yet adopted the payload form (default to the target instance when no `unit` arg is given).

**Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): `GRID_LAYOUT` gaining the `unit` field is an additive payload change within the closed five-message bus, not a new message — the alternative (a `Ka0s_KickCD_GRID_LAYOUT_FOCUS` sibling message) would have doubled the bus surface for no dispatch benefit, since every subscriber already needs to branch on which instance the payload is for.

## `Ka0s_KickCD_COMBAT_STATE` payload

`core/State.lua`'s bootstrap frame is the only file in the addon that registers `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED`. It writes `NS.State.inCombat`, then fires `Ka0s_KickCD_COMBAT_STATE` so `IconGrid` and `Castbar` see an explicit ordered transition signal — the flag write is guaranteed to land before any subscriber's handler runs, instead of relying on TOC-load-order to ensure the bootstrap frame's `RegisterEvent` happened before each module's. The same message also fires on `PLAYER_LOGIN` (after the initial `InCombatLockdown()` seed).

Payload `{ inCombat }` carries the freshly-written flag value, but subscribers typically read `NS.State.inCombat` directly (the same source `shouldBeVisible` / `isVisible` use elsewhere) rather than trusting the payload, so the two reads stay in lockstep.

## Adding or removing a message

Adding a message means updating:

1. The source emitter (only one is allowed per message — the table above is sender-authoritative).
2. Every consumer that reacts to it.
3. The table above (sender, listeners, payload).
4. The relevant module header comment.
5. The `CLAUDE.md` "Hard rules" pointer if the new message has cross-module rules attached.
