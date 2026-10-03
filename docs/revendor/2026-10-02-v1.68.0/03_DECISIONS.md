# Decisions (KickCD)

No interview: the owner delegated every decision for this run (TP-KC-01 of
`Ka0sAddonsCommonTasks/docs/2026-10-02-LIBKA0S_TOOLTIP_PLACE/00_PLAN.md`) and asked that the reasoning be
recorded. No GitHub issue is filed: nothing was declined.

## `tooltipPlace`: adopt

The owner's request (AuraMaster#22 smoke feedback, 2026-10-02, extended to the collection the same day) is
that a drag strip's tooltip sit **beside** the strip: to its right, or to its left when the strip's right
edge plus the tooltip's width would leave the screen. KickCD's strips are not cursor-owned, so the plan's
"adopt where cursor-owned" rule does not decide it; the question is whether `ANCHOR_TOP` off the hovered
frame already matches that request. It does not, for three reasons:

1. **It is not the placement asked for.** `ANCHOR_TOP` puts the tooltip above the strip, not beside it, and
   above the `?` mark when the mark is hovered, so the strip and its mark give two different positions.
   Beside-the-strip resolves the mark to its strip and gives one.
2. **Above is where KickCD stacks its own frames.** The strip hangs above the grid (or the bar), above the
   unit label when one is parked there (`UnitLabel:FrameAbove`), and the Focus grid sits above Target's by
   default (FOCUS-1: y 260 over y 120). A tooltip opening upward lands on the next thing in that stack;
   beside the strip it covers neither.
3. **It has no edge rule.** Near the top of the screen `ANCHOR_TOP` is clamped back down over the strip
   being hovered; the requested rule flips sides at the right edge instead.

Consistency is a fourth, smaller reason: AuraMaster (TP-AM-01) places its strip tooltips this way, and the
owner hovers both addons' strips in the same session.

Shape: one placement, `NS.Util.PlaceTooltipBeside(tip, frame)` in `core/Util.lua`, passed as
`tooltipPlace` by both strips. It resolves the strip (the hovered frame when it carries the widget's `help`
field, else its parent), reads the strip's right edge, the tooltip's width and `UIParent`'s right edge,
each multiplied by its frame's effective scale so the comparison is in screen pixels (the grid takes the
master scale), and answers `nil` (not placed, so the widget's cursor fallback) when any of those reads is
nil, not a number, or secret by `NS.Compat.IsSecret`, the seam every other KickCD read goes through. It
returns `true` only after anchoring. KickCD's frames are plain `UIParent` children, so the fallback is a
guard, not an expected path.

## Smoke

New owner checks CAST-15 and GRID-17 in `docs/smoke-tests.md` (owed table), and CAST-10's expectation
corrected to the beside position. Owner-run; never marked here.
