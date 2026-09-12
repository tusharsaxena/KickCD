# Testing

A headless Lua unit harness lives under `tests/` — run `lua tests/run.lua` from the repo root (exits non-zero on any failure); `luacheck .` must stay at 0 warnings and 0 errors — the tree is clean on both counts, so any new warning is a regression, not background noise. The suites load every source under a WoW-API mock and assert pure logic, the message bus, the full `OnInitialize → OnEnable` cascade that AceAddon fires on `PLAYER_LOGIN` (via `test_lifecycle`), and the per-frame coalescing of the chatty `SPELL_UPDATE_*` events (via `test_cooldowns`). The harness draws nothing and cannot model taint, so it complements rather than replaces the in-game checks.

## Local toolchain

`lua` (5.1-compatible) and `luacheck` on `PATH` are the whole toolchain — no build step, and the only runner beyond `tests/run.lua` is the vendored `tests/_kit/run-automated-tests.sh`, which shells out to the same two commands. Both run from the repo root and are the green commit gate: run them before every commit, alongside the four vendored-copy diffs below (two pairs — the library and the test kit). `lizard` is a third, **optional** tool, driven by the non-gating `complexity` suite of that runner (see [Automated test records — the consolidated run](#automated-test-records--the-consolidated-run)).

Install instructions for all three, with the WSL2/Ubuntu commands that actually work, live in the root [DEPENDENCIES.md](../DEPENDENCIES.md). That file says *what to install*; this one says *how to verify*.

**Dual-path WSL.** `/home/tushar/GIT/KickCD/` and `/mnt/d/Profile/Users/Tushar/Documents/GIT/KickCD/` are the same repo via symlink; either path works for git and for file tools. Line endings are CRLF everywhere by `.gitattributes` policy — see [common-tasks.md](common-tasks.md) — which is why the vendored-copy check below is two diffs rather than one.

## What is the harness, and what is KickCD's

The registry, the assertion set, the `skip` status, the suite-inventory gate, the `--list` renderer and the source loader are the **vendored kit's** (`tests/_kit/framework.lua`, `loader.lua`, `mock_base.lua` — copied verbatim from LibKa0s, never edited here; `tests/test_vendor_sync.lua` is the byte-identity gate). `tests/run.lua` holds only what is genuinely per-addon: the `libs/LibKa0s` load list, the instance factory `T.load`, the suite list, and the two guaranteed-run fixture wrappers described below.

The kit **collects, then runs**: `test()` records a case and nothing executes until the runner decides to. This file's runner used to `pcall` each case body at registration time and short-circuit it under `--list`, which made the inventory a second code path through the same function and made "what has already happened when this case runs?" depend on where in its file the case sat. `--list` is now a pure filter over the registry and cannot disagree with the run.

One thing the kit's loader does not serve, and `tests/run.lua` supplies: almost every WoW-API read in this addon is written `_G.SomeAPI` (architecture-§1 forbids the deprecated bare globals, and the `_G.` prefix is what makes a Compat-bypassing read visible in review). The kit's per-chunk environment falls through to the process's real `_G`, which holds no client API — so `run.lua` publishes one kit-built environment as `mocks._G`, per instance, and `_G.X` resolves through the same mock table a bare `X` does.

## Parking shared state: `T.withFocusLink` / `T.withViewedUnit`

Most suites run against **one shared instance**, so a case that changes session
state has to put it back. Doing that on the last line of the case body does not
work: the kit `pcall`s the body, so a case that goes red never reaches its own
last line and leaves the next case reading a fixture a *failure* set up.

Both pieces of state this comes up for are parked through the runner instead:

```lua
T.withFocusLink(true, function(cfg) ... end)   -- units.focus.link, restored always
T.withViewedUnit(function() ... end)           -- the shared Unit picker, restored always
```

Each parks the value, `pcall`s the body, restores, and re-raises the original
error at level 0 so the failure still points at the assertion that raised it.

They are a guarantee, not the repair of an observed break: `units.focus.link`
defaults to `true` (`defaults/Profile.lua:322`) and the viewed unit is written
without restore by every unit-page fixture, so a leak out of these cases reddens
nothing measurable today. Write new cases through the wrappers anyway — the first
case to render a Focus page without seeding the flag is the one that pays.

## What the frame mock does and doesn't model

`tests/wow_mock.lua` layers KickCD's half over the shared base in `tests/_kit/mock_base.lua`, overwriting per key (it reassigns 27 of the base's 60 keys and inherits 33). **LibStub and the Ace layer are the kit's** (#21): the strict LibStub, AceAddon with `NewModule` and the lifecycle, AceEvent's two CallbackHandler registries (the `(message, target)` fan-out, string methods, the recorded and validated event half, `mocks.__msgRegistry`, `mocks.__fireEvent`), AceConsole, AceTimer and AceGUI with `Release`. So every kit revision to them reaches this suite. The mock layers only what is KickCD's: its non-Ace library fakes and its AceDB, registered into `mocks.__libs`; the `SetHighlight` recorder, wrapped onto `AceGUI:Create`; `__enableAll`, one line over `AceAddon:EnableAddon`; and a `C_Timer` queue of plain functions drained by `__flushTimers`. Its frame stub carries **real state** for the properties the addon's correctness depends on — visibility (`Show`/`Hide`/`SetShown`/`IsShown`, with `IsVisible` walking the parent chain), geometry (`SetPoint`/`GetPoint` round trip, size, scale with `GetEffectiveScale` as the product down the parent chain), alpha, text, color, and `StatusBar` min/max/value. Two C-side seams that accept 12.0 **secret values** are modeled deliberately, because they are the only correct way to branch on a secret: `Frame:SetAlphaFromBoolean` (which also records the raw flag, so a suite can prove the secret was passed through rather than read) and `C_CurveUtil.EvaluateColorValueFromBoolean`.

**Curve evaluation reads the control points.** `__makeDurationObject(remaining, total)`'s `EvaluateRemainingDuration` / `EvaluateTotalDuration` walk the curve they are handed and return the value of the last point at or below the queried time — neither returns a constant. The separate `total` is what lets a suite tell a GCD lockout from the tail of a real cooldown, which is the distinction the icon's alpha / tint / swipe-suppression curves are actually making (`tests/test_icongrid_gcd_classify.lua`). This is load-bearing for the same reason `IsShown` is: the addon's curves are per unit and built from config, so a stub that ignores the points makes "this icon used ITS unit's curve" and "this icon used some other unit's curve" the same observation. A per-unit curve regression shipped green through exactly that hole (see `tests/test_icongrid_curve_link.lua`); the fix was to model the evaluation, not to add more assertions on the curve objects.

This fidelity is load-bearing, not convenience. Against a blanket no-op stub, `IsShown()` returns the frame — permanently truthy — so "the grid hid itself" and "the grid did nothing" are the same observation, and every visibility mode looks alike; `SetText`/`SetValue` go nowhere, so the cast bar's whole render path is unobservable. Anything **not** in that list keeps a self-returning no-op, so unmodeled chains stay inert. `CreateFrame` also records every frame it builds; `mocks.__findFrame(event)` reaches a bootstrap frame that has no published handle (the `PLAYER_REGEN_*` listener in `core/State.lua`), so a suite can fire its `OnEvent` without widening the addon's public surface.

Where a module's decision logic is a file-local, it is published on the module purely so the harness can reach it — the idiom `Castbar.AutoSizeLong` established. Current examples: `Castbar.{UnpackColor,TruncateName,StateConfig,ToSetPoint,Fetch*,StructureSignature,ResolveBarSize}`, `IconGrid.{VisibilityMode,ShouldBeVisible,InstanceCasting,MasterEnabled,SafeUnpackColor,UnpackGlowColor,TriggerSatisfied,PlainStateMoved,CurvesFor,CurveSignature}`, `Cooldowns.{MaterialChange,StateChanged,MasterEnabled}` and `Spells.{ValidateSpellInput,SpecOrder,SortedKeys,TitleCaseToken,ClassDisplayName,GetSelection,SeedSelectionToPlayer}`. (`Spells.MoveTo` left the list when the drag's splice became `Database:MoveSpell`, a real verb the harness calls directly.) (`Helpers.SnapToStep` was on this list; step snapping is `LibKa0s-Options-1.0`'s now, and `tests/test_options_panel.lua` asserts the name does **not** come back.) Internal call sites keep using the locals; nothing in the addon calls through these fields.

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
reporting **every** divergence in one message rather than the first
(testing-§8, anti-pattern #56). The question it asks is "what does the library
export today?" rather than "what did somebody remember to list": a re-vendor that
adds a member forces a decision. A member that is live-only *on purpose* is
recorded in the case's `ignore` list, as data, with the reason — the library's
own string resolvers and the widget makers and layout constants `options-ui-§1`
forbids a host copy of.

The three library-backed seams — DebugLog, Slash and Options — call the kit's
**by-name** form, `assertSurfaceParity(stub, "LibKa0s-Options-1.0", ignore)`:

* The live half is **named, not rebuilt**. `tests/run.lua` registers it with
  `Kit.setSurfaceSource`, and it has to be explicit — each of the three stubs
  mirrors an *instance* (what `lib:New(descriptor)` returned), not the library
  table `LibStub` answers for the same major, so `Kit.expose`'s auto-wiring would
  resolve the wrong thing and report members no stub was ever meant to carry.
* Only the **public** members are walked (`Kit.publicMembers`): `MAJOR`, `MINOR`,
  `MODULES` and every `__`-prefixed key are the library talking to itself across
  its own file boundary, and a stub does not mirror them. That rule is the kit's
  now, so a re-vendor that publishes a new internal needs no edit in this repo.
  The one exception is pinned by hand — `settings/Panel_Widgets.lua:138` calls
  `Helpers.__panelFor`, so the stub owes it and a line beside the parity call
  says so.

Core keeps the four-argument form (`assertSurfaceParity(live, degraded, label,
ignore)`) because `NS` and `NS.Util` are this addon's own namespace, not a
major's surface: there is no name to look up.

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
diff -r --strip-trailing-cr ../LibKa0s/LibKa0s libs/LibKa0s   # content — empty vs the CLAIMED tag
diff -r ../LibKa0s/LibKa0s libs/LibKa0s                       # bytes  — SHOULD be empty
diff -r --strip-trailing-cr ../LibKa0s/testkit tests/_kit      # content — empty vs the CLAIMED tag
diff -r ../LibKa0s/testkit tests/_kit                          # bytes  — SHOULD be empty
```

### When these diffs are supposed to be non-empty

They compare against the sibling checkout's **working tree** — whatever `../LibKa0s` happens to have
checked out — which is a different question from *"is the vendored payload the release this addon
claims?"*. The two questions give the same answer only while the library has tagged nothing newer
than the tag this addon has taken.

Between a library release and the re-vendor that carries it they disagree, and that disagreement is
the normal state rather than a defect. Re-vendoring to quiet them would be the actual mistake — it
would pull an untested library release for the sake of a clean diff. As this is written the two
agree: `../LibKa0s` sits on **v1.32.0**, [`CLAUDE.md`](../CLAUDE.md) names the same tag, and all
four commands above report nothing. That is the state immediately after a re-vendor and before the
library's next tag — a coincidence of timing, not the stronger guarantee the block below states.

**The authoritative comparison is against the tag `CLAUDE.md` names**, and that one must be empty at
every commit:

```sh
tag=$(grep -oE 'Bundles \[LibKa0s\]\([^)]*\) v[0-9]+\.[0-9]+\.[0-9]+' CLAUDE.md \
        | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
rm -rf "/tmp/libka0s-$tag" && mkdir -p "/tmp/libka0s-$tag"
git -C ../LibKa0s archive "$tag" | tar -x -C "/tmp/libka0s-$tag"
diff -r --strip-trailing-cr "/tmp/libka0s-$tag/LibKa0s" libs/LibKa0s   # MUST be empty
diff -r --strip-trailing-cr "/tmp/libka0s-$tag/testkit" tests/_kit     # MUST be empty
```

`tests/test_vendor_sync.lua` asks exactly this question inside the suite — it greps the tag out of
`CLAUDE.md` and reads that blob out of git — so **a green suite has already answered it**, and the
block above is only the by-eye version for when you want to see the hunks. Which leaves the
working-tree diffs above answering a real but different question: *how far behind the library is
this addon?* That is release planning, not a gate.


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

`tests/test_source_style.lua` joined them on 2026-09-08, and it is the one where the shape is not a fallback but the *only* option. It reads the standing `_G.` list out of [common-tasks.md](common-tasks.md#global-lookup-form) and fails on a bare read of any name on it. There is nothing to drive: `tests/run.lua` publishes each instance's mock table as `mocks._G` on purpose, so `_G.UnitExists` and `UnitExists` resolve through the same table — the two spellings are indistinguishable at runtime, in the harness and in the client alike. The rule's entire value is that a reader skimming a file can see which reads might find nothing there, so the only instrument that can measure it is one that reads. The violations it now guards sat under 845 green cases until the 2026-09-07 review opened the files.

It is also narrower than the doc's rule, deliberately, and the narrowing is recorded in the doc rather than hidden here: the "guarded somewhere → `_G.X` everywhere" half is advisory, because `LibStub`, `Settings`, `GameTooltip` and four more are guarded and bare at some seventy sites. A gate is worth having only where the tree can be green today and stay green; a gate that ships red teaches everyone to read past it.

`tests/test_locale.lua` grew the fourth of these on 2026-09-08 (M4-21, KICKCD-R-03), and it is the one whose *direction* is the point. The obvious locale gate is a `gmatch` for `L["…"]` over the sources checked against `locales/enUS.lua` — four repositories in the collection had one, and everything such a scan can find is by construction already wrapped, so the one thing it exists to catch is the one thing it cannot see. What is here instead lexes the TOC-derived source list for string **literals** and asks two questions in opposite directions: every literal that *is* an `L[…]` subscript must be defined in `locales/enUS.lua`, and every literal in `settings/` that is *not* one and reads as prose must be recorded, with a declared class, in the residue register at the foot of the file. Both directions are pinned — an unrecorded bare sentence is red, and so is a register entry whose literal has since been wrapped, reworded or deleted, which is what keeps the register from becoming a mute button.

It lexes rather than `gmatch`es because this repo's comments are prose and quote strings freely, so a naive `"(.-)"` scan reports a paragraph *about* a string as a string — and it handles long brackets rather than skipping them, because `settings/Spells.lua:50-51` holds two `[[Interface\…]]` texture paths and a lexer that walked past `[[` would misread the next apostrophe as a string opener and lose the rest of the file. Two limits are stated rather than papered over. The prose floor is two adjacent alphabetic words, so a one-word label is invisible to it. And the residue half reads `settings/` **only**: `/kcd` command output in `core/KickCD.lua` (about a hundred prose literals) and the debug-console text in `modules/Castbar_Debug.lua` and `modules/Cooldowns.lua` are still bare English and are a known gap this gate does not close. The key-coverage half has no such fence — it reads every file the TOC loads outside `libs/`.

`tests/test_spelling.lua` is the fifth, added on 2026-09-08 (M4c-02), and it is the one that exists because a *sweep* was not enough. `M4-13` ran `localization-§5`'s published `BRITISH` / `ALLOWED` pair over this tree and left it clean — one line survived, a deliberate quote in the smoke doc. Eight commits later the same scan found fifteen lines, put back by five different items that had no way to know: a TOC comment, two comments about where the icon grid sits relative to the screen's center, two more in the smoke doc, and a locale-lexer transplanted from PrettyChat and ConsumableMaster whose residue taxonomy spelled one of its eleven class names the British way in every entry that carried it. Nothing here could see any of it — `luacheck` does not read English, and every other suite reads behavior — so the sweep would have been re-run forever. The gate carries both published lists **whole**, because a private subset is a gate whose green tells a reader nothing about which spellings it covers, and it derives its candidate set from `git ls-files` rather than a hand-typed list, for the reason `tests/_kit/test_eol.lua` gives about its own: a typed list is a list the next document quietly falls out of. Its four exclusions and its one per-word waiver are in [common-tasks.md](common-tasks.md#us-english).

`tests/test_lintconfig.lua` is the sixth, added on 2026-09-08 (`M4c-06`), and it guards the *lint configuration* rather than the code — because `luacheck .` reporting 0/0 is only worth reading if the config it obeyed was not the thing doing the silencing. `.luacheckrc` here carried `ignore = { "212/self", "212/event", "211/addonName" }`, and the trap is that those entries are in the narrow `<code>/<variable>` SPELLING while sitting at the top level, which is the widest SCOPE there is: all 93 files, including every file with no business producing them. Removing the three lines took the tree from 0/0 to 61 warnings, 32 of them defects — 29 `local addonName, NS = ...` headers over an unread folder name, two named-and-unread receivers in the test tree, and a `NS.Slash:PrintHelp` forwarder nothing called, which under a silenced receiver read like the third member of a trio. Four cases hold the line: no top-level `ignore`; no warning class switched off wholesale (`unused_args = false` and eight relatives, which is `ignore` spelled as a switch); no `files[...]` ignore that is neither keyed to one `.lua` file nor narrowed to a variable; and no bare `-- luacheck: ignore` in any tracked `.lua`. All four were watched red in the working tree before the commit landed.

It loads `.luacheckrc` **as Lua**, under a sandbox whose `__index` auto-creates tables the way luacheck's own config loader does, rather than scanning it as text — Lua has half a dozen ways to write the same assignment, and a text scan loses to all of them. What this gate reads is therefore the table luacheck obeys. It fails rather than skips when it cannot look — no config, no `io.popen`, no git, a chunk that will not compile — the same bargain `tests/test_doc_structure.lua` and `tests/_kit/test_eol.lua` strike.

Reach for this shape when a rule must hold in code the harness cannot enter — combat-only paths, branches gated on live game state, anything behind an API the mock stubs to a constant, and anything consumed by a library before it becomes observable. It is not a substitute for behavioral coverage; it is what you add when you can prove coverage is structurally impossible. Pair it with an in-game check where one exists — smoke-test §25 is the `L` trap's.

## Keeping the inventory & badge in sync

`docs/test-cases.md` and the README `Tests` badge are hand-maintained-in-lockstep coverage artifacts (Ka0s WoW Addon Standard, testing-§5). Whenever the suite changes — a case is added, removed, or renamed, or the pass count moves (i.e. whenever a failing test is resolved) — regenerate the inventory via `lua tests/run.lua --list > docs/test-cases.md` **and** update the README `Tests-X/Y_passing` badge count in the **same change**, never as a deferred follow-up. Verify the inventory is in sync with `diff <(lua tests/run.lua --list) docs/test-cases.md` (no output = clean).

For end-to-end test scenarios — fresh install, visibility modes, lock/drag, cast bar auto-size, spec/talent/pet rebuilds, profile lifecycle, secret-value safety, etc. — see [smoke-tests.md](smoke-tests.md). The matrices below catalog what each slash and debug command produces; they're the reference the smoke tests lean on.

## Slash command coverage

- `/kcd` — print the slash command help. `/kickcd` is a long-form alias that routes to the same handler. Every printed line should carry a cyan `[KCD]` prefix (added by `Util.print`); each help row should show the slash invocation in yellow and the description in white.
- `/kcd version` — print the addon version on its own line (`v<X.Y.Z>`), read from the TOC manifest with the in-code `NS.VERSION` stamp as fallback. Covered headlessly by `test_version`.
- `/kcd config` — open the settings panel. Refuses during combat (the Blizzard category-switch is protected); user gets a one-line print instead. `/kcd options` is an alias.
- `/kcd lock` / `/kcd unlock` / `/kcd toggle` — exercise the shared icon grid + cast bar lock state. Routes through `Helpers.SetAndRefresh("locked", ...)` so the General → "Lock frame" checkbox refreshes. With no `locked` row to write through, it prints "Settings layer not ready yet" and changes nothing (covered headlessly in `test_slash`).
- `/kcd list` — dump every schema-driven setting grouped by panel, with current values. Useful for "did the panel/slash share state?" spot checks.
- `/kcd get <path>` / `/kcd set <path> <value>` — type-aware CLI for every schema row. `path` is the dotted `db.profile` path (`enabled`, `units.target.icons.primarySize`, `units.target.icons.cooldownTint` …). `set` parses by `def.type`: bool accepts `true/false/on/off/1/0`; number is clamped to `[min, max]`; string must match a `values[i].value` (rejection prints the option list, plus `(depends on <gate> = ...)` when the row carries a `valueGate`); color takes 3–4 floats (`r g b [a]`, each clamped to `[0, 1]`). On success, any open panel re-syncs its widgets via `Helpers.RefreshScalars()` — a value write changes what a widget *shows*, so it must never rebuild the page under a slider or swatch mid-drag; `RefreshAllPanels` is reserved for structural changes (a profile switch, and the `units.focus.link` row's `onChange` when the link actually moves).
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
