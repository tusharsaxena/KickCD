# Ka0s KickCD

![version](https://img.shields.io/badge/version-0.1.0--alpha-blue)
![wow](https://img.shields.io/badge/WoW-Midnight%2012.0.5-orange)
![license](https://img.shields.io/badge/license-MIT-green)

KickCD is a lightweight, single-folder WoW addon that helps the player make
informed interrupt decisions in real time. It pairs two pieces of UI:

- A movable, persistently-visible **icon grid** of the player's interrupt +
  cast-stopping CC abilities, with cooldown swipes and a clear ready /
  not-ready state. Defaults are sensible per class and spec; the secondary
  block can be anchored to any of 13 points on the primary icon (the four
  sides × center / left / right alignments, plus a stack-on-top CENTER
  anchor) and filled in any of 8 grow directions.
- An independently-anchored **target cast bar** that mirrors the current
  target's cast or channel — spell icon, name, and remaining time. Bar fill
  color, background, border style, and font are configurable per
  interruptibility state (interruptible vs. uninterruptible). The bar can
  free-float, anchor to the icon grid's primary icon, and auto-size to the
  grid's actual visible footprint.

Both panels share a single addon-wide visibility mode (always / in combat /
target casting / target casting interruptible) and a single drag lock, and
both correctly handle WoW 12.0's "secret value" protection on protected-
interrupt cooldowns and `UnitCastingInfo` / `UnitChannelInfo` returns.

Everything is configurable through the standard Blizzard Settings panel and
through the `/kcd` slash command (every panel control has a CLI peer via
`/kcd get` / `/kcd set`).

## Status

`v0.1.0` alpha, targeting **WoW: Midnight 12.0.5** (Interface `120005`).
Backward compatibility with TWW 11.2.x is not a goal of this release.

## Install

1. Download or clone this repository.
2. Copy the entire `KickCD/` folder into your WoW install:
   `World of Warcraft/_retail_/Interface/AddOns/KickCD/`.
   The folder must contain `KickCD.toc` directly inside it (the repo root
   *is* the addon folder). Ace3 + LibSharedMedia + LibCustomGlow are
   vendored under `libs/` — no manual library install required.
3. Launch WoW and enable **Ka0s KickCD** in the addon list.

## Usage

### Slash commands

- `/kickcd` or `/kcd` — print the help index.
- `/kcd config` — open the settings panel (refuses during combat, as
  Blizzard's category-switch is protected). Also routed by `/kcd options`.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — share one drag lock with
  both the icon grid and the cast bar.
- `/kcd list` — dump every settings option grouped by panel, with current
  values.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every
  schema-driven option (e.g. `/kcd set icons.primarySize 56`,
  `/kcd set castbar.interruptible.barColor 0.2 0.8 0.2 1`).
- `/kcd reset <general|icons|castbar|spells>` — reset one panel to defaults.
- `/kcd resetall` — reset every schema-driven panel and rebuild every spec's
  default spell list. Mirrors the General → "Reset all settings" popup; no
  CLI confirmation prompt.
- `/kcd resetposition` — restore the icon grid to its default screen
  position (CENTER, y = -180).
- `/kcd spells` — per-class+spec spell-list editor:
  `list / add / remove / enable / disable / category / reset`. CLASS+SPEC
  default to the player's current spec when omitted.
- `/kcd debug` — diagnostic subcommands:
  - `spells` — dump the watched cooldown list.
  - `castbar` — print current target cast state plus configured / live
    per-state colors.
  - `interrupt` — dump `UnitCastingInfo` / `UnitChannelInfo` positions
    with their type and `issecretvalue()` flag, plus what the visibility
    logic decided (used to diagnose 12.0 secret-value handling).
  - `log` — toggle internal-message logging (mirrors General → Debug).

### Settings panel

Five subcategories under **Ka0s KickCD**:

- **General** — master enable, addon-wide visibility mode, lock, master
  scale / alpha, debug log. "Reset position" and "Reset all settings"
  buttons sit under Master controls.
- **Icons** — sizing, layout (anchor + grow + rows × cols), visual states
  (alpha / tint / GCD swipe suppression), border, annotations (cooldown
  text font / size / flags, charges, hover tooltip), per-slot ready glow
  (independent trigger and style for primary vs. secondary icons, backed
  by LibCustomGlow).
- **Cast bar** — enable, position (free-float or anchored to the primary
  icon at one of 13 anchor points × 13 cast-bar points), orientation /
  growth direction, auto-size to icon grid, sizing & layout, font, per-
  element text anchors and offsets (spell name, cast time), per-state
  appearance (interruptible vs. uninterruptible: bar texture / color /
  background / border style / border color / border thickness / spell-name
  color).
- **Spells** — per-class+spec spell-list editor. Class/spec dropdown shows
  class+spec icons and class-colored entries; rows show known/unknown glyph
  + spell icon + name + category + enable/move/remove controls. Header
  "Defaults" button resets the currently-selected spec only. The grid only
  ever renders entries the player can actually cast (talent choice nodes,
  pet spells while the pet is summoned, etc.).
- **Profiles** — AceDBOptions UI rendered into the unified panel chrome.

Use `/kcd unlock` to drag the icon grid (and the cast bar, if it's in FREE
anchor mode) into position, then `/kcd lock` to fix them.

## Documentation

For agents (or anyone diving into the code), start at:

- [`CLAUDE.md`](CLAUDE.md) — agent guide: rules, anti-patterns, the 12.0
  secret-value protocol. Indexes the per-section files under [`docs/`](docs/).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — current architecture: module map,
  data flow, message bus, saved-variable shape, Compat surface, slash
  dispatch. Indexes the per-section `ARCHITECTURE_*.md` files.

The original design docs are preserved under [`docs/legacy/`](docs/legacy/)
for historical context — they predate the cast-bar removal/re-add and the
12.0 secret-value handling, so do not treat them as the source of truth for
current behavior.

## Testing

There is no automated test harness; verification is manual. See
[`docs/CLAUDE_TESTING.md`](docs/CLAUDE_TESTING.md) for the slash-command
coverage and in-game spot checks. The legacy UAT scenarios live in
[`docs/legacy/UAT.md`](docs/legacy/UAT.md).

## License

MIT — see [`LICENSE`](LICENSE).
