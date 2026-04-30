# Icon grid layout model

`modules/IconGrid.lua` builds the visible grid from three orthogonal pieces, picked in this order:

1. **`icons.anchor`** — one of 12 anchor points naming where the secondary block attaches to the primary. The first word (`TOP` / `BOTTOM` / `LEFT` / `RIGHT`) is the side; the second word is the alignment along the perpendicular axis (`CENTER` always works; `LEFT` / `RIGHT` for `TOP`/`BOTTOM` sides; `TOP` / `BOTTOM` for `LEFT`/`RIGHT` sides). Examples: `RIGHT_CENTER`, `TOP_LEFT`, `BOTTOM_RIGHT`. There is no longer a separate `layout` (horizontal/vertical) field — the anchor's side is the primary axis.
2. **`icons.secondaryGrow`** — fill order inside the block as a compound `<primary>_<secondary>` direction. 8 valid values: `right_down`, `right_up`, `left_down`, `left_up`, `down_right`, `down_left`, `up_right`, `up_left`. Primary axis decides row-major (`right`/`left`) vs column-major (`down`/`up`) fill; secondary axis decides which way the next row/column wraps. Anchor and grow are independent — any of the 96 combinations renders sensibly.
3. **`icons.secondaryRows` × `icons.secondaryCols`** — block dimensions. Always geometric: `rows` is the vertical extent (icons stacked up/down), `cols` is the horizontal extent. Same values produce the same shape regardless of anchor.

The whole layout is in three small functions: `parseAnchor`, `parseGrow`, `placeBlock` (computes grid bounding box and the primary/block TOPLEFT corners), and the single `layoutBlock` that anchors every widget to the grid frame's TOPLEFT in pixel-floored screen coordinates.

`secondaryOffsetX` / `secondaryOffsetY` shift the block (not the primary) in screen-pixel space (positive X = right, positive Y = down).
