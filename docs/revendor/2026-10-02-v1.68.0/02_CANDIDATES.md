# Candidates (KickCD)

One release, one surface. Sources: `git -C ../LibKa0s log --oneline v1.67.0..v1.68.0`, the v1.68.0 block of
`../LibKa0s/CHANGELOG.md`, and `docs/api/Widgets/version-12.1.4-docs.md` against `version-12.1.3-docs.md`.

## Class A (delivered on the copy)

- **The tooltip lines are evaluated once per hover** (`dhTooltipLines`, `WidgetsDragHandle.lua` minor 4).
  Without a hook, a hover still makes minor 3's calls in minor 3's order (`version-12.1.4-docs.md:44-45`).
  KickCD's two descriptors carry plain strings, so nothing a player sees moves.

## Class B (host change required)

- **`tooltipPlace(tip, frame)` / descriptor `place`** (Since 4, `version-12.1.4-docs.md:20-48`, `:692`,
  `:725-745`). With a hook set, the widget owns `GameTooltip` by `UIParent` at `ANCHOR_NONE`, draws, shows,
  then calls the hook under `pcall` with the frame hovered; only a literal `true` means placed, and
  anything else falls back to the cursor owner with the same lines.
  - Files it would touch: `core/Util.lua` (one placement both strips share), `modules/Castbar_Handle.lua`
    and `modules/IconGrid_Handle.lua` (one spec field each, and their headers' tooltip paragraphs),
    `tests/test_util_anchor.lua`, `tests/test_castbar_frame.lua`, `tests/test_icongrid_handle.lua`,
    `docs/smoke-tests.md`, `docs/castbar.md`.
  - Today: both strips leave `tooltipOwner`/`tooltipAnchor` unset, so the tooltip is owned by the frame
    hovered at `ANCHOR_TOP` (strip or `?` mark). It is NOT cursor-owned: nothing in KickCD inherits
    `DisableUntrustedLayoutScriptsTemplate` (both handle files say so).
  - Recommendation: **adopt** (reasoning in `03_DECISIONS.md`).
  - Blast radius: additive. One new pure function and one spec field per strip; nothing the addon ships
    is deleted. The failure mode is bounded by the widget: an unplaceable read falls back to the cursor
    tooltip with the same lines.

## Class C (whole-module adoption)

None. No major moved that KickCD does not already consume.
