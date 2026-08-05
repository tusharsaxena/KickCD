# KickCD — Proposed Changes (HLD + LLD)

**Date:** 2026-08-05
**Derived from:** `01_FINDINGS.md` (F-001 … F-012)
**Standard resolved:** Ka0s WoW Addon Standard **v2.21.0, 2026-08-04**. The cross-check was
performed; it was **not** skipped. Section files were read from the local read-only
`WowAddonStandards` checkout after verifying it matches the remote for a fetched section.

---

## Upstream change-set

**Empty.** No proposed change targets a path under `libs/` or `tests/_kit/`. F-008's remediation
*consumes* `tests/_kit/` and must not edit it.

---

## HLD — themes

### Theme A — One color shape, one unpacker (F-001)

**Rationale.** The addon already made the decision: colors are stored keyed, migrated once at
v3→v4, and every seam reads them through `NS.Util.Unpack`. Exactly one helper never got the memo,
and it is the one behind a user-facing setting. The fix is not to add tolerance — it is to delete
the second unpacker so there is only one place that can be wrong again.

**Alternatives considered.**
- *Make `rgba` shape-agnostic in place.* Rejected: it would be a second copy of `Util.Unpack`'s
  logic, and the next divergence lands the same way.
- *Add a positional↔keyed translation at the descriptor seam.* Rejected explicitly —
  `settings/Slash.lua:35-39` records that the migration was chosen over a translation layer because
  *"a translation layer is a thing to keep correct forever, whereas a migration runs once."*
  Re-introducing one here contradicts the addon's own written decision and `options-ui-§1`.

**Trade-off.** `rgba` is on the per-cast (not per-frame) path; `Util.Unpack` costs one extra
branch. Negligible: `ApplyState` runs on cast start/stop and interruptibility flips, not in
`onUpdate`.

### Theme B — Make the silent skips loud (F-002)

**Rationale.** A gate that cannot answer must say so in the output a human reads, not only in a
comment. The value of `test_vendor_sync` is entirely in *whether it looked*.

**Alternative considered.** *Fail hard when the sibling is missing.* Rejected as the default: it
would redden every fresh clone and every CI box, and the standard's own position is that a
non-running suite is a **skip stated plainly**, never a pass and never an invented failure. An
opt-in strict mode is offered instead.

### Theme C — One options-registration path, and no dead public surface (F-003)

**Rationale.** `anti-patterns` and `options-ui-§1` are unambiguous that a subsystem the vendored
library provides is not to be kept in a private parallel copy. Two registration mechanisms means a
change to page ordering, deferral or category registration has two homes.

**Alternatives considered.**
- *Delete the library forwarders and keep the private path.* This is the smaller change and is
  offered as **C2** (a fallback), because the private bootstrap has real behavior the library's
  does not obviously replicate (the `ADDON_LOADED == "Blizzard_Settings"` arm at
  `settings/Panel.lua:612`). But it leaves the fork standing.
- *Delete the private path outright in this pass.* Rejected as too large for a review-driven
  change-set touching the panel every user opens; it is scheduled as its own milestone with its own
  checkpoint.

### Theme D — Instrumentation that measures what it claims (F-005, F-007, F-004)

**Rationale.** Three defects with one root: the perf story is asserted rather than recorded. Close
the two unclosed brackets, widen the test that pins the rule, stop double-firing the reset fan-out,
and give the addon the offline scenario the standard expects so the next claim has a number under it.

### Theme E — Consume the kit that is already vendored (F-008)

**Rationale.** Byte-identity is gated on a payload nothing loads. Adopting it deletes three local
copies and buys the collect-then-run guarantee the kit exists to provide.

### Theme F — Comment and surface hygiene (F-009, F-010, F-011, F-012)

Small, independent, zero-risk.

---

## LLD — change-set

### C-001 — Route cast-bar name color through the single unpacker

**Covers:** F-001
**Files:** `modules/Castbar.lua`
**Risk:** low. Behavior change is intended and user-visible.

Before (`modules/Castbar.lua:724-729`):

```lua
local WHITE = { 1, 1, 1, 1 }
local function rgba(c)
    c = c or WHITE
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end
```

After — delete `rgba` and `WHITE`; at `:740`, `:747-748` call the existing helper:

```lua
frame.nameText:SetTextColor(unpackColor(intCfg.nameTextColor, 1, 1, 1, 1))
...
local ur, ug, ub, ua = unpackColor(unintCfg.nameTextColor, 1, 1, 1, 1)
local ir, ig, ib, ia = unpackColor(intCfg.nameTextColor,   1, 1, 1, 1)
```

`unpackColor` is already file-local at `:228-231` and already delegates to `NS.Util.Unpack`, which
handles both shapes and defaults each channel to 1 — so the `WHITE` fallback is subsumed, not lost.

Also convert the two fallback tables to the stored shape so nothing in the file carries the
positional form any more:

- `modules/Castbar.lua:571-576` — `barColor`, `bgColor`, `nameTextColor`, `borderColor` → keyed.
- `modules/Castbar.lua:581-586` — same four.

These tables are published as `Castbar.INT_FALLBACK` / `.UNINT_FALLBACK` (`:1304-1305`) and read by
`modules/Castbar_Skin.lua` through `Castbar.UnpackColor`, which accepts either shape — so the
conversion is safe. **Check the suites that assert on those tables** before landing.

**Regression pressure:** this adds cases (see C-002 below), so `docs/test-cases.md` and the README
`[tests]` badge (`README.md:7`) must move **in the same commit** (`testing-§5`).

### C-002 — Cases pinning the keyed color shape end-to-end

**Covers:** F-001
**Files:** `tests/test_castbar.lua` (or `tests/test_castbar_skin.lua` — put it beside the existing
castbar color coverage), `docs/test-cases.md`, `README.md`

Two cases:

1. *"the spell-name color the profile stores is the color the bar paints"* — build the instance,
   write `units.target.castbar.interruptible.nameTextColor = { r = 0.2, g = 0.4, b = 0.6, a = 1 }`
   through `Helpers.SetAndRefresh`, drive `Castbar:ApplyState`, assert the mock FontString's
   recorded text color with `assertNear`. `-- red under: reverting C-001` — and it is red today,
   which is the falsification.
2. *"every profile color reaches its widget through Util.Unpack"* — a source guard over
   `modules/Castbar.lua` asserting no positional `c[1]`-shaped color read survives. Same shape as
   the existing guard at `tests/test_color_shape.lua:205-211`.

### C-003 — Name the skip in the vendor-sync gate

**Covers:** F-002
**Files:** `tests/test_vendor_sync.lua`
**Risk:** low.

Replace the two silent `if not tag then return end` bodies (`:140`, `:146`) with a registered case
whose **name carries the outcome**. Two options, and the plan takes both:

```lua
-- The name is the report. A reader scanning 737 PASS lines must be able to see
-- that this one did not look.
local tag = siblingTag()
if not tag then
    T.assertTrue(true, "skipped: no sibling LibKa0s checkout at " .. SIBLING)
    return   -- and rename the case: "... (or is skipped when the sibling repo is absent)"
end
```

plus an opt-in strict arm: when `os.getenv("KICKCD_REQUIRE_VENDOR_SYNC")` is set, a missing sibling
**fails** rather than skips — so CI that *does* check out the sibling cannot silently stop checking.

Do **not** weaken `assertVendorSync`'s byte-identity assertions (`:118-136`).

**Regression pressure:** case *names* change, so `docs/test-cases.md` must be regenerated in the same
commit; the count does not move.

### C-004 — Close both perf brackets on their early exits

**Covers:** F-005
**Files:** `modules/IconGrid_Render.lua`, `modules/Castbar.lua`
**Risk:** low.

`modules/IconGrid_Render.lua:831-837`, before:

```lua
if next(_textIcons) == nil then
    if _textTicker and _textTicker.Cancel then _textTicker:Cancel() end
    _textTicker = nil
    return
end
```

After — close the bracket on the way out, exactly as `Cooldowns:PollSpell` does at
`modules/Cooldowns.lua:192-195`:

```lua
if next(_textIcons) == nil then
    if _textTicker and _textTicker.Cancel then _textTicker:Cancel() end
    _textTicker = nil
    if __t0 then Perf.Note("cdText", debugprofilestop() - __t0) end
    return
end
```

`modules/Castbar.lua:694-697` takes the identical treatment for `castTick`.

### C-005 — Widen the exit-completeness case from PollSpell to every bracket

**Covers:** F-005
**Files:** `tests/test_perfsetup.lua`, `docs/test-cases.md`, `README.md`

Generalize `tests/test_perfsetup.lua:551-589` into a **source guard**: for each of the four bracketed
files, find every function containing `local __t0 = Perf.on and debugprofilestop()` and assert the
count of `return` statements between the open and the final `Perf.Note` is matched by an equal
number of `Perf.Note` lines with the same key. A static check is the honest instrument here — the
harness cannot drive `castTick` (needs a live cast) or `cdText` (needs the ticker), which
`tests/test_perfsetup.lua:120-123` already states.

`-- red under: deleting the new Note line from either early return in C-004.`

**Regression pressure:** +1 case (or +1 net if the PollSpell case is subsumed). Inventory and badge
move in the same commit.

### C-006 — Let `afterRestoreAll` own the non-schema reset

**Covers:** F-004
**Files:** `settings/Panel_Render.lua`
**Risk:** medium — this is the reset path; the ordering guarantee matters.

Before (`settings/Panel_Render.lua:259-266`):

```lua
function Helpers.ResetAll()
    Helpers.RestoreAllDefaults()
    Helpers.ResetAllPositions()
    Helpers.RestoreUnitLinks()
    if NS.Database and NS.Database.ResetAllSpells then NS.Database:ResetAllSpells() end
end
```

After:

```lua
function Helpers.ResetAll()
    -- RestoreAllDefaults runs the library's afterRestoreAll hook, which IS this
    -- addon's ResetAllPositions + RestoreUnitLinks (settings/OptionsSetup.lua:93).
    -- Calling them again here fired CONFIG_CHANGED twice for general/castbar/units
    -- and drove a second full Cooldowns:Rebuild. Spells are the only thing no
    -- schema row and no hook covers.
    Helpers.RestoreAllDefaults()
    if NS.Database and NS.Database.ResetAllSpells then NS.Database:ResetAllSpells() end
end
```

**Risk note.** The degradation stub's `Helpers.RestoreAllDefaults`
(`settings/OptionsSetup.lua:187-196`) *already* calls both helpers itself, so the LibKa0s-absent path
keeps working unchanged — verify with the existing library-absent load
(`tests/run.lua:100`'s `opts = { libFiles = {} }`).

### C-007 — Make `GateHint`'s probe restore unconditionally

**Covers:** F-006
**Files:** `settings/Slash.lua`
**Risk:** low.

`settings/Slash.lua:118-129`, after:

```lua
local hints = {}
for candidate in pairs(gateValues) do
    if candidate ~= gateVal then
        -- The raw write is deliberate: this is a transient probe, and firing the
        -- notify path for a value we are about to undo would publish a config
        -- change that never happened. What it MUST NOT do is leave the profile
        -- mutated, so the restore runs even when `values()` raises.
        parent[key] = candidate
        local ok, alt = pcall(allowedKeys, row)
        parent[key] = gateVal
        if ok and #alt > 0 then
            hints[#hints + 1] = ("flip %s to %s for %s")
                :format(row.valueGate, tostring(candidate), table.concat(alt, "/"))
        end
    end
end
```

Add a case: *"a raising values() leaves the gate setting untouched"* — stub `row.values` to `error()`
and assert the stored value is unchanged. `-- red under: removing the pcall.`

### C-008 — Commit the capture behind the bucket design, and add the zero-overhead scenario

**Covers:** F-007
**Files:** `docs/perf-runs/README.md`, `docs/perf-runs/<YYYY-MM-DD>-client-buckets.json` (new,
produced in-client — see `03_SMOKE_TESTS.md`), `docs/performance.md` (new),
`tests/perf.lua` (new), `core/PerfSetup.lua` (citation only)
**Risk:** low — additive.

1. Run the two-arm `/kcd perf` protocol in client and commit the record. `docs/perf-runs/` is
   append-only; never rewrite a capture.
2. Add the citation to `core/PerfSetup.lua:105-113` so the 125.02 / 51.14 / 73.9 ms figures name
   the file that holds them.
3. Add `tests/perf.lua` with, minimally, the scenario `performance-§9`/`§2` require: the hottest
   bracketed path (`Icon:Apply`, the `iconApply` bucket, per `core/PerfSetup.lua:28-33`) driven N
   times with capture **off**, asserting allocation and API-call counts equal to the same path with
   the instrumentation absent. **No wall-clock assertion** — that is forbidden outright and is a
   flake generator. Derive its addon load list from the TOC via the same reader
   `tests/loader.lua:41-55` uses; do not hand-maintain a second list.
4. Its scenarios are **not** test cases: they must not appear in `docs/test-cases.md` and must not
   move the README `[tests]` badge (`testing-§7`).

Once `tests/perf.lua` exists, the next `/wow-addon:automated-tests` run turns
`suites.perf.status` from `skip` to a real result — note that as an expected movement, not a task.

### C-009 — Adopt the vendored test kit

**Covers:** F-008
**Files:** `tests/run.lua`, `tests/loader.lua`, `tests/wow_mock.lua`
**Risk:** medium — it is the harness itself. Exit criterion is a byte-identical
`docs/test-cases.md` and an unchanged 737/737.

- `tests/run.lua`: replace the private micro-framework (`:19-90`) and the `--list` renderer
  (`:189-238`) with `tests/_kit/framework.lua`. Keep `loadInstance` (`:95-121`) — that is genuinely
  this addon's.
- `tests/loader.lua`: replace `makeEnv`/`runFile`/`loadAll` (`:57-101`) with `tests/_kit/loader.lua`'s
  equivalents. **Keep `readTOCOrder` and `LIB_FILES` as they are** — the TOC derivation and the
  explicitly-pinned library order are correct today and are gated by
  `tests/test_coresetup.lua:374` / `tests/test_perfsetup.lua:433`.
- `tests/wow_mock.lua:573`: build on `tests/_kit/mock_base.lua`'s builder instead of porting it.
- **Never edit `tests/_kit/`.** If the kit lacks something the addon needs, the compliant direction
  is an additive member pushed upstream into LibKa0s and re-vendored as its own commit — not a local
  copy and not a patch in place.

**Note on `__newindex`.** The kit's `makeEnv` (`tests/_kit/loader.lua:20-23`) routes sandbox writes
to `_G`; `tests/loader.lua:71-77` has no `__newindex`. That is a real behavior difference —
SavedVariables globals and `StaticPopupDialogs` registrations will now land in `_G`. Expect suite
churn there and resolve it in the harness, never by editing a case to change a result.

### C-010 — Comment and surface hygiene

**Covers:** F-009, F-010, F-011, F-012
**Files:** `core/PerfSetup.lua`, `settings/Slash.lua`, `tests/test_coresetup.lua`,
`modules/Castbar.lua`, `.luacheckrc`
**Risk:** none.

- `core/PerfSetup.lua:108` — "All four of PollSpell's exits" → "Both of PollSpell's exits".
- `settings/Slash.lua:211` and `tests/test_coresetup.lua:360` — the AbsorbTracker citation names
  this repo's path with a line that does not exist. Name the repo, drop the line number.
- `modules/Castbar.lua:1312` — delete `NS.Castbar = Castbar`, or, if it is a deliberate public
  surface, say so and add it to `docs/module-map.md`. Grep first: zero readers today.
- `.luacheckrc:29` — drop `InterfaceOptionsFrame_OpenToCategory`. Re-run `luacheck .`; it must stay
  0/0 over 32 files.

---

## Standards conformance (per change)

| Change | Conformance |
|---|---|
| C-001 | Keeps one storage shape and one unpacker (`savedvariables`; `options-ui-§1`'s single-seam intent). The rejected alternative — a positional↔keyed translation layer — is the one the addon's own record already rejected (`settings/Slash.lua:35-39`) |
| C-002 | `testing-§5`: inventory + badge move in the same change. Both cases carry a `-- red under:` note per `testing-§12` |
| C-003 | `testing-§12`: a case must be able to go red, and a skip is stated plainly rather than read as a pass. The byte-identity assertions are untouched, per the vendor rule |
| C-004 | `performance-§3`: every bracketed exit closes, so declared bucket call counts are true |
| C-005 | `testing-§12` again — the new case is falsifiable by exactly the mutation C-004 fixes |
| C-006 | `options-ui-§1`: the library instance is decorated in place and its hook owns what it declares; the host does not re-run it |
| C-007 | Keeps the documented single write seam's meaning intact (`options-ui-§1`) by making the bypass provably transient rather than removing it |
| C-008 | `performance-§2` (dormant bracket is free — now measured), `-§9` (offline scenarios, no wall-clock assertion), `-§8` (a record is attributable); `testing-§7` (scenarios are not test cases); `testing-§9` (TOC-derived load list); `docs/perf-runs/` stays append-only |
| C-009 | `testing-§8`: the addon owns integration coverage of its wiring, not a fork of the shared harness. No edit under `tests/_kit/`; upstream gaps go upstream additively |
| C-010 | `lint` (allowlist reflects real call sites); `public-api` (no exported surface without a consumer) |

**No change in this document targets a path under `libs/` or `tests/_kit/`.**

---

## Expected movement for the next release's regeneration

- **Test count:** +3 to +4 (C-002 ×2, C-005 ×1, C-007 ×1), less any case C-005 subsumes.
  `docs/test-cases.md` and `README.md:7` move with the commit that moves the count.
- **`suites.perf`:** `skip` → a real status once C-008 lands `tests/perf.lua`.
- **Complexity watch list:** nothing here is expected to move it. C-001 removes a 4-line function;
  C-006 removes two statements. The fresh `lizard` run reports **zero** functions over CCN 15 today,
  and none of these changes adds a branch. To be confirmed by the next release's regeneration —
  **not** regenerated as part of this work.
