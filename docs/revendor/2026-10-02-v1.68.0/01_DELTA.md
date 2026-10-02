# Delta: LibKa0s v1.67.0 -> v1.68.0

Copied from the local tag `v1.68.0` (`cc9f5eb`) with `git -C ../LibKa0s archive v1.68.0 LibKa0s testkit`,
never from a working tree (`../LibKa0s` HEAD equals `v1.68.0^{commit}`, and
`git -C ../LibKa0s diff --quiet v1.68.0 -- LibKa0s testkit` exits 0). The tag is local only. This re-vendor
is item TP-KC-01 of the 2026-10-02 LibKa0s tooltip-place bundle
(`Ka0sAddonsCommonTasks/docs/2026-10-02-LIBKA0S_TOOLTIP_PLACE/00_PLAN.md`).

## 3a/3b. Claimed and actual version

`grep -n '[Bb]undles' CLAUDE.md` read v1.67.0 (line 42). The last commit to touch either payload
(`git log -1 --format=%H -- libs/LibKa0s tests/_kit`, `48f7960`, CA-KC-RV) left the same line. The payload
matched the library at v1.67.0 (`diff -rq` of both folders against `git archive v1.67.0`: no output). No
claim/fact disagreement. Base: v1.67.0.

Step 0 pre-flight for this addon: the newest single-tag bundle, `2026-10-02-v1.67.0/`, states
v1.66.0 -> v1.67.0, and the provenance line at `48f7960^` named v1.66.0. No base correction.

`git -C ../LibKa0s log --oneline v1.67.0..v1.68.0`: eight commits, `2cc8a03` (DA-LK-01, the code) through
`cc9f5eb` (DA-LK-07R, the release record).

## 3c. Per-file minor delta (file list from the tag's `LibKa0s.xml`)

| File | v1.67.0 | v1.68.0 |
|---|---|---|
| `WidgetsDragHandle.lua` (`DRAG_MINOR`) | 3 | 4 |

Every other shipped file is unchanged (`git -C ../LibKa0s diff --stat v1.67.0 v1.68.0 -- LibKa0s testkit`:
one file, `LibKa0s/WidgetsDragHandle.lua`). `Widgets.lua` stays at 12 and `WidgetsReorder.lua` at 1, so the
Widgets major's composite key moves 12.1.3 -> 12.1.4. No file is added or removed, so the TOC
(`libs\LibKa0s\LibKa0s.xml`) and `tests/run.lua`'s XML-derived load list need no line. No cross-major skew.

## 3d. Both diffs, before the copy

`diff -rq <tag>/LibKa0s libs/LibKa0s`: `WidgetsDragHandle.lua` differs. No `Only in` line on either side.

`diff -rq <tag>/testkit tests/_kit`: no output. The kit did not move.

Nothing is deleted.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)'` outside `libs/` and `tests/`: the Widgets major is
looked up at `modules/Castbar_Handle.lua:41`, `modules/IconGrid_Handle.lua:42`, `settings/Spells_Rows.lua:291`
and `settings/Spells.lua:595`. The two `*_Handle.lua` sites are the two drag-strip hosts, and both call
`KW.DragHandle` (the cast bar's strip, one per unit; the icon grid's strip, one per unit). Neither passes
`tooltipOwner`, `tooltipAnchor` or a descriptor `owner`/`anchor`, so both strips' tooltips are owned by the
frame hovered at `"ANCHOR_TOP"` (the widget's default; their headers say so on purpose).

## 3f. Kit revision

`Kit.VERSION` 35 -> 35 (`tests/_kit/framework.lua:20`). The kit did not change between the tags, so the
kit-revision pairing rule holds by construction.

## 3g. Contract delta

Additive only. `docs/api/Widgets/version-12.1.4-docs.md:20-48` ("What changed at 12.1.4"): the spec gains
`tooltipPlace` and the tooltip descriptor `place`, both Since 4. "Without a hook nothing changes. A host that
sets neither field gets minor 3's calls in minor 3's order (one `SetOwner`, the lines, one `Show`), for the
cursor owner and the frame owner alike" (`:44-45`), and "What a host must change: nothing" (`:47`). The one
internal change on the no-hook path is that the lines are evaluated into a table before drawing
(`dhTooltipLines`); a function entry is still called once per hover. KickCD's descriptors carry plain strings.

`__Attach*`: the only site in host code is a comment (`settings/Panel.lua:182`, the Compose seam), which this
release does not touch.

### Blockers

None.

## 3h. Tags vendored and never recorded

None. The audit listing (vendored tags from the payload and provenance-roll walk since the store's first
bundle, minus every bundle's recorded tags) printed nothing; the newest bundle is `2026-10-02-v1.67.0/`.
