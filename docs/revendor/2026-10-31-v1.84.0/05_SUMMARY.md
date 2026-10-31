# Summary (KickCD)

LibKa0s v1.83.0 -> v1.84.0 from the local tag (`e917ccd`, via `git archive`). The base comes from the
CLAUDE.md provenance line and matches the payload bytes. Per-file minors are in `01_DELTA.md`. Kit 46 -> 47.

In the same commit as both payloads:

- the CLAUDE.md provenance line rolls to v1.84.0; `LibKa0s icons: clear, close, confirm, copy, help,
  segment, settings.` stays directly under it;
- the tag's `tools/prune-icons.lua` keeps 8 files and removes 5,832, the same set as before;
- the 3g blockers: `settings/OptionsSetup.lua`'s Options stub gains a hollow `PositionBlock`, and
  `tests/test_options_panel.lua` counts twenty Options files;
- `tests/test_sim_seam.lua` drops four Sim files, not three (`SimPanelRender.lua` joined).

- **Delivered free (class A):** the drag handle's fit and allocation fix, and the peels.
- **Adopted, in later commits of this run:** `PageBanner{ acts }` (`KC-ADOPT`), and the glow knobs and
  the cast bar's anchor rows on `shownWhen` (`KC-67`).
- **Declined:** the flow seams, the `note` row, `O.PositionBlock` and Charts, in `02_CANDIDATES.md`. No
  issue filed, by the run's brief.
- No span bundle; no base correction; README credits unchanged (the same sets ship); no dead stub
  mirror; no refresh file.

Gate after the copy, prune and blocker fixes:

- tests (`ka0s-bounded lua tests/run.lua`): 1576 passed, 0 failed, 1 skipped, 1577 total. Before the
  fixes: 1575 passed, 1 failed (`tests/test_sim_seam.lua`'s count).
- `docs/test-cases.md`: `lua tests/run.lua --list` output identical to the committed file.
- luacheck (`ka0s-bounded luacheck .`): 0 warnings / 0 errors in 153 files.
