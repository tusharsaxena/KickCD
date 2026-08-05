# Ka0s KickCD

![WoW](https://img.shields.io/badge/WoW-Midnight_12.0.7-purple)
![CurseForge Version](https://img.shields.io/curseforge/v/1530802)
![License](https://img.shields.io/badge/License-MIT-orange)
[![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)](https://github.com/tusharsaxena/WowAddonStandards)
![Tests](https://img.shields.io/badge/Tests-738%2F738_passing-green)

![Logo](https://media.forgecdn.net/attachments/1659/608/kickcd-logo-jpg.jpg)

KickCD helps you decide when to interrupt. It tracks two enemy units — your **target** and your **focus** — and puts two things on screen for each one:

*   An **icon grid** of your interrupts and cast-stopping crowd control, each with a cooldown timer and a clear ready / not-ready look. It comes set up for your class and spec out of the box.
*   A **cast bar** that shows what that unit is casting — the spell's icon, its name, and how much time is left — and colors itself by whether the cast can be interrupted.

Focus tracking is on out of the box and mirrors your target's look, so you get a matching second set. You can move each grid and cast bar, resize them, and lock everything with a single lock; it all appears and disappears together based on one visibility setting you choose. Don't want the focus set? Turn it off. Want it to look different from your target's? Unlink it and style it on its own.

Set everything up in the Blizzard settings panel (under **Ka0s KickCD**) or with the `/kcd` chat command.

## What's new in 1.2.1

*   **Fixed: no spells tracked on non-English clients.** On a French, German, Spanish or any other localized client, KickCD silently tracked nothing for most specs — the grid just stayed empty. Your spell lists now carry over automatically the first time each profile loads, with your own edits intact. Huge thanks to [@fttf7](https://github.com/fttf7), who reported this in [issue #8](https://github.com/tusharsaxena/kickcd/issues/8) with the debug output that pinpointed the cause.
*   **The Spells tab follows your spec.** Change spec with the settings window open and the spec dropdown now switches with you, instead of staying stuck on the old one until you closed and reopened settings.
*   **A quieter, more useful debug log.** A spell sitting on cooldown used to write about ten identical lines a second and bury everything else. The log now records real changes only, and the rebuild line names every spell being watched or skipped — so a pasted log is far easier to act on in a bug report.
*   **Lighter icon drawing.** Icons now skip repainting the parts that haven't changed while a cooldown ticks down — about a third less work per update, with no change to how anything looks.

### Also in 1.2.0

*   **Focus tracking.** KickCD now watches your focus as well as your target, each with its own icon grid and cast bar. Focus is on out of the box and copies your target's look — unlink it any time to style it on its own.
*   **Custom identity labels.** A new **Text Label** tab lets you put a label — "Target", "Focus", or your own text — on a unit's icon grid or cast bar, and place it however you like.
*   **On-screen debug window.** Debug output now shows in its own movable window with Copy and Clear buttons instead of filling up chat, and resets each reload. Toggle it with `/kcd debug on\|off\|toggle\|window`.
*   **Refreshed default layout.** Out of the box the cast bar sits under the icon grid with the cast time below it, and the target and focus sets start well apart so they don't overlap.
*   **`/kcd resetall` now restores positions,** putting every grid and cast bar back to its starting spot. A new `/kcd version` command tells you which build you're running.

## Screenshots

**_KickCD in Action_**

![KickCD in Action](https://i.ibb.co/8LSRBj0n/kickcd-video-07-compressed.gif)

_[Watch on YouTube](https://youtu.be/-rUhkVdmZfo)_


**_Zoomed in view of the icon grid and cast bar_**

![Zoomed in view of the icon grid and cast bar](https://media.forgecdn.net/attachments/1806/482/kickcd-image-01-addon-png.png)

**_Settings panel_**

![Settings panel](https://media.forgecdn.net/attachments/1806/483/kickcd-image-02-general-png.png)

![Settings panel](https://media.forgecdn.net/attachments/1806/484/kickcd-image-03-icons-png.png)

![Settings panel](https://media.forgecdn.net/attachments/1806/485/kickcd-image-04-castbar-png.png)

![Settings panel](https://media.forgecdn.net/attachments/1806/486/kickcd-image-05-textlabel-png.png)

![Settings panel](https://media.forgecdn.net/attachments/1806/487/kickcd-image-06-spells-png.png)

## Usage

### Slash commands

Type `/kcd` (or the longer `/kickcd`) to control the addon from chat. Replies are tagged with a cyan `[KCD]` label.

| Command | What it does |
| --- | --- |
| `/kcd` | Show the list of commands. |
| `/kcd version` | Show which version you're running. |
| `/kcd config` | Open the settings panel. Won't open during combat. Also `/kcd options`. |
| `/kcd lock` / `unlock` / `toggle` | Lock, unlock, or flip the one lock that covers every grid and cast bar so you can drag them. |
| `/kcd list` | List every setting and its current value. |
| `/kcd get setting` | Show one setting's value (for example `/kcd get units.target.icons.primarySize`). |
| `/kcd set setting value` | Change a setting. Colors take red/green/blue numbers, e.g. `/kcd set units.target.castbar.interruptible.barColor 0.2 0.8 0.2 1`. |
| `/kcd reset setting` | Put one setting back to its default (for example `/kcd reset units.target.icons.primarySize`). To reset a whole tab, use that tab's **Defaults** button. |
| `/kcd resetall` | Reset every tab, and every spec's spell list, to defaults — and put every grid and cast bar back in its starting position. |
| `/kcd resetposition` | Put the target icon grid back in its default spot on screen. |
| `/kcd spells subcommand` | Edit the tracked spells for a class and spec: `list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`, `resetall`. Defaults to your current spec. |
| `/kcd perf` | Measure the addon's performance — a guided before/after capture, driven from a clickable step panel. Mostly useful for bug reports. |
| `/kcd debug spells` | List the cooldowns the addon is watching. |
| `/kcd debug castbar` | Show your target's current cast and the colors in use. |
| `/kcd debug interrupt` | Show what the addon decided about your target's cast. Handy for bug reports. |
| `/kcd debug on\|off\|toggle` | Turn the debug log on or off. It resets when you reload. |
| `/kcd debug window` | Show or hide the on-screen debug window. |

### Settings panel

Six tabs under **Ka0s KickCD**:

| Tab | Covers |
| --- | --- |
| **General** | The master on/off switch, which units to track (target and/or focus), when the UI shows, the drag lock, and overall size and transparency. The "Reset position" and "Reset all settings" buttons live here too, plus a "Debug console" checkbox that shows or hides the on-screen debug window for this session. |
| **Icons** | Icon size, grid layout, how ready and not-ready icons look, borders, cooldown text and charges, tooltips, and the ready glow. A **Target / Focus** switch at the top picks which unit you're editing. |
| **Cast bar** | Turn the cast bar on, place it, size it, choose its direction, pick a font, and set separate colors for casts you can and can't interrupt — per unit, via the same Target / Focus switch. |
| **Text Label** | Show a custom identity label on a unit's icon grid or cast bar — its text, where it attaches, its offset, alignment, rotation, and font. Each unit has its own label. |
| **Spells** | Choose which spells to track for each class and spec. Only spells you can actually cast right now show up. |
| **Profiles** | Save separate settings per character, class, realm, or faction. |

On the Icons, Cast bar, and Text Label tabs, switch between **Target** and **Focus** at the top. The focus set starts **linked** to target — it copies target's icon and cast-bar styling automatically. Untick "Use same styling as Target" (or press "Copy styling from Target" and then edit) to give focus its own look; either way, each unit keeps its own position and its own label text.

Use `/kcd unlock` to drag each grid (and its cast bar, if it's set to move freely) into position, then `/kcd lock` to fix them.

## How interrupt tracking works

Here's what decides when the UI shows, hides, and lights up.

1.  **The master switch comes first.** If the addon is turned off, nothing shows.
2.  **A single visibility setting decides when the UI appears** — always, only in combat, only while a tracked unit is casting, or only while a tracked unit is casting something you can interrupt. Every grid and cast bar follows this one setting, so they show, hide, move, and lock together — but each unit is judged against its *own* cast, so your focus set can light up for the focus's cast while the target set stays hidden.
3.  **The icon grids track your cooldowns.** For your current class and spec, they watch your interrupts and cast-stopping crowd control, run each icon's cooldown timer, and show whether the ability is ready. Both units show the same cooldowns — they're yours, not the enemy's.
4.  **The cast bars track their units.** Each shows the spell its unit (target or focus) is casting or channeling and colors itself by whether you can interrupt it, so a glance tells you if the cast is worth a kick.

In the "interruptible only" mode a unit's set stays hidden while that unit casts something you can't interrupt, and appears the moment it casts something you can.

### Key settings

A few settings shape the addon's behavior more than the rest.

#### Target and focus

KickCD tracks two enemy units, and each gets its own icon grid, cast bar, and identity label:

*   **Target** — always tracked while the addon is on.
*   **Focus** — tracked by default, and **linked** to target so it copies target's icon and cast-bar styling. Turn it off in General → Units, or unlink it to style it on its own.

Position and the label's text are always per-unit, linked or not — the two sets start well apart so they don't overlap, and each can say "Target" / "Focus". While focus is linked it also mirrors target's label styling and whether the label shows at all; unlink it to set those separately. The drag lock, the visibility mode, and overall size/transparency stay shared across both.

#### Visibility (General → Master controls → General visibility)

One setting controls when the grids and cast bars appear. The master switch always wins: if the addon is off, nothing shows. Each tracked unit is judged separately against its own cast, so the focus set can be visible while the target set isn't.

| Value | When a unit's set shows |
| --- | --- |
| `always` | Always. |
| `in_combat` | Only while you're in combat. |
| `target_casting` | Only while that unit is casting or channeling. |
| `target_casting_interruptible` | Only while that unit is hostile and casting something you can interrupt. Casts you can't interrupt stay hidden. (Default.) |

The ready glow has its own copy of this setting (Icons → Ready glow), with the same choices plus a `never` option to turn the glow off. Your primary and secondary icons can use different triggers.

#### Cast bar placement (Cast bar → Position)

Two modes:

*   **Free (drag to move)** — the cast bar floats on its own. Unlock it, drag it where you want, and lock it again. Its position is saved.
*   **Anchored to the primary icon** — the cast bar sticks to the main icon in the grid and moves with it. Pick which points connect and a small offset. In this mode you don't drag the bar itself.

By default the bar sits just below the icon grid, lined up with its left edge.

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
| Does this replace Blizzard's cast bars? | No. It adds its own cast bars and leaves Blizzard's alone. If you don't want to see both, hide Blizzard's target/focus cast bars in Edit Mode. |
| Does it track my focus too? | Yes — target and focus are both tracked out of the box, each with its own grid and cast bar. The focus set copies target's look by default. Turn focus off in General → Units if you only want your target. |
| How do I make focus look different from target? | On the Icons, Cast bar, or Text Label tab, switch to **Focus** and untick "Use same styling as Target" (or press "Copy styling from Target" first, then edit). Position and the label's text are always independent; the label's styling and whether it shows follow the link. |
| I see a "Target" (or "Focus") label on my grid — what is it, and can I change or hide it? | That's the unit's identity label. Set its text, turn it off, or restyle and reposition it on the **Text Label** tab — you can attach it to the icon grid or the cast bar, and each unit has its own. While focus is linked it mirrors target's label styling and whether the label shows at all; its text stays independent. |
| How do I move the grids or cast bars? | `/kcd unlock`, drag, then `/kcd lock` — one lock covers every unit. Each icon grid always drags when unlocked. A cast bar drags only when it's set to move freely; when it's anchored, it follows its grid. `/kcd resetposition` puts the target grid back in its default spot, and `/kcd resetall` resets every unit's positions. |
| Where do my spell defaults come from, and why isn't every spell there? | Each class and spec comes with a starter list, set up the first time you use that character. The grid then shows only the spells you can cast right now, so spells from talents you didn't pick, spells you haven't learned, and pet abilities without a pet are hidden. To start over, use `/kcd spells resetall` (all specs) or `/kcd spells reset` (one spec). |
| Can I add my own spells? | Yes — in Settings → Spells, or with `/kcd spells add`. For the spec you're currently playing, only spells the game already tracks as cooldowns can be added. |
| Does it track items or trinkets? | Not yet — spells only. |
| Why won't the settings panel open in combat? | The game blocks opening settings mid-fight, so `/kcd config` waits until combat ends. |
| Are there per-character settings? | Yes — see Settings → Profiles. Every character starts on a shared default, and you can split off a per-character, per-class, per-realm, or per-faction profile whenever you like. |
| Does the fill direction change for channels? | Yes. A channel drains the same way the matching cast would fill — a bar that fills to the right during a cast drains to the left during a channel. |
| How do I capture debug info for a bug report? | The one-off snapshots — `/kcd debug interrupt`, `/kcd debug spells`, `/kcd debug castbar` — print to chat, so copy them from there. For a running trace, turn logging on with `/kcd debug on`, reproduce the problem, then open the on-screen debug window with `/kcd debug window` and hit **Copy**. The window resets on every reload. |

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The icon grid never appears. | Check three things: the addon is on (`/kcd get enabled` is `true`), your visibility setting fits the situation (`/kcd get visibility` — some modes need combat or a casting target), and your spec has at least one enabled spell that you know. `/kcd debug spells` lists what it's watching. |
| The icon grid won't drag. | It's locked. `/kcd unlock`, drag, `/kcd lock`. If unlocking doesn't seem to take, run `/kcd toggle`. |
| The focus set sits on top of my target set. | They start apart, but if you've moved things they can overlap. `/kcd unlock`, drag one out of the way, `/kcd lock`. `/kcd resetall` puts every unit back to its starting position. |
| I only want my target, not focus. | Turn focus off in General → Units (or `/kcd set units.focus.enabled false`). Everything focus-related disappears. |
| The cast bar still shows on casts I can't interrupt, even in "interruptible only" mode. | If the bar fades out on those casts, that's it working as intended — the frame is still there, just invisible. For anything else, run `/kcd debug interrupt` while the target is casting and include the output in a bug report. |
| Cooldown text sticks at `0.0` for a few seconds after a spell finishes. | This shouldn't happen anymore. If it does, capture `/kcd debug spells` during the stuck moment and report it, and make sure cooldown text is on (Icons → Annotations). |
| The glow on secondary icons flickers or restarts constantly. | This shouldn't happen anymore. If it does, make sure the glow trigger is set to one of the "target casting" options, and send a short video with your settings. |
| The settings panel won't open mid-fight. | On purpose — the game blocks it in combat. It opens the moment combat ends. |
| The cast bar won't auto-size to the grid. | Toggle Auto-size off and on, or run `/kcd resetposition` to force a refresh. Auto-size only controls the bar's length; its other dimension stays where you set it. |
| I want a clean slate. | One tab: that tab's **Defaults** button. One setting: `/kcd reset <setting>`. Everything but profiles: `/kcd resetall` (or General → Reset all settings). Just the grid's position: `/kcd resetposition`. One spec's spell list: `/kcd spells reset` or the Spells tab's Defaults button; every spec's: `/kcd spells resetall`. |

## Libraries and credits

KickCD bundles its libraries in `libs/` rather than fetching them at build time, so they ship inside the addon zip.

*   Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.8.0 (MIT). The shared Ka0s addon library — KickCD takes five of its modules: Core (the secret-safe printer), DebugLog (the on-screen console), Slash (the `/kcd` dispatcher and schema CLI), Options (the settings panel) and Perf (the A/B capture harness). Its license travels with the code at `libs/LibKa0s/LICENSE`.
*   Also bundled: Ace3 (AceAddon, AceConfig, AceConsole, AceDB, AceDBOptions, AceEvent, AceGUI and the SharedMedia widgets), CallbackHandler-1.0, LibCustomGlow-1.0, LibSharedMedia-3.0 and LibStub.

Whenever the vendored copy is refreshed, the LibKa0s version named above moves with it — that line is the answer to "which LibKa0s does this build carry?", so nobody has to grep minors out of `libs/LibKa0s/*.lua`.

## Issues and feature requests

Found a bug or want a feature? File it at [https://github.com/tusharsaxena/kickcd/issues](https://github.com/tusharsaxena/kickcd/issues). The issue tracker is where all reports and planned work live, so please post there rather than in comments.

## Version History

| Version | Date | Highlights |
| --- | --- | --- |
| 1.2.1 | 2026-07-26 | Fixed spell lists being empty on non-English clients — spec lists are now keyed on Blizzard's spec ID rather than the translated spec name, and existing profiles migrate automatically on load.<br>The Spells tab's spec dropdown now follows an in-game spec change while settings are open.<br>Debug log no longer floods with repeated lines while a spell is on cooldown; the rebuild line now names every watched and skipped spell.<br>Icons skip redundant repainting as a cooldown ticks down — about a third less work per update, with no visual change. |
| 1.2.0 | 2026-07-13 | Added target **and** focus tracking — each unit gets its own icon grid and cast bar, with focus on by default and linked to target's look. New **Text Label** tab for custom identity labels on any grid or cast bar. Added an on-screen debug window with Copy/Clear buttons, controlled by `/kcd debug on\|off\|toggle\|window` (replacing `/kcd debug log`); debug messages now go there instead of chat and reset each reload. Refreshed default layout: cast bar under the grid, cast time below it, and the two sets spaced apart. `/kcd resetall` now restores positions; added `/kcd version`. |
| 1.1.0 | 2026-05-03 | Added texture, font, and border dropdowns with live previews. The settings panel's main page now shows the logo and command list, with breadcrumb headers on subpages. All chat output now uses a single cyan `[KCD]` label. |
| 1.0.1 | 2026-05-02 | Rebuild only; nothing changed for players. |
| 1.0.0 | 2026-05-02 | Initial release. Interrupt and CC cooldown icon grid with flexible layout, plus a target cast bar that colors itself by interruptibility and can auto-size to the grid. Five-tab settings panel with full `/kcd` command coverage and per-tab Defaults. Visibility modes (always / in combat / target casting / interruptible only) with a per-icon ready glow. Per-spec spell lists with hover tooltips and known/unknown markers. Saved profiles. |
