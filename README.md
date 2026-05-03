# Ka0s KickCD

![wow](https://img.shields.io/badge/WoW-Midnight_12.0.5-orange)
![CurseForge Version](https://img.shields.io/curseforge/v/1530802)
![license](https://img.shields.io/badge/license-MIT-green)

![alt text](https://media.forgecdn.net/attachments/1659/608/kickcd-logo-jpg.jpg)

KickCD is a lightweight, single-folder WoW addon that helps the player make informed interrupt decisions in real time. It pairs two pieces of UI:

*   A movable, persistently-visible **icon grid** of the player's interrupt + cast-stopping CC abilities, with cooldown swipes and a clear ready / not-ready state. Sensible defaults per class and spec; the secondary block can be anchored to any of 13 points on the primary icon and filled in any of 8 grow directions.
*   An independently-anchored **target cast bar** that mirrors the current target's cast or channel — spell icon, name, and remaining time. Bar fill color, background, border style, and font are configurable per interruptibility state (interruptible vs. uninterruptible). The bar can free-float, anchor to the icon grid's primary icon, and auto-size to the grid's actual visible footprint.

Both panels share a single addon-wide visibility mode and a single drag lock. The addon is fully compatible with WoW 12.0's "secret value" protection on protected-interrupt cooldowns and casting info.

Everything is configurable through the standard Blizzard Settings panel and through the `/kcd` slash command (every panel control has a CLI peer via `/kcd get` / `/kcd set`).

## Screenshots

**_Addon in action_**

![alt text](https://media.forgecdn.net/attachments/1659/619/kickcd-video-04-compressed-gif.gif)

**_Zoomed in view of the icon grid and cast bar_**

![alt text](https://media.forgecdn.net/attachments/1659/603/kickcd-image-01-addon-png.png)

**_General settings panel_**

![alt text](https://media.forgecdn.net/attachments/1659/604/kickcd-image-02-general-png.png)

**_Icons setting panel_**

![alt text](https://media.forgecdn.net/attachments/1659/605/kickcd-image-03-icons-png.png)

**_Castbar settings panel_**

![alt text](https://media.forgecdn.net/attachments/1659/606/kickcd-image-04-castbar-png.png)

**_Spells settings panel_**

![alt text](https://media.forgecdn.net/attachments/1659/607/kickcd-image-05-spells-png.png)

## Usage

### Slash commands

`/kcd` is the short form; `/kickcd` is a long-form alias for the same handler. Every chat line is prefixed with a cyan `[KCD]` banner.

| Command | Purpose |
| --- | --- |
| `/kcd` | Print the help index. |
| `/kcd config` | Open the settings panel. Refuses during combat (Blizzard's category-switch is protected). Aliased as `/kcd options`. |
| `/kcd lock` / `unlock` / `toggle` | Set / clear / flip the shared drag lock for the icon grid and the cast bar. |
| `/kcd list` | Dump every settings option grouped by panel, with current values. |
| `/kcd get <path>` | Print one setting's current value (e.g. `/kcd get icons.primarySize`). |
| `/kcd set <path> <value>` | Type-aware write. Numbers clamp to range, dropdowns validate against the option list, colors take `r g b [a]` (e.g. `/kcd set castbar.interruptible.barColor 0.2 0.8 0.2 1`). |
| `/kcd reset <general\|icons\|castbar\|spells>` | Reset one panel to defaults. `spells` rebuilds every spec's list. |
| `/kcd resetall` | Reset every schema-driven panel **and** every spec's spell list. Mirrors the General → "Reset all settings" popup; no CLI confirmation. |
| `/kcd resetposition` | Restore the icon grid to its default screen position. |
| `/kcd spells <subcmd>` | Per-class+spec spell-list editor: `list / add / remove / enable / disable / category / reset`. CLASS+SPEC default to the player's current spec when omitted. |
| `/kcd debug spells` | Dump the watched cooldown list. |
| `/kcd debug castbar` | Print current target cast state plus configured / live per-state colors. |
| `/kcd debug interrupt` | Dump `UnitCastingInfo` / `UnitChannelInfo` positions plus what the visibility logic decided. Use to diagnose 12.0 secret-value handling. |
| `/kcd debug log` | Toggle internal-message logging (mirrors General → Debug). |

### Settings panel

Five subcategories under **Ka0s KickCD**:

| Tab | Covers |
| --- | --- |
| **General** | Master enable, addon-wide visibility mode, lock, master scale / alpha, debug log. "Reset position" and "Reset all settings" buttons sit under Master controls. |
| **Icons** | Sizing, layout (anchor + grow + rows × cols), visual states (alpha / tint / GCD swipe suppression), border, annotations (cooldown text font / size / flags, charges, hover tooltip), per-slot ready glow (independent trigger and style for primary vs. secondary icons). |
| **Cast bar** | Enable, position (free-float or anchored to the primary icon), orientation / growth direction, auto-size to icon grid, sizing, font, per-element text anchors and offsets, per-state appearance for interruptible vs. uninterruptible casts. |
| **Spells** | Per-class+spec spell-list editor. Class/spec dropdown shows class+spec icons and class-colored entries; rows show known/unknown glyph + spell icon + name + category + enable/move/remove. Header "Defaults" button resets the currently-selected spec only. The grid only renders entries the player can actually cast (talent choice nodes, pet spells while the pet is summoned, etc.). |
| **Profiles** | Standard AceDB profile management (default / per-character / per-class / per-realm). |

Use `/kcd unlock` to drag the icon grid (and the cast bar, if it's in FREE anchor mode) into position, then `/kcd lock` to fix them.

## Critical settings

A few options change the addon's behavior more than any others.

### Visibility modes (General → Master controls → General visibility)

A single visibility selector governs **both** the icon grid and the cast bar. The master enable toggle still wins — disabled hides everything regardless of mode.

| Value (`/kcd set visibility …`) | When the UI shows |
| --- | --- |
| `always` | Always. |
| `in_combat` | Only while combat is active. |
| `target_casting` | Only while the current target has a cast or channel in progress. |
| `target_casting_interruptible` | Only while a hostile target is casting **and** the cast is interruptible. Uninterruptible casts hide. (Default.) |

The per-icon glow trigger (Icons → Ready glow → Trigger) reuses three of these values — `always`, `target_casting`, `target_casting_interruptible` — plus a `never` option to disable the glow entirely. (`in_combat` is intentionally absent; the glow is a per-cast cue, not a combat-state indicator.) Primary and secondary icons each carry their own trigger.

### Cast bar anchoring (Cast bar → Position)

Two modes:

*   **Free (drag to move)** — the cast bar is a free-floating frame. Unlock with `/kcd unlock`, drag, lock again with `/kcd lock`. Position is saved per-profile.
*   **Anchored to primary icon** — the cast bar attaches to the icon grid's primary icon via three settings: an attach point on the primary icon (one of 13), the matching point on the cast bar (same 13-option set), and an X / Y offset. The cast bar follows the grid for free; the bar itself is not draggable.

Defaults: `Anchor mode = PRIMARY`, attach point `TOP_LEFT` ↔ `BOTTOM_LEFT`, offset `(0, 1)` — bar sits 1 px above the primary icon, left-aligned.

### Cast bar orientation, growth, and auto-size (Cast bar → Orientation)

*   **Orientation** — `HORIZONTAL` (default) or `VERTICAL`. Vertical rotates the whole frame 90°; spark, fill, name, time, and icon layouts all follow.
*   **Growth direction** — pairs with orientation. Horizontal accepts `RIGHT` / `LEFT`; vertical accepts `UP` / `DOWN`. Switching orientation auto-resets growth to the canonical default for the new axis.
*   **Auto-size to icon grid** — when on, the bar's _long_ axis matches the icon grid's actual rendered size in that direction (horizontal → bar width, vertical → bar height). Tracks the grid's _visible_ footprint, so adding/removing/disabling icons resizes the bar in place. The orthogonal dimension stays as configured.

### Icon grid anchoring (Icons → Layout)

`Primary anchor` places the secondary block on the primary icon (12 `<SIDE>_<ALIGN>` tokens + a 13th `CENTER` that stacks the block on the primary). `Grow direction` picks the fill order inside the block (8 combinations of `right` / `left` / `down` / `up`). `Rows × Cols` is the block's capacity. Anchor and grow are independent — any anchor pairs with any grow direction.

If more spells are enabled than the block holds, the extras are dropped — the addon prints a one-time chat warning per (class, spec, capacity) tuple so you know to bump rows × cols or remove spells.

## FAQ

| Question | Answer |
| --- | --- |
| Does this replace Blizzard's default cast bars? | No. The cast bar is a brand-new frame; Blizzard's player and target cast bars are untouched. Disable Blizzard's target cast bar in _Edit Mode_ if you don't want both visible. |
| How do I move the icon grid / cast bar? | `/kcd unlock`, drag, `/kcd lock`. The icon grid is always draggable when unlocked. The cast bar is draggable only in Free anchor mode — in Anchored mode it follows the primary icon. `/kcd resetposition` snaps the grid back to its default screen position. |
| Where do my spell defaults come from? Why doesn't every class spell I expect show up? | Defaults are per-class+spec and only seeded _once_, on first profile creation, from `defaults/Spells.lua`. The grid then renders only the spells the player can actually cast — wrong-talent choice-node spells, unlearned spells, and pet abilities while no pet is summoned are filtered out at render time. To restore defaults later, `/kcd reset spells` (every spec) or `/kcd spells reset [CLASS SPEC]` (one spec). |
| Can I add my own spells? | Yes — Settings → Spells, or `/kcd spells add SPELL_ID category`. When editing your own active spec, only spells already tracked by the Cooldown Manager validate; the editor shows an error if not. |
| Does the addon track items / trinkets? | Not yet. Spells only. |
| Why does the settings panel refuse to open during a pull? | Blizzard's category-switching is protected in combat, so opening _any_ settings subcategory mid-fight would taint the panel. `/kcd config` errors out cleanly until combat ends. |
| Are there profiles? Per-character configs? | Yes — full AceDB profiles under Settings → Profiles. Every character on the account starts on the shared **Default** profile; opt into per-character / per-class / per-realm scope from the Profiles panel if you want a character (or group of characters) to diverge. |
| What does "secret value" mean and why does it matter? | WoW 12.0 marks certain protected-interrupt cooldown timings and `notInterruptible` flags as opaque tokens that error if an addon tries to compare them in Lua. KickCD never compares them; the visibility / glow / interruptibility decisions are routed through C-side Blizzard methods that accept the protected values directly. Run `/kcd debug interrupt` to see what the gate decided for the current target. |
| Does the bar fill direction affect channels? | Channels drain in the same direction the equivalent cast would fill — a HORIZONTAL + RIGHT bar drains right-to-left during a channel. |

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The icon grid never appears. | (1) Master enable: `/kcd get enabled` must be `true`. (2) Visibility mode: `/kcd get visibility` — `in_combat` requires combat, `target_casting*` requires an actively-casting target. (3) The active spec has at least one **enabled** spell **the player knows**. `/kcd debug spells` lists the watched cooldowns. |
| The icon grid won't drag. | It's locked. `/kcd unlock`, drag, `/kcd lock`. If `/kcd unlock` doesn't visibly flip the lock state, run `/kcd toggle`. |
| The cast bar shows on uninterruptible casts even though I picked "interruptible only". | A bar that _visually fades_ to alpha 0 during an uninterruptible cast is the gate working as intended (the frame still exists; only its alpha changes). For other cases, run `/kcd debug interrupt` while the offending unit is casting and report the output. |
| Cooldown text is stuck at `0.0` for a few seconds after a spell finishes. | Should not happen since the 1.0.0 fix. If you see it, capture `/kcd debug spells` output during the stuck window and report it. Make sure `Icons → Annotations → Show cooldown text` is enabled. |
| Glow on secondary icons looks janky / restarts every ~0.1s. | Should not happen since the 1.0.0 fix. If you see it, confirm the trigger is set to one of the _target casting_ options and capture the cast bar / icon configuration plus a video. |
| Settings panel won't open mid-pull. | Intentional — Blizzard's settings category-switch is protected in combat; KickCD refuses rather than silently tainting the panel. `/kcd config` works the moment combat ends. |
| Cast bar doesn't auto-size to the grid. | Toggle Auto-size off and on, or run `/kcd resetposition` to force a layout pass. Auto-size only governs the long axis; the orthogonal dimension stays at the configured Width / Height. |
| I want a clean slate. | One panel: `/kcd reset general` / `icons` / `castbar` / `spells`. Everything except profiles: `/kcd resetall` (or General → Reset all settings). Just the icon grid's screen position: `/kcd resetposition`. A specific spec's spell list: `/kcd spells reset CLASS SPEC` or the Spells panel's per-spec **Defaults** button. |

## Issues and feature requests

All bugs, feature requests, and outstanding work are tracked at [https://github.com/tusharsaxena/kickcd/issues](https://github.com/tusharsaxena/kickcd/issues). Please file new reports there rather than as comments — the issue tracker is the single source of truth for the project's backlog.

## Testing

There is no automated test harness — verification is manual, in-game. The end-to-end smoke-test suite covering install, visibility modes, lock/drag, cast bar, spec/talent/pet rebuilds, profiles, and 12.0 secret-value safety lives at [docs/smoke-tests.md](docs/smoke-tests.md). Run it before tagging a release or after refreshing libs / bumping `## Interface:`.

## Version History

| Version | Changes |
| --- | --- |
| 1.1.0 | Vendored LSM dropdown widgets with texture/font previews; first-run defaults<br>Added KickCD_COMBAT_STATE bus message; consolidated PLAYER_REGEN_* in core/State.lua<br>Filtered UNIT_SPELLCAST_* events to target unit via private dispatch frames<br>Settings panel breadcrumb separator now an inline atlas chevron (font-agnostic)<br>OpenSettings combat-lockdown gate now applies to every entry point<br>Fixed dropdown selection; clarified `/kcd reset spells` description<br>Removed dead Settings exports/shims, `_maxC` record field, unused Util exports<br>Internals: code-review M1–M5 cleanup; smoke-test suite; doc drift fixes |
| 1.0.1 | Version bump to 1.0.1-release to trigger build. |
| 1.0.0 | Initial release … yay! |
