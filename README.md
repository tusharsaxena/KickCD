# Ka0s KickCD

![version](https://img.shields.io/badge/version-0.1.0--alpha-blue)
![wow](https://img.shields.io/badge/WoW-Midnight%2012.0.5-orange)
![license](https://img.shields.io/badge/license-MIT-green)

KickCD is a lightweight, single-folder WoW addon that helps the player make
informed interrupt decisions in real time. When the current target is a
hostile unit casting an interruptible spell, KickCD shows a movable icon grid
of the player's interrupt + cast-stopping CC abilities (with cooldown swipes
and a clear ready/not-ready state) plus a movable minimal target castbar with
cast name, time remaining, and an interruptibility-color border. Defaults are
sensible per class and spec; everything is configurable through the standard
Blizzard Settings panel.

## Status

`v0.1.0` alpha, targeting **WoW: Midnight 12.0.5** (Interface `120005`).
Backward compatibility with TWW 11.2.x is not a goal of this release.

## Install

1. Download or clone this repository.
2. **Vendor the libraries** — KickCD embeds Ace3 + LibSharedMedia-3.0 under
   `libs/`. The repo ships with empty lib folders and a step-by-step guide;
   follow [`libs/MANUAL_INSTALL.md`](libs/MANUAL_INSTALL.md) before first launch.
3. Copy the entire `KickCD/` folder into your WoW install:
   `World of Warcraft/_retail_/Interface/AddOns/KickCD/`
4. The folder must contain `KickCD.toc` directly inside it (the repo root *is*
   the addon folder).
5. Launch WoW and enable **Ka0s KickCD** in the addon list.

## Usage

- `/kickcd` — open the Ka0s KickCD settings panel.
- `/kcd` — same, shorter alias.
- `/kickcd debug` — verbose debug print (target state, watched-spell state).

The settings panel exposes five subcategories: General, Icons, Castbar,
Spells (per-class+spec list editor), and Profiles (Ace3 AceDBOptions).

## Documentation

Design docs live in [`docs/`](docs/):

- [`REQUIREMENTS.md`](docs/REQUIREMENTS.md) — functional + non-functional spec
- [`TECHNICAL_DESIGN.md`](docs/TECHNICAL_DESIGN.md) — architecture, file layout, message contracts
- [`RESEARCH.md`](docs/RESEARCH.md) — class/spec spell research backing the defaults
- [`EXECUTION_PLAN.md`](docs/EXECUTION_PLAN.md) — multi-agent build plan

## Testing

See [`docs/UAT.md`](docs/UAT.md) for the manual user-acceptance test scenarios
that cover all twelve acceptance criteria from `docs/REQUIREMENTS.md` §6.

## License

MIT — see [`LICENSE`](LICENSE).
