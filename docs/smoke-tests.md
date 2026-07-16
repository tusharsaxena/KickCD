# Smoke tests

Manual end-to-end smoke tests for **Ka0s KickCD**. Run before claiming a non-trivial change works, before tagging a release, and after refreshing libs or bumping `## Interface:`. There is no automated harness — every check below is performed in-game with the live client.

Companion docs:

- Slash + debug coverage matrix (what each command produces): [testing.md](testing.md).
- 12.0 secret-value rules referenced throughout: [midnight-quirks.md](midnight-quirks.md).

## Conventions

- **`/reload`** is the abbreviation used below for `/console reloadui`.
- **BugSack / BugGrabber** (or the stock Lua error frame) is the primary regression signal — a clean run is "no errors thrown at any point".
- **Chat banner** — every line the addon prints starts with a cyan `[KCD]`. A double `[KCD][KCD]` banner or any line missing the banner is a bug; the only sanctioned colored sub-tokens are the yellow command names + white descriptions in the help printers and the red `schema error:` token in `settings/Panel.lua`.
- **"Hostile caster"** below means a target dummy / world mob that channels or casts an interruptible spell on demand. Stockades casters, Stormwind training dummies tagged with a friend's spell, and Plaguefall trash are common picks.
- **"In combat"** smoke checks rely on `NS.State.inCombat`, which flips on `PLAYER_REGEN_DISABLED` / `_ENABLED`. Auto-attack on a dummy is enough.
- **"Pass"** lines describe what success looks like; if a step says "should X" and X does not happen, the smoke test failed.

## Suite

| # | Area | Surfaces | Scenario |
|---|------|----------|----------|
| 1 | Cold start | TOC load, `OnInitialize`, schema validator | [Fresh install + first login](#1-fresh-install--first-login) |
| 2 | Reload | Persistence, OnEnable | [`/reload` integrity](#2-reload-integrity) |
| 3 | Master enable | `db.profile.enabled` | [Master enable toggle](#3-master-enable-toggle) |
| 4 | Visibility | All four visibility modes | [Visibility mode matrix](#4-visibility-mode-matrix) |
| 5 | Lock + drag | Shared lock, anchor save | [Lock / unlock / drag](#5-lock--unlock--drag) |
| 6 | Icon grid | Anchor × grow × dimensions, truncation | [Icon grid layout](#6-icon-grid-layout) |
| 7 | Cast bar | Free / anchored, auto-size, orientation, per-state | [Cast bar](#7-cast-bar) |
| 8 | Cooldowns + glow | Interrupt fire, GCD suppression, ready glow | [Cooldown + glow](#8-cooldown--glow) |
| 9 | Spec / talent / pet | Watched-list rebuild | [Spec, talent, pet rebuilds](#9-spec-talent-pet-rebuilds) |
| 10 | Spells | Spells panel + slash parity | [Spell-list editor](#10-spell-list-editor) |
| 11 | Settings panel | Schema, valueGate, panel ↔ slash sync | [Settings panel parity](#11-settings-panel-parity) |
| 12 | Resets | Per-panel, resetall, resetposition, per-spec | [Resets](#12-resets) |
| 13 | Profiles | AceDB profile lifecycle | [Profiles](#13-profiles) |
| 14 | Combat gating | Combat-protected operations | [Combat gating](#14-combat-gating) |
| 15 | Debug | `/kcd debug …` subcommands | [Debug commands](#15-debug-commands) |
| 16 | 12.0 secret values | Cooldown / cast secret-tainted paths | [Secret-value safety](#16-secret-value-safety-120) |
| 17 | Schema validator | PLAYER_LOGIN validator output | [Schema validator boot output](#17-schema-validator-boot-output) |
| 18 | LSM dropdowns | Statusbar / Border / Font dropdowns | [LSM dropdown rendering](#18-lsm-dropdown-rendering) |
| 19 | Debug traces | §8 key functional-flow lines in the debug console | [Debug traces](#19-debug-traces) |
| 20 | Focus tracking | Enable focus, independent gating, link/copy styling | [Focus tracking](#20-focus-tracking) |
| 21 | Legacy migration | `FoldLegacyUnits` on a pre-`units` profile | [Legacy migration](#21-legacy-migration) |
| 22 | Text label | `modules/UnitLabel.lua`, Text Label settings panel | [Text label](#22-text-label) |
| 23 | Label style migration | `Database:BackfillLabelStyle` on a pre-`label.style` profile | [Label style migration](#23-label-style-migration) |

---

### 1. Fresh install + first login

**Setup.** Quit WoW. Delete `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` (and the `.lua.bak` if present). Confirm the addon is enabled in the character select AddOns list as **Ka0s KickCD**.

**Steps.**
- Log in to a fresh character.
- Run `/kcd`.

**Pass.**
- Login completes with no Lua errors.
- The icon grid renders with the current spec's default spells (filtered to spells the player can actually cast).
- `/kcd` prints the help index — every row carries the cyan `[KCD]` banner, command names are yellow, descriptions are white, no `schema error:` line appears.
- Settings → AddOns shows a **Ka0s KickCD** parent category with the six subcategories **General / Icons / Cast bar / Text Label / Spells / Profiles**.
- `KickCDDB` is now present on disk after `/reload` with `profileKeys`, `profiles.Default`, and the seeded `spells[CLASS][SPEC]` block for the current spec.
- Switch to a different class+spec character (alt) and log in: their spec's spells are seeded on first profile creation without errors.

### 2. `/reload` integrity

**Setup.** From the cold-start state, run a few writes:

```
/kcd unlock
/kcd set units.target.icons.primarySize 50
/kcd set units.target.castbar.interruptible.barColor 0.2 0.8 0.2 1
```

Drag the icon grid to a new screen position. Lock it back: `/kcd lock`.

**Steps.**
- `/reload`.

**Pass.**
- No Lua errors during reload.
- Icon grid sits at the dragged position.
- Lock state is `locked = true` (`/kcd get locked` → `true`).
- `/kcd get units.target.icons.primarySize` → `50`.
- `/kcd get units.target.castbar.interruptible.barColor` → `0.2 0.8 0.2 1`.
- All six settings tabs still appear under **Ka0s KickCD**.

### 3. Master enable toggle

**Setup.** Pick a context where the icon grid would normally be visible (e.g. `visibility = always`).

**Steps.**
- `/kcd set enabled false`.
- `/kcd set enabled true`.

**Pass.**
- `false` hides both the icon grid and the cast bar regardless of visibility mode or current target.
- `true` immediately restores both per the active visibility rules.
- The General → "Enable KickCD" checkbox in the panel reflects the slash write live (open the panel before flipping; the box state changes when `/kcd set enabled …` is run).

### 4. Visibility mode matrix

A single visibility selector governs **both** the icon grid and the cast bar.

| `visibility` | Setup | Expected |
|---|---|---|
| `always` | No target, no combat | Both UI pieces visible. |
| `in_combat` | No target | Hidden out of combat. Auto-attack a dummy: both appear within one frame of `PLAYER_REGEN_DISABLED`. Drop combat: both hide on `_ENABLED`. |
| `target_casting` | Target a friendly NPC casting an emote spell, or no cast | Hidden until the target *starts* casting / channeling, then both appear; both hide on cast finish/cancel. |
| `target_casting_interruptible` (default) | Target a hostile mob mid-uninterruptible cast | Hidden. Switch to a hostile mob casting interruptibly: both appear. During an `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` flip mid-cast (some bosses), the cast bar's alpha fades to 0 — the frame stays parented but visually disappears (alpha curve, not `:Hide()`). |

**Pass for each row.**
- No Lua errors at any visibility flip.
- `/kcd debug interrupt` while a hostile is casting reports the secret-value status of `notInterruptible` and the gate's decision matching the row's expected outcome.

### 5. Lock / unlock / drag

**Setup.** `/kcd set units.target.castbar.anchorMode FREE` so the cast bar is independently draggable. Pick `visibility = always` so both pieces are visible without a casting target.

**Steps.**
- `/kcd unlock`.
- Click-drag the icon grid; release.
- Click-drag the cast bar; release.
- `/kcd lock`.
- Try to drag both again.
- `/reload`.

**Pass.**
- After `unlock`, both pieces are draggable.
- After `lock`, neither piece is draggable.
- After `/reload`, both retain their dragged positions.
- Switch `units.target.castbar.anchorMode` back to `PRIMARY`: the cast bar is no longer draggable (it's parented to the primary icon) even when unlocked, and it follows the icon grid when the grid is dragged.
- `/kcd toggle` flips the lock state; the General → "Lock frame" checkbox updates to match in real time when the panel is open.

### 6. Icon grid layout

**Setup.** Open Settings → Icons. Make sure at least 4 spells are enabled in the current spec so the secondary block is non-empty.

**Steps.**
- Walk through every value of `units.target.icons.anchor` (13 anchor tokens). For each, set `units.target.icons.secondaryGrow` to two distinct values applicable to that axis.
- Set `units.target.icons.secondaryRows` and `units.target.icons.secondaryCols` such that `rows * cols < (number of enabled spells) - 1`.

**Pass.**
- For each anchor / grow combination, the secondary block lays out from the primary icon's named anchor in the chosen direction without overlap.
- When `visibleCount > rows * cols`, a one-time chat warning prints with a `[KCD]` banner naming the (class, spec, capacity) tuple.
- Bumping `rows × cols` to fit the visible count, then dropping back below it on a *different* (class, spec, capacity) tuple, re-fires the warning for the new tuple but does not re-fire for the previous one in the same session.
- Setting `units.target.icons.primarySize` from 16 → 80 (within the slider range) live-updates without reloading.

### 7. Cast bar

#### 7a. Free anchor mode

**Setup.** `/kcd set units.target.castbar.anchorMode FREE`. `/kcd unlock`. Pick a hostile caster in `target_casting_interruptible` mode.

**Steps.**
- Drag the cast bar to a new position; lock; `/reload`.
- Target the hostile caster mid-cast.

**Pass.**
- Position persists across reload.
- Bar appears on cast start, mirrors duration via `UnitCastingDuration`, snaps off at cast end.
- Spell name and remaining time render; spark animates along the fill.

#### 7b. Anchored mode + auto-size

**Setup.** `/kcd set units.target.castbar.anchorMode PRIMARY`. `/kcd set units.target.castbar.autoSize true`. `/kcd set units.target.castbar.orientation HORIZONTAL`.

**Steps.**
- Disable a few spells with `/kcd spells disable <id>` and re-enable them with `add` so the icon grid's *visible* footprint changes.
- Resize via `/kcd set units.target.icons.secondaryCols 4`, then `2`.
- Toggle `/kcd set units.target.castbar.orientation VERTICAL`. Set `/kcd set units.target.castbar.growDirection UP`.

**Pass.**
- The bar's long axis tracks the grid's *visible* width (HORIZONTAL) or height (VERTICAL), not the configured `rows × cols` capacity. Removing a visible spell shortens the bar in place; adding one extends it.
- The orthogonal dimension stays at the configured `units.target.castbar.width` / `units.target.castbar.height`.
- Switching `orientation` resets `growDirection` to the canonical default for the new axis (`HORIZONTAL` → `RIGHT`, `VERTICAL` → `UP`); `/kcd set units.target.castbar.growDirection UP` while in HORIZONTAL is rejected and the error message names the gating sibling (`units.target.castbar.orientation`) and its current value (the `valueGate` mechanism).

#### 7c. Per-state appearance

**Setup.** `/kcd set units.target.castbar.interruptible.barColor 0.2 0.8 0.2 1`. `/kcd set units.target.castbar.uninterruptible.barColor 0.8 0.2 0.2 1`.

**Steps.**
- Target a hostile caster mid-interruptible cast.
- Find a hostile mid-uninterruptible cast (or a boss spell that flips to uninterruptible mid-cast).

**Pass.**
- Interruptible cast renders with the green bar, configured interruptible border style and font.
- Uninterruptible cast renders with red (or alpha-fades to 0 in `target_casting_interruptible` mode — both behaviors are correct, governed by the visibility mode).
- Mid-cast flip via `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` switches state without a Lua error and without the addon ever doing a Lua-side `if notInterruptible then …`.

### 8. Cooldown + glow

**Setup.** Pick a class/spec with at least one off-GCD interrupt and one on-GCD CC (e.g. Warrior Pummel + Intimidating Shout). `visibility = always`.

**Steps.**
- Cast Pummel into a friendly target dummy.
- During its cooldown, also cast a different spell with a GCD that's shorter than Pummel's CD.
- Set `units.target.icons.primaryGlowTrigger` and `units.target.icons.secondaryGlowTrigger` to two different trigger modes (e.g. primary = `target_casting_interruptible`, secondary = `target_casting`).

**Pass.**
- Pummel's icon desaturates immediately on cast, with a cooldown swipe and (if enabled) the `Icons → Annotations → Show cooldown text` countdown ticking down.
- The unrelated GCD does NOT visually trigger Pummel's swipe — the C-side curve gates GCD vs real CD without comparing the secret remaining time in Lua.
- Glow on the primary icon triggers only on hostile interruptible casts; glow on the secondary icons triggers on any hostile cast, per the per-trigger config. The two are independent.
- After Pummel comes off CD, `Cooldowns:Refresh` re-emits `Ka0s_KickCD_SPELL_STATE { ready = true }`, the icon re-saturates, and the cooldown swipe vanishes — no `0.0` stuck-text bug (regression check from 1.0.0).

### 9. Spec, talent, pet rebuilds

**Setup.** Pick a character with two specs and at least one talent choice node that materially differs (e.g. a node that replaces one interrupt-adjacent spell). For pet rebuild, use a Hunter.

**Steps.**
- Switch spec via the Talents UI or `/changespec`.
- In a spec with a choice-node interrupt swap, swap the choice node.
- On a Hunter: `/cast Call Pet 1`, then dismiss the pet.

**Pass.**
- Spec swap rebuilds the watched cooldown list against the new spec's seeded spells; the icon grid re-pools and re-lays out without errors. `Cooldowns:OnEnable` listens for `PLAYER_SPECIALIZATION_CHANGED`.
- Talent choice swap fires `TRAIT_CONFIG_UPDATED` / `SPELLS_CHANGED` and rebuilds the watched list immediately — no need to swap spec.
- Pet summon adds the pet's tracked interrupt to the visible grid; pet dismiss removes it. The dismissed pet's icon does not linger with stale state — `Cooldowns` emits a sentinel `SPELL_STATE { ready=false, isActive=false, cdObject=nil }` on poll-nil for the now-vanished spell.
- After dismiss, `/kcd debug spells` no longer lists the pet spell.

### 10. Spell-list editor

**Setup.** Note the player's current class+spec for the slash invocations below.

**Steps.**
- `/kcd spells list` — dump the current spec's watched spells.
- `/kcd spells add <SPELL_ID> interrupt` — using a spell ID present in the active spec's Cooldown Manager.
- `/kcd spells add <SPELL_ID> interrupt` — using an arbitrary spell ID that is NOT in the active spec's Cooldown Manager.
- `/kcd spells disable <SPELL_ID>`; `/kcd spells enable <SPELL_ID>`.
- `/kcd spells category <SPELL_ID> stun`.
- `/kcd spells remove <SPELL_ID>`.
- Open Settings → Spells. Edit a different spec via the class+spec dropdown.
- Trigger a CLI write while the panel is open: `/kcd spells add <SPELL_ID> interrupt CLASS SPEC`.
- `/kcd spells reset CLASS SPEC` for one spec; verify it rebuilds *only* that spec.
- `/kcd reset spells` — verify it wipes *every* spec.

**Pass.**
- The active-spec write paths validate against the Cooldown Manager spell-set — adding a spell that isn't tracked there prints an error and is rejected.
- Editing a *different* class+spec falls through to the lenient validation path and succeeds for any valid spell ID.
- After every mutating subcommand, the Spells panel rebuilds rows live (it listens for `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }`) — no need to close and reopen the panel.
- `/kcd spells reset CLASS SPEC` rebuilds one spec from `NS.DefaultSpells`; the other specs are untouched.
- `/kcd reset spells` calls `Database:ResetAllSpells` and wipes every spec.
- The Spells panel header **Defaults** button rebuilds *only* the currently-selected spec, matching `/kcd spells reset` (not `/kcd reset spells`).

### 11. Settings panel parity

**Setup.** Open Settings → General with the chat window visible.

**Steps.**
- Toggle the General → "Enable KickCD" checkbox; observe `/kcd get enabled` reports the new value.
- Run `/kcd set scale 1.25`; observe the General → "Master scale" slider snap to 1.25x while the panel is open.
- Run `/kcd set units.target.castbar.growDirection LEFT` while `units.target.castbar.orientation = VERTICAL`. The error message should list the valid options for VERTICAL plus a `(depends on units.target.castbar.orientation = VERTICAL)` line.
- Run `/kcd list`. Spot-check that every General / Icons / Castbar row from the panel is present with its current value.
- For a number-type row, run `/kcd set <path> <out-of-range>` (e.g. `/kcd set scale 99`) — the value should clamp to the row's `max` (e.g. `2.00x`).
- For a color-type row, run `/kcd set units.target.castbar.interruptible.barColor 0.5 0.5 0.5` (3 floats, no alpha); the alpha should default to 1 and the row should accept the write.
- Drag a color slider in the panel's `ColorPicker`; chat / frame should not stutter or error on rapid drag (the throttle is 50ms via `Util.Throttle` in `settings/Panel.lua`).

**Pass.**
- Every panel write fires `Ka0s_KickCD_CONFIG_CHANGED { section = … }`; subscribed modules redraw.
- Every slash write does the same and any open panel widget refreshes.
- `valueGate` errors name both the option list and the gating sibling.
- Number clamps respect `min` / `max` / `step`. Color writes accept 3 or 4 floats and clamp each to `[0, 1]`.

### 12. Resets

| Command | Expected |
|---|---|
| `/kcd reset general` | All General rows return to their `default` values; spell list and other panels untouched. |
| `/kcd reset icons` | All Icons rows return to defaults; icon grid re-lays out. |
| `/kcd reset castbar` | All Cast bar rows return to defaults; bar re-skins. |
| `/kcd reset spells` | Every spec's spell list is rebuilt from `NS.DefaultSpells` (NOT just the active spec). |
| `/kcd resetall` | Every schema-driven panel + every spec's spell list reset. Profiles untouched. No CLI confirmation prompt. |
| `/kcd resetposition` | Icon grid snaps to its default screen position; everything else untouched. |
| Settings → General → **Reset all settings** button | StaticPopup confirm → same effect as `/kcd resetall`. |
| Settings → General → **Reset position** button | Same effect as `/kcd resetposition`. |
| Per-panel **Defaults** button (General / Icons / Cast bar) | That panel only; mirrors `/kcd reset <panel>`. |
| Spells panel header **Defaults** button | Currently-selected spec only; mirrors `/kcd spells reset CLASS SPEC`. |

**Pass.**
- No Lua errors at any reset path.
- Open panels reflect reset values without manual refresh.
- After `/kcd resetall`, `/kcd get enabled` returns `true` and `/kcd get visibility` returns `target_casting_interruptible` (the schema defaults from `settings/General.lua`).

### 13. Profiles

**Setup.** Settings → Ka0s KickCD → Profiles.

**Steps.**
- Create a new profile `SmokeTest`. Switch to it.
- Make a change (`/kcd set units.target.icons.primarySize 60`).
- Switch back to `Default`.
- Switch to per-character: choose **Choose** → character-specific.
- Use **Copy from** to copy `SmokeTest` into the active profile.
- Use **Delete** to remove `SmokeTest`.
- `/reload` after each step.

**Pass.**
- Switching profiles fires `Ka0s_KickCD_PROFILE_CHANGED`; both UI pieces re-anchor and re-skin to the new profile's settings.
- Per-character / per-class / per-realm scope correctly scopes the active profile (verify via `KickCDDB.profileKeys` after `/reload`).
- `Database:MigrateProfile` runs on profile change (`db.global.schemaVersion` should already read `CURRENT_DB_VERSION = 2` for an account that's run this build before; re-running should not error or re-fold anything). The schema version is account-wide in `db.global.schemaVersion`, not per-profile.
- Spell-list edits on one profile do not bleed into another.

### 14. Combat gating

**Setup.** Pull a target dummy so `NS.State.inCombat = true`.

**Steps.**
- Run `/kcd config` mid-combat.
- Run `/kcd set units.target.icons.primarySize 50` mid-combat.
- Drop combat. Run `/kcd config` again.

**Pass.**
- Mid-combat `/kcd config` prints a one-line "cannot open during combat" message with the `[KCD]` banner and does NOT open the settings panel (Blizzard's category-switch is protected and would taint the panel).
- Mid-combat `/kcd set …` for non-protected operations succeeds and applies live (icon size, color, etc.).
- Out of combat `/kcd config` opens the settings panel landing on the Ka0s KickCD parent page with the subcategory tree expanded in the left nav (the parent page renders the logo + slash command list).
- Running `/kcd config` immediately after login (before `PLAYER_LOGIN`-deferred `RegisterPanel`) eventually succeeds — `OpenSettings` schedules deferred retries via `C_Timer.After(0.5, …)`, capped at 3 attempts.

### 15. Debug commands

**Setup.** Hostile caster targeted in combat is the most informative state.

| Command | Expected output |
|---|---|
| `/kcd debug spells` | Per-spell line: `ready=…  active=…  cdObj=yes/no  chargeCdObj=yes/no  charges=…`. Charges may render as `<secret>` for charged spells in combat. **No remaining-time field** — `:GetRemainingDuration()` is secret in combat and printing it would error. |
| `/kcd debug castbar` | Current target cast state plus configured + live per-state colors and `notInterruptible`'s `type()` and `issecretvalue()` flag. The dump uses `type()` / `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error. |
| `/kcd debug interrupt` | Every `UnitCastingInfo` / `UnitChannelInfo` field with its type + secret flag, plus `NS.State.IsHostileUnitCasting("target")` and the visibility-mode / glow-trigger gate decisions. Secret-tainted fields render as `<secret>`. |
| `/kcd debug on` / `off` / `toggle` | Sets / clears the session-only `NS.State.debug` flag (never written to SavedVariables — resets to off on every `/reload`). Continuous debug output streams to the on-screen console window, not chat. There is no longer a `db.profile.debugLog` field or a General → "Debug" checkbox. |
| `/kcd debug window` | Toggles the on-screen debug console window (`modules/DebugLog.lua`); logging keeps running whether the window is open or closed. |
| `/kcd debug` | Toggles the console window and prints the debug subcommand help index. |

**Pass.**
- Every subcommand runs mid-combat without Lua errors.
- `interrupt` shows `<secret>` for `notInterruptible` (and any other secret-tainted field) when targeting a hostile caster mid-cast for a protected interrupt — never a Lua-coerced value.
- `/kcd debug on` starts streaming `Ka0s_KickCD_*` traffic to the on-screen console window (not chat); `off` cleanly stops it. After a `/reload` the flag is back off — `NS.State.debug` is session-only and never persisted.
- `/kcd debug window` opens / closes the console window without touching the logging flag.

### 16. Secret-value safety (12.0)

This suite catches regressions in 12.0's protected-interrupt taint propagation. See [midnight-quirks.md](midnight-quirks.md) for the underlying rules; the test below exercises every known taint vector.

**Setup.** A class with a tracked interrupt (Warrior Pummel, Rogue Kick, Mage Counterspell, etc.) targeted onto a hostile caster mid-interruptible cast, in combat.

**Steps.**
- Cast the interrupt successfully; cast it on cooldown (it should fail). Repeat 5+ times across a long cast / channel.
- Switch targets between hostile interruptible-caster, hostile uninterruptible-caster, friendly NPC, and untargeted, while `visibility = target_casting_interruptible`.
- Run `/kcd debug interrupt` while a hostile is mid-cast.
- Trigger a glow flip mid-cast on a boss spell that flips `notInterruptible` (some Plaguefall and Zskera trash do).

**Pass.**
- Zero Lua errors at any point. The most common regression signature is a `cannot perform arithmetic on a secret value` or `attempt to format a secret value` error at the moment the protected interrupt fires while in combat.
- Cooldown swipe + cooldown text on the interrupt icon work correctly (text is rendered via `:SetFormattedText` on a duration object — never `tostring`).
- Cast bar's interruptible / uninterruptible appearance switches without a Lua-side `if notInterruptible then …` ever running. `/kcd debug interrupt` reports `<secret>` for `notInterruptible`.
- The two-step gate (`NS.State.IsHostileUnitCasting` for show + `NS.State.ApplyInterruptibleAlpha` for filter) is invoked; the interruptible-only visibility mode hides the cast bar via *alpha curve to 0*, not via `:Hide()`.

### 17. Schema validator boot output

**Setup.** Restart WoW (full quit, not `/reload`) to force a cold `PLAYER_LOGIN`.

**Steps.**
- Watch chat after login.

**Pass.**
- No `|cffff0000KickCD schema error|r:` lines print. `Helpers.ValidateSchema` (in `settings/Panel.lua`) runs at panel-register time and emits red error lines for any malformed row — a healthy build is silent here. Any error means a recent schema change shipped a malformed row.

### 18. LSM dropdown rendering

The vendored `AceGUI-3.0-SharedMediaWidgets` (r65) provides `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` dropdowns. `core/LSMPatch.lua` is a defensive in-tree fixup that hides the 42×42 Border `displayButton` preview tile and re-anchors the dropdown bar; it runs at `PLAYER_LOGIN`.

**Steps.**
- Open Settings → Cast bar.
- Click the **Bar texture** (statusbar) dropdown, the **Border style** dropdown, and the **Font** dropdown.

**Pass.**
- Each dropdown opens, lists installed media, and applies a chosen entry live to the cast bar.
- The Border dropdown does NOT show a 42×42 black preview tile to the left of the dropdown bar (regression: that tile was the upstream lib's `displayButton`; `LSMPatch.lua` hides it).
- Switching to Settings → Icons and changing **Cooldown text font** updates the icon countdown immediately on the live grid.

### 19. Debug traces

`docs/agent-context.md` §8 requires one gated, secret-safe line per key functional-flow transition, routed through `NS.Debug` to the on-screen console (never chat).

**Setup.** `/kcd debug on`, then `/kcd debug window` to keep the console visible while driving each transition below.

**Steps + pass.**
- **Combat.** Enter combat (auto-attack a dummy), then leave combat. One `[Combat] entered` line appears when combat starts, one `[Combat] left` line when it ends — nothing at `PLAYER_LOGIN`, nothing per-tick during sustained combat.
- **Profile.** Settings → Profiles → switch to a different profile (or create one). One `[Profile] switched to '<name>'` line appears naming the new profile key.
- **Cast / IconGrid.** Set Visibility to `target_casting_interruptible`, then have a hostile target start and stop an interruptible cast. One `[Cast] target cast gate: interruptible on/off` line appears when the gate flips, and one `[IconGrid] visibility …: shown/hidden` line appears when the grid's shown state actually changes — no line on refreshes where neither moved.
- **Open.** `/kcd config` (or the minimap/options button) while out of combat. One `[Open] settings panel` line appears per successful open.
- **Spells.** In the Spells editor: toggle a row's enabled checkbox (`[Spells] enable/disable <spellID>`), remove a row (`[Spells] remove <spellID>`), and click "Reset to defaults" for a spec (`[Spells] reset <CLASS>/<SPEC>: N spells`).
- **Set.** Change any setting on any panel (e.g. Icons → primary size). One debounced `[Set] …` line appears after the value settles — no re-echo, no per-keystroke spam (§10, Task 3).
- **No spam.** Across all of the above, stay in combat for 30+ seconds with no target-cast activity: no additional `[Combat]`/`[Cast]`/`[IconGrid]` lines appear beyond the transition(s) already logged.

### 20. Focus tracking

Focus tracking adds a second, independent (icon grid + cast bar) instance for the player's focus unit, rendering the same player cooldowns. Focus is off by default and defaults to linking Target's appearance.

#### 20a. Enable focus + independent target/focus gating

**Setup.** `visibility = target_casting_interruptible`. Set a focus target (`/focus` while targeting a hostile caster) distinct from the current hard target.

**Steps.**
- `/kcd set units.focus.enabled true`.
- Target a hostile mid-interruptible cast (different mob than the focus) while the focus mob is NOT casting.
- Have the focus mob start an interruptible cast while the hard target is NOT casting.
- Have both cast simultaneously.
- `/kcd set units.focus.enabled false`.

**Pass.**
- Enabling focus immediately builds a second icon grid (`KickCDIconGridFocus`) and cast bar (`KickCDCastbarFocus`) — no `/reload` needed — showing the SAME tracked spells as target's grid (player-centric spell list).
- Each grid/bar's visibility is gated independently against its OWN unit's cast state: target casting alone shows only the target pair; focus casting alone shows only the focus pair; both casting shows both. Neither unit's gate is affected by the other's cast state.
- `/kcd set units.focus.enabled false` immediately tears down the focus instance (grid + bar disappear); target's instance is unaffected.
- Zero Lua errors at any step.

#### 20b. Link / unlink / copy styling

**Setup.** `/kcd set units.focus.enabled true`. Open Settings → Icons.

**Steps.**
- Select **Focus** in the Icons panel's Unit dropdown. Confirm the panel shows only "Use same styling as Target" (checked) + "Copy styling from Target" — no appearance rows, plus a "Linked to Target — uncheck to customize." note.
- Change Target's `units.target.icons.primarySize` (switch the dropdown to Target first). Switch back to Focus — the linked Focus grid should visually match Target's new size live (no manual sync needed).
- Uncheck "Use same styling as Target". The appearance schema rows appear, seeded with target's last-copied values (or defaults if never copied).
- Change a Focus-only appearance value (e.g. `units.focus.icons.primarySize`) — confirm Target's grid is unaffected.
- Re-check "Use same styling as Target" — Focus reverts to mirroring Target live; the customization from the previous step is no longer visually active (though not necessarily wiped from `units.focus.icons` — the schema row is simply not read while linked).
- Uncheck again, then click **"Copy styling from Target"** — Focus's `icons`/`castbar` tables are deep-copied from Target's current values and `link` flips to `false` (button also unlinks if still linked).

**Pass.**
- While linked, `NS.Units.Icons("focus")` / `.Castbar("focus")` resolve to `units.target.icons` / `.castbar` — verified by the live visual match in the steps above.
- Position (`units.focus.anchors.icons`/`castbar`) and the Focus identity label (`units.focus.label.text`, if shown) stay independent of Target's position/label at every step, linked or not — dragging the Focus grid never moves Target's.
- "Copy styling from Target" is a one-time deep copy (not a live link) — a subsequent Target-only appearance change does NOT propagate to the now-unlinked Focus.
- No Lua errors at any toggle.

#### 20c. Mid-cast enable + master-enable revive

**Setup.** Set a focus target that is a hostile caster. `visibility = target_casting_interruptible`, `units.focus.enabled = false`.

**Steps.**
- While the focus unit IS mid-cast, run `/kcd set units.focus.enabled true`.
- `/kcd set units.focus.enabled false`, then re-target/re-cast, then `/kcd set units.focus.enabled true` again.
- With both target and focus enabled and visible, `/kcd set enabled false` (master enable), then `/kcd set enabled true`.

**Pass.**
- Enabling focus mid-cast shows the focus cast bar immediately, mid-cast, at the correct progress — the newly-built instance re-evaluates current cast state on enable rather than waiting for the next `UNIT_SPELLCAST_*` event.
- Re-enabling focus after a fresh cast start behaves identically (no stale state from the previous enable/disable cycle).
- `/kcd set enabled false` hides BOTH units' grids and bars regardless of per-unit `enabled`; `/kcd set enabled true` immediately revives every unit whose `units.<unit>.enabled` is still `true`, re-evaluating current cast/cooldown state for each without requiring a `/reload`.

### 21. Legacy migration

**Setup.** On a test account/character, quit WoW. Edit `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` (or a backed-up copy from before this feature) so the active profile has top-level `icons`, `castbar`, and `anchors` tables with a few customised values (e.g. a non-default `icons.primarySize`, a moved `anchors.icons`) and NO `units` table. Set `db.global.schemaVersion` to `1` or remove it entirely (either should trigger the fold).

**Steps.**
- Log in.
- `/kcd get units.target.icons.primarySize` — compare to the customised value from the edited file.
- `/kcd get units.target.anchors.icons` (or visually check the grid's position) — compare to the customised anchor.
- `/reload`, then inspect `KickCDDB` on disk: confirm `profiles.<key>.icons` / `.castbar` / `.anchors` no longer exist at the top level and `profiles.<key>.units.target.{icons,castbar,anchors}` hold the customised values. `db.global.schemaVersion` should read `2`.

**Pass.**
- No Lua errors during the migration login.
- The icon grid renders at the SAME position and with the SAME customised appearance as before the migration — visually, nothing changes for the user.
- `Database:FoldLegacyUnits` output is idempotent: a second `/reload` doesn't move anything or error (the top-level tables are already gone, so the shape check short-circuits).
- Focus (`units.focus`) is present with its own fresh defaults (`enabled = false`, `link = true`) — the migration only touches target, since legacy accounts only ever had one unit.

### 22. Text label

Each unit (target/focus) can show one configurable identity label, rendered by `modules/UnitLabel.lua` and configured on its own **Text Label** settings tab (`settings/Label.lua`, panel/section `label`, after Cast bar).

**Setup.** `/kcd set units.target.enabled true` and `/kcd set units.focus.enabled true`. Open Settings → Text Label.

**Steps.**
- Select **Target** in the Text Label panel's unit dropdown. **Show label** is checked by default; confirm a label reading "Target" already appears just above the target cast bar (the default `attach = "castbar"`, `point = "BOTTOM"`, `relPoint = "TOP"`, `offsetY = 12`). Toggle **Show label** off/on; confirm the label disappears/reappears.
- Edit **Label text** to something custom (e.g. "MainTank"); confirm it updates live, no `/reload` needed.
- Switch **Attach to** from `castbar` to `icons`; confirm the label re-anchors to the icon grid frame instead, still tracking live as the grid moves/resizes (drag the grid; the label follows via the next `Ka0s_KickCD_GRID_LAYOUT`).
- Walk the anchor/attach point pair (`Label anchor point` / `Attach point`) through a few combinations (e.g. `TOP`/`BOTTOM`, `LEFT`/`RIGHT`) and vary **X offset (in px)** / **Y offset (in px)**; confirm the label's position updates live and matches the chosen points + offsets.
- Set **Horizontal justify** / **Vertical justify** through their values; confirm text alignment changes visibly (most apparent with multi-word text).
- Set **Rotation (degrees)** to a nonzero value (e.g. 45, -90); confirm the label visibly rotates and returns to upright at 0.
- Change **Font** / **Font size** / **Font flags**; confirm the label's rendered font updates live (LSM dropdown, same widget family as Cast bar → Font).
- Change **Label color** (color picker in the Font group) to a distinct color (e.g. bright green or red); confirm the label's text color updates live. Switch **Attach to** between `castbar`/`icons`; confirm the color persists across the re-anchor.
- Switch to **Focus** in the unit dropdown with `units.focus.link = true` (the default): confirm the Text Label page now shows only the "Linked to Target — uncheck to customize." note — no Show label / Label text / Placement / Orientation / Font rows are rendered while linked (matching the Icons and Cast bar pages). Focus's label still renders live (with Target's style, including color) if `units.focus.label.show` is `true` in the saved profile — it's just not editable from this page while linked.
- Uncheck "Use same styling as Target" for Focus: confirm the page now shows the full Show label / Label text / Placement / Orientation / Font body again. Set Focus's label text to something distinct from Target's (e.g. "Kick this") and change one style value (e.g. rotation or color); confirm Target's label is unaffected and both units can show different text with different styles. Re-check the link; confirm the body collapses back to the note and Focus's label style (including color) reverts to mirroring Target's live (text stays as "Kick this" — text is per-unit data, not link-resolved).
- With both labels shown, toggle `units.focus.enabled` off; confirm the Focus label disappears immediately (independent of Target's, which stays visible) and reappears when Focus is re-enabled.
- Toggle **Show label** off for Target while Target's icon grid/cast bar remain visible; confirm only the label disappears, not the grid/bar.
- **General-visibility follow (reversal of the old "independent visibility" behavior):** set `visibility = target_casting` (or `target_casting_interruptible`) via General settings, with **Show label** on for Target. With the target NOT casting (grid + cast bar hidden per General visibility), confirm the Target label is ALSO hidden — it no longer floats on screen while its attach frame is hidden. Start a target cast; confirm the grid/cast bar AND the label all appear together. Stop casting; confirm all three hide together. Repeat with `attach = "icons"` to confirm the label follows the icon grid's visibility too, not just the cast bar's.

**Pass.**
- Every field change is live — no `/reload` required for any of the above.
- Target and Focus labels are visually and positionally independent (dragging the grid/cast bar of one never moves the other's label), while sharing identical default style values (including color) out of the box.
- A label is visible only when BOTH `label.show` is on AND its attach frame is currently shown per General visibility — the label never floats on screen while the grid/cast bar it's anchored to is hidden.
- No Lua errors at any step, including rapid attach-mode switching, rapid slider drags on offset/rotation, and visibility-mode changes.

### 23. Label style migration

**Setup.** On a test account/character, quit WoW. Edit `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` (or a backed-up copy predating this feature) so the active profile's `units.target.label` and `units.focus.label` exist as `{ show, text }` only — **no** `style` sub-table. Leave `db.global.schemaVersion` as-is (this migration is shape-driven, not version-gated, so it runs regardless).

**Steps.**
- Log in.
- `/kcd get units.target.label.style.font` (or open Settings → Text Label and confirm the Font/placement/orientation rows show sane default values rather than erroring or rendering blank).
- `/reload`, then inspect `KickCDDB` on disk: confirm `profiles.<key>.units.target.label.style` and `profiles.<key>.units.focus.label.style` are now both present and match `LABELSTYLE_DEFAULT` in `core/Database.lua`.

**Pass.**
- No Lua errors during the migration login or on the Text Label panel.
- If a label was already shown pre-migration (`label.show = true` in the edited file), it renders identically before and after — **no visual change**, since the backfilled `style` values equal the shipped defaults the label was implicitly using anyway.
- `label.show` / `label.text` values from the edited file are preserved exactly (the migration only fills in the missing `style` sub-table).
- A second `/reload` doesn't error or re-write anything (`Database:BackfillLabelStyle` is idempotent — it only acts when `style == nil`).

---

## When to run which subset

- **Pre-commit (hot path edits):** 1, 2, 8, 16. Anything touching `Cooldowns.lua`, `IconGrid.lua` / `IconGrid_Layout.lua` / `IconGrid_Render.lua`, `Castbar.lua`, or the secret-value gates needs the secret-value pass.
- **Settings / schema edits:** 11, 17 plus the panel under change. Any new schema row also exercises 12 (its panel's reset path).
- **Spell-list / Database edits:** 9, 10, 13. DB shape edits (`DEFAULT_PROFILE`, migrations) also need 21 (and 23 if the edit touches `units.<unit>.label`).
- **Target/focus dual-tracking edits:** 20 (plus 6/7 per-unit if touching layout/cast-bar internals shared by both instance managers).
- **Text label edits:** 22 (plus 23 if the change touches `label.style`'s shape or defaults).
- **Pre-release / TOC bump:** the entire suite. The 23 surfaces above are designed to span every system the addon owns; running them in order takes ~30–40 minutes and gives release-grade confidence.

If a smoke test fails, capture the offending line from BugSack / the Lua error frame plus the exact slash command sequence that produced it and file an issue at the tracker referenced in [README.md](../README.md#issues-and-feature-requests).
