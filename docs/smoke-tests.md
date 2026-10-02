# Smoke tests — Ka0s KickCD

These are the in-client checks the headless suite cannot make: real frames drawing, real casts and
cooldowns, 12.0 secret values in combat, real taint, real SavedVariables files. Run them before a
release, after a LibKa0s re-vendor or an `## Interface` bump, and before claiming a non-trivial change
works. Start from a clean `/reload` (`/console reloadui`) and turn logging on (`/kcd debug on`) only
where a check says so. Each check says what to do and what must happen; anything that does not match
is a bug, not a tolerance. Record the outcome on the check's `Result:` line (pass, or what you saw
instead). IDs are `<THEME>-<n>` and stay stable: a new check takes the next free number in its theme,
and a retired one leaves its number unused.

## Index

| ID range | Theme | What it covers |
|---|---|---|
| INSTALL-1 – 14 | Install, load and the launcher | First login, the store on disk, `/reload`, the schema validator, the two shape migrations, the minimap button and broker plugin |
| SLASH-1 – 14 | Slash commands | Bare `/kcd`, help, `list` / `get` / `set` / `reset` / `resetall`, value gates and clamps, verbs while disabled, the `debug` and `spells` sub-help rows |
| PANEL-1 – 30 | Settings panel | The tree, the Grid page's band, rail and tabs, panel and slash sync, Defaults and Reset all, media dropdowns, the minimap checkbox, raw locale keys, the descriptor's folder name |
| PROFILE-1 – 14 | Profiles | The Profiles page, switches, copies and resets, their debug lines, the `/kcd profile` verb |
| STATE-1 – 15 | Enable, lock and visibility | The master switch and stand-down, lock and drag, `resetposition`, the four visibility modes |
| COMBAT-1 – 11 | Combat | Settings refusals and the combat cover, debug dumps and diagnostics in combat, the protected-interrupt taint pass |
| GRID-1 – 16 | Icon grid | Layout, cooldown swipe and text, GCD suppression, ready glow, render gating, the charges badge, the ticker owning time |
| CAST-1 – 14 | Cast bar | A cast on the bar, auto-size, per-state colors, anchor modes, the drag strip, two bars at once, empowered casts |
| FOCUS-1 – 19 | Focus tracking | The second instance, independent gating, link, unlink, copy styling, per-unit alpha and tint |
| LABEL-1 – 15 | Text label | Every label control, visibility follow, the drag strip clearing the label, rapid changes |
| SPELLS-1 – 16 | Spell lists | Spec, talent and pet rebuilds, the Spells page and `/kcd spells`, resets, racials |
| DIAG-1 – 45 | Debug and diagnostics | `/kcd debug` subcommands, the traces, the console and its chrome, the perf panel, `/kcd diagnostics`, resizing the console, copy window and perf panel, the console's Diagnostics link, diagnostics turning logging on, the library's own Slash and Lifecycle lines, state lines at enable, Clear re-arming the gates, the interrupt dump's secret sentinel |
| DEGRADED-1 – 15 | Library-absent install | `libs/LibKa0s` renamed aside: fallbacks, refusals, the shared cause clause, restore, plain sub-help rows, the interrupt dump's sentinel |
| LOC-1 – 6 | Non-English client | Spec seeding and resolution on a non-English client, the spec-key upgrade |

## Before you start

- Error display on: BugSack / BugGrabber, or `/console scriptErrors 1`. A clean run means no Lua error
  at any point, and every check assumes it.
- **Chat banner.** Every line the addon prints starts with a cyan `[KCD]`. A doubled `[KCD][KCD]`, or
  a line with no banner, fails whichever check printed it.
- **A hostile caster** is a dummy or world mob that casts or channels an interruptible spell on demand
  (Stockades casters, Plaguefall trash). **In combat** means `PLAYER_REGEN_DISABLED` has fired;
  auto-attacking a dummy is enough.
- Characters: one with two specs and a talent choice node that swaps an interrupt-adjacent spell, a
  Hunter (SPELLS-4), a Tauren, Highmountain Tauren, Pandaren, Kul Tiran or Nightborne (SPELLS-16), and
  a class with an off-GCD interrupt plus an on-GCD crowd control (Warrior Pummel
  and Intimidating Shout) for GRID.
- An Evoker to duel for CAST-14 (a duel partner counts as hostile).
- Other addons: a second Ka0s addon with a debug console (DIAG-20, DIAG-36), AbsorbTracker and
  ConsumableMaster (DEGRADED-7), PanelMaster, AbsorbTracker, ConsumableMaster and MultiMeters
  (PANEL-23), a media addon such as SharedMedia (PANEL-19 – 22), and Titan Panel, Bazooka or ElvUI's
  data texts (INSTALL-14, PANEL-26).
- Back up `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` before INSTALL-1, INSTALL-7, INSTALL-9
  and LOC-6: each deletes or edits it.
- A frFR (or other non-English) client for LOC.
- For DEGRADED, first `/kcd set units.target.castbar.anchorMode FREE` (DEGRADED-12 needs it, and nothing
  can change it once the library is gone), then rename `Interface/AddOns/KickCD/libs/LibKa0s` to
  `libs/LibKa0s_off` and `/reload`; DEGRADED-13 renames it back. A folder left renamed ships a silently degraded addon.

Which checks to run for a partial change:

- **Border dropdown, or `settings/OptionsSetup.lua`'s live wiring:** PANEL-19, PANEL-23 and PANEL-30. PANEL-23 is
  the only check that loads five addons into one AceGUI registry; PANEL-19 alone cannot see its defect.
- **LibKa0s re-vendor, or a seam file** (`core/CoreSetup.lua`, `core/DebugLogSetup.lua`,
  `core/PerfSetup.lua`, `core/MediaSetup.lua`, `settings/OptionsSetup.lua`, `settings/Slash.lua`):
  DEGRADED; PANEL-3, PANEL-8 – 16 and PANEL-19 – 28; SLASH-3 – 6; DIAG-1 – 6 and DIAG-16 – 40;
  COMBAT-6 – 9 and COMBAT-11; CAST-6 – 12; LABEL-2, LABEL-6 and LABEL-13 – 14; GRID-13 – 14;
  SPELLS-13; STATE-7; INSTALL-10 – 14. The panel, the console, the strips and the window edge are what
  the library draws, and a re-vendor can change them with no addon file touched.
- **Hot paths** (`Cooldowns.lua`, `IconGrid*.lua`, `Castbar*.lua`, the secret-value gates):
  INSTALL-1 – 5, SLASH-1 – 2, PANEL-1, GRID, CAST-5, COMBAT-8 – 10, STATE-11 – 15. The cast bar's
  `OnUpdate` install (`EnsureFrame`, `Start`, `Stop`) also needs CAST-13, the only check that drives two
  units at once.
- **Settings or schema:** PANEL, SLASH-3 – 11, INSTALL-6, LABEL-2, LABEL-6, GRID-13, SPELLS-13 and
  STATE-10. A new schema row also needs the reset paths (PANEL-17 – 18, PANEL-29, SLASH-7 – 11, SPELLS-11 – 12
  and DIAG-8).
- **Spell lists or `core/Database.lua`:** SPELLS, PROFILE-1 – 6; a shape change (`DEFAULT_PROFILE`, a
  migration) also INSTALL-7 – 8, and INSTALL-9 if it touches `units.<unit>.label`.
- **Target and focus:** FOCUS, STATE-4, PANEL-11, PANEL-13 and COMBAT-5, plus GRID-1 – 3, CAST-1 – 5,
  CAST-8 and SLASH-4 on each unit if the change touches layout or cast-bar internals both instances
  share. Anything touching per-unit derived state (the icon curves, the cast bar's structure
  signature) needs FOCUS-16 – 19, the only checks that catch one unit inheriting the other's resolved
  appearance.
- **Text label:** LABEL and FOCUS-6, and INSTALL-9 if `label.style`'s shape or defaults moved.
- **The printer (`NS.Util.print` or `core/CoreSetup.lua`):** DEGRADED-6 and DEGRADED-11, then
  DIAG-1 – 6, DIAG-28 and COMBAT-7 – 9. DEGRADED-11 is the only check that runs a call site on the
  library-less load.
- **Debug console** (the window, its subcommands, the scrollbar and line counter, the title-bar art):
  DIAG-1 – 6, DIAG-16 – 25, DIAG-28, DIAG-34 – 37, DIAG-39, COMBAT-7 – 9 and PANEL-25.
- **Diagnostics** (`modules/Diagnostics.lua`, the descriptor's `diagnostics` or `brandName`, a seam a
  section reads through, or a chat dump a section reuses): DIAG-27 – 33, DIAG-39 – 40, DIAG-17, COMBAT-11, GRID-14,
  DEGRADED-9, then DIAG-1 – 6 and COMBAT-7 – 9.
- **Perf descriptor or panel** (`core/PerfSetup.lua`): DIAG-23 – 24 and DIAG-38, then DIAG-21 – 26
  and PANEL-25. DIAG-23 is the only place the panel's close is checked against what is drawn.
- **Media seam** (`core/MediaSetup.lua`, `core/Constants.lua`'s `FONT_MONO`, the `NS.MakeCloseButton`
  wrapper, the DebugLog descriptor): DIAG-21 – 25 and PANEL-25, then DIAG-16 – 20. The tests pin what
  is passed; these are the only look at what is drawn.
- **Launcher, logo or `## IconTexture`** (and a re-vendor that moves `Launcher.lua`): INSTALL-10 – 14,
  STATE-5, STATE-9, PANEL-26 – 27, PROFILE-8, SLASH-12 – 13. A wrong TGA format draws nothing and
  raises nothing, so no gate reports it.
- **The Grid page** (`settings/Grid.lua`, `settings/Panel_Render.lua`, the three entry files):
  PANEL-1 – 13, PANEL-17, PANEL-29, FOCUS-6 – 7, COMBAT-4 and SLASH-9.
- **A release or a TOC bump:** everything.

## INSTALL

- **INSTALL-1. Clean first login.** Quit WoW, delete `KickCD.lua` (and `KickCD.lua.bak`) from
  SavedVariables, confirm the character-select AddOns list shows **Ka0s KickCD** enabled, and log in →
  zero Lua errors. Result:
- **INSTALL-2. The grid seeds itself.** On that login (a fresh profile starts unlocked, so the grid
  shows) → the icon grid holds the current spec's default spells, only ones the character can cast.
  Result:
- **INSTALL-3. The store on disk.** `/reload`, then open `KickCD.lua` → `profileKeys`,
  `profiles.Default` and a seeded `spells[CLASS][specID]` block for the current spec, the spec key a
  **number** (`[262]`), never a spec name. Result:
- **INSTALL-4. An alt seeds its own spec.** Log in on a character of another class and spec → its spec's
  spells are seeded with no error. Result:
- **INSTALL-5. Settings survive `/reload`.** `/kcd unlock`, `/kcd set units.target.icons.primarySize 50`,
  `/kcd set units.target.castbar.interruptible.barColor 0.2 0.8 0.2 1`, drag the grid somewhere new,
  `/kcd lock`, `/reload` → no error; the grid is where you left it; `/kcd get locked` → `true`;
  `/kcd get units.target.icons.primarySize` → `50 px`; `/kcd get` on the bar color →
  `{0.20, 0.80, 0.20, 1.00}`. Result:
- **INSTALL-6. The schema validator is silent.** Quit fully (not `/reload`) and log in, watching chat →
  no `schema error` line. The validator (`Store.Validate`, run at panel register) prints one for a
  malformed row or a stored path the defaults cannot resolve; any line means a schema change shipped
  broken. Result:
- **INSTALL-7. The legacy unit fold.** Quit. Edit `KickCD.lua` so the active profile has top-level
  `icons`, `castbar` and `anchors` tables with a non-default `icons.primarySize`, a moved
  `anchors.icons` and a custom color, no `units` table, and `global.schemaVersion` set to `1` or
  removed. Log in → no error; the grid sits at the same place with the same look;
  `/kcd get units.target.icons.primarySize` and `/kcd get units.target.icons.cooldownTint` return your
  values, not the defaults. `/reload` and reopen the file → the top-level tables are gone,
  `units.target.{icons,castbar,anchors}` hold your values, and `global.schemaVersion` is `5` (one
  login runs every step from v1). Result:
- **INSTALL-8. The fold runs once, and Focus arrives fresh.** After INSTALL-7, `/reload` again →
  nothing moves and nothing errors. `units.focus` exists with its own defaults (`enabled = true`,
  `link = true`); the fold touched only Target. Result:
- **INSTALL-9. The label style backfill.** Quit. Edit `KickCD.lua` so `units.target.label` and
  `units.focus.label` hold only `show` and `text` (no `style`); leave `schemaVersion` alone, since this
  step is shape-driven. Log in → no error; `/kcd get units.target.label.style.font` answers and Grid →
  Text Label shows sane values; a label that was shown looks the same as before; `show` and `text` are
  as you wrote them. `/reload` and reopen the file → both units have a `style` equal to
  `LABELSTYLE_DEFAULT` in `defaults/Profile.lua`. A second `/reload` rewrites nothing. Result:
- **INSTALL-10. The minimap button draws the logo.** Look at the minimap ring → a round button wearing
  the KickCD logo, not a Blizzard ability icon and not an empty or black square (the TGA-format
  failure: `media/logos/kickcd.logo.128.tga` must be image type 2 at 32 bpp). The AddOns list shows the
  same logo beside Ka0s KickCD. Result:
- **INSTALL-11. The button's tooltip.** Hover it → `Ka0s KickCD  v<version>`, `Enabled: Yes`,
  `Locked: Yes` or `No`, `Left-click: Open settings`, `Right-click: Options menu`, and no `Test mode`
  line. Result:
- **INSTALL-12. Left-click.** Left-click the button → the settings panel opens on its landing page,
  and the lock does not change. Result:
- **INSTALL-13. The button remembers where it sits.** Drag it a quarter of the way round the ring,
  `/reload` → it comes back where you left it. Result:
- **INSTALL-14. Broker displays.** In Titan Panel, Bazooka or ElvUI's data texts add Ka0s KickCD → the
  row wears the same logo, left-click opens the panel, right-click opens the same two-entry menu, and
  the row has no value cell (it is a launcher, not a data source). Result:

## SLASH

- **SLASH-1. Bare `/kcd`.** Out of combat type `/kcd` → the settings panel opens on the Ka0s KickCD
  landing page with the tree expanded, and no help list prints. `/kcd config` does the same. Result:
- **SLASH-2. Help.** `/kcd help` → the help index; every row has the `[KCD]` banner, command names in
  yellow, descriptions in white, and no `schema error:` line. Result:
- **SLASH-3. `/kcd list`.** Type `/kcd list` → every schema row from General and the three Grid entries
  prints, each with its current value. Result:
- **SLASH-4. A gated value names its gate.** With `units.target.castbar.orientation` at `HORIZONTAL`,
  `/kcd set units.target.castbar.growDirection UP` → refused with two lines,
  `Invalid value for units.target.castbar.growDirection` and `allowed values: RIGHT, LEFT (depends on
  units.target.castbar.orientation = HORIZONTAL); flip units.target.castbar.orientation to VERTICAL
  for DOWN/UP`. Set orientation to `VERTICAL` and try `LEFT` → the same shape: `allowed values: UP,
  DOWN (depends on … = VERTICAL); flip … to HORIZONTAL for LEFT/RIGHT`. Result:
- **SLASH-5. Numbers clamp.** `/kcd set scale 99` → clamped to the row's maximum; the echo reads
  `scale = 2`. Result:
- **SLASH-6. Colors take three or four numbers.** `/kcd set units.target.castbar.interruptible.barColor
  0.5 0.5 0.5` → accepted with alpha 1, echoed `{0.50, 0.50, 0.50, 1.00}`. The same row with
  `255 128 0` → any component above 1 switches the whole color to the 0 – 255 scale, echoed
  `{1.00, 0.50, 0.00, 1.00}`; a component above 255 clamps to `1.00`. Result:
- **SLASH-7. Reset one setting.** Change `units.target.icons.primarySize`, then
  `/kcd reset units.target.icons.primarySize` → that row returns to its default; every other row and
  the spell list are untouched. Result:
- **SLASH-8. A reset color is a copy.** `/kcd reset units.target.icons.cooldownTint` on two profiles,
  then edit it on one → the other does not move. Result:
- **SLASH-9. Retired reset words answer.** `/kcd reset general`, `icons`, `castbar` and `label` → each
  says `` `/kcd reset <word>` is gone `` and points at the Defaults button that replaced it (General's,
  or the Grid entry's for the unit in the band) or `/kcd reset <path>`. `/kcd reset spells` → it has
  moved to `/kcd spells resetall`. None answers `Setting not found`. Result:
- **SLASH-10. `/kcd resetall`.** `/kcd unlock`, move both grids,
  `/kcd set units.target.castbar.anchorMode FREE` and drag the Target cast bar well away from the grid;
  change settings on several pages and edit a spell list on two specs. Then `/kcd resetall` → one line,
  `all settings + spells reset to defaults`, and no confirm prompt; every setting is back to default
  (`/kcd get enabled` → `true`, `/kcd get visibility` → `target_casting_interruptible`,
  `/kcd get units.target.castbar.anchorMode` → `PRIMARY`); every spec's spell list is re-seeded; the
  Target grid is back at y = 120 and Focus at y = 260; the profile list is untouched. Now
  `/kcd set units.target.castbar.anchorMode FREE` again → the bar sits at its default free anchor,
  `CENTER / CENTER, x = 0, y = +120`, not where you dragged it. Result:
- **SLASH-11. The defaults `resetall` lands on.** After SLASH-10, `/kcd get` each →
  `units.target.label.show` `true`, `units.target.label.style.offsetY` `12 px`,
  `units.target.label.style.color` `{1.00, 0.82, 0.00, 1.00}`, `units.target.label.style.attach`
  `icons`, `units.target.castbar.anchorPoint` `BOTTOM_LEFT`, `castbarPoint` `TOP_LEFT`,
  `anchorOffsetY` `-1 px`, `timePosition` `CENTER`, `timeOffsetY` `-20 px`, both states'
  `statusBarTexture` `Blizzard Raid Bar`; `units.focus.label.style.*` identical to Target's. Result:
- **SLASH-12. Live verbs answer while disabled.** `/kcd disable`, then: bare `/kcd` → the settings
  panel, not a refusal; `/kcd help`, `/kcd version`, `/kcd list`, `/kcd get locked`,
  `/kcd set locked true`, `/kcd spells list`, `/kcd config` and `/kcd debug` → each answers normally;
  `/kcd enable` → back on. A refusal on any of these is the failure (`slash-commands-§2`). Result:
- **SLASH-13. Feature verbs refuse while disabled.** Still disabled, `/kcd toggle`, `/kcd lock`,
  `/kcd unlock` and `/kcd resetposition` → each prints one tagged line,
  `Ka0s KickCD is disabled — enable it with /kcd enable`, and nothing else; `/kcd get locked` is
  unchanged. `/kcd enable`. Result:
- **SLASH-14. Sub-command help through the shared formatter.** `/kcd debug` → the console toggles and
  chat prints `debug subcommands`, then one row per verb (`diagnostics`, `spells`, `castbar`,
  `interrupt`, `window`, `on`, `off`, `toggle`, `events`), each with the `[KCD]` banner and a two-space
  indent: `/kcd debug <verb>` in yellow, an em dash, the description in white, the same look as a
  `/kcd help` row. `/kcd debug` again to close the console. `/kcd spells` → `spells subcommands` and its
  rows the same way, then the `(default class/spec when omitted: …)` line. `/kcd debug EVENTS` → the
  events answer (the verb is case-insensitive); `/kcd debug nosuch` → `unknown debug subcommand
  'nosuch'`, then the list again. Result:

## PANEL

- **PANEL-1. The Settings tree.** Settings → AddOns → Ka0s KickCD → exactly **General · Grid ·
  Spells · Profiles**, each once, and no Icons, Cast bar or Text Label entries. Same after `/reload`.
  Result:
- **PANEL-2. The landing page.** Click Ka0s KickCD itself → the logo and the slash command list.
  Result:
- **PANEL-3. The Grid page's shape.** Open Grid → the Unit picker is a band across the top, full
  width; the rail is on the left with Icons · Cast bar · Text Label; the page opens on Icons; the
  rail's top edge is level with the top of the tab art. Click every tab on Icons → the Unit picker
  stays in the band, naming the same unit, on each one. Result:
- **PANEL-4. Only the controls scroll.** Rail → Cast bar, scroll to the bottom of Interruptible → the
  band, the rail and the tab strip stay put. Result:
- **PANEL-5. Tabs from the first frame.** `/reload`, open Grid as the session's first page → the tabs
  sit in one row right of the rail from the first frame, none under the rail. Result:
- **PANEL-6. Rail tooltips.** Hover each rail entry → a tooltip saying what the entry holds. Result:
- **PANEL-7. Each entry remembers its tab.** Cast bar → Font, then Icons, then Cast bar → opens on Font.
  Text Label → Placement, Icons, Text Label → opens on Placement. Result:
- **PANEL-8. The tab strips.** General → `Master controls | Units`; Grid → Icons → `Sizing | Layout |
  Visual states | Border | Annotations | Ready glow`; Grid → Cast bar → `General | Size and position |
  Icon | Font | Spell name | Cast time | Interruptible | Non-interruptible`; Grid → Text Label →
  `General | Placement | Font`; Spells → one tab, `Spell list`, with the spec picker and Add spell
  above it; Profiles → no strip. No tab name appears twice on a page. The table in
  [settings-panel.md](settings-panel.md) is the reference. Result:
- **PANEL-9. Headings.** Icons → Annotations shows `Icon`, `Font`, `Charges`; Cast bar → Size and
  position shows `Size`, `Position`; Interruptible and Non-interruptible each show `Bar`,
  `Background`, `Text`, `Border`. No page draws a heading that repeats its tab's name. Result:
- **PANEL-10. Class color beside every swatch.** Every color swatch has a `Use class color` checkbox
  right of it on the same line. Tick one → the surface takes a class color and the swatch stays
  enabled (its opacity still applies). Against an NPC boss the cast bar and label keep the stored color,
  as the swatch's tooltip says. Icons' swatches take the player's class on both units. Result:
- **PANEL-11. One unit selection across the Grid entries.** Pick Focus on Icons, click Cast bar and
  Text Label on the rail → both open on Focus. Flip one to Target, return to Icons → Target. `/reload`
  → Grid opens on Target (the selection is session-only). Result:
- **PANEL-12. The band retargets every tab.** Untick General → Units → "Use same styling as Target".
  On Grid → Cast bar → Font pick Focus → the page stays on Font and shows Focus's values. Click to
  Interruptible → Focus's colors (`/kcd get units.focus.castbar.interruptible.barColor` agrees), not
  Target's. Result:
- **PANEL-13. The Unit picker survives rebuilds.** On Icons switch the band Target → Focus → Target a
  few times and click every tab; tick and untick General → Units → "Use same styling as Target" and
  press "Copy styling from Target"; then, panel open, run any `/kcd set …`. Repeat on Cast bar and
  Text Label → the picker lists exactly `Target` / `Focus` throughout, and every other widget shows its
  own value. Anchor points or text positions in the picker are the stale-refresher bug. FOCUS-17 makes
  the same check after a write mid-cooldown. Result:
- **PANEL-14. The Enable box and the slash agree.** With General open, `/kcd set enabled false` → the
  "Enable KickCD" box unticks at once. Tick it → `/kcd get enabled` → `true`. Result:
- **PANEL-15. A slash write repaints the panel.** General open on Master controls, `/kcd set scale 1.25`
  → the Master scale slider moves to 1.25 and the grid rescales, no reopen. Result:
- **PANEL-16. Color picker drag.** Drag a color slider in a swatch's picker quickly → no stutter and no
  error (commits are throttled to 50 ms). Result:
- **PANEL-17. A Grid entry's Defaults.** Unlink Focus. With Target in the band, change a Cast bar and an
  Icons setting for Target and a Cast bar setting for Focus; open Cast bar and click Defaults → only
  Target's Cast bar settings reset; Target's Icons setting and Focus's Cast bar setting keep your
  values; the open page repaints; the spell list is untouched. The Defaults tooltip says it restores the
  selected unit's settings in the section on screen. Result:
- **PANEL-18. Reset all settings.** Hover General → Reset all settings → the tooltip reads *"Reset the
  current profile to its defaults — the same thing Profiles -> Reset Profile does. Your other profiles
  are not affected."* The arrow is an ASCII `->`, as the vendored string writes it. Click → a confirm
  popup; Yes → the same result as SLASH-10. Result:
- **PANEL-19. Media dropdowns list real media.** With a media addon loaded, open Icons → Border texture
  and Cooldown text font; Text Label → Font; Cast bar → Font, and Bar texture and Border texture for
  both states (eight composed dropdowns) → each lists several entries, never a lone `Default` or an
  empty list. Pick a Cast bar texture, border and font → the bar takes each live. Change Cooldown text
  font → the grid's countdown changes at once. Result:
- **PANEL-20. The composed module is the vendored one.** `/dump
  LibStub("LibKa0s-Options-1.0").MODULES.OptionsCompose` → the `COMPOSE_MINOR` in the vendored
  `libs/LibKa0s/OptionsCompose.lua`. Anything else means a foreign LibKa0s won the LibStub resolve or
  CLAUDE.md's provenance line is wrong. Result:
- **PANEL-21. A chosen face sticks.** Grid → Text Label → Font → a non-default face → the label redraws
  in it, and still does after `/reload`. Result:
- **PANEL-22. Media registered later shows up.** Enable a media addon that was off, `/reload`, reopen
  Cast bar → Bar texture → its textures are listed. An unchanged list means `Helpers.LSMValues`
  (`settings/Panel.lua`) went back to returning a table frozen at file load. Result:
- **PANEL-23. The Border dropdown, alone and with five addons.** Open Cast bar → Border style → no
  42×42 black preview tile left of the bar. Then enable KickCD, PanelMaster, AbsorbTracker,
  ConsumableMaster and MultiMeters, log in, and open each one's Border dropdown → in all five the closed
  control's left edge is flush with the controls stacked with it (no ~42px gap), and the open list still
  previews each row. Change which addon loads last (toggle addons or rename a folder), `/reload`, walk
  all five again → nothing differs. A dropdown unlike the other four, or one that changes with load
  order, is the failure. Result:
- **PANEL-24. The pooled tab strip.** On General, Grid → Icons and Grid → Cast bar, cycle every tab three
  times, ending on the first → each pass shows each tab's own label, the tab you pressed selected, the
  body under the right tab, and a band that never changes height. Result:
- **PANEL-25. JetBrains Mono is offered.** Grid → Text Label → Font → JetBrains Mono is listed with the
  other fonts. Result:
- **PANEL-26. The Minimap button checkbox.** Untick General → Master controls → Minimap button → the
  button goes at once; `/kcd get global.minimap.shown` → `false`; `/kcd get global.minimap.hide` →
  `Setting not found` (the stored key is not an alias). `/reload` → still gone, still `false`. Tick it
  → back, `true`. Hide the plugin from a broker display's own list where it offers one → the tick
  follows. Result:
- **PANEL-27. No reset shows a hidden button.** Hide the button. Reset all settings ▸ Yes → the button
  stays hidden. General's Defaults → Lock frame, General visibility and the rest reset, and the button
  **still** stays hidden (`launcher-§3`). Result:
- **PANEL-28. No raw locale keys.** Walk every page of `/kcd config`, then `/kcd debug window` and
  `/kcd perf` → every label, tooltip title, heading, button and perf step reads as English prose. A
  `SCREAMING_SNAKE_CASE` string (`STEP_START`, `PANEL_TITLE_SUFFIX`, `LIST_HEADER`) means a descriptor
  was handed `NS.L` itself; this addon once shipped a perf panel reading `Ka0s KickCDPANEL_TITLE_SUFFIX`.
  `tests/test_perfsetup.lua` guards the source; this is the only look at what rendered. Result:
- **PANEL-29. General's and Icons' Defaults stay on their own page.** Out of combat, Focus linked (the
  default): `/kcd set scale 1.25`, `/kcd set units.target.icons.primarySize 50`,
  `/kcd set units.target.castbar.timeOffsetY -30`, and on Spells drag row 3 above row 1. Open General and
  click Defaults → the Master scale slider is back at 1 and the grid returns to its normal size;
  `/kcd get units.target.icons.primarySize` → `50 px`; `/kcd get units.target.castbar.timeOffsetY` →
  `-30 px`; the Spells order is still yours. `/kcd set scale 1.25` again, then Grid → Icons with Target in
  the band → Defaults → `/kcd get units.target.icons.primarySize` → `64 px`; the Master scale slider still
  reads 1.25, `timeOffsetY` still `-30 px`, the Spells order still yours. Clean up: Grid → Cast bar →
  Defaults, General → Defaults, Spells → Defaults. Result:
- **PANEL-30. The Options descriptor names the folder.** `/kcd debug on`, then `/kcd config` and open
  every page in turn → each renders exactly as before, with no Lua error, and the console logs no
  `[Cfg] help art:` line. The descriptor now passes `addonName` (LibKa0s v1.67.0, LibKa0s#42), the folder
  name an IdList help mark builds the library's `info` art from. No page here has a help mark yet, so
  this only proves nothing broke; `tests/test_options_panel.lua` pins the field. `/kcd debug off`. Result:

## PROFILE

- **PROFILE-1. The Profiles page draws.** Open another addon's options page first, then Ka0s KickCD →
  Profiles → the AceDBOptions controls (current profile, New, Copy From, Delete, Reset Profile), never
  a blank page under the header. Result:
- **PROFILE-2. Create, switch, copy, delete.** Create `SmokeTest` and switch to it,
  `/kcd set units.target.icons.primarySize 40` → the grid re-draws at 40. Switch to `Default` → the
  grids re-anchor and re-skin to `Default`'s settings. Create `SmokeCopy`, switch to it, Copy From
  `SmokeTest` → the grid re-draws at 40. Switch to `Default` and Delete `SmokeCopy`; keep `SmokeTest`
  for PROFILE-9 – 14. `/reload` after each step → no error, and each result holds. Result:
- **PROFILE-3. Profile scope.** On Profiles, open Existing Profiles: besides `Default` it offers this
  character (`<Name> - <Realm>`), the realm (`<Realm>`) and the class (listed by its name). Pick each
  in turn and `/reload` after each → `KickCDDB.profileKeys["<Name> - <Realm>"]` names the pick:
  `<Name> - <Realm>`, then `<Realm>`, then the class token (`WARRIOR` on a Warrior). Switch back to
  `Default` and delete the three. Result:
- **PROFILE-4. The migration re-runs harmlessly.** Switch profiles → no error and nothing re-folds;
  `global.schemaVersion` reads `5`, account-wide, not per profile. Result:
- **PROFILE-5. Colors and font flags survive a switch.** Create a second profile, switch to it and back
  → cast bar swatches and outline dropdowns show the stored values, never blank or defaults. With
  `/kcd debug on`, no `settings migration ... failed` line. Result:
- **PROFILE-6. Spell lists are per profile.** Edit a spell list on one profile, switch → the other
  profile's list is unchanged. Result:
- **PROFILE-7. One debug line per profile event.** `/kcd debug on`, `/kcd debug window`. Switch profile
  → one `[Profile] switched to '<name>'`. Copy From another profile → one
  `[Set] copied profile '<source>' → '<active>'` and no `[Profile] switched`. Profiles → Reset Profile
  → `[Set] reset profile '<name>' to defaults` with no count. Result:
- **PROFILE-8. A switch leaves the minimap button alone.** Hide the button, switch profile → still
  hidden; switch back → still hidden. Result:
- **PROFILE-9. `/kcd profile` lists.** With `Default` and `SmokeTest` present, `/kcd profile` → a
  `Profiles` header, one row per profile sorted without regard to case, the current one suffixed
  `(current)`, then `/kcd profile <name> switches profile`. No line ends in a colon. Result:
- **PROFILE-10. `/kcd profile <name>` switches.** Switch to `Default` on the Profiles page;
  `/kcd get units.target.icons.primarySize` → `64 px` (`/kcd reset units.target.icons.primarySize` if
  not). `SmokeTest` holds 40 from PROFILE-2. `/kcd profile SmokeTest` →
  `Switched to profile 'SmokeTest'.`; the grid shrinks to 40 with no `/reload`, exactly as a switch on
  the page does, and the Profiles page shows `SmokeTest` as current on its next show.
  `/kcd profile SmokeTest` again → `Already on profile 'SmokeTest'.` and nothing changes.
  `/kcd profile Default`. Result:
- **PROFILE-11. An unknown name is refused, never created.** `/kcd profile Nope` →
  `No profile named 'Nope'.` then the list; the Profiles page has no `Nope`. `/kcd profile smoketest`
  → refused the same way, with `Did you mean 'SmokeTest'?` before the list. Result:
- **PROFILE-12. Quotes and spaces.** Create `My Raid` on the page, switch to `Default`.
  `/kcd profile "My Raid"` → switched to `My Raid`. `/kcd profile 'Default'` → switched back. Delete
  `My Raid`. Result:
- **PROFILE-13. The verb answers while disabled.** `/kcd profile SmokeTest`, `/kcd disable` (the
  master switch is per profile). `/kcd profile` → the list, not the disabled refusal.
  `/kcd profile Default` → switched, and the grids are back (`Default` is enabled).
  `/kcd profile SmokeTest` → the addon stands down again. `/kcd enable`, `/kcd profile Default`.
  Result:
- **PROFILE-14. No switch in combat.** Pull a dummy. `/kcd profile SmokeTest` →
  `Can't switch profiles in combat.` and the profile does not change. `/kcd profile` → the list still
  prints. Leave combat, delete `SmokeTest`. Result:

## STATE

- **STATE-1. The master switch hides and restores.** `/kcd lock`, `/kcd set visibility always`,
  `/kcd set enabled false` → the grids and cast bars go, whatever the visibility mode or target.
  `/kcd set enabled true` → they come back at once. Result:
- **STATE-2. Off is total.** Disabled: `/dump C_AddOns.IsAddOnLoaded("KickCD")` → true (standing down,
  not unloaded). Enter and leave combat, swap target, swap spec → nothing appears, nothing prints,
  `/kcd get locked` reports what it did before. Result:
- **STATE-3. Off unregisters listeners.** Disabled, `/kcd debug on`, enter combat → no
  `[Combat] entered` line in the console. Result:
- **STATE-4. Enable rebuilds from current state.** `/kcd enable`,
  `/kcd set units.focus.enabled false`, `/kcd disable`. While off, `/kcd set units.focus.enabled true`,
  target and focus hostile casters, then `/kcd enable` → every unit whose `units.<unit>.enabled` is
  true comes back in the same turn, including Focus (enabled while the addon was off), with the current
  casts and cooldowns shown, no `/reload`. Result:
- **STATE-5. The minimap button while off.** Disabled, hover the button → `Enabled: No` and the same
  two hints. Left-click → the settings panel, nothing printed. Right-click → Enabled unticked and
  clickable; Locked reads *Locked (enable the addon first)*, grayed, and clicking it does nothing
  (`/kcd get locked` unchanged). Tick Enabled → back on, with the line `/kcd enable` prints. Result:
- **STATE-6. A fresh profile starts unlocked.** On a new profile `/kcd get locked` → `false`, and the
  grid drags with no `/kcd unlock`. Result:
- **STATE-7. Lock and unlock.** `/kcd set units.target.castbar.anchorMode FREE`, `/kcd unlock` → the
  grid and the cast bar both drag. `/kcd lock` → neither does, and both drag strips go. Result:
- **STATE-8. `/kcd toggle` and the Lock frame box.** Panel open on General → Master controls,
  `/kcd toggle` twice → the lock flips each time and Lock frame follows live. Result:
- **STATE-9. The launcher menu.** Right-click the button → a menu titled Ka0s KickCD with exactly two
  ticks, Enabled (ticked) and Locked. Untick Locked → the grids and the cast bar placeholder appear, the
  grid drags, the menu closes, and chat prints the *icon grid unlocked* line `/kcd toggle` prints.
  Right-click → Locked unticked. Tick it → locked. `/kcd get locked` and General → Lock frame agree at
  each step. Result:
- **STATE-10. `resetposition`.** Drag both grids away, `/kcd resetposition` → Target's grid at
  `CENTER / CENTER, x = 0, y = +120` (above center) and Focus's at `y = +260`, exactly; a free cast bar
  and every setting untouched. Drag them away again, General → Reset position → the same. Result:
- **STATE-11. Unlocked bypasses visibility.** `/kcd unlock` with any visibility mode and no target →
  both pieces show at full alpha, so they can be placed. Run STATE-12 – 15 locked. Result:
- **STATE-12. Visibility `always`.** No target, no combat → both pieces visible. Result:
- **STATE-13. Visibility `in_combat`.** No target → hidden. Auto-attack a dummy → both appear on combat
  start; leave combat → both hide. Result:
- **STATE-14. Visibility `target_casting`.** Target a mob that is not casting → hidden. It starts a cast
  or channel → both appear; the cast ends or is canceled → both hide. Result:
- **STATE-15. Visibility `target_casting_interruptible` (the default).** Target a hostile in an
  uninterruptible cast → hidden. Switch to one casting interruptibly → both appear. A cast that flips
  to uninterruptible mid-cast (some bosses) → the cast bar fades to alpha 0 but stays shown (an alpha
  curve, not `:Hide()`). An occasional leak at cast start is a known issue (WoW's `notInterruptible` is
  unreliable then), tracked on the issue tracker. Result:

## COMBAT

- **COMBAT-1. `/kcd config` in combat.** → one `[KCD]` line saying settings cannot open during combat,
  and no panel. Result:
- **COMBAT-2. `/kcd set` in combat.** `/kcd set units.target.icons.primarySize 50` in combat → applies
  live. Result:
- **COMBAT-3. The AddOns sidebar in combat.** In combat, Game Menu → Options → AddOns → Ka0s KickCD,
  then General, Grid, Spells and Profiles in turn → each page shows under the cover reading "Settings
  are locked during combat.", nothing on it can be clicked, and the Settings window stays open. Chat
  prints one gray `settings are locked during combat — changes are refused until it ends` line on the
  first page and none on the others (once per combat). Leave combat → the page on screen draws
  normally. This path skips `OpenOptionsPanel` and is guarded only by the library's page cover, so run
  all five pages, not a sample. Result:
- **COMBAT-4. The combat cover.** Open Grid, enter combat, click a rail entry → the whole page, rail
  included, is under the cover reading "Settings are locked during combat."; nothing changes; one gray
  locked line prints. After combat the page draws normally on the entry you were on. Result:
- **COMBAT-5. The linked note under the cover.** Open Grid with a linked Focus picked in the band, so
  the Linked-to-Target note shows, then pull a dummy → the cover goes over the note as well. Click the
  note's link → nothing happens: the page does not switch to General and no `cannot open settings
  during combat` line prints (the link's own combat refusal sits under the cover). Result:
- **COMBAT-6. The drag strip's right-click in combat.** Unlocked, Free anchor mode, in combat,
  right-click the cast bar's strip → the gray refusal line and no panel. Result:
- **COMBAT-7. Debug dumps in combat.** In combat on a hostile caster, run every `/kcd debug`
  subcommand → no Lua error. Result:
- **COMBAT-8. `/kcd debug interrupt` on a secret cast.** Target a hostile mid-cast of a protected
  interrupt → `notInterruptible` reads `<secret>`, never a coerced value, and the gate decision
  matches what the current visibility mode shows. Result:
- **COMBAT-9. `/kcd debug castbar` on a secret cast.** Same target → the
  `current.notInterruptible: type=…, isSecret=true` line is always followed by a `secret-tainted; …`
  line: that the state comes from `C_CurveUtil.EvaluateColorValueFromBoolean` where it exists, that it
  is unavailable where it does not. On live Retail only the first half is observable; a pre-12.0 or
  Classic-flavor build shows the second. A secret field with nothing after it is the failure. Result:
- **COMBAT-10. The protected-interrupt taint pass.** Run
  `/kcd set visibility target_casting_interruptible` (the mode that runs the interruptible-alpha gate
  on a secret `notInterruptible`), then in combat on a hostile interruptible caster: interrupt it, press the
  interrupt again on cooldown, five or more times over a long cast or channel; with that mode still set,
  swap between a hostile interruptible caster, a hostile uninterruptible caster, a friendly NPC and no
  target → zero Lua errors (the usual signature is `cannot perform arithmetic on a secret value` or
  `attempt to format a secret value` as the interrupt fires), and the interrupt icon's swipe and text
  keep working. Result:
- **COMBAT-11. Diagnostics in combat and in a restricted instance.** `/kcd diagnostics` in combat with
  a hostile caster targeted mid-cast and a second on focus, then again in a Mythic+ key or raid
  encounter → no Lua error; the cast record reads as types; `notInterruptible` in the `interrupt` lines
  reads `<secret>` where the client hides it; charges may read `<secret>`. Result:

## GRID

- **GRID-1. Layout.** With four or more spells enabled, walk `units.target.icons.anchor` through all 13
  tokens, and for each set `units.target.icons.secondaryGrow` to two values valid on its axis → the
  secondary block lays out from the primary icon's named anchor in that direction, no overlap. Result:
- **GRID-2. The overflow warning.** `/kcd set units.focus.enabled false` (each unit warns for its own
  grid). Set `units.target.icons.secondaryRows` × `secondaryCols` below the enabled spell count minus
  one → one line, `dropped <n> icon(s) past the <rows × cols>-slot grid for <CLASS>/<specID> — bump
  rows*cols or remove spells`. Change `primarySize` → no second line. Set another capacity that still
  does not fit → the line prints again for it. Raise it until everything fits, then drop it below
  again → the line prints again (fitting re-arms it). `/kcd set units.focus.enabled true`. Result:
- **GRID-3. Icon size is live.** `units.target.icons.primarySize` from 24 to 96 (the row's range) → the
  grid resizes with no `/reload`. Result:
- **GRID-4. A cooldown starts.** `visibility = always`, cast Pummel at a dummy → its icon desaturates at
  once with a swipe, and with Annotations → Show cooldown text on, a countdown. Result:
- **GRID-5. The GCD is not a cooldown.** While Pummel cools down, cast an on-GCD spell → Pummel's
  swipe is not restarted or touched by the GCD. Result:
- **GRID-6. Two glow triggers, independent.** Primary glow trigger `target_casting_interruptible`,
  secondary `target_casting` → the primary glows only on hostile interruptible casts, the secondaries on
  any hostile cast. Result:
- **GRID-7. Ready again.** When Pummel comes off cooldown → the icon re-saturates and the swipe goes, with
  no `0.0` stuck on the text. Result:
- **GRID-8. The swipe runs smoothly.** Put a spell on a 30 s+ cooldown → the swipe animates without a
  stutter or restart and the countdown ticks continuously. Result:
- **GRID-9. Cooldown visuals hold to the end.** Same cooldown → the icon keeps the cooldown alpha and
  tint for all of it, final second included, and turns ready only when castable. Brightening early is
  the regression (the curves read the total length, not the remaining time). Result:
- **GRID-10. Changes land mid-cooldown.** While it runs, change glow type and glow color, and toggle
  cooldown text and the charges badge → each applies at once. Result:
- **GRID-11. Glow follows the target mid-cooldown.** With the spell still cooling and a
  `target_casting` or `target_casting_interruptible` trigger, the target starts and stops casting → the
  glow follows it. Result:
- **GRID-12. Charges in combat.** Spend and recharge a charged spell (a talented Mind Freeze) in combat
  → the badge keeps counting, though the count is secret. Result:
- **GRID-13. The charges badge inset.** Annotations → Show charges on a charged spell. At the defaults
  (X `-2`, Y `2`) → flush inside the bottom-right corner. X `-20` → 18 px left; Y `20` → 18 px up.
  `/kcd set units.target.icons.chargesOffsetX 900` → clamps to `32 px`, badge at the slider maximum.
  Result:
- **GRID-14. Grid strips carry no close mark.** `/kcd unlock` → the grid strips and cast bar strips
  have the `?` mark and no X (KickCD does not adopt the strip's close option, owner ruling X-03).
  Result:
- **GRID-15. Cooldown text off: the icon still dims, tints and brightens on time (KickCD#9).**
  Annotations → Show cooldown text off. Put Pummel on cooldown → the icon dims and tints for the whole
  cooldown and brightens when it is castable again, with no countdown drawn. Then, mid-rotation, press
  the interrupt inside an on-GCD spell's global cooldown → within a moment the icon dims to the
  cooldown alpha, and the swipe shows the interrupt's cooldown no later than when the GCD's swipe would
  have ended. Result: pass (owner, 2026-10-02)
- **GRID-16. A steady cooldown emits nothing (KickCD#9).** `/kcd debug on`, put a spell on a 30 s+
  cooldown and stand still → one `[Cooldowns]` line when it starts and one when it ends, none repeating
  in between. Then `/kcd perf` through a short fight → `iconApply` is close to 0 calls/sec while
  spells sit on cooldown, and the cost shows under `cdText`. Result: pass (owner, 2026-10-02)

## CAST

- **CAST-1. A cast on the bar.** Target a hostile caster mid-cast → the bar appears at cast start, fills
  over the cast's duration and goes at cast end; the spell name and remaining time draw and the spark
  moves along the fill. Result:
- **CAST-2. Auto-size tracks the visible grid.** `anchorMode PRIMARY`, `autoSize true`, `orientation
  HORIZONTAL`. Disable spells (`/kcd spells disable <id>`) and re-add them, and set `secondaryCols` 4
  then 2 → the bar's long side matches the grid's visible width, not its `rows × cols` capacity,
  shrinking and growing in place; the other side stays at `castbar.width` / `height`. Same with
  `VERTICAL` and height. Result:
- **CAST-3. Orientation resets grow direction.** Switch `orientation` → `growDirection` resets to that
  axis's default (`HORIZONTAL` → `RIGHT`, `VERTICAL` → `UP`). Result:
- **CAST-4. Per-state appearance.** Interruptible bar color `0.2 0.8 0.2 1`, uninterruptible
  `0.8 0.2 0.2 1` → an interruptible cast draws green with its border style and font; an
  uninterruptible one draws red, or fades to 0 under `target_casting_interruptible`. Result:
- **CAST-5. A mid-cast flip.** A boss or trash spell that flips interruptibility mid-cast
  (`UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) → the bar switches state and the glow follows,
  with no Lua error. Result:
- **CAST-6. Primary anchor mode.** `anchorMode PRIMARY`, unlocked → no strip on the cast bar, and the
  bar cannot be dragged by the strip, the mark or its body; it follows the grid when the grid is dragged.
  Result:
- **CAST-7. The strip names its unit.** `anchorMode FREE`, `/kcd unlock`, a cast bar on screen → a dark
  strip with a gold label directly above the bar reading **Target castbar** (and **Focus castbar** on
  the focus bar). Result:
- **CAST-8. Drag the strip.** Drag it → the bar moves; release, `/kcd lock`, `/reload` → the position
  sticks. Result:
- **CAST-9. The `?` mark drags too.** Drag the `?` on the strip → the bar moves. Result:
- **CAST-10. Strip tooltips.** Hover the strip, then the `?` → each shows the same tooltip, titled
  `KickCD castbar` and reading `Drag to move. Right-click for settings.` (prose, no locale key); the
  `?` brightens under the cursor. Result:
- **CAST-11. Right-click opens settings.** Out of combat, right-click the strip → the settings panel
  opens. Result:
- **CAST-12. Back to Free without leaving the panel.** From PRIMARY set Free again in the panel → the strip
  comes back (`ApplyLock` does not run on every route that changes `anchorMode`). Result:
- **CAST-13. Two bars at once.** `units.target.castbar.enabled` and `units.focus.castbar.enabled` true,
  `/kcd lock`, `/kcd set visibility always`. Target one hostile caster and focus another, both
  mid-cast → both bars animate at the same time and independently; each unit's second cast (no
  retarget) animates like its first; swap target and focus and repeat; names and times track on both
  and neither shows the other's spell. One frozen bar, or both showing the same fill, is a mis-bound
  `onUpdateScript`; a Lua error naming `Castbar.lua` and a nil `onUpdateScript` is too. Result:
- **CAST-14. An empowered cast.** Duel an Evoker. Target (then focus) them first, and only then have
  them start Fire Breath or Eternity Surge → the bar shows the empower, the `*_casting` visibility and glow follow
  it at once, and the bar clears on its release. A blank bar or a late glow means the
  `UNIT_SPELLCAST_EMPOWER_*` routes are missing ([midnight-quirks.md](midnight-quirks.md)). Result:

## FOCUS

- **FOCUS-1. Focus defaults.** On a fresh profile → Focus is enabled and linked to Target, its grid at
  y = 260 above Target's (y = 120), with a small gap between Focus's cast timer and the Target label.
  Result:
- **FOCUS-2. Enabling Focus builds it live.** `/kcd set units.focus.enabled false`, `/reload` (so no
  Focus frames exist yet), `/kcd unlock` (a locked cast bar stays hidden until a real cast), then
  `/kcd set units.focus.enabled true` → a second grid (`KickCDIconGridFocus`) and the cast bar's
  placeholder (`KickCDCastbarFocus`) appear with no further `/reload`, the grid tracking the same spells
  as Target. Result:
- **FOCUS-3. Independent gating.** `/kcd lock`, `/kcd set visibility target_casting_interruptible`, a
  hostile target and a different hostile focus. Only the target casts → only the Target pair shows; only the focus casts → only the
  Focus pair; both cast → both. Result:
- **FOCUS-4. Disabling Focus.** `/kcd set units.focus.enabled false` → the Focus grid and bar go at once;
  Target is untouched. Result:
- **FOCUS-5. Enabling mid-cast.** Focus disabled, the focus mob mid-cast, `/kcd set units.focus.enabled
  true` → the Focus bar shows at once at the cast's current progress. Disable, let a new cast start,
  enable again → the same, no stale state. Result:
- **FOCUS-6. A linked Focus page.** Pick Focus in the band on each Grid entry → the full tab strip,
  every tab grayed and not clickable, and only the note *"Linked to Target. Untick 'Use same styling as
  Target' on the General page's Units tab to give Focus its own."* The page keeps its shape; picking
  Target restores color and clicks. Result:
- **FOCUS-7. The note's link.** *General page's Units tab* is in link blue. Mouse along the line →
  nothing lights up behind it (no plate, no bright-green block). Click anywhere on it → General opens
  on its Units tab. Result:
- **FOCUS-8. Linked Focus mirrors Target live.** Change Target's `primarySize` → the linked Focus grid
  matches at once. Result:
- **FOCUS-9. Unlinking.** Untick General → Units → "Use same styling as Target", then open Grid → Icons
  on Focus → the strip and rows appear, seeded with Target's last-copied values (or defaults). The page
  was hidden when you unticked; it repaints on its next show. Result:
- **FOCUS-10. Unlinked edits stay on Focus.** Change `units.focus.icons.primarySize` → Target's grid does
  not change. Result:
- **FOCUS-11. Relinking reverts live.** Re-tick the box → Focus mirrors Target again at once and Icons
  collapses to the note under its grayed strip; your Focus values stop applying. Result:
- **FOCUS-12. The link controls.** General → Units shows `[Use same styling as Target] [Copy styling
  from Target]` on one line, the button in the right half, and neither control appears anywhere else.
  Result:
- **FOCUS-13. Copy styling from Target.** `/kcd resetall` (Focus linked, every styling row equal to
  Target's), then `/kcd set units.target.castbar.orientation VERTICAL`,
  `/kcd set units.target.castbar.growDirection DOWN`, `/kcd set units.target.icons.primarySize 50` and
  `/kcd debug on`; click General → Units → Copy styling from Target → every Focus `icons`, `castbar`,
  `label.style` row and `label.show` takes Target's value, `link` becomes false, Focus's bar is vertical
  and still grows Down (orientation's own reset to Up must not win). The console shows one
  `[Set] copy target→focus: 4 rows` line and no per-row `[Set] units.focus.…` lines: N counts the rows
  the copy changed, here the three Target rows you moved off their defaults plus the link. Then change
  Target → Focus does not follow (a one-time copy). Result:
- **FOCUS-14. The link from the slash, and Defaults.** `/kcd set units.focus.link false` → the tick
  clears on an open General page and the Grid entries grow their rows; `true` collapses them. With
  Focus unlinked, General's Defaults re-links it. Result:
- **FOCUS-15. Position and identity stay per unit.** Linked or not, drag the Focus grid → Target's does
  not move; Focus's label text stays its own. Result:
- **FOCUS-16. Unlinked Focus has its own alpha and tint.** Unlink first, then `visibility always`, both
  units enabled, and `/kcd set units.target.icons.cooldownAlpha 0.20`,
  `units.target.icons.cooldownTint 1 0.3 0.3 1`, `units.focus.icons.cooldownAlpha 0.90`,
  `units.focus.icons.cooldownTint 0.3 0.3 1 1`; unlock, part the grids, lock. Cast a real interrupt
  (cooldown over ~1.6 s) → Target's icon heavily dimmed and red, Focus's nearly bright and blue. Identical
  grids mean Focus inherits Target's curves. (While only the GCD runs both look ready; that is correct.)
  Result:
- **FOCUS-17. A Focus alpha change mid-cooldown.** With the settings panel open on Grid → Icons,
  mid-cooldown `/kcd set units.focus.icons.cooldownAlpha 0.40` → Focus changes while the cooldown runs;
  Target does not. Then, panel still open, pick Target and Focus in the band and click every tab on
  Icons, Cast bar and Text Label → the Unit picker lists exactly `Target` / `Focus` throughout (anchor
  points or text positions there are a stale refresher that survived the rebuild). Result:
- **FOCUS-18. An unrelated edit leaves the curves alone.** Mid-cooldown, change Target's Border style
  (Icons → Border) to a visibly different border → Target's edge changes and neither grid's alpha or
  tint shifts. Result:
- **FOCUS-19. Relinking mid-cooldown reverts the curves.** With FOCUS-16's values still set (Target
  0.20 and red, Focus 0.40 and blue), cast the interrupt again if its cooldown has ended, and while it
  runs tick General → Units → "Use same styling as Target" → Focus's icon takes Target's dim red at
  once, mid-cooldown, with no `/reload`. Clean up: Icons → Defaults with Target in the band; untick the
  box, Icons → Defaults with Focus in the band, and tick the box again. Result:

## LABEL

- **LABEL-1. The default label.** Grid → Text Label, Target → Show label is on and "Target" sits just
  above the grid. Untick → only the label goes, grid and bar stay; tick → back. General carries no
  label controls. Result:
- **LABEL-2. Label text.** Type "MainTank" in the Label text box and press Enter → the label changes at
  once. Result:
- **LABEL-3. Attach to.** Switch Attach to between `castbar` and `icons` → the label re-anchors; drag
  the grid → it follows. Result:
- **LABEL-4. Anchor pairs.** Walk Label anchor point and Attach point through several pairs (`TOP` /
  `BOTTOM`, `LEFT` / `RIGHT`) and vary the X and Y offsets → the label moves to match, and no pick
  raises an error. Result:
- **LABEL-5. Justify.** Step Horizontal and Vertical justify with multi-word text → the alignment moves.
  Result:
- **LABEL-6. Rotation.** Set Rotation to 45, then -90 → the label turns, and is upright at 0. At 45 the
  control is labeled `Rotation (degrees)` and `/kcd get units.target.label.style.rotation` echoes
  `45 deg`; neither shows an empty box where a degree sign used to be. Result:
- **LABEL-7. Font.** Change Font, Font size and Font flags → the label redraws each time. Result:
- **LABEL-8. Label color.** Pick a bright color → the text changes; switch Attach to → the color stays.
  Result:
- **LABEL-9. An unlinked Focus label.** Unlink Focus, set its text to "Kick this" and change its rotation
  or color → Target's label is unaffected; both show their own text and style; positions are
  independent. Relink → Focus's style mirrors Target's again and its text stays "Kick this". Result:
- **LABEL-10. Focus off hides its label.** Both labels shown, `/kcd set units.focus.enabled false` →
  the Focus label goes at once, Target's stays; enable → back. Result:
- **LABEL-11. The label follows General visibility.** `visibility target_casting`, Show label on,
  Attach to `castbar` → target not casting: grid, bar and label all hidden; cast starts: all three
  appear; cast stops: all hide. Same with Attach to `icons`. Result:
- **LABEL-12. Always means the label shows.** `visibility always`, Show label on, target not casting.
  Attach to `icons` → the label shows above the grid. Attach to `castbar` → the label still shows,
  placed against the hidden cast bar: it follows the grid's visibility, never the bar's own hiding
  when nothing is cast (a label parented to the bar used to vanish here). Result:
- **LABEL-13. The strip clears the label.** `/kcd unlock` with the label attached to the icons → the grid
  strip sits above the label text. Label off → the strip drops to the grid's top. Attach the label to the
  cast bar, or anchor it to the grid's bottom → the grid strip returns to the grid's top and the cast
  bar's strip clears the label instead. Result:
- **LABEL-14. The strip clears it straight after `/reload`.** Unlocked, `/reload`, no lock toggle →
  both strips ("Ka0s KickCD — Target" / "— Focus") sit fully above their labels with a small gap.
  Untick Show label on each unit (unlink Focus first) → that strip drops to just above its icons; tick
  → it climbs back. Font size 30 → the strip still clears it. `/kcd lock` hides both. Result:
- **LABEL-15. Rapid changes raise nothing.** Panel open on Text Label, flip Attach to between
  `castbar` and `icons` ten times fast; drag the X offset, Y offset and Rotation sliders end to end
  quickly several times; then cycle `/kcd set visibility` through `always`, `in_combat`,
  `target_casting` and `target_casting_interruptible` back to back → no Lua error at any point, and the
  label ends where the final values put it. Result:

## SPELLS

- **SPELLS-1. A spec swap rebuilds.** Switch spec → the watched list and the grid rebuild for the new
  spec's spells, no error. Result:
- **SPELLS-2. A talent swap rebuilds.** Swap a choice node that replaces an interrupt-adjacent spell →
  the list rebuilds at once, no spec swap needed. Result:
- **SPELLS-3. An open Spells page follows the spec.** With Settings → Spells open, switch spec → the
  spec dropdown moves to the new spec and its rows redraw. Result:
- **SPELLS-4. Pets.** On a Hunter, `/cast Call Pet 1` → the pet's interrupt joins the grid. Dismiss it
  → it leaves with no stale icon, and `/kcd debug spells` no longer lists it. Result:
- **SPELLS-5. The Cooldown Manager gate.** On the active spec, add a spell not tracked by the Cooldown
  Manager (on the page and with `/kcd spells add <id>`) → `Spell <name> (#<id>) is not tracked by the
  Blizzard Cooldown Manager for this specialization.`, and nothing is added. A tracked id is added.
  Result:
- **SPELLS-6. Names with spaces.** As a Shaman, `/kcd spells add Wind Shear` → Wind Shear is added, the
  name never split. Result:
- **SPELLS-7. Unknown class or spec.** `/kcd spells add <id> WARLORD 99999` → `Unknown class WARLORD`;
  `/kcd spells add <id> <CLASS> 99999` → `Unknown spec 99999 for <CLASS>`. Neither writes to
  `KickCDDB`. Result:
- **SPELLS-8. A spec swap with the page closed.** Close Settings, switch spec, open Spells → the Add box
  accepts only the new spec's Cooldown Manager spells. Result:
- **SPELLS-9. Editing another spec.** Pick another class and spec in the page's dropdown and add any
  valid spell id → accepted (the lenient path). Result:
- **SPELLS-10. The subcommands, live.** Page open, run `/kcd spells list`, `disable <id>`,
  `enable <id>`, `category <id> stun`, `remove <id>`, and `add <id> <CLASS> <SPEC>` → each works and
  the page's rows redraw after each write, no reopen. Result:
- **SPELLS-11. Reset one spec.** Edit two specs' lists, then `/kcd spells reset <CLASS> <SPEC>` on one →
  only that spec is rebuilt from the defaults. The page's Defaults button → only the selected spec.
  Result:
- **SPELLS-12. Reset every spec.** `/kcd spells resetall` → every spec's list is rebuilt. Result:
- **SPELLS-13. Drag to reorder.** Grab row 3's handle and drop it above row 1 in one gesture → the list
  and the grid's priority follow; one box and one handle per row; the drop line is in the list color;
  `/reload` keeps the order. The row strip looks as it did before the list moved onto `RenderGrid`
  (KickCD#10): no gap between rows, and a drop onto the fourth or a later row lands on that slot,
  not one off. Start a drag and press Esc → no stray line. Leave and re-enter the page
  twice → no handle or box left stranded. Result:
- **SPELLS-14. Row tooltips and the remove mark.** Hover a spell name → the spell tooltip; a category
  dropdown → the Category tooltip. The remove button draws the red catalog close mark. Result:
- **SPELLS-15. Other addons' panels are untouched.** Close Settings, open another Ka0s addon's panel
  (`/at config`), hover and click its labels → no KickCD spell tooltip, and every click lands. Result:
- **SPELLS-16. Racials survive a reset.** On a race with a racial cast-stopper, reset one of your own
  class's specs (Defaults or `/kcd spells reset`) → the racial is the last row. Reset another class's
  spec → no racial. Result:

## DIAG

- **DIAG-1. `/kcd debug spells`.** → `Cooldowns: class=<CLASS> spec=<SPEC> (<specID>)`, then one line
  per watched spell: `[<id>] <name> ready=… active=… cdObj=yes|nil chargeCdObj=yes|nil charges=…`,
  charges maybe `<secret>` in combat, and no remaining-time field. Result:
- **DIAG-2. `/kcd debug castbar`.** Target a hostile caster mid-cast → `castbar state (target)`, the
  cast record with `current.notInterruptible: type=…, isSecret=…`, then `configured colors` and
  `live SetStatusBarColor values` for both states. With no cast the dump stops at
  `no active cast tracked (current = nil)`. Result:
- **DIAG-3. Logging is session-only.** `/kcd debug on` → chat says `debug logging ON` and the `[Tag] …`
  trace lines go to the console, not chat; `off` → `debug logging OFF` and they stop; `toggle` flips
  it. `/reload` → off again; no saved setting holds it. Result:
- **DIAG-4. `/kcd debug window`.** → the console opens and closes; logging keeps its state either way.
  Result:
- **DIAG-5. `/kcd debug events`.** → `no rejected events` on a live client. `/kcd debug on`, `/reload`,
  turn it on again → the `[Init]` line ends at `profile '<name>'` with no `rejected event(s)` clause.
  Result:
- **DIAG-6. Bare `/kcd debug`.** → the console toggles and the debug subcommand list prints. Result:
- **DIAG-7. The combat trace.** Debug on, console open. Enter and leave combat → one
  `[Combat] entered`, one `[Combat] left`; nothing at login, nothing per tick. Result:
- **DIAG-8. A section's Defaults logs a count.** Move two Cast bar settings, press Cast bar's Defaults
  (Target in the band) → one `[Set] reset castbar: 2 rows`, no per-row `[Set]`. Again →
  `[Set] reset castbar: 0 rows`. Result:
- **DIAG-9. Reset all logs one line.** Move three settings, Reset all settings (or `/kcd resetall`) →
  exactly one `[Set] reset profile '<name>' to defaults (3 rows)`, no `[Set] reset all` and no
  `[Profile] switched`. Again at once → `(0 rows)`, never the schema's size. Result:
- **DIAG-10. The reset mute does not stick.** After DIAG-9, `/kcd set locked true` → its own
  `[Set] locked = true`. `/kcd set locked false` and press General's Defaults within a third of a
  second → `[Set] locked = false` prints before `[Set] reset general: …`. Result:
- **DIAG-11. The cast and grid traces.** `target_casting_interruptible`; the target starts and stops an
  interruptible cast → at the start one `[Cast] [target] cast gate: interruptible on` (`interruptible
  secret (combat-tainted)` where the client hides the flag), at the stop one
  `[Cast] [target] cast gate: interruptible none (no hostile cast)`; one
  `[IconGrid] [target] visibility target_casting_interruptible: shown` or `…: hidden` each time the
  grid's shown state actually changes; nothing on refreshes that move neither. Result:
- **DIAG-12. The open trace.** `/kcd config` out of combat → one `[Open] settings panel` per open. Result:
- **DIAG-13. The spell-list traces.** On the Spells page add, toggle, recategorize, drag, remove and
  reset a spec → exactly one write line each: `[Spells] add <id> to <CLASS>/<SPEC>: N spells`,
  `enable/disable <id> in …`, `category <id> = <cat> in …`, `move <from> -> <to> in …`,
  `remove <id> from …: N spells`, `reset <CLASS>/<SPEC>: N spells`. `/kcd spells remove` and
  `/kcd spells reset` log the same lines; `/kcd spells resetall` logs one
  `[Spells] resetall: N lists, M spells`. The page's drag list also traces its own gesture and
  repaint (`[Spells] grab …`, `drop …`, `released …`, `painted …`); those are not writes. Result:
- **DIAG-14. The setting trace.** Change a setting → one debounced `[Set] …` line after it settles; no
  echo, no per-keystroke lines. Result:
- **DIAG-15. No spam.** 30 s+ in combat with no target casts → no `[Combat]`, `[Cast]` or `[IconGrid]`
  lines beyond the transitions already logged. Result:
- **DIAG-16. The console header.** `/kcd debug window` → the title bar's `Debug: ON` (green) or
  `Debug: OFF` (red) label is there; Esc closes the window. Opening it raises no error. Result:
- **DIAG-17. The line counter and its cap.** Grow the log (debug on in combat) → the bottom-right reads
  `N / 3000 lines`, rising one per line; Clear → `0 / 3000 lines`, log empty. Fill it past the cap (a
  long combat, or twenty-odd `/kcd diagnostics`) → `3000 / 3000 lines` and it stays there; Copy opens
  without a hitch. Result:
- **DIAG-18. The scrollbar tracks.** With more lines than fit, wheel up and down → the thumb moves with
  it; drag the thumb → the log follows; no flicker. Thumb at the bottom is newest, at the top oldest.
  Result:
- **DIAG-19. Inert when it fits.** After Clear → the scrollbar still shows, thumb parked, ignoring wheel
  and drag, and the right gutter keeps its width. Result:
- **DIAG-20. The shared window edge.** The console reads as a flat 1px black border with a 1px light-gray
  highlight inside it, a gold "Ka0s KickCD — Debug" title and a gray divider. Beside a second Ka0s
  addon's console → border, highlight, divider and title are indistinguishable. A difference means
  a host passing `applySkin` again or `libs/LibKa0s` drifting from `../LibKa0s` (fix upstream and
  re-vendor, never in `libs/`). Result:
- **DIAG-21. The title bar marks.** → copy, clear and close are three small white glyphs from
  `libs/LibKa0s/media/icons/`, with no tooltips. A `×`, or the words Copy and Clear, means
  `addonName = addonName` fell out of `core/DebugLogSetup.lua`'s descriptor. Result:
- **DIAG-22. The copy window's close.** Click copy → `KickCDDebugCopyWindow` opens with a read-only box,
  and its close is the same mark. Result:
- **DIAG-23. The perf panel's close.** `/kcd perf start` → the step panel has exactly one close control,
  top right, level with the title about 6 px in: the same `close` mark as the console's, pixel for pixel
  side by side. A `×` means `addonName` stopped reaching the library's `PerfPanel`. Result:
- **DIAG-24. The perf close only hides.** Click it → the panel hides, the run is not canceled, and
  `/kcd perf report` still has the capture. Result:
- **DIAG-25. The console face is monospace.** → timestamps and `[tags]` line up in a column. A
  proportional face is the honest fallback (`media/fonts/` missing from the payload); no text at all is
  the failure. Result:
- **DIAG-26. The perf strings.** `/kcd perf start mylabel` → `perf run STARTED — <YYYY-MM-DD HH:MM>
  mylabel`; `/kcd perf finish`, then `/kcd perf report` → the report's `capture:` line names the same
  label. `/kcd perf start` with no label → the start line carries the timestamp alone (the library
  always stamps one, so `unlabeled` never shows); `/kcd perf cancel` → `perf run CANCELED — nothing
  saved`, one L. A doubled L means the string did not come from the vendored payload. Result:
- **DIAG-27. The README's bug-report steps.** From a fresh `/reload` with the console closed, follow
  README → *Reporting a bug* word for word → every step works and the paste holds the trace and the
  whole report. Result:
- **DIAG-28. `/kcd diagnostics` keeps the trace and copies clean.** Debug on, a few target casts, then
  `/kcd diagnostics` → the console opens if closed; the trace sits above
  `==== Ka0s KickCD diagnostics begin ====`; chat prints *Diagnostic report written to the debug
  console: N lines. Use Copy to share it.* Copy and paste → the trace, both markers
  (`==== Ka0s KickCD diagnostics end: N line(s) ====`), no `|c` escapes, and the counts agree. Result:
- **DIAG-29. The report's shape.** → `[State]` first after the `[Diag]` identity lines, sections in
  [debug.md](debug.md#kcd-diagnostics-the-report-debug-logging-14)'s order, no `section <name> failed`,
  about 100 to 200 lines on a default profile. Result:
- **DIAG-30. Ungated.** `/kcd debug off`, `/kcd diagnostics` → the full report, begin to end marker,
  with nothing missing: it lands whatever the flag read before the run. The run turns logging on
  first (DIAG-40), so afterwards the header reads `Debug: ON`. Result:
- **DIAG-31. While disabled, both forms.** `/kcd disable`, `/kcd diagnostics`,
  `/kcd debug diagnostics` → both write a full report; the state line reads
  `enabled stored=false, stood down=true, holds=…`; `cooldowns`, `icongrid`, `castbar` and `unitlabel` each
  print one `stood down: …` line; nothing stands up. `/kcd enable`. Result:
- **DIAG-32. No alias.** `/kcd diag` → `unknown command 'diag'` and the help index;
  `/kcd debug diag` → the unknown-word line and the debug list. Neither writes a report. Result:
- **DIAG-33. The long alias and any case.** `/kickcd diagnostics`, `/kickcd debug diagnostics` and
  `/kcd DIAGNOSTICS` → each writes the same report. Result:
- **DIAG-34. The console resizes.** `/kcd debug window` → a small grip sits in the bottom-right corner,
  clear of the `N / 3000 lines` counter. Drag it out and in on both axes → the window follows; the log,
  the scrollbar and the title-bar controls follow their edges, the counter and the thumb stay in step,
  and the lines and scroll position are kept. Drag it as small as it goes → it stops while the title and
  every title-bar control still fit side by side and a few lines show; nothing overlaps. Result:
- **DIAG-35. The console's size is for the session.** Resize the console, close it (Esc or the close
  mark) and reopen it → the same size, not the default. `/reload`, reopen → back at 700 × 344. Drag the
  window somewhere, resize it, `/reload` → the default size again, and the position behaves as it did
  before this change. `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` holds no console size. Result:
- **DIAG-36. Each console is its own.** Beside a second Ka0s addon's console (DIAG-20), resize KickCD's →
  the other keeps its size; resize the other → KickCD's does not move. Result:
- **DIAG-37. The copy window resizes.** Click copy → `KickCDDebugCopyWindow` has the same grip. Drag it
  on both axes → the text box widens and narrows with it, the scroll bar's down arrow stays clickable
  above the grip, and there is a minimum it will not go under. Close and reopen it → the same size;
  `/reload`, open it again → the default size. Resizing it leaves the console's size alone. Result:
- **DIAG-38. The perf panel resizes in width only.** `/kcd perf start` → the step panel has a grip in
  its bottom-right corner. Drag it → the width changes and every step row stretches to the new width;
  the height does not move, and the panel will not go narrower than it opened. `/kcd perf hide`,
  `/kcd perf show` → the same width; `/kcd perf cancel`, `/reload`, `/kcd perf start` → the default
  width again. Result:
- **DIAG-39. The Diagnostics link.** Bare `/kcd debug` → in the title bar, top left, the word
  **Diagnostics** sits just right of the `Debug: ON` / `Debug: OFF` label with a small gap, drawn
  orange in the same plain text as that label: no button art, border or background. Hover it → it
  brightens; move off → orange again. With logging off, click it → logging turns on first: the label
  reads `Debug: ON`, chat prints `debug logging ON`, and the console gains `[Debug] logging enabled`
  and the `[Init]` summary; then the report is written after them (begin to end marker, as DIAG-28,
  its header reading `debug logging: on`) with the one chat line giving its line count. Click it
  again → the report appends once more, with no second `logging enabled` line. Toggle the label
  between ON and OFF → the gap after it holds for either word. Drag the console in as far as it goes
  (DIAG-34) → the link still fits beside the label and the title. Result:
- **DIAG-40. Diagnostics turns logging on for the session.** `/reload` → logging is off (DIAG-3).
  `/kcd diagnostics` → chat prints `debug logging ON`, then the report's line-count line; the console
  holds `[Debug] logging enabled` and the `[Init]` summary ahead of the begin marker, the header reads
  `debug logging: on`, and the title-bar label reads `Debug: ON`. Change a setting → a `[Set]` line
  streams. `/reload` → logging is off again. `/kcd debug diagnostics`, or the console's Diagnostics
  link (DIAG-39) → the same: logging on for the session. `/reload` once more, then `/kcd debug on` and
  `/kcd diagnostics` → the report appends with no second `logging enabled` line. `/kcd debug off` →
  logging stops, and nothing turns it back on until the next report or `/kcd debug on`. Result:
- **DIAG-41. A Slash refusal shows in the console.** `/kcd debug on`, `/kcd debug window`. Type
  `/kcd frobnicate` → chat prints `unknown command 'frobnicate'` and the help index, and the console
  gains one `[Cmd] refused frobnicate: unknown verb` line. `/kcd set locked banana` → one
  `[Cmd] refused set locked: parse` line. `/kcd disable`, then `/kcd lock` → chat prints the disabled
  line, and the console gains one `[Cmd] refused lock: disabled`; `/kcd enable`. In combat,
  `/kcd profile Default` (with a second profile active) → `Can't switch profiles in combat.` in chat
  and one `[Cmd] refused profile Default: in combat`. No refusal is written twice, and none has a
  second line beside it naming the same verb. Result:
- **DIAG-42. A Lifecycle edge shows in the console.** `/kcd debug on`, `/kcd debug window`.
  `/kcd disable` → one `[Lifecycle] stood down: added disabled (holds: disabled)` line and no
  `[State] stood down` line. `/kcd disable` again → no new `[Lifecycle]` line (nothing changed).
  `/kcd enable` → one `[Lifecycle] stood up: released disabled (holds: none)`. Result:
- **DIAG-43. State lines land at the first enable.** `/reload`, then `/kcd debug on` → after
  `[Debug] logging enabled` and the `[Init]` summary, the console holds one `[Launcher] registered`
  line. `/kcd debug off`, `/kcd debug on` → no second `[Launcher] registered`. With
  `libs/LibCustomGlow-1.0` renamed aside and a `/reload`, `/kcd debug on` → one
  `[Init] LibCustomGlow-1.0 absent; no icon glows` line, and the `[Init]` summary carries no
  `missing` clause. Restore the folder. Result:
- **DIAG-44. Clear re-arms the change-gated lines.** `/kcd debug on`, `/kcd debug window`, open the
  settings on the General page. Drag the master scale slider back and forth → at most one
  `[Cooldowns] rebuild …` line, however long the drag. Click the console's clear control, then nudge
  the slider → exactly one `[Cooldowns] rebuild …` line, although the watched list did not change;
  keep dragging → no more. Result:
- **DIAG-45. The interrupt dump's secret sentinel.** In combat, target a hostile caster whose cast
  flags are secret and type `/kcd debug interrupt` → every secret-tainted position reads
  `isSecret=true  value=<secret>`, with no Lua error, the same spelling as `charges=<secret>` in
  `/kcd debug spells` (both are LibKa0s-Core's `NS.SECRET` now). Result:

## DEGRADED

Before the rename, `/kcd set units.target.castbar.anchorMode FREE`. With the library gone the degraded
`/kcd set` writes only `enabled` and `locked`, and the settings panel does not open, so the anchor mode
cannot be changed afterwards; an earlier reset puts it back to Primary. Then rename `libs/LibKa0s` to
`libs/LibKa0s_off` and `/reload` before DEGRADED-1.

- **DEGRADED-1. It degrades, it does not error.** → zero Lua errors at login; `/kcd` answers and the host
  verbs work. Result:
- **DEGRADED-2. `/kcd list`.** → exactly `/kcd list is unavailable: the LibKa0s library did not load.`,
  tagged `[KCD]`. Result:
- **DEGRADED-3. Disable and enable.** `/kcd disable` → `enabled = false`, the grids go, no error.
  `/kcd lock` → `Ka0s KickCD is disabled — enable it with /kcd enable`. `/kcd enable` →
  `enabled = true`, the grids return. Result:
- **DEGRADED-4. Lock and unlock.** `/kcd unlock`, `/kcd lock` → each confirms and moves the lock.
  Result:
- **DEGRADED-5. Plain help rows.** `/kcd help` → rows read `/kcd <verb>  <desc>`: white, two spaces, no
  em-dash separator between verb and description (a description may carry its own em dash, as
  `disable`, `get`, `set`, `reset`, `spells`, `debug` and `perf` do). Result:
- **DEGRADED-6. One notice.** → the missing-library notice appears exactly once per session, naming
  `libs/LibKa0s`, however many lines print after it. Run DEGRADED-11's dump too: the notice comes
  before the dump, never once per dump line. Result:
- **DEGRADED-7. The same sentence as the other addons.** Do the same rename on AbsorbTracker and
  ConsumableMaster → all three state the cause (`NS.LIBKA0S_MISSING`) identically, differing only in the
  addon name and the trailing consequence. Result:
- **DEGRADED-8. Each seam names its own consequence.** `/kcd config` → opens nothing, one line about the
  settings panel; `/kcd debug` → its line about the debug console window; `/kcd perf` → its line
  saying performance measurement is unavailable. Result:
- **DEGRADED-9. No report.** `/kcd diagnostics` and `/kcd debug diagnostics` → each prints
  `/kcd diagnostics is unavailable: the LibKa0s library did not load.` and nothing else. Result:
- **DEGRADED-10. No profile verb.** `/kcd profile` and `/kcd profile Default` → each prints
  `/kcd profile is unavailable: the LibKa0s library did not load.` and switches nothing. Result:
- **DEGRADED-11. The castbar dump prints tagged.** Target anything, `/kcd debug castbar` → the dump
  prints, every line tagged `[KCD]`. A Lua error naming `Castbar_Debug.lua` and a nil `emit` means
  `Util.print` is missing on the degraded path. Result:
- **DEGRADED-12. The cast bar drags by its body.** Target's anchor mode set to Free before the rename (see
  above), `/kcd unlock` → the Target cast bar's preview shows with no strip, and drags by its body. No
  error. Result:
- **DEGRADED-13. Restore.** Rename the folder back to `libs/LibKa0s` and `/reload` → the notice is gone
  and the console is back. Result:
- **DEGRADED-14. Plain sub-help rows.** Run this before DEGRADED-13's restore. `/kcd debug` and
  `/kcd spells` → each prints its sub-list as plain `/kcd debug <verb>  <description>` (and
  `/kcd spells <verb>  <description>`) rows: no color, no em-dash separator, the same shape as
  DEGRADED-5's help rows, and no Lua error. `/kcd debug events` still answers. Result:
- **DEGRADED-15. The interrupt dump still says `<secret>`.** Run this before DEGRADED-13's restore. In
  combat, target a hostile caster whose cast flags are secret, `/kcd debug interrupt` → the dump prints,
  every line tagged `[KCD]`, and every secret-tainted position reads `value=<secret>` (the stub's
  `NS.SECRET`), with no Lua error. Result:

## Non-English client

A client set to a non-English locale; frFR is the reported case (issue #8), and an Elemental Shaman
reproduces it exactly.

- **LOC-1. The grid populates.** Log in on a fresh profile → the grid fills with the spec's default
  spells. The original bug was an empty grid with no error. Result:
- **LOC-2. `/kcd debug spells` speaks tokens.** → the English spec token beside the numeric id,
  `class=SHAMAN spec=ELEMENTAL (262)`, on every locale. Result:
- **LOC-3. The rebuild line.** Debug on → the `[Cooldowns] rebuild` line reads
  `SHAMAN(7) ELEMENTAL(262): N watched (...); M skipped (...)`, tokens and ids, not localized names.
  Result:
- **LOC-4. Both spec forms resolve.** `/kcd spells add 51490 ELEMENTAL` and
  `/kcd spells add 51490 Élémentaire` → the same list; the output echoes the English token. Result:
- **LOC-5. The page shows the client's names.** Settings → Spells → spec names in the client's language
  (`Élémentaire`) while the store holds `[262]`. Result:
- **LOC-6. The spec-key upgrade, per profile.** Log in with a `KickCDDB` saved by v1.2.0 or earlier with
  customized spell lists, `/reload`, inspect it → numeric spec keys, your entries intact under them.
  Switch to a second profile and check again → rekeyed too (the rekey runs on each profile as it is
  activated). Result:

## Pending sign-off

The pre-2026-09-29 document recorded no result for any check, so every check carried over from it is
owed unless an owner run records its pass. Three runs do: the Grid page checks on 2026-09-26 (KC-S1
to KC-S11, the old `§36`, `Ka0sAddonsCommonTasks/docs/2026-09-26-NAVRAIL_ADOPTION`), the diagnostics
checks on 2026-09-26 (the old `§35`, `2026-09-25-DIAGNOSTICS_COMMAND/99_REPORT.md` § 6), and the
minimap button re-run on 2026-09-25 in every addon (left-click opens settings, right-click opens the
options menu, the status tooltip; part of the old `§33`,
`2026-09-23-REVIEW_AND_STANDARDS_AUDIT_REMEDIATION/06_SMOKE_TESTS.md` X1.4). So INSTALL-11, PANEL-4 – 7,
COMBAT-4, COMBAT-11, GRID-14, DIAG-27, DIAG-31 – 33 and DEGRADED-9 are signed and not listed.
A check that merged a passed step with an unrun one is listed for the unrun half. Checks new in this
rework, and checks whose expectation it corrected against the code, are listed too. Origins are the
old document's sections (`§n`, with its line numbers where a section held several checks). Sign one
off on its own `Result:` line, then remove its row here.

| ID | Origin | Why it is owed |
|---|---|---|
| INSTALL-1 – 4 | §1 L65 – 66, L70 – 71 | No result recorded |
| INSTALL-5 | §2 L89 – 93 | No result recorded; corrected: `/kcd get` echoes `50 px` and `{0.20, 0.80, 0.20, 1.00}` |
| INSTALL-6 – 9 | §17, §21, §23 | No result recorded |
| INSTALL-10, INSTALL-13, INSTALL-14 | §33 L976 – 980, L990 – 992, L1009 – 1012 | No result recorded |
| INSTALL-12 | §33 L983 | Left-click opening settings passed (2026-09-25, X1.4); the landing page and the untouched lock have no result |
| SLASH-1 – 3 | §1 L67 – 68, §14 L406, §11 L326 | No result recorded |
| SLASH-4 | §7b L198, §11 L325, L336 | No result recorded; corrected: the gate hint shares the `allowed values:` line and names the flip |
| SLASH-5, SLASH-6 | §11 L327 – 328, L337 | No result recorded; corrected: the echoes, and a component above 1 reads the color as 0 – 255 |
| SLASH-7, SLASH-8 | §12 L353 – 354 | No result recorded |
| SLASH-9 | §12 L355, §36 KC-S10 | Only `castbar` passed (KC-S10); corrected: `spells` has moved, not gone |
| SLASH-10 | §12 L358, L368, L370 | No result recorded; its cast-bar anchor half restored in this rework |
| SLASH-11 | §12 L369 | No result recorded; corrected: the `px` and color echoes |
| SLASH-12, SLASH-13 | §33 | No result recorded |
| SLASH-14 | New | The `debug` and `spells` sub-help through LibKa0s-Slash's `CommandRows` (LibKa0s v1.67.0, KickCD#36, CA-KC-01) |
| PANEL-1 | §1 L69, §2 L94, §14 L408, §36 KC-S1 | KC-S1 passed; the `/reload` half and §14's each-page-once (owed on the 2026-09-07 checklist, 4.2) did not |
| PANEL-2 | §14 L406 | No result recorded |
| PANEL-3 | §11 L343, §36 KC-S2 | KC-S2 passed; the every-tab half (§11) has no result |
| PANEL-8 – 11 | §11 L338 – 340, §20b L518 | No result recorded |
| PANEL-12 | §11 L344, §36 KC-S5 | KC-S5 passed; the Interruptible-tab half (§11) has no result |
| PANEL-13, PANEL-14, PANEL-16 | §11 L323, L329 – 330, L333, §3 L119 | No result recorded |
| PANEL-15 | §11 L324, L334 – 335 | No result recorded; corrected: the slider reads 1.25 |
| PANEL-17 | §12 L356, L362, L366 – 367, §36 KC-S7 | KC-S7 passed; the repaint and spell-list halves (§12) have no result |
| PANEL-18 | §12 L360 | No result recorded; corrected: the vendored tooltip's ASCII `->` |
| PANEL-19 – 22 | §27, §18 L469, L471 | §27 never run (2026-09-07 checklist, session 4); PANEL-20 corrected to the vendored `COMPOSE_MINOR` |
| PANEL-23 | §29, §18 L470 | §29 never run (2026-09-07 checklist, session 5) |
| PANEL-24 | §28 | Never run (2026-09-07 checklist, session 3) |
| PANEL-25 – 27 | §26 L740 – 742, §33 | No result recorded |
| PANEL-28 | §25 L690 – 697 | Never run (2026-09-07 checklist, 3.9) |
| PANEL-29 | §12 L362 | No result recorded; restored in this rework: General's and Icons' Defaults leave the other pages and the spell list alone |
| PANEL-30 | New | The Options descriptor passes `addonName` (LibKa0s v1.67.0, LibKa0s#42, CA-KC-NM) |
| PROFILE-1, PROFILE-4 – 6 | §13 L386, L389 – 391 | No result recorded |
| PROFILE-2 | §13 L377 – 383, L387 | No result recorded; corrected: copies into a scratch `SmokeCopy` |
| PROFILE-3 | §13 L388 | No result recorded; its realm and class scopes restored in this rework |
| PROFILE-7, PROFILE-8 | §19 L481 – 482, §33 L1001 – 1002 | No result recorded |
| PROFILE-9 – 14 | New | The `/kcd profile` verb |
| STATE-1 – 3, STATE-5 – 8 | §3, §5, §33 | No result recorded |
| STATE-4 | §3 L117 – 118, §20c L546 | No result recorded; corrected: Focus is turned off first |
| STATE-9 | §33 L984 – 989 | Right-click opening the menu passed (2026-09-25, X1.4); the Locked tick and the agreement with `/kcd get locked` and Lock frame have no result |
| STATE-10 | §12 L359, L361 | Never run (2026-09-07 checklist, 3.9) |
| STATE-11 – 15 | §4, §16 L448 | No result recorded |
| COMBAT-1, COMBAT-2 | §14 L404 – 405 | No result recorded |
| COMBAT-3 | §14 L407 | Never run (2026-09-07 checklist, 1.1); corrected: the Ka0s KickCD page and four subpages, not six, each covered with the window left open |
| COMBAT-5 | §20b L517 | No result recorded; rewritten: the combat cover blocks the note's link |
| COMBAT-6 – 8, COMBAT-10 | §34 step 5, §15 L425 – 426, §4 L136, §16 | No result recorded |
| COMBAT-9 | §15 L427 | Never run (2026-09-07 checklist, 1.7) |
| GRID-1, GRID-4 – 13 | §6 L166, §8, §9c, §11 L345 | No result recorded |
| GRID-2 | §6 L167 – 168 | No result recorded; corrected: the warning's text, one per unit, re-armed once the grid fits |
| GRID-3 | §6 L169 | No result recorded; corrected: the row's range is 24 – 96 |
| CAST-1 – 9, CAST-11, CAST-12 | §5 L154, §7a – 7c, §34 | No result recorded |
| CAST-10 | §34 step 4 | No result recorded; corrected: the tooltip's title is `KickCD castbar` |
| CAST-13 | §32 | NOT YET RUN since `M4-22`; corrected: the top-level `visibility` |
| CAST-14 | New | An empowered cast |
| FOCUS-1 – 5, FOCUS-8 – 12, FOCUS-14 – 19 | §20, §20a – 20d | No result recorded; FOCUS-2 corrected: Focus is turned off first and the frame unlocked, so the cast bar's placeholder shows |
| FOCUS-6, FOCUS-7 | §20b L515 – 517, §22 L625, §36 KC-S6 | KC-S6 passed; the Target-restores and link-style halves have no result |
| FOCUS-13 | §20b L524, L530 | No result recorded; corrected: a `/kcd resetall` baseline makes N = 4 |
| LABEL-1 – 5, LABEL-7 – 11, LABEL-13 – 15 | §22, §34 step 0 | No result recorded |
| LABEL-6 | §11 L346 | No result recorded; corrected: only the `/kcd get` echo carries `deg` |
| LABEL-12 | §22 L630, L635 | No result recorded; its cast-bar attach half restored in this rework |
| SPELLS-1 – 16 | §9, §10, §12 L357, L363 | No result recorded |
| DIAG-1 – 3 | §15 L416 – 418, L428 | No result recorded; corrected: the dump and ack lines as printed |
| DIAG-4 – 10, DIAG-12, DIAG-14, DIAG-15 | §15, §19 | No result recorded |
| DIAG-11 | §19 L483 | No result recorded; corrected: the `[target]` tag and the stop label |
| DIAG-13 | §19 L485 | No result recorded; corrected: the drag list's own trace lines |
| DIAG-16 | §24 L660, L668 | No result recorded; corrected: `Debug: ON` / `Debug: OFF` |
| DIAG-17 | §24 L661, L669, §35 step 9 | The cap passed (2026-09-26); the rising counter and Clear have no result |
| DIAG-18 – 22, DIAG-25 | §24, §26 | No result recorded |
| DIAG-23, DIAG-24 | §30, §26 L727 – 733 | Never run (2026-09-07 checklist, 3.4) |
| DIAG-26 | §28 | Never run (2026-09-07 checklist, 3.3); corrected: the timestamp label and the cancel line |
| DIAG-28 | §15 L422, §35 step 2 | The kept trace and the clean Copy passed (2026-09-26, KC-S2, KC-S4); the console opening, the chat line and the agreeing counts have no result |
| DIAG-29 | §35 step 3 | Not in the 2026-09-26 run |
| DIAG-30 | §35 step 4 | The full report passed (2026-09-26, KC-S5); corrected on 2026-09-30: the run now turns logging on (standard v2.71.0, DebugLogDiagnostics 2, DL-KC-03), so the header reads `Debug: ON` afterwards |
| DIAG-34 – 38 | New | Resizing the console, the copy window and the perf panel (LibKa0s v1.64.0) |
| DIAG-39 | New | The console's Diagnostics link (LibKa0s v1.64.0, DebugLog 17, DL-KC-03) |
| DIAG-40 | New | Diagnostics turns debug logging on for the session (standard v2.71.0, DebugLogDiagnostics 2, DL-KC-03) |
| DIAG-41 – 44 | New | The library's Slash refusals and Lifecycle edges in the console, the at-enable queue, Clear re-arming the gates (LibKa0s v1.65.0, DG-KC-01) |
| DIAG-45 | New | The interrupt dump's secret sentinel, now LibKa0s-Core's `NS.SECRET` (KickCD#36, CA-KC-02) |
| DEGRADED-1 – 5, DEGRADED-7, DEGRADED-12, DEGRADED-13 | §25, §34 step 9 | No result recorded |
| DEGRADED-6 | §25 L684, §31 L923 – 924 | The before-the-dump half NOT YET RUN since `M4-20` |
| DEGRADED-8 | §25 L686 | No result recorded; corrected: the perf seam's line |
| DEGRADED-10 | New | The `/kcd profile` verb |
| DEGRADED-11 | §31 | NOT YET RUN since `M4-20` |
| DEGRADED-14 | New | The stub's plain `debug` and `spells` sub-help rows (KickCD#36, CA-KC-01) |
| DEGRADED-15 | New | The degraded interrupt dump's `<secret>`, from the stub's `NS.SECRET` (KickCD#36, CA-KC-02) |
| LOC-1 – 6 | §9b | Never run (2026-09-07 checklist, session 6) |

If a check fails, capture the error from BugSack or the Lua error frame and the exact commands that led
to it, and file an issue at the tracker in [README.md](../README.md#issues-and-feature-requests).
