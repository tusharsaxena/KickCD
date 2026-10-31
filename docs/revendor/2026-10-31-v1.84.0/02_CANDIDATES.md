# Candidates (KickCD, LibKa0s v1.83.0 -> v1.84.0)

Sources: `git -C ../LibKa0s log --oneline v1.83.0..v1.84.0` (26 commits), the tag's `CHANGELOG.md`
v1.84.0 block, and the API documents of the majors that moved. Every decision below was taken by the
run's brief (Ka0sAddonsCommonTasks `docs/2026-10-31-FINDINGS_REMEDIATION/M2_LIBRARY_RELEASE.md`), not by
an interview. Candidates beyond the brief are declined here, and no GitHub issue is filed.

## A. Delivered on the re-vendor alone (not offered)

- **The drag handle's fit** (WidgetsDragHandle 10, LibKa0s#68): a strip measures at its own effective
  scale, writes the measured text fresh and repeats the host's last fit on show. `modules/Castbar_Handle.lua`,
  the one at-risk host the library's pass named, needs no change.
- **`ApplyLevel` allocates nothing** (WidgetsDragHandle 9).
- **The peels**: `SkinOwnerTokens`, `SkinDefsOthers`, `SimPanelRender`, `OptionsSkinPickerRows`,
  `OptionsIdSuggest`, `OptionsFlow`, `OptionsTabbed` and kit `mock_ace.lua`. Pure moves.
- **DebugLogDiagnostics 6**: the identity header names Charts. No KickCD suite pins the minor.

## B. Decided: adopt in this run

- **`O.PageBanner{ acts }`** (OptionsTabs 13, LibKa0s#59): replaces the Units page's `PageHeader` band,
  KIC-L01. Replaces code the host owns. Commit prefix `KC-ADOPT`.
- **`shownWhen`** (OptionsSwitch 1, already vendored; LibKa0s#67): the glow knob subsections of
  `settings/Icons.lua`. Commit prefix `KC-67`.

## C. Declined (outside the run's brief)

- **`opts.afterSubgroup`, `opts.beforeGroup`** (OptionsFlow 2): no host-drawn heading or line of KickCD's
  waits on them. Additive.
- **The `note` row** (OptionsFlow 2, Schema 3, Slash 21): additive; not in the brief.
- **`O.PositionBlock`** (OptionsCompose 15): the addon's position rows and its Reset are its own and
  this run moves nothing in them. The stub member arrives as the 3g blocker fix only.
- **`LibKa0s-Charts-1.0`** (whole module, new): KickCD draws no chart.
