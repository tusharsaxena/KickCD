# 03 — In-client smoke tests (KickCD, 2026-10-07 review)

The owner runs these in the live client after the changes in `02_PROPOSED_CHANGES.md` land. **Never
mark a check passed on the owner's behalf.** Headless suites are not repeated here. They ran in Step 0b
and get re-run once as pre-flight.

## Pre-flight

1. From the repo root, run `~/.claude/dev-copilot/bin/ka0s-bounded lua5.1 tests/run.lua` and
   `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`. Expect all pass (one kit skip), 0/0 lint, and a
   pass count equal to the README badge.
2. The client is Retail 12.1.x (`## Interface: 120100`), and the game loads `GIT/KickCD` through its
   symlink. Do not test from a side worktree.
3. Run `/console scriptErrors 1`, then `/reload`. Have a training dummy, or any hostile caster, in reach,
   and also a friendly caster (a party member, or a friendly NPC that casts).
4. Leave `/kcd debug on` running so the console carries the trace while testing.

## Per-change tests

### C-01: the cast bar re-anchors when the icon grid empties

- **Setup:** default profile (`/kcd resetall` on a test profile). Cast bar *Anchor mode* = Primary icon
  (the default). Lock off (`/kcd unlock`), so the preview bar shows.
- **Steps:**
  1. Note where the cast bar preview sits: above the first (largest) icon.
  2. Open Settings → KickCD → Spells and untick **every** spell for your current spec. Alternatively,
     run `/kcd spells disable <id>` for each id that `/kcd spells list` prints.
  3. Look at the preview bar.
  4. Target a hostile caster, `/kcd lock`, and let it cast.
  5. Re-enable one spell.
- **Expected:** in step 3 the bar is still visible, now anchored to the empty 48×48 grid frame at the
  grid's position. In step 4 the live bar shows. In step 5 the bar snaps back onto the primary icon. No
  Lua error appears.
- **Pass:** the bar is visible and near the grid in steps 3–5, and no error popup appears.

### C-02: name truncation counts characters

- **Setup:** set the client locale to **frFR** or **deDE** (Battle.net → Game Settings → Text
  Language), then restart. In Grid → Cast bar → Spell name, set **Truncate after (characters)** to `4`.
- **Steps:**
  1. Out of combat, target a hostile NPC casting a spell whose localized name has an accented letter in
     its first four characters. A friendly caster also works, since the name is not secret out of combat.
  2. Read the bar's name text.
- **Expected:** exactly four visible characters followed by "…", with no garbage glyph or empty box
  before the ellipsis.
- **Pass:** the visible count equals 4 and every glyph renders. Afterwards, switch the locale back to
  enUS and confirm an English name is cut at 4 as well.

### C-03 / C-04: debug verbs

- **Setup:** the debug console closed.
- **Steps:**
  1. Type `/kcd debug spels`, a deliberate typo.
  2. Type `/kcd debug` (bare).
  3. Type `/kcd debug castbar focus` with a focus target set, then `/kcd debug interrupt focus`.
  4. Type `/kcd debug castbar` with no unit.
- **Expected:** step 1 prints `unknown debug subcommand 'spels'` and then the sub-verb list, and the
  console **stays closed**. Step 2 toggles the console open and prints the list. Step 3 prints
  `castbar state (focus)` and an interrupt dump for `focus`. Step 4 dumps `target`.
- **Pass:** the console visibility changes only in step 2, and step 3 names `focus`.

### C-05: the glow refreshes on a cast by a target you cannot attack

- **Setup:** in Grid → Icons, set the primary glow trigger to **When target is casting**. The primary
  spell must be ready (off cooldown).
- **Steps:**
  1. Target a friendly player or NPC and wait for them to start a cast.
  2. Watch the primary icon at cast start and at cast end.
  3. Repeat on a hostile caster.
- **Expected:** the glow starts at cast start and stops at cast end, for the friendly caster and the
  hostile one alike.
- **Pass:** the glow tracks the cast edges on both targets without needing a cooldown to tick.

### C-06: Cooldowns no longer rebuilds on `general`

- **Setup:** `/kcd debug on`, with a few spells on cooldown.
- **Steps:**
  1. Drag the Scale slider on General → Master controls back and forth.
  2. Unlock, drag the icon grid, and release.
  3. Run `/kcd disable` and then `/kcd enable`.
- **Expected:** steps 1 and 2 produce no `[Cooldowns] rebuild …` console lines, and the icons keep
  their cooldown swipes. Step 3 produces exactly one rebuild line on enable, and the icons come back
  with the correct cooldown state.
- **Pass:** no rebuild lines in steps 1–2, and correct state after step 3.

### C-08: lint whitelist

Headless only (`luacheck .` 0/0). There is nothing to do in the client.

### C-09: throttle allocation

Headless measurement only (`tests/perf.lua`, new scenario). There is nothing to do in the client
unless the follow-up change ships. If it does, run a `/kcd perf` two-arm capture per `performance-§7`
and record it with `/dev-copilot:wow-perf-analysis`.

## Cross-addon (in-client half of the Step 0b pass)

With several Ka0s addons loaded, type `/kcd` and `/kickcd` and confirm each opens **KickCD's** settings.
Open Settings → AddOns and confirm Ka0s KickCD appears **once**, with General, Grid, Spells and
Profiles each listed once.

## Regression suite

1. Run `/reload` and confirm no Lua errors. The `[KCD]` login line appears if it is enabled.
2. With a fresh SavedVariables (rename `WTF/.../SavedVariables/KickCD.lua`), log in and confirm the
   default lists seed for your class and spec, and the grid and bar appear in their default places.
3. Enter and leave combat on a dummy, under each visibility mode (Always / In combat / When target is
   casting / interruptible), for target **and** focus.
4. Switch profile on the Profiles page and with `/kcd profile <name>`, and confirm both units re-lay out.
5. Open every settings page and tab, and toggle at least one row on each.
6. Run `/kcd disable` and confirm everything hides and `/kcd diagnostics` still writes the report. Run
   `/kcd enable` and confirm everything returns.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | |
| C-02 | | | |
| C-03 | | | |
| C-04 | | | |
| C-05 | | | |
| C-06 | | | |
| C-08 | n/a (headless) | | |
| C-09 | n/a unless the follow-up ships | | |
| Cross-addon | | | |
| Regression | | | |
