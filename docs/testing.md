# Testing

A headless Lua unit harness lives under `tests/` — run `lua tests/run.lua` from the repo root (exits non-zero on any failure); `luacheck .` must stay at 0 warnings and 0 errors — the tree is clean on both counts, so any new warning is a regression, not background noise. The suites load every source under a WoW-API mock and assert pure logic, the message bus, the full `OnInitialize → OnEnable` cascade that AceAddon fires on `PLAYER_LOGIN` (via `test_lifecycle`), and the per-frame coalescing of the chatty `SPELL_UPDATE_*` events (via `test_cooldowns`). The harness draws nothing and cannot model taint, so it complements rather than replaces the in-game checks.

## Local toolchain

`lua` (5.1-compatible) and `luacheck` on `PATH` are the whole toolchain — no build step, and the only runner beyond `tests/run.lua` is the vendored `tests/_kit/run-automated-tests.sh`, which shells out to the same two commands. Both run from the repo root and are the green commit gate: run them before every commit, alongside the four vendored-copy diffs below (two pairs — the library and the test kit). `lizard` is a third, **optional** tool, driven by the non-gating `complexity` suite of that runner (see [Automated test records — the consolidated run](#automated-test-records--the-consolidated-run)).

Install instructions for all three, with the WSL2/Ubuntu commands that actually work, live in the root [DEPENDENCIES.md](../DEPENDENCIES.md). That file says *what to install*; this one says *how to verify*.

**Dual-path WSL.** `/home/tushar/GIT/KickCD/` and `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD/` are the same repo via symlink; either path works for git and for file tools. Line endings are CRLF everywhere by `.gitattributes` policy — see [common-tasks.md](common-tasks.md) — which is why the vendored-copy check below is two diffs rather than one.

## What is the harness, and what is KickCD's

The registry, the assertion set, the `skip` status, the suite-inventory gate, the `--list` renderer and the source loader are the **vendored kit's** (`tests/_kit/framework.lua`, `loader.lua`, `mock_base.lua` — copied verbatim from LibKa0s, never edited here; `tests/test_vendor_sync.lua` is the byte-identity gate). `tests/run.lua` holds only what is genuinely per-addon: the `libs/LibKa0s` load list, the instance factory `T.load`, and the suite list.

The kit **collects, then runs**: `test()` records a case and nothing executes until the runner decides to. This file's runner used to `pcall` each case body at registration time and short-circuit it under `--list`, which made the inventory a second code path through the same function and made "what has already happened when this case runs?" depend on where in its file the case sat. `--list` is now a pure filter over the registry and cannot disagree with the run.

One thing the kit's loader does not serve, and `tests/run.lua` supplies: almost every WoW-API read in this addon is written `_G.SomeAPI` (architecture-§1 forbids the deprecated bare globals, and the `_G.` prefix is what makes a Compat-bypassing read visible in review). The kit's per-chunk environment falls through to the process's real `_G`, which holds no client API — so `run.lua` publishes one kit-built environment as `mocks._G`, per instance, and `_G.X` resolves through the same mock table a bare `X` does.

## What the frame mock does and doesn't model

`tests/wow_mock.lua` layers KickCD's half over the shared base in `tests/_kit/mock_base.lua`, overwriting per key (it reassigns 29 of the base's 56 keys and inherits 27, none of which any addon source touches — the file's own header lists them). Its frame stub carries **real state** for the properties the addon's correctness depends on — visibility (`Show`/`Hide`/`SetShown`/`IsShown`, with `IsVisible` walking the parent chain), geometry (`SetPoint`/`GetPoint` round trip, size, scale with `GetEffectiveScale` as the product down the parent chain), alpha, text, color, and `StatusBar` min/max/value. Two C-side seams that accept 12.0 **secret values** are modeled deliberately, because they are the only correct way to branch on a secret: `Frame:SetAlphaFromBoolean` (which also records the raw flag, so a suite can prove the secret was passed through rather than read) and `C_CurveUtil.EvaluateColorValueFromBoolean`.

**Curve evaluation reads the control points.** `__makeDurationObject(remaining, total)`'s `EvaluateRemainingDuration` / `EvaluateTotalDuration` walk the curve they are handed and return the value of the last point at or below the queried time — neither returns a constant. The separate `total` is what lets a suite tell a GCD lockout from the tail of a real cooldown, which is the distinction the icon's alpha / tint / swipe-suppression curves are actually making (`tests/test_icongrid_gcd_classify.lua`). This is load-bearing for the same reason `IsShown` is: the addon's curves are per unit and built from config, so a stub that ignores the points makes "this icon used ITS unit's curve" and "this icon used some other unit's curve" the same observation. A per-unit curve regression shipped green through exactly that hole (see `tests/test_icongrid_curve_link.lua`); the fix was to model the evaluation, not to add more assertions on the curve objects.

This fidelity is load-bearing, not convenience. Against a blanket no-op stub, `IsShown()` returns the frame — permanently truthy — so "the grid hid itself" and "the grid did nothing" are the same observation, and every visibility mode looks alike; `SetText`/`SetValue` go nowhere, so the cast bar's whole render path is unobservable. Anything **not** in that list keeps a self-returning no-op, so unmodeled chains stay inert. `CreateFrame` also records every frame it builds; `mocks.__findFrame(event)` reaches a bootstrap frame that has no published handle (the `PLAYER_REGEN_*` listener in `core/State.lua`), so a suite can fire its `OnEvent` without widening the addon's public surface.

Where a module's decision logic is a file-local, it is published on the module purely so the harness can reach it — the idiom `Castbar.AutoSizeLong` established. Current examples: `Castbar.{UnpackColor,TruncateName,StateConfig,ToSetPoint,Fetch*,StructureSignature,ResolveBarSize}`, `IconGrid.{VisibilityMode,ShouldBeVisible,InstanceCasting,MasterEnabled,SafeUnpackColor,UnpackGlowColor,TriggerSatisfied,PlainStateMoved,CurvesFor,CurveSignature}`, `Cooldowns.{MaterialChange,StateChanged,MasterEnabled}` and `Spells.{ValidateSpellInput,SpecOrder,SortedKeys,TitleCaseToken,ClassDisplayName,GetSelection,SeedSelectionToPlayer,MoveTo}`. (`Helpers.SnapToStep` was on this list; step snapping is `LibKa0s-Options-1.0`'s now, and `tests/test_options_panel.lua` asserts the name does **not** come back.) Internal call sites keep using the locals; nothing in the addon calls through these fields.

`Castbar.ResolveGridFrame` looks like it belongs in that list but does **not**: `modules/Castbar_Skin.lua` genuinely calls it to resolve the auto-size reference frame, so it is a real cross-file dependency rather than a harness hook. Its comment says so, to keep a future dead-export sweep from mistaking it for one.

The **authoritative test count and per-suite breakdown** live in the generated inventory at [test-cases.md](test-cases.md) — never a hand-typed number here. Regenerate it (and see the current total) with `lua tests/run.lua --list > docs/test-cases.md`. `lua tests/run.lua --list` is a non-executing listing mode: it loads every suite, prints the full inventory to stdout, and exits without running a single test.

## Testing against the vendored library

`tests/run.lua` loads every `libs/LibKa0s/*.lua` file before any addon file, in
`LibKa0s.xml`'s own order — **derived from that XML** by `Loader.xmlFiles`, not
typed in the runner. The TOC pulls the library in through the one `.xml`, which
`Loader.tocFiles` deliberately skips, so this list used to be hand-maintained in
every runner in the collection; a short list does not raise, it just leaves the
dependent major unregistered, the host's setup file falling back to its stub, and
the suite happily measuring **the stub** — green, and testing nothing
(testing-§9).

`tests/test_coresetup.lua` pins the three things the derivation cannot guarantee
on its own: that the derived list is the one the runner actually **fed** the
loader and is not empty, that every path in it resolves on disk, and that the
TOC-derived addon list leaks no `libs/` entry back in (which would load a library
file twice, and out of XML order). The suite list is the third list testing-§9
names: `Kit.run` asserts it against `tests/test_*.lua` on disk in both directions
before it loads a single case, and `test_coresetup` calls
`Kit.assertSuiteInventory` again so the gate has a name in the inventory.

The degraded path is exercised by a **real load**, never by hand-stubbing:

```lua
local inst = T.load(true, false, nil, { libFiles = {} })   -- LibKa0s absent
```

`tests/test_surface_parity.lua` carries one `Kit.assertSurfaceParity` case per
adopted seam whose degradation stub answers members — Core (the namespace and the
printer), DebugLog, Slash (both `NS.Slash` and `NS.Slash.cli`) and Options —
comparing a live load against that degraded one and reporting **every**
divergence in one message (testing-§8, anti-pattern #56). It walks the LIVE
table, so the question is "what does the library export today?" rather than
"what did somebody remember to list": a re-vendor that adds a member forces a
decision. A member that is live-only *on purpose* is recorded in the case's
`ignore` list, as data, with the reason — the library's own string resolvers and
the widget makers and layout constants `options-ui-§1` forbids a host copy of.

What parity cannot catch is a stub with the right member set and a **wrong
implementation** — a hand-copied line format or ack string. That is
`debug-logging-§7`, and it stays with the source-scan cases in
`tests/test_debuglogsetup.lua`.

`tests/test_options_panel.lua` additionally pins `#NS.Settings.Schema` against
the fully-loaded environment — the only thing standing between the options stub
and a silent half-load — and exercises a **write** through the degraded settings
path (`SetAndRefresh` then `RestoreAllDefaults`), not only a read.

## Verifying the vendored copies

```
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s   # content — MUST be empty
diff -r ../LibKa0s/LibKa0s libs/LibKa0s                       # bytes  — SHOULD be empty
diff -r --strip-trailing-cr ../LibKa0s/testkit tests/_kit      # content — MUST be empty
diff -r ../LibKa0s/testkit tests/_kit                          # bytes  — SHOULD be empty
```

The payload carries **art as well as code** now: `libs/LibKa0s/media/` holds the shared
icon set and the JetBrains Mono face (this addon shipped its own copy of that face under
`media/fonts/` until the LibKa0s-Media adoption; it does not any more). `diff -r` recurses
into it, and `--strip-trailing-cr` is meaningless on a `.tga` or a `.ttf` — the plain
byte diff is the one that matters for those, so a re-vendor that dropped a texture shows
up in the second command and not the first.

Run **both** halves before every commit — they are different findings. Nothing about
"the tests are green" will tell you the copies have diverged: the library's suite
passes against the library, and this addon's passes against a stale copy that still
works.

**Content differs** → a real fork in `libs/`, the forbidden state. Name every hunk.

**Bytes differ but content matches** → a line-ending divergence, not a fork. Both repos pin
`* text=auto eol=crlf` with LF blobs, so a working tree holding *either* ending reads clean to
`git status` and neither side's cleanliness proves anything. Establish which side drifted
(`file -b <path>`, and `git cat-file -p HEAD:<path> | file -b -` for what git stores) and
renormalize it. **Re-vendoring will not converge it, and the fix is never an edit to `libs/`** —
that makes a fork nobody knows about, which the next re-vendor reverts silently. Not
hypothetical: the bare single-diff gate this block used to publish produced a false accusation
against the one consumer whose checkout was actually correct.

## Automated test records — the consolidated run

All four out-of-game suites go through one vendored runner, and every run is recorded
(`automated-tests`):

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --suite complexity          # a subset
tests/_kit/run-automated-tests.sh --suite lint --suite tests --no-bundle   # the green gate; writes nothing
```

There are **two checkpoints** — the run/commit and the tag — and a suite's answer differs between
them, so the table names both:

| Suite | Command | Gates the run and the commit? | Gates the tag? |
|---|---|---|---|
| `lint` | `luacheck .` | **yes** | **yes** |
| `tests` | `lua tests/run.lua` | **yes** | **yes** |
| `perf` | `lua tests/perf.lua` | no — recorded only | **yes** |
| `complexity` | `lizard -l lua -x "./libs/*" -x "./tests/_kit/*" .` | no — recorded only | **yes** |

**`perf` and `complexity` never fail a run and never block a commit** — they are measured, recorded
and diffed, not thresholded. A threshold that fails a run teaches everyone to reach for
`--no-verify`, after which the gate protects nothing and the habit remains. They contribute `amber`,
which is a signal rather than a stop.

**They do gate the tag.** The release gate requires all four suites at `pass` plus zero functions
above CCN 15, evaluated by `/wow-addon:bump-version` from the `manifest.json` the release run writes
— not by the runner, whose exit code is unchanged. **A missing tool is a skip recorded with its
reason**, never a pass: at the release gate a `skip` is NOT EVALUATED rather than passed, so install
the tool and re-run.

The runner is **vendored** from `LibKa0s`'s `testkit/`; never edit `tests/_kit/`. A kit fix goes
upstream and is re-vendored.

**At release, not at commit.** A full bundle is produced as part of every version bump, before the
tag, with an `ANALYSIS.md` write-up. Commits are gated on lint + tests only; the **tag** is gated on
all four suites at `pass` plus zero functions above CCN 15.

Results live in [`automated-tests/`](./automated-tests/): `RESULTS.md` is one row per run across all
four suites plus the current complexity watch list — **one file, overwritten in place**, so its git
history is the trend line — and each `<YYYYMMDD-HHMMSS>/` is a frozen bundle of that run's raw
output. Bundles are never edited and never pruned.

`docs/complexity.md` was this addon's standalone complexity report through standard v2.18.0; it is
**retired** — its raw output is each bundle's `complexity.txt` and its trend line is `RESULTS.md`.

## The source-scan guard

Most suites here assert on *behavior* — drive the real code, inspect what it produced. `tests/test_slash_style.lua` also does something different, and it's worth knowing why before writing another guard like it.

It enforces the no-trailing-colon chat rule (slash-commands-§4, see [common-tasks.md](common-tasks.md#chat-output)) two ways:

1. **Behaviorally** — drive `/kcd help`, `debug`, `spells`, and the three diagnostic dumps, then inspect every line that reached `DEFAULT_CHAT_FRAME`. New sub-headers under those paths are covered without anyone adding a case.
2. **By reading the sources** — scan every `.lua` under `core/`, `modules/`, `settings/`, `defaults/`, `locales/` for a string literal ending in `:` that closes a call.

The second exists because the first has a hole that is not fixable by adding more cases: **the mock's `UnitExists` returns false**, so both `Castbar:DebugDump` and `Compat.DebugInterrupt` take their early-return branch and their deep section headers are unreachable headlessly. Five real violations lived in exactly those branches. A behavior-only guard would have passed on all five, and the 2026-07-18 audit's grep missed them too because it only inspected the help printers.

The scan needs no exemption list. The one legitimate `:`-terminated literal closing a call is a **separator** argument (`table.concat(parts, ":")`), and it is distinguishable structurally: a separator is *exactly* `":"` with nothing before the colon, while a chat header always carries text. Flag a non-empty prefix and `curveSignature`'s concat stays legal on its own merits — no filename or function-name whitelist to rot.

`tests/test_perfsetup.lua` carries the second guard of this shape, for the **`L` trap**, and it is the sharper example of when the shape is mandatory. Every LibKa0s module taking an `L` override resolves the descriptor's table before its own `STRINGS`; `NS.L` answers *every* key with a string (the standard's mandated metatable fallback), so `L = NS.L` in a descriptor renders raw SCREAMING_SNAKE keys for every key at once — and only in game. **This addon shipped it**: a perf panel titled `Ka0s KickCDPANEL_TITLE_SUFFIX`. There is nothing to drive: a descriptor field is not observable after `lib:New` returns, so behavioral coverage is not merely inconvenient here, it is impossible.

The guard scans the five seam files, and the interesting part is what it matches on. It flags any `L =` whose value can **evaluate to** the locale table, not one spelling of it:

```
L = NS.L                     -- the table itself                        OFFENDER
L = NS.L or { ... }          -- NS.L is always truthy, so: the table    OFFENDER
L = NS.L and { ... } or nil  -- evaluates to the plain table            fine
```

That third form is this addon's real descriptor at `settings/Slash.lua`, so an `and` → `or` typo yields the live trap. The original pattern anchored `L = NS.L` to end-of-line and never looked at that line at all. Three inline assertions drive the matcher against all three spellings, because a matcher nothing tests can be narrowed back to a single anchored form while still reporting green — which is exactly how it got there.

That guard is no longer alone: every adopted major now carries the same shape in its own suite — `tests/test_slash.lua`, `tests/test_debuglogsetup.lua`, `tests/test_coresetup.lua` and `tests/test_options_panel.lua` alongside `tests/test_perfsetup.lua`. The Options one is shaped differently on purpose, and the difference is worth copying: `libs/LibKa0s/Options.lua` never reads a descriptor `L` at all, so the trap is not *expressible* for that major today and there is no rendered string to assert on. What it pins instead is that absence, by scanning all **three** files of the major — `Options.lua`, `OptionsWidgets.lua`, `OptionsScroll.lua` — so a future minor that grows an `L` hook reddens here rather than inheriting the trap silently. `OptionsWidgets.lua` is in that sweep because it is where the rendered labels actually come from, which makes it the likelier of the three to grow one.

Reach for this shape when a rule must hold in code the harness cannot enter — combat-only paths, branches gated on live game state, anything behind an API the mock stubs to a constant, and anything consumed by a library before it becomes observable. It is not a substitute for behavioral coverage; it is what you add when you can prove coverage is structurally impossible. Pair it with an in-game check where one exists — smoke-test §25 is the `L` trap's.

## Keeping the inventory & badge in sync

`docs/test-cases.md` and the README `Tests` badge are hand-maintained-in-lockstep coverage artifacts (Ka0s WoW Addon Standard, testing-§5). Whenever the suite changes — a case is added, removed, or renamed, or the pass count moves (i.e. whenever a failing test is resolved) — regenerate the inventory via `lua tests/run.lua --list > docs/test-cases.md` **and** update the README `Tests-X/Y_passing` badge count in the **same change**, never as a deferred follow-up. Verify the inventory is in sync with `diff <(lua tests/run.lua --list) docs/test-cases.md` (no output = clean).

For end-to-end test scenarios — fresh install, visibility modes, lock/drag, cast bar auto-size, spec/talent/pet rebuilds, profile lifecycle, secret-value safety, etc. — see [smoke-tests.md](smoke-tests.md). The matrices below catalog what each slash and debug command produces; they're the reference the smoke tests lean on.

## Slash command coverage

- `/kcd` — print the slash command help. `/kickcd` is a long-form alias that routes to the same handler. Every printed line should carry a cyan `[KCD]` prefix (added by `Util.print`); each help row should show the slash invocation in yellow and the description in white.
- `/kcd version` — print the addon version on its own line (`v<X.Y.Z>`), read from the TOC manifest with the in-code `NS.VERSION` stamp as fallback. Covered headlessly by `test_version`.
- `/kcd config` — open the settings panel. Refuses during combat (the Blizzard category-switch is protected); user gets a one-line print instead. `/kcd options` is an alias.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the shared icon grid + cast bar lock state. Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes.
- `/kcd list` — dump every schema-driven setting grouped by panel, with current values. Useful for "did the panel/slash share state?" spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every schema row. `path` is the dotted `db.profile` path (`enabled`, `units.target.icons.primarySize`, `units.target.icons.cooldownTint` …). `set` parses by `def.type`: bool accepts `true/false/on/off/1/0`; number is clamped to `[min, max]`; string must match a `values[i].value` (rejection prints the option list, plus `(depends on <gate> = ...)` when the row carries a `valueGate`); color takes 3–4 floats (`r g b [a]`, each clamped to `[0, 1]`). On success, any open panel re-syncs its widgets via `Helpers.RefreshScalars()` — a value write changes what a widget *shows*, so it must never rebuild the page under a slider or swatch mid-drag; `RefreshAllPanels` is reserved for structural changes (a profile switch, the Units tab's link toggle).
- `/kcd reset <path>` — reset **one setting** to its default, through the same `Helpers.SetAndRefresh` write seam `set` uses (a table default is `DeepCopy`'d, so two profiles resetting to the same RGBA don't share a table). Page-scoped reset lives only on each panel's **Defaults** button now; the five retired page names (`general` / `icons` / `castbar` / `label` / `spells`) each answer with a line naming where their capability went rather than a bare "Setting not found".
- `/kcd resetall` — reset the **active profile** to the shipped defaults (`options-ui-§12`): every panel, every anchor, every unit's `link` flag and every spec's spell list come back with it, because all of them live in the profile. Mirrors the General → "Reset all settings" popup but with no CLI confirmation prompt. Other profiles are never touched, and the profile *list* is untouched.
- `/kcd resetposition` — restore the icon grid to its default screen position. Mirrors the General → "Reset position" button.
- `/kcd spells <subcmd>` — per-class+spec spell-list editor (CLI parity for the Spells panel). Subcommands: `list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`, `resetall`. Every subcommand accepts an optional trailing `[CLASS SPEC]`; both default to the player's current spec when omitted. Note: `/kcd spells reset` rebuilds **one** spec's list, while `/kcd spells resetall` (the new home of the old `/kcd reset spells`) calls `Database:ResetAllSpells` and rebuilds every spec's.
- `/kcd perf` — the guided A/B performance capture (`LibKa0s-Perf-1.0`, wired in `core/PerfSetup.lua`), driven from a clickable step panel. `perf` is a **reserved verb across the collection** and is registered by the addon, never by the library: the lib returns lines and `core/KickCD.lua` prints them through the tagged printer. Records land in the `KickCDPerfDB` saved variable, stamped with the TOC version so a capture is attributable once it leaves the session. The instrumented path is `iconApply`; `NS.Perf.suspended` is consulted by the two show decisions so a capture doesn't measure itself.

## Debug subcommands

Continuous debug output does **not** go to the chat frame. It routes through the `NS.Debug(tag, fmt, ...)` sink (gated on the session flag `NS.State.debug`) into the on-screen debug console — the DIALOG-strata "Ka0s KickCD — Debug" window `LibKa0s-DebugLog-1.0` builds from the descriptor in `core/DebugLogSetup.lua`. The enabled flag is session-only: default off, never persisted to SavedVariables (there is no `db.profile.debugLog` field and no General → "Debug" checkbox), and it resets each `/reload`. The structured `spells|castbar|interrupt` dumps below are still printed to chat.

- `/kcd debug window` — toggle the on-screen debug console window (ScrollingMessageFrame, a title-bar `copy` / `clear` / `close` trio drawn from the shared LibKa0s icon set, header Debug:ON/OFF toggle, the JetBrains Mono face out of the vendored LibKa0s payload). This is where `NS.Debug` output lands.
- `/kcd debug on` / `/kcd debug off` / `/kcd debug toggle` — set / clear / flip the session-only debug flag `NS.State.debug` via the single write seam `DebugLog:SetEnabled(on)`. Off by default; not persisted; resets each `/reload`.
- `/kcd debug spells` — dump (to chat) the watched cooldown list with `ready / active / cdObj / chargeCdObj / charges` per spell. `cdObj=yes` means a full-cooldown duration object is held; `chargeCdObj=yes` means a charge-recharge timer is ticking while the spell is still castable. We deliberately do NOT print remaining time — `:GetRemainingDuration()` is secret in combat and `tostring` would error in tainted scope; charges are also secret-safed via a `safeStr` placeholder.
- `/kcd debug castbar` — print (to chat) one unit's cast state plus the configured/live per-state colors and `notInterruptible`'s type/secret-status (`Castbar:DebugDump(unit)`, defaulting to `target`). Uses `type()` and `issecretvalue()` rather than `tostring` so a secret-tainted record doesn't error the dump.
- `/kcd debug interrupt` — dump (to chat) every `UnitCastingInfo` / `UnitChannelInfo` position with `type()` and `issecretvalue()` flag, plus what `NS.State.IsHostileUnitCasting("target")` and the addon-wide visibility / glow-trigger logic decided. The reference for diagnosing 12.0 secret-value handling drift (especially regressions in the `target_casting_interruptible` mode where `notInterruptible` cannot be inspected from Lua). Reads safely via the `safeRender` helper that short-circuits secret values to `<secret>`.

## In-game spot checks

The end-to-end scenarios that used to live here — interrupt-on-hostile, visibility-mode matrix, drag/reload persistence, spec / talent / pet rebuilds, cast bar auto-size — are now part of the comprehensive suite in [smoke-tests.md](smoke-tests.md). Run that file before claiming a non-trivial change works.
