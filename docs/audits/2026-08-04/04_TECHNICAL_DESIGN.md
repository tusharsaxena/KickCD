# KickCD — Remediation Technical Design (2026-08-04)

**Standard:** v2.17.1 (2026-08-03). Keyed to the IDs in `02_DEVIATIONS.md`.

This is a **design**, not a change. The audit is read-only; remediation is a separate engagement
that executes `05_EXECUTION_PLAN.md`.

---

## Themes

The nine MUSTs are not nine unrelated jobs. They sort into four themes plus two one-liners, and the
ordering between them matters in exactly two places.

| Theme | IDs | Shape |
|---|---|---|
| **A — Finish the LibKa0s adoption** | `KCD-30`, `KCD-31`, `KCD-32`, `KCD-33` | Delete host code the vendored library already provides. Four separate deletions, one rule (AP-47). |
| **B — Close the performance evidence gap** | `KCD-34`, `KCD-35`, `KCD-39` | The wiring is done and good; the *evidence* and the *docs* are missing. Additive only. |
| **C — README lockstep** | `KCD-36`, `KCD-37` | Two one-line edits plus making the badge rule mechanical. |
| **D — Bus ownership** | `KCD-38` | A design decision, not an edit. Needs the user. |

**Ordering constraints — only two, and both are real:**

1. `KCD-30` (adopt the kit) should land **before** `KCD-31`/`KCD-32`, because deleting the host
   Options members changes what the suite exercises and it is better to be running the shared mock's
   widget fakes when that happens than to change both the code under test and the mock underneath it
   in one step. If they must be reordered, do `KCD-31` first and `KCD-30` second — never together.
2. `KCD-34` depends on `KCD-30` only if the perf runner is written against the kit's
   `Loader.tocFiles` (which testing-§9 requires). Writing `tests/perf.lua` before the kit adoption
   means writing its load list twice.

Everything else is independent and can land in any order.

---

## Theme A — Finish the LibKa0s adoption

### KCD-30 — adopt the vendored test kit

**Files:** `tests/run.lua`, `tests/loader.lua` (deleted), `tests/wow_mock.lua`, `tests/perf.lua`
(new, see `KCD-34`).

**Shape.**

```lua
-- tests/run.lua
local Kit    = dofile(root .. "/tests/_kit/framework.lua")
local Loader = dofile(root .. "/tests/_kit/loader.lua")
local mockmod = dofile(root .. "/tests/wow_mock.lua")

Kit.expose(_G.KICKCD_TEST)                  -- keeps the repo's own global name and extra keys
...
os.exit(Kit.run{ dir = "tests/", suites = { ... } })
```

- Delete `tests/run.lua:19-83` (registry, `test()`, the assertion set, the `--list` renderer) and
  `tests/loader.lua` entirely. The addon's own `loadInstance` factory (`tests/run.lua:88-…`) —
  the lifecycle kick, the `{ libFiles = {} }` degraded-path option, the `mutate` hook — **stays**;
  that is genuinely this addon's and testing-§1 says to keep exactly it.
- Rebuild `tests/wow_mock.lua` as `local base = dofile("tests/_kit/mock_base.lua")` plus a builder
  that calls `base()` and overwrites the keys KickCD actually needs. Delete the ported widget
  builder at `:559-…` outright — the comment at `:556-558` already says that is the intent.
- Re-derive the addon's own file list with `Loader.tocFiles("KickCD.toc")`; keep the explicit
  `LibKa0s.xml` file list (testing-§9 requires it to be explicit) and keep
  `tests/test_coresetup.lua`'s case comparing that list against the XML file-for-file.

**Risk: medium-high, and concentrated in the mock.** 648 cases run against `wow_mock.lua`; the kit's
`mock_base.lua` is a different implementation of the same fakes. The two are not guaranteed
behaviourally identical, and a mock that is *friendlier* than the current one will turn a real
failure green rather than red — which is the failure mode testing-§1's fidelity rules exist to
prevent.

**Mitigation, and it is not optional:** land the kit adoption with the suite count **unchanged at
648, case-for-case**, and diff `lua tests/run.lua --list` before and after — it must be identical.
Any case that changes status during this step is a mock-fidelity difference to understand, never to
paper over. If a case cannot be made to pass under the shared mock, that is a **finding for the
LibKa0s repo** (an additive `mock_base` improvement, pushed upstream and re-vendored), never a local
patch to `tests/_kit/` (testing-§1, library-stack-§7).

**What NOT to do:** do not edit anything under `tests/_kit/`. The byte-identity gate
(`tests/test_vendor_sync.lua:144`) will go red, and it is right to.

### KCD-31 — delete the host copies of library Options members

**Files:** `settings/Panel.lua`, `settings/Icons.lua`, `settings/Label.lua`, `settings/Castbar.lua`.

Delete from `settings/Panel.lua`: `Helpers.LSMValues` (`:276-291`), `attachTooltip` +
`Helpers.AttachTooltip` (`:309-341`), `ensureScroll` + `Helpers.EnsureScroll` (`:348-394`),
`addSpacer` + `Helpers.AddSpacer` (`:432-443`). Point the in-file callers at the instance —
`BuildMainContent` (`:469`) becomes `Helpers.EnsureScroll(ctx)`.

**The one non-mechanical part** is `LSMValues`, because the shapes differ: the host's returns a
**table**, the library's (`libs/LibKa0s/Options.lua:485`) returns a **closure** fed by the
descriptor's existing `getLSM` seam (`settings/OptionsSetup.lua:104`). Every call site is currently
`values = function() return H.LSMValues(m) end` and becomes `values = H.LSMValues(m)` — the closure
the library hands back **is** the `values` function the schema row wants. Sites:
`settings/Icons.lua:196,220`; `settings/Label.lua:147`;
`settings/Castbar.lua:280,401,438,463,500`.

**User-visible change to flag:** when no media library is loaded, the empty-media fallback key moves
from the host's `"Default"` to the library's `LSM_NONE`. That is one dropdown entry in a degraded
install; it is the correct direction (one vocabulary across the collection), but it should be named
in the change, not discovered.

**Keep:** `Helpers.AnchorValues` (`:244-260`) and `Helpers.AnchorOrder` (`:266-274`). Those are
genuinely this addon's schema vocabulary and did not generalize — exactly what options-ui-§1 allows
the instance to be decorated with.

**Risk: medium.** Touches the render path of every settings page. `settings/Panel.lua:300-306`
already asserts the host and library scroll geometry agree (`PADDING_X - 4, -8` /
`-(PADDING_X + 12), 8`, both at 16), so this should be visually a no-op — but "should be" is what
the in-game smoke pass is for.

### KCD-32 — stop restating library layout constants

**Files:** `settings/Panel.lua`, `core/Constants.lua`, and (for the `PADDING_X` half) the LibKa0s
repo.

Two halves with two different answers:

- **`ROW_VSPACER` — pure deletion.** Delete `settings/Panel.lua:426` and `:430`. The library already
  publishes `O.ROW_VSPACER` (`libs/LibKa0s/Options.lua:159`) and
  `settings/Panel_Render.lua:20` already reads it off the instance — it just currently reads the
  host's overwrite. `settings/Panel_Widgets.lua:47-49` is already correct and its comment already
  states the rule.
- **`PADDING_X` — an upstream change first.** The library does **not** publish `PADDING_X` on the
  instance today (it publishes `ROW_VSPACER`, `SECTION_HEADING_H`, `BUTTON_PAIR_REL` at
  `Options.lua:159-161`), so there is nothing to read it off. The compliant route is an **additive**
  `O.PADDING_X = L.PADDING_X` in `LibKa0s-Options-1.0`, with its file-minor bump and changelog entry,
  pushed to `../LibKa0s`, then a **re-vendor commit** here (library-stack-§7), then delete
  `Const.PANEL_PADDING_X` and read `Helpers.PADDING_X`.

**Explicitly rejected:** editing `libs/LibKa0s/Options.lua` in this repo to add the field. The next
re-vendor silently reverts it and the regression has no cause anywhere in this repo's history
(library-stack-§7, AP-45). `CLAUDE.md:52` already says "Never edit `libs/`".

**Interim, if the upstream minor cannot land in the same cycle:** keep `Const.PANEL_PADDING_X` and
add a one-line comment at `core/Constants.lua:66` naming `KCD-32` and the upstream field it is
waiting on. A deviation with its reason and its exit condition written down is a decision; the same
line without them is the drift options-ui-§8 describes.

### KCD-33 — one stringifier, one detection mechanism

**File:** `core/Compat.lua`.

Delete `safeRender` (`:377-387`). Route every value through `NS.SafeToString` — the library's own
function, already published at `core/CoreSetup.lua:110`. The `%q` quoting that made the host copy
feel necessary is presentation, not safety, so it wraps the shared result:

```lua
local function render(v)
    local s = NS.SafeToString(v)
    return (type(v) == "string" and s ~= NS.SafeToString(nil)) and ("%q"):format(s) or s
end
```

(or simply drop the quoting — `DebugInterrupt` already prints a `type=` column, which is what the
quotes were disambiguating.)

Replace `local out = (NS.Util and NS.Util.print) or _G.print` (`:372`) with the shared printer
alone; `core/CoreSetup.lua` guarantees `NS.Util.print` exists on both the library and degraded
paths, so the `_G.print` arm is unreachable in practice and forbidden in principle.

**Keep `issecretvalue` at `:401`.** It is the command's *reporting* column — "is this value secret?"
is the diagnostic payload of `/kcd debug interrupt`. What must stop is `issecretvalue` being the
*safety* mechanism at `:378`; the mandated probe is `table.concat`, which is what
`NS.SafeToString` does.

**Risk: low.** One command, already exercised by `tests/test_compat.lua` /
`tests/test_compat_api.lua`. Add a case that feeds `DebugInterrupt` a value the mock reports as
concat-hostile and asserts the sentinel appears — and prove the case can fail by mutating the render
back to raw `tostring` (testing-§12).

---

## Theme B — Close the performance evidence gap

### KCD-34 — `tests/perf.lua`

**New file.** Derives its addon-file list through `Loader.tocFiles` (testing-§9 — hence the
dependency on `KCD-30`), loads the addon under the mock, and ships scenarios asserting **only**
deterministic quantities.

Minimum content, and the section names it: a **zero-overhead scenario** over the addon's hottest
bracketed path. `core/PerfSetup.lua:19-31` has already identified that path and why —
`iconApply`, driven at ~10 Hz per spell on cooldown by `C_Spell.GetSpellCooldownDuration` minting a
fresh handle per call. So:

- run `Icon:Apply` N times with `NS.Perf.on = false`, with a full `collectgarbage("collect")` either
  side, recording `collectgarbage("count")` delta and call counts;
- run the same N times with `NS.Perf` replaced by the absent-library stub;
- assert the first allocates **no more** than the second.

Add a second scenario for `Cooldowns:PollSpell` if it is cheap to drive. Output states plainly that
any timings printed are orientation-only.

**Hard constraints:** it lives at exactly `tests/perf.lua`, is **not** run by `tests/run.lua`
(testing-§7), asserts nothing on wall clock (performance-§9), and its scenarios are **not** counted
in `--list` or the `[tests]` badge. Add a gated case that reads `tests/perf.lua`'s source for the
`Loader.tocFiles` call, since the gate never runs the file itself (testing-§9).

### KCD-35 — `docs/performance.md` + `docs/perf-runs/README.md`

**`docs/performance.md`** — mostly a **move**, not new writing. The bucket rationale, the nesting
reasoning and the two capture-driven corrections are already written, in
`core/PerfSetup.lua:19-31` and `:104-122`. Relocate the reader-facing half there (which paths are
bracketed and why; how to run `/kcd perf`; how to read the report; what the harness can and cannot
resolve — buckets are the addon's cost, the frame-time delta is unresolved below the harness's
spread). Point at LibKa0s for the shared protocol and the record contract; do not restate them.
Leave the *why this line of code is here* comments in the source.

**`docs/perf-runs/README.md`** — the naming convention
(`<YYYY-MM-DD>-<source>-<label>.json`), a schema summary, and the pointer to the library's canonical
field-by-field contract. State that the directory is standing and cumulative rather than tied to one
investigation. Commit the first real capture beside it — a README heading an empty directory is a
promise, not a store.

Link both from `docs/ARCHITECTURE.md`'s topic-detail index and from `CLAUDE.md`'s pointer list.

**Risk: none.** Pure addition; no code path changes.

### KCD-39 — `docs/complexity.md`

`lizard core modules settings defaults locales -l lua > docs/complexity.md`, with a generated-by
header naming the command. **MUST NOT** gate commits. Regenerate when a file it names changes
materially. If `lizard` is not installed locally, this stays open and is recorded as such — the
section says absent tooling makes the report stale, not the addon non-compliant.

---

## Theme C — README lockstep

### KCD-36 — the `[tests]` badge

`README.md:7` → `Tests-648%2F648_passing`. Then make it mechanical rather than remembered: the
regeneration (`lua tests/run.lua --list > docs/test-cases.md`) and the badge edit belong in the same
commit, every time. `CLAUDE.md:56` already states the rule verbatim — the gap is execution, so the
durable fix is to fold the badge line into whatever step already regenerates the inventory rather
than to restate the rule a fourth time.

Note: `KCD-30` and `KCD-34` may both move the count. Do this **last** in the sprint that touches
tests, not first.

### KCD-37 — the README placeholder

`README.md:191`: `` `/kcd reset <setting>` `` → `` `/kcd reset setting` ``, matching `README.md:75`.
**Do not** sweep `<br>` from `README.md:210-211` — documentation-§1 protects deliberate HTML by
name, and a regex sweep is exactly how that gets broken.

---

## Theme D — Bus ownership (`KCD-38`)

**Not an edit. A decision, then an edit.** `Ka0s_KickCD_CONFIG_CHANGED` has six senders across five
files; architecture-§4 says one. The addon has recorded it as intentional
(`docs/message-bus.md:61`), but that record does not itself satisfy the standard, and the addon's
own softer rule ("a second emitter must live in the same file as the first") is not met either.

Two coherent ends — pick one, do not stay in the middle:

**(a) Narrow to one owning module.** `settings/Panel.lua:75-91` (`Helpers.FireConfigChanged`) is
already the natural owner: it is the settings layer's single fan-out point and the write seam
already routes through it. The other five sites publish through `Helpers.FireConfigChanged(section)`
instead of `NS:SendMessage(...)` directly. Cost: `modules/IconGrid.lua` and `modules/Castbar.lua`
would then depend on a `settings/` helper, which inverts the layering — so the owner may instead
want to be a small `NS.PublishConfigChanged(section)` in `core/State.lua`, with `FireConfigChanged`
delegating to it. That keeps one sender, in `core/`, that everything can reach.

**(b) Take it upstream.** Argue in `WowAddonStandards` that a settings-changed fan-in message is a
legitimate shape and that architecture-§4's one-sender MUST needs a carve-out with its own
constraints (a single named publisher function, even if several modules call it). If the standard
changes, KickCD conforms to the new rule and this ID closes without code movement.

**Recommendation:** (a), in the `core/State.lua` variant. It is a mechanical refactor with a clear
invariant ("`SendMessage("Ka0s_KickCD_CONFIG_CHANGED", …)` appears exactly once in the tree"), it is
testable by a grep-shaped case, and it does not require a standard change to unblock the other eight
deviations. But it is the user's call, per `CLAUDE.md:11-14`.

**Risk: medium.** Six call sites, each currently passing a different `section`. A covering case per
site must exist before the refactor, not after.

---

## Cross-cutting notes

- **Nothing in this design touches `libs/` or `tests/_kit/`.** Two findings (`KCD-32`'s `PADDING_X`
  half, and any mock-fidelity gap surfaced by `KCD-30`) route **upstream** to `../LibKa0s` as
  additive changes, each with its file-minor bump, changelog entry and a standalone re-vendor commit
  here (library-stack-§7, versioning-git).
- **The green gate applies to every step.** `lua tests/run.lua` green and `luacheck .` clean before
  each commit (testing-§4, versioning-git). Both are green today, so any red is this work.
- **Test-first.** `KCD-31`, `KCD-32`, `KCD-33` and `KCD-38` all change behavior-adjacent code; each
  needs a failing case first (testing-§4), and any case asserting a negative needs its falsification
  proven by mutation with the mutation named in a comment (testing-§12).
- **No version bump is implied.** None of this is user-facing except `KCD-31`'s `LSM_NONE` fallback
  key and the two README edits. If a release is cut, `## What's new` and the top Version History row
  move together (documentation-§1 item 5).
