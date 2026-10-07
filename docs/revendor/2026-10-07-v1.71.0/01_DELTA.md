Delta: LibKa0s v1.70.0 -> v1.71.0

Run non-interactively by item `RV-KC` of the 2026-10-07 review and standards-audit remediation, on
branch `feat/2026-10-07-review-audit-remediation`, following the local `../dev-copilot`
`wow-revendor-libka0s` procedure by hand. The owner's scope ruling 5
(`Ka0sAddonsCommonTasks/docs/2026-10-07-REVIEW_AND_STANDARDS_AUDIT_REMEDIATION/inputs/OWNER_SCOPE.md`)
makes the re-vendor mechanical: both payloads copied whole, the provenance line rolled, this bundle
written, and every adoption candidate listed as "not adopted in this run" with no interview and no
GitHub issue.

## Source

```sh
git -C ../LibKa0s tag -l v1.71.0                        # v1.71.0 (LOCAL tag; not pushed in this run)
git -C ../LibKa0s rev-parse --short 'v1.71.0^{commit}'  # cb274a4 (annotated)
git -C ../LibKa0s archive v1.71.0 LibKa0s testkit | tar -x -C <scratch>/v1.71.0
```

The payload is taken from the tag through `git archive`, never from the library's working tree.

## Base (3a, 3b)

```sh
grep -n 'Bundles \[LibKa0s' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.70.0 (MIT).   (before the roll)
git log -1 --format='%h %s' master -- libs/LibKa0s tests/_kit
# 9d4a10b chore: re-vendor LibKa0s v1.70.0
git -C ../LibKa0s archive v1.70.0 LibKa0s testkit | tar -x -C <scratch>/v1.70.0
diff -rq <scratch>/v1.70.0/LibKa0s libs/LibKa0s && diff -rq <scratch>/v1.70.0/testkit tests/_kit && echo base-matches-v1.70.0
# base-matches-v1.70.0
```

Base v1.70.0, agreed by the provenance line, the last payload commit and the bytes. No base
correction is owed. The two tags before it (v1.69.0, v1.70.0) were vendored without a bundle; they
are recorded by the span bundle `../2026-10-07-v1.69.0-v1.70.0/`, written in the same commit (3h).

## Range

```sh
git -C ../LibKa0s log --oneline v1.70.0..v1.71.0 | wc -l   # 20
diff -rq <scratch>/v1.70.0/LibKa0s <scratch>/v1.71.0/LibKa0s
#   Env.lua, OptionsIdList.lua, Slash.lua, SlashParse.lua, WidgetsAutocomplete.lua, WidgetsLineChart.lua differ
diff -rq <scratch>/v1.70.0/testkit <scratch>/v1.71.0/testkit
#   README.md, framework.lua, inventory.lua differ; Only in v1.71.0/testkit: secrets.lua
```

## Per-file minor delta (3c)

| File | Major | v1.70.0 | v1.71.0 |
|---|---|---|---|
| `WidgetsLineChart.lua` | `LibKa0s-Widgets-1.0` | 2 | **3** |
| `WidgetsAutocomplete.lua` | `LibKa0s-Widgets-1.0` | 1 | **2** |
| `Slash.lua` | `LibKa0s-Slash-1.0` | 19 | **20** |
| `SlashParse.lua` | `LibKa0s-Slash-1.0` | 1 | **2** |
| `Env.lua` | `LibKa0s-Env-1.0` | 1 | **2** |
| `OptionsIdList.lua` | `LibKa0s-Options-1.0` | 3 | **4** |

Composite keys: Widgets 12.1.4.2.1 -> **12.1.4.3.2**, Slash 19.1 -> **20.2**, Env 1 -> **2**,
Options 28.2.34.2.3.8.1.7.4.2 -> **28.2.34.2.4.8.1.7.4.2**. Every other file stays at its v1.70.0
minor (`../LibKa0s/CHANGELOG.md`, the `v1.71.0` block). No file is added to or removed from
`libs/LibKa0s/`, no `NEEDS_*` floor rises, no cross-major skew.

## Both diffs (3d), summarized

**Library payload** (six files):

- `WidgetsLineChart.lua` 3: every series segment is clipped to the plot rectangle before it is
  drawn (new pure `ChartMath.ClipSegment`); a render re-syncs the hover. KickCD draws no chart.
- `WidgetsAutocomplete.lua` 2: each `lib.Autocomplete` call re-installs the box's hooks under a new
  generation; `opts.maxRows` is floored; the list backdrop is set once. KickCD uses no autocomplete.
- `SlashParse.lua` 2: `ParseValue` refuses `nan`, `inf`, `-inf` and overflowing literals on a
  number row with `ERR_NUMBER`. `Slash.lua` 20 changes one comment citation only.
- `Env.lua` 2: `GetAddOnMetadata` no longer falls back to the bare `GetAddOnMetadata` global; it
  answers `C_AddOns.GetAddOnMetadata` or nil.
- `OptionsIdList.lua` 4: the help-art guard asks `C_AddOns.IsAddOnLoaded` only, never the bare
  `IsAddOnLoaded` global.

**Kit payload**: `framework.lua` (`Kit.VERSION` 38, loads `secrets.lua`, the `--list` renderer
moves out), `inventory.lua` (holds the renderer; Totals count only the cases that run, plus a
`| Skipped | N |` row), `README.md` (file table), and the new `secrets.lua` (`Kit.secret`,
`Kit.isSecret`, `Kit.reveal`, `Kit.installSecretValue`, `Kit.SECRET_ERROR`).

After the copy, `diff -r` of both payloads against the tag is empty, and
`tests/_kit/run-automated-tests.sh` keeps its executable mode.

## Consumption map (3e)

Fourteen majors are looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env,
Launcher, Lifecycle, Media, Options, Perf, Pool, Schema, Slash and Widgets. `Item` is not looked up
(the settled decline, issue #14). Of the moved files, KickCD reaches:

- **Env** (`core/EnvSetup.lua:74`, `Env.GetAddOnMetadata`). Every supported client has `C_AddOns`,
  so a live client sees no difference; the host's own `C_AddOns` fallback at `core/EnvSetup.lua:75`
  is untouched.
- **Slash `ParseValue`** through `/kcd set` (the shared write seam).
- **Options `O.IdList`** through the Spells editor (`settings/Spells_Header.lua`,
  `settings/OptionsSetup.lua`).

`WidgetsLineChart` and `WidgetsAutocomplete` are not used.

## Kit revision (3f)

```sh
grep -n 'Kit.VERSION =' <scratch>/v1.71.0/testkit/framework.lua   # Kit.VERSION = 38
grep -n 'Kit.VERSION =' <scratch>/v1.70.0/testkit/framework.lua   # Kit.VERSION = 37
```

Kit revision 37 -> 38. Both payloads move together in one commit (the pairing rule), by
construction of the whole-folder copy. No host prose names the kit revision it holds, so nothing
rolls 37 -> 38 under `docs/api/testkit/version-38-docs.md`'s Adoption note.

## Contract delta (3g)

Contract changes under signatures that did not move:

- **Slash `ParseValue` refuses `nan` / `inf` / `-inf` / `1e400` on a number row** (Slash 20.2).
  Delivered free to `/kcd set`: a typed non-finite value is now refused with the existing
  `ERR_NUMBER` reason instead of reaching the store. Class A (delivered on the re-vendor alone).
- **Kit `--list` Totals count only the cases that run** (kit 38). Delivered free: the regenerated
  `docs/test-cases.md` drops the diagnostics contract's declared opt-out skip from its suite row,
  gains `| Skipped | 1 |`, and its Total falls from 1303 to **1302**, equal to the README badge
  (1302/1302). This closes `KC-A-07` (the 2026-10-07 audit's `KICKCD-D-03`).
- **Env 2 / OptionsIdList 4** drop the bare-global rungs. No live-client difference.

### Blockers

One, mechanical, fixed host-side in this commit:

- `tests/test_list_mode.lua`'s case "--list Totals row equals the grand total of bullets" pinned
  revision 37's Totals semantics (Total == every listed bullet, declared skips included). Under
  revision 38 it failed `Totals row (1302) must equal bullet count (1303)`. It is replaced by
  "--list Totals row plus the Skipped row equals the grand total of bullets", which asserts the new
  contract no less strictly: the `Skipped` row equals the bullets the inventory marks
  `(skipped: ...)`, and Total plus Skipped equals every bullet. Nothing under `libs/` or
  `tests/_kit/` was edited and no assertion was weakened.

Also seen on the first gate run, not caused by the payload: `test_eol` flagged
`docs/audits/2026-10-07/01_CURRENT_STATE.md` and `02_DEVIATIONS.md` as LF on disk (the index was
already CRLF-correct). Both were repaired with `rm <path> && git checkout -- <path>`; no content
changed and nothing is committed for them.

## Unrecorded tags (3h)

v1.69.0 (`da8a8b8`) and v1.70.0 (`9d4a10b`) were vendored with no bundle (the 2026-10-07 audit's
`KICKCD-C-01`, `KC-A-01`). They are recorded by `../2026-10-07-v1.69.0-v1.70.0/`, written in the
same commit as this bundle.
