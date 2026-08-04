# KickCD — Manual Smoke Tests (2026-08-03 review)

Run **after** the changes in `02_PROPOSED_CHANGES.md` have been applied. Every step is literal: type
what is written, click what is named, observe what is listed.

---

## Pre-flight

1. **Build/install.** Copy the repo folder to `World of Warcraft/_retail_/Interface/AddOns/KickCD`.
   Confirm `KickCD.toc` still reads `## Interface: 120007` and
   `## SavedVariables: KickCDDB, KickCDPerfDB`.
2. **Gates before you log in.** From the repo root:
   - `luacheck .` → must print `0 warnings / 0 errors`.
   - `lua tests/run.lua` → must print `0 failed` (baseline before this review: **648 passed, 0 failed**;
     C-07 and C-10 add cases, so the passed count should be *higher*, never lower).
3. **Make failures visible in game.** `/console scriptErrors 1`, then `/reload`.
4. **Character requirements.** A **Retail** character with an interrupt in its default spell list
   (any Death Knight, Rogue, Shaman, Mage, Warrior, Monk, Demon Hunter). You will need a hostile
   target that casts — the **Stormwind / Orgrimmar training dummies** do not cast, so use a low-level
   outdoor caster mob (e.g. any Elwynn Forest / Durotar caster) for the cast-bar cases.
5. **Two SavedVariables states are exercised below.** Keep a copy of your existing
   `WTF/Account/<ACCT>/SavedVariables/KickCD.lua` so you can restore the "existing profile" state after
   the fresh-install cases.

---

## Per-change tests

### C-01 — Host copies of library Options members deleted

**Change covered:** the settings panel now renders entirely through `LibKa0s-Options-1.0`'s scroll,
spacer, tooltip and media-list members.

**Setup:** existing SavedVariables (not fresh), out of combat, LibSharedMedia present (it is vendored).

**Steps:**
1. `/kcd config`
2. Click each subcategory in the left tree in turn: **General**, **Icons**, **Cast bar**,
   **Text Label**, **Spells**, **Profiles**.
3. On **Icons**, open the **Border** dropdown and then the **Font** dropdown.
4. On **Cast bar**, open the **Font**, **Bar texture** and **Border** dropdowns.
5. Hover the **Master scale** slider on **General** and hold for 2 seconds.
6. Resize the game window (or toggle UI scale under Esc → Options → Graphics) and return to
   `/kcd config`.

**Expected:**
- No Lua error popup at any point.
- Every page shows a vertical scrollbar on the right, **including short pages** (General), parked at
  the top and greyed out where the content fits (`options-ui-§10`).
- Right-edge gutter width is visually identical between General (short) and Icons (long) — content
  must not shift horizontally when switching tabs.
- Both dropdowns in step 3 and all three in step 4 list at least one entry and open cleanly.
- Step 5 shows a tooltip with the setting's label in white and its description below.
- After step 6 the scrollbar still tracks the new body height.

**Pass / Fail:** PASS iff no Lua error, every listed dropdown populates, and the right gutter is the
same width on General and Icons. FAIL on any `attempt to call field 'EnsureScroll'`,
`'AddSpacer'`, `'AttachTooltip'` or `'LSMValues'` (a nil value), which means a call site was missed.

**Extra case — no media library.** Temporarily rename
`libs/LibSharedMedia-3.0` to `libs/LibSharedMedia-3.0.off`, `/reload`, reopen the Icons page and open
the **Border** dropdown. Expected: the dropdown opens and offers exactly one entry (the library's
`LSM_NONE` label — note it is **no longer** the string `Default`; that change is intentional and is
what this case is confirming). Restore the folder and `/reload`.

### C-02 — Host copies of library layout constants deleted

**Change covered:** `Const.PANEL_PADDING_X` and `Panel.lua`'s local `ROW_VSPACER` are gone;
`Helpers.ROW_VSPACER` is the library's.

**Setup:** as C-01.

**Steps:**
1. `/kcd config` → **Icons**.
2. Take a screenshot. Compare the vertical gap between two adjacent widget rows, and the left inset of
   the page title, against a screenshot taken **before** the changes (or against
   `media/screenshots/kickcd.image.03.icons.png`).
3. Open the **parent** landing page (click "Ka0s KickCD" in the left tree). Confirm the logo's left
   edge lines up with the page title's left edge.

**Expected:** pixel-identical row spacing and title inset; the landing-page logo still left-aligns with
the title.

**Pass / Fail:** PASS iff no visible geometry change. Any shift means the landing-page
`MAIN_PADDING_X` value in C-02 does not match the library's `PADDING_X` (16).

### C-03 — Options stub comments corrected + stub member set re-measured

**Change covered:** the load-completing stub's justification, and its member set after C-01 moved
`LSMValues` back to the library.

**Setup:** **this is the critical case for C-01.** Rename `libs/LibKa0s` to `libs/LibKa0s.off` and
comment out the `libs\LibKa0s\LibKa0s.xml` line in `KickCD.toc`. Restart the client (a `/reload` will
not re-read the TOC).

**Steps:**
1. Log in. Watch the chat frame during load.
2. `/kcd list`
3. `/kcd get castbar.height`
4. `/kcd config`
5. `/kcd resetall`
6. Restore `libs/LibKa0s` and the TOC line; restart the client.

**Expected:**
- Step 1: **no** Lua error popup. One `[KCD]`-tagged line naming the missing library.
- Step 2: `/kcd list` says the verb is unavailable and names the missing library — but the addon has
  not half-loaded.
- Step 3: same shape of message.
- Step 4: one `[KCD]` line: *"The LibKa0s library is missing from this installation of KickCD
  (expected in libs/LibKa0s), so the settings panel is unavailable."*
- Step 5: prints `all settings + spells reset to defaults` — the global reset stays real with no panel
  (`options-ui-§1`).

**Pass / Fail:** PASS iff step 1 produces zero Lua errors **and** the headless case
`tests/test_options_panel.lua` (which pins `#NS.Settings.Schema` against the fully-loaded environment)
is green. A schema row count lower than the loaded count means the stub is missing a load-time member
that C-01 introduced — the stub must grow `LSMValues` back.

### C-04 — `Compat.DebugInterrupt` on the shared stringifier

**Change covered:** `safeRender` now delegates to `NS.SafeToString`.

**Setup:** target a hostile caster mob **out of combat** first, then **in combat**.

**Steps:**
1. Target a caster mob that is not in combat with you. `/kcd debug interrupt`
2. Pull the mob. While it is mid-cast and you are in combat: `/kcd debug interrupt`
3. `/kcd debug castbar` while the same cast is running.

**Expected:**
- Step 1: a `[KCD]`-tagged block listing `UnitCastingInfo positions` 1–9 (or
  `UnitCastingInfo: not casting`), each row `type=… isSecret=false value=…`.
- Step 2: the same block. Positions that came back protected show `isSecret=true` and
  `value=<secret>`. **No Lua error**, and no `invalid value (secret) at index N in table for 'concat'`.
- Step 3: the castbar dump prints a `current.notInterruptible:` line **and** a following line
  (see C-08) in every case.

**Pass / Fail:** PASS iff both invocations complete with no Lua error and every `value=` cell is either
a rendered value or the `<secret>` sentinel. FAIL on any raise, or on a `value=` cell showing a raw
`table: 0x…` for a string field.

### C-05 — Survivable AceGUI resolution

**Change covered:** three hard `LibStub("AceGUI-3.0")` calls made silent + guarded.

**Setup:** rename `libs/AceGUI-3.0` to `libs/AceGUI-3.0.off` and comment out
`libs\AceGUI-3.0\AceGUI-3.0.xml` and `libs\AceGUI-3.0-SharedMediaWidgets\widget.xml` in the TOC.
Restart the client.

**Steps:**
1. Log in and watch for a Lua error popup during load.
2. `/kcd list`
3. `/kcd get general.scale`
4. `/kcd set icons.size 40`
5. `/kcd config`
6. Restore the folders and TOC lines; restart the client and confirm `/kcd config` opens normally.

**Expected:**
- Steps 1: no Lua error popup.
- Steps 2–4: the schema CLI works fully — this is the whole point of "survivable, not a dependency".
  Step 4 prints the usual `icons.size = 40` confirmation.
- Step 5: one honest `[KCD]` line about the panel being unavailable; **no** error.

**Pass / Fail:** PASS iff the CLI is fully functional with AceGUI absent and no Lua error appears.
Any `attempt to index local 'AceGUI' (a nil value)` means a creator function was missed by the guard
sweep.

### C-06 — `GateHint` restores the gating setting even on a raise

**Change covered:** the probe's restore is now `pcall`-protected.

**Setup:** fresh or existing SavedVariables, out of combat.

**Steps:**
1. `/kcd get castbar.orientation` — note the value (expect `HORIZONTAL`).
2. `/kcd set castbar.growDirection UP` (an invalid value while orientation is horizontal).
3. `/kcd get castbar.orientation` — **note the value again**.
4. `/reload`
5. `/kcd get castbar.orientation` once more.

**Expected:**
- Step 2 prints a rejection naming the allowed values **and** a hint of the form
  `(depends on castbar.orientation = HORIZONTAL); flip castbar.orientation to VERTICAL for DOWN/UP`.
- Steps 3 and 5 print **the same value step 1 printed**.

**Pass / Fail:** PASS iff `castbar.orientation` is unchanged at steps 3 and 5. FAIL if it reads
`VERTICAL` — the probe leaked.

### C-07 — `castTick` bucket counts every exit

**Change covered:** the perf bracket is closed on the `not d` early return.

**Setup:** a hostile caster mob; `/kcd perf` available.

**Steps:**
1. `/kcd perf start`
2. Pull the caster mob and let it complete at least three casts, then kill it.
3. `/kcd perf report`

**Expected:** the report lists a `castTick` bucket with a non-zero `calls` count. The `calls` figure
should be at least one per rendered frame of cast time plus one per cast teardown.

**Pass / Fail:** PASS iff `castTick` appears with `calls > 0` and no bucket reads `0.000 / 0 calls`
(`performance-§3` — a declared bucket no bracket reaches is a lie in every report). Also confirm the
new headless case in `tests/test_perfsetup.lua` is green.

### C-08 — Castbar debug dump always prints the interruptibility line

**Change covered:** the `else` branch's unconditional line.

**Setup:** as C-04.

**Steps:**
1. In combat with a mid-cast hostile mob: `/kcd debug castbar`

**Expected:** after the `current.notInterruptible: type=… isSecret=…` line there is **always** a
following indented line — either `plain value = …`, `plain nil (treated as interruptible)`, or
`secret-tainted; visual state determined via …`.

**Pass / Fail:** PASS iff no path produces a blank gap after the `notInterruptible:` line.

### C-09 — `.pkgmeta` excludes the scratch directories

**Change covered:** `.superpowers` and `.claude` added to `ignore:`.

**Setup:** repo checkout only; no client needed.

**Steps:**
1. `grep -n "superpowers\|claude" .pkgmeta`
2. If the BigWigs packager is available locally, run a package build and list the zip contents;
   otherwise inspect the `ignore:` list by eye.

**Expected:** step 1 prints both entries. A built zip contains no `.superpowers/` and no `.claude/`.

**Pass / Fail:** PASS iff both entries are present in `ignore:`.

### C-10 — Orphaned locale keys removed

**Change covered:** ten dead keys deleted from `locales/enUS.lua`.

**Setup:** in-client, after `lua tests/run.lua` is green.

**Steps:**
1. `/kcd config` → **Text Label**. Read every visible label and description.
2. `/kcd config` → **General**. Read the "Debug console" checkbox label and its tooltip.
3. `/kcd set nosuchsetting 1`
4. `/kcd get nosuchsetting`
5. `/kcd set icons.size notanumber`

**Expected:** no on-screen or in-chat string appears as a raw un-rendered key. Steps 3–5 produce the
library's own not-found / usage / invalid-value lines, all `[KCD]`-tagged.

**Pass / Fail:** PASS iff nothing renders as a bare English key that used to be a deleted entry, and
`tests/test_locale.lua`'s bidirectional key-set assertion is green.

### C-11 — Message-bus doc corrected

**Change covered:** documentation only.

**Steps:** read `docs/message-bus.md` lines 7–12 and 55–65.

**Expected:** the emitter rule as written is satisfied by the table directly above it. No sentence
requires all emitters of `Ka0s_KickCD_CONFIG_CHANGED` to share a file.

**Pass / Fail:** PASS iff a reader can determine the policy without the doc contradicting itself.

---

## Regression suite

Not tied to any one change; these cover behavior the changes could plausibly break.

| # | Check | Expected |
|---|---|---|
| R-1 | `/reload` from a fully open settings panel | No Lua error; panel reopens on `/kcd config` |
| R-2 | Delete `WTF/.../SavedVariables/KickCD.lua`, log in fresh | Defaults populate; icon grid appears; `/kcd list` shows every page's rows |
| R-3 | Fresh login: watch `ADDON_LOADED` → `PLAYER_LOGIN` → `PLAYER_ENTERING_WORLD` | Zero Lua errors with `scriptErrors 1` |
| R-4 | Enter combat with the grid and cast bar visible; leave combat | Grid/bar visibility follows the `general.visibility` mode; no error at either transition |
| R-5 | `/kcd config` → **Profiles** → create a new profile, switch to it, switch back | Panel re-reads values on each switch; no error; no profile data lost |
| R-6 | `/kcd config`, toggle **every** checkbox on General, Icons, Cast bar and Text Label once, then toggle each back | Each toggle repaints its widget in place with no visible page rebuild hitch; no error |
| R-7 | Drag every slider on Icons end to end | No error; no chat spam; the grid updates live |
| R-8 | `/kcd config` → **Spells**, add a spell by ID, reorder it, change its category, remove it | Editor refreshes; `/kcd spells list` agrees |
| R-9 | `/kcd resetall`, confirm the popup | Every page returns to defaults; the grid returns to its default position; Profiles are untouched |
| R-10 | `/kcd lock`, `/kcd unlock`, `/kcd toggle`, `/kcd resetposition` | Each prints its confirmation; drag behavior matches the lock state |
| R-11 | `/kcd` with no argument, then `/kcd help`, then `/kcd nosuchverb` | Identical help index all three times, each row `[KCD]`-tagged cyan |
| R-12 | `/kcd version` and the version stamped in a `/kcd perf report` record | Identical strings |
| R-13 | Enter combat, then `/kcd config` | Gray refusal line, panel does **not** open, no taint error |

---

## Taint-specific tests

The review raised no new taint findings, but C-05 and C-01 touch the panel build path, so the existing
guarantees must be re-confirmed.

| # | Steps | Expected |
|---|---|---|
| T-1 | Enter combat with a target dummy. Type `/kcd config`. | One gray `[KCD]` notice: *cannot open settings during combat*. Panel stays closed. No red *"Interface action failed because of an AddOn"*. |
| T-2 | Leave combat. `/kcd config`. Then close, and open the same page via **Esc → Options → AddOns → Ka0s KickCD**. | Both routes open the same canvas; the left tree is expanded showing every subcategory; no error either way. |
| T-3 | With the panel open out of combat, enter combat, click through three subcategories, leave combat. | No error; widgets remain interactive. |
| T-4 | In combat, click an action bar slot repeatedly for 10 seconds while the grid and cast bar are visible. | No *"Interface action failed because of an AddOn"* red text. |

---

## Localization sanity

C-10 touches `locales/enUS.lua`, and there is currently no second locale file, so a non-enUS client
exercises the **metatable fallback** rather than a translation.

1. Set the client language to **deDE** (Battle.net app → WoW → Options → Game Language) and restart.
2. Re-run **C-10 steps 1–5** and **R-6**.
3. Expected: every KickCD string renders in English (the fallback returns the key). Nothing renders as
   a `SCREAMING_SNAKE_CASE` token — `STEP_START`, `PANEL_TITLE_SUFFIX`, `LIST_HEADER` on screen means a
   descriptor was handed `NS.L` and the library's own strings became unreachable
   (see `docs/smoke-tests.md:636`; this addon has shipped that bug before).
4. Also run `/kcd perf` and open the guided step panel — its labels come from
   `LibKa0s-Perf-1.0`'s own `STRINGS`, which is exactly the surface that regression hits.
5. Restore the client language.

---

## Performance spot-checks

Only C-01 and C-07 are perf-relevant.

1. **Allocation, panel render.** Before opening the panel: `/run collectgarbage("collect"); print(collectgarbage("count"))`.
   Open `/kcd config`, click through all six subcategories, close. Repeat the measurement.
   Record before/after in the sign-off table. C-01 should be neutral or slightly better (one fewer
   duplicate closure set); a growth of more than ~50 KB over the pre-change baseline needs
   investigation.
2. **Per-frame cost, cast bar.** `/console scriptProfile 1` → `/reload` → pull a caster mob, let it
   cast → `/run UpdateAddOnCPUUsage(); print(GetAddOnCPUUsage("KickCD"))`. Compare against the same
   measurement taken before the changes. C-07 adds one conditional on a teardown path only; the
   per-frame figure must not move.
3. **Bucket sanity.** `/kcd perf start` → 30 seconds of combat → `/kcd perf report`. Confirm all eight
   declared buckets (`spellPoll`, `pollSpell`, `spellState`, `iconApply`, `cdText`, `castEvent`,
   `visibility`, `castTick`) report non-zero `calls`.

---

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | |
| C-02 | | | |
| C-03 | | | |
| C-04 | | | |
| C-05 | | | |
| C-06 | | | |
| C-07 | | | |
| C-08 | | | |
| C-09 | | | |
| C-10 | | | |
| C-11 | | | |
| Regression R-1…R-13 | | | |
| Taint T-1…T-4 | | | |
| Localization | | | |
| Perf spot-checks | | | before / after: |
