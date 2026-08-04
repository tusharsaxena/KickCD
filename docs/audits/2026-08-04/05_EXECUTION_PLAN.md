# KickCD — Execution Plan (2026-08-04)

**Standard:** v2.17.1 (2026-08-03). Steps are keyed to `02_DEVIATIONS.md` IDs and to the themes in
`04_TECHNICAL_DESIGN.md`.

**Hand-off.** This audit wrote no code. The steps below are the remediation engagement's work list.

**Standing gate for every step:** `lua tests/run.lua` green **and** `luacheck .` clean before the
commit (testing-§4). Both are green at audit time — 648 passed / 0 failed, 0 warnings / 0 errors in
32 files — so any red is introduced by this work. Trunk-based; no branches unless the user asks
(versioning-git). Never edit `libs/` or `tests/_kit/`.

---

## Sprint 0 — Decisions the user owns (blocks nothing else)

| # | ID | Step | Done when |
|---|---|---|---|
| 0.1 | `KCD-38` | Present the bus-ownership choice: **(a)** narrow to one publisher (`NS.PublishConfigChanged` in `core/State.lua`, with `settings/Panel.lua`'s `FireConfigChanged` delegating), or **(b)** take a settings-changed fan-in carve-out upstream to `WowAddonStandards`. Recommendation is (a). | The user has chosen, and the choice is written into `docs/message-bus.md` replacing the current "multi-module by design" note. |
| 0.2 | `KCD-32` | Confirm the `PADDING_X` route: additive `O.PADDING_X` upstream in `LibKa0s-Options-1.0`, or an interim recorded deviation in `core/Constants.lua:66`. | Chosen; if upstream, an issue exists in the `LibKa0s` repo. |
| 0.3 | A-1 | Confirm the AceTimer position stands (deleted, per library-stack-§3) and, if it recurs across the collection, raise the §1-vs-§3 tension upstream. | Confirmed or raised. |

---

## Sprint 1 — Additive, zero-risk (do this first; it can ship on its own)

Nothing here changes a code path. It closes three deviations and buys the evidence the rest of the
work is judged against.

| # | ID | Step | Done when |
|---|---|---|---|
| 1.1 | `KCD-37` | `README.md:191`: `` `/kcd reset <setting>` `` → `` `/kcd reset setting` ``. **Do not** touch the `<br>` tags at `:210-211`. | `grep -n '<[a-zA-Z_][a-zA-Z0-9_ ]*>' README.md` returns only the two `<br>` lines. |
| 1.2 | `KCD-35` | Create `docs/performance.md` — which paths are bracketed and why (relocate the reader-facing half of `core/PerfSetup.lua:19-31` and `:104-122`), how to run `/kcd perf`, how to read the report, what the harness can and cannot resolve. Point at LibKa0s for the shared protocol; do not restate it. | File exists, is player/engineer-readable, and is linked from `docs/ARCHITECTURE.md`'s topic index and `CLAUDE.md`'s pointer list. |
| 1.3 | `KCD-35` | Create `docs/perf-runs/README.md` — `<YYYY-MM-DD>-<source>-<label>.json` naming, schema summary, pointer to the library's canonical record contract, and a line saying the store is standing and cumulative. | File exists; the directory is committed. |
| 1.4 | `KCD-35` | Run one real `/kcd perf` capture in-game and commit the JSON under `docs/perf-runs/`. | At least one record is committed — a README heading an empty directory is a promise, not a store (performance-§8). |
| 1.5 | `KCD-39` | `lizard core modules settings defaults locales -l lua > docs/complexity.md`, with a generated-by header naming the command. Do not gate anything on it. | File exists, or the step is recorded as blocked on `lizard` not being installed (which is not non-compliance — performance-§10). |

**Commit shape:** 1.1 alone; 1.2–1.4 together as the performance-docs commit; 1.5 alone.

---

## Sprint 2 — Adopt the shared test kit (`KCD-30`)

The highest-risk step, done in isolation so a regression has one possible cause.

| # | ID | Step | Done when |
|---|---|---|---|
| 2.0 | `KCD-30` | Record the baseline: `lua tests/run.lua --list > /tmp/kcd-cases-before.md`. | Baseline saved. |
| 2.1 | `KCD-30` | Rebuild `tests/wow_mock.lua` as a **thin extender**: `local base = dofile("tests/_kit/mock_base.lua")`, then per-key overwrites for what KickCD genuinely needs. Delete the ported widget builder (`:559-…`, the block its own comment at `:556-558` says to delete). | `grep -c 'mock_base' tests/wow_mock.lua` ≥ 1 as a `dofile`, and the file is materially shorter. |
| 2.2 | `KCD-30` | Point `tests/run.lua` at the kit: `dofile` `tests/_kit/framework.lua` and `tests/_kit/loader.lua`, `Kit.expose(_G.KICKCD_TEST)`, `Kit.run{ dir = "tests/", suites = {...} }`. Delete `tests/run.lua:19-83` and delete `tests/loader.lua`. **Keep** `loadInstance` and its `{ libFiles = {} }` degraded-path option — that is genuinely this addon's. | `grep -rn 'Kit\.expose\|Kit\.run' tests/run.lua` matches; `tests/loader.lua` is gone. |
| 2.3 | `KCD-30` | Re-derive the addon's own file list with `Loader.tocFiles("KickCD.toc")`; keep the explicit `LibKa0s.xml` file list and the case in `tests/test_coresetup.lua` that compares it against the XML file-for-file (testing-§9). | The derivation cases pass and still fail if a library file is dropped from the list. |
| 2.4 | `KCD-30` | Diff the inventories: `lua tests/run.lua --list > /tmp/kcd-cases-after.md; diff /tmp/kcd-cases-before.md /tmp/kcd-cases-after.md`. | **Empty.** Same 648 cases, case-for-case. |
| 2.5 | `KCD-30` | Any case that changes status is a **mock-fidelity difference** — understand it, and if the shared mock is the weaker one, fix it **upstream** in `../LibKa0s/testkit/` with its own commit, then re-vendor here (`diff -r ../LibKa0s/testkit tests/_kit` empty). Never patch `tests/_kit/` locally. | No local edits under `tests/_kit/`; `tests/test_vendor_sync.lua` green. |
| 2.6 | `KCD-36` | If the count moved (it should not), regenerate `docs/test-cases.md` and update `README.md:7` in the same commit. | Badge, inventory and runner agree. |

**Rollback:** this sprint is one commit. If 2.4 will not come back empty, revert it whole rather than
chasing individual cases — a mock that is *friendlier* than the one it replaced turns a real failure
green, which is worse than not adopting the kit yet.

---

## Sprint 3 — Finish the Options de-duplication (`KCD-31`, `KCD-32`)

| # | ID | Step | Done when |
|---|---|---|---|
| 3.1 | `KCD-31` | Delete `Helpers.LSMValues` (`settings/Panel.lua:276-291`), `attachTooltip` + `Helpers.AttachTooltip` (`:309-341`), `ensureScroll` + `Helpers.EnsureScroll` (`:348-394`), `addSpacer` + `Helpers.AddSpacer` (`:432-443`). Repoint in-file callers (`BuildMainContent`, `:469`) at `Helpers.EnsureScroll` / `Helpers.AddSpacer`. | `grep -n 'Helpers.LSMValues\|Helpers.AttachTooltip\|Helpers.EnsureScroll =\|Helpers.AddSpacer =' settings/Panel.lua` returns nothing. |
| 3.2 | `KCD-31` | Sweep the `LSMValues` call sites from the table shape to the closure shape: `values = function() return H.LSMValues(m) end` → `values = H.LSMValues(m)`, at `settings/Icons.lua:196,220`; `settings/Label.lua:147`; `settings/Castbar.lua:280,401,438,463,500`. | All seven sites converted; `tests/test_settings_widgets.lua` / `test_schema.lua` green. |
| 3.3 | `KCD-31` | Note the user-visible change in the commit message: the empty-media fallback key moves from `"Default"` to the library's `LSM_NONE` when no media library is loaded. | Stated. |
| 3.4 | `KCD-32` | Delete `local ROW_VSPACER = 8` (`settings/Panel.lua:426`) and `Helpers.ROW_VSPACER = ROW_VSPACER` (`:430`). `settings/Panel_Render.lua:20` and `settings/Panel_Widgets.lua:49` already read the instance. | `grep -n 'ROW_VSPACER' settings/Panel.lua` returns nothing; the panel still renders with 8px row gaps. |
| 3.5 | `KCD-32` | Per decision 0.2: either land `O.PADDING_X` upstream (file-minor bump + changelog + standalone re-vendor commit here), then delete `Const.PANEL_PADDING_X` and read `Helpers.PADDING_X`; **or** add the interim comment at `core/Constants.lua:66` naming `KCD-32` and the upstream field it waits on. | Either `Const.PANEL_PADDING_X` is gone, or it carries its reason **and its exit condition** in a comment. |
| 3.6 | `KCD-31`/`KCD-32` | Keep `Helpers.AnchorValues` / `Helpers.AnchorOrder` (`settings/Panel.lua:244-274`). They are this addon's schema vocabulary, not a library copy. | Untouched. |
| 3.7 | — | In-game smoke pass on all six subcategories: scroll geometry, row spacing, tooltips, every media dropdown (font/texture/border), the Defaults button, and the landing page. | `docs/smoke-tests.md` steps executed and the result recorded. |

**Why the smoke pass is not optional:** the host and library scroll geometry are byte-equivalent
today (`PADDING_X - 4, -8` / `-(PADDING_X + 12), 8`), so a regression here is invisible in the
headless suite and obvious on screen.

---

## Sprint 4 — Performance evidence (`KCD-34`)

| # | ID | Step | Done when |
|---|---|---|---|
| 4.1 | `KCD-34` | Create `tests/perf.lua`. Derive the addon-file list through the kit's `Loader.tocFiles` (depends on Sprint 2). Load the addon under the mock. | File exists at exactly that path; `lua tests/perf.lua` runs from the repo root. |
| 4.2 | `KCD-34` | Ship the **zero-overhead scenario**: `Icon:Apply` × N with `NS.Perf.on = false` vs. the same path with `NS.Perf` at the absent-library stub, full `collectgarbage("collect")` either side, comparing `collectgarbage("count")` deltas and call counts. Assert the instrumented-but-off arm allocates **no more** than the uninstrumented arm. | The scenario runs and its number is committed — performance-§2's required evidence exists as a number rather than a comment. |
| 4.3 | `KCD-34` | Add a second scenario over `Cooldowns:PollSpell` if cheap to drive. State in the output that any printed timings are orientation-only. | Optional; skip if it adds nothing. |
| 4.4 | `KCD-34` | Confirm the boundaries: `tests/run.lua` does **not** run `tests/perf.lua`; its scenarios are **not** in `--list` or the `[tests]` badge; **no** wall-clock assertion anywhere in the file. | `grep -n 'perf' tests/run.lua` shows no invocation; `lua tests/run.lua --list` total unchanged. |
| 4.5 | `KCD-34` | Add a gated case reading `tests/perf.lua`'s source for the `Loader.tocFiles` call (testing-§9 — the gate never runs the file, so its derivation is pinned by reading it). | Case exists and reddens if the derivation is replaced with a hand-maintained list. |
| 4.6 | `KCD-36` | Regenerate `docs/test-cases.md` and update `README.md:7` in the same commit (4.5 adds a case). | Badge = inventory total = runner total. |

---

## Sprint 5 — One stringifier (`KCD-33`)

| # | ID | Step | Done when |
|---|---|---|---|
| 5.1 | `KCD-33` | Write the failing case first: feed `Compat.DebugInterrupt` a value the mock reports as concat-hostile and assert the shared sentinel appears in the output (testing-§4). | Case exists and is **red**. |
| 5.2 | `KCD-33` | Delete `safeRender` (`core/Compat.lua:377-387`); route every value through `NS.SafeToString`. Keep `%q` quoting as presentation wrapped around the shared result, or drop it (the `type=` column already disambiguates). | `grep -n 'safeRender' core/Compat.lua` returns nothing; case from 5.1 green. |
| 5.3 | `KCD-33` | Replace `local out = (NS.Util and NS.Util.print) or _G.print` (`:372`) with the shared printer alone. | `grep -n '_G.print' core/Compat.lua` returns nothing. |
| 5.4 | `KCD-33` | Keep `issecretvalue` at `:401` — it is the command's diagnostic *reporting* column, not its safety mechanism. | Still present, still reporting. |
| 5.5 | `KCD-33` | Prove the 5.1 case can fail: mutate the render back to raw `tostring`, watch it redden, restore from a `cp` backup (never `git checkout`), and name the mutation in a one-line comment on the case (testing-§12). | Comment present, e.g. `-- red under: replace NS.SafeToString with tostring in DebugInterrupt`. |

---

## Sprint 6 — Bus ownership (`KCD-38`) — only after decision 0.1

Skip entirely if the user chose route (b); that closes upstream.

| # | ID | Step | Done when |
|---|---|---|---|
| 6.1 | `KCD-38` | Add a covering case per existing sender first — six sites, each with its own `section` payload (testing-§4). | Six cases, green against today's code. |
| 6.2 | `KCD-38` | Add `NS.PublishConfigChanged(section)` in `core/State.lua` as the single publisher; make `settings/Panel.lua:75-91`'s `FireConfigChanged` delegate to it. | The function exists and is reachable from `core/`, `modules/` and `settings/`. |
| 6.3 | `KCD-38` | Convert the other five `NS:SendMessage("Ka0s_KickCD_CONFIG_CHANGED", …)` sites (`core/KickCD.lua:128,457`; `modules/IconGrid.lua:522`; `modules/Castbar.lua:333`; `settings/Spells.lua:325`) to call it. | `grep -rn 'SendMessage("Ka0s_KickCD_CONFIG_CHANGED"' core/ modules/ settings/` returns **exactly one** line. |
| 6.4 | `KCD-38` | Add a case pinning that invariant, so a sixth sender cannot come back quietly. | Case exists and reddens when a second `SendMessage` of that message is added. |
| 6.5 | `KCD-38` | Update `docs/message-bus.md:61` and `docs/ARCHITECTURE.md`'s Message Bus table to name the single sender. | Docs and code agree. |

---

## Sprint 7 — Close-out

| # | Step | Done when |
|---|---|---|
| 7.1 | Full green gate: `lua tests/run.lua`, `luacheck .`. | 0 failures, 0 warnings / 0 errors. |
| 7.2 | Re-run both vendor diffs: `diff -r ../LibKa0s/LibKa0s libs/LibKa0s` and `diff -r ../LibKa0s/testkit tests/_kit`. | **Both empty.** Any upstream change made during this work has landed as a re-vendor commit here (library-stack-§7). |
| 7.3 | Regenerate `docs/test-cases.md`; confirm `README.md:7` matches its total. | Badge = inventory = runner. |
| 7.4 | Run `docs/smoke-tests.md` in-game — settings panel, debug console, perf step panel, icon grid, cast bar, both units. | Recorded. |
| 7.5 | If a release is cut: bump TOC `## Version`, `NS.VERSION`, the `[wow]` badge if the Interface moved, `## What's new` and the top `## Version History` row — all in one change (documentation-§1 item 5, versioning-git). | Done or explicitly deferred. |
| 7.6 | Re-run `/wow-addon:standards-audit` into a **new** dated folder. Never edit this one. | A fresh `docs/audits/<date>/` bundle exists. |

---

## Sequencing summary

```
Sprint 0 (decisions)  ──┐
Sprint 1 (docs, additive) — independent, ship any time
Sprint 2 (test kit)   ──┬─→ Sprint 3 (Options de-dup)
                        └─→ Sprint 4 (tests/perf.lua)
Sprint 5 (stringifier) — independent
Sprint 6 (bus)         — needs decision 0.1
Sprint 7 (close-out)   — last
```

Only two hard dependencies: Sprint 2 before Sprint 3 (change the mock or the code under test, never
both at once) and Sprint 2 before Sprint 4 (`tests/perf.lua` should use the kit's `Loader.tocFiles`
rather than have its load list written twice). Sprint 1 and Sprint 5 can be done at any point,
including first, and Sprint 1 closes three of the ten deviations with no code risk at all.

**Deviations closed per sprint:** S1 → `KCD-35`, `KCD-37`, `KCD-39`. S2 → `KCD-30`. S3 → `KCD-31`,
`KCD-32`. S4 → `KCD-34`. S5 → `KCD-33`. S6 → `KCD-38`. `KCD-36` is touched by S2/S4 and confirmed in
S7.
