# LibKa0s v1.61.0 -> v1.62.0: the delta (KickCD)

Copied from the local tag `v1.62.0` (`5dc9f5d`) with `git -C ../LibKa0s archive v1.62.0 LibKa0s testkit`,
never from a working tree. The tag is local only (automated-tests sweep, item KC-ATS-RV; ATS-20, ATS-21).

## 3a/3b. Claimed and actual version

`grep -n '[Bb]undles' CLAUDE.md` read v1.61.0, and the vendored minors agreed with v1.61.0
(`Options` 25, `OptionsTabs` 5, `OptionsWidgets` 31). No claim/fact disagreement.

## 3c. Per-file minor delta (file list from the tag's `LibKa0s.xml`)

| File | v1.61.0 | v1.62.0 |
|---|---|---|
| `Options.lua` (`MINOR`) | 25 | 26 |
| `OptionsWidgets.lua` (`WIDGETS_MINOR`) | 31 | 32 |
| `OptionsTabs.lua` (`TABS_MINOR`) | 5 | 6 |
| `OptionsRegistry.lua` (`REGISTRY_MINOR`) | absent | 1 (new) |
| `OptionsIds.lua` (`IDS_MINOR`) | absent | 1 (new) |
| `OptionsIdList.lua` (`IDLIST_MINOR`) | absent | 1 (new) |
| `OptionsCombat.lua` (`COMBAT_MINOR`) | absent | 1 (new) |

Every other file is unchanged. The Options major key moves from `25.31.5.7.4.1` to
`26.1.32.1.1.6.1.7.4.1`, and the major is now ten files. No cross-major skew: every file moves with
the whole-folder copy.

## 3d. Both diffs, before the copy

`diff -rq --strip-trailing-cr <tag>/LibKa0s libs/LibKa0s`:

```
Files <tag>/LibKa0s/LibKa0s.xml and libs/LibKa0s/LibKa0s.xml differ
Files <tag>/LibKa0s/Options.lua and libs/LibKa0s/Options.lua differ
Only in <tag>/LibKa0s: OptionsCombat.lua
Only in <tag>/LibKa0s: OptionsIdList.lua
Only in <tag>/LibKa0s: OptionsIds.lua
Only in <tag>/LibKa0s: OptionsRegistry.lua
Files <tag>/LibKa0s/OptionsTabs.lua and libs/LibKa0s/OptionsTabs.lua differ
Files <tag>/LibKa0s/OptionsWidgets.lua and libs/LibKa0s/OptionsWidgets.lua differ
```

`diff -rq --strip-trailing-cr <tag>/testkit tests/_kit`:

```
Files <tag>/testkit/README.md and tests/_kit/README.md differ
Files <tag>/testkit/framework.lua and tests/_kit/framework.lua differ
Only in <tag>/testkit: inventory.lua
Only in <tag>/testkit: prose_coverage.lua
Only in <tag>/testkit: prose_selftests.lua
Files <tag>/testkit/run-automated-tests.sh and tests/_kit/run-automated-tests.sh differ
Files <tag>/testkit/test_layout_cap.lua and tests/_kit/test_layout_cap.lua differ
Files <tag>/testkit/test_prose.lua and tests/_kit/test_prose.lua differ
```

The byte diffs (`diff -rq`, no strip) list the same eight files each: no line-ending drift. No
`Only in libs/LibKa0s` or `Only in tests/_kit` line, so nothing is deleted.

What moved (LibKa0s `CHANGELOG.md`, v1.62.0): the id surface peels out of `OptionsWidgets.lua` into
`OptionsIds.lua` and `OptionsIdList.lua` (LibKa0s #32); the combat lock's page chrome out of
`OptionsTabs.lua` into `OptionsCombat.lua`; the page registry and its park out of `Options.lua` into
`OptionsRegistry.lua`. Each is a move: no member, descriptor field or row field changes.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)'` over the addon's own source (not `libs/`,
not `tests/`) finds 15 majors looked up; `LibKa0s-Options-1.0` at 8 sites. Only the Options major
moved, and it is consumed.

## 3f. Kit revision

`Kit.VERSION` 27 -> 31 (`tests/_kit/framework.lua:20`). Revisions 28 (the suite inventory peeled to
`inventory.lua`), 29 (the prose gate peeled to `prose_coverage.lua` and `prose_selftests.lua`), 30
(the runner prints `None.` under an empty "Functions `lizard` warned on" table, ATS-20) and 31 (the
runner's band table leaves out `Kit.layoutCap.exempt`'s generated files, ATS-21). Both payloads move
together by construction (whole-folder copy), which satisfies the kit-revision pairing rule.

## 3g. Contract delta

None. `grep -rn '__Attach[A-Za-z]*'` over the addon's own source finds only a comment
(`settings/Panel.lua:182`, about `lib.__AttachCompose`, which did not move). The four new
`__Attach*` entry points (`__AttachRegistry`, `__AttachIds`, `__AttachIdList`, `__AttachCombat`) are
library-internal: the shells call them where the members used to be defined, so an instance gets the
same members in the same order. The changelog states no member, descriptor field or row field
changes. **No blockers.**
