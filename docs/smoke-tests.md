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
| 9b | Locale | Non-English client seeds + resolves specs | [Non-English client](#9b-non-english-client-issue-8) |
| 9c | Icons | Render gating repaints correctly | [Icon render gating](#9c-icon-render-gating) |
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
| 20 | Focus tracking | Enable focus, independent gating, link/copy styling, per-unit alpha/tint | [Focus tracking](#20-focus-tracking) |
| 21 | Legacy migration | `FoldLegacyUnits` on a pre-`units` profile | [Legacy migration](#21-legacy-migration) |
| 22 | Text label | `modules/UnitLabel.lua`, Text Label settings panel | [Text label](#22-text-label) |
| 23 | Label style migration | `Database:BackfillLabelStyle` on a pre-`label.style` profile | [Label style migration](#23-label-style-migration) |
| 24 | Debug console scrollbar + counter | `DebugLog:UpdateScrollBar` / `UpdateStatus`, `ScrollingMessageFrameMixin` offsets | [Debug console scrollbar + line counter](#24-debug-console-scrollbar--line-counter) |
| 25 | LibKa0s seam | Degraded install + the shared `NS.LIBKA0S_MISSING` clause, the `L` trap | [LibKa0s seam](#25-libka0s-seam--degraded-install--the-l-trap) |
| 26 | Shared art + shipped face | `core/MediaSetup.lua`, the `NS.MakeCloseButton` wrapper, the DebugLog descriptor's `addonName` | [The shared icon set and the shipped face](#26-the-shared-icon-set-and-the-shipped-face) |
| 27 | Composed media rows | `LibKa0s-OptionsCompose` minor 3, the `Helpers.LSMValues` shadow | [Composed media dropdowns after the v1.26.0 re-vendor](#27-composed-media-dropdowns-after-the-v1260-re-vendor) |

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
- `KickCDDB` is now present on disk after `/reload` with `profileKeys`, `profiles.Default`, and the seeded `spells[CLASS][specID]` block for the current spec — the spec key is a **number** (e.g. `[262]`), never a spec name.
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

> **Run this section LOCKED.** While the frame is unlocked — now the default on a fresh profile (`locked = false`) — both pieces deliberately bypass the visibility mode (and the interruptibility alpha-mask) and always show at full alpha so you can reposition them. `/kcd lock` before exercising the modes below, or every row will read as "always visible". (Known follow-up, tracked separately: even while locked, a non-interruptible cast can intermittently leak through `target_casting_interruptible` because WoW's `notInterruptible` is unreliable at cast-start — see the repo issue tracker.)

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

**Setup.** On a fresh profile, `locked` defaults to `false` (`/kcd get locked` → `false`) — the frame is draggable out of the box, no `/kcd unlock` needed. `/kcd set units.target.castbar.anchorMode FREE` so the cast bar is independently draggable. Pick `visibility = always` so both pieces are visible without a casting target.

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
- Pummel's icon desaturates immediately on cast, with a cooldown swipe and (if enabled) the `Icons > Annotations > Show cooldown text` countdown ticking down.
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
- With **Settings → Spells already open**, swapping spec moves the spec dropdown to the new spec and re-renders its rows (regression: it used to stay pinned to the old spec until Settings was fully closed and reopened).
- Pet summon adds the pet's tracked interrupt to the visible grid; pet dismiss removes it. The dismissed pet's icon does not linger with stale state — `Cooldowns` emits a sentinel `SPELL_STATE { ready=false, isActive=false, cdObject=nil }` on poll-nil for the now-vanished spell.
- After dismiss, `/kcd debug spells` no longer lists the pet spell.

### 9b. Non-English client (issue #8)

**Setup.** A client set to a non-English locale — frFR is the reported case. Any class works; an Elemental Shaman reproduces the original report exactly.

**Steps.**
- Log in on a fresh profile and watch the grid populate.
- `/kcd debug spells`.
- `/kcd spells list`.
- `/kcd spells add 51490 ELEMENTAL` and `/kcd spells add 51490 Élémentaire` (the localized name).
- Upgrade path: log in with a `KickCDDB` saved by v1.2.0 or earlier that has customized spell lists, then inspect it after `/reload`.

**Expect.**
- The grid populates with the spec's default spells — the original bug was an entirely empty grid with no error.
- `/kcd debug spells` prints the English spec token alongside the numeric ID, e.g. `class=SHAMAN spec=ELEMENTAL (262)`, on every locale.
- The `[Cooldowns] rebuild` debug line reads `SHAMAN(7) ELEMENTAL(262): N watched (...); M skipped (...)` — English tokens and numeric IDs, not localized names.
- Both `/kcd spells add` forms resolve to the same list; output echoes the English token.
- Settings → Spells shows spec names in the client's own language (`Élémentaire`) while storing `[262]`.
- After the upgrade, `KickCDDB` has numeric spec keys and the user's customized entries are intact under them. **Repeat with a second profile** — the rekey is per-profile and must catch each one as it is activated, not just the profile that was active at upgrade.

### 9c. Icon render gating

**Setup.** `visibility = always`, cooldown text on, charges shown, a glow trigger configured on both the primary and a secondary icon. `Icon:Apply` skips glow / badge / Show work when no plain state field moved, so these steps confirm nothing that *should* repaint stopped repainting.

**Steps.**
- Put a spell on a long (30s+) cooldown and watch the icon through the whole cooldown.
- With that cooldown still running, change the glow type and glow color in Settings > Icons.
- With it still running, toggle cooldown text and the charges badge.
- Target a hostile caster and let it start and stop casting while a spell is on cooldown (glow trigger `target_casting` / `target_casting_interruptible`).
- Use a charged spell (e.g. a talented Mind Freeze) in combat and watch the badge as charges are spent and recharge.

**Expect.**
- The swipe animates smoothly with no stutter or restart, and the countdown text ticks continuously.
- The icon holds the cooldown alpha/tint for the **whole** cooldown, including its final second, and snaps to ready visuals only when the spell is actually castable. Brightening early is the regression the `evaluateByTotal` classification exists to prevent — the curves read the cooldown's total length, not its remaining time.
- Glow type / color changes take effect immediately, without waiting for the cooldown to end.
- Glow follows the target's cast start/stop while the spell stays on cooldown throughout.
- The charges badge keeps updating in combat, where the count is secret-tainted.

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
- `/kcd spells resetall` — verify it wipes *every* spec.

**Pass.**
- The active-spec write paths validate against the Cooldown Manager spell-set — adding a spell that isn't tracked there prints an error and is rejected.
- Editing a *different* class+spec falls through to the lenient validation path and succeeds for any valid spell ID.
- After every mutating subcommand, the Spells panel rebuilds rows live (it listens for `Ka0s_KickCD_CONFIG_CHANGED { section = "spells" }`) — no need to close and reopen the panel.
- `/kcd spells reset CLASS SPEC` rebuilds one spec from `NS.DefaultSpells`; the other specs are untouched.
- `/kcd spells resetall` calls `Database:ResetAllSpells` and wipes every spec.
- The Spells panel header **Defaults** button rebuilds *only* the currently-selected spec, matching `/kcd spells reset` (not `/kcd spells resetall`).
- On a character whose race has a racial cast-stopper (Tauren, Highmountain Tauren, Pandaren, Kul Tiran, Nightborne), resetting one of **your own class's** specs, from the Defaults button or `/kcd spells reset`, keeps the racial as the list's last row. Resetting another class's spec never adds it.

### 11. Settings panel parity

**Setup.** Open Settings → General with the chat window visible.

**Steps.**
- Toggle the General → "Enable KickCD" checkbox; observe `/kcd get enabled` reports the new value.
- Run `/kcd set scale 1.25`; observe the General → "Master scale" slider snap to 1.25x while the panel is open.
- Run `/kcd set units.target.castbar.growDirection LEFT` while `units.target.castbar.orientation = VERTICAL`. The error message should list the valid options for VERTICAL plus a `(depends on units.target.castbar.orientation = VERTICAL)` line.
- Run `/kcd list`. Spot-check that every General / Icons / Castbar row from the panel is present with its current value.
- For a number-type row, run `/kcd set <path> <out-of-range>` (e.g. `/kcd set scale 99`) — the value should clamp to the row's `max` (e.g. `2.00x`).
- For a color-type row, run `/kcd set units.target.castbar.interruptible.barColor 0.5 0.5 0.5` (3 floats, no alpha); the alpha should default to 1 and the row should accept the write.
- Drag a color slider in the panel's `ColorPicker`; chat / frame should not stutter or error on rapid drag (the throttle is 50ms via `Util.Throttle` in `settings/Panel_Widgets.lua`).
- **Panel-rebuild integrity.** On Settings → Icons, switch the **Unit** dropdown Target → Focus → Target a few times, click every tab in the strip in turn, then go to General → Units and tick / untick "Use same styling as Target" and press "Copy styling from Target". Then, with the panel still open, run any `/kcd set …`. Repeat the unit and tab clicking on Cast bar and Text Label.

**Pass.**
- **The Unit dropdown lists exactly `Target` / `Focus` on every page, always** — before and after those rebuilds, and after the `/kcd set`. A unit switch calls `Helpers.RenderUnitPanel` and a tab click clears and rebuilds the scroll; `/kcd set` then runs the whole refresher registry. If a refresher outlives the widget it captured, AceGUI's pool has already recycled that object into a different role and the stale closure overwrites it: the shipped symptom was the Unit dropdown listing **anchor points** on Icons and **text positions** on Cast bar. Any row's values appearing in a dropdown that shouldn't have them is this bug. Every other widget must also still show its own value, not a neighbor's.
- Every panel write fires `Ka0s_KickCD_CONFIG_CHANGED { section = … }`; subscribed modules redraw.
- Every slash write does the same and any open panel widget refreshes.
- `valueGate` errors name both the option list and the gating sibling.
- Number clamps respect `min` / `max` / `step`. Color writes accept 3 or 4 floats and clamp each to `[0, 1]`.
- **The tab strip matches the table in [settings-panel.md](settings-panel.md).** General shows `Master controls | Units`; Icons shows `Sizing | Layout | Visual states | Border | Annotations | Ready glow`; Cast bar shows `General | Size and position | Icon | Font | Spell name | Cast time | Interruptible | Non-interruptible`; Text Label shows `General | Placement | Font`; **Spells shows a one-tab strip reading `Spell list`**, with the spec picker and *Add spell* pinned above it. No tab name appears twice on one page (a duplicate means a row was filed under a group its page had already left), and **Profiles is the only page with no strip** — it stays one scrolling AceDBOptions page.
- **Every color swatch has a `Use class color` checkbox immediately to its right, on the same line.** Tick one and the surface takes a class color; the swatch stays enabled, because its opacity still applies. Against an NPC boss the cast-bar and label swatches keep their stored color — that is intended, and the swatch's tooltip says so. The Icons page's swatches take the PLAYER's class on both units' pages.
- **Icons → Annotations shows three headings** (`Icon`, `Font`, `Charges`), Cast bar → Size and position shows two (`Size`, `Position`), and Cast bar → Interruptible / Non-interruptible show four (`Bar`, `Background`, `Text`, `Border`). No page draws a heading that repeats the tab you just clicked.
- **Text Label → General → `Label text` is a text box you can type into**, not a dropdown that opens on nothing. Type a caption, press Enter, and the label above the grid changes.
- **Spells rows drag.** Grab the handle at a row's far left and move it several positions in one gesture; the list re-orders to where you dropped it, and the icon grid's priority order follows. There is exactly one box and one handle per row — two stacked fills means the host drew its own. Leave and re-enter the page twice: no handle or box is left stranded on anything.
- **The Unit dropdown sits ABOVE the tab strip, in the page's chrome, and stays there when you click a tab.** This is the check that catches the whole class of regression the banner exists to prevent: a picker drawn into the scroll looks correct until the first tab click and then disappears. Click through every tab on Icons and confirm the dropdown is still there, still naming the same unit, on each one.
- **Selecting a unit retargets every tab, not just the visible one.** On Cast bar with Focus unlinked, switch to Focus, click through to Interruptible, and confirm the colors shown are Focus's (`/kcd get units.focus.castbar.interruptible.barColor` agrees) rather than Target's.
- **Charges badge inset (new controls).** On a spell with charges, tick Icons → Annotations → "Show charges". With both `Charges X offset` and `Charges Y offset` at their defaults (`-2` and `2`) the badge sits exactly where it did before this setting existed — flush inside the icon's bottom-right corner. Drag `Charges X offset` to `-20`: the badge moves LEFT by 18 px. Drag `Charges Y offset` to `20`: it moves UP by 18 px. `/kcd set units.target.icons.chargesOffsetX 900` clamps to `32 px`, and the badge lands at the slider's maximum rather than off the icon.
- **Rotation reads in plain ASCII.** Text Label → Placement → "Rotation (degrees)" and `/kcd get units.target.label.style.rotation` both render e.g. `45 deg` — never an empty box where a degree sign used to be.
- **Renderer robustness (per-row `pcall` in `Helpers.RenderRows`):** a single malformed saved value degrades to one missing widget plus a red `schema error:` line — it does NOT blank the rest of the panel body (regression: a stale saved value once left a whole panel showing only its header). This is exercised by the headless suite (`tests/test_schema.lua`); it is not readily inducible in-game, so there is nothing to click here — it is listed for completeness of branch coverage.

### 12. Resets

| Command | Expected |
|---|---|
| `/kcd reset units.target.icons.primarySize` | That one row returns to its `default`; every other row, and the spell list, untouched. |
| `/kcd reset units.target.icons.cooldownTint` | A color row resets to a *copy* of its default — reset the same row on two profiles and confirm editing one doesn't move the other. |
| `/kcd reset general` (and `icons` / `castbar` / `label` / `spells`) | Retired. Each prints a line naming where the capability went — the panel's **Defaults** button, `/kcd reset <path>`, or `/kcd spells resetall` — never "Setting not found". |
| Each panel's **Defaults** button | All of that panel's rows return to their `default` values; other panels and the spell list untouched. With `/kcd debug on`, the console shows one `[Set] reset <page>: N rows` line (N = the rows that were off their default), and no per-row `[Set]` line. |
| `/kcd spells resetall` | Every spec's spell list is rebuilt from `NS.DefaultSpells` (NOT just the active spec). |
| `/kcd resetall` | Every schema-driven panel + every spec's spell list reset, AND every unit's icon-grid + cast-bar screen position restored to its `DEFAULT_PROFILE` anchor (anchors aren't schema rows; `resetall` is a profile reset now, so `db:ResetProfile()` puts `DEFAULT_PROFILE`'s anchors back with everything else and `Database:OnProfileChanged` re-seeds the spell lists — the dedicated positions pass it used to run is gone). Profiles untouched. No CLI confirmation prompt. |
| `/kcd resetposition` | Target icon grid snaps to `CENTER / CENTER, x = 0, y = +120` — **above** screen center, the coordinate `defaults/Profile.lua` ships; everything else untouched. The number is named here on purpose: `Helpers.ResetIconPosition` used to carry a second, hand-written copy of it that said `y = -180`, and a check that only asks whether the grid moved cannot tell the two apart. |
| Settings → General → **Reset all settings** button | StaticPopup confirm → same effect as `/kcd resetall`. |
| Settings → General → **Reset position** button | Same effect as `/kcd resetposition`. |
| Per-panel **Defaults** button (General / Icons / Cast bar) | That panel only; mirrors `/kcd reset <panel>`. |
| Spells panel header **Defaults** button | Currently-selected spec only; mirrors `/kcd spells reset CLASS SPEC`. |

**Pass.**
- No Lua errors at any reset path.
- Open panels reflect reset values without manual refresh.
- After `/kcd resetall`, `/kcd get enabled` returns `true` and `/kcd get visibility` returns `target_casting_interruptible` (the schema defaults from `settings/General.lua`).
- After `/kcd resetall`, the label + cast-bar defaults shipped on this branch hold (schema `default` ↔ `DEFAULT_PROFILE` are single-sourced/in-sync): `/kcd get units.target.label.show` → `true`, `units.target.label.style.offsetY` → `12`, `units.target.label.style.color` → `1 0.82 0 1`, `units.target.label.style.attach` → `icons`; `units.target.castbar.anchorPoint` → `BOTTOM_LEFT`, `castbarPoint` → `TOP_LEFT`, `anchorOffsetY` → `-1`, `timePosition` → `CENTER`, `timeOffsetY` → `-20`; both `units.target.castbar.interruptible.statusBarTexture` and `.uninterruptible.statusBarTexture` → `Blizzard Raid Bar`. `units.focus.label.style.*` reset to the identical values (single-sourced `LABELSTYLE_DEFAULT`).
- Drag either grid (or its cast bar) away from its default position, then `/kcd resetall`: the grid snaps back to its `DEFAULT_PROFILE` position (Target y=120, Focus y=260) rather than staying where it was dragged. (The cast bar is only independently draggable when `anchorMode = FREE`; in the default `PRIMARY` mode it follows the grid — the caveat in §5 `anchorMode FREE` setup applies here.)

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
- `Database:MigrateProfile` runs on profile change (`db.global.schemaVersion` should already read `CURRENT_DB_VERSION = 5` for an account that's run this build before; re-running should not error or re-fold anything). The schema version is account-wide in `db.global.schemaVersion`, not per-profile.
- Spell-list edits on one profile do not bleed into another.

### 14. Combat gating

**Setup.** Pull a target dummy so `NS.State.inCombat = true`.

**Steps.**
- Run `/kcd config` mid-combat.
- Run `/kcd set units.target.icons.primarySize 50` mid-combat.
- Still in combat, open the game menu → **Options → AddOns** and click **Ka0s KickCD** in the sidebar. Then click each of the six sub-pages in turn: General, Icons, Cast bar, Text Label, **Spells**, **Profiles**.
- Drop combat. Run `/kcd config` again.

**Pass.**
- Mid-combat `/kcd config` prints a one-line "cannot open during combat" message with the `[KCD]` banner and does NOT open the settings panel (Blizzard's category-switch is protected and would taint the panel).
- Mid-combat `/kcd set …` for non-protected operations succeeds and applies live (icon size, color, etc.).
- Out of combat `/kcd config` opens the settings panel landing on the Ka0s KickCD parent page with the subcategory tree expanded in the left nav (the parent page renders the logo + slash command list).
- Mid-combat, **every one of the six pages opened from the Blizzard AddOns sidebar** prints the library's refusal line and closes the Settings window. This is a **different path** from the `/kcd config` check above and it fails for different reasons: the sidebar reaches a canvas panel without going through `OpenOptionsPanel`, so the only guard on it is the one `Helpers.SetRenderer` installs (`libs/LibKa0s/Options.lua:796-815`). Spells and Profiles parked their own `OnShow` until `CX03` and had no guard at all on this path, so a green here before that change proved nothing about them — run all six, not a sample, after anything that touches a page builder's render wiring.
- Each of the six pages (General / Icons / Cast bar / Text Label / Spells / Profiles) appears **exactly once** under the Ka0s KickCD parent in the left nav — there is one registry now (LibKa0s-Options-1.0's), drained once from `OnEnable`.

### 15. Debug commands

**Setup.** Hostile caster targeted in combat is the most informative state.

| Command | Expected output |
|---|---|
| `/kcd debug spells` | Per-spell line: `ready=…  active=…  cdObj=yes/no  chargeCdObj=yes/no  charges=…`. Charges may render as `<secret>` for charged spells in combat. **No remaining-time field** — `:GetRemainingDuration()` is secret in combat and printing it would error. |
| `/kcd debug castbar` | Current target cast state plus configured + live per-state colors and `notInterruptible`'s `type()` and `issecretvalue()` flag. The dump uses `type()` / `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error. |
| `/kcd debug on` / `off` / `toggle` | Sets / clears the session-only `NS.State.debug` flag (never written to SavedVariables — resets to off on every `/reload`). Continuous debug output streams to the on-screen console window, not chat. There is no longer a `db.profile.debugLog` field or a General → "Debug" checkbox. |
| `/kcd debug window` | Toggles the on-screen debug console window (`LibKa0s-DebugLog-1.0`, wired in `core/DebugLogSetup.lua`); logging keeps running whether the window is open or closed. |
| `/kcd debug` | Toggles the console window and prints the debug subcommand help index. |

**Pass.**
- Every subcommand runs mid-combat without Lua errors.
- `interrupt` shows `<secret>` for `notInterruptible` (and any other secret-tainted field) when targeting a hostile caster mid-cast for a protected interrupt — never a Lua-coerced value.
- **`/kcd debug castbar` with and without `C_CurveUtil`.** Target a hostile caster mid-cast for a protected interrupt so `notInterruptible` comes back secret, and run the dump. The `current.notInterruptible: type=…, isSecret=true` line is **always** followed by a `secret-tainted; …` line — one saying the visual state is determined via `C_CurveUtil.EvaluateColorValueFromBoolean` where that evaluator exists, and one saying it is unavailable where it does not. **Fail:** the dump reports the field as secret and then says nothing further about it, which reads to whoever is given the paste as a dump that had nothing to say. A client without `C_CurveUtil` is the awkward half to arrange — a Classic-flavor or pre-12.0 build is the honest test; on a live Retail client the evaluator is present and only the first half is observable.
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

The vendored `AceGUI-3.0-SharedMediaWidgets` (r65) provides `LSM30_Statusbar` / `LSM30_Border` / `LSM30_Font` dropdowns. The fixup that hides the 42×42 Border `displayButton` preview tile and re-anchors the dropdown bar is `lib.__PatchLSM30Border()`, a `LibKa0s-Options-1.0` member called once from `settings/OptionsSetup.lua`. **This section checks it with KickCD alone, which is exactly the check that stayed green through the defect section 29 exists for** — run 29 too whenever this one matters.

**Steps.**
- Open Settings → Cast bar.
- Click the **Bar texture** (statusbar) dropdown, the **Border style** dropdown, and the **Font** dropdown.

**Pass.**
- Each dropdown opens, lists installed media, and applies a chosen entry live to the cast bar.
- The Border dropdown does NOT show a 42×42 black preview tile to the left of the dropdown bar (regression: that tile was the upstream lib's `displayButton`; the library's patch hides it).
- Switching to Settings → Icons and changing **Cooldown text font** updates the icon countdown immediately on the live grid.

### 19. Debug traces

Debug output is not chat: one gated, secret-safe line per key functional-flow transition, routed through `NS.Debug` to the on-screen console (see [testing.md](testing.md#debug-subcommands)).

**Setup.** `/kcd debug on`, then `/kcd debug window` to keep the console visible while driving each transition below.

**Steps + pass.**
- **Combat.** Enter combat (auto-attack a dummy), then leave combat. One `[Combat] entered` line appears when combat starts, one `[Combat] left` line when it ends — nothing at `PLAYER_LOGIN`, nothing per-tick during sustained combat.
- **Profile.** Settings → Profiles → switch to a different profile (or create one). One `[Profile] switched to '<name>'` line appears naming the new profile key. Then **Copy From** another profile: one `[Set] copied profile '<source>' → '<active>'` line, and no `[Profile] switched` line.
- **Resets.** Move two Cast bar settings off their defaults, then press the Cast bar page's **Defaults**: one `[Set] reset castbar: 2 rows` line, and no per-row `[Set] units.…` line. Press **Defaults** again: `[Set] reset castbar: 0 rows`. Then move three settings off their defaults (on any pages) and press **Reset all settings** (or `/kcd resetall`): exactly **one** `[Set]` line, `[Set] reset profile '<name>' to defaults (3 rows)`, with no `[Set] reset all` line beside it and no `[Profile] switched` line. Press **Reset all settings** again at once: `[Set] reset profile '<name>' to defaults (0 rows)`, never the schema's size. Then Settings → Profiles → **Reset Profile**: `[Set] reset profile '<name>' to defaults` with no count. A single `/kcd set locked true` afterwards logs its own `[Set] locked = true`, so the mute did not stick. Finally `/kcd set locked false` and press the General page's **Defaults** within a third of a second: `[Set] locked = false` prints **before** `[Set] reset general: …`, not after it.
- **Cast / IconGrid.** Set Visibility to `target_casting_interruptible`, then have a hostile target start and stop an interruptible cast. One `[Cast] target cast gate: interruptible on/off` line appears when the gate flips, and one `[IconGrid] visibility …: shown/hidden` line appears when the grid's shown state actually changes — no line on refreshes where neither moved.
- **Open.** `/kcd config` (or the minimap/options button) while out of combat. One `[Open] settings panel` line appears per successful open.
- **Spells.** Every spell-list write is traced once, by its one writer (`core/Database.lua`), so the Spells editor and `/kcd spells` log the same line. In the Spells editor: add a spell (`[Spells] add <spellID> to <CLASS>/<SPEC>: N spells`), toggle a row's enabled checkbox (`[Spells] enable/disable <spellID> in <CLASS>/<SPEC>`), change its category (`[Spells] category <spellID> = <cat> in …`), drag a row (`[Spells] move <from> -> <to> in …`), remove a row (`[Spells] remove <spellID> from <CLASS>/<SPEC>: N spells`), and click "Reset to defaults" for a spec (`[Spells] reset <CLASS>/<SPEC>: N spells`). Each act logs **exactly one** line, not two. Then `/kcd spells remove <id>` and `/kcd spells reset` log the same lines, and `/kcd spells resetall` logs one `[Spells] resetall: N lists, M spells`.
- **Set.** Change any setting on any panel (e.g. Icons → primary size). One debounced `[Set] …` line appears after the value settles — no re-echo, no per-keystroke spam (§10, Task 3).
- **No spam.** Across all of the above, stay in combat for 30+ seconds with no target-cast activity: no additional `[Combat]`/`[Cast]`/`[IconGrid]` lines appear beyond the transition(s) already logged.

### 20. Focus tracking

Focus tracking adds a second, independent (icon grid + cast bar) instance for the player's focus unit, rendering the same player cooldowns. Focus is ON by default (`units.focus.enabled` defaults to `true`, same as Target) and defaults to linking Target's appearance, offset 140px above Target's grid (Target y=120, Focus y=260) — a computed estimate leaving ~10px of clearance between the Focus cast-timer bottom and the Target label top; nudge Focus Y if the rendered gap isn't quite right.

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
- Select **Focus** in the Icons panel's Unit dropdown. Confirm the page draws its **tab strip** and no appearance rows — just the Unit dropdown in the chrome, the strip, and the note *"Linked to Target. Untick 'Use same styling as Target' on the General page's Units tab to give Focus its own."*
- **The strip is inert.** Every tab on it is **desaturated** and **none of them can be clicked** — every tab of a linked page draws the same note, so a clickable strip would redraw the identical page. Confirm the strip is still THERE (the page must not change shape when the picker flips) and that switching back to Target restores full color and clickability.
- **The note is a link.** *"General page's Units tab"* is drawn in link blue. Mouse along the whole line: **nothing lights up behind it** — no plate, and above all no bright-green block (AceGUI paints one for a `SetHighlight` given color numbers). Clicking anywhere on it opens **General**, already on the **Units** tab — not the parent category, not General's Master controls tab. Then pull something and click it in combat: it must refuse with `[KCD] cannot open settings during combat` and **not** open the panel (Blizzard's category switch is protected — opening it under lockdown taints the panel for the session).
- **The Unit dropdown is one selection across the three pages.** With Focus selected on Icons, walk to **Cast bar** and to **Text label**: both open on **Focus**, not back on Target. Flip one of them to Target and return to Icons — it is on Target too. Then `/reload`: every unit page opens on **Target** again, because the selection is session-only and deliberately not saved.
- Change Target's `units.target.icons.primarySize` (switch the dropdown to Target first). Switch back to Focus — the linked Focus grid should visually match Target's new size live (no manual sync needed).
- Go to **General → Units** and untick "Use same styling as Target". Return to Icons with Focus selected: the tab strip and the appearance rows appear, seeded with target's last-copied values (or defaults if never copied). The tick reaching a page you were not looking at is the point — it is a structural refresh, and a page that was hidden repaints on its next show.
- Change a Focus-only appearance value (e.g. `units.focus.icons.primarySize`) — confirm Target's grid is unaffected.
- Re-tick "Use same styling as Target" on General → Units — Focus reverts to mirroring Target live, and the Icons page collapses back to the note under its now-inert strip; the customization from the previous step is no longer visually active (though not necessarily wiped from `units.focus.icons` — the schema row is simply not read while linked).
- On **General → Units**, the tick and the button are **one line**: `[Use same styling as Target] [Copy styling from Target]`, the button in the right half. A button on a line of its own reads as belonging to whatever follows it rather than to the tick above.
- Untick again, then click **"Copy styling from Target"** (also on General → Units). Every Focus `icons` / `castbar` / `label.style` row and `label.show` takes Target's current value, row by row through the settings helper, and `link` flips to `false` (the button also unlinks if still linked). Before clicking, give Target a **vertical** cast bar growing **Down**; after, Focus's bar is vertical and still grows Down (orientation's own reset to Up must not win). With `/kcd debug on`, the console shows **one** `[Set] copy target→focus: N rows` summary line for the whole copy (N is the rows the copy changed: the Target rows you moved off their defaults, plus the link), **no** per-row `[Set] units.focus.…` lines, and no Lua error.
- `/kcd set units.focus.link false` unlinks exactly as the tick does: the tick unticks on an open General page, and the three unit pages grow their rows back. `/kcd set units.focus.link true` collapses them to the note again. With Focus unlinked, the General page's **Defaults** button re-links it.

**Pass.**
- While linked, `NS.Units.Icons("focus")` / `.Castbar("focus")` resolve to `units.target.icons` / `.castbar` — verified by the live visual match in the steps above.
- Position (`units.focus.anchors.icons`/`castbar`) and the Focus identity label (`units.focus.label.text`, if shown) stay independent of Target's position/label at every step, linked or not — dragging the Focus grid never moves Target's.
- "Copy styling from Target" is a one-time deep copy (not a live link) — a subsequent Target-only appearance change does NOT propagate to the now-unlinked Focus.
- Neither control appears anywhere else. There is exactly one "Use same styling as Target" tick and one "Copy styling from Target" button in the whole panel, both on General → Units; the three unit pages carry the note and nothing else.
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

#### 20d. Unlinked focus honors its own alpha / tint

Unlink **first**: untick **"Use same styling as Target"** on Settings → General → Units, or `/kcd set units.focus.link false` (the link is a schema row, `units.focus.link`; there is no `units.target.link`, since Target is never linked). Getting this wrong is what hid the regression this scenario now guards: the values below were set while focus was still silently linked, so focus resolved target's table and the two grids rendered identically.

This is also the reason to unlink **first** and set values **second**.

**Setup.** `visibility = always` (no focus target needed — in this mode `shouldBeVisible` returns true regardless of unit existence, so both grids sit on screen for side-by-side comparison). Both units enabled:

```
/kcd set enabled true
/kcd set visibility always
/kcd set units.target.enabled true
/kcd set units.focus.enabled true
```

Open Settings → **General → Units** and **untick "Use same styling as Target"**. Then open Icons and pick **Focus** in the Unit dropdown; confirm the tab strip and the appearance rows appear. Only then:

```
/kcd set units.target.icons.cooldownAlpha 0.20
/kcd set units.target.icons.cooldownTint 1 0.3 0.3 1
/kcd set units.focus.icons.cooldownAlpha 0.90
/kcd set units.focus.icons.cooldownTint 0.3 0.3 1 1
```

`/kcd unlock`, drag the two grids apart if they overlap, `/kcd lock`.

**Steps.**
- Cast an interrupt at a friendly target dummy. Use one whose cooldown is comfortably over ~1.6s — any real interrupt (15–24s) qualifies. Both grids render the same player cooldowns, so one cast drives both.
- Watch both grids during the cooldown.
- Mid-cooldown, run `/kcd set units.focus.icons.cooldownAlpha 0.40`.
- Mid-cooldown, change target's border **style** on Settings → Icons (the `units.target.icons.borderTexture` row, "Border style") to a visibly different LSM border. Style is the clearest of the three border rows to eyeball: it changes the whole edge treatment, whereas `borderColor` only repaints it and `borderSize` defaults to `2` on a composed 0-16 slider, so a one-step thickness change is invisible and proves nothing.
- **Leave the settings panel open** for the two steps above — a `/kcd set` with a panel open fires every refresher in `ctx.refreshers` (through `RefreshScalars`), which is the path that once corrupted the Unit dropdown after a rebuild (see 11).
- Re-tick "Use same styling as Target" on General → Units.

**Pass.**
- Target's icon is heavily dimmed and red-tinted; focus's is nearly full brightness and blue-tinted. They must be **clearly different**. Identical grids mean focus is inheriting target's curves.
- The mid-cooldown focus alpha change takes effect **while the cooldown is still running**, and target is unaffected — the curve rebuild guard re-opens on a real change instead of stranding a stale curve.
- Target's border visibly changes style and **neither** grid's alpha or tint shifts — an unrelated `icons` edit must not disturb the curves.
- The **Unit** dropdown still lists exactly `Target` / `Focus` on every tab after those `/kcd set` calls. Anchor points, text positions, or any other row's values appearing there means a stale refresher survived a panel rebuild.
- Re-ticking the checkbox immediately reverts focus to target's dim-red values, with no `/reload`.
- Zero Lua errors throughout.

**Note.** While only the GCD is running (no real cooldown on the watched spell) both icons correctly show ready visuals — the curves classify that lockout by its total length, below `Const.GCD_UPPER`. If both look bright and untinted right after you press something else, wait a moment — that is not a failure.

**Cleanup.** Icons panel → **Defaults**.

### 21. Legacy migration

**Setup.** On a test account/character, quit WoW. Edit `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` (or a backed-up copy from before this feature) so the active profile has top-level `icons`, `castbar`, and `anchors` tables with a few customized values (e.g. a non-default `icons.primarySize`, a moved `anchors.icons`) and NO `units` table. Set `db.global.schemaVersion` to `1` or remove it entirely (either should trigger the fold).

**Steps.**
- Log in.
- `/kcd get units.target.icons.primarySize` — compare to the customized value from the edited file.
- `/kcd get units.target.anchors.icons` (or visually check the grid's position) — compare to the customized anchor.
- `/reload`, then inspect `KickCDDB` on disk: confirm `profiles.<key>.icons` / `.castbar` / `.anchors` no longer exist at the top level and `profiles.<key>.units.target.{icons,castbar,anchors}` hold the customized values. `db.global.schemaVersion` should read `4` — `MigrateProfile` loops forward one step at a time, so a v1 account runs the v1→v2 fold, the v2→v3 spec-key rekey and the v3→v4 color-shape rewrite in the same login. Spot-check one color (e.g. `/kcd get units.target.icons.cooldownTint`) to confirm it survived as the user's value, not the default — a positional color arrives at the migrator as an AceDB hybrid whose *keys* hold the defaults.

**Pass.**
- No Lua errors during the migration login.
- The icon grid renders at the SAME position and with the SAME customized appearance as before the migration — visually, nothing changes for the user.
- `Database:FoldLegacyUnits` output is idempotent: a second `/reload` doesn't move anything or error (the top-level tables are already gone, so the shape check short-circuits).
- Focus (`units.focus`) is present with its own fresh defaults (`enabled = true`, `link = true`) — the migration only touches target, since legacy accounts only ever had one unit.

### 22. Text label

Each unit (target/focus) can show one configurable identity label, rendered by `modules/UnitLabel.lua` and configured on its own **Text Label** settings tab (`settings/Label.lua`, panel/section `label`, after Cast bar).

**Setup.** `/kcd set units.target.enabled true` and `/kcd set units.focus.enabled true`. Open Settings → Text Label. (On the way, confirm Settings → **General** no longer carries any label show/text controls — those moved to this Text Label tab; General keeps only the per-unit **Enable** rows.)

**Steps.**
- Select **Target** in the Text Label panel's unit dropdown. **Show label** is checked by default; confirm a label reading "Target" already appears just above the target icon grid (the default `attach = "icons"`, `point = "BOTTOM"`, `relPoint = "TOP"`, `offsetY = 12`). Toggle **Show label** off/on; confirm the label disappears/reappears.
- Edit **Label text** to something custom (e.g. "MainTank"); confirm it updates live, no `/reload` needed.
- Switch **Attach to** from `castbar` to `icons`; confirm the label re-anchors to the icon grid frame instead, still tracking live as the grid moves/resizes (drag the grid; the label follows via the next `Ka0s_KickCD_GRID_LAYOUT`).
- Walk the anchor/attach point pair (`Label anchor point` / `Attach point`) through a few combinations (e.g. `TOP`/`BOTTOM`, `LEFT`/`RIGHT`) and vary **X offset (in px)** / **Y offset (in px)**; confirm the label's position updates live and matches the chosen points + offsets. Every option in both dropdowns is a native `SetPoint` anchor (`TOPLEFT` … `BOTTOMRIGHT` / `CENTER`), so selecting *any* combination repositions the label with no Lua error — regression guard: an earlier build fed the icon grid's `<SIDE>_<ALIGN>` tokens (e.g. `TOP_MIDDLE`) straight into `SetPoint`, which errored on the first non-`CENTER` pick and left the default unselectable in the dropdown.
- Set **Horizontal justify** / **Vertical justify** through their values; confirm text alignment changes visibly (most apparent with multi-word text).
- Set **Rotation (degrees)** to a nonzero value (e.g. 45, -90); confirm the label visibly rotates and returns to upright at 0.
- Change **Font** / **Font size** / **Font flags**; confirm the label's rendered font updates live (LSM dropdown, same widget family as Cast bar → Font).
- Change **Label color** (color picker in the Font group) to a distinct color (e.g. bright green or red); confirm the label's text color updates live. Switch **Attach to** between `castbar`/`icons`; confirm the color persists across the re-anchor.
- Switch to **Focus** in the unit dropdown with `units.focus.link = true` (the default): confirm the Text Label page now shows only the "Linked to Target…" note, under a desaturated and unclickable strip — no Show label / Label text / Placement / Orientation / Font rows are rendered while linked (matching the Icons and Cast bar pages). Focus's label still renders live (with Target's style, including color) if `units.focus.label.show` is `true` in the saved profile — it's just not editable from this page while linked.
- Uncheck "Use same styling as Target" for Focus: confirm the page now shows the full Show label / Label text / Placement / Orientation / Font body again. Set Focus's label text to something distinct from Target's (e.g. "Kick this") and change one style value (e.g. rotation or color); confirm Target's label is unaffected and both units can show different text with different styles. Re-check the link; confirm the body collapses back to the note and Focus's label style (including color) reverts to mirroring Target's live (text stays as "Kick this" — text is per-unit data, not link-resolved).
- With both labels shown, toggle `units.focus.enabled` off; confirm the Focus label disappears immediately (independent of Target's, which stays visible) and reappears when Focus is re-enabled.
- Toggle **Show label** off for Target while Target's icon grid/cast bar remain visible; confirm only the label disappears, not the grid/bar.
- **General-visibility follow (reversal of the old "independent visibility" behavior):** the label follows the icon grid's General-visibility state (its position still comes from the chosen attach frame). Set `visibility = target_casting` (or `target_casting_interruptible`) via General settings, with **Show label** on for Target. With the target NOT casting (grid + cast bar hidden per General visibility), confirm the Target label is ALSO hidden — it no longer floats on screen while the grid is hidden. Start a target cast; confirm the grid/cast bar AND the label all appear together. Stop casting; confirm all three hide together. Repeat with `attach = "icons"` to confirm the label follows the icon grid's visibility too, not just the cast bar's.
- **Always-visibility regression guard (the bug this fix addresses):** set `visibility = Always` via General settings, with **Show label** on for Target and the default `attach = "icons"`. With the target NOT casting (so the cast bar itself is hidden — it only shows during an active cast), confirm the Target label IS still shown, anchored above the icon grid. This is the case a prior build broke: parenting the label to the cast bar (instead of the icon grid) made it cast-gated, so it stayed invisible in Always mode whenever nothing was being cast — even though the grid itself was always visible.

**Pass.**
- Every field change is live — no `/reload` required for any of the above.
- Target and Focus labels are visually and positionally independent (dragging the grid/cast bar of one never moves the other's label), while sharing identical default style values (including color) out of the box.
- A label is visible only when BOTH `label.show` is on AND the icon grid is currently shown per General visibility — the label never floats on screen while the grid is hidden, and (the regression this fix addresses) it is NOT additionally gated by the cast bar's own cast-presence hiding when attached to the cast bar.
- No Lua errors at any step, including rapid attach-mode switching, rapid slider drags on offset/rotation, and visibility-mode changes.

### 23. Label style migration

**Setup.** On a test account/character, quit WoW. Edit `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` (or a backed-up copy predating this feature) so the active profile's `units.target.label` and `units.focus.label` exist as `{ show, text }` only — **no** `style` sub-table. Leave `db.global.schemaVersion` as-is (this migration is shape-driven, not version-gated, so it runs regardless).

**Steps.**
- Log in.
- `/kcd get units.target.label.style.font` (or open Settings → Text Label and confirm the Font/placement/orientation rows show sane default values rather than erroring or rendering blank).
- `/reload`, then inspect `KickCDDB` on disk: confirm `profiles.<key>.units.target.label.style` and `profiles.<key>.units.focus.label.style` are now both present and match `LABELSTYLE_DEFAULT` in `defaults/Profile.lua`.

**Pass.**
- No Lua errors during the migration login or on the Text Label panel.
- If a label was already shown pre-migration (`label.show = true` in the edited file), it renders identically before and after — **no visual change**, since the backfilled `style` values equal the shipped defaults the label was implicitly using anyway.
- `label.show` / `label.text` values from the edited file are preserved exactly (the migration only fills in the missing `style` sub-table).
- A second `/reload` doesn't error or re-write anything (`Database:BackfillLabelStyle` is idempotent — it only acts when `style == nil`).

---

### 24. Debug console scrollbar + line counter

**Setup.** `/reload`, then open the console with `/kcd debug window`. Turn capture on (`/kcd debug on`, or the header "Debug: OFF/ON" button) so lines stream in; targeting a hostile caster in combat fills it fastest.

**Checks.**
- **Header renders.** The title-bar "Debug: ON/OFF" label is present and colored (green ON / red OFF) — i.e. the initial scrollbar/counter sync didn't abort the build. ESC closes the window (`UISpecialFrames` registration intact).
- **Line counter.** The bottom-right label reads `N / 1500 lines` and `N` climbs by one per appended line. `/kcd debug spells` (and friends) print to chat, not here — use `/kcd debug on` + live combat, or repeated events, to grow `N`. Hit **Clear**: the counter resets to `0 / 1500 lines` and the log empties.
- **Scrollbar tracks the wheel.** With more lines than fit, mouse-wheel up/down over the log — the thumb moves in step. Drag the thumb — the log scrolls to match. No flicker or runaway (the `_syncing` re-entrancy guard holds).
- **Thumb direction.** Thumb at the **bottom** = newest lines (offset 0); thumb at the **top** = oldest. If it reads inverted, the `sliderValue = maxRange − offset` mapping in `LibKa0s-DebugLog-1.0` has the wrong sign — fix it upstream in `../LibKa0s` and re-vendor, never in `libs/`.
- **Inert when it fits.** Right after Clear (or with only a few lines), the scrollbar is still shown but the thumb is parked and the bar ignores mouse/drag; the right-edge gutter stays the same width.
- **The shared Ka0s window edge.** ⚠ This is chrome the addon does not own: `core/DebugLogSetup.lua` passes no `applySkin` and no `makeCloseButton`, so both the console and the `/kcd perf` step panel take `Core.SKIN` / `Core.ApplySkin` verbatim. The window must read as a **flat 1px black outer border** with a **1px light-gray highlight** one pixel inside it, a **gold** "Ka0s KickCD — Debug" title and a **gray** divider under the title bar — not the soft brown 12px tooltip frame with a black divider and a white title it wore before LibKa0s v1.3.0. Then open a **second** Ka0s addon's console (AbsorbTracker, ConsumableMaster, BankLedger or LootHistory) and put them side by side: border, highlight, divider and title colors must be **indistinguishable**. A difference is either a host that has gone back to passing `applySkin`, or `libs/LibKa0s` drifting from `../LibKa0s` — fix it upstream and re-vendor, never in `libs/`.

**Pass.**
- Opening the console never throws (`GetNumLinesDisplayed` / `GetCurrentScroll` are **not** called — only `GetMaxScrollRange` / `GetScrollOffset` / `SetScrollOffset`).
- Counter increments on every append and resets to `0 / 1500 lines` on Clear.
- Wheel ↔ thumb stay synced both ways with the thumb bottom = newest.
- The window edge, inner highlight, divider and title match a second Ka0s addon's console exactly.

### 25. LibKa0s seam — degraded install + the `L` trap

Both halves are invisible headlessly and both are cheap. Run after any change under `libs/LibKa0s/`
or to a seam file (`core/CoreSetup.lua`, `core/DebugLogSetup.lua`, `core/PerfSetup.lua`,
`settings/OptionsSetup.lua`, `settings/Slash.lua`).

**Setup.** Rename `Interface/AddOns/KickCD/libs/LibKa0s` to `libs/LibKa0s_off`, `/reload`.

**Checks — the degraded half.**
- **It degrades, it does not error.** Zero Lua errors at login. `/kcd` still answers and the host verbs still work; `/kcd list` is **complete** — every unit / icons / castbar / label path present, because the page files must finish loading even with no panel library.
- **One cause, said once.** The missing-library notice appears **exactly once** per session however many lines print afterwards, and it names `libs/LibKa0s`.
- **The same sentence the other two addons say.** ⚠ This is the check the section exists for. The cause clause is `NS.LIBKA0S_MISSING` in `core/CoreSetup.lua` — one shared string that every seam appends its own *"so &lt;what&gt; is unavailable"* to. Do the same rename on **AbsorbTracker** and **ConsumableMaster** and compare: all three must state the cause identically, differing only in the trailing consequence and the addon name. KickCD used to phrase this its own way; converging it is the whole point, and a drift here means a seam grew its own wording again.
- **Each seam names its own consequence.** `/kcd config` opens nothing and prints one line about the settings panel; `/kcd debug` says its piece about the console; `/kcd perf` about the capture. Same cause, different tails.

**Checks — the `L` trap.** Rename the folder back and `/reload` first; this half needs the library present.
- Open `/kcd config` and walk every panel, then `/kcd debug window` and `/kcd perf`. Every label, tooltip title, section heading, button and perf step name reads as **English prose**.
- A `SCREAMING_SNAKE_CASE` string on screen — `STEP_START`, `PANEL_TITLE_SUFFIX`, `LIST_HEADER` — is the trap: a descriptor was handed `NS.L`, whose metatable answers every key with the key, so the library's own strings became unreachable. It fails for every key in that module at once, so one sighting means dozens. **This addon has shipped this bug**: a perf panel once read `Ka0s KickCDPANEL_TITLE_SUFFIX` / `STEP_START` / `STEP_MEASURE_A` in exactly this way.
- The one legitimate override is `settings/Slash.lua`'s `L = NS.L and { LIST_HEADER = … } or nil` — a freshly built table, not `NS.L` itself. `tests/test_perfsetup.lua` guards the source (including the `and` → `or` typo that would quietly turn it back into the trap); this step is the only one that sees what actually rendered.

**Pass.**
- Rename the folder back and `/reload` before you finish — a `libs/LibKa0s_off` left in place is a silently degraded addon.
- Degraded: no errors, complete `/kcd list`, one notice, wording identical to the other two Ka0s addons.
- Normal: not one SCREAMING_SNAKE string anywhere in the UI.

---

### 26. The shared icon set and the shipped face

The art on the console's title bar and the face its lines are drawn in both live in the VENDORED
LibKa0s payload (`libs/LibKa0s/media/`), not in this addon. Neither can be checked headlessly: a
texture path that resolves to nothing draws nothing and raises nothing, and `SetFont` on a missing
file loads nothing and raises nothing. That is the whole reason this section exists.

Run after any LibKa0s re-vendor, and after any edit to `core/MediaSetup.lua`, `core/CoreSetup.lua`,
`core/DebugLogSetup.lua`, `core/PerfSetup.lua` or `core/Constants.lua`.

**Setup.** `/reload`, then `/kcd debug window`.

**Checks.**
- **The console title bar is three MARKS, not two words and a glyph.** Left to right on the right-hand
  side of the bar: a **copy** sheet, a **clear**/eraser mark, and a **close** cross — all three small
  white square glyphs of the same weight, all three from `libs/LibKa0s/media/icons/`. There is **no
  tooltip** on any of them, and that is deliberate: one shipped for a single release, anchored under
  the control, and it covered the first line of the log.
- **The regression to watch for is a multiplication sign.** A `×` on the console close — or the words
  `Copy` and `Clear` next to it — means the addon FOLDER name stopped reaching the library. The
  library is vendored: it cannot work out which folder it was copied into, so it falls back to the
  glyph and the words when nothing tells it. The one line that tells it is `addonName = addonName`
  in `core/DebugLogSetup.lua`'s descriptor, beside `name` and not instead of it.
- **The copy window closes with the same mark.** Click **copy**; `KickCDDebugCopyWindow` opens with a
  read-only edit box. Its close control must be the same `close` art, not a `×`. A mismatch between
  the two windows means the descriptor is right and something else regressed.
- **The perf panel closes with the same mark, too.** `/kcd perf start` and look at the step panel's
  top-right. ⚠ **As of `M4-16` no close button in this addon is built by the HOST** — this one used
  to be, through a `decorate` hook in `core/PerfSetup.lua`, and that hook is gone; the library's own
  `PerfPanel` arm draws it now, from the `addonName` the descriptor states. So this bullet has
  changed meaning: it is no longer checking a wrapper call, it is checking that a descriptor field
  reached the library. Put the panel and the console on screen together and compare the two close
  controls pixel for pixel — see **30** for the full check.
- **The console text is monospace.** Timestamps and `[tags]` line up in a column down the left. If
  they do not, `Const.FONT_MONO` resolved to something that is not JetBrains Mono. Two outcomes are
  possible and they look different: a **proportional** face means the fallback to the client's
  `STANDARD_TEXT_FONT` fired (no library, or `media/fonts/` missing from the payload — honest
  degradation); **no text at all** means the path is dead, which is the failure the fallback exists to
  prevent and is never acceptable.
- **The face is in the font dropdowns.** `/kcd config` → **Text Label** → the font dropdown lists
  **JetBrains Mono** beside the player's other fonts. `core/MediaSetup.lua` registers it with
  LibSharedMedia at file load; if it is missing, `Media.RegisterLSM` did not run or ran before LSM.
- **Degraded stays honest.** Rename `libs/LibKa0s` to `libs/LibKa0s_off` and `/reload` (section 25's
  setup). The console is gone entirely with the library, but `/kcd config` must still open, still
  render text, and the **Text Label** font dropdown must simply not list JetBrains Mono. No errors, no
  blank labels. Rename it back before you finish.

**Pass.**
- Copy, clear and close are art; nothing on the title bar is a word or a `×`.
- The console close, the copy-window close and the perf panel close are the SAME mark.
- Console timestamps line up; JetBrains Mono is in the font dropdown.
- With the library renamed away: no errors, no missing text, no dead font.

---

### 27. Composed media dropdowns after the v1.26.0 re-vendor

**Smoke, session 4.** The proof that `LIBKA0S-A-01` — the collection's only Critical — is closed in a
consumer, and the proof that closing it did not break the one consumer that was already working around
it. Nothing here is headless-testable end to end: the harness pins that a composed media row hands back
a **reader** rather than a reading, but only a live client has a LibSharedMedia that fills after the
schema files have been read, which is the whole failure mode.

**Setup.** A media addon that registers extra faces, borders and bar textures — SharedMedia,
SharedMediaAdditionalFonts or ElvUI's media pack — enabled alongside KickCD, so LSM holds more than the
Blizzard defaults. Log in fresh; do not `/reload` before the first check.

**Steps.**
- `/kcd config` → **Icons**. Open **Border texture** and **Cooldown text font**.
- → **Text Label**. Open the **Font** dropdown.
- → **Cast bar**. Open **Font**, and for BOTH the interruptible and the uninterruptible state open
  **Bar texture** and **Border texture**. That is eight dropdowns across the three pages; they are the
  eight composed rows this item moved.
- `/dump LibStub("LibKa0s-Options-1.0").MODULES.OptionsCompose`
- Pick a non-default face in **Text Label** → **Font** and confirm the label redraws in it.
- Now the deferral itself, which is the half a snapshot would pass: with the client already running,
  enable a media addon you had disabled, `/reload`, and re-open **Cast bar** → **Bar texture**.

**Pass.**
- All eight dropdowns list real media — several faces, several borders, several bar textures — not a
  single `Default` entry and not an empty list that opens onto nothing.
- The `/dump` reports **3**. A 2 means the vendored payload is still v1.25.0 and CLAUDE.md's provenance
  line is lying; anything else means a foreign LibKa0s won the LibStub resolve.
- The chosen face applies live, and survives `/reload`.
- The newly registered media appears in the dropdown after the reload. If the list is identical to what
  it held before, `Helpers.LSMValues` (`settings/Panel.lua`) has gone back to returning a **table** and
  every composed media row is frozen at file load — silently, with no error and no empty control. That
  is the regression this step exists to catch, and it is invisible to every other check in this suite.
- No Lua errors at any point.

### 28. The pooled tab strip, and the perf strings, after the v1.27.0 re-vendor

**Smoke, session 3.** Two things arrived with `M4-01`'s LibKa0s v1.27.0 payload that only a client
can settle. Nothing here may be reported as passing until someone has actually looked at it.

`TabStrip` (`libs/LibKa0s/OptionsWidgets.lua`) no longer builds a button and a content panel per
click: it acquires both from per-`ctx` `LibKa0s-Pool-1.0` pools and re-dresses them, re-setting
`OnClick` on every dress. Its only headless proof counts `CreateFrame` calls on a second selection
pass, and the case that would pin band geometry as invariant under selection cannot be written yet —
the shared mock answers `GetHeight` with 0 for every frame, and kit 17 (LibKa0s v1.31.0, unchanged at v1.32.0) did not
flip that either: the flip ships alone, at kit 18 at the earliest, not here. **So a
stale label, a mis-anchored button or a band that changes height on a re-dressed tab is invisible to
every automated check in this repo.**

**Steps — the strip.**
- `/kcd config` → **General**, **Icons** (six tabs, the widest strip here) and **Cast bar**. On each
  page, cycle every tab three times, ending back on the first.
- Watch three things on each pass: the **label** is that tab's own, the **selected** tab is the one
  you pressed, and the strip's **band height** does not move as you go through it.

**Steps — the strings.** `LibKa0s-Perf-1.0` minor 8 respells five player-facing strings: two
`CANCELLED` and three `unlabelled` become `CANCELED` and `unlabeled`. No single capture shows all
five, so run two.
- `/kcd perf start mylabel`, then `finish` — the started line and the report header both name the
  label.
- `/kcd perf start` with no label, then `cancel`.

**Pass.**
- Every tab labeled and selected correctly on all three passes, on all three pages, and no band that
  grows or shrinks. A label carried over from the previously-dressed tab, a highlight on the wrong
  button, a body drawn under the wrong tab, or a strip whose height moves between passes is the pool
  handing back a frame it did not finish dressing.
- The unlabeled start line, its report header and the cancel line read **`unlabeled`** and
  **`perf run CANCELED`**. A double-L in either is a copy of the string that did not come from the
  vendored payload.
- No Lua errors at any point.

### 29. The Border dropdown when five Ka0s addons share one registry

**Smoke, session 5.** Run after this addon's `core/LSMPatch.lua` was deleted and
`settings/OptionsSetup.lua`'s live wiring took over the fixup (`M4-04`), and again after **each** of
the four remaining deletions — PanelMaster, ConsumableMaster, MultiMeters, then AbsorbTracker last,
because AbsorbTracker's copy is the one that diverges (a callable `NS.ApplyLSMBorderPatch()` rather
than a `PLAYER_LOGIN` frame). Five deletions, five commits, five bisect points if this goes wrong.

**The thing under test is not KickCD.** AceGUI's `WidgetRegistry` is process-global: one slot named
`LSM30_Border` shared by every addon in the client. Five Ka0s addons each carried a private copy of
the wrapper, each registering at whatever version it found plus one, so the wrapper a Border dropdown
actually got belonged to whichever addon the client loaded last. Nothing headless in any of the five
repos could see it — each suite loads one copy, registers once and passes — and section 18 above,
which checks the alignment with KickCD alone, passed throughout.

KickCD is now the **only** one of the five with no private copy. So this run is also the first
evidence that one library-level registration is enough to dress a dropdown in an addon that no longer
carries its own.

**Steps.**
- Enable KickCD, PanelMaster, AbsorbTracker, ConsumableMaster and MultiMeters together, and log in.
- Open each addon's Border dropdown in turn. KickCD's is `/kcd config` → **Cast bar** → **Border
  style**.
- Change the load order — disable and re-enable addons, or rename folders so a different one is
  reached last — `/reload`, and walk the five dropdowns again.

**Pass.**
- In all five, the closed control's left edge is **flush** with the sliders and checkboxes stacked
  with it, with **no ~42px gap**, and opening it still draws the per-row hover previews.
- Nothing differs between the two passes. **Any dropdown that looks different from the other four, or
  that changes when the load order changes, is the finding** — the whole point of moving the
  registration into LibKa0s is that the answer no longer depends on who loaded last.
- No Lua errors at any point.

---

### 30. The perf panel's close control, after `decorate` was deleted

**Smoke, session 3.** Run after `M4-16` removed the `decorate` field from `core/PerfSetup.lua`'s
descriptor. **Nothing on screen is supposed to change**, and that is precisely why it needs a human:
the change swaps which code draws the control, not what the control looks like, and the two arms are
exclusive — `libs/LibKa0s/PerfPanel.lua` runs the host's hook **or** its own else arm, never both. For
as long as the hook existed the library's arm never ran once in a client from this addon, so this is
the first time it will have run at all. A headless case pins the argument that reaches the factory
(`tests/test_perfsetup.lua`); nothing headless can see what was drawn.

**Setup.** `/reload`, then `/kcd perf start`.

**Checks.**
- The step panel opens with **exactly one** close control in its top-right corner — not two stacked on
  the same corner, and not none.
- That control is the shared **`close`** mark from `libs/LibKa0s/media/icons/`, the same small white
  glyph the debug console wears. **A multiplication sign `×` is the regression**, and it means the
  addon FOLDER name stopped reaching `MakeCloseButton`: the library is vendored, cannot infer which
  folder it was copied into, and falls back to the glyph when nothing tells it. The one line that
  tells it is now `addonName = addonName` in the perf descriptor.
- It sits at the same inset from the same corner as before the change — level with the title, ~6px in
  from the right edge. Put the panel and `/kcd debug window` on screen together and compare the two
  close controls pixel for pixel; they come from one factory and must be indistinguishable.
- **Clicking it hides the panel** and nothing else: the run is not canceled, and `/kcd perf report`
  afterwards still has the capture. The click handler is now the library's own `HidePanel` rather
  than one this addon passed in, which is the half of the swap a screenshot cannot show.
- No Lua errors at any point.

---

### 31. The castbar dump with no LibKa0s, after the `_G.print` arm went

**Smoke, session 3. NOT YET RUN — no WoW client was available when `M4-20` landed.** Folded into
session 3 because that is this repository's outstanding seam run, and the setup it needs — the
renamed `libs/LibKa0s` folder — is already section 25's.

`M4-20` deleted `modules/Castbar_Debug.lua`'s `local emit = NS.Util and NS.Util.print or _G.print`
in favor of `local emit = NS.Util.print`. The deleted arm was unreachable: `core/CoreSetup.lua`
defines `Util.print` on the library-absent path at `:115` and returns, and on the library-present
path at `:187`, so there is no load in which `NS.Util.print` is nil. But the guard and the fallback
went together, and what used to degrade into an untagged global `print` now raises. That is the
intended trade — an untagged dump pasted into a bug report is worse than a visible error — and it is
the only behavior this deletion can change.

Both halves are pinned headlessly and neither pins the join. `tests/test_coresetup.lua`'s "the
degraded printer is still secret-safe and still says `<secret>`" proves `Util.print` exists with no
library; the 18 cases in `tests/test_castbar_debug.lua` drive the dump line by line **with** one.
Nothing headless runs the dump on a library-less load, because `tests/test_castbar_debug.lua`'s
helper loads `T.load(true, …)` throughout. This step is that composition and nothing else.

**Setup.** Section 25's — rename `Interface/AddOns/KickCD/libs/LibKa0s` to `libs/LibKa0s_off`,
`/reload`. Run this while you are already in there for 25 rather than arranging it twice.

**Checks.**
- Target anything and run `/kcd debug castbar`. It prints the dump. **A Lua error naming
  `Castbar_Debug.lua` and a nil `emit` is the finding** — it would mean `Util.print` is not on the
  namespace by the time a slash command runs on the degraded path, which no headless load reproduces.
- **Every line carries the `[KCD]` tag.** The degraded printer prefixes with `NS.PREFIX` the same way
  the library's does; a run of untagged lines means something else is doing the printing.
- The one-off missing-library notice appears before the dump, not once per dump line — the same
  `announced` latch section 25 checks, seen through a command that prints ~20 lines at once.
- Rename the folder back and `/reload` before you finish.

---

### 32. Two cast bars driven by one cached handler each

**Smoke, session 3. NOT YET RUN — no WoW client was available when `M4-22` landed.** Folded into
session 3 because that is this repository's outstanding run, and it needs no setup of its own.

`M4-22` stopped `Castbar:Start` from minting `function() onUpdate(inst) end` on every cast start.
`EnsureFrame` builds `inst.onUpdateScript` once per unit instead, and Start installs that. Section
7a already watches one bar fill and snap off, and it would have caught a handler that was never
installed. What it cannot see is the failure this change actually risks, which is a handler that is
installed but bound to the **wrong instance** — because 7a drives one unit.

Headless proof exists for the binding (`tests/test_castbar_frame.lua` asserts target and focus get
distinct handler objects) and for the allocation (`tests/perf.lua`'s `castStart` scenario, 304.0 ->
208.0 bytes per start/stop pair). Neither runs a frame. `SetScript` under the mock is a table write
and `GetScript` reads it back; nothing headless ever calls the handler the way the client does,
sixty times a second, against two live casts at once. This step is that and nothing else.

**Setup.** `/kcd set units.target.castbar.enabled true` and the same for `units.focus.castbar`.
`/kcd lock`. `/kcd set units.target.visibility always`. Find two hostile casters — a pull with two
casting mobs is the easiest arrangement.

**Steps.**
- Target one caster and focus the other, both mid-cast, and watch both bars at once.
- Let each finish and start a second cast without retargeting.
- Swap target and focus and repeat.

**Pass.**
- **Both bars animate simultaneously and independently.** One bar frozen while the other runs, or
  both bars showing the same fill, is the finding — that is a shared or mis-bound handler, and it is
  exactly what a single file-scope handler would produce.
- The second cast on the same unit animates like the first. A bar that fills on the first cast of a
  session and is static afterwards means the handler is being torn down and not re-installed.
- Spell name and remaining time keep tracking on both bars, and neither shows the other's spell.
- No Lua error naming `Castbar.lua` and a nil `onUpdateScript` — that would mean Start ran on an
  instance `EnsureFrame` had not reached, which no headless load reproduces.

---
## When to run which subset

- **The Border dropdown, or anything under `settings/OptionsSetup.lua`'s live wiring:** 18 **and 29**. 18 alone cannot see the defect 29 is for.
- **LibKa0s re-vendor, or any seam-file edit:** 25, 26, **27**, **28** and **31**, plus 11, 15 and 24 (the panel and console are what the library actually draws — and 24 is where the shared Ka0s window edge is checked, which a re-vendor can change with no addon file touched, as v1.3.0 did).
- **Pre-commit (hot path edits):** 1, 2, 8, 16. Anything touching `Cooldowns.lua`, `IconGrid.lua` / `IconGrid_Layout.lua` / `IconGrid_Render.lua`, `Castbar.lua` / `Castbar_Skin.lua`, or the secret-value gates needs the secret-value pass. Anything touching the cast bar's `OnUpdate` install or teardown — `EnsureFrame`, `Start`, `Stop` — also needs **32**, which is the only step that drives two units at once.
- **Settings / schema edits:** 11, 17 plus the panel under change. Any new schema row also exercises 12 (its panel's reset path).
- **Spell-list / Database edits:** 9, 10, 13. DB shape edits (`DEFAULT_PROFILE`, migrations) also need 21 (and 23 if the edit touches `units.<unit>.label`).
- **Target/focus dual-tracking edits:** 20 (plus 6/7 per-unit if touching layout/cast-bar internals shared by both instance managers). Anything touching per-unit **derived** state — the icon curves, the cast bar's structure signature — needs **20d** specifically: it is the only surface that catches a unit inheriting another unit's resolved appearance.
- **Text label edits:** 22 (plus 23 if the change touches `label.style`'s shape or defaults).
- **`NS.Util.print` call-site edits, or anything under `core/CoreSetup.lua`'s printer:** **31**, then 15. 31 is the only step that runs a call site on the library-less load.
- **Debug console edits:** 15, 24, 26 (the console window, its subcommands, the scrollbar + line counter, and the title-bar art).
- **Perf descriptor / perf panel edits (`core/PerfSetup.lua`):** **30**, then 26. 30 is the only place the panel's close control is checked against what is actually drawn; 26 is where it is compared with the console's.
- **Media-seam edits** (`core/MediaSetup.lua`, `core/Constants.lua`'s `FONT_MONO`, the `NS.MakeCloseButton` wrapper, the DebugLog descriptor): **26**, then 24. Nothing here is headless-testable past the argument — the tests pin what is PASSED, and 26 is the only place what is DRAWN is checked.
- **Pre-release / TOC bump:** the entire suite. The 26 surfaces above are designed to span every system the addon owns; running them in order takes ~30–40 minutes and gives release-grade confidence.

If a smoke test fails, capture the offending line from BugSack / the Lua error frame plus the exact slash command sequence that produced it and file an issue at the tracker referenced in [README.md](../README.md#issues-and-feature-requests).
