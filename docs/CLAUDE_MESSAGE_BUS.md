# The closed message bus

All inter-module communication uses `AceEvent`-style messages with a fixed name set:

| Message | Sender | Payload |
|---|---|---|
| `KickCD_SPELL_STATE` | Cooldowns | `{ spellID, ready, isActive, cdObject, chargeCdObject, charges }` |
| `KickCD_CONFIG_CHANGED` | settings/* + slash | `{ section = "general"\|"icons"\|"spells"\|"castbar" }` |
| `KickCD_PROFILE_CHANGED` | Database (AceDB callback) | `{ newProfileKey }` |
| `KickCD_GRID_LAYOUT` | IconGrid (after every Layout pass) | `{ gridFrame, primaryIcon, width, height }` |

**Don't invent new messages without a reason.** The closed list is documented in this file and in module headers; new entries should appear here too. `cdObject` is the secret-aware `CooldownDuration` handle from `C_Spell.GetSpellCooldownDuration`, non-nil whenever the legacy `isActive` flag is true (real CD or just-GCD; the IconGrid disambiguates downstream). `chargeCdObject` is a separate handle on the same API, set when the spell has charges and at least one is missing while `isActive=false` — i.e. a recharge timer is ticking but the spell is still castable. The IconGrid renders the recharge swipe + countdown text from `chargeCdObject` without applying the cooldown alpha/tint (the spell IS castable; `state.ready` stays true).

**Spell-disappeared sentinel.** When `Cooldowns:Refresh` finds a previously-watched `spellID` no longer available (pet dismissed, talent untrained, encounter mechanic suppresses the spell), it emits one final `KickCD_SPELL_STATE` with `ready = false, isActive = false, cdObject = nil, chargeCdObject = nil, charges = nil` and drops the id from its `watched` table. The IconGrid's `OnSpellState` no-cdObject branch already renders ready visuals correctly for this payload; the next `Rebuild` (fired by `SPELLS_CHANGED` / `TRAIT_CONFIG_UPDATED`, both of which fire on the same triggers) trims the now-orphaned icon out of `ordered[]`. Without the sentinel the icon would linger with the last-known state until a `/reload`.

Both handles can be:
- Passed to `Cooldown:SetCooldownFromDurationObject` for the swipe.
- Passed to `FontString:SetFormattedText("%.1f", cdObj:GetRemainingDuration())` for countdown text.
- Evaluated against a `C_CurveUtil.CreateCurve` / `CreateColorCurve` via `cdObj:EvaluateRemainingDuration(curve)` to produce alpha / color values that ride through `Frame:SetAlphaFromBoolean(true, alpha, 0)` and `Texture:SetVertexColor(color:GetRGB())`.

The legacy `start` / `duration` raw timings are NOT in the payload precisely because they go secret in combat for every watched spell and break arithmetic in tainted scope. **`cdObject:GetRemainingDuration()` is also secret in combat** — only ever pass it directly to a C method as an argument; never hold it in a Lua local for compare / format / tostring. The GCD-vs-real-CD visual filter lives entirely in `modules/IconGrid.lua` as a step-shaped alpha/tint curve evaluated C-side: `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts (Mind Freeze, Pummel, Kick, …) so a cast-event tracker would never flip the primary icon's state — the curve sidesteps that by reading remaining only inside Blizzard's curve evaluator.

A separate `gcdSuppressCurve` (also built in `IconGrid.BuildCurves`) drives the cooldown swipe + countdown text alpha when `db.profile.icons.suppressGCDSwipe` is on. Same shape as the alpha/tint curves — 0 below `GCD_UPPER`, 1 above — fed through `Frame:SetAlphaFromBoolean(true, value, 0)` on the cooldown frame and the cooldownText FontString. Default-on; users can flip it off in Settings → Icons → Visual states. The cooldown-text OnUpdate also re-polls the plain `Compat.GetSpellCooldown` `isActive` boolean as an early-exit so SPELL_UPDATE_COOLDOWN's lag doesn't leave the text stuck at "0.0" after the cooldown ends — only valid for full-cooldown drives, not the chargeCdObject path.

**`KickCD_GRID_LAYOUT` payload.** `IconGrid:Layout` fires `{ gridFrame, primaryIcon, width, height }` after every layout pass — `gridFrame` is the parent frame (`KickCDIconGrid`), `primaryIcon` is the first laid-out icon button or `nil` when the active spell list is empty, and `width` / `height` are the post-layout bounding box of the grid. Subscribers (today: `Castbar:OnGridLayout`) prefer the payload over reaching back through `KickCD.IconGrid:GetGridFrame` / `:GetPrimaryIcon`. The public accessors remain available for callers that haven't yet adopted the payload form.

