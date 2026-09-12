# 02 — Candidates: LibKa0s v1.29.0 → v1.30.0

```
git -C ../LibKa0s log --oneline v1.29.0..v1.30.0
e369e0f The v1.30.0 release record, re-taken on the review-fixed tree
e5f6906 Kit 16 review: double release raises, the release wipe, RegisterEvent validates, a per-build event registry
aaef20a The v1.30.0 release record
7aaf1fe Kit 16: AceGUI:Release, AceEvent's event half on an embed, Printf, and the runner's mode in every consumer
```

Sources: the `v1.30.0` block of the tag's `CHANGELOG.md` and
`docs/api/testkit/version-16-docs.md`. No major under `LibKa0s/` moved its minor, so there is no
`docs/api/<Major>/` diff to read and no class B or class C candidate from the shipped library.

All four changes are kit revision 16, in `tests/_kit/`.

## A — Reached this addon on the re-vendor alone

**#28, the runner's recorded mode (`vendor_sync.lua`).** `VendorSync.register` now adds the case
`the automated-test runner is recorded executable (100755)` (automated-tests-§2).
`tests/test_vendor_sync.lua` already delegates to `register`, so the case arrived with the copy and
passes: the total moved **870 → 871**. The addon's own rule moves the README `[Tests]` badge and
`docs/test-cases.md` in the same commit. The header of `tests/test_vendor_sync.lua` said the
consumer's case names keep the count fixed. It now also names the one case the kit adds.

## Inert here — the local harness replaces the kit's Ace layer

KickCD's `tests/wow_mock.lua` starts from the kit base (`dofile` at `:44`, `kitMockBase()` at
`:472`), then builds its own `libs` table (`:807`) and its own `mocks.LibStub` (`:846`). Every Ace
library the addon resolves comes from that table, never from the kit's fakes. So the three kit
fixes below cannot reach this suite:

| Kit change | KickCD's local version | Why it is inert |
|---|---|---|
| **#27** `AceGUI:Release` + `widget:Release` | `makeAceGUI` at `tests/wow_mock.lua:782` has no `Release` | Production calls it only behind a guard (`settings/Spells.lua:828`, `if w and w.Release then w:Release() end`), so the headless path skips it silently. |
| **#29** AceEvent's event half on an Embed | `embedAceEvent` at `tests/wow_mock.lua:493`; the event half is three no-ops at `:510-513` | The local embed is what every `NewAddon` target, module and `NS.NewBusTarget()` gets. Nothing is recorded and nothing is validated. |
| **#30** `Printf` beside `Print` | `embedAceConsole` at `tests/wow_mock.lua:526` stamps a no-op `Print` at `:529` and no `Printf` | The addon never calls `Printf`, and it publishes its printer at `NS.Util.print`, not `NS.Print`, so there is nothing for `NewAddon` to clobber. |

**There is no local shim to delete.** None of these is a copy of the kit's contract that the kit now
makes redundant. Each is a piece of a local Ace layer that replaces the kit's layer wholesale.

**The candidate is the harness migration:** adopt the kit's `NewAddon` / AceEvent / AceGUI /
AceConsole fakes in place of the local `libs` table. That is not additive. The kit's `NewAddon`
(`mock_base.lua`) has no `NewModule` / `GetModule` / `__enableAll`, which KickCD relies on
(`tests/wow_mock.lua:567-586`). The local bus resolves method-name strings through
`resolveCallback` (`:496`). `tests/test_state.lua:103` calls the local-only
`mocks.__embedAceEvent`. The migration replaces code the addon owns and would touch most suites.
Recommendation: **decline for this run** (see `03_DECISIONS.md`).
