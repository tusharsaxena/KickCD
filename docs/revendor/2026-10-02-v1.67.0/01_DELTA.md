# Delta: LibKa0s v1.66.0 -> v1.67.0

Copied from the local tag `v1.67.0` (`0bccf4c`) with `git -C ../LibKa0s archive v1.67.0 LibKa0s testkit`,
never from a working tree (`../LibKa0s` HEAD equals `v1.67.0^{commit}`, tree clean). The tag is local only.
This re-vendor is item CA-KC-RV of the 2026-10-02 LibKa0s census adoption
(`Ka0sAddonsCommonTasks/docs/2026-10-02-LIBKA0S_CENSUS_ADOPTION/`).

## 3a/3b. Claimed and actual version

`grep -n '[Bb]undles' CLAUDE.md` read v1.66.0 (line 42). The last commit to touch either payload
(`git log -1 --format=%H -- libs/LibKa0s tests/_kit`, `3901b38`, GI-KC-RV) left the same line. The payload
matched the library at v1.66.0 (`diff -rq` of both folders against `git archive v1.66.0`: no output). No
claim/fact disagreement. Base: v1.66.0.

Step 0 pre-flight: the newest single-tag bundle, `2026-10-01-v1.66.0/`, states v1.65.0 -> v1.66.0, which the
history agrees with (`3901b38` rolled the line from v1.65.0). No base correction, and no tag this addon
vendored is without a bundle (see 3h).

## 3c. Per-file minor delta (file list from the tag's `LibKa0s.xml`)

| File | v1.66.0 | v1.67.0 |
|---|---|---|
| `Core.lua` (`MINOR`) | 9 | 10 |
| `Options.lua` (`MINOR`) | 27 | 28 |
| `OptionsIdList.lua` (`IDLIST_MINOR`) | 2 | 3 |

Every other file is unchanged (`git -C ../LibKa0s diff --stat v1.66.0 v1.67.0 -- LibKa0s testkit`: three
files, all under `LibKa0s/`). The payload stays at 32 library files. No file is added or removed, so the TOC
(`KickCD.toc:28`, `libs\LibKa0s\LibKa0s.xml`) and `tests/run.lua`'s XML-derived load list need no line.

## 3d. Both diffs, before the copy

`diff -rq <tag>/LibKa0s libs/LibKa0s`: `Core.lua`, `Options.lua` and `OptionsIdList.lua` differ. No
`Only in` line on either side.

`diff -rq <tag>/testkit tests/_kit`: no output. The kit did not move.

Nothing is deleted. After the copy, `diff -r` of both folders against the tag is empty, and
`diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s` is empty. Line endings as the last re-vendor:
the archive's CRLF working-tree bytes copied as they are (`.gitattributes` `* text=auto eol=crlf`, stored
LF).

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' core modules settings`: both moved majors are
consumed. Core (`core/CoreSetup.lua:72`) and Options (`settings/OptionsSetup.lua:71`). OptionsIdList is a
secondary file of the Options major.

- KickCD calls no `MakeResizable` itself. The library calls it for the debug console and copy window
  (`DebugLog.lua:689-690`) and the perf panel (`PerfPanel.lua:162`), passing none of minor 10's three new
  fields, so those grips behave exactly as at minor 9.
- KickCD builds no `O.IdList`, so the `addonName` guard has no reader here today. The descriptor in
  `settings/OptionsSetup.lua` does not yet pass `addonName`; that is CA-KC-NM.

## 3f. Kit revision

`Kit.VERSION` 35 -> 35 (`tests/_kit/framework.lua:20`). The kit did not change between the tags, so the
kit-revision pairing rule holds by construction and no suite is wired.

## 3g. Contract delta

Additive only. Core minor 10: `MakeResizable` opts gain `canResize`, `onResizeStop` and `gripParent`, each
ignored unless of the right type; every existing caller passes none of them and is unchanged (version 10
document, *The resize grip*). OptionsIdList minor 3: the help mark accepts `d.addonName` only when the client
says that addon is loaded, and otherwise draws the Blizzard glyph and writes one `Cfg` line through `debug`.
Options minor 28 is a docblock correction. No member, field or string that existed at the old minors
changed meaning for a caller that passes none of the new fields.

### Blockers

None. After the copy alone the suite stayed at 1282 passed / 0 failed / 1 skipped (1283), the same as
before; the two vendor-sync cases read the provenance line, rolled in the same commit. No consumer test
broke from a library change, and nothing under `libs/` or `tests/_kit/` was edited.

### Sighted complexity

`bash tests/_kit/run-automated-tests.sh --suite complexity` on the copy: `pass`, `blindFiles` 0, 3538
functions, max CCN 15, 0 warnings. Its bundle and `RESULTS.md` roll were discarded; they are not part of this
item.

## 3h. Tags vendored and never recorded

None. Every tag the provenance line has named has a bundle, the newest being `2026-10-01-v1.66.0/`.
