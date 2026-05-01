# Purpose

Track the player's interrupt and CC cooldowns and surface them on a movable icon grid, with a sibling target cast bar driven from the same lock and visibility settings. Both widgets are gated by the addon-wide `db.profile.visibility` mode (`always` / `in_combat` / `target_casting` / `target_casting_interruptible`); both honor the master enable and the shared lock. Designed as an interrupt rotation helper rather than a generic raid-frame replacement.

