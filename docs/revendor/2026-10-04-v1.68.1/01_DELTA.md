Delta: LibKa0s v1.68.0 -> v1.68.1

Run non-interactively as `/dev-copilot:wow-revendor-libka0s KickCD --tag v1.68.1`, on branch
`feat/2026-10-04-revendor-libka0s-v1.68.1`. The owner pre-authorized the run and was not available
for an interview; any genuine decision would have stopped it. None arose. Written before the copy.

## Source

```sh
git -C ../LibKa0s rev-parse --short 'v1.68.1^{commit}'          # 9000cbd (annotated tag object 9fb7956)
git -C ../LibKa0s ls-remote --tags origin v1.68.1                # 9fb7956... refs/tags/v1.68.1 (pushed)
git -C ../LibKa0s rev-parse --short HEAD                         # 29e61d6 (the rename merge, after the tag)
git -C ../LibKa0s diff --quiet v1.68.1 -- LibKa0s testkit && echo clean   # clean
git -C ../LibKa0s archive v1.68.1 LibKa0s testkit | tar -x -C <scratch>/new
```

The payload is taken from the tag through `git archive`, never from the working tree.

## Pre-flight (Step 0)

```text
KickCD  2026-10-02-v1.68.0  base v1.67.0  vendored-before v1.67.0@18dc978  ok
```

Taken before this bundle was written. Every roster addon whose newest bundle is committed prints
`ok`. A row that prints `MISMATCH` with an empty `vendored-before` is a v1.68.1 re-vendor in flight
(this run's or another workflow's in its own checkout): its new `01_DELTA.md` is written, as the spec
orders, before the commit that carries the tag exists. That is a run in flight, not a misstated base.
No base correction is owed here.

## Base (3a, 3b)

```sh
grep -n '[Bb]undles' CLAUDE.md
# 42:Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.68.0 (MIT).
git log -1 --format='%h %s' -- libs/LibKa0s tests/_kit
# 18dc978 TP-KC-01: re-vendor LibKa0s v1.68.0 (WidgetsDragHandle 4; kit 35 unchanged)
git show 18dc978:CLAUDE.md | grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9.]+'   # ... v1.68.0
git log --format='%h %s' 18dc978..HEAD -- CLAUDE.md                            # (none)
git -C ../LibKa0s archive v1.68.0 LibKa0s testkit | tar -x -C <scratch>/claimed
diff -rq <scratch>/claimed/LibKa0s libs/LibKa0s && diff -rq <scratch>/claimed/testkit tests/_kit && echo payload-matches
# payload-matches
grep -hoE 'local (MAJOR, )?[A-Z_]*MINOR *= *("[^"]+", *)?[0-9]+' libs/LibKa0s/*.lua | wc -l   # 32, v1.68.0's
```

Base v1.68.0, agreed by the line, the last payload commit and the bytes.

## Range

```sh
git -C ../LibKa0s log --oneline v1.68.0..v1.68.1 | wc -l          # 7 (SD-FIN-01, DC-REN-01 .. DC-REN-05, a merge)
git -C ../LibKa0s diff --stat v1.68.0 v1.68.1 -- LibKa0s testkit
#  testkit/framework.lua          | 2 +-
#  testkit/run-automated-tests.sh | 8 ++++----
#  testkit/test_eol.lua           | 2 +-
#  3 files changed, 6 insertions(+), 6 deletions(-)
```

## Per-file minor delta (3c)

The 3c loop over the tag's `LibKa0s.xml` prints the same constant old and new for all 32 files. No
LibStub minor moves, no file is added or removed, no `NEEDS_*` floor rises. No cross-major skew. The
CHANGELOG `v1.68.1` block (`../LibKa0s/CHANGELOG.md:13-19`) states the same: "Every library file is
unchanged from v1.68.0".

## Both diffs (3d), before the copy

```sh
diff -rq --strip-trailing-cr <scratch>/new/LibKa0s libs/LibKa0s   # (empty)
diff -rq                     <scratch>/new/LibKa0s libs/LibKa0s   # (empty)
diff -rq --strip-trailing-cr <scratch>/new/testkit tests/_kit     # differ: framework.lua, run-automated-tests.sh, test_eol.lua
diff -rq                     <scratch>/new/testkit tests/_kit     # the same three
```

Content and bytes agree: three genuinely changed kit files, no line-ending drift, no `Only in` line,
so nothing to delete.

## Consumption map (3e)

Fourteen majors looked up outside `libs/` and `tests/`: Bus, Compat, Core, DebugLog, Env, Launcher,
Lifecycle, Media, Options, Perf, Pool, Schema, Slash and Widgets (4 sites: the two drag-strip hosts
and the two spell-list settings files). `Item` is not looked up, the settled decline in issue #14
(`state:will-not-do`: a spell-cooldown addon with no item concept); nothing in this range touches
its premise. Nothing moved under any consumed major.

## Kit revision (3f)

```sh
grep -n 'Kit.VERSION =' <scratch>/new/testkit/framework.lua tests/_kit/framework.lua
# new: Kit.VERSION = 36    vendored: Kit.VERSION = 35
```

Kit revision 35 -> 36. Both payloads move together in one commit (the pairing rule, required since
v1.9.0 / kit revision 11), by construction of the whole-folder copy.

## Contract delta (3g)

No library major moved a minor, so no `docs/api/<Major>/` document is in scope. The one document
that moved is the kit's:

```sh
diff <(git -C ../LibKa0s show v1.68.0:docs/api/testkit/version-35-docs.md) \
     <(git -C ../LibKa0s show v1.68.1:docs/api/testkit/version-36-docs.md)
```

"No public member is added, removed or renamed, no kit case is added, removed or renamed, no mock
changes, and the manifest the runner writes is unchanged" (`docs/api/testkit/version-36-docs.md:19-23`).
The one visible effect is the `RESULTS.md` lead-in the runner prints, which names
`/dev-copilot:bump-version` where revision 35 named `/wow-addon:bump-version` (`:35`, `:40-43`); this
addon's next automated-test run rewrites that line. What a consumer owes is the whole-folder copy,
the provenance line, and "own prose that names the revision it holds (`kit revision 35`) moves to 36
in the same commit" (`:58-60`).

`grep -rn '__Attach[A-Za-z]*'` outside `libs/` and `tests/_kit/` finds one hit, a comment
(`settings/Panel.lua:182`, the Compose seam's `LSMValues` note). No Options file moved, so nothing
it describes changed.

### Blockers

None.

## Unrecorded tags (3h)

The audit walk (payload commits plus provenance rolls since the store's first bundle, 2026-08-25)
lists 49 vendored tags against 49 recorded; the difference prints nothing. No span bundle owed.
