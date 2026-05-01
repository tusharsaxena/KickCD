# Lock and anchor

The icon grid and the cast bar each have a single anchor in
`db.profile.anchors`, always relative to UIParent.
`Util.SaveAnchor(frame)` snapshots `{ point, relativePoint, x, y }`;
`Util.ApplyAnchor(frame, anchor)` restores it.

* `db.profile.anchors.icons` — the icon grid's saved position.
  Persisted by `IconGrid` `OnDragStop` and re-applied by
  `IconGrid:OnProfileChanged` / the General → "Reset position" button.
* `db.profile.anchors.castbar` — the cast bar's saved position. Only
  consulted when `db.profile.castbar.anchorMode == "FREE"`. Under
  `"PRIMARY"` the bar is `SetPoint`'d to the icon grid's primary icon
  button via the configured `(anchorPoint, castbarPoint, anchorOffsetX,
  anchorOffsetY)` tuple, the bar is locked from dragging regardless of
  `db.profile.locked`, and `KickCD_GRID_LAYOUT` triggers re-anchoring
  whenever the primary icon button reference changes.

Lock state lives in `db.profile.locked` and is shared by both widgets.
`IconGrid:ApplyLock` and `Castbar:ApplyLock` flip `EnableMouse(true/false)`
+ `RegisterForDrag("LeftButton" or nothing)` accordingly. The icon grid
also flips per-icon `EnableMouse` based on `(locked AND
icons.showTooltip)` so the hover-tooltip path lights up only while the
grid frame isn't claiming the mouse for drag. Touch points:

- Settings → General → "Lock frame" checkbox writes `db.profile.locked` and fires `KickCD_CONFIG_CHANGED { section = "general" }`.
- Slash commands `/kcd lock | unlock | toggle` do the same write + fire (see `core/KickCD.lua`).
- `IconGrid:OnConfigChanged` and `Castbar:OnConfigChanged` react to section `"general"` by calling `ApplyLock`.
