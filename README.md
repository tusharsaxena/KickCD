# Ka0s KickCD

![version](https://img.shields.io/badge/version-0.1.0--alpha-blue)
![wow](https://img.shields.io/badge/WoW-Midnight%2012.0.5-orange)
![license](https://img.shields.io/badge/license-MIT-green)

KickCD is a lightweight, single-folder WoW addon that helps the player make informed interrupt decisions in real time. It pairs two pieces of UI:

- A movable, persistently-visible **icon grid** of the player's interrupt + cast-stopping CC abilities, with cooldown swipes and a clear ready / not-ready state. Defaults are sensible per class and spec; the secondary block can be anchored to any of 13 points on the primary icon (the four sides × center / left / right alignments, plus a stack-on-top CENTER anchor) and filled in any of 8 grow directions.
- An independently-anchored **target cast bar** that mirrors the current target's cast or channel — spell icon, name, and remaining time. Bar fill color, background, border style, and font are configurable per interruptibility state (interruptible vs. uninterruptible). The bar can free-float, anchor to the icon grid's primary icon, and auto-size to the grid's actual visible footprint.

Both panels share a single addon-wide visibility mode (always / in combat / target casting / target casting interruptible) and a single drag lock, and both correctly handle WoW 12.0's "secret value" protection on protected-interrupt cooldowns and `UnitCastingInfo` / `UnitChannelInfo` returns.

Everything is configurable through the standard Blizzard Settings panel and through the `/kcd` slash command (every panel control has a CLI peer via `/kcd get` / `/kcd set`).

## Usage

### Slash commands

- `/kickcd` or `/kcd` — print the help index.
- `/kcd config` — open the settings panel (refuses during combat, as Blizzard's category-switch is protected). Also routed by `/kcd options`.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — share one drag lock with both the icon grid and the cast bar.
- `/kcd list` — dump every settings option grouped by panel, with current values.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every schema-driven option (e.g. `/kcd set icons.primarySize 56`, `/kcd set castbar.interruptible.barColor 0.2 0.8 0.2 1`).
- `/kcd reset <general|icons|castbar|spells>` — reset one panel to defaults.
- `/kcd resetall` — reset every schema-driven panel and rebuild every spec's default spell list. Mirrors the General → "Reset all settings" popup; no CLI confirmation prompt.
- `/kcd resetposition` — restore the icon grid to its default screen position (CENTER, y = -180).
- `/kcd spells` — per-class+spec spell-list editor: `list / add / remove / enable / disable / category / reset`. CLASS+SPEC default to the player's current spec when omitted.
- `/kcd debug` — diagnostic subcommands:
  - `spells` — dump the watched cooldown list.
  - `castbar` — print current target cast state plus configured / live per-state colors.
  - `interrupt` — dump `UnitCastingInfo` / `UnitChannelInfo` positions with their type and `issecretvalue()` flag, plus what the visibility logic decided (used to diagnose 12.0 secret-value handling).
  - `log` — toggle internal-message logging (mirrors General → Debug).

### Settings panel

Five subcategories under **Ka0s KickCD**:

- **General** — master enable, addon-wide visibility mode, lock, master scale / alpha, debug log. "Reset position" and "Reset all settings" buttons sit under Master controls.
- **Icons** — sizing, layout (anchor + grow + rows × cols), visual states (alpha / tint / GCD swipe suppression), border, annotations (cooldown text font / size / flags, charges, hover tooltip), per-slot ready glow (independent trigger and style for primary vs. secondary icons, backed by LibCustomGlow).
- **Cast bar** — enable, position (free-float or anchored to the primary icon at one of 13 anchor points × 13 cast-bar points), orientation / growth direction, auto-size to icon grid, sizing & layout, font, per-element text anchors and offsets (spell name, cast time), per-state appearance (interruptible vs. uninterruptible: bar texture / color / background / border style / border color / border thickness / spell-name color).
- **Spells** — per-class+spec spell-list editor. Class/spec dropdown shows class+spec icons and class-colored entries; rows show known/unknown glyph + spell icon + name + category + enable/move/remove controls. Header "Defaults" button resets the currently-selected spec only. The grid only ever renders entries the player can actually cast (talent choice nodes, pet spells while the pet is summoned, etc.).
- **Profiles** — AceDBOptions UI rendered into the unified panel chrome.

Use `/kcd unlock` to drag the icon grid (and the cast bar, if it's in FREE anchor mode) into position, then `/kcd lock` to fix them.

## Critical settings

A few options change the addon's behavior more than any others. They're documented in detail here so the panel tooltips don't have to.

### Visibility modes (General → Master controls → General visibility)

A single visibility selector governs **both** the icon grid and the cast bar. The master enable toggle still wins — disabled hides everything regardless of mode.

| Value (`/kcd set visibility …`)    | When the UI shows                                                                                        |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `always`                           | Always (default).                                                                                        |
| `in_combat`                        | Only while `InCombatLockdown()` is true.                                                                 |
| `target_casting`                   | Only while the current target has a cast or channel in progress (`UnitCastingInfo` / `UnitChannelInfo`). |
| `target_casting_interruptible`     | Only while a hostile target is casting **and** the cast is interruptible. Uninterruptible casts hide.    |

`target_casting_interruptible` is a two-step gate: a hostile-target gate in Lua picks whether the frames participate at all, then per-frame alpha is driven C-side from the cast's secret `notInterruptible` flag via `C_CurveUtil.EvaluateColorValueFromBoolean`. This is required because WoW 12.0 marks `notInterruptible` as a "secret value" — addons can't compare it in Lua without erroring. If the icon grid or cast bar unexpectedly shows during an uninterruptible cast, run `/kcd debug interrupt` to dump what the gate is seeing.

The same 4 values drive the per-icon glow trigger (Icons → Ready glow → Trigger), independently for primary and secondary icons.

### Cast bar anchoring (Cast bar → Position)

Two modes:

- **Free (drag to move)** — the cast bar is a free-floating frame. Unlock with `/kcd unlock`, drag, and lock again with `/kcd lock`. The position is saved per-profile in `anchors.castbar`.
- **Anchored to primary icon** — the cast bar attaches to the icon grid's primary icon. Three settings combine to position it:
  - **Anchor on primary icon** — one of 13 points on the primary icon (`TOP_LEFT`, `TOP_MIDDLE`, `TOP_RIGHT`, `BOTTOM_LEFT`, `BOTTOM_MIDDLE`, `BOTTOM_RIGHT`, `LEFT_TOP`, `LEFT_MIDDLE`, `LEFT_BOTTOM`, `RIGHT_TOP`, `RIGHT_MIDDLE`, `RIGHT_BOTTOM`, `CENTER`).
  - **Anchor on cast bar** — the matching point on the cast bar itself (same 13-option set).
  - **X / Y offset** — fine-tune in pixels (positive Y = up, screen convention internally converted).

  In this mode the cast bar follows the icon grid for free — drag the grid and the bar comes with it. The bar itself is not draggable.

Defaults: `Anchor on primary icon = TOP_MIDDLE`, `Anchor on cast bar = BOTTOM_MIDDLE`, `Y offset = 8`. That places the bar 8 px above the primary icon, centered.

### Cast bar orientation and growth (Cast bar → Orientation)

- **Orientation** — `HORIZONTAL` (default) or `VERTICAL`. Vertical rotates the whole frame 90°; the spark, fill, name, time, and icon layouts all follow.
- **Growth direction** — pairs with orientation. Horizontal accepts `RIGHT` / `LEFT`; vertical accepts `UP` / `DOWN`. Switching orientation auto-resets growth to the canonical default for the new axis (`RIGHT` / `UP`) so an inconsistent pair (e.g. horizontal + UP) can't linger after a flip.
- **Auto-size to icon grid** — when on, the bar's *long* axis matches the icon grid's actual rendered size in that direction:
  - Horizontal bar → bar width = icon grid width.
  - Vertical bar → bar height = icon grid height.

  Auto-size tracks the grid's *visible* footprint, not the configured rows × cols, so adding/removing/disabling icons or resizing the grid resizes the bar in place. The orthogonal dimension stays at the configured Width / Height. Auto-size works in both Free and Anchored modes — it only governs size, not position.

### Icon grid anchoring (Icons → Layout)

`Primary anchor` places the secondary block on the primary icon. The first word picks the side (`TOP` / `BOTTOM` / `LEFT` / `RIGHT`); the second picks where on that side (`MIDDLE` plus the perpendicular axis alignments). A 13th value, plain `CENTER`, stacks the secondary block on top of the primary at the grid's center.

`Grow direction` picks how secondary icons fill the block (8 combinations of `right`/`left`/`down`/`up`). Anchor places the block; grow arranges icons within it. They are independent — you can anchor `RIGHT_MIDDLE` and grow `down_right`, for example.

`Rows × Cols` is the secondary block's capacity; pair it with grow to get e.g. a 1 × 6 horizontal strip or a 2 × 3 grid. If more spells are enabled than the block holds, the extras are dropped silently — the addon logs a warning if Debug is on.

## FAQ

**Does this replace Blizzard's default cast bars?**

No. The cast bar is a brand-new frame; Blizzard's player and target cast bars are untouched. Disable Blizzard's target cast bar in *Edit Mode* if you don't want both visible.

**How do I move the icon grid / cast bar?**

`/kcd unlock`, drag, `/kcd lock`. The icon grid is always draggable when unlocked. The cast bar is draggable only in Free anchor mode — in Anchored mode it follows the primary icon and isn't a drop target. `/kcd resetposition` snaps the icon grid back to its default screen position (CENTER, y = -180). The cast bar's free-mode position is saved per-profile.

**Where do my spell defaults come from? Why doesn't every class spell I expect show up?**

Defaults are per-class+spec and only seeded *once*, on first profile creation, from `defaults/Spells.lua`. The grid then renders only the spells the player can actually cast — wrong-talent choice-node spells, unlearned spells, and pet abilities while no pet is summoned are filtered out at render time, not at list time. To restore defaults later, `/kcd reset spells` (every spec) or `/kcd spells reset [CLASS SPEC]` (one spec).

**Can I add my own spells?**

Yes — Settings → Spells, or `/kcd spells add SPELL_ID category`. Only spells already tracked by the Cooldown Manager validate; the editor shows the relevant error if not.

**Does the addon track items / trinkets?**

Not yet. Spells only.

**Why does the settings panel refuse to open during a pull?**

Blizzard's category-switching is protected, so opening *any* settings subcategory during combat would taint the panel. `/kcd config` errors out cleanly until combat ends.

**Are there profiles? Per-character configs?**

Yes — full AceDB profiles under Settings → Profiles. Every character on the account starts on the shared **Default** profile, so changes made on one character carry over to every other one out of the box. Opt into per-character / per-class / per-realm scope from the Profiles panel if you want a character (or group of characters) to diverge.

**What does "secret value" mean and why does it matter?**

WoW 12.0 marks certain protected returns (`UnitCastingInfo` / `UnitChannelInfo`'s `notInterruptible`, `C_Spell.GetSpellCooldown` fields, …) as opaque tokens that error if an addon tries to compare them in Lua. KickCD never compares them — interruptibility is fed into `C_CurveUtil.EvaluateColorValueFromBoolean` / `Frame:SetAlphaFromBoolean` so the comparison happens C-side. Run `/kcd debug interrupt` to see what the gate decided for the current target.

**Does the bar fill direction affect channels?**

Channels drain in the same direction the equivalent cast would fill — a HORIZONTAL + RIGHT bar drains right-to-left during a channel.

## Troubleshooting

**The icon grid never appears.**

Check, in order:
1. Master enable: `/kcd get enabled` → must be `true`.
2. Visibility mode: `/kcd get visibility`. If it's `in_combat` you have to be in combat; if `target_casting*` you need a target that's actively casting.
3. The active spec has at least one **enabled** spell **the player knows**. `/kcd debug spells` lists the watched cooldowns.

**The icon grid won't drag.**

It's locked. `/kcd unlock`, drag, `/kcd lock`. If `/kcd unlock` doesn't visibly flip the lock state, run `/kcd toggle`.

**The cast bar shows on uninterruptible casts even though I picked "interruptible only".**

Run `/kcd debug interrupt` while the offending unit is casting. The output prints both `UnitCastingInfo` / `UnitChannelInfo` positions and their `issecretvalue()` flag, plus what the visibility logic decided. A bar that *visually fades* to alpha 0 during an uninterruptible cast is the gate working as intended (the frame still exists; only its alpha changes, because addons can't read the secret flag in Lua).

**Cooldown text is stuck at `0.0` for a few seconds after a spell finishes.**

Should not happen since the v0.1.0-alpha fix; if you see it, capture `/kcd debug spells` output during the stuck window and report it. Make sure `Icons → Annotations → Cooldown text` is enabled.

**Glow on secondary icons looks janky / restarts every ~0.1s.**

Should not happen since the v0.1.0-alpha fix. If you see it, confirm the trigger is set to one of the *target casting* options and capture the cast bar / icon configuration plus a video.

**Settings panel won't open mid-pull.**

This is intentional. Blizzard's settings category-switch is protected in combat; KickCD refuses rather than silently tainting the panel. `/kcd config` works the moment combat ends.

**Cast bar doesn't auto-size to the grid.**

Auto-size honors the grid's *visible* size on each `KickCD_GRID_LAYOUT`. If the bar didn't update, toggle Auto-size off and on, or run `/kcd resetposition` to force a layout pass. Auto-size only governs the long axis; the orthogonal dimension stays at the configured Width / Height.

**I want a clean slate.**

- One panel only: `/kcd reset general` / `/kcd reset icons` / `/kcd reset castbar` / `/kcd reset spells`.
- Everything except profiles: `/kcd resetall` (or General → Reset all settings).
- Just the icon grid's screen position: `/kcd resetposition`.
- A specific spec's spell list: `/kcd spells reset CLASS SPEC` or the Spells panel's per-spec **Defaults** button.

## Issues and feature requests

All bugs, feature requests, and outstanding work are tracked at <https://github.com/tusharsaxena/kickcd/issues>. Please file new reports there rather than as comments — the issue tracker is the single source of truth for the project's backlog.

## Version History

**0.1.0**

*   Alpha release
