# Scope

What KickCD is, what's in scope, and what's not. The user-facing contract lives in [README.md](../README.md); this doc records the *boundary* decisions so a fresh contributor can tell whether a feature request is in or out of scope without re-litigating it.

## What KickCD is

KickCD is a WoW addon that tracks the player's interrupt and CC cooldowns and surfaces them on a movable, persistently-visible icon grid, with a sibling cast bar — for **both the player's target and focus unit**, each independently — driven from the same drag lock and visibility settings. Designed as an interrupt rotation helper — not a generic raid-frame replacement.

Both UI pieces are gated by the addon-wide `db.profile.visibility` mode (`always` / `in_combat` / `target_casting` / `target_casting_interruptible`); both honor the master enable, the shared lock, and (per-unit, on top of those) each unit's own `units.<unit>.enabled` toggle. The tracked spell list itself stays player-centric (not unit-specific) — target and focus each render the *same* cooldowns against their own cast state. The full message contract between the cooldown poller, the icon grid, the cast bar, and the settings layer is documented in [message-bus.md](message-bus.md); per-unit config resolution (including "focus links to target's styling") lives in `core/Units.lua` (`NS.Units`) — see [saved-variables.md](saved-variables.md#unitsunit-shape).

Target client: WoW 12.0.7 (Midnight). Mainline branch: `master`. English-only.

Display name in the addon list and the Settings panel: `Ka0s KickCD` (the colored `## Title` field in `KickCD.toc`). The folder, addon ID, slash commands (`/kcd`, `/kickcd`), saved-variable namespace (`KickCDDB`), and global frame names all stay unprefixed `KickCD` for ergonomics — extended for target/focus dual tracking with a `Focus`-suffixed sibling per per-unit frame (`KickCDIconGridFocus`, `KickCDCastbarFocus`); target keeps the exact legacy unsuffixed names. See [conventions.md](conventions.md#frame-names).

## In scope

- **Cooldown tracking** for the player's interrupt + CC spells, with dynamic add/remove via talent / pet / racial events.
- **Movable icon grid** with anchor + grow model (13 anchor points × 8 grow directions × free row/col dims). Per-icon ready glow via LibCustomGlow. Tracked independently for target and focus (each unit's own enable, position, and — unless linked — appearance).
- **Cast bar** mirroring the tracked unit's (target and/or focus) cast via secret-value-gated `UnitCastingDuration` / `UnitChannelDuration`. Stacked dual widgets render distinct interruptible / uninterruptible appearance via `C_CurveUtil.EvaluateColorValueFromBoolean`.
- **Target + focus dual tracking.** Focus is on by default and links to target's icon grid + cast bar appearance (`units.focus.link`, default on) — or can be styled independently via "Copy styling from Target" + manual edits. Position and the identity label's *text* stay independent regardless of link state; the label's styling and its on/off flag follow the link like `icons`/`castbar` do. One shared drag lock and one shared visibility mode still cover both units — see [ARCHITECTURE.md](ARCHITECTURE.md#invariants-worth-not-breaking).
- **Per-class+spec spell list** with default seed plus user add / remove / enable / disable / re-categorize. CLI parity for every list operation.
- **Settings panel** integrated into Blizzard's AddOns settings + matching `/kcd` slash CLI for every panel-shaped operation. Schema is the single source of truth — see [settings-panel.md](settings-panel.md).
- **AceDB profiles** (every character starts on the shared `"Default"` profile; user can opt into per-character / per-class / per-realm scope via the Profiles tab).

## Out of scope

These have been considered and explicitly declined.

- **Localization.** English only for the addon's own strings: chat output, log lines and the slash CLI's canonical tokens are English on every client. Localization plumbing is a deliberate non-goal.

  This is **not** a license to be locale-*dependent*, which is a different thing and was a real bug (issue #8): persisted keys and lookups must never be derived from a localized string. Spell-list keys are the numeric specID (`Const.SPEC`), class keys are `UnitClass()`'s file token. Localized spec names are accepted as slash-command *input* and shown as dropdown *labels*, but never stored or compared as identity.
- **TestMode preview for the cast bar.** The original test-mode preview was removed at commit `59fb5c0` and has not been re-added. While the bar is unlocked it shows a static placeholder instead so the user can grab and reposition it.
- **Generic raid-frame / unit-frame replacement.** KickCD is scoped to the player's own interrupt rotation; mirroring party / arena cooldowns is out.
- **Drag-and-drop reordering** of Spells panel rows. The list order is intentional (defaults first, then user-added in append order).
- **LDB / minimap icon.**
- **Per-encounter / per-boss visibility profiles.**

## Default spell coverage

`defaults/Spells.lua` is the per-class+spec default cast-stopper list. The canonical source for "what cast-stoppers does spec X have?" is Baratus's "Class Info - Wow" Google Sheet, **Midnight tab** (`gid=2092737897`):

  https://docs.google.com/spreadsheets/d/1lXIRuETd3s3wxLHE8mOwhXtz0xm71ayhrlYxwi6herU/edit?gid=2092737897

When syncing the defaults to the sheet, only columns **Q, S, T, U, V, X** matter (Interrupt, Stuns ST, Stuns AoE, CC Hard, CC Soft AoE, CC Other). Skip column **R** (Dispels / Soothes — not cast-stoppers) and column **W** (CC AoE Slow — slows don't stop casts in the categories KickCD tracks).

## Spell-list lifecycle and recovery

`Database:BuildSpells` only re-seeds `db.profile.spells` when the WHOLE table is empty (i.e. on first profile creation or after `Database:ResetAllSpells`). Once any class entry exists, subsequent logins leave every spec list alone — including specs the user hasn't customized yet, since clearing every row in an active spec is a deliberate user choice that must survive a reload. This is intentional, not a missing re-seed pass.

If the user later changes their mind and wants defaults back, two slash commands cover the recovery surface:

- `/kcd spells resetall` — wipes every class+spec list and re-seeds from defaults plus the player's racial cast-stopper. Use this for a clean slate.
- `/kcd spells reset [CLASS SPEC]` — restores a single spec list to defaults; leaves every other spec untouched. The settings panel's per-spec "Defaults" button (the `KICKCD_RESET_SPELLS` popup) is the GUI entry point for the same recovery.

## Cast-bar removal history

The original cast-bar pipeline (Castbar / Tracker / TestMode modules) was removed at commit `59fb5c0` because its `OnUpdate` did arithmetic on `startTimeMS` / `endTimeMS` from `UnitCastingInfo`, which 12.0 returns as secret values. A fresh `modules/Castbar.lua` was re-added later with explicit secret-value gating (see [castbar.md](castbar.md)) — it now drives the bar entirely via `UnitCastingDuration` / `UnitChannelDuration` (CastingDuration objects whose methods are passed as direct C-method arguments), with stacked dual widgets curve-switched on the secret `notInterruptible` flag for per-state appearance.
