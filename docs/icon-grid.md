# Icon grid layout

`modules/IconGrid.lua` is a **per-unit instance manager**: `instances[unit]` (`NS.Units.LIST` — `target`, `focus`) each hold their own frame, icon pool, and layout state, built lazily by `EnableUnit(unit)` and torn down by `DisableUnit(unit)` as `NS.Units.IsEnabled(unit)` flips. Everything below describes what one instance's `Layout()` pass does; every enabled unit runs it independently against its own config (`NS.Units.Icons(unit)`, link-resolved — a linked focus renders with target's `icons` table) and its own frame (`KickCDIconGrid` for target, `KickCDIconGridFocus` for focus). The two instances never share geometry state; a focus instance rebuilding doesn't touch target's icons or vice versa.

`Layout()` builds the visible grid from three orthogonal pieces, picked in this order:

1. **`icons.anchor`** — one of 13 anchor points naming where the secondary block attaches to the primary (12 `<SIDE>_<ALIGN>` tokens + `CENTER`). The first word (`TOP` / `BOTTOM` / `LEFT` / `RIGHT`) is the side; the second word is the alignment along the perpendicular axis (`MIDDLE` always works; `LEFT` / `RIGHT` for `TOP`/`BOTTOM` sides; `TOP` / `BOTTOM` for `LEFT`/`RIGHT` sides). Examples: `RIGHT_MIDDLE` (the default), `TOP_LEFT`, `BOTTOM_RIGHT`. There is no longer a separate `layout` (horizontal/vertical) field — the anchor's side is the primary axis.
2. **`icons.secondaryGrow`** — fill order inside the block as a compound `<primary>_<secondary>` direction. 8 valid values: `right_down`, `right_up`, `left_down`, `left_up`, `down_right`, `down_left`, `up_right`, `up_left`. Primary axis decides row-major (`right`/`left`) vs column-major (`down`/`up`) fill; secondary axis decides which way the next row/column wraps. Anchor and grow are independent — any of the 104 combinations (13 anchors × 8 grows) renders sensibly.
3. **`icons.secondaryRows` × `icons.secondaryCols`** — block dimensions. Always geometric: `rows` is the vertical extent (icons stacked up/down), `cols` is the horizontal extent. Same values produce the same shape regardless of anchor.

The geometry lives in `modules/IconGrid_Layout.lua` (published as `IconGrid.LayoutMath` — a distinct key from `modules/IconGrid.lua`'s `IconGrid:Layout()` orchestrator method, which calls into it): the three pure functions `IconGrid.LayoutMath.parseAnchor`, `IconGrid.LayoutMath.parseGrow`, `IconGrid.LayoutMath.placeBlock` (computes grid bounding box and the primary/block TOPLEFT corners), and the single `IconGrid.LayoutMath.layoutBlock` that anchors every widget to the grid frame's TOPLEFT in pixel-floored screen coordinates. The per-icon rendering — the `Icon` widget, cooldown/glow render, curves, and the countdown-text ticker — lives in the sibling `modules/IconGrid_Render.lua`.

`secondaryOffsetX` / `secondaryOffsetY` shift the block (not the primary) in screen-pixel space (positive X = right, positive Y = down).

## Visible-count sizing

The block's bounding box is computed against `usedRows` / `usedCols` — the rectangular extent of the *visible* icons — not the configured `secondaryRows * secondaryCols` capacity. Wrap math inside the per-icon loop still uses the configured `cols` / `rows` so a multi-row layout wraps at the user's chosen column count, but the grid frame's footprint hugs the live icons. This makes:

- the cast bar's "Auto-size to icon grid" track the actual visible width / height (commit `7f016f7`),
- the drag handle exclude phantom empty slots beyond the rendered icons,
- a primary-only grid collapse to `primarySize × primarySize` (no leftover gap or block padding).

## CENTER / MIDDLE alias

A `CENTER` anchor is the 13th option — it stacks the secondary block on top of the primary at the grid's centerpoint. Both `MIDDLE` and `CENTER` are accepted as the perpendicular-axis token (modern profiles save `_MIDDLE`; legacy profiles saved `_CENTER`); `IconGrid.LayoutMath.parseAnchor` normalizes them.

## Per-unit instances

Each unit's instance ends its `Layout()` pass by emitting `Ka0s_KickCD_GRID_LAYOUT { unit, gridFrame, primaryIcon, width, height }` (see [message-bus.md](message-bus.md#ka0s_kickcd_grid_layout-payload)) — `Castbar` filters on `payload.unit` before re-anchoring/auto-sizing its same-unit instance. Positioning (`anchors.icons`) and the optional identity label (`label.show`/`label.text`, a toggleable FontString above the grid) are always per-unit, even when a linked focus instance is rendering with target's `icons` styling table.
