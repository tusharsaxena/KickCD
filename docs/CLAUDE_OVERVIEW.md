# What this is

KickCD is a WoW addon that tracks the player's interrupt and CC cooldowns and shows them on a movable, persistently-visible icon grid. Target: WoW 12.0 (Midnight). Mainline branch is `master`.

The original cast-bar pipeline (Castbar / Tracker / TestMode modules) was removed at commit `59fb5c0` because its `OnUpdate` did arithmetic on `startTimeMS` / `endTimeMS` from `UnitCastingInfo`, which 12.0 returns as secret values. A fresh `modules/Castbar.lua` was re-added later with explicit secret-value gating (see [CLAUDE_CASTBAR.md](CLAUDE_CASTBAR.md)). The TestMode preview was not re-added.
