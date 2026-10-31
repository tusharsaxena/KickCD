Delta: LibKa0s v1.83.0 -> v1.84.0

Run non-interactively by item `KC-RV` of the 2026-10-31 findings remediation (M2), on branch
`feat/2026-10-31-findings-remediation`, following the installed `/dev-copilot:wow-revendor-libka0s`
at 2.6.1. Both payloads are copied whole, the provenance line rolls, the copy is pruned to the
`LibKa0s icons:` line, and every candidate beyond the run's brief is recorded as declined
(`02_CANDIDATES.md`). There is no interview and no GitHub issue is filed.

## Source

```sh
git -C ../LibKa0s rev-parse 'v1.84.0^{commit}'   # e917ccd (LOCAL; not pushed in this run)
git -C ../LibKa0s archive v1.84.0 LibKa0s testkit tools | tar -x -C <scratch>/x
```

## Pre-flight (Step 0)

KickCD's newest single-tag bundle, `../2026-10-24-v1.77.0/`, states base v1.76.0, and the provenance
line before it named v1.76.0: ok. No base correction is owed. The sweep of the rest of the roster
belongs to the run, not to this bundle.

## Base (3a, 3b)

```sh
grep -n 'Bundles' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.83.0 (MIT).   (before the roll)
git log -1 --format='%h %s' -- libs/LibKa0s tests/_kit
# f97114c KC-RV3: Take the re-cut LibKa0s v1.83.0 (LK-A3, the skin picker's rows)
git -C ../LibKa0s archive v1.83.0 LibKa0s testkit | tar -x -C <scratch>/claimed
diff -rq <scratch>/claimed/LibKa0s libs/LibKa0s | grep -v media/icons   # (empty)
diff -rq <scratch>/claimed/testkit tests/_kit                           # (empty)
```

Base v1.83.0: the line, the last payload commit and the bytes agree.

## Range

```sh
git -C ../LibKa0s log --oneline v1.83.0..v1.84.0
# e917ccd LK-M2-REL: Record the v1.84.0 release run (20261031-234858)
# ec46aae LK-M2-REL: Move the version lines to v1.84.0 and record the register rulings
# 940ed34 LK-M2-FIX: Pin the banner acts' release and the two shell-pair guards
# be9c929 LK-M2-68: Measure the drag handle at its scale and refit on show
# 0b49b58 LK-M2-66: Add LibKa0s-Charts-1.0, the Insights chart renderers
# c48d590 LK-M2-69: Record real Friz's md5 and guard WoW Default's bytes
# 3ff30a3 LK-M2-59: Add the flow seams, note row, Position block and banner acts
# 2455fe4 LK-M2-PEEL: Sync the docs and the band for the peels
# 2b6c0ab LK-M2-PEEL: Drop the drag handle's per-call mark tables
# 8cf7f75 LK-M2-PEEL: Peel the Ace fakes out of the kit's mock_base.lua
# 8dbbda1 LK-M2-PEEL: Peel the tabbed page out of OptionsTabs.lua
# 235b942 LK-M2-PEEL: Peel the flow engine out of OptionsWidgets.lua
# dc47002 LK-M2-PEEL: Peel the suggestion half out of OptionsIds.lua
# 14129ca LK-M2-PEEL: Peel the rows' section out of OptionsSkinPicker.lua
# 284907a LK-M2-PEEL: Peel the renderer out of SimPanel.lua
# 486005f LK-M2-PEEL: Peel the eight other skins out of SkinDefs.lua
# 9aec15e LK-M2-PEEL: Peel the owner-token block out of Skin.lua
# b007fcf FX-LK-REC: Record the post-remediation automated-test run
# e7363f3 FX-LK-SIZE: Correct the band note left stale by the sim panel split
# 960873f FX-LK-DOCS: Give IsFromSkin, OnReloadRequest and Owners their own keep reasons
# 0492f84 FX-LK-DOCS: Re-run the consumer census and step 9, and close the doc findings
# 5bf045a FX-LK-SIZE: Peel four suites on their named seams and track the payload band
# ddd7ef8 FX-LK-CITE: Name the repo on the suites' cross-repo citations
# 33840f0 Merge the skin fonts and font pickers runs
# 9ddbe89 SD-FIN: Sync docs for the font pickers and skin faces run
# 3abfe4d AT-FIN: Record the pre-merge automated-test run
git -C ../LibKa0s diff --stat v1.83.0 v1.84.0 -- LibKa0s testkit
#  29 files changed, 5290 insertions(+), 3521 deletions(-)
```

## Per-file minor delta (3c)

The loop over the tag's `LibKa0s/LibKa0s.xml`; every file not listed is at its v1.83.0 minor. No file
is behind, so there is no cross-major skew.

| File | v1.83.0 | v1.84.0 |
|---|---|---|
| `Schema.lua` | 2 | **3** |
| `Charts.lua` | (new) | **1** |
| `ChartsRender.lua` | (new) | **1** |
| `Skin.lua` | 10 | **11** |
| `SkinOwnerTokens.lua` | (new) | **1** |
| `SkinDefs.lua` | 18 | **19** |
| `SkinDefsOthers.lua` | (new) | **1** |
| `WidgetsDragHandle.lua` | 8 | **10** |
| `DebugLogDiagnostics.lua` | 5 | **6** |
| `Slash.lua` | 20 | **21** |
| `Options.lua` | 34 | **35** |
| `OptionsWidgets.lua` | 38 | **40** |
| `OptionsFlow.lua` | (new) | **2** |
| `OptionsIds.lua` | 5 | **6** |
| `OptionsIdSuggest.lua` | (new) | **1** |
| `OptionsTabs.lua` | 11 | **13** |
| `OptionsTabbed.lua` | (new) | **2** |
| `OptionsCompose.lua` | 14 | **15** |
| `OptionsSkinPicker.lua` | 4 | **5** |
| `OptionsSkinPickerRows.lua` | (new) | **1** |
| `SimPanel.lua` | 8 | **9** |
| `SimPanelRender.lua` | (new) | **1** |

Kit revision 46 -> 47 (3f), which moves with the payload as the pairing rule requires.

## Consumption (3e)

KickCD looks up Glow, Env, Bus, Core, DebugLog, Compat, Launcher, Lifecycle, Skin, Pool, Sim, Media,
Perf, Widgets, Schema, Slash and Options. `LibKa0s-Charts-1.0` is new and unconsumed; `Item` and
`Toast` stay unconsumed.

## Contract delta (3g)

Read: `docs/api/Options/version-35.4.40.2.6.1.7.13.2.3.15.9.4.3.6.5.5.1.1.1-docs.md` lines 39-72,
`docs/api/Widgets/version-17.3.10.5.5.2-docs.md` lines 19-30, against their predecessors named in each
header's `Supersedes` row. `grep -rn '__Attach' --include='*.lua'` outside `libs/` and `_kit` finds only
a comment at `settings/Panel.lua:181`, so no host-supplied member's call site moved.

### Blockers

1. `O.PositionBlock` is a new public member, owed by the Options degradation stub in
   `settings/OptionsSetup.lua` (Options document, "What changed at this version", first paragraph).
   Fixed in the copy commit.
2. `tests/test_options_panel.lua` pins sixteen Options files; the major is twenty at this tag. Fixed in
   the copy commit.

## Icon declaration (3i)

`LibKa0s icons: clear, close, confirm, copy, help, segment, settings.` stays directly under the
provenance line, unchanged. Hand lists have drifted before; a pruned icon still resolves to a path and
draws blank, so the owner's in-client smoke is the backstop.

## Tests that assume the whole folder (3j)

`tests/test_options_panel.lua:640` reads `info.tga` only to prove it is absent, and
`tests/test_mediasetup.lua:109` reads the catalog names rather than files. Neither is a blocker.

## Unrecorded tags (3h)

Every tag this addon vendored has a bundle after `../2026-10-31-v1.80.0-v1.83.0/`. Nothing to back-fill.
