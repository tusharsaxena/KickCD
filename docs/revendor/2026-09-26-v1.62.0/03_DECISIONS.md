# Decisions (KickCD)

- **No adoption in this item.** The candidate-adoption interview is out of scope for the
  automated-tests sweep (`Ka0sAddonsCommonTasks/docs/2026-09-26-AUTOMATED_TESTS_SWEEP/`, item
  KC-ATS-RV), and there is no candidate to adopt in any case (`02_CANDIDATES.md`).
- The library-absent stub in `settings/OptionsSetup.lua` needs no new no-op: no Options member is
  added, only moved between files.
- The descriptor-L tripwire in `tests/test_options_panel.lua` scans every `Options*.lua` file the
  vendored XML derives, and its count moves from six to ten (`OptionsRegistry`, `OptionsIds`,
  `OptionsIdList`, `OptionsCombat`). All ten were scanned and none reads a descriptor `L`.
