# Candidates (KickCD, LibKa0s v1.76.0 -> v1.77.0)

Sources: `git -C ../LibKa0s log --oneline v1.76.0..v1.77.0` (15 commits), the tag's `CHANGELOG.md`
v1.77.0 block (`CHANGELOG.md:13-387`, with *What a consumer owes* at its end), and the API documents
of the majors that moved: `docs/api/Core/version-12-docs.md`,
`docs/api/Widgets/version-15.1.5.3.3-docs.md`,
`docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md`, `docs/api/Sim/version-2.3.6-docs.md`
and `docs/api/testkit/version-42-docs.md`.

Every decision below was taken by the run's plan (`items.json` and `inputs/OWNER_SCOPE.md` of the
2026-10-24 bundle in Ka0sAddonsCommonTasks), not by an interview here. There is no
`03_DECISIONS.md` or `04_EXECUTION_PLAN.md`, and no GitHub issue is filed.

## A. Delivered on the re-vendor alone (not offered)

- **Toplevel tool windows** (Core 12, DebugLog 21, PerfPanel 9, SimPanel 6): the debug console, the
  perf panel and the sim panel are `SetToplevel(true)`, and each re-raises a shown StaticPopup on
  show through `Core.RaiseStaticPopups()` (`CHANGELOG.md:71-97`; `docs/api/Core/version-12-docs.md:24`).
  KickCD opens all three, so a *Reset all settings* confirmation is no longer buried by a console
  opened after it (KIC-Z10 of the strata review).
- **Clamped popups** (Widgets 15, WidgetsAutocomplete 3): the shared dropdown menu and the
  autocomplete list stay on screen (`CHANGELOG.md:128-149`).
- **The suggestion list closes at combat start** (OptionsIds 3, OptionsCombat 2;
  `CHANGELOG.md:151-179`). KickCD's spell id editor is the library's, so it takes this as is.

## B. Decided: adopt in this run (not in this commit)

- **DragHandle `spec.level` / `handle:ApplyLevel()` / `spec.ignoreParentAlpha`** (WidgetsDragHandle 5,
  class B). Evidence: `CHANGELOG.md:99-126` (KickCD KIC-Z07 named among the hosts that re-level by
  hand) and `docs/api/Widgets/version-15.1.5.3.3-docs.md:39-60`. Additive. **Decided adopt** by
  KC-ZS, for the ids `plan-data/accepted.json` lists for KickCD; that item is held for the owner and
  launched later.

## C. Deferred (run 2026-10-24)

- **`O.KeybindingsTab(spec)` / `O.KeybindRows` / `O.KEYBINDS_UNCHANGED`** (OptionsKeybinds 2-3,
  class B). Evidence: `docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md:61-71`. KickCD has
  no `Bindings.xml` and no KC-KB item in this run. Deferred (run 2026-10-24); the stub members
  arrive in this commit as the 3g blocker fix only.
- **`O.StrataTooltip(values, strings)`** (OptionsCompose 8, class B). Evidence:
  `docs/api/Options/version-30.2.34.3.5.9.2.8.4.2.1.3-docs.md:86-92`. KickCD is not among the
  run's four adopters (AuraMaster, MultiMeters, PanelMaster, PartyFrameEnhanced). Deferred (run
  2026-10-24); any strata row KC-ZS touches decides it there.
- **Kit `mock_bindings.lua`, `Kit.assertBindingsXml`, `Kit.keybindThroughTab`** (kit 42). No
  binding to test. Deferred (run 2026-10-24).
- **Kit `mock_layers.lua`** (kit 42; `docs/api/testkit/version-42-docs.md:82`). The KC-ZS item
  installs it for its layering tests. Deferred (run 2026-10-24) to that item.

Nothing is filed as an issue: the run's plan files nothing from a re-vendor.
