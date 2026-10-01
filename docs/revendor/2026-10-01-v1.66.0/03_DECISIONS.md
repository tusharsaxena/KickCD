# Decisions (KickCD)

- **No adoption interview and no GitHub issues this cycle.** Spec S4 of the 2026-10-01 issue pass
  (`Ka0sAddonsCommonTasks/docs/2026-10-01-GITHUB_ISSUE_PASS/02_SPEC.md`) says the candidates the skill
  surfaces are noted here and not interviewed; GI-LK-13's census picks them up.
- **`RenderGrid`'s `parent` and `opts.gap`**: adopted by item GI-KC-11 of the same run (KickCD#10), in its
  own commit after this re-vendor.
- **`test_lizard_sighted`**: wired in the re-vendor commit, as kit 35 requires.
- **The blind file `tests/test_icongrid_curves.lua`**: fixed in the re-vendor commit (a hoisted local),
  so the complexity suite is sighted from this commit on.
- **The three functions above CCN 15**: not touched here; item GI-KC-12.
- Everything else in `02_CANDIDATES.md` is left as is.
