Delta: LibKa0s v1.57.0 -> v1.58.0

# 01 — Delta

Run: 2026-09-25, plan item M6-KC of the 2026-09-23 review and standards-audit remediation (milestone
M6, the launcher's left-click settings and right-click options menu), written by hand by a workflow
subagent the same way M5-KC wrote `docs/revendor/2026-09-24-v1.57.0/`. Steps 0 and 2 to 4 are taken
here. Steps 5 to 7 (candidates, interview, adoption) are not run as an interview: the one adoption
this release owes (`launcher-§2`, standard v2.67.0) is fixed by the M6 plan and lands in the same
M6-KC commit, because the copy alone turns seven launcher cases red (below). Target: this repo,
branch `feat/2026-09-23-review-audit-remediation` at `13c04e0`. No push.

Source: the sibling checkout `../LibKa0s`, **tag `v1.58.0` (tag object `93cf3ad` -> commit
`34931c9`)**. Extracted with `git -C ../LibKa0s archive v1.58.0 LibKa0s testkit | tar -x -C
<scratch>/`, never from the working tree and never by checking the tag out. The tag is local and not
pushed; `tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the
local tag is enough.

```
git -C ../LibKa0s log --oneline v1.57.0..v1.58.0 | wc -l      -> 2
```

## Step 0 — Pre-flight on this addon's newest bundle

Newest single-tag bundle: `docs/revendor/2026-09-24-v1.57.0/`. Its line 1 names base `v1.56.0`, and
the commit that vendored v1.57.0 is `16a04d2` (M5-KC), whose parent's `CLAUDE.md` names v1.56.0.
**ok**, so no base correction is owed.

## 3a — Claimed version, and the delta base

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:42`: Bundles
[LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.57.0** (MIT). `git log -1 --format=%h --
libs/LibKa0s tests/_kit` -> `16a04d2`, which names v1.57.0. **Base: v1.57.0.**

## 3b — Actual version, before the copy

`libs/LibKa0s/Launcher.lua` -> `local MAJOR, MINOR = "LibKa0s-Launcher-1.0", 3`. Kit revision 26.

## 3c — Per-file minor delta

One file moves. Every other file is unchanged from v1.57.0 (the library's CHANGELOG v1.58.0 version
block: Core 8, Env 1, Compat 1, Lifecycle 2, Bus 2, Schema 2, Pool 3, Item 2, Media 4, Widgets 10,
WidgetsDragHandle 2, DebugLog 13, Slash 15, Options key 24.31.4.7.4, Perf 13, PerfPanel 5).

| File | Constant | v1.57.0 | v1.58.0 |
|---|---|---|---|
| `Launcher.lua` | `MINOR` | 3 | **4** |

No file is new and none is removed, so there is no cross-major skew. No `NEEDS_*` floor rises.

## 3d — Both diffs

Before the copy:

```
diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s   -> Launcher.lua differ
diff -rq --strip-trailing-cr <scratch>/testkit tests/_kit      -> (empty)
```

After the copy (`rm -rf` both folders, then `cp -r` from the extracted tag, staged, and both folders
checked out again so the working tree carries the repo's CRLF), `diff -r --strip-trailing-cr` of both
payloads prints nothing and the kit's shell runner keeps mode 100755. The only payload file git sees
change is `libs/LibKa0s/Launcher.lua`.

## 3e — Consumption map

Unchanged from the v1.57.0 bundle's 3e: thirteen majors, Launcher among them at
`core/LauncherSetup.lua` (`LibStub("LibKa0s-Launcher-1.0", true)`).

## 3f — Kit revision, and the pairing rule

**26** at the tag and **26** vendored; the kit bytes are identical. Both payloads are still copied
whole in one commit, so the pairing rule holds by construction.

## 3g — Contract delta

| Major | Old -> new document | What moved |
|---|---|---|
| Launcher | `Launcher/version-3-docs.md` -> version 4 | left-click always calls `openSettings`, in either state (the rungs and version 2's disabled refusal are retired); right-click opens `MenuUtil.CreateContextMenu` with one checkbox per supplied pair, in the order Enabled / Locked / Test mode / Show window, the last three grayed while disabled; new optional fields `setEnabled`, `toggleLock`, `toggleTestMode`, `isWindowShown`, `toggleWindow`; `onClick`, `leftClickLabel`, `disabledLine`, `slash` retired and ignored; tooltip hints fixed to `Open settings` / `Options menu` |

**Bound to what this addon hands over.** At the copy, `core/LauncherSetup.lua` still passed
`onClick` (the rung-(b) lock toggle), `leftClickLabel` and `disabledLine`, all now ignored, and no
toggle, so both buttons opened the settings panel. That is a contract change under a surface whose
signature did not move, and it is an adoption blocker rather than a candidate: the lock toggle was
unreachable from the button until the host passed `toggleLock`.

### Blockers

Seven cases went red at the copy, every one pinning a retired contract:

```
FAIL  DISABLED: the launcher's LEFT click is refused and writes nothing
FAIL  LEFT click toggles the lock — rung (b), through the addon's own switch
FAIL  the left click goes through the SAME write seam the Lock frame checkbox does
FAIL  the tooltip, enabled and locked: title with the TOC version, Enabled, Locked, the rung-(b) hint
FAIL  the tooltip reads the lock on EVERY show, and the left-click hint follows it
FAIL  the tooltip still shows while DISABLED: Enabled: No, and the left-click hint names /kcd enable
FAIL  the left-click hint goes through the addon's locale
1140 passed, 7 failed, 0 skipped, 1147 total
```

Resolved in the same commit by the adoption (`05_SUMMARY.md`), which is why the copy and the adoption
are one commit rather than two.

## 3h — Tags this addon vendored and never recorded

None new: v1.16.0 to v1.57.0 are recorded by the earlier bundles, and v1.58.0 by this one.
