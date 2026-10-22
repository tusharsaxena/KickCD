# Refresh (KickCD): the moved local tag v1.75.0

The local annotated tag v1.75.0 moved twice after KC-RV vendored it from `265a89e`: to `6bf5f3e`
(LK-26: Sim minor 2, SimTimeline minor 2) and then to `9e5c4e2` (LK-27: SimPanel minor 2), its
final position. This addendum records the refresh from `265a89e` to `9e5c4e2` (KC-RV2). The files
before it (01_DELTA, 02_CANDIDATES, 05_SUMMARY) describe `265a89e` and stay frozen.

## The copy

The same copy KC-RV made: both payloads whole from `git -C ../LibKa0s archive v1.75.0 LibKa0s
testkit` (now `9e5c4e2`), with no `Only in` files on the addon side, then the tag's
`tools/prune-icons.lua` run against the unchanged CLAUDE.md line `LibKa0s icons: clear, close,
copy, help, segment.` The provenance line stays v1.75.0.

## What changed

| File | Old minor (`265a89e`) | New minor (`9e5c4e2`) |
|---|---|---|
| `libs/LibKa0s/Sim.lua` (`LibKa0s-Sim-1.0`) | 1 | 2 |
| `libs/LibKa0s/SimTimeline.lua` | 1 | 2 |
| `libs/LibKa0s/SimPanel.lua` | 1 | 2 |

The Sim docs key moves 1.1.1 -> 2.2.2. No other file under `libs/LibKa0s/` or `tests/_kit/`
changed; the kit revision stays 41 and the pruned icon set is the same six files.

## Effect on KickCD

None in code. KickCD does not consume `LibKa0s-Sim-1.0` (KickCD#38 stays open), and no test or
doc in the addon pins a Sim, SimTimeline or SimPanel minor or the Sim docs key. `test_vendor_sync`
passes against the moved tag.
