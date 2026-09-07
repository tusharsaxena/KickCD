# 03 — Manual smoke tests (in-client)

**Repo:** KickCD v1.2.1 · **Derived from:** `02_PROPOSED_CHANGES.md` · **Date:** 2026-09-07

Everything that runs headless in a shell was already run in Step 0 and lives in `01_FINDINGS.md`'s
measurement block. **This document is only for what needs a logged-in game client.**

---

## Pre-flight

**One command, not a suite.** After the changes land, re-run the two gates once from the repo root and
confirm they are green before you log in:

```
luacheck .            # expect: 0 warnings / 0 errors
lua5.1 tests/run.lua  # expect: N passed, 0 failed, 0 skipped  (N = 842 or 843 after C-02/C-04)
```

Then:

1. **Interface version.** `KickCD.toc` declares `## Interface: 120007`. Test on a Retail client at
   patch **12.0.7 (Midnight)**. Do not test on Classic — this addon is Retail-only and its secret-value
   handling (`C_CurveUtil`, `CastingDuration` objects) has no Classic equivalent.
2. **Character.** Any character with an interrupt on a short cooldown and at least one **charged** spell,
   so both the plain and the charge-recharge cooldown paths are exercised. A Death Knight (Mind Freeze +
   Death Grip) or a Warlock (the character in the committed capture) is ideal.
3. **Install shape.** Copy the built addon folder to
   `World of Warcraft/_retail_/Interface/AddOns/KickCD`. For §C-01 you additionally need **at least one
   other AceGUI + LibSharedMedia addon whose options panel has a border picker** installed and enabled —
   any Ace3 addon exposing an `LSM30_Border` widget. Note its name here: `________________`.
4. **Errors visible.** `/console scriptErrors 1`, then `/reload`. A red error popup during any step below
   is an automatic FAIL for that step regardless of the stated criterion.
5. **Event tracing (only if a step below asks for it).** `/etrace` and filter to `PLAYER_LOGIN`,
   `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`.
6. **Baseline SavedVariables.** Before starting, copy
   `_retail_/WTF/Account/<ACC>/SavedVariables/KickCD.lua` somewhere safe. Several steps need a
   **fresh** SavedVariables (delete the file, then `/reload`); this is how you get back.

---

## Per-change tests

### §C-01 — LSM border patch moves into LibKa0s

**Change covered:** C-01 — `core/LSMPatch.lua` deleted; the fixup applied once, from the library, via
`settings/OptionsSetup.lua`.

This is the **highest-risk change in the set** and needs the most in-client attention, because it is
entirely cosmetic, entirely client-side, and has no headless coverage at all.

#### C-01a — KickCD's own border dropdown is still tidy

- **Setup:** existing SavedVariables. Out of combat, standing still, in a city.
- **Steps:**
  1. `/kcd config`
  2. Click the **Icons** page.
  3. Find the **Border** group's border-texture dropdown (an `LSM30_Border` widget).
  4. Take a screenshot.
- **Expected:** the dropdown's closed bar starts flush at the group's left edge, in line with the sliders
  and checkboxes above and below it. There is **no** empty ~42 px square to the left of the bar and **no**
  42 px gap between the label and the bar.
- **Pass / Fail:** PASS only if the row is visually indistinguishable from the same row before the change.
  Compare against `media/screenshots/kickcd.image.03.icons.png` if in doubt. Any horizontal shift of the
  bar or reappearance of the preview tile is a FAIL.

#### C-01b — the fixup still applies when KickCD's panel is opened first

- **Setup:** fresh `/reload`. Do **not** open any other addon's options first.
- **Steps:**
  1. `/reload`
  2. `/kcd config` → **Castbar** page → the **Border** group's border dropdown.
- **Expected:** the same tidy layout as C-01a.
- **Pass / Fail:** PASS if tidy. A FAIL here specifically means the patch is being applied **too late** —
  the risk called out in `02_PROPOSED_CHANGES.md` C-01's risk note, where the library patches on the
  caller's frame instead of deferring to `PLAYER_LOGIN`. Report it as a library bug, not an addon bug.

#### C-01c — the fixup still applies when the OTHER addon's panel is opened first

- **Setup:** fresh `/reload`.
- **Steps:**
  1. `/reload`
  2. Open the **other** addon's options panel first and browse to its border picker.
  3. Close it. Now `/kcd config` → **Icons** → the border dropdown.
- **Expected:** KickCD's dropdown is tidy.
- **Pass / Fail:** PASS if tidy. This is the ordering the old `PLAYER_LOGIN` hook was written to survive;
  a FAIL means the idempotence sentinel is checking the wrong thing.

#### C-01d — the other addon is no longer collaterally patched (the actual point of C-01)

- **Setup:** fresh `/reload`, with the other addon enabled.
- **Steps:**
  1. `/reload`
  2. Open the **other** addon's options and go to its border picker.
  3. Screenshot it.
  4. Now disable KickCD in the AddOns list, `/reload`, and open the same picker again. Screenshot.
- **Expected:** the two screenshots are **identical**. The other addon's border-preview tile is present in
  both, or absent in both — KickCD's presence must not change it.
- **Pass / Fail:** PASS only if identical. This is the regression the whole change exists to prevent; if it
  is not fixed, C-01 has not achieved its purpose and should be reported as such rather than signed off.

#### C-01e — no double application with several Ka0s addons installed

- **Setup:** install **KickCD plus at least two** of AbsorbTracker / ConsumableMaster / MultiMeters /
  PanelMaster, all having adopted the library patch.
- **Steps:**
  1. `/reload`
  2. Open each addon's options in turn and view its border dropdown.
  3. `/console scriptErrors 1` must already be on; watch for any error popup.
- **Expected:** every dropdown is tidy; no errors; no visible layout difference between them.
- **Pass / Fail:** PASS if all tidy and error-free.

---

### §C-04 — locale keys reconciled

**Change covered:** C-04 — three cast-bar `desc` strings added to `locales/enUS.lua`, three stale keys
removed, plus a new headless coverage case.

- **Setup:** existing SavedVariables, enUS client.
- **Steps:**
  1. `/kcd config` → **Castbar** page.
  2. Hover the **Width** slider and read the tooltip body.
  3. Hover the **Height** slider and read the tooltip body.
  4. Hover the **Spell icon size** slider and read the tooltip body.
- **Expected:** exactly these three sentences, complete, with no key-looking text and no truncation:
  - *"Cast bar width in pixels. Overridden by Auto-size to icon grid while the bar is horizontal."*
  - *"Cast bar height in pixels. Overridden by Auto-size to icon grid while the bar is vertical."*
  - *"Spell icon size in pixels (0 hides the icon). Capped at the bar's short axis so the icon never
    overflows it."*
- **Pass / Fail:** PASS if all three render in full. Any tooltip showing a bare key, an empty body, or only
  the first sentence is a FAIL.

#### Localization sanity (required — this change touched user-facing strings)

- **Setup:** switch the client to **deDE** (Battle.net → Game Settings → Language). Restart the client.
- **Steps:** repeat steps 1–4 above.
- **Expected:** the three tooltips render the **English** sentences above, in full. KickCD ships only
  `locales/enUS.lua`, so the key-returning metatable fallback is the correct and intended behaviour on a
  German client.
- **Pass / Fail:** PASS if the sentences render in full English. A FAIL is a blank tooltip or a key with
  underscores. Switch the client back to enUS afterwards.
- **Note:** also confirm no tooltip line is broken by a non-breaking space (NBSP, `U+00A0`) — deDE
  tooltips commonly contain them and Lua's `%s` does not match one. KickCD does no tooltip-text pattern
  matching, so this is a spot-check, not an expected failure.

---

### §C-05 — the cast-bar debug dump speaks on its secret branch

**Change covered:** C-05 — `reportSecretNint` prints unconditionally.

- **Setup:** in combat with a **casting** hostile target, so `notInterruptible` is secret-tainted.
  A training dummy will not cast; use an outdoor mob that casts, or a dungeon trash pack.
- **Steps:**
  1. Enable the console: `/kcd debug on`
  2. Target a hostile caster and pull it. While it is **mid-cast**, run `/kcd debug castbar`
  3. Read the console output.
- **Expected:** the dump includes a `current.notInterruptible: type=…, isSecret=…` line **followed
  immediately** by a line beginning `secret-tainted; not rendered in Lua.` — never a gap where that line
  should be.
- **Pass / Fail:** PASS if the secret-tainted line is present. FAIL if the dump jumps straight from the
  `type=` line to the `duration:` line. Also FAIL on any red Lua error — that would mean a secret value
  reached a string operation, which this change must not introduce.
- **Cleanup:** `/kcd debug off`

---

### §C-06 — the anchor fallback removal

**Change covered:** C-06 — `Helpers.ResetIconPosition`'s hardcoded fallback deleted.

- **Setup:** **fresh SavedVariables** (delete `KickCD.lua`, `/reload`).
- **Steps:**
  1. `/kcd unlock` (or toggle **Locked** off on the General page) so the grids are draggable.
  2. Drag the **Target** icon grid to the bottom-left of the screen.
  3. `/kcd resetposition`
  4. Note where the grid lands. Screenshot with the default UI grid on if helpful.
  5. Repeat via the UI: `/kcd config` → **General** → **Reset position** button.
- **Expected:** in both cases the Target grid snaps to **CENTER / CENTER, x = 0, y = +120** — i.e.
  **above** screen centre, matching `defaults/Profile.lua:314`. It must **not** land 180 px *below* centre.
- **Pass / Fail:** PASS only if the grid lands above centre and the two routes agree with each other.
- **Regression check for the same change:** `/kcd resetall`, confirm at the "reset everything" prompt, and
  verify **both** the Target and Focus grids return to their defaults (Focus at y = +260, so the two do not
  overlap) and that your **profile list** is untouched — only the active profile's contents reset.

---

### §C-08 — cast-bar OnUpdate closure caching (only if C-08 was taken)

**Change covered:** C-08 — the per-cast closure is cached on the instance.

- **Setup:** cast bar enabled for Target. In combat with a casting hostile.
- **Steps:**
  1. Pull a caster. Watch the cast bar fill across a full cast, then complete.
  2. Let it cast **at least ten** more times without leaving combat.
  3. Switch target to a second caster mid-cast; watch the bar re-arm.
  4. Leave combat, re-enter, repeat once.
- **Expected:** the bar animates smoothly on every cast, drains correctly on channels, stops cleanly on
  interrupt/cancel, and re-arms on the new target. No frozen bar, no bar left filled after a cast ends, no
  error.
- **Pass / Fail:** PASS if all four hold. A bar that stops animating after the first cast means the cached
  closure is being reused against a stale `inst` — an immediate FAIL and a revert of C-08.
- **Performance evidence (do this only if C-08 was taken AND a `castStart` scenario was added to
  `tests/perf.lua`):** run the standard two-arm capture per §Performance below and compare the `castTick`
  bucket's `calls` and `totalMs` against
  `docs/perf-analysis/20260807-131311/dump.json` — `{"calls":1262,"maxMs":0.0560,"totalMs":11.6115}`.
  **Read the bucket figures, never the `deltaMsPerFrame`**: that capture's own delta is `-0.1740` ms,
  which is below the harness's run-to-run spread and therefore unresolved. If no scenario was added, make
  **no** performance claim for C-08 at all.

---

### §C-09 / §C-10 — mechanical renames

**Changes covered:** C-09 (`_G.` prefixes), C-10 (`print` parameter renamed to `emit`).

These have no independent in-client behaviour. They are covered by the Regression suite below, plus:

- **Steps:** `/kcd debug on`, then `/kcd debug castbar` with a target, then `/kcd debug off`.
- **Expected:** the dump renders in the console exactly as before, every line carrying the addon's
  `|cff00ffff[KCD]|r` prefix (or the console's own row format).
- **Pass / Fail:** PASS if the output is unchanged and prefixed. A line appearing in chat **without** the
  cyan `[KCD]` tag means the printer seam was broken by the rename — FAIL.

---

## Regression suite

Not tied to any one change; these cover what the change-set could plausibly break.

| # | Check | Expected | P/F |
|---|---|---|---|
| R-01 | `/reload` from a settled session | No error popup; grids and cast bars return exactly where they were | |
| R-02 | **Fresh SavedVariables** → login | Defaults populate; Target grid at centre+120, Focus at centre+260; spell list seeded for the current spec | |
| R-03 | Cold login: `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` | No error at any stage (`/etrace` to confirm ordering if one occurs) | |
| R-04 | Enter combat, leave combat, three times | Grids and bars show/hide per the **General visibility** mode; no error; no frame stuck visible or invisible | |
| R-05 | Change **General visibility** to each of Always / In combat / Target casting / Target casting (interruptible), testing each in combat | Each mode behaves as labelled; the interruptible mode alpha-masks rather than hides | |
| R-06 | Profile switch: `/kcd config` → **Profiles** → create "smoketest", switch to it, switch back | Panel re-reads on each switch; grids re-anchor; spell lists re-seed; **no error** | |
| R-07 | Profile **copy** and profile **reset** from the Profiles page | Only the active profile changes; the profile **list** survives (this is the `skipRestoreAll` veto) | |
| R-08 | Open the settings panel and toggle **every** option on every page at least once (General, Icons, Castbar, Label, Spells, Profiles) | No error; every toggle takes effect or is visibly disabled with a reason | |
| R-09 | Esc → Options → AddOns → Ka0s KickCD | The panel opens on its landing page, with the logo, tagline and slash-command rows | |
| R-10 | Every page draws its **tab strip**, and the strip's geometry does not move when you change tabs | Strip present on every page (Profiles is the documented exemption); tabs wrap rather than truncate | |
| R-11 | Link Focus to Target (**link** checkbox on), then change a Target appearance setting | Focus mirrors it; Focus's own tab strip is **disabled and desaturated** (this is what C-02's split case pins headlessly) | |
| R-12 | Unlink Focus, change a Focus-only setting | Focus keeps its own value; its tab strip is operable and **not** dimmed | |
| R-13 | Spec change (dual-spec swap or a talent-loadout switch) | Spell list rebuilds for the new spec; grid re-renders; no error | |
| R-14 | `/kcd list`, `/kcd get <path>`, `/kcd set <path> <value>`, `/kcd reset <path>` | Each answers through the `[KCD]` prefixed printer; a set is reflected in the open panel immediately | |
| R-15 | `/kcd reset general` (a retired verb) | The "it moved" message, naming the Defaults button and `/kcd reset <path>` — **not** "Setting not found" | |
| R-16 | `/kcd version` | Prints v1.2.1 (or the current version), never `?` | |
| R-17 | `/kcd spells resetall` | Every spec's list rebuilds from defaults; the profile survives | |
| R-18 | Drag both grids and both cast bars while unlocked, then `/reload` | Positions persist exactly | |

---

## Taint-specific tests

The review raised **no** taint findings, but the change-set touches the settings-panel wiring
(`settings/OptionsSetup.lua`, C-01/C-09), so the panel-open paths must be re-confirmed.

| # | Check | Expected | P/F |
|---|---|---|---|
| T-01 | **In combat**, type `/kcd config` | Refuses with the grey "Cannot open settings during combat." line. The panel does **not** open, and does **not** open later when combat drops | |
| T-02 | **In combat**, press Esc → Options → AddOns → Ka0s KickCD | Blizzard's own panel behaviour; no KickCD error, no `Interface action failed because of an AddOn` red text | |
| T-03 | **In combat**, click any in-panel link that jumps to another KickCD page (`Helpers.OpenPageTab`) | Refuses with the same grey line; no category switch | |
| T-04 | Enter combat with the settings panel **already open**, then toggle several options | Options apply; no red taint text; no error | |
| T-05 | Enter combat, then click an actionbar slot and cast from it | No `Interface action failed because of an AddOn` red text at any point in the session | |
| T-06 | Out of combat, `/kcd config` → navigate to **Spells** → reorder a row by dragging its handle → then enter combat | Reorder persists; no error; no taint text on the first actionbar click in combat | |

---

## Performance spot-checks

Only relevant if C-08 was taken **with** its scenario. The offline scenarios already ran headless in
Step 0 and are **not** part of this checklist.

The in-client check is KickCD's own harness, following the standard's two-arm protocol:

1. `/kcd perf start` — the **clean** arm first. Do **not** `/reload` between arms.
2. Fight for a sustained window with the grid and cast bar both active. Open and close the window on your
   **combat state**, not on a timer.
3. Follow the harness's prompts into the **suspended** arm (this is the second arm; suspend must make the
   addon inert without a reload — that is why `NS.Perf.suspended` is step 0 of both show decisions).
4. `/kcd perf report`, then `/kcd perf dump`.
5. Record the capture as a frozen bundle via `/wow-addon:perf-analysis`, producing
   `docs/perf-analysis/<YYYYMMDD-HHMMSS>/` with `report.md`, the verbatim `dump.json` and its `ANALYSIS.md`.

**How to read it.** Compare the **bucket figures** against the committed capture
`docs/perf-analysis/20260807-131311/dump.json`:

```
spellPoll   399 calls  135.2610 ms   (max 1.7497)
  pollSpell  1596 calls  67.1303 ms  (within spellPoll)
  spellState 1171 calls  54.3927 ms  (within spellPoll)
    iconApply 2342 calls 50.0322 ms  (within spellState)
cdText       225 calls   11.4686 ms
castTick    1262 calls   11.6115 ms
castEvent     11 calls    1.6358 ms
visibility    21 calls    1.6512 ms
```

Nested totals are **not disjoint** — `spellPoll` already contains `pollSpell` and `spellState`. Never sum
them. And do **not** build any conclusion on `fps.deltaMsPerFrame`: the committed capture's value is
`-0.1740` ms, which is below the harness's measured run-to-run spread and therefore unresolved.

Do **not** delete, rewrite or tidy the existing `20260807-131311` bundle. It is frozen evidence; a new
capture goes in a new dated folder beside it.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01a | | | |
| C-01b | | | |
| C-01c | | | |
| C-01d | | | |
| C-01e | | | |
| C-04 (enUS) | | | |
| C-04 (deDE) | | | |
| C-05 | | | |
| C-06 | | | |
| C-08 | | | |
| C-09 / C-10 | | | |
| R-01 … R-18 | | | |
| T-01 … T-06 | | | |
| Perf capture | | | |

**Tester:** ________________  **Client build:** ________________  **Date:** ________________
