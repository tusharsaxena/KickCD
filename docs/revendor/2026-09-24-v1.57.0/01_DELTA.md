Delta: LibKa0s v1.56.0 -> v1.57.0

# 01 — Delta

Run: 2026-09-24, plan item M5-KC of the 2026-09-23 review and standards-audit remediation (milestone
M5, the always-on launcher status tooltip), written by hand by a workflow subagent the same way RV-KC
wrote `docs/revendor/2026-09-23-v1.56.0/`. Steps 0 and 2 to 4 are taken here. Steps 5 to 7
(candidates, interview, adoption) are not run as an interview: the one adoption this release owes
(`launcher-§1`, standard v2.66.0) is fixed by the M5 plan and lands in M5-KC's second commit. Target:
this repo, branch `feat/2026-09-23-review-audit-remediation` at `504ff29`. No push.

Source: the sibling checkout `../LibKa0s`, **tag `v1.57.0` (tag object `d03e836` -> commit
`aa37bc9`)**. `git -C ../LibKa0s tag --sort=-v:refname | head -1` -> `v1.57.0`. Extracted with
`git -C ../LibKa0s archive v1.57.0 LibKa0s testkit | tar -x -C <scratch>/`, never from the working
tree (`git -C ../LibKa0s status --short | wc -l` -> `0`). The tag is local and not pushed;
`tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the local tag is
enough.

```
git -C ../LibKa0s log --oneline v1.56.0..v1.57.0 | wc -l      -> 2
```

## Step 0 — Pre-flight on this addon's newest bundle

Newest single-tag bundle: `docs/revendor/2026-09-23-v1.56.0/`. Its line 1 names base `v1.55.0`, and
the commit that vendored v1.56.0 is `4844256` (RV-KC), whose parent's `CLAUDE.md` names v1.55.0.
**ok**, so no base correction is owed.

## 3a — Claimed version, and the delta base

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:42`: Bundles
[LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.56.0** (MIT). `git log -1 --format=%h --
libs/LibKa0s tests/_kit` -> `4844256`, which names v1.56.0. Before the copy the payload differed
from the v1.56.0-era bytes only where v1.57.0 moves (3d). **Base: v1.56.0.**

## 3b — Actual version, before the copy

`libs/LibKa0s/Launcher.lua:51` -> `local MAJOR, MINOR = "LibKa0s-Launcher-1.0", 2`. Kit revision 26
(`tests/_kit/framework.lua:20`).

## 3c — Per-file minor delta

One file moves. Every other file is unchanged from v1.56.0 (the library's CHANGELOG v1.57.0 version
block: Core 8, Env 1, Compat 1, Lifecycle 2, Bus 2, Schema 2, Pool 3, Item 2, Media 4, Widgets 10,
WidgetsDragHandle 2, DebugLog 13, Slash 15, Options 24, OptionsWidgets 31, OptionsTabs 4,
OptionsCompose 7, OptionsScroll 4, Perf 13, PerfPanel 5).

| File | Constant | v1.56.0 | v1.57.0 |
|---|---|---|---|
| `Launcher.lua` | `MINOR` | 2 | **3** |

No file is new and none is removed, so there is no cross-major skew. No `NEEDS_*` floor rises.

## 3d — Both diffs

Before the copy:

```
diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s   -> Launcher.lua differ
diff -rq <scratch>/LibKa0s libs/LibKa0s                        -> Launcher.lua differ
diff -rq --strip-trailing-cr <scratch>/testkit tests/_kit      -> (empty)
diff -rq <scratch>/testkit tests/_kit                          -> (empty)
```

After the copy (`rm -rf` both folders, then `cp -r` from the extracted tag), `diff -r` of both
payloads prints nothing and `test -x tests/_kit/run-automated-tests.sh` holds.
`git diff --stat` on the payload: `libs/LibKa0s/Launcher.lua | 113 +++++++++++++++++++++++++++++++++++++++++++--`.

## 3e — Consumption map

Unchanged from the v1.56.0 bundle's 3e: thirteen majors, Launcher among them at
`core/LauncherSetup.lua:61` (`LibStub("LibKa0s-Launcher-1.0", true)`).

## 3f — Kit revision, and the pairing rule

**26** at the tag and **26** vendored; the kit bytes are identical. Both payloads are still copied
whole in one commit, so the pairing rule holds by construction.

## 3g — Contract delta

| Major | Old -> new document | What moved |
|---|---|---|
| Launcher | `Launcher/version-2-docs.md:15` -> version 3 | the LDB object's `OnTooltipShow` is always the library's, drawing the status tooltip (title and version, `Enabled`, optional `Locked` / `Test mode`, the host's lines, the click hints) enabled or disabled; new optional descriptor fields `version`, `isLocked`, `isTestMode`, `leftClickLabel`, `slash`; `onTooltipShow` appends instead of replacing |

**Bound to what this addon hands over.** `core/LauncherSetup.lua` passes no `onTooltipShow`, so no
host line is doubled (anti-pattern #89 cannot fire here). It passes no `isEnabled` either: the left
click's disabled gate is the host's own, inside `onClick`. So at the copy the tooltip reads
`Enabled: Yes` in every state, and `Left-click: Toggle` (the library's default for a rung (a)/(b)
host with no `leftClickLabel`). Both are what `launcher-§1` (v2.66.0) now owes and M5-KC's second
commit supplies.

### Blockers

**None.** No test called the object's `OnTooltipShow`, so none expected only host lines.

**Suite at the copy** (payload, provenance line and this bundle only):

- `ka0s-bounded lua5.1 tests/run.lua` -> **1141 passed, 0 failed, 0 skipped, 1141 total**.
- `ka0s-bounded luacheck .` -> 0 warnings / 0 errors in 106 files.

## 3h — Tags this addon vendored and never recorded

None new: v1.16.0 to v1.54.2 are recorded by `docs/revendor/2026-09-24-v1.16.0-v1.54.2/` (KC-24),
v1.55.0 and v1.56.0 by their own bundles, and v1.57.0 by this one.
