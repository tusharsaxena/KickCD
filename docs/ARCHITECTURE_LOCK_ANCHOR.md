# Lock and anchor

The icon grid has a single anchor (`db.profile.anchors.icons`), always relative to UIParent. `Util.SaveAnchor(frame)` snapshots `{ point, relativePoint, x, y }`; `Util.ApplyAnchor(frame, anchor)` restores it.

Lock state lives in `db.profile.locked`. `IconGrid:ApplyLock` flips `EnableMouse(true/false)` + `RegisterForDrag("LeftButton" or nothing)`. Touch points:

- Settings → General → "Lock frame" checkbox writes `db.profile.locked` and fires `KickCD_CONFIG_CHANGED { section = "general" }`.
- Slash commands `/kcd lock | unlock | toggle` do the same write + fire (see `core/KickCD.lua`).
- `IconGrid:OnConfigChanged` reacts to section `"general"` by calling `ApplyLock`.
