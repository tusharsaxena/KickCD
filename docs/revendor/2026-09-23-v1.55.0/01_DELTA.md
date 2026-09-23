# Re-vendor delta: LibKa0s v1.54.2 -> v1.55.0

Written before the copy (`revendor-libka0s` Step 3). Steps 2-4 only in this run: the copy, the
provenance line and the harness wiring land together; candidates and adoption (Steps 5-8) belong to
a later run and are not decided here.

Scratch extraction: `git -C ../LibKa0s archive v1.55.0 LibKa0s testkit | tar -x -C <scratch>/new`
(and `v1.54.2` into `<scratch>/old` for the old-tag comparison).

## Step 2: the tag

`git -C ../LibKa0s tag --sort=-v:refname | head -1` -> `v1.55.0`. The payload is taken from the
tag, not from the library's working tree.

## 3a. Claimed version

`grep -n '[Bb]undles' CLAUDE.md` ->

```
42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.54.2 (MIT).
```

## 3b. Actual version

`diff -rq --strip-trailing-cr <scratch>/old/LibKa0s libs/LibKa0s` and the same for
`<scratch>/old/testkit tests/_kit` both print nothing: the vendored bytes are exactly v1.54.2's.
Claim and fact agree.

## 3c. Per-file minor delta

File list read from the tag's `LibKa0s/LibKa0s.xml`; each minor by
`grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+'` on both sides.

| File | Vendored (v1.54.2) | Tag (v1.55.0) |
|---|---|---|
| `Core.lua` | Core 7 | 7 |
| `Env.lua` | Env 1 | 1 |
| `Compat.lua` | absent | **Compat 1 (new major)** |
| `Lifecycle.lua` | Lifecycle 1 | 1 |
| `Bus.lua` | absent | **Bus 1 (new major)** |
| `Schema.lua` | absent | **Schema 1 (new major)** |
| `Pool.lua` | Pool 3 | 3 |
| `Item.lua` | Item 1 | 1 |
| `Media.lua` | Media 3 | 3 |
| `Widgets.lua` | Widgets 9 | 9 |
| `WidgetsDragHandle.lua` | DRAG_MINOR 2 | 2 |
| `DebugLog.lua` | DebugLog 12 | 12 |
| `Slash.lua` | Slash 14 | 14 |
| `Launcher.lua` | Launcher 1 | 1 |
| `Options.lua` | Options 23 | 23 |
| `OptionsWidgets.lua` | WIDGETS_MINOR 30 | 30 |
| `OptionsTabs.lua` | TABS_MINOR 3 | 3 |
| `OptionsCompose.lua` | COMPOSE_MINOR 7 | 7 |
| `OptionsScroll.lua` | SCROLL_MINOR 3 | 3 |
| `Perf.lua` | Perf 12 | 12 |
| `PerfPanel.lua` | PANEL_MINOR 5 | 5 |

No existing file's minor moves. No cross-major skew. Three files are added.

## 3d. Both diffs (before the copy)

`diff -rq --strip-trailing-cr <scratch>/new/LibKa0s libs/LibKa0s` (content) and `diff -rq` (bytes)
report the same set:

- `Only in <scratch>/new/LibKa0s`: `Bus.lua`, `Compat.lua`, `Schema.lua`
- `LibKa0s.xml` differs (three new `<Script>` rows: `Compat.lua` after `Env.lua`, `Bus.lua` and
  `Schema.lua` after `Lifecycle.lua`; `diff -r <scratch>/old/LibKa0s <scratch>/new/LibKa0s`)

`diff -rq --strip-trailing-cr <scratch>/new/testkit tests/_kit` (content) and `diff -rq` (bytes):

- differ: `README.md`, `framework.lua`, `run-automated-tests.sh`, `test_eol.lua`, `test_prose.lua`
- `Only in <scratch>/new/testkit`: `test_layout_cap.lua`

No `Only in libs/LibKa0s` or `Only in tests/_kit` lines: nothing was removed upstream, so the copy
deletes nothing. Content and bytes agree, so there is no line-ending-only drift.

## 3e. Consumption map

`grep -rnoE 'LibStub\("LibKa0s-[A-Za-z]+-1\.0", true\)' . --include='*.lua'`, addon sources only
(libs/ and tests/ excluded):

| Major | Lookup site(s) |
|---|---|
| Core | `core/CoreSetup.lua:67` |
| Env | `core/EnvSetup.lua:61` |
| Lifecycle | `core/LifecycleSetup.lua:50` |
| Pool | `core/PoolSetup.lua:38` |
| Media | `core/MediaSetup.lua:57` |
| DebugLog | `core/DebugLogSetup.lua:41` |
| Launcher | `core/LauncherSetup.lua:61` |
| Perf | `core/PerfSetup.lua:33` |
| Slash | `settings/Slash.lua:55` |
| Options | `settings/OptionsSetup.lua:90` |
| Widgets | `modules/IconGrid.lua:581`, `modules/Castbar_Handle.lua:41`, `settings/Spells.lua:829`, `settings/Spells.lua:1141` |

Not looked up by the addon: `Item` (reached only through the library's own `OptionsWidgets.lua`),
and the three new majors `Compat`, `Bus` and `Schema`. The addon carries its own `core/Compat.lua`,
its own message bus and its own settings schema, so each new major is a whole-module (class C)
candidate for the adoption run, not for this one.

## 3f. Kit revision, and the pairing rule

`grep -n 'Kit.VERSION' <scratch>/new/testkit/framework.lua tests/_kit/framework.lua` ->
`Kit.VERSION = 25` (tag) against `Kit.VERSION = 24` (vendored).

The pairing rule (a consumer taking LibKa0s v1.9.0 or newer takes kit revision 11 or newer in the
same commit) is satisfied by construction: both payloads are copied whole, from the same tag, in one
commit, which is also what `tests/test_vendor_sync.lua` checks.

Revision 25 brings three things this repo must act on in the same commit, because the kit fails the
run until they are done:

- `tests/_kit/test_layout_cap.lua` arrives undeclared, and `Kit.assertSuiteInventory` fails the run
  on an undeclared kit suite. It is wired as `{ name = "test_layout_cap", dir = "tests/_kit/" }`.
- A declaration is now keyed by the pair (basename, directory). This repo already declared
  `test_prose` in the pair form; `test_eol` was declared as `root .. "/tests/_kit/"`, which the kit
  now reads against the runner's `dir` and accepts, and is respelled `"tests/_kit/"` so all three kit
  suites carry the one form `testing-§9` prescribes.
- `test_layout_cap` reads a `Files over the 1500-line cap` census under `## Documented deviations`
  in `docs/ARCHITECTURE.md`. It lands in a prep commit before this one, green on the old kit.

## 3g. Contract delta

**Majors to read:** those whose minor moved (3c: none) intersected with those this addon consumes
(3e). The intersection is empty. No existing `.lua` file in the payload changes a byte
(`diff -r <scratch>/old/LibKa0s <scratch>/new/LibKa0s` shows only the three new files and the XML).

The API documents under consumed majors that did change in this range
(`git -C ../LibKa0s diff --stat v1.54.2 v1.55.0 -- docs/api`) are `Widgets/version-9.1-docs.md` and
`Widgets/version-9.2-docs.md`. Both edits are header bookkeeping: 9.1's status becomes
`Superseded` with a `Superseded by` pointer to 9.2, and 9.2 gets the header rows it was missing. The
one behavior note (the help mark brightens on hover only where `onRightClick` is wired) describes
`WidgetsDragHandle.lua` minor 2, which shipped at v1.48.1 and is already vendored here. No sentence
under an existing surface changed meaning, and no new MUST appears.

`__Attach*` sites (`grep -rn '__Attach[A-Za-z]*' . --include='*.lua' --exclude-dir=libs
--exclude-dir=Libs --exclude-dir=_kit`): one hit, `settings/Panel.lua:592`, a comment about
`lib.__AttachCompose` reading `LSMValues` once at row-declaration time. `OptionsCompose.lua` is at
minor 7 on both sides, so that call site did not move.

### Blockers

None.
