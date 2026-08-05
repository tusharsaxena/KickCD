# KickCD — Manual Smoke Tests (in-client)

**Date:** 2026-08-05
**Run this after** the changes in `02_PROPOSED_CHANGES.md` have been applied.
**Scope:** only what requires a logged-in game client. Everything headless — `luacheck`, the 737-case
harness, `lua tests/run.lua --list`, `lizard` — was already run in Step 0 and is recorded in
`01_FINDINGS.md`. Do not re-do it here.

---

## Pre-flight

1. **One command, before you log in:**
   `luacheck . && lua5.1 tests/run.lua && diff <(lua5.1 tests/run.lua --list) docs/test-cases.md`
   All three must be clean. If the harness is red, stop — do not smoke-test a red build.
2. **Client:** Retail / Midnight. `KickCD.toc:1` declares `## Interface: 120007`; confirm the client
   build matches or the addon will show as out of date.
3. **Install:** copy the repo folder to `Interface/AddOns/KickCD`. Confirm `KickCD` is enabled in the
   AddOns list and `## DefaultState: enabled` took.
4. **Make failures visible:** `/console scriptErrors 1`, then `/reload`.
5. **Characters needed:**
   - **A** — any spec with at least two interrupt/CC spells in the default list (a Death Knight,
     Shaman or Mage is easiest). Used for most tests.
   - **B** — optional second character on a different class, for the profile/spec tests.
6. **Back up SavedVariables** (`WTF/Account/<ACCT>/SavedVariables/KickCD.lua` and
   `KickCD.lua.bak`) before starting — several tests reset settings deliberately.
7. **Location:** the Stormwind / Orgrimmar training-dummy area. You need a target dummy that casts
   (Valdrakken's or a dungeon trash pack) for the cast-bar tests; a plain dummy is enough for the
   cooldown tests.

---

## C-001 — Cast-bar spell-name color now honors the setting

**Change covered:** C-001 — route cast-bar name color through `Util.Unpack` (F-001).

**Setup**
- Character A, out of combat.
- Fresh SavedVariables is *not* required — testing a **migrated** profile is more valuable here.
  Use your existing profile.

**Steps**
1. `/kcd config` → **Cast bar** page.
2. Under **Interruptible casts**, click the **Spell name color** swatch. Set it to a strongly
   distinct color — pure red, `R 255 G 0 B 0`, alpha 100%. Accept.
3. Target a mob that casts (a caster trash pack, or use the Valdrakken dummies). Wait for a cast bar.
4. Read the spell name text on the bar.
5. Under **Uninterruptible casts**, set **Spell name color** to pure blue (`R 0 G 0 B 255`).
6. Find a mob casting an **uninterruptible** spell (most boss casts with a shielded bar; a
   dungeon boss or the "Cannot be interrupted" trash cast). Read the spell name.
7. `/kcd get units.target.castbar.interruptible.nameTextColor` — note the printed value.
8. `/reload`, re-target a caster, and re-read the spell name.

**Expected**
- Step 4: the spell name renders **red**, not white.
- Step 6: the spell name renders **blue**.
- Step 7: prints the keyed color you set (r=1, g=0, b=0, a=1), not four ones.
- Step 8: still red after a reload — the value round-tripped through SavedVariables.

**Pass / Fail**
PASS only if the name text color visibly matches the configured color in **both** interruptible and
uninterruptible states, **and** survives `/reload`. Any white name with a non-white setting is a FAIL.

**Note for the tester:** this is the regression this whole review found. Before the change the name
was white in every case. If it is still white, C-001 did not land.

---

## C-004 — Perf brackets close on their early exits

**Change covered:** C-004 — `cdText` / `castTick` bracket closure (F-005).

**Setup**
- Character A. `/kcd debug on` so the console shows perf lifecycle lines.

**Steps**
1. `/kcd perf` — read the workflow it prints.
2. Start a capture per the library's guided protocol: `/kcd perf start`, take the **clean** arm
   first, then suspend for the second arm. Open both windows on your combat **state** (start each
   window as you enter combat), and do **not** `/reload` between arms.
3. During the clean arm: pull a caster pack so at least one cast bar runs to completion, and use
   two spells so cooldown text ticks for several seconds.
4. `/kcd perf report`.
5. Read the `cdText` and `castTick` rows: note the **calls** count for each.
6. `/kcd perf dump` and commit the record under `docs/perf-runs/` as
   `<YYYY-MM-DD>-client-<label>.json`.

**Expected**
- `cdText` and `castTick` both report a **non-zero `calls`** count.
- The counts are plausible against the run: `castTick` should be roughly (frames per second ×
  seconds of cast time observed); `cdText` roughly (10 × seconds any cooldown was visible).

**Pass / Fail**
PASS if both buckets report calls and the counts are within the same order of magnitude as the
back-of-envelope above. **Read the bucket figures, not the frame-time delta between arms** — that
delta is unresolved below the harness's own run-to-run spread and must not be used to judge this.

---

## C-006 — Reset fires each config section once

**Change covered:** C-006 — `Helpers.ResetAll` stops re-running `afterRestoreAll`'s work (F-004).

**Setup**
- Character A. `/kcd debug on`, `/kcd debug window` to open the console.
- First, make the reset *visible*: drag the icon grid well off center, unlink Focus
  (Settings → Icons → Focus → uncheck "Mirror Target"), and change a couple of colors.

**Steps**
1. Clear the console (`Clear` button).
2. `/kcd resetall`.
3. Read the console.
4. Observe the icon grid and the cast bar on screen.
5. `/kcd config` → check that Focus's **Mirror Target** is back on, and colors are back to defaults.
6. Repeat via the UI path: Settings → General → **Reset all settings** → confirm.

**Expected**
- The grid snaps back to its default screen position; the cast bar likewise.
- Focus's link flag is restored.
- The console shows the `Cooldowns` rebuild line **once**, not twice, per reset.
- No Lua error popup.

**Pass / Fail**
PASS if both the slash and the popup path fully restore positions, links, settings and spells, and
the rebuild is not duplicated. A duplicated rebuild line is a FAIL for this change (the reset itself
still working is necessary but not sufficient).

---

## C-007 — A failing dropdown probe leaves the gate setting alone

**Change covered:** C-007 — `GateHint` restores under `pcall` (F-006).

**Setup**
- Character A. Note the current value: `/kcd get units.target.castbar.orientation`.

**Steps**
1. `/kcd set units.target.castbar.orientation HORIZONTAL`.
2. `/kcd set units.target.castbar.growDirection UP` — an invalid value for the horizontal
   orientation, which is what triggers the gate hint.
3. Read the rejection line printed in chat.
4. `/kcd get units.target.castbar.orientation`.
5. `/reload`, then `/kcd get units.target.castbar.orientation` again.

**Expected**
- Step 3: the error names the allowed values **and** appends
  `(depends on units.target.castbar.orientation = HORIZONTAL)` plus a "flip … for …" hint.
- Step 4: still `HORIZONTAL`. The probe restored it.
- Step 5: still `HORIZONTAL` after reload — nothing was persisted.

**Pass / Fail**
PASS if `orientation` reads `HORIZONTAL` at both step 4 and step 5, and the cast bar's on-screen
orientation is unchanged throughout.

---

## C-008 — Capture protocol and the committed record

**Change covered:** C-008 — commit the record the bucket design cites (F-007).

**Setup**
- Character A, in a dungeon or a busy world pull — the capture is only worth what the load under it
  is worth.

**Steps**
1. `/kcd perf start`.
2. **Arm 1 (clean):** fight normally for a full combat. Do not `/reload`. Do not change the addon set.
3. **Arm 2 (suspended):** `/kcd perf suspend` (or whatever verb the workflow prints), fight a
   comparable combat.
4. `/kcd perf report`, then `/kcd perf dump`.
5. Save the JSON to `docs/perf-runs/<YYYY-MM-DD>-client-<label>.json` and commit it. Do not modify,
   tidy or delete any existing capture in that directory.
6. Confirm `docs/perf-runs/README.md` explains what the new file is.

**Expected**
- The record stamps a real addon version (`1.2.1`), never `v?` — this is what
  `core/PerfSetup.lua:78-86` and `tests/test_perfsetup.lua:500` exist to guarantee.
- The record stamps a real client interface version, never `0`.
- The `spellPoll` / `pollSpell` / `spellState` / `iconApply` nesting renders indented, and
  `visibility` renders un-nested (it is deliberately not declared `within` — `core/PerfSetup.lua:114`).

**Pass / Fail**
PASS when a committed capture exists in `docs/perf-runs/` with a real version stamp and all eight
declared buckets present. **Do not sum a parent bucket with its children** when reading it.

---

## Regression suite (not tied to one change)

| # | Check | Expected |
|---|---|---|
| R-1 | `/reload` from a clean login | No error popup; grid and cast bar reappear in place |
| R-2 | Delete `KickCD.lua` from SavedVariables, log in fresh | Defaults populate; grid appears at its default position; no error |
| R-3 | Log in and watch through `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` | No Lua error at any stage; `/kcd debug window` shows the `[Init]` summary line with a real version, schema version and profile name |
| R-4 | Enter combat, leave combat, with the grid and cast bar visible | Both stay visible/hide per the visibility setting; no `Interface action failed because of an AddOn` red text |
| R-5 | `/kcd config` **during combat** | Prints the gray "cannot open settings during combat" notice and does **not** open the panel (`core/KickCD.lua:779-783`) |
| R-6 | Open Settings from **Esc → Options → AddOns → Ka0s KickCD**, out of combat | Panel opens; the left tree is **expanded** showing General / Icons / Cast bar / Label / Spells / Profiles |
| R-7 | Open every page and toggle every option at least once | No error; each toggle takes effect immediately without `/reload` |
| R-8 | AceDB profile switch (Profiles page → new profile → back) | Widgets re-read the new profile; grid re-anchors; no error |
| R-9 | `/kcd list`, `/kcd get <path>`, `/kcd set <path> <v>`, `/kcd reset <path>` | All four answer; `list` groups by page in the order general, icons, castbar, label, spells, profiles (`settings/Slash.lua:265`) |
| R-10 | `/kcd reset general` (a retired page name) | Prints the "is gone — `reset` now takes a setting path" guidance, not "Setting not found" |
| R-11 | `/kcd spells list`, `add`, `remove`, `enable`, `disable`, `category`, `reset`, `resetall` | Each answers; an open Spells panel refreshes without reopening |
| R-12 | Change spec, then change back | Grid rebuilds for the new spec's list both ways |
| R-13 | Summon and dismiss a pet (Hunter/Warlock) with a pet interrupt in the list | The icon appears on summon and disappears on dismiss |
| R-14 | Drag the grid unlocked, then `/kcd lock` | Position persists across `/reload` |
| R-15 | `/kcd debug on` / `off` / `toggle` / `window` | The flag and window follow; the General page's "Debug console" checkbox mirrors the window's visibility, including when the window is closed with **Esc** |

---

## Taint-specific tests

The review raised **no** `[taint]` findings, but C-006 and R-5/R-6 touch the settings-category path,
which is the classic taint surface. Run these two:

| # | Check | Expected |
|---|---|---|
| T-1 | Enter combat with a target dummy; while in combat click an action-bar slot the addon has never touched, then `/kcd config` | The action fires normally; the config notice prints; **no** `Interface action failed because of an AddOn` red text at any point |
| T-2 | Out of combat, open the panel from `/kcd config` **and** separately from Esc → Options | Both routes open the same parent category with the tree expanded; neither produces a taint error, and switching between subpages works after each route |

---

## Performance spot-checks

Covered by **C-004** and **C-008** above — the in-client `/kcd perf` two-arm capture is the check.
Two rules while reading it:

- **Bucket figures only.** The frame-time delta between the clean and suspended arms is unresolved
  below the harness's measured run-to-run spread; do not build a conclusion on it.
- **Same addon set, no `/reload` between arms.** Reloading shifts shared-frame ownership, which is
  the exact confound the suspend mechanism exists to avoid (`core/PerfSetup.lua:123-127`).

The offline scenarios are **not** part of this checklist — they run headless.

---

## Localization sanity

The review raised **no** `[locale]` findings (all 263 `L[...]` keys resolve). One low-cost
confirmation is still worth doing because C-001 changes what a settings row *does*:

1. Switch the client to **deDE** or **frFR** and `/reload`.
2. Open Settings → Cast bar. Confirm the **Spell name color** row's label and description render in
   the client language (or fall back to the English key text, never to `nil` or a blank row).
3. Re-run the C-001 steps 1–4 in that locale.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-001 | | | |
| C-002 | n/a — headless | n/a | Covered by the pre-flight harness run |
| C-003 | n/a — headless | n/a | Covered by the pre-flight harness run |
| C-004 | | | |
| C-005 | n/a — headless | n/a | Covered by the pre-flight harness run |
| C-006 | | | |
| C-007 | | | |
| C-008 | | | |
| C-009 | n/a — headless | n/a | Exit criterion is 737/737 + clean inventory diff |
| C-010 | n/a — headless | n/a | Covered by the pre-flight `luacheck` run |
| R-1 … R-15 | | | |
| T-1, T-2 | | | |
