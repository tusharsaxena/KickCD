Delta: LibKa0s v1.55.0 -> v1.56.0

# 01 — Delta

Run: 2026-09-24, plan item RV-KC of the 2026-09-23 review and standards-audit remediation, written by
hand by a workflow subagent. It follows the local `../wow-addon/commands/revendor-libka0s.md` as
amended by WA-01 (`d4b5950`, `aa0d7d5`). The installed plugin does not carry WA-01 yet, so the command
itself was not run. Steps 0 and 2 to 4 are taken here. Steps 5 to 7 (candidates, interview, adoption)
are **not**: every adoption decision is one of this addon's M3 plan items (KC-02 to KC-28). The folder
is dated for the plan (2026-09-23), as the plan names it. Target: this repo, branch
`feat/2026-09-23-review-audit-remediation` at `5adf126` (KC-01, which cleared the v1.56.0 dry-run
reds ahead of this copy). No push.

Source: the sibling checkout `../LibKa0s`, **tag `v1.56.0` (tag object `4622018` -> commit
`514fc0a`)**. The tag was resolved with `git -C ../LibKa0s tag --sort=-v:refname | head -1` and
extracted with `git -C ../LibKa0s archive v1.56.0 LibKa0s testkit | tar -x -C <scratch>/`, never from
the working tree (`git -C ../LibKa0s status --short | wc -l` -> `0`). The tag is local and not yet
pushed. `tests/test_vendor_sync.lua` compares against the tag the provenance line names, so the local
tag is enough.

```
git -C ../LibKa0s log --oneline v1.55.0..v1.56.0 | wc -l      -> 53
```

## Step 0 — Pre-flight on this addon's newest bundle

Newest single-tag bundle: `docs/revendor/2026-09-23-v1.55.0/`. Its line 1 names base `v1.54.2`. The
commit that vendored v1.55.0 is `523d05a` ("Re-vendor LibKa0s v1.55.0"), and `git show
523d05a^:CLAUDE.md | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9.]+[0-9]'` gives `v1.54.2`. **ok**, so
no base correction is owed.

That bundle's line 1 is a heading, `# Re-vendor delta: LibKa0s v1.54.2 -> v1.55.0`, not the bare form
WA-01 now fixes. The audit reads the tags off it all the same, and a frozen bundle is never rewritten,
so it stays as written.

## 3a — Claimed version, and the delta base

`grep -n '[Bb]undles' CLAUDE.md` -> `CLAUDE.md:42`: Bundles
[LibKa0s](https://github.com/tusharsaxena/LibKa0s) **v1.55.0** (MIT).

Cross-check: `git log -1 --format=%h -- libs/LibKa0s tests/_kit` -> `523d05a`, whose `CLAUDE.md` names
v1.55.0, and `git log --format=%h 523d05a..HEAD -- CLAUDE.md` is empty. The two answers agree. The
payload before the copy also matched the v1.55.0 tag exactly: `diff -rq <v1.55.0>/LibKa0s libs/LibKa0s
&& diff -rq <v1.55.0>/testkit tests/_kit` printed `payload-matches`. **Base: v1.55.0.**

## 3b — Actual version, before the copy

`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua`: the v1.55.0
block in the old column of 3c. Kit revision 25 (`grep -n 'Kit.VERSION' tests/_kit/framework.lua` ->
`:20`). The line and the bytes agreed.

## 3c — Per-file minor delta

The file list comes from the tag's `LibKa0s/LibKa0s.xml` (21 `<Script>` rows, unchanged from
v1.55.0). The minors come from the 3b grep over the vendored copy (old) and the extracted tag (new).

| File | Constant | v1.55.0 | v1.56.0 |
|---|---|---|---|
| `Core.lua` | `MINOR` | 7 | **8** |
| `Env.lua` | `MINOR` | 1 | 1 |
| `Compat.lua` | `MINOR` | 1 | 1 |
| `Lifecycle.lua` | `MINOR` | 1 | **2** |
| `Bus.lua` | `MINOR` | 1 | **2** |
| `Schema.lua` | `MINOR` | 1 | **2** |
| `Pool.lua` | `MINOR` | 3 | 3 |
| `Item.lua` | `MINOR` | 1 | **2** |
| `Media.lua` | `MINOR` | 3 | **4** |
| `Widgets.lua` | `MINOR` | 9 | **10** |
| `WidgetsDragHandle.lua` | `DRAG_MINOR` | 2 | 2 |
| `DebugLog.lua` | `MINOR` | 12 | **13** |
| `Slash.lua` | `MINOR` | 14 | **15** |
| `Launcher.lua` | `MINOR` | 1 | **2** |
| `Options.lua` | `MINOR` | 23 | **24** |
| `OptionsWidgets.lua` | `WIDGETS_MINOR` | 30 | **31** |
| `OptionsTabs.lua` | `TABS_MINOR` | 3 | **4** |
| `OptionsCompose.lua` | `COMPOSE_MINOR` | 7 | 7 |
| `OptionsScroll.lua` | `SCROLL_MINOR` | 3 | **4** |
| `Perf.lua` | `MINOR` | 12 | **13** |
| `PerfPanel.lua` | `PANEL_MINOR` | 5 | 5 |

No file is new and none is removed. Every file moves forward or stays put, so there is **no
cross-major skew** before or after. The library's CHANGELOG says no `NEEDS_*` floor rises.

## 3d — Both diffs

Before the copy:

```
diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s   -> 15 "differ" lines: Bus, Core, DebugLog,
    Item, Launcher, Lifecycle, Media, Options, OptionsScroll, OptionsTabs, OptionsWidgets, Perf, Schema,
    Slash, Widgets (.lua). No "Only in" line.
diff -rq <scratch>/LibKa0s libs/LibKa0s                        -> the same 15 lines (bytes == content)
diff -rq --strip-trailing-cr <scratch>/testkit tests/_kit
    README.md, framework.lua, mock_base.lua, mock_record.lua, run-automated-tests.sh, test_eol.lua,
    test_layout_cap.lua, test_prose.lua differ
    Only in <scratch>/testkit: asserts.lua, mock_events.lua, prose_lists.lua
diff -rq <scratch>/testkit tests/_kit                          -> the same 11 lines
```

Content is dirty in both payloads for the expected reason, a newer tag. There is no `Only in
libs/LibKa0s` or `Only in tests/_kit` line, so nothing was removed upstream and nothing is deleted
here. There is no content-clean, bytes-dirty drift.

After the copy (`rm -rf` both folders, then `cp -r` from the extracted tag), `diff -r
<scratch>/LibKa0s libs/LibKa0s` and `diff -r <scratch>/testkit tests/_kit` both print nothing, and
`test -x tests/_kit/run-automated-tests.sh` holds.

## 3e — Consumption map

```
grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'   (libs/ and tests/ rows dropped)
  core/CoreSetup.lua:67          Core
  core/EnvSetup.lua:61           Env
  core/Compat.lua:35             Compat
  core/Constants.lua:63          Bus      (NS.MSG's Catalog, adopted at ae286ce)
  core/PoolSetup.lua:38          Pool
  core/MediaSetup.lua:57         Media
  core/DebugLogSetup.lua:41      DebugLog
  core/LifecycleSetup.lua:50     Lifecycle
  core/LauncherSetup.lua:61      Launcher
  core/PerfSetup.lua:33          Perf
  settings/OptionsSetup.lua:90   Options
  settings/Slash.lua:55          Slash
  modules/IconGrid.lua:581       Widgets
  modules/Castbar_Handle.lua:41  Widgets
  settings/Spells.lua:829        Widgets
  settings/Spells.lua:1141       Widgets  (the Spells page's ReorderList)
```

This addon consumes thirteen majors. Unadopted in the payload: Schema (adoption is plan item
**KC-18**) and Item (reached inside the library only).

## 3f — Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/testkit/framework.lua tests/_kit/framework.lua` -> **26** at the tag,
**25** vendored before the copy. Both payloads are copied whole in one commit, so the pairing rule
(LibKa0s v1.9.0 or newer takes kit revision 11 or newer in the same commit) holds by construction.
That rule is why the two payloads move together.

## 3g — Contract delta

The majors that both moved a minor (3c) and are looked up here (3e): Core, Lifecycle, Bus, Media,
Widgets, DebugLog, Slash, Launcher, Options and Perf. Each old document's `Superseded by` row, read at
the tag:

| Major | Old -> new document | What moved |
|---|---|---|
| Core | `Core/version-7-docs.md:15` -> version 8 | `Format` survives a secret in a numeric slot; the `SafeRegisterEvent` family is added |
| Lifecycle | `Lifecycle/version-1-docs.md:15` -> version 2 | documentation and pins only; "the code is unchanged" |
| Bus | `Bus/version-1-docs.md:15` -> version 2 | the tracking wrappers are re-stamped at every edge after a newer AceEvent-3.0 re-embed |
| Media | `Media/version-3-docs.md:15` -> version 4 | `RegisterLSM` flags the face western + ruRU and counts only what LSM holds |
| Widgets | `Widgets/version-9.2-docs.md:15` -> 10.2 | a `ReorderList` drag polls on the ghost, not the host's row frame, and takes its line from a library free list; `Finish` returns nothing |
| DebugLog | `DebugLog/version-12-docs.md:15` -> version 13 | the buffer trim is batched at the cap; `#buffer` may run 64 past it |
| Slash | `Slash/version-14-docs.md:15` -> version 15 | `CliSet` / `CliReset` print the write seam's refusal |
| Launcher | `Launcher/version-1-docs.md:15` -> version 2 | optional `isEnabled` / `disabledLine`; the missing-library notice prints once, without the `[LibKa0s] ` prefix |
| Options | `Options/version-23.30.3.7.3-docs.md:16` -> 24.31.4.7.4 | `CreateOptionsPanel` parks in combat and replays at `PLAYER_REGEN_ENABLED`; `OpenOptionsPanel` answers a boolean; the drag throttles keep their own armed flag (OptionsWidgets 31); `RenderTabbedSchema` moves to `OptionsTabs.lua` and takes `opts`; the banner chrome is Released per render |
| Perf | `Perf/version-12.5-docs.md:16` -> 13.5 | `armed` / `recording` / `label` hold `false`, never nil; the open depth resets at window edges |

**Bound to what this addon hands over.** `grep -rn '__Attach[A-Za-z]*' . --include='*.lua'
--exclude-dir=libs --exclude-dir=_kit` -> one hit, `settings/Panel.lua:592`, a comment explaining why
the `LSMValues` shadow returns a closure for `lib.__AttachCompose`. OptionsCompose stays at minor 7,
so that contract does not move. The host-supplied members the moved contracts can reach:

- **Options `scheduleTimer`.** `settings/OptionsSetup.lua:243` passes `C_Timer.After`, which answers
  nil. Under OptionsWidgets 31 the slider and color-picker drag throttles keep their own armed flag,
  so this host now gets the 50 ms throttle it was missing (review finding `KICKCD-R-19`). An
  improvement that arrives without being asked for. KC-10 still gives the member a real handle.
- **Options `CreateOptionsPanel`.** `core/KickCD.lua:90` calls it once from `OnEnable`, with no park
  of its own, so nothing needs deleting (`options-ui-§9`, standard v2.65.0: a host MUST NOT add its
  own park). The addon's own combat refusals (`core/KickCD.lua` `NS:OpenSettings`,
  `settings/Panel_Widgets.lua` `refusedInCombat`) guard an **open**, which the library still never
  defers, so they stand.
- **Widgets `ReorderList`.** `settings/Spells.lua:1143` builds it and `:1176` calls `Finish` without
  reading its return, so the minor 10 change (`Finish` returns nothing) reaches nothing here. The
  drag now polls on the library's ghost frame and no longer overwrites a row frame's `OnUpdate`. KC-12
  pins the drag.
- **Slash `set`.** `settings/Slash.lua:378` routes to `SetAndRefresh` and returns nothing, so there
  is no refusal for minor 15 to print. No change.
- **Perf.** No host code reads `recording` / `armed` / `label` against nil (the suite is green, see
  below). KC-14 owns the nesting on the Rebuild path.

### Blockers

**None.** No host-supplied member's call site moved in a way that breaks this addon.

**Suite at the RV commit.** The RV commit is copy-only: it carries the payload, the provenance line
and this bundle, and nothing else (spec Part B). KC-01 (`5adf126`) cleared the reds the library's
release dry-run predicted for KickCD before this copy, so the stricter kit and library turn nothing
red:

- `ka0s-bounded lua5.1 tests/run.lua` -> **1051 passed, 0 failed, 0 skipped, 1051 total**.
- `ka0s-bounded luacheck .` -> 0 warnings / 0 errors in 101 files.
- `ka0s-bounded lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` -> no thresholds exceeded; no
  function above CCN 15.

## 3h — Tags this addon vendored and never recorded

The 3h listing, run before this commit, with horizon `2026-08-25`, prints **29** tags:

```
v1.16.0 v1.17.0 v1.18.0 v1.18.1 v1.19.0 v1.23.0 v1.24.0 v1.26.0 v1.27.0 v1.28.0 v1.29.0 v1.35.0
v1.36.0 v1.36.1 v1.36.2 v1.37.0 v1.38.0 v1.39.0 v1.42.0 v1.43.0 v1.44.0 v1.45.0 v1.46.1 v1.47.0
v1.50.0 v1.51.0 v1.52.0 v1.53.0 v1.54.2
```

Recorded, by the same listing: v1.15.0, v1.25.0, v1.30.0 to v1.34.0 and v1.55.0.

**Not written here.** The consolidated span bundle is plan item **KC-24**, and this commit may touch
only `docs/revendor/2026-09-23-v1.56.0/` (spec Part B). KC-24's item text says 25 tags, v1.18.0 to
v1.53.0. This listing also prints v1.16.0, v1.17.0 and v1.54.2, so KC-24 should re-derive its tag
list rather than trust the count. v1.56.0 is recorded by this bundle.
