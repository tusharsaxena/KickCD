# 04 - Execution plan

Written before any code moved. One candidate per commit (C2 is two commits, in the spec's sequence).
Every commit is gated on `ka0s-bounded lua tests/run.lua` and the bounded lint run, both green, from the
repo root. A candidate that cannot go green is rolled back to its commit boundary and reported.

## C1. Compat (one commit)

**Characterization first (green on the current code, committed in the same commit as the change):**

- `GetSpellCooldown` answers exactly five values on every branch (modern, nil info, legacy, absent) -
  `select("#", ...)`.
- `GetSpellInfo` takes a string identifier and hands back position 6 (`spellID`), the read
  `settings/Spells.lua:281` and `core/KickCD.lua:580` depend on.
- The secret-gated call sites behave the same through the seam. Covered already, each by a case that
  swaps `mocks.issecretvalue`: `tests/test_cooldowns_gates.lua` (StateChanged / MaterialChange),
  `tests/test_castbar_helpers.lua:97` (truncateName), `tests/test_icongrid_buildlist.lua:204`
  (applySpellTexture), `tests/test_icongrid_glowgate.lua:108,125` (resolveInterruptible),
  `tests/test_castbar_debug.lua:28`, `tests/test_compat_debug.lua:25`. They run green before and must run
  green after. What they cannot see is whether a module still reads the global itself, so a source-scan
  case pins that no authored file outside `core/Compat.lua` calls `issecretvalue`.

**Then the change:** `core/Compat.lua` resolves `LibStub("LibKa0s-Compat-1.0", true)`; the five readers
become `CompatLib and CompatLib.X or <absent answer>`; `Compat.IsSecret` is the library's or the guard
stub; the 12 inline calls become `NS.Compat.IsSecret(x)` (the one at `core/Compat.lua:86` goes with the
body).

**Tests that move with the change (the behavior the spec changes on purpose):**

- `tests/test_compat_api.lua:218-224`: the legacy fixture becomes `"Legacy", nil, 9, 1.5` (the global's
  real shape); the assertions stay.
- New: legacy `isEnabled == 0` reads disabled; `GetSpellTexture` answers one value when the client
  answers two; `GetSpecializationInfo(nil)` answers nil without calling the client.
- New: `IsSecret` is the library's member when the payload is present, and answers a strict boolean.
- New degraded-load case (`libFiles = {}`): every wired reader answers the absent table
  (`nil` / `0, 0, false, 1, false`) with the client API present, and the guard stub answers the same as the
  library under the same `issecretvalue` fixture.
- `tests/test_surface_parity.lua`: `assertSurfaceParity(degraded.NS.Compat, "LibKa0s-Compat-1.0", ignore)`,
  `ignore` = `CanAccess`, `IsSafeKey`, `GetSpellName` (the major's members this host does not wire).
  `tests/run.lua`'s `Kit.setSurfaceSource{}` gains the `["LibKa0s-Compat-1.0"]` row (the live mock's
  library table).

**Docs:** `docs/compat-layer.md` rows for the routed members point at the library; `docs/ARCHITECTURE.md`
External dependencies counts the major and names `core/Compat.lua` as its seam.

## C2a. Bus, declare-once table (one commit)

**Characterization first:** a case that every declared constant's value is the wire string the modules
used before the sweep (the five `Ka0s_KickCD_<SCREAMING_SNAKE>` strings), and a source-scan case that no
authored file types a `Ka0s_KickCD_` literal at a `SendMessage` / `RegisterMessage` / `UnregisterMessage`
call. The scan goes red before the sweep and green after. The existing sender/receiver cases
(`test_bus`, `test_lifecycle`, `test_state`, `test_cooldowns`, `test_units`, ...) are the proof the wiring
still connects.

**Then:** `NS.MSG` in `core/Constants.lua`, each key with its one sender named in a comment; the 23
literal lines move onto it; the test files that type a literal read the constant instead.

## C2b. Bus, PascalCase + `Catalog` (one commit)

**Then:** the five values in the one table become `Ka0s_KickCD_<PascalCase>`; the table is wrapped in
`Bus.Catalog("KickCD", MSG)` when the major resolves, the plain table when it does not.

**Tests:** the value pins move to the new strings; new cases pin that `NS.MSG` raises on an undeclared
key with the payload present, and that a degraded load publishes the plain table with the same keys and
values. `docs/ARCHITECTURE.md` `## Message bus` names the major and the new wire strings;
`docs/message-bus.md` and every live doc that quotes a wire string follow. Frozen bundles
(`docs/audits`, `docs/reviews`, `docs/automated-tests/<stamp>`, earlier `docs/revendor/<date>`) and the
README's version history are history and are not rewritten.

## C3. Schema

Declined (#22); no code.

## End

Regenerate `docs/test-cases.md` from `lua tests/run.lua --list` and move the README Tests badge in the
same commit as each count change (testing-section-5 lockstep), then commit this bundle.

## As executed

- The plan held. Every commit went through the green gate before it landed; the counts are in
  `05_SUMMARY.md`.
- C1: the two characterization pins ran green on the old code (1035). The code change then failed only
  the legacy `GetSpellInfo` fixture the spec names (1034 passed, 1 failed). The fixture was corrected
  and the new cases were added.
- C2a: the test files moved from literals to constants in this commit rather than in C2b, so C2b only
  had to change the one table and the pins. The subscription-map pin and the key-to-wire pin still
  spell the wire names on purpose.
- C2b: the stale quote in `.luacheckrc` (the `OnSpellState` registration) was brought up to date with
  the constant form and its current line.
