Delta: LibKa0s v1.69.0 -> v1.70.0 (span: v1.69.0 v1.70.0)

Back-filled on 2026-10-07 by item `RV-KC` of the 2026-10-07 review and standards-audit remediation,
beside `../2026-10-07-v1.71.0/`. Two tags this addon vendored went without a bundle of their own (the
2026-10-07 audit's `KICKCD-C-01`, verified as `KC-A-01`). Both commits moved only the payload, the
kit and the CLAUDE.md provenance line; neither adopted anything.

**Base: v1.68.1**, the tag recorded by `../2026-10-04-v1.68.1/`, the newest bundle before this span.

The commits that carried them:

- **v1.69.0**: KickCD@`da8a8b8` (2026-10-06, "chore: re-vendor LibKa0s v1.69.0 (kit 37; adds the
  line chart widget)").
- **v1.70.0**: KickCD@`9d4a10b` (2026-10-07, "chore: re-vendor LibKa0s v1.70.0").

## v1.68.1 -> v1.69.0

```sh
git -C ../LibKa0s diff --stat v1.68.1 v1.69.0 -- LibKa0s testkit
#  LibKa0s/LibKa0s.xml          |   1 +
#  LibKa0s/WidgetsLineChart.lua | 463 +++
#  testkit/README.md            |   3 +-
#  testkit/framework.lua        |   2 +-
#  testkit/mock_base.lua        |   2 +
#  testkit/mock_lines.lua       |  85 ++++
```

- **Minors:** new file `WidgetsLineChart.lua` at minor 1 (`LibKa0s-Widgets-1.0` key 12.1.4.1). Every
  other file unchanged from v1.68.1.
- **Kit revision:** 36 -> **37** (new `mock_lines.lua`; `mock_base.lua` wires it).
- KickCD draws no chart. Nothing to adopt.

## v1.69.0 -> v1.70.0

```sh
git -C ../LibKa0s diff --stat v1.69.0 v1.70.0 -- LibKa0s testkit
#  LibKa0s/LibKa0s.xml             |   1 +
#  LibKa0s/WidgetsAutocomplete.lua | 375 +++
#  LibKa0s/WidgetsLineChart.lua    |  10 +-
```

- **Minors:** new file `WidgetsAutocomplete.lua` at minor 1, `WidgetsLineChart.lua` 1 -> 2
  (`LibKa0s-Widgets-1.0` key 12.1.4.2.1). Every other file unchanged from v1.69.0.
- **Kit revision:** 37, unchanged.
- **Note, not an adoption:** Widgets `Autocomplete` is a possible fit for the Spells editor's
  add-box (`settings/Spells_Header.lua`), offering spell-name completion as the user types. It is
  not adopted here and no issue is filed; it becomes an issue only if the owner wants it tracked.
