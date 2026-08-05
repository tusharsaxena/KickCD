# KickCD — Technical Design (2026-08-05)

Remediation design for the deviations catalogued in `02_DEVIATIONS.md`. This document is a **plan**;
this audit changed no addon code. Every heading names its deviation IDs.

---

## Shape of the work

Nineteen findings fall into six coherent changesets, not nineteen edits. The grouping is driven by
which files they touch and by two ordering constraints that genuinely bind:

1. **`KCD-31`, `KCD-32` and `KCD-40` all rewrite `settings/Panel.lua`.** Doing them in three passes
   means three rounds of the same merge; doing `KCD-40` first means deleting code that `KCD-31` was
   about to delete anyway.
2. **`KCD-41` moves the defaults table that `KCD-42` reads.** `KCD-42` is a user-visible bug and
   should not wait, so it lands **first and small** (a three-line body change plus a test) and the
   defaults move follows.

Everything else is independent and can be scheduled on its own.

---

## A. The color bug and the defaults tree — `KCD-42`, `KCD-41`

### A1. `rgba()` (KCD-42) — the smallest possible change

`modules/Castbar.lua:726-729` becomes a call into the decoder the rest of the addon already uses:

```lua
local function rgba(c)
    return NS.Util.Unpack(c or WHITE)
end
```

`Util.Unpack` (`core/Util.lua:22-28`) already tries `c.r` first and falls back to the positional arm,
already defaults each channel to 1, and already returns four values — so the signature, the
allocation-free return and the `WHITE` fallback are all preserved. `modules/Castbar.lua:228-231`
proves the call shape works on this hot path today.

**Characterization first (`testing-§13`).** The function has no coverage, so before touching it:

- add a case to `tests/test_color_shape.lua` that drives `applyLiveVisuals` (and
  `applyPreviewVisuals`) with `nameTextColor = { r = 0.2, g = 0.4, b = 0.6, a = 1 }` and asserts the
  four values that reach `nameText:SetTextColor`;
- **run it against the unrefactored code and watch it go red** — it will report `1,1,1,1`. That red
  run is the evidence the test describes the bug rather than the author's belief about it;
- fix, watch it go green.

Also add the negative-direction case: a **positional** table still decodes, so the change is not a
swap of one shape for the other.

**Risk:** none material. `Unpack` is the addon's most-exercised helper. The only behavior that
changes is the one that was wrong.

### A2. `defaults/Profile.lua` (KCD-41)

Move `DEFAULT_PROFILE` (`core/Database.lua:239-303`) verbatim into a new `defaults/Profile.lua`:

```lua
local addonName, NS = ...
NS.C = { --[[ the tree, unchanged ]] }
NS.DEFAULT_PROFILE = NS.C
```

Then:

- `core/Database.lua:291-292` reads `profile = NS.DEFAULT_PROFILE`; `:304` (the re-export) is deleted
  as redundant. `core/Database.lua` keeps the AceDB assembly, the migration table and the runner —
  which is what `savedvariables-§1` puts there.
- `KickCD.toc:46` gains `defaults\Profile.lua` **before** `defaults\Spells.lua`. `core/Database.lua`
  loads in the `# Core` block, which the TOC places *before* `# Defaults` — so the table must be
  reached at **call** time, not captured as a load-time local. `AceDB:New` runs from `InitDB`
  (`core/Database.lua:820`), well after load, so `NS.DEFAULT_PROFILE` resolves; the one thing to
  check is that no file-scope statement in `core/Database.lua` indexes the tree at load.
- Delete the second copy at `modules/Castbar.lua:566-590` and read the shared tree. This is where the
  positional `nameTextColor` at `:573`/`:583` disappears — the same divergence `KCD-42` fixed at the
  read end, now fixed at the write end.

**Risk:** load-order. Mitigated by the two facts above and by `tests/test_database.lua`, which
already pins the defaults tree's shape and will redden on any accidental restructure. Do the move as
a pure cut-and-paste commit with no edits to the tree's contents, so the diff is reviewable.

---

## B. The Options surface — `KCD-40`, `KCD-31`, `KCD-32`

One changeset, in this internal order, because each step shrinks the file the next step edits.

### B1. Adopt the library's page registry (KCD-40)

The library already offers the whole shape (`libs/LibKa0s/Options.lua:536` `RegisterOptionsPage`,
`:576` `CreateOptionsPanel`, `:636` `OpenOptionsPanel`), and the host already forwards to all three
(`settings/OptionsSetup.lua:228-230`). What is missing is that anything calls them.

- Each page tail changes from `NS.Settings.RegisterTab("<key>", Build)` to
  `NS.RegisterOptionsPage("<key>", L["<Name>"], Build)` — six one-line edits
  (`settings/General.lua:183`, `Icons.lua:417`, `Castbar.lua:560`, `Label.lua:193`,
  `Spells.lua:1158`, `Profiles.lua:66`).
- Each `Build` already returns its `Settings.RegisterCanvasLayoutSubcategory` handle
  (`settings/General.lua:178` and siblings), which is exactly the contract `options-ui-§5` states, so
  the builders themselves do not change. A builder that returns nil is a legitimate opt-out, which is
  how `settings/Profiles.lua` behaves when AceConfig is absent.
- Delete `NS.Settings.RegisterTab` (`settings/Panel.lua:546-553`), `RegisterPanel` (`:554-604`),
  `NS.Settings.Register` (`:605`) and the private bootstrap frame (`:607-616`). Call
  `NS.CreateOptionsPanel()` once from the surviving `PLAYER_LOGIN`/`ADDON_LOADED` handler — the
  registration is **eager** (`options-ui-§5`) and the library's own body build stays lazy.
- `Helpers.ValidateSchema()` (called at `:569` today) moves to the same login handler, ahead of
  `CreateOptionsPanel`, so `architecture-§5`'s boot validation keeps happening before any row is
  handed to a renderer.
- `NS:OpenSettings` (`core/KickCD.lua:775-790`) delegates to `NS.OpenOptionsPanel()`. The combat gate
  moves out of the host (the library gates inside its own open, `options-ui-§2`), and the host keeps
  only what is genuinely its own: the bounded retry (`scheduleOpenRetry`, `:764-774`) and
  `expandMainCategory` (`:718-731`). If the retry proves unnecessary once registration is eager —
  which is its stated reason for existing (`:761-763`) — delete it rather than port it.

**Callers to re-point:** `tests/test_coresetup.lua:354` and `tests/test_options_panel.lua:342`
already drive `NS.OpenOptionsPanel`, so they become the *production* path's tests rather than tests
of a dead forwarder. `tests/test_settings_spells_editor.lua:30` calls `NS.Settings.Register()` and
must move to `NS.CreateOptionsPanel()`.

**Risk — this is the highest-risk item in the plan, and it is a rendering risk, not a logic one.**
The library's `CreateOptionsPanel` drains a queue and registers subcategories in registration order;
the host's loop walks `NS.Settings.order`. Page **order** in the Blizzard sidebar is user-visible.
Pin it before starting: add a case asserting the six subcategory names in order as the current code
produces them, run it green, then refactor. If the library registers in call order, the six
`RegisterOptionsPage` calls must be made in the TOC order that already matches `NS.Settings.order`.

### B2. Delete the host copies of library members (KCD-31)

Delete `Helpers.LSMValues` (`settings/Panel.lua:276-291`), `attachTooltip` + its assignment
(`:315-341`), `ensureScroll` + `Helpers.EnsureScroll` (`:355-394`) and `addSpacer` +
`Helpers.AddSpacer` (`:435-443`). The instance then answers with the library's own.

The one contract difference is `LSMValues`: the host returns a table, the library returns the
**closure** `options-ui-§6` requires. Eight schema rows currently wrap it —
`values = function() return H.LSMValues(m) end` — and each becomes `values = H.LSMValues(m)`
(`settings/Icons.lua:196`, `:220`; `settings/Label.lua:147`; `settings/Castbar.lua:280`, `:401`,
`:438`, `:463`, `:500`).

**User-visible consequence to record in the change:** the empty-media fallback key moves from the
host's `"Default"` (`settings/Panel.lua:288-289`) to the library's `LSM_NONE`. A profile that stored
the literal string `"Default"` for a font/texture path will no longer match a list entry. Check
whether `core/Database.lua`'s migration table needs a step for it; if the stored value is a media
*name* the addon resolves through LSM at render time, a missing match already falls back, and no
migration is needed — confirm which, do not assume.

`Helpers.AnchorValues` (`:244`) and `Helpers.AnchorOrder` (`:266`) are genuinely host-shaped and
stay. So does everything in `settings/Panel_Widgets.lua`, which is already a 65-line adapter.

### B3. Delete the host copies of layout constants (KCD-32)

- Delete `local ROW_VSPACER = 8` (`settings/Panel.lua:426`) and `Helpers.ROW_VSPACER = ROW_VSPACER`
  (`:430`). The library publishes it at `libs/LibKa0s/Options.lua:176`, and
  `settings/Panel_Render.lua:20` and `settings/Panel_Widgets.lua:48-50` already read it off the
  instance — those two become the only readers.
- `PADDING_X` is the harder half: the library holds it in its private `LAYOUT` table
  (`libs/LibKa0s/Options.lua:46`) and does **not** publish it on the instance. The compliant route is
  **upstream**: add `O.PADDING_X = L.PADDING_X` beside the existing `O.ROW_VSPACER` line in
  `LibKa0s-Options-1.0`, bump that file's LibStub minor, add its changelog entry, tag, re-vendor into
  every consumer, then read `Helpers.PADDING_X` here. **Never** edit `libs/` locally
  (`library-stack-§7`).
- Until that minor lands, `core/Constants.lua`'s `PANEL_PADDING_X` stays, with a comment at the
  declaration naming `KCD-32` and the upstream change it is waiting on. A time-boxed deviation with
  its exit written down is a decision; an undated one is the drift the rule exists to stop.

---

## C. The test harness — `KCD-30`, `KCD-43`, `KCD-49` (test half)

### C1. Adopt the kit (KCD-30)

Three substitutions, and the reason they are cheap is that the kit was written to make them cheap.

- **Framework.** `tests/run.lua` gains `local Kit = dofile(root .. "/tests/_kit/framework.lua")` and
  loses `:17-82` (the registry, `test`, the six assertions and the `--list` renderer). `Kit.expose`
  merges `test` plus the assertion set into whatever table you hand it, so
  `Kit.expose(_G.KICKCD_TEST)` keeps the global's name and its extra keys (`T.root`, the instance
  factory) — **no suite file changes**, which is the property that makes this one commit rather than
  a rewrite. The suite list goes to `Kit.run{ dir = "tests/", suites = { ... } }`, which exits 0/1 so
  the shell gate is unchanged.
  - This also removes the *"registration is execution"* shape for free: the kit collects and runs
    nothing until `Kit.run`, so `--list` becomes a pure filter over the registry and can no longer
    disagree with the run.
- **Loader.** Delete `tests/loader.lua`; use the kit's `loader.lua`. The addon's own file list comes
  from `Loader.tocFiles("KickCD.toc")` (`testing-§9`); the vendored library files stay **explicitly
  listed in the runner, in `LibKa0s.xml` order**, because `tocFiles` skips `libs\` and cannot see
  inside an XML. Keep the existing `{ libFiles = {} }` degraded-path option — it is the mechanism
  `testing-§8` requires and it is already used correctly.
  - Add the three pins `testing-§9` names: the runner fed the loader exactly the TOC's files in the
    TOC's order (publish what it loaded through `Kit.expose`, compare against a fresh derivation);
    every derived path exists on disk; no `libs/` path leaked in.
- **Mock.** Rebuild `tests/wow_mock.lua` as `local base = dofile("tests/_kit/mock_base.lua")` plus a
  builder that calls `base()` and overwrites the handful of keys KickCD genuinely needs. `:573`
  already identifies its widget builder as a verbatim port, so that block deletes outright. Use
  `M.__stubFrame()` for extra frame-shaped objects and `M.__libs` for additional library fakes.
  Expect the file to drop from 1066 lines to a few hundred, which also clears the `A-2` band entry
  the watch list tracks under this ID.

**Risk:** highest churn, lowest conceptual risk. The suite is 737 cases and green; adopt in the order
framework → loader → mock, running the full suite after each, so a regression is attributable to one
substitution. Do **not** "improve" a case while porting — a behavior change hidden in a mechanical
diff is unreviewable (`performance-§11`).

### C2. Make the vendor-sync gate visible (KCD-43)

Two acceptable end states; pick one and say which in the change.

- **Preferred — fail when it cannot look.** `testing-§11` states the rule directly: a gate that goes
  quiet when it cannot look is worse than no gate. `siblingTag()` raises instead of returning nil,
  with a message naming the path it looked for (`../LibKa0s`) and how to get it.
- **Acceptable — name the skip.** If a checkout-optional workflow is genuinely wanted, register a
  *different case* when the sibling is absent:
  ```lua
  if not siblingTag() then
      test("vendor sync SKIPPED — ../LibKa0s is not checked out", function() end)
      return
  end
  ```
  The inventory and the badge then report an unmeasured gate as unmeasured, which is the whole point.

Either way, correct the comment at `:107-109`, which asserts a property the case names do not have.

**Note for whoever runs this:** the audit's own `diff -r` checks (`03_EVIDENCE.md` §1.5) were **not
run**, so vendor sync is currently **unverified** in both directions. Run both diffs as the first
step of this item, before changing the suite — if they are non-empty, that is an `AP #45` finding
that needs its own deviation ID, and it is invisible until someone looks.

### C3. Generalize the bracket-exit pin (KCD-49, test half)

`tests/test_perfsetup.lua:551-589` pins that `PollSpell` closes its bracket on every exit. Generalize
it to every bracketed function: scan the source for `local __t0 = Perf.on and debugprofilestop()` and
assert that the enclosing function has no `return` between the open and a `Perf.Note` — a
source-scan guard in the shape `tests/test_slash_style.lua` already establishes in this repo
(`docs/testing.md:112`). That is what makes a future early return impossible to add silently.

---

## D. The performance surface — `KCD-34`, `KCD-35`, `KCD-49` (source half), `KCD-44`

### D1. Close the two brackets (KCD-49)

`modules/IconGrid_Render.lua:831-837` and `modules/Castbar.lua:694-697` each gain
`if __t0 then Perf.Note("<bucket>", debugprofilestop() - __t0) end` on the early-return arm, exactly
as `modules/Cooldowns.lua:194` does. Correct `core/PerfSetup.lua:108` from "All four of PollSpell's
exits" to "Both of PollSpell's exits" in the same change — the comment is the record of *why* the
bucket exists and a wrong count in it undermines the rest.

Two-line change; do it first in this group, because the numbers `tests/perf.lua` will produce should
come from correct brackets.

### D2. `tests/perf.lua` (KCD-34)

Minimum viable and standard-complete:

- Lives at `tests/perf.lua`, run as `lua tests/perf.lua`, **not** referenced by `tests/run.lua`
  (`testing-§7`). The vendored runner picks it up as the non-gating `perf` suite automatically.
- Derives its addon-file list through `Loader.tocFiles` (`testing-§9`) — it is a load list outside
  the gate, which is precisely the one that rots. Pin the derivation by reading its source from a
  gated suite.
- **The zero-overhead scenario is the required one** (`performance-§2`): drive `iconApply` — named at
  `core/PerfSetup.lua:26-31` as the addon's only real hot path — N times with `Perf.on == false`, and
  again with `NS.Perf` replaced by the absent-library stub, measuring `collectgarbage("count")`
  deltas with a full `collectgarbage("collect")` either side of each loop. Assert the two allocate
  the same, and that the API call count matches.
- **Assert nothing on wall-clock** (`performance-§9`). Timings may be printed for orientation with
  the "compare within a run, never across machines" note.
- Worth adding beside it: a scenario over `spellPoll` → `pollSpell` → `spellState` → `iconApply` that
  asserts each declared bucket is reached, which is `testing-§8`'s per-module requirement in
  executable form.

Landing this turns the manifest's `"perf": "skip"` into `"perf": "pass"` and removes the release
gate's one blocker (see D4).

### D3. `docs/performance.md` and `docs/perf-runs/README.md` (KCD-35)

- **`docs/performance.md`.** Do not write it from scratch: the reasoning already exists in prose at
  `core/PerfSetup.lua:19-31` (why the signal is where it is) and `:96-122` (the buckets and their
  nesting, with the 125.02/51.14/73.9 ms capture that drove them). **Move** it, leaving a one-line
  pointer in the source rather than duplicating it. Add: how to run `/kcd perf`, how to read the
  report, what the harness can and cannot resolve, and a pointer to the library for the shared
  protocol and record schema rather than restating them.
  - **One honesty problem to fix while moving it.** `core/PerfSetup.lua:105-120` cites 125.02, 51.14
    and 73.9 ms from a capture with **no record anywhere in the repo**. `performance-§8` treats a
    committed record as evidence and an interpretation without its record as an assertion. Either
    commit the capture under `docs/perf-runs/` (D3b) or mark the figures in the new page as an
    uncommitted historical reading. Do not carry them forward as though they were sourced.
- **`docs/perf-runs/README.md`.** The naming convention `<YYYY-MM-DD>-ingame-<label>.json`, a field
  summary of the library's record schema, a pointer to the library's canonical contract, and the
  `automated-tests-§7` split stated plainly: this directory is the **in-game** half, offline runs
  live in `docs/automated-tests/`. It is standing and cumulative, not tied to one investigation.
  Commit the first real capture beside it.

### D4. State the release gate (KCD-44)

- **`docs/testing.md`.** Add a paragraph beside the existing commit-gate text at `:99-100`: the
  **release** gate is all four suites at `pass` **plus** `suites.complexity.warnings == 0` (zero
  functions above CCN 15) at the tag; it is evaluated by `/wow-addon:bump-version` from the run's
  `manifest.json`, **not** by the runner's exit code, which stays what it is because the same script
  is the commit gate; and a `skip` blocks as NOT EVALUATED rather than reading as a pass. Extend the
  suite table's `Gates?` column into two — `Commit?` and `Release?` — so the distinction is in the
  table rather than in the prose under it.
- **`CLAUDE.md:75`.** "Complexity — recorded, never a gate" becomes "recorded, never a **commit**
  gate — and a **release** gate: zero functions above CCN 15 at the tag."
- **`docs/automated-tests/README.md`.** Same two-checkpoint statement, since that is the doc a reader
  lands on from the bundle.
- **The `perf: skip`.** Once D2 lands the exception disappears. Until then, the narrow
  no-`tests/perf.lua` exception `automated-tests-§3` allows **MUST** be stated in the release notes
  of any release cut in the meantime — so if a release precedes D2, add the sentence.

---

## E. The output seams — `KCD-33`, `KCD-45`, `KCD-46`

All three are about lines the addon prints; they are independent of everything above and of each
other, but they read as one theme and are cheapest reviewed together.

### E1. `core/Compat.lua` (KCD-33)

Delete `safeRender` (`:373-386`) and route every value through `NS.SafeToString`
(`core/CoreSetup.lua:131`, the library's own function). Where the current renderer quotes plain
strings with `%q`, wrap the shared result — do not re-derive the safety decision. Drop the `_G.print`
fallback at `:446`; `NS.Util.print` is published unconditionally on both the library and the stub
path (`core/CoreSetup.lua:100`/`:135`), so the fallback protects against nothing. **Keep** the
`issecretvalue` column at `:387`: reporting whether a value is secret is the diagnostic payload of
`/kcd debug interrupt`; it simply must stop being the safety mechanism.

### E2. `core/DebugLogSetup.lua` (KCD-45)

Delete `FormatPlain` (`:94-96`) and `D.FormatColored = D.FormatPlain` (`:114`). Rewrite the comment
at `:58-62` to say what was removed and why, so the next author does not re-add it for the same
plausible reason. If a suite asserts on the stub's formatter, move that assertion to the library path
where the format is actually specified; if a suite needs the stub to answer *something*, return the
message alone.

### E3. `modules/Castbar_Debug.lua` (KCD-46)

Three changes in one pass:

- `:125` drops `or _G.print`.
- Every call site passes pieces as **varargs** rather than one pre-concatenated string —
  `print("  current.isChannel = ", current.isChannel)` — so the shared printer's per-argument
  secret-safe stringifier actually runs. This matters most in this file: it is the one whose subject
  is possibly-secret values, and pre-concatenation is exactly what defeats the guard.
- The dump routes to the console through the ungated raw append,
  `NS.DebugLog:Add("Cast", line)` — `debug-logging-§12` puts an explicit user-initiated diagnostic
  run there, ungated, and `core/PerfSetup.lua:169-170` already does exactly this for the perf run.
  Reveal the console **once** at the start of the dump (`core/PerfSetup.lua:182-183` is the pattern),
  never per line.

`tests/test_castbar_debug.lua` already drives this path and will characterize the change. Sequence
E3 **after** `KCD-30`, or the mock work will collide with it.

---

## F. Documentation and prose — `KCD-37`, `KCD-47`, plus `A-9`

- **`KCD-37`.** `README.md:191` → `` `/kcd reset setting` ``. One character class, one line. Add the
  angle-bracket sweep to the pre-release doc pass so the next straggler is caught by process rather
  than by an audit — and **exclude** the `<br>` tags at `:210-211`, which `documentation-§1` protects
  by name.
- **`KCD-47`.** `colour(s)` → `color(s)`, `behaviour` → `behavior` in
  `docs/superpowers/plans/2026-08-04-ccn-elimination.md` (`:51`, `:53`, `:57`, `:121`, `:149`).
  **Do not touch** `docs/automated-tests/20260804-182144/ANALYSIS.md:72` — a run bundle is frozen
  evidence (`automated-tests-§1`), and hand-editing one is worse than the typo it fixes. Note it in
  the next `ANALYSIS.md` instead.
- **`A-9`.** While in `core/DebugLogSetup.lua` for E2, sweep the two stale references to the deleted
  `modules/DebugLog.lua` at `core/Constants.lua:91` and `core/CoreSetup.lua:20`.

---

## G. `KCD-48` — the gate-hint probe

`settings/Slash.lua:118-122`. Two candidate fixes, in order of preference:

1. **Remove the write.** If `allowedKeys(row)` can take the candidate value as an argument rather
   than reading it back out of the db, the probe needs no mutation at all and the finding disappears
   rather than being contained. Check the shape of `allowedKeys` and the row `values()` contracts
   first — this is the better answer if it is available.
2. **Contain it.** Wrap mutate → probe → restore in `pcall` so the restore is unconditional:
   ```lua
   parent[key] = candidate
   local ok, alt = pcall(allowedKeys, row)
   parent[key] = gateVal
   if ok and #alt > 0 then ... end
   ```

Either way add a case that makes `values()` raise and asserts the stored value is unchanged — and
per `testing-§12`, prove the case can fail by removing the guard and watching it redden before
committing it.

---

## H. `KCD-38` — the bus fan-in

Not an edit; a decision, and it has been carried across three audits. Two ends, both legitimate:

- **(a) Narrow to one owner.** `settings/Panel.lua:75` `Helpers.FireConfigChanged(section)` already
  exists and is already the panel's path. Route the other five sends through it:
  `core/KickCD.lua` (×2), `modules/Castbar.lua`, `modules/IconGrid.lua`, `settings/Spells.lua`. The
  message then has one sender, `docs/ARCHITECTURE.md:118` shrinks to one name, and
  `docs/message-bus.md`'s own same-file rule is satisfied. Cost: two `modules/` files gain a
  dependency on a `settings/` helper, which inverts the layering — so the seam probably wants to move
  to `core/State.lua` or `core/KickCD.lua` rather than staying in `settings/`.
- **(b) Take it upstream.** Propose a `architecture-§4` carve-out for a settings-changed fan-in
  message: one *shape*, many emitters, one documented payload. If the collection has the same
  pattern in several addons, that is the honest resolution and the standard is the place for it.

**Do not leave it in the middle.** The current state already breaks the addon's own written rule, and
`A-8` (the double `CONFIG_CHANGED` from `ResetAll`) is a symptom of the same missing seam — fixing
`KCD-38` by route (a) removes it for free.

---

## Ordering constraints, summarized

- `KCD-42` before `KCD-41` (fix the visible bug small, then move the table).
- `KCD-40` before `KCD-31` before `KCD-32` (all in `settings/Panel.lua`; each shrinks the next).
- `KCD-30` before `KCD-46` and before the `KCD-49` test half (both touch suites the kit adoption
  rewrites).
- `KCD-49` (source half) before `KCD-34` (measure with correct brackets).
- `KCD-34` before `KCD-44`'s release-notes exception becomes unnecessary.
- `KCD-32`'s `PADDING_X` half is **blocked on an upstream LibKa0s minor** and cannot be finished in
  this repo.
- `KCD-43` should start by running the two `diff -r` checks this audit could not
  (`03_EVIDENCE.md` §4) — an unverified vendor sync is the one finding that hides from both suites.
