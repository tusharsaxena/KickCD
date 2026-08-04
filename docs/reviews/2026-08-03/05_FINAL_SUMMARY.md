# KickCD — Final Summary (2026-08-03 review cycle)

> **Status: forward-looking.** This document is written on the assumption that every change in
> `02_PROPOSED_CHANGES.md` has been applied per `04_EXECUTION_PLAN.md` and every case in
> `03_SMOKE_TESTS.md` has passed. Fill in the bracketed placeholders (`[…]`) when the work lands.

---

## Headline

This cycle finished a migration that was almost, but not quite, complete. When KickCD adopted
`LibKa0s-Options-1.0`, it correctly made its `Helpers` table *be* the library instance rather than a
copy — but it kept five pre-extraction implementations (`EnsureScroll`, `AddSpacer`, `AttachTooltip`,
`LSMValues`, and the `ROW_VSPACER` constant) and assigned them **onto that instance**. Because the
library's own widget makers reach those members through the instance, KickCD was quietly running its
own copies inside library code paths — the exact drift the shared library exists to prevent, pointed
inward where nothing would ever report it. Those copies are gone. Alongside that, the addon's second
hand-rolled secret-value stringifier was replaced by the shared one, three hard library resolutions in
the settings layer were made survivable, a settings-probe that could persist a wrong value on an error
path was made safe, and six smaller hygiene items were cleared. No user-facing feature changed.

---

## Counts

- **Critical fixed:** 0 (none were raised)
- **High fixed:** 2 — F-001, F-002
- **Medium fixed:** 5 — F-003, F-004, F-005, F-006, F-007
- **Low fixed:** 4 — F-008, F-009, F-010, F-011

**Deliberately deferred:** none. All eleven findings are addressed in this cycle.

**Not in scope, recorded for the next audit:** the byte-level `diff -r` between
`libs/LibKa0s/` and the LibKa0s source repo (required by `library-stack-§7` / anti-pattern #45) could
not be run — no `LibKa0s` checkout exists on this machine. `tests/test_vendor_sync.lua` pins the
vendored payload against the tag the README names, which is necessary but not the same check.

---

## Changes by theme

### Theme A — Finish the LibKa0s-Options de-duplication

**What changed.** `settings/Panel.lua` no longer defines or publishes `EnsureScroll`, `AddSpacer`,
`AttachTooltip` or `LSMValues`; the settings panel renders entirely through the vendored library's
implementations. The eight schema rows that wrapped `H.LSMValues(...)` in a closure now take the
library's deferred closure directly. The host copies of `PADDING_X` and `ROW_VSPACER` are gone; the
landing-page body keeps a clearly-named host constant, which `options-ui-§8` explicitly sanctions
because the landing body is the host's. The Options stub's justification comments were re-measured
against a library-absent load and rewritten to describe what the code actually does.

**Why it mattered.** Two implementations of one thing is the failure mode the whole `LibKa0s`
extraction was built to end, and this instance was the worst shape of it: the duplicate was installed
*over* the original, so the library's five widget makers ran host code. One contract had already
diverged — the library's `AddSpacer` returns the widget it creates and the host's returned nothing —
which meant the first library minor to use that return would break in this addon and nowhere else,
with no test anywhere going red to say so.

**Finding IDs covered:** F-001, F-004, F-007. **Change IDs:** C-01, C-02, C-03.

**Files touched:**
- `settings/Panel.lua`
- `settings/Panel_Widgets.lua`
- `settings/Panel_Render.lua`
- `settings/Icons.lua`
- `settings/Castbar.lua`
- `settings/Label.lua`
- `settings/OptionsSetup.lua`
- `core/Constants.lua`
- `tests/test_options_panel.lua`

### Theme B — One secret-safe stringifier, one detection mechanism

**What changed.** `Compat.DebugInterrupt`'s private `safeRender` and the equivalent inline handling in
`modules/Castbar_Debug.lua` now delegate to `NS.SafeToString` — the value published from
`LibKa0s-Core-1.0` in `core/CoreSetup.lua`. The `isSecret=` columns in both dumps keep their
`issecretvalue` probe, because reporting whether a value is secret is what those commands are *for*;
only the stringification moved.

**Why it mattered.** `events-frames-taint-§8` requires secret detection to probe `table.concat`, and
names exactly one sanctioned second copy of the stringifier (the library-absent branch of
`core/CoreSetup.lua`). The private copy detected via `issecretvalue` alone and fell through to
`("%q"):format(value)` — so any value the probe missed would raise inside `/kcd debug interrupt`, the
one command a user runs *because* they are chasing a secret-value problem in combat.

**Finding IDs covered:** F-002. **Change IDs:** C-04.

**Files touched:**
- `core/Compat.lua`
- `modules/Castbar_Debug.lua`

### Theme C — Survivable library resolution in the settings layer

**What changed.** The three load-time `LibStub("AceGUI-3.0")` calls in `settings/Panel.lua`,
`Panel_Widgets.lua` and `Panel_Render.lua` now read the resolution off the Options instance, fall back
to a silent `LibStub(..., true)`, and every widget-creating function short-circuits on a nil AceGUI.

**Why it mattered.** `options-ui-§1` names AceGUI *survivable, not a dependency*. A hard resolution at
file load meant a corrupted install did not degrade — it raised inside `settings/Panel.lua`, taking
`Helpers.Get` / `Set` / `SetAndRefresh` / `FindSchema` / `ValidateSchema` / `AnchorValues` with it, so
the page files that evaluate those at load raised too and a third of the schema silently never
registered. That is the same silent half-load the load-completing Options stub was designed to prevent,
arriving through a different door.

**Finding IDs covered:** F-003. **Change IDs:** C-05.

**Files touched:**
- `settings/Panel.lua`
- `settings/Panel_Widgets.lua`
- `settings/Panel_Render.lua`

### Theme D — Correctness and hygiene

**What changed.** Five independent fixes: `NS.Slash.GateHint`'s transient profile write is now
`pcall`-protected so the restore always runs; the `castTick` perf bracket is closed on its early exit;
`/kcd debug castbar` always prints a line for the interruptibility state; `.pkgmeta` excludes the
`.superpowers` and `.claude` scratch directories from the shipped zip; ten orphaned `enUS` keys were
removed; and `docs/message-bus.md`'s emitter rule was rewritten so it no longer contradicts the emitter
table three lines above it.

**Why it mattered.** The `GateHint` one is the only user-affecting item: an unwound probe loop would
have persisted a probe candidate into `KickCDDB`, so a user typing an *invalid* value could silently
end up with a *different* setting changed and saved. The rest are maintenance risk — an under-counted
perf bucket is a report that misleads (`performance-§3`), a diagnostic that prints nothing is worse
than one that prints a caveat, and a translator copying `enUS.lua` should not spend effort on strings
that render nowhere.

**Finding IDs covered:** F-005, F-006, F-008, F-009, F-010, F-011. **Change IDs:** C-06, C-07, C-08,
C-09, C-10, C-11.

**Files touched:**
- `settings/Slash.lua`
- `modules/Castbar.lua`
- `modules/Castbar_Debug.lua`
- `.pkgmeta`
- `locales/enUS.lua`
- `docs/message-bus.md`
- `tests/test_perfsetup.lua`
- `tests/test_locale.lua`

---

## API / behavior changes

- **Slash commands:** none added, renamed or removed. `/kcd` grammar is unchanged.
- **Saved variables:** no schema change, no migration. `db.global.schemaVersion` stays at **4**.
- **Defaults:** unchanged.
- **Settings UI:** one visible difference. When **no** LibSharedMedia media of a given type is
  registered, the affected dropdown's single placeholder entry now reads the library's
  `LSM_NONE` label instead of the string `Default`. This only appears on an installation missing
  LibSharedMedia; with the vendored copy present it is unreachable.
- **Diagnostics:** `/kcd debug interrupt` renders plain strings without surrounding `%q` quotes;
  `/kcd debug castbar` gains one always-present line under `current.notInterruptible`.
- **Locale keys removed** (all had zero call sites): `Show Target label`, `Target label text`,
  `Focus label text`, `Debug`, `Print every internal message to chat. Useful for diagnosing module
  wiring.`, `Allowed values: %s`, `Setting not found: %s`, `Invalid value for %s`,
  `Usage: /kcd get <path>`, `Usage: /kcd set <path> <value>`. No keys added or renamed.
- **Packaged artifact:** the CurseForge zip no longer contains `.superpowers/` or `.claude/`.

---

## Saved-variable / migration notes

**None.** No change in this cycle touches the stored shape. `db.global.schemaVersion` remains **4** and
the migration chain (`v1→v2` FoldLegacyUnits, `v2→v3` MigrateSpecKeys, `v3→v4` MigrateColorShape) is
untouched. Existing profiles load unchanged; no `/kcd resetall` is required.

The one data-integrity fix (C-06) is preventive: it stops a rare error path from *writing* a wrong
value. It does not repair a value already written by that path. A user who suspects their
`castbar.orientation` flipped unexpectedly can correct it with `/kcd reset castbar.orientation`.

---

## Deprecated-API migrations

**None.** The pre-change audit of this cycle found no deprecated API calls anywhere outside
`core/Compat.lua`, which owns every one of them behind a shim per `compat`. No `GetSpellInfo`,
`UnitAura*`, `GetContainerItemInfo`, `IsAddOnLoaded`, `LoadAddOn`, `InterfaceOptions_AddCategory` or
bare `GetAddOnMetadata` call site exists in `core/` (excl. Compat), `modules/` or `settings/`. Every
`SetBackdrop` call site already uses `"BackdropTemplate"`.

| Old API | New API | Files |
|---|---|---|
| *(none required)* | — | — |

---

## Performance impact

| Measurement | Before | After | Notes |
|---|---|---|---|
| `collectgarbage("count")` delta, open panel → all six subcategories → close | `[…]` KB | `[…]` KB | C-01 removes one duplicate closure set; expected neutral-to-better |
| `GetAddOnCPUUsage("KickCD")` over 30s of cast-bar activity | `[…]` | `[…]` | C-07 adds one conditional on a teardown path only; expected unchanged |
| `castTick` bucket `calls` over three casts | `[…]` | `[…]` | Should increase by exactly one per cast teardown (the previously-dropped exit) |

Fill from `03_SMOKE_TESTS.md`'s "Performance spot-checks" section.

---

## Known follow-ups

1. **Vendor-sync verification (`library-stack-§7`, anti-pattern #45).** `diff -r <LibKa0s repo>/LibKa0s
   libs/LibKa0s` could not be run — no LibKa0s checkout exists on this machine. Deferred because it is
   an environment gap, not a code change; `tests/test_vendor_sync.lua` covers the tag but not the bytes.
2. **`docs/performance.md` and `docs/perf-runs/README.md`** are required by `documentation-§3` and are
   absent. Deferred deliberately: enumerating pre-existing standard deviations is
   `/wow-addon:standards-audit`'s job, not a review's, and they are unrelated to any finding here.
3. **`Ka0s_KickCD_CONFIG_CHANGED`'s five emitters.** C-11 fixed the *documentation* contradiction, not
   the design. Whether the message should be narrowed to a single owning module (`architecture-§4`'s
   default) or stay multi-module by recorded justification is a design question worth its own pass —
   too large to fold into a review-remediation cycle, and the doc now states the position honestly.
4. **`Helpers.PADDING_X` upstream.** C-02 kept the landing-page inset as a host constant under
   `options-ui-§8`'s carve-out. If a second Ka0s addon ever needs the header's `PADDING_X` for a
   bespoke widget, the compliant move is an additive publication of `L.PADDING_X` onto the Options
   instance, pushed upstream and re-vendored — never a host copy.

---

## Verification evidence

- Completed checklist with its sign-off table filled in: `docs/reviews/2026-08-03/03_SMOKE_TESTS.md`
- Gates: `luacheck .` → `[…]`; `lua tests/run.lua` → `[…] passed, 0 failed`
  (pre-change baseline: `0 warnings / 0 errors`, `648 passed, 0 failed`)
- Commit range: `[…]` … `[…]`
- PR: `[…]`

---

## Suggested commit message / PR description

```
review(2026-08-03): finish the LibKa0s-Options de-duplication and the secret-stringifier convergence

settings/Panel.lua still carried five pre-extraction implementations that
LibKa0s-Options-1.0 now provides — EnsureScroll, AddSpacer, AttachTooltip,
LSMValues and the ROW_VSPACER constant — and assigned them onto the library
INSTANCE. The library's five widget makers reach those members through the
instance, so every one of them was running KickCD's copy instead of the
library's: the drift the extraction exists to end, pointed inward where no
repo goes red to report it. One contract had already diverged (the library's
AddSpacer returns its widget; ours returned nothing), which would have broken
here and nowhere else on the next library minor. All five are deleted; the
panel renders entirely through the library. (F-001, F-004, F-007)

core/Compat.lua's DebugInterrupt carried a second secret-safe stringifier
detecting via issecretvalue alone and falling through to ("%q"):format() —
so a value the probe missed raised inside the one command you run BECAUSE
you are chasing a secret in combat. It now delegates to NS.SafeToString,
LibKa0s-Core-1.0's, whose detection is the mandated table.concat probe;
the isSecret= reporting column is unchanged. (F-002)

The settings layer's three hard LibStub("AceGUI-3.0") calls are now silent
and instance-sourced with guarded creators: options-ui-§1 names AceGUI
survivable, and a raise in Panel.lua took the whole schema down with it.
(F-003)

Plus: GateHint's transient profile write now restores under pcall, so a
raising values() can no longer persist a probe candidate into KickCDDB
(F-005); the castTick perf bracket closes on its early exit (F-008);
/kcd debug castbar always prints an interruptibility line (F-009);
.pkgmeta excludes .superpowers and .claude (F-006); ten orphaned enUS keys
removed (F-010); docs/message-bus.md's emitter rule no longer contradicts
its own emitter table (F-011).

No schema change, no migration, no slash-grammar change. Findings and
design: docs/reviews/2026-08-03/.
```
