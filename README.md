# Ka0s KickCD

![WoW](https://img.shields.io/badge/WoW-Midnight_12.0.7-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1530802)
![License](https://img.shields.io/badge/License-MIT-orange)
[![Standard](https://img.shields.io/badge/Ka0s-WoW%20Addon%20Standard-yellow)](https://github.com/tusharsaxena/WowAddonStandards)
![Tests](https://img.shields.io/badge/Tests-81%2F81_passing-green)

![alt text](https://media.forgecdn.net/attachments/1659/608/kickcd-logo-jpg.jpg)

KickCD helps you decide when to interrupt. It shows two things on screen:

*   An **icon grid** of your interrupts and cast-stopping crowd control, each with a cooldown timer and a clear ready / not-ready look. It comes set up for your class and spec out of the box.
*   A **target cast bar** that shows what your current target is casting — the spell's icon, its name, and how much time is left — and colors itself by whether that cast can be interrupted.

You can move both, resize them, and lock them in place. They appear and disappear together based on a single visibility setting you choose.

Set everything up in the Blizzard settings panel (under **Ka0s KickCD**) or with the `/kcd` chat command.

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

Type `/kcd` (or the longer `/kickcd`) to control the addon from chat. Replies are tagged with a cyan `[KCD]` label.

| Command | What it does |
| --- | --- |
| `/kcd` | Show the list of commands. |
| `/kcd version` | Show which version you're running. |
| `/kcd config` | Open the settings panel. Won't open during combat. Also `/kcd options`. |
| `/kcd lock` / `unlock` / `toggle` | Lock, unlock, or flip the lock on the icon grid and cast bar so you can drag them. |
| `/kcd list` | List every setting and its current value. |
| `/kcd get <setting>` | Show one setting's value (for example `/kcd get icons.primarySize`). |
| `/kcd set <setting> <value>` | Change a setting. Colors take red/green/blue numbers, e.g. `/kcd set castbar.interruptible.barColor 0.2 0.8 0.2 1`. |
| `/kcd reset <general\|icons\|castbar\|spells>` | Reset one settings tab to its defaults. |
| `/kcd resetall` | Reset every tab, and every spec's spell list, to defaults. |
| `/kcd resetposition` | Put the icon grid back in its default spot on screen. |
| `/kcd spells <subcommand>` | Edit the tracked spells for a class and spec: `list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`. Defaults to your current spec. |
| `/kcd debug spells` | List the cooldowns the addon is watching. |
| `/kcd debug castbar` | Show your target's current cast and the colors in use. |
| `/kcd debug interrupt` | Show what the addon decided about your target's cast. Handy for bug reports. |
| `/kcd debug on\|off\|toggle` | Turn the debug log on or off. It resets when you reload. |
| `/kcd debug window` | Show or hide the on-screen debug window. |

### Settings panel

Five tabs under **Ka0s KickCD**:

| Tab | Covers |
| --- | --- |
| **General** | The master on/off switch, when the UI shows, the drag lock, and overall size and transparency. The "Reset position" and "Reset all settings" buttons live here too. |
| **Icons** | Icon size, grid layout, how ready and not-ready icons look, borders, cooldown text and charges, tooltips, and the ready glow. |
| **Cast bar** | Turn the cast bar on, place it, size it, choose its direction, pick a font, and set separate colors for casts you can and can't interrupt. |
| **Spells** | Choose which spells to track for each class and spec. Only spells you can actually cast right now show up. |
| **Profiles** | Save separate settings per character, class, or realm. |

Use `/kcd unlock` to drag the icon grid (and the cast bar, if it's set to move freely) into position, then `/kcd lock` to fix them.

## How interrupt tracking works

Here's what decides when the UI shows, hides, and lights up.

1.  **The master switch comes first.** If the addon is turned off, nothing shows.
2.  **A single visibility setting decides when the UI appears** — always, only in combat, only while your target is casting, or only while your target is casting something you can interrupt. The icon grid and the cast bar both follow this one setting, so they show, hide, move, and lock together.
3.  **The icon grid tracks your cooldowns.** For your current class and spec, it watches your interrupts and cast-stopping crowd control, runs each icon's cooldown timer, and shows whether the ability is ready.
4.  **The cast bar tracks your target.** It shows the spell your target is casting or channeling and colors itself by whether you can interrupt it, so a glance tells you if the cast is worth a kick.

In the "interruptible only" mode the UI stays hidden while your target casts something you can't interrupt, and appears the moment they cast something you can.

### Key settings

A few settings shape the addon's behavior more than the rest.

#### Visibility (General → Master controls → General visibility)

One setting controls when both the icon grid and the cast bar appear. The master switch always wins: if the addon is off, nothing shows.

| Value | When the UI shows |
| --- | --- |
| `always` | Always. |
| `in_combat` | Only while you're in combat. |
| `target_casting` | Only while your target is casting or channeling. |
| `target_casting_interruptible` | Only while a hostile target is casting something you can interrupt. Casts you can't interrupt stay hidden. (Default.) |

The ready glow has its own copy of this setting (Icons → Ready glow), with the same choices plus a `never` option to turn the glow off. Your primary and secondary icons can use different triggers.

#### Cast bar placement (Cast bar → Position)

Two modes:

*   **Free (drag to move)** — the cast bar floats on its own. Unlock it, drag it where you want, and lock it again. Its position is saved.
*   **Anchored to the primary icon** — the cast bar sticks to the main icon in the grid and moves with it. Pick which points connect and a small offset. In this mode you don't drag the bar itself.

By default the bar sits just above the primary icon, lined up with its left edge.

#### Cast bar direction and auto-size (Cast bar → Orientation)

*   **Orientation** — horizontal (default) or vertical.
*   **Fill direction** — which way the bar fills. Horizontal fills to the right or left; vertical fills up or down.
*   **Auto-size to icon grid** — when on, the bar's length matches the icon grid and follows it, so adding, removing, or disabling icons resizes the bar in place. Its other dimension stays where you set it.

#### Icon grid layout (Icons → Layout)

The **primary anchor** sets where the block of secondary icons sits relative to the main icon. The **grow direction** sets the order they fill in. **Rows × Cols** sets how many fit. Any anchor pairs with any grow direction.

If you enable more spells than the grid can hold, the extras are left off and the addon warns you once in chat so you can make room or trim the list.

## FAQ

| Question | Answer |
| --- | --- |
| Does this replace Blizzard's cast bars? | No. It adds its own cast bar and leaves Blizzard's alone. If you don't want to see both, hide Blizzard's target cast bar in Edit Mode. |
| How do I move the icon grid or cast bar? | `/kcd unlock`, drag, then `/kcd lock`. The icon grid always drags when unlocked. The cast bar drags only when it's set to move freely — when it's anchored, it follows the main icon. `/kcd resetposition` puts the grid back in its default spot. |
| Where do my spell defaults come from, and why isn't every spell there? | Each class and spec comes with a starter list, set up the first time you use that character. The grid then shows only the spells you can cast right now, so spells from talents you didn't pick, spells you haven't learned, and pet abilities without a pet are hidden. To start over, use `/kcd reset spells` (all specs) or `/kcd spells reset` (one spec). |
| Can I add my own spells? | Yes — in Settings → Spells, or with `/kcd spells add`. For the spec you're currently playing, only spells the game already tracks as cooldowns can be added. |
| Does it track items or trinkets? | Not yet — spells only. |
| Why won't the settings panel open in combat? | The game blocks opening settings mid-fight, so `/kcd config` waits until combat ends. |
| Are there per-character settings? | Yes — see Settings → Profiles. Every character starts on a shared default, and you can split off a per-character, per-class, or per-realm profile whenever you like. |
| Does the fill direction change for channels? | Yes. A channel drains the same way the matching cast would fill — a bar that fills to the right during a cast drains to the left during a channel. |

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The icon grid never appears. | Check three things: the addon is on (`/kcd get enabled` is `true`), your visibility setting fits the situation (`/kcd get visibility` — some modes need combat or a casting target), and your spec has at least one enabled spell that you know. `/kcd debug spells` lists what it's watching. |
| The icon grid won't drag. | It's locked. `/kcd unlock`, drag, `/kcd lock`. If unlocking doesn't seem to take, run `/kcd toggle`. |
| The cast bar still shows on casts I can't interrupt, even in "interruptible only" mode. | If the bar fades out on those casts, that's it working as intended — the frame is still there, just invisible. For anything else, run `/kcd debug interrupt` while the target is casting and include the output in a bug report. |
| Cooldown text sticks at `0.0` for a few seconds after a spell finishes. | This shouldn't happen anymore. If it does, capture `/kcd debug spells` during the stuck moment and report it, and make sure cooldown text is on (Icons → Annotations). |
| The glow on secondary icons flickers or restarts constantly. | This shouldn't happen anymore. If it does, make sure the glow trigger is set to one of the "target casting" options, and send a short video with your settings. |
| The settings panel won't open mid-fight. | On purpose — the game blocks it in combat. It opens the moment combat ends. |
| The cast bar won't auto-size to the grid. | Toggle Auto-size off and on, or run `/kcd resetposition` to force a refresh. Auto-size only controls the bar's length; its other dimension stays where you set it. |
| I want a clean slate. | One tab: `/kcd reset general` / `icons` / `castbar` / `spells`. Everything but profiles: `/kcd resetall` (or General → Reset all settings). Just the grid's position: `/kcd resetposition`. One spec's spell list: `/kcd spells reset` or the Spells tab's Defaults button. |

## Issues and feature requests

Found a bug or want a feature? File it at [https://github.com/tusharsaxena/kickcd/issues](https://github.com/tusharsaxena/kickcd/issues). The issue tracker is where all reports and planned work live, so please post there rather than in comments.

## Version History

| Version | Date | Highlights |
| --- | --- | --- |
| 1.2.0 | 2026-07-13 | Added an on-screen debug window with Copy/Clear buttons, controlled by `/kcd debug on\|off\|toggle\|window`. Debug messages now go to that window instead of chat and reset each reload. Replaced `/kcd debug log` with `/kcd debug on\|off\|toggle`. |
| 1.1.0 | 2026-05-03 | Added texture, font, and border dropdowns with live previews. The settings panel's main page now shows the logo and command list, with breadcrumb headers on subpages. All chat output now uses a single cyan `[KCD]` label. |
| 1.0.1 | 2026-05-02 | Rebuild only; nothing changed for players. |
| 1.0.0 | 2026-05-02 | Initial release. Interrupt and CC cooldown icon grid with flexible layout, plus a target cast bar that colors itself by interruptibility and can auto-size to the grid. Five-tab settings panel with full `/kcd` command coverage and per-tab Defaults. Visibility modes (always / in combat / target casting / interruptible only) with a per-icon ready glow. Per-spec spell lists with hover tooltips and known/unknown markers. Saved profiles. |
</content>
</invoke>
