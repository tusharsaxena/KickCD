# What this is

KickCD is a WoW addon that tracks the player's interrupt and CC cooldowns and shows them on a movable, persistently-visible icon grid, with a sibling target cast bar. Target: WoW 12.0.5 (Midnight). Mainline branch is `master`. Display name in the addon list and Settings panel: `Ka0s KickCD`; the folder, addon ID, slash commands, and saved-variable namespace stay unprefixed `KickCD`.

The original cast-bar pipeline (Castbar / Tracker / TestMode modules) was removed at commit `59fb5c0` because its `OnUpdate` did arithmetic on `startTimeMS` / `endTimeMS` from `UnitCastingInfo`, which 12.0 returns as secret values. A fresh `modules/Castbar.lua` was re-added later with explicit secret-value gating (see [CLAUDE_CASTBAR.md](CLAUDE_CASTBAR.md)) — it now drives the bar entirely via `UnitCastingDuration` / `UnitChannelDuration` (CastingDuration objects whose methods are passed as direct C-method arguments), with stacked dual widgets curve-switched on the secret `notInterruptible` flag for per-state appearance. The TestMode preview was not re-added; the cast bar shows a placeholder while unlocked so the user can grab it for repositioning.

Both the icon grid and the cast bar honor a single addon-wide visibility mode (`db.profile.visibility`: `always` / `in_combat` / `target_casting` / `target_casting_interruptible`) and a single drag lock (`db.profile.locked`). The `target_casting_interruptible` mode uses a two-step gate (Show on hostile cast, alpha-mask uninterruptible via `SetAlphaFromBoolean` on the secret bool) because the underlying `notInterruptible` flag cannot be compared in Lua under 12.0 — see [CLAUDE_SECRET_VALUES.md](CLAUDE_SECRET_VALUES.md).

## Default spell coverage

`defaults/Spells.lua` is the per-class+spec default cast-stopper list. The canonical source for "what cast-stoppers does spec X have?" is Baratus's "Class Info - Wow" Google Sheet, **Midnight tab** (`gid=2092737897`):

  https://docs.google.com/spreadsheets/d/1lXIRuETd3s3wxLHE8mOwhXtz0xm71ayhrlYxwi6herU/edit?gid=2092737897

When syncing the defaults to the sheet, only columns **Q, S, T, U, V, X** matter (Interrupt, Stuns ST, Stuns AoE, CC Hard, CC Soft AoE, CC Other). Skip column **R** (Dispels / Soothes — not cast-stoppers) and column **W** (CC AoE Slow — slows don't stop casts in the categories KickCD tracks).

