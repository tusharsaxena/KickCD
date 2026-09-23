# 03 — In-client smoke tests

Everything headless (luacheck, the 1050-case suite, `tests/perf.lua`, lizard, vendor sync and the cross-addon greps) ran in Step 0 and is recorded in `01_FINDINGS.md`. This file covers only what needs a logged-in client.

## Pre-flight

1. **Headless re-check after the changes land (one line):**
   ```
   ~/.claude/wow-addon/bin/ka0s-bounded lua5.1 tests/run.lua && ~/.claude/wow-addon/bin/ka0s-bounded luacheck .
   ```
   Both must be green, and the pass count must equal `docs/test-cases.md` and the README badge.
2. **Install.** Copy the repo folder to `World of Warcraft\_retail_\Interface\AddOns\KickCD`. The TOC `## Interface: 120100` must match the client build. If the U-001 re-vendor landed, confirm `libs/LibKa0s` came over whole.
3. **Characters.** Use one interrupt-capable melee character (e.g. a Death Knight or Rogue, where Mind Freeze or Kick is on the default list). Also have a second character, or the ability to create a second profile.
4. **Error visibility.** Run `/console scriptErrors 1`, `/reload`, and keep BugSack or the default error frame visible.
5. **Other AceGUI addons (for C-02).** Load at least one other Ka0s addon with a settings panel, such as AbsorbTracker or PanelMaster.
6. **Debug console (optional).** `/kcd debug on`, then `/kcd debug window`.

---

## C-01 — per-profile color and font-flag migration (F-001)

- **Setup:** a SavedVariables file from **1.2.1** with **two** profiles. Put a custom cast-bar text color and `fontFlags = "NONE"` on profile **B**. Keep profile **A** active. Close the client, install the fixed build, and log in on A.
- **Steps:**
  1. Settings → KickCD → Profiles, switch to **B**.
  2. Open Cast bar and look at the Text color swatch and the Font outline dropdown.
  3. `/kcd get units.target.castbar.textColor`.
  4. `/reload`, then repeat step 3.
- **Expected:** the swatch shows B's custom color, not the default. The outline dropdown shows **None**, not blank. The `get` output prints the custom r/g/b. No Lua error.
- **Pass / fail:** pass only if B's color and flag are right both before and after `/reload`.

## C-02 — no leaked tooltips or mouse capture on pooled widgets (F-002)

- **Setup:** fixed build plus one other Ka0s addon loaded.
- **Steps:**
  1. `/kcd config` → Spells. Toggle two rows' enable checkboxes and change one category, which causes several renders.
  2. Close Settings. Open the other addon's settings pages, then KickCD's General and Icons pages.
  3. Hover plain text labels and dropdowns on those pages. Click controls that sit under or next to labels.
- **Expected:** no KickCD spell tooltip and no "Category for future filtering…" tooltip anywhere but the Spells page. Labels do not eat clicks. On the Spells page itself, hovering a spell name shows its spell tooltip and hovering a category dropdown shows the category tooltip.
- **Pass / fail:** pass if the tooltip appears only on its own widget, and no label outside the Spells page is mouse-interactive.

## C-03 — frame reuse and EMPOWER events (F-003, F-006)

- **Setup:** fixed build; target a training dummy.
- **Steps:**
  1. `/run print(collectgarbage("count"))`. Note the number, but it is informational only.
  2. Run `/kcd disable` then `/kcd enable` **ten times**.
  3. `/fstack` is not useful here. Instead, `/run local n=0; local f=EnumerateFrames(); while f do n=n+1; f=EnumerateFrames(f) end; print(n)` before step 2 and after it.
  4. **EMPOWER (PvP or a duel with an Evoker friend):** target the Evoker and have them cast Fire Breath (empowered), both from targeted and already-targeted states.
- **Expected:** the frame count from step 3 grows by **0** across the ten cycles (today: +36 per cycle). The cast bar appears for the empowered cast and hides when it ends. In `target_casting` visibility mode the icon grid shows during the empower.
- **Pass / fail:** pass if the frame delta is 0 **and** the empowered cast shows and clears. If EMPOWER cannot be tested, record it as untested; do not mark it passed.

## C-04 — color-drag throttle (F-004, U-001)

- **Setup:** fixed build, `/kcd debug on`, `/kcd debug window` open.
- **Steps:** Cast bar → drag the Text color picker around continuously for about 3 s.
- **Expected:** no stutter. The debug console shows **one** `[Set] … textColor = …` line after release; it is debounced. The color updates live on the preview bar while unlocked (`/kcd unlock`).
- **Pass / fail:** pass if the drag is smooth and only one `[Set]` line appears. Frame time can be eyeballed with `/run print(GetFramerate())` during the drag against idle. Treat that as orientation, not evidence.

## C-05 — spell input parity (F-005, F-018)

- **Steps (on a Shaman, or substitute a multi-word interrupt for your class):**
  1. `/kcd spells add Wind Shear`
  2. `/kcd spells add 1766 WARLORD`
  3. `/kcd spells add <an ID the Cooldown Manager does not track for your current spec>`
  4. `/kcd spells`
- **Expected:**
  1. `added Wind Shear (#57994) to SHAMAN/<SPEC>`, or `already in …, re-enabled`.
  2. A refusal naming the unknown class. `/kcd spells list WARLORD` afterwards must not show a list.
  3. The same refusal text the Spells page's Add box shows.
  4. The default spec line shows the spec token (e.g. `ENHANCEMENT`), not a number.
- **Pass / fail:** all four as expected.

## C-06 — state replay after rebuild (F-007)

- **Steps:**
  1. Out of combat, cast your interrupt on a dummy so it is on cooldown.
  2. Immediately open the talent UI and swap a talent that fires `TRAIT_CONFIG_UPDATED`, or summon/dismiss a pet as a Hunter or Warlock.
  3. Watch the interrupt icon.
  4. Repeat with `/reload` while it is on cooldown.
- **Expected:** the icon stays in its on-cooldown look (dim or tinted, with the swipe) the whole time and never flashes "ready".
- **Pass / fail:** repeat five times; pass if there is no ready flash.

## C-07 — Spells page single render and stuck guard (F-008)

- **Steps:** Spells page. Toggle an enable checkbox, then drag a row to a new position.
- **Expected:** the rows re-render once. No visible double flicker, and the drag lands where dropped.
- **Pass / fail:** pass if there is no flicker and no Lua error. The stuck-guard half is headless-only.

## C-08 — perf nesting reads correctly (F-009)

- **Protocol (performance, two-arm):**
  1. Log in fresh and do not `/reload` between arms.
  2. `/kcd perf` → follow the printed workflow. The **clean arm first**, then the **suspended** arm. Open each window on the player's **combat state**, fighting the same dummy with the same rotation for about 60 s each, with the debug console **off** in both.
  3. Copy the dump and record it as a frozen `docs/perf-analysis/<YYYYMMDD-HHMMSS>/` bundle via `/wow-addon:perf-analysis`.
- **Expected:** the report shows `stateEmit` with `spellState` under it and `iconApply` under that. `glowGate` appears. Read the **bucket figures**. Do not read the frame-time delta, which is unresolved below the harness's run-to-run spread.
- **Pass / fail:** pass if the nesting matches `core/PerfSetup.lua` and the bundle is committed with its `ANALYSIS.md`.

## C-09 / C-10 — hygiene (F-010 to F-017)

1. `/kcd resetposition`: with both grids moved, it restores whichever set the help text now names.
2. `/kcd config` in combat: prints the refusal line. The README wording now matches.
3. **Disabled at login:** `/kcd disable`, `/reload`, `/kcd enable`, then `/etrace` briefly while out of combat. KickCD must not be listening for `PLAYER_LOGIN` (inspect with `/dump` on `C_EventUtils` if available; otherwise mark it untested).
4. Spells page (after the C-09 split): every control still works. Add, remove, enable, category, drag and Defaults all behave as before.

---

## Regression suite

- `/reload` 3× with no errors.
- A **fresh character** (no SavedVariables): defaults populate, the grid appears for spells you know, and the cast bar appears under the grid on a casting target.
- Login order: no error across ADDON_LOADED → PLAYER_LOGIN → PLAYER_ENTERING_WORLD. Zone through a loading screen once.
- **Combat:** enter combat on a dummy and leave it, in each visibility mode (`/kcd set visibility always|in_combat|target_casting|target_casting_interruptible`).
- **Profiles:** switch and copy between two profiles, then Reset Profile. The grid re-reads each time.
- **Settings panel:** open every page and toggle at least one control per tab. Defaults on one page, then *Reset all settings*. The minimap button survives the reset.
- **Disable path:** `/kcd disable` puts nothing on screen. The minimap left-click prints one refusal line and right-click opens settings. `/kcd enable` brings everything back.
- **Taint:** in combat, click an action button next to where KickCD draws, cast your interrupt, and change target 10×. There must be no `Interface action failed because of an AddOn`. Also open Settings from the Esc menu → Options → AddOns → KickCD while **out** of combat, then try the same **in** combat: expect the locked or refused page and no broken settings window (anti-pattern #88).
- **Cross-addon (not optional):** with several Ka0s addons loaded, type each root (`/at`, `/am`, `/bl`, `/cm`, `/kcd`, `/lh`, `/mm`, `/pm`, `/pc`, `/wg`) and confirm each reaches its own addon. Then open Settings → AddOns and confirm each addon appears exactly once, and each multi-page addon's pages appear once each.

## Localization sanity

F-005 changes user-facing refusal strings, so switch the client to **deDE** or **frFR** once and re-run C-05 steps 1–3. Messages must render without `%s` artifacts. The spell name resolves in the client language, and the output still echoes the English class/spec token.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | |
| C-02 | | | |
| C-03 | | | EMPOWER half: |
| C-04 | | | |
| C-05 | | | |
| C-06 | | | |
| C-07 | | | |
| C-08 | | | bundle stamp: |
| C-09 | | | |
| C-10 | | | |
| U-001 (re-vendor) | | | LibKa0s tag: |
| Regression | | | |
| Cross-addon | | | |
