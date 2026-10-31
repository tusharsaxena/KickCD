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
| SLASH-1 – 14 | Slash commands | Bare `/kcd`, help, `list` / `get` / `set` / `reset` / `resetall`, value gates and clamps, verbs while disabled, the `debug` and `spells` sub-help rows (15 – 24 retired into SIM) |
| PANEL-1 – 36 | Settings panel | The tree, the Units page's band, rail and tabs, panel and slash sync, Defaults and Reset all, media dropdowns, the minimap checkbox, raw locale keys, the descriptor's folder name, item 020's layout on every page (31 – 36) |
| PROFILE-1 – 14 | Profiles | The Profiles page, switches, copies and resets, their debug lines, the `/kcd profile` verb |
| STATE-1 – 15 | Enable, lock and visibility | The master switch and stand-down, lock and drag, `resetposition`, the four visibility modes |
| COMBAT-1 – 11 | Combat | Settings refusals and the combat cover, debug dumps and diagnostics in combat, the protected-interrupt taint pass |
| GRID-1 – 21 | Icon grid | Layout, cooldown swipe and text, GCD suppression, ready glow, render gating, the charges badge, the ticker owning time, the strip's tooltip beside it, the any-cast glow on a friendly caster, the per-style glow knobs and their clamp, the glow through LibKa0s-Glow-1.0 |
| CAST-1 – 16 | Cast bar | A cast on the bar, auto-size, per-state colors, anchor modes, the drag strip, two bars at once, empowered casts, the strip's tooltip flipping at the screen edge, the primary anchor on an empty grid (17 – 18 retired into SIM) |
| FOCUS-1 – 19 | Focus tracking | The second instance, independent gating, link, unlink, copy styling, per-unit alpha and tint |
| LABEL-1 – 15 | Text label | Every label control, visibility follow, the drag strip clearing the label, rapid changes |
| SPELLS-1 – 16 | Spell lists | Spec, talent and pet rebuilds, the Spells page and `/kcd spells`, resets, racials |
| SIM-1 – 13 | Simulator | `/kcd sim`: the duration probe, refusals, the four scenarios, no strip over the grids, auto-stops, destructive refusals, stand-down, diagnostics, the step panel pinned up for the session |
| DIAG-1 – 45 | Debug and diagnostics | `/kcd debug` subcommands, the traces, the console and its chrome, the perf panel, `/kcd diagnostics`, resizing the console, copy window and perf panel, the console's Diagnostics link, diagnostics turning logging on, the library's own Slash and Lifecycle lines, state lines at enable, Clear re-arming the gates, the interrupt dump's secret sentinel |
| DEGRADED-1 – 16 | Library-absent install | `libs/LibKa0s` renamed aside: fallbacks, refusals, the shared cause clause, restore, plain sub-help rows, the interrupt dump's sentinel, the HUD on its stored picks |
| SKIN-1 – 36 | Skins | The skinning rollout: Ka0s Default's one HUD change (O2), the one-time reset per profile, the Skin tab, each skin live on the HUD, the "Use the skin's ..." boxes, the settings pages and tool surfaces on the skin, the font and texture overrides, Ignore fonts (the HUD included), EllesmereUI on and off, the copy, profiles, combat, the first-run skin picker (no eye) and its preview, Apply, gear, stand-down, combat and cross-addon queue, then LibKa0s v1.82.0: the Font outline, From skin flags and their one-time step, `/kcd skin`, HUD and window width parity, picked HUD fonts kept off the skin |
| LAYER-1 – 9 | Frame layering | Icon text over the swipe, border and glow, the cast bar's spark and text over its border, the cast bar over its grid, the label over the bar it is attached to, the drag strips on top (7 retired with the sim strip), the tool windows raising on click, the icon tooltip |
| LOC-1 – 7 | Non-English client | Spec seeding and resolution on a non-English client, the spec-key upgrade, the cast-bar name cap counted in characters |

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
- For SKIN: a **full client start** (not `/reload`) after installing this build, because the client
  loads new font and texture files only at start and a `/reload` leaves the skins' faces as fallback
  squares and their bars blank. SKIN-1 and SKIN-2 need a `KickCDDB` saved by an earlier build (back it
  up); SKIN-15 – 17 need EllesmereUI; SKIN-18 and SKIN-27 a second Ka0s addon that uses skins (Ka0s
  Loot History, or the Ka0s Skin Tester).
- For DEGRADED, first `/kcd set units.target.castbar.anchorMode FREE` (DEGRADED-12 needs it, and nothing
  can change it once the library is gone), then rename `Interface/AddOns/KickCD/libs/LibKa0s` to
  `libs/LibKa0s_off` and `/reload`; DEGRADED-13 renames it back. A folder left renamed ships a silently degraded addon.

Which checks to run for a partial change:

- **Border dropdown, or `settings/OptionsSetup.lua`'s live wiring:** PANEL-19, PANEL-23 and PANEL-30. PANEL-23 is
  the only check that loads five addons into one AceGUI registry; PANEL-19 alone cannot see its defect.
- **LibKa0s re-vendor, or a seam file** (`core/CoreSetup.lua`, `core/DebugLogSetup.lua`,
  `core/PerfSetup.lua`, `core/MediaSetup.lua`, `settings/OptionsSetup.lua`, `settings/Slash.lua`):
  DEGRADED; PANEL-3, PANEL-8 – 16 and PANEL-19 – 28; SLASH-3 – 6; DIAG-1 – 6 and DIAG-16 – 40;
  COMBAT-6 – 9 and COMBAT-11; CAST-6 – 12 and CAST-15; LABEL-2, LABEL-6 and LABEL-13 – 14; GRID-13 – 14
  and GRID-17;
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
- **Skins** (`core/SkinSetup.lua`, an `NS.Skin` / `NS.SkinResolve` / `NS.SkinColor` call site, a
  "Use the skin's ..." companion, `Database:MigrateHudSkin`, an `owner` handed to a LibKa0s factory, or
  a re-vendor that moves `libs/LibKa0s/Skin*.lua`, `OptionsAppearance.lua` or `OptionsSkinPicker.lua`):
  SKIN, then DIAG-20, DEGRADED-16, PANEL-31, PANEL-33 – 35 and LAYER-1.
- **A release or a TOC bump:** everything.

## INSTALL

- **INSTALL-1. Clean first login.** Quit WoW, delete `KickCD.lua` (and `KickCD.lua.bak`) from
  SavedVariables, confirm the character-select AddOns list shows **Ka0s KickCD** enabled, and log in →
  zero Lua errors. Result: pass (owner-marked 2026-10-10)
- **INSTALL-2. The grid seeds itself.** On that login (a fresh profile starts unlocked, so the grid
  shows) → the icon grid holds the current spec's default spells, only ones the character can cast.
  Result: pass (owner-marked 2026-10-10)
- **INSTALL-3. The store on disk.** `/reload`, then open `KickCD.lua` → `profileKeys`,
  `profiles.Default` and a seeded `spells[CLASS][specID]` block for the current spec, the spec key a
  **number** (`[262]`), never a spec name. Result: pass (owner-marked 2026-10-10)
- **INSTALL-4. An alt seeds its own spec.** Log in on a character of another class and spec → its spec's
  spells are seeded with no error. Result: pass (owner-marked 2026-10-10)
- **INSTALL-5. Settings survive `/reload`.** `/kcd unlock`, `/kcd set units.target.icons.primarySize 50`,
  `/kcd set units.target.castbar.interruptible.barColor 0.2 0.8 0.2 1`, drag the grid somewhere new,
  `/kcd lock`, `/reload` → no error; the grid is where you left it; `/kcd get locked` → `true`;
  `/kcd get units.target.icons.primarySize` → `50 px`; `/kcd get` on the bar color →
  `{0.20, 0.80, 0.20, 1.00}`. Result: pass (owner-marked 2026-10-10)
- **INSTALL-6. The schema validator is silent.** Quit fully (not `/reload`) and log in, watching chat →
  no `schema error` line. The validator (`Store.Validate`, run at panel register) prints one for a
  malformed row or a stored path the defaults cannot resolve; any line means a schema change shipped
  broken. Result: pass (owner-marked 2026-10-10)
- **INSTALL-7. The legacy unit fold.** Quit. Edit `KickCD.lua` so the active profile has top-level
  `icons`, `castbar` and `anchors` tables with a non-default `icons.primarySize`, a moved
  `anchors.icons` and a custom color, no `units` table, and `global.schemaVersion` set to `1` or
  removed. Log in → no error; the grid sits at the same place with the same look;
  `/kcd get units.target.icons.primarySize` and `/kcd get units.target.icons.cooldownTint` return your
  values, not the defaults. `/reload` and reopen the file → the top-level tables are gone,
  `units.target.{icons,castbar,anchors}` hold your values, and `global.schemaVersion` is `5` (one
  login runs every step from v1). Result: pass (owner-marked 2026-10-10)
- **INSTALL-8. The fold runs once, and Focus arrives fresh.** After INSTALL-7, `/reload` again →
  nothing moves and nothing errors. `units.focus` exists with its own defaults (`enabled = true`,
  `link = true`); the fold touched only Target. Result: pass (owner-marked 2026-10-10)
- **INSTALL-9. The label style backfill.** Quit. Edit `KickCD.lua` so `units.target.label` and
  `units.focus.label` hold only `show` and `text` (no `style`); leave `schemaVersion` alone, since this
  step is shape-driven. Log in → no error; `/kcd get units.target.label.style.font` answers and Grid →
  Text Label shows sane values; a label that was shown looks the same as before; `show` and `text` are
  as you wrote them. `/reload` and reopen the file → both units have a `style` equal to
  `LABELSTYLE_DEFAULT` in `defaults/Profile.lua`. A second `/reload` rewrites nothing. Result: pass (owner-marked 2026-10-10)
- **INSTALL-10. The minimap button draws the logo.** Look at the minimap ring → a round button wearing
  the KickCD logo, not a Blizzard ability icon and not an empty or black square (the TGA-format
  failure: `media/logos/kickcd.logo.128.tga` must be image type 2 at 32 bpp). The AddOns list shows the
  same logo beside Ka0s KickCD. Result: pass (owner-marked 2026-10-10)
- **INSTALL-11. The button's tooltip.** Hover it → `Ka0s KickCD  v<version>`, `Enabled: Yes`,
  `Locked: Yes` or `No`, `Left-click: Open settings`, `Right-click: Options menu`, and no `Test mode`
  line. Result: pass (owner-marked 2026-10-10)
- **INSTALL-12. Left-click.** Left-click the button → the settings panel opens on its landing page,
  and the lock does not change. Result: pass (owner-marked 2026-10-10)
- **INSTALL-13. The button remembers where it sits.** Drag it a quarter of the way round the ring,
  `/reload` → it comes back where you left it. Result: pass (owner-marked 2026-10-10)
- **INSTALL-14. Broker displays.** In Titan Panel, Bazooka or ElvUI's data texts add Ka0s KickCD → the
  row wears the same logo, left-click opens the panel, right-click opens the same two-entry menu, and
  the row has no value cell (it is a launcher, not a data source). Result: pass (owner-marked 2026-10-10)

## SLASH

- **SLASH-1. Bare `/kcd`.** Out of combat type `/kcd` → the settings panel opens on the Ka0s KickCD
  landing page with the tree expanded, and no help list prints. `/kcd config` does the same. Result: pass (owner-marked 2026-10-10)
- **SLASH-2. Help.** `/kcd help` → the help index; every row has the `[KCD]` banner, command names in
  yellow, descriptions in white, and no `schema error:` line. Result: pass (owner-marked 2026-10-10)
- **SLASH-3. `/kcd list`.** Type `/kcd list` → every schema row from General and the three Grid entries
  prints, each with its current value. Result: pass (owner-marked 2026-10-10)
- **SLASH-4. A gated value names its gate.** With `units.target.castbar.orientation` at `HORIZONTAL`,
  `/kcd set units.target.castbar.growDirection UP` → refused with two lines,
  `Invalid value for units.target.castbar.growDirection` and `allowed values: RIGHT, LEFT (depends on
  units.target.castbar.orientation = HORIZONTAL); flip units.target.castbar.orientation to VERTICAL
  for DOWN/UP`. Set orientation to `VERTICAL` and try `LEFT` → the same shape: `allowed values: UP,
  DOWN (depends on … = VERTICAL); flip … to HORIZONTAL for LEFT/RIGHT`. Result: pass (owner-marked 2026-10-10)
- **SLASH-5. Numbers clamp.** `/kcd set scale 99` → clamped to the row's maximum; the echo reads
  `scale = 2`. Result: pass (owner-marked 2026-10-10)
- **SLASH-6. Colors take three or four numbers.** `/kcd set units.target.castbar.interruptible.barColor
  0.5 0.5 0.5` → accepted with alpha 1, echoed `{0.50, 0.50, 0.50, 1.00}`. The same row with
  `255 128 0` → any component above 1 switches the whole color to the 0 – 255 scale, echoed
  `{1.00, 0.50, 0.00, 1.00}`; a component above 255 clamps to `1.00`. Result: pass (owner-marked 2026-10-10)
- **SLASH-7. Reset one setting.** Change `units.target.icons.primarySize`, then
  `/kcd reset units.target.icons.primarySize` → that row returns to its default; every other row and
  the spell list are untouched. Result: pass (owner-marked 2026-10-10)
- **SLASH-8. A reset color is a copy.** `/kcd reset units.target.icons.cooldownTint` on two profiles,
  then edit it on one → the other does not move. Result: pass (owner-marked 2026-10-10)
- **SLASH-9. Retired reset words answer.** `/kcd reset general`, `icons`, `castbar` and `label` → each
  says `` `/kcd reset <word>` is gone `` and points at the Defaults button that replaced it (General's,
  or the Grid entry's for the unit in the band) or `/kcd reset <path>`. `/kcd reset spells` → it has
  moved to `/kcd spells resetall`. None answers `Setting not found`. Result: pass (owner-marked 2026-10-10)
- **SLASH-10. `/kcd resetall`.** `/kcd unlock`, move both grids,
  `/kcd set units.target.castbar.anchorMode FREE` and drag the Target cast bar well away from the grid;
  change settings on several pages and edit a spell list on two specs. Then `/kcd resetall` → one line,
  `all settings + spells reset to defaults`, and no confirm prompt; every setting is back to default
  (`/kcd get enabled` → `true`, `/kcd get visibility` → `target_casting_interruptible`,
  `/kcd get units.target.castbar.anchorMode` → `PRIMARY`); every spec's spell list is re-seeded; the
  Target grid is back at y = 120 and Focus at y = 260; the profile list is untouched. Now
  `/kcd set units.target.castbar.anchorMode FREE` again → the bar sits at its default free anchor,
  `CENTER / CENTER, x = 0, y = +120`, not where you dragged it. Result: pass (owner-marked 2026-10-10)
- **SLASH-11. The defaults `resetall` lands on.** After SLASH-10, `/kcd get` each →
  `units.target.label.show` `true`, `units.target.label.style.offsetY` `12 px`,
  `units.target.label.style.color` `{1.00, 0.82, 0.00, 1.00}`, `units.target.label.style.attach`
  `icons`, `units.target.castbar.anchorPoint` `BOTTOM_LEFT`, `castbarPoint` `TOP_LEFT`,
  `anchorOffsetY` `-1 px`, `timePosition` `CENTER`, `timeOffsetY` `-20 px`, both states'
  `statusBarTexture` `Blizzard Raid Bar`; `units.focus.label.style.*` identical to Target's. Result: pass (owner-marked 2026-10-10)
- **SLASH-12. Live verbs answer while disabled.** `/kcd disable`, then: bare `/kcd` → the settings
  panel, not a refusal; `/kcd help`, `/kcd version`, `/kcd list`, `/kcd get locked`,
  `/kcd set locked true`, `/kcd spells list`, `/kcd config` and `/kcd debug` → each answers normally;
  `/kcd enable` → back on. A refusal on any of these is the failure (`slash-commands-§2`). Result: pass (owner-marked 2026-10-10)
- **SLASH-13. Feature verbs refuse while disabled.** Still disabled, `/kcd toggle`, `/kcd lock`,
  `/kcd unlock` and `/kcd resetposition` → each prints one tagged line,
  `Ka0s KickCD is disabled — enable it with /kcd enable`, and nothing else; `/kcd get locked` is
  unchanged. `/kcd enable`. Result: pass (owner-marked 2026-10-10)
- **SLASH-14. Sub-command help through the shared formatter.** `/kcd debug` → the console toggles and
  chat prints `debug subcommands`, then one row per verb (`diagnostics`, `spells`, `castbar`,
  `interrupt`, `window`, `on`, `off`, `toggle`, `events`), each with the `[KCD]` banner and a two-space
  indent: `/kcd debug <verb>` in yellow, an em dash, the description in white, the same look as a
  `/kcd help` row. `/kcd debug` again to close the console. `/kcd spells` → `spells subcommands` and its
  rows the same way, then the `(default class/spec when omitted: …)` line. `/kcd debug EVENTS` → the
  events answer (the verb is case-insensitive); `/kcd debug nosuch` → `unknown debug subcommand
  'nosuch'`, then the list again, and the console neither opens nor closes. Result: pass (owner-marked 2026-10-10)
- **SLASH-15 – 24. Retired 2026-10-23: now in [SIM](#sim).** The `sim` verb's row and refusal is SIM-3,
  the combat stop SIM-6, unlock and resetall SIM-7, `disable` SIM-8, absorbed input and diagnostics SIM-9,
  the scenarios SIM-10 – 12 and the strip SIM-12.

## PANEL

**Item 020 (settings layout, 2026-10-24) changed every page's labels and tabs.** PANEL-31 – 36
describe the layout it shipped. An older check below that names a pre-020 label (the *Grid* page,
*General > Units*, *Use same styling as Target*, *Copy styling from Target*, Icons' *Sizing* /
*Layout* / *Visual states* / *Border* tabs, Cast bar's *Icon* / *Font* / *Spell name* / *Cast time*
tabs, *Text Label*, *Horizontal justify*) means the same control under its new name and place, and
PANEL-31 – 36 govern where the two disagree. No setting's key, default or range moved: every value
you had before the update is still yours.

- **PANEL-1. The Settings tree.** Settings → AddOns → Ka0s KickCD → exactly **General · Grid ·
  Spells · Profiles**, each once, and no Icons, Cast bar or Text Label entries. Same after `/reload`.
  Result: pass (owner-marked 2026-10-10)
- **PANEL-2. The landing page.** Click Ka0s KickCD itself → the logo and the slash command list.
  Result: pass (owner-marked 2026-10-10)
- **PANEL-3. The Grid page's shape.** Open Grid → the Unit picker is a band across the top, full
  width; the rail is on the left with Icons · Cast bar · Text Label; the page opens on Icons; the
  rail's top edge is level with the top of the tab art. Click every tab on Icons → the Unit picker
  stays in the band, naming the same unit, on each one. Result: pass (owner-marked 2026-10-10)
- **PANEL-4. Only the controls scroll.** Rail → Cast bar, scroll to the bottom of Interruptible → the
  band, the rail and the tab strip stay put. Result: pass (owner-marked 2026-10-10)
- **PANEL-5. Tabs from the first frame.** `/reload`, open Grid as the session's first page → the tabs
  sit in one row right of the rail from the first frame, none under the rail. Result: pass (owner-marked 2026-10-10)
- **PANEL-6. Rail tooltips.** Hover each rail entry → a tooltip saying what the entry holds. Result: pass (owner-marked 2026-10-10)
- **PANEL-7. Each entry remembers its tab.** Cast bar → Font, then Icons, then Cast bar → opens on Font.
  Text Label → Placement, Icons, Text Label → opens on Placement. Result: pass (owner-marked 2026-10-10)
- **PANEL-8. The tab strips.** General → `Master controls | Units`; Grid → Icons → `Sizing | Layout |
  Visual states | Border | Annotations | Ready glow`; Grid → Cast bar → `General | Size and position |
  Icon | Font | Spell name | Cast time | Interruptible | Non-interruptible`; Grid → Text Label →
  `General | Placement | Font`; Spells → one tab, `Spell list`, with the spec picker and Add spell
  above it; Profiles → no strip. No tab name appears twice on a page. The table in
  [settings-panel.md](settings-panel.md) is the reference. Result: pass (owner-marked 2026-10-10)
- **PANEL-9. Headings.** Icons → Annotations shows `Icon`, `Font`, `Charges`; Cast bar → Size and
  position shows `Size`, `Position`; Interruptible and Non-interruptible each show `Bar`,
  `Background`, `Text`, `Border`. No page draws a heading that repeats its tab's name. Result: pass (owner-marked 2026-10-10)
- **PANEL-10. Class color beside every swatch.** Every color swatch has a `Use class color` checkbox
  right of it on the same line. Tick one → the surface takes a class color and the swatch stays
  enabled (its opacity still applies). Against an NPC boss the cast bar and label keep the stored color,
  as the swatch's tooltip says. Icons' swatches take the player's class on both units. Result: pass (owner-marked 2026-10-10)
- **PANEL-11. One unit selection across the Grid entries.** Pick Focus on Icons, click Cast bar and
  Text Label on the rail → both open on Focus. Flip one to Target, return to Icons → Target. `/reload`
  → Grid opens on Target (the selection is session-only). Result: pass (owner-marked 2026-10-10)
- **PANEL-12. The band retargets every tab.** Untick General → Units → "Use same styling as Target".
  On Grid → Cast bar → Font pick Focus → the page stays on Font and shows Focus's values. Click to
  Interruptible → Focus's colors (`/kcd get units.focus.castbar.interruptible.barColor` agrees), not
  Target's. Result: pass (owner-marked 2026-10-10)
- **PANEL-13. The Unit picker survives rebuilds.** On Icons switch the band Target → Focus → Target a
  few times and click every tab; tick and untick General → Units → "Use same styling as Target" and
  press "Copy styling from Target"; then, panel open, run any `/kcd set …`. Repeat on Cast bar and
  Text Label → the picker lists exactly `Target` / `Focus` throughout, and every other widget shows its
  own value. Anchor points or text positions in the picker are the stale-refresher bug. FOCUS-17 makes
  the same check after a write mid-cooldown. Result: pass (owner-marked 2026-10-10)
- **PANEL-14. The Enable box and the slash agree.** With General open, `/kcd set enabled false` → the
  "Enable KickCD" box unticks at once. Tick it → `/kcd get enabled` → `true`. Result: pass (owner-marked 2026-10-10)
- **PANEL-15. A slash write repaints the panel.** General open on Master controls, `/kcd set scale 1.25`
  → the Master scale slider moves to 1.25 and the grid rescales, no reopen. Result: pass (owner-marked 2026-10-10)
- **PANEL-16. Color picker drag.** Drag a color slider in a swatch's picker quickly → no stutter and no
  error (commits are throttled to 50 ms). Result: pass (owner-marked 2026-10-10)
- **PANEL-17. A Grid entry's Defaults.** Unlink Focus. With Target in the band, change a Cast bar and an
  Icons setting for Target and a Cast bar setting for Focus; open Cast bar and click Defaults → only
  Target's Cast bar settings reset; Target's Icons setting and Focus's Cast bar setting keep your
  values; the open page repaints; the spell list is untouched. The Defaults tooltip says it restores the
  selected unit's settings in the section on screen. Result: pass (owner-marked 2026-10-10)
- **PANEL-18. Reset all settings.** Hover General → Reset all settings → the tooltip reads *"Reset the
  current profile to its defaults — the same thing Profiles -> Reset Profile does. Your other profiles
  are not affected."* The arrow is an ASCII `->`, as the vendored string writes it. Click → a confirm
  popup; Yes → the same result as SLASH-10. Result: pass (owner-marked 2026-10-10)
- **PANEL-19. Media dropdowns list real media.** With a media addon loaded, open Icons → Border texture
  and Cooldown text font; Text Label → Font; Cast bar → Font, and Bar texture and Border texture for
  both states (eight composed dropdowns) → each lists several entries, never a lone `Default` or an
  empty list. Pick a Cast bar texture, border and font → the bar takes each live. Change Cooldown text
  font → the grid's countdown changes at once. Result: pass (owner-marked 2026-10-10)
- **PANEL-20. The composed module is the vendored one.** `/dump
  LibStub("LibKa0s-Options-1.0").MODULES.OptionsCompose` → the `COMPOSE_MINOR` in the vendored
  `libs/LibKa0s/OptionsCompose.lua`. Anything else means a foreign LibKa0s won the LibStub resolve or
  CLAUDE.md's provenance line is wrong. Result: pass (owner-marked 2026-10-10)
- **PANEL-21. A chosen face sticks.** Grid → Text Label → Font → a non-default face → the label redraws
  in it, and still does after `/reload`. Result: pass (owner-marked 2026-10-10)
- **PANEL-22. Media registered later shows up.** Enable a media addon that was off, `/reload`, reopen
  Cast bar → Bar texture → its textures are listed. An unchanged list means `Helpers.LSMValues`
  (`settings/Panel.lua`) went back to returning a table frozen at file load. Result: pass (owner-marked 2026-10-10)
- **PANEL-23. The Border dropdown, alone and with five addons.** Open Cast bar → Border style → no
  42×42 black preview tile left of the bar. Then enable KickCD, PanelMaster, AbsorbTracker,
  ConsumableMaster and MultiMeters, log in, and open each one's Border dropdown → in all five the closed
  control's left edge is flush with the controls stacked with it (no ~42px gap), and the open list still
  previews each row. Change which addon loads last (toggle addons or rename a folder), `/reload`, walk
  all five again → nothing differs. A dropdown unlike the other four, or one that changes with load
  order, is the failure. Result: pass (owner-marked 2026-10-10)
- **PANEL-24. The pooled tab strip.** On General, Grid → Icons and Grid → Cast bar, cycle every tab three
  times, ending on the first → each pass shows each tab's own label, the tab you pressed selected, the
  body under the right tab, and a band that never changes height. Result: pass (owner-marked 2026-10-10)
- **PANEL-25. JetBrains Mono is offered.** Grid → Text Label → Font → JetBrains Mono is listed with the
  other fonts. Result: pass (owner-marked 2026-10-10)
- **PANEL-26. The Minimap button checkbox.** Untick General → Master controls → Minimap button → the
  button goes at once; `/kcd get global.minimap.shown` → `false`; `/kcd get global.minimap.hide` →
  `Setting not found` (the stored key is not an alias). `/reload` → still gone, still `false`. Tick it
  → back, `true`. Hide the plugin from a broker display's own list where it offers one → the tick
  follows. Result: pass (owner-marked 2026-10-10)
- **PANEL-27. No reset shows a hidden button.** Hide the button. Reset all settings ▸ Yes → the button
  stays hidden. General's Defaults → Lock frame, General visibility and the rest reset, and the button
  **still** stays hidden (`launcher-§3`). Result: pass (owner-marked 2026-10-10)
- **PANEL-28. No raw locale keys.** Walk every page of `/kcd config`, then `/kcd debug window` and
  `/kcd perf` → every label, tooltip title, heading, button and perf step reads as English prose. A
  `SCREAMING_SNAKE_CASE` string (`STEP_START`, `PANEL_TITLE_SUFFIX`, `LIST_HEADER`) means a descriptor
  was handed `NS.L` itself; this addon once shipped a perf panel reading `Ka0s KickCDPANEL_TITLE_SUFFIX`.
  `tests/test_perfsetup.lua` guards the source; this is the only look at what rendered. Result: pass (owner-marked 2026-10-10)
- **PANEL-29. General's and Icons' Defaults stay on their own page.** Out of combat, Focus linked (the
  default): `/kcd set scale 1.25`, `/kcd set units.target.icons.primarySize 50`,
  `/kcd set units.target.castbar.timeOffsetY -30`, and on Spells drag row 3 above row 1. Open General and
  click Defaults → the Master scale slider is back at 1 and the grid returns to its normal size;
  `/kcd get units.target.icons.primarySize` → `50 px`; `/kcd get units.target.castbar.timeOffsetY` →
  `-30 px`; the Spells order is still yours. `/kcd set scale 1.25` again, then Grid → Icons with Target in
  the band → Defaults → `/kcd get units.target.icons.primarySize` → `64 px`; the Master scale slider still
  reads 1.25, `timeOffsetY` still `-30 px`, the Spells order still yours. Clean up: Grid → Cast bar →
  Defaults, General → Defaults, Spells → Defaults. Result: pass (owner-marked 2026-10-10)
- **PANEL-30. The Options descriptor names the folder.** `/kcd debug on`, then `/kcd config` and open
  every page in turn → each renders exactly as before, with no Lua error, and the console logs no
  `[Cfg] help art:` line. The descriptor now passes `addonName` (LibKa0s v1.67.0, LibKa0s#42), the folder
  name an IdList help mark builds the library's `info` art from. No page here draws an `O.IdList`, so
  `info` is not declared on the `LibKa0s icons:` line and its art does not ship (LibKa0s v1.75.0's
  icon prune); this only proves nothing broke. `tests/test_options_panel.lua` pins the field and
  that `info` is declared exactly when an `O.IdList` is drawn. `/kcd debug off`. Result: pass (owner-marked 2026-10-10)

- **PANEL-31. General after item 020.** Open General → two tabs, `Master controls` and `Skin`
  (SKIN-4), and no `Units` tab. Hover Defaults → it says it restores the Master controls tab and also resets both units'
  *Enable this unit* and Focus's *Link to Target*, which sit in the Units page's band. Hover General
  visibility → *"When KickCD's displays (icon grids, cast bars and labels) are shown. Enable KickCD
  still wins: off hides everything."*; its list reads `Always`, `In combat`, `When the tracked unit is
  casting`, `When the tracked unit is casting an interruptible spell`. Hover Lock frame → the
  library's unlocked-is-the-preview sentence (*"... this is the addon's test mode."*). Set General
  visibility to a non-default value, `/reload` → still set (`/kcd get visibility`). (Amended by
  KC-05, 2026-10-29: the Skin tab.) Result: pass (owner-marked 2026-10-30)
- **PANEL-32. The Units page's band.** The tree reads **General · Units · Spells · Profiles** (no
  *Grid*). Open Units with Target in the band → one row: `[Unit] [Enable this unit]`, the enable at the
  same height as the picker's control. Pick Focus → `[Unit] [Enable this unit] [Link to Target] [Copy
  from Target]` on the same one row, the band no taller, the picker not moved. Hover the picker → the
  tooltip ends *"Focus follows Target while Link to Target, beside this picker, is ticked."* Hover
  Defaults → it names the entry selected on the left and the unit in the band, and says the band's
  Enable this unit and Link to Target are reset by the General page's Defaults. With Focus linked,
  every entry draws its strip and the plain note *"Linked to Target. Untick Link to Target above to
  give this unit its own look."* (not a link, nothing happens on click); Icons' and Cast bar's strips
  are grayed, Text label's is live. Untick *Link to Target* → the entries fill in at once; tick it →
  they collapse. Untick *Enable this unit* on Focus → the Focus grid, bar and label go; tick → back;
  `/kcd get units.focus.enabled` agrees each time. General → Defaults → Focus enabled and linked again
  and the band shows it. Leave Focus unlinked, `/reload` → still unlinked.
  Result: pass (owner, 2026-10-24)
- **PANEL-33. Units > Icons after item 020.** Tabs `Size and layout | Appearance | Annotations | Ready
  glow`. Size and layout → `Size` (`Primary size (px)` | `Secondary size (fraction of primary)`, `Gap
  (px)` | `Icon zoom`) then `Secondary block` (`Primary icon anchor point` | `Growth direction`, `Rows`
  | `Columns`, `X offset (px)` | `Y offset (px, positive = down)`). Appearance → `States` (`Ready
  opacity` | `Cooldown opacity`, `Cooldown tint` | `Use class color`, `Suppress GCD swipe and text`)
  then `Border` (ending in `Use the skin's border`). Annotations → `Cooldown text` (`Show cooldown
  text` alone, then the font block with `Use the skin's font`),
  `Charges`, `Tooltip` (`Show tooltip on hover`). Ready glow's triggers read `When the tracked unit is
  casting ...`, its knobs say `(px)` / `(seconds)`, its last heading is still `Offset`. Hover the Icons
  rail entry → *"The interrupt icons: size and layout, appearance, annotations and ready glow."* Change
  one row on each tab, `/reload` → each value kept. (Amended by KC-05, 2026-10-29: the two `Use the
  skin's ...` boxes, SKIN-7.) Result: pass (owner-marked 2026-10-30)
- **PANEL-34. Units > Cast bar after item 020.** Tabs `General | Size and position | Text |
  Interruptible | Non-interruptible`. General → `Enable cast bar` (tooltip *"Show this unit's cast
  bar."*), `Orientation` | `Growth direction`, `Show spark`. Size and position → `Size` (`Auto-size to
  icon grid` alone, then `Cast bar width (px)` | `Cast bar height (px)`; auto-size still dims the
  overridden slider), `Position` (the X / Y offset tooltips end `(positive = right)` / `(positive =
  up)`), `Spell icon` (`Icon position` | `Icon size (px)`; Icon position's tooltip ends *"Off hides the
  icon; so does Icon size 0."*). Text → `Spell name`, `Cast time`, `Font (both texts)` with `Cast time
  color` and `Use the skin's font`. Interruptible and Non-interruptible → `Bar` (with `Use the skin's
  texture`), `Background`, `Spell name`, `Border` (with `Use the skin's border`). Hover the
  rail entry → *"The cast bar: size and position, text, and the colors for casts you can and cannot
  interrupt."* Change one row on each tab, `/reload` → each value kept. (Amended by KC-05, 2026-10-29:
  the five `Use the skin's ...` boxes, SKIN-7.) Result: pass (owner-marked 2026-10-30)
- **PANEL-35. Units > Text label after item 020.** The rail entry reads `Text label`; its Font tab
  ends in `Use the skin's font` (SKIN-7). Placement →
  `Position` (`Attach to` alone, `Attached widget anchor point` | `Label anchor point`, `X offset (px)`
  | `Y offset (px)`) then `Alignment` (`Horizontal alignment` | `Vertical alignment`, `Rotation
  (degrees)`). Hover `Attached widget anchor point` → it says *"the widget chosen in Attach to"*. With
  Focus linked and picked → Text label > General shows `Label text` above the note; rename Focus's
  label → the Focus tag on screen changes, Target's does not, Focus stays linked. Swap the two anchor
  points' values, `/reload` → kept, and the label sits where they say. (Amended by KC-05, 2026-10-29:
  the `Use the skin's font` box.) Result: pass (owner-marked 2026-10-30)
- **PANEL-36. Spells after item 020.** The picker above the list is captioned `Class and
  specialization`; picking an entry still switches the list. `/kcd reset icons`, `/kcd reset castbar`
  and `/kcd reset label` → each redirect names `Units > Icons'`, `Units > Cast bar's` and `Units > Text
  label's` Defaults button, with an ASCII `>`. Result: pass (owner, 2026-10-24)

## PROFILE

- **PROFILE-1. The Profiles page draws.** Open another addon's options page first, then Ka0s KickCD →
  Profiles → the AceDBOptions controls (current profile, New, Copy From, Delete, Reset Profile), never
  a blank page under the header. Result: pass (owner-marked 2026-10-10)
- **PROFILE-2. Create, switch, copy, delete.** Create `SmokeTest` and switch to it,
  `/kcd set units.target.icons.primarySize 40` → the grid re-draws at 40. Switch to `Default` → the
  grids re-anchor and re-skin to `Default`'s settings. Create `SmokeCopy`, switch to it, Copy From
  `SmokeTest` → the grid re-draws at 40. Switch to `Default` and Delete `SmokeCopy`; keep `SmokeTest`
  for PROFILE-9 – 14. `/reload` after each step → no error, and each result holds. Result: pass (owner-marked 2026-10-10)
- **PROFILE-3. Profile scope.** On Profiles, open Existing Profiles: besides `Default` it offers this
  character (`<Name> - <Realm>`), the realm (`<Realm>`) and the class (listed by its name). Pick each
  in turn and `/reload` after each → `KickCDDB.profileKeys["<Name> - <Realm>"]` names the pick:
  `<Name> - <Realm>`, then `<Realm>`, then the class token (`WARRIOR` on a Warrior). Switch back to
  `Default` and delete the three. Result: pass (owner-marked 2026-10-10)
- **PROFILE-4. The migration re-runs harmlessly.** Switch profiles → no error and nothing re-folds;
  `global.schemaVersion` reads `5`, account-wide, not per profile. Result: pass (owner-marked 2026-10-10)
- **PROFILE-5. Colors and font flags survive a switch.** Create a second profile, switch to it and back
  → cast bar swatches and outline dropdowns show the stored values, never blank or defaults. With
  `/kcd debug on`, no `settings migration ... failed` line. Result: pass (owner-marked 2026-10-10)
- **PROFILE-6. Spell lists are per profile.** Edit a spell list on one profile, switch → the other
  profile's list is unchanged. Result: pass (owner-marked 2026-10-10)
- **PROFILE-7. One debug line per profile event.** `/kcd debug on`, `/kcd debug window`. Switch profile
  → one `[Profile] switched to '<name>'`. Copy From another profile → one
  `[Set] copied profile '<source>' → '<active>'` and no `[Profile] switched`. Profiles → Reset Profile
  → `[Set] reset profile '<name>' to defaults` with no count. Result: pass (owner-marked 2026-10-10)
- **PROFILE-8. A switch leaves the minimap button alone.** Hide the button, switch profile → still
  hidden; switch back → still hidden. Result: pass (owner-marked 2026-10-10)
- **PROFILE-9. `/kcd profile` lists.** With `Default` and `SmokeTest` present, `/kcd profile` → a
  `Profiles` header, one row per profile sorted without regard to case, the current one suffixed
  `(current)`, then `/kcd profile <name> switches profile`. No line ends in a colon. Result: pass (owner-marked 2026-10-10)
- **PROFILE-10. `/kcd profile <name>` switches.** Switch to `Default` on the Profiles page;
  `/kcd get units.target.icons.primarySize` → `64 px` (`/kcd reset units.target.icons.primarySize` if
  not). `SmokeTest` holds 40 from PROFILE-2. `/kcd profile SmokeTest` →
  `Switched to profile 'SmokeTest'.`; the grid shrinks to 40 with no `/reload`, exactly as a switch on
  the page does, and the Profiles page shows `SmokeTest` as current on its next show.
  `/kcd profile SmokeTest` again → `Already on profile 'SmokeTest'.` and nothing changes.
  `/kcd profile Default`. Result: pass (owner-marked 2026-10-10)
- **PROFILE-11. An unknown name is refused, never created.** `/kcd profile Nope` →
  `No profile named 'Nope'.` then the list; the Profiles page has no `Nope`. `/kcd profile smoketest`
  → refused the same way, with `Did you mean 'SmokeTest'?` before the list. Result: pass (owner-marked 2026-10-10)
- **PROFILE-12. Quotes and spaces.** Create `My Raid` on the page, switch to `Default`.
  `/kcd profile "My Raid"` → switched to `My Raid`. `/kcd profile 'Default'` → switched back. Delete
  `My Raid`. Result: pass (owner-marked 2026-10-10)
- **PROFILE-13. The verb answers while disabled.** `/kcd profile SmokeTest`, `/kcd disable` (the
  master switch is per profile). `/kcd profile` → the list, not the disabled refusal.
  `/kcd profile Default` → switched, and the grids are back (`Default` is enabled).
  `/kcd profile SmokeTest` → the addon stands down again. `/kcd enable`, `/kcd profile Default`.
  Result: pass (owner-marked 2026-10-10)
- **PROFILE-14. No switch in combat.** Pull a dummy. `/kcd profile SmokeTest` →
  `Can't switch profiles in combat.` and the profile does not change. `/kcd profile` → the list still
  prints. Leave combat, delete `SmokeTest`. Result: pass (owner-marked 2026-10-10)

## STATE

- **STATE-1. The master switch hides and restores.** `/kcd lock`, `/kcd set visibility always`,
  `/kcd set enabled false` → the grids and cast bars go, whatever the visibility mode or target.
  `/kcd set enabled true` → they come back at once. Result: pass (owner-marked 2026-10-10)
- **STATE-2. Off is total.** Disabled: `/dump C_AddOns.IsAddOnLoaded("KickCD")` → true (standing down,
  not unloaded). Enter and leave combat, swap target, swap spec → nothing appears, nothing prints,
  `/kcd get locked` reports what it did before. Result: pass (owner-marked 2026-10-10)
- **STATE-3. Off unregisters listeners.** Disabled, `/kcd debug on`, enter combat → no
  `[Combat] entered` line in the console. Result: pass (owner-marked 2026-10-10)
- **STATE-4. Enable rebuilds from current state.** `/kcd enable`,
  `/kcd set units.focus.enabled false`, `/kcd disable`. While off, `/kcd set units.focus.enabled true`,
  target and focus hostile casters, then `/kcd enable` → every unit whose `units.<unit>.enabled` is
  true comes back in the same turn, including Focus (enabled while the addon was off), with the current
  casts and cooldowns shown, no `/reload`. Result: pass (owner-marked 2026-10-10)
- **STATE-5. The minimap button while off.** Disabled, hover the button → `Enabled: No` and the same
  two hints. Left-click → the settings panel, nothing printed. Right-click → Enabled unticked and
  clickable; Locked reads *Locked (enable the addon first)*, grayed, and clicking it does nothing
  (`/kcd get locked` unchanged). Tick Enabled → back on, with the line `/kcd enable` prints. Result: pass (owner-marked 2026-10-10)
- **STATE-6. A fresh profile starts unlocked.** On a new profile `/kcd get locked` → `false`, and the
  grid drags with no `/kcd unlock`. Result: pass (owner-marked 2026-10-10)
- **STATE-7. Lock and unlock.** `/kcd set units.target.castbar.anchorMode FREE`, `/kcd unlock` → the
  grid and the cast bar both drag. `/kcd lock` → neither does, and both drag strips go. Result: pass (owner-marked 2026-10-10)
- **STATE-8. `/kcd toggle` and the Lock frame box.** Panel open on General → Master controls,
  `/kcd toggle` twice → the lock flips each time and Lock frame follows live. Result: pass (owner-marked 2026-10-10)
- **STATE-9. The launcher menu.** Right-click the button → a menu titled Ka0s KickCD with exactly two
  ticks, Enabled (ticked) and Locked. Untick Locked → the grids and the cast bar placeholder appear, the
  grid drags, the menu closes, and chat prints the *icon grid unlocked* line `/kcd toggle` prints.
  Right-click → Locked unticked. Tick it → locked. `/kcd get locked` and General → Lock frame agree at
  each step. Result: pass (owner-marked 2026-10-10)
- **STATE-10. `resetposition`.** Drag both grids away, `/kcd resetposition` → Target's grid at
  `CENTER / CENTER, x = 0, y = +120` (above center) and Focus's at `y = +260`, exactly; a free cast bar
  and every setting untouched. Drag them away again, General → Reset position → the same. Result: pass (owner-marked 2026-10-10)
- **STATE-11. Unlocked bypasses visibility.** `/kcd unlock` with any visibility mode and no target →
  both pieces show at full alpha, so they can be placed. Run STATE-12 – 15 locked. Result: pass (owner-marked 2026-10-10)
- **STATE-12. Visibility `always`.** No target, no combat → both pieces visible. Result: pass (owner-marked 2026-10-10)
- **STATE-13. Visibility `in_combat`.** No target → hidden. Auto-attack a dummy → both appear on combat
  start; leave combat → both hide. Result: pass (owner-marked 2026-10-10)
- **STATE-14. Visibility `target_casting`.** Target a mob that is not casting → hidden. It starts a cast
  or channel → both appear; the cast ends or is canceled → both hide. Result: pass (owner-marked 2026-10-10)
- **STATE-15. Visibility `target_casting_interruptible` (the default).** Target a hostile in an
  uninterruptible cast → hidden. Switch to one casting interruptibly → both appear. A cast that flips
  to uninterruptible mid-cast (some bosses) → the cast bar fades to alpha 0 but stays shown (an alpha
  curve, not `:Hide()`). An occasional leak at cast start is a known issue (WoW's `notInterruptible` is
  unreliable then), tracked on the issue tracker. Result: pass (owner-marked 2026-10-10)

## COMBAT

- **COMBAT-1. `/kcd config` in combat.** → one `[KCD]` line saying settings cannot open during combat,
  and no panel. Result: pass (owner-marked 2026-10-10)
- **COMBAT-2. `/kcd set` in combat.** `/kcd set units.target.icons.primarySize 50` in combat → applies
  live. Result: pass (owner-marked 2026-10-10)
- **COMBAT-3. The AddOns sidebar in combat.** In combat, Game Menu → Options → AddOns → Ka0s KickCD,
  then General, Grid, Spells and Profiles in turn → each page shows under the cover reading "Settings
  are locked during combat.", nothing on it can be clicked, and the Settings window stays open. Chat
  prints one gray `settings are locked during combat — changes are refused until it ends` line on the
  first page and none on the others (once per combat). Leave combat → the page on screen draws
  normally. This path skips `OpenOptionsPanel` and is guarded only by the library's page cover, so run
  all five pages, not a sample. Result: pass (owner-marked 2026-10-10)
- **COMBAT-4. The combat cover.** Open Grid, enter combat, click a rail entry → the whole page, rail
  included, is under the cover reading "Settings are locked during combat."; nothing changes; one gray
  locked line prints. After combat the page draws normally on the entry you were on. Result: pass (owner-marked 2026-10-10)
- **COMBAT-5. The linked note under the cover.** Open Grid with a linked Focus picked in the band, so
  the Linked-to-Target note shows, then pull a dummy → the cover goes over the note as well. Click the
  note's link → nothing happens: the page does not switch to General and no `cannot open settings
  during combat` line prints (the link's own combat refusal sits under the cover). Result: pass (owner-marked 2026-10-10)
- **COMBAT-6. The drag strip's right-click in combat.** Unlocked, Free anchor mode, in combat,
  right-click the cast bar's strip → the gray refusal line and no panel. Result: pass (owner-marked 2026-10-10)
- **COMBAT-7. Debug dumps in combat.** In combat on a hostile caster, run every `/kcd debug`
  subcommand → no Lua error. Result: pass (owner-marked 2026-10-10)
- **COMBAT-8. `/kcd debug interrupt` on a secret cast.** Target a hostile mid-cast of a protected
  interrupt → `notInterruptible` reads `<secret>`, never a coerced value, and the gate decision
  matches what the current visibility mode shows. Result: pass (owner-marked 2026-10-10)
- **COMBAT-9. `/kcd debug castbar` on a secret cast.** Same target → the
  `current.notInterruptible: type=…, isSecret=true` line is always followed by a `secret-tainted; …`
  line: that the state comes from `C_CurveUtil.EvaluateColorValueFromBoolean` where it exists, that it
  is unavailable where it does not. On live Retail only the first half is observable; a pre-12.0 or
  Classic-flavor build shows the second. A secret field with nothing after it is the failure. Result: pass (owner-marked 2026-10-10)
- **COMBAT-10. The protected-interrupt taint pass.** Run
  `/kcd set visibility target_casting_interruptible` (the mode that runs the interruptible-alpha gate
  on a secret `notInterruptible`), then in combat on a hostile interruptible caster: interrupt it, press the
  interrupt again on cooldown, five or more times over a long cast or channel; with that mode still set,
  swap between a hostile interruptible caster, a hostile uninterruptible caster, a friendly NPC and no
  target → zero Lua errors (the usual signature is `cannot perform arithmetic on a secret value` or
  `attempt to format a secret value` as the interrupt fires), and the interrupt icon's swipe and text
  keep working. Result: pass (owner-marked 2026-10-10)
- **COMBAT-11. Diagnostics in combat and in a restricted instance.** `/kcd diagnostics` in combat with
  a hostile caster targeted mid-cast and a second on focus, then again in a Mythic+ key or raid
  encounter → no Lua error; the cast record reads as types; `notInterruptible` in the `interrupt` lines
  reads `<secret>` where the client hides it; charges may read `<secret>`. Result: pass (owner-marked 2026-10-10)

## GRID

- **GRID-1. Layout.** With four or more spells enabled, walk `units.target.icons.anchor` through all 13
  tokens, and for each set `units.target.icons.secondaryGrow` to two values valid on its axis → the
  secondary block lays out from the primary icon's named anchor in that direction, no overlap. Result: pass (owner-marked 2026-10-10)
- **GRID-2. The overflow warning.** `/kcd set units.focus.enabled false` (each unit warns for its own
  grid). Set `units.target.icons.secondaryRows` × `secondaryCols` below the enabled spell count minus
  one → one line, `dropped <n> icon(s) past the <rows × cols>-slot grid for <CLASS>/<specID> — bump
  rows*cols or remove spells`. Change `primarySize` → no second line. Set another capacity that still
  does not fit → the line prints again for it. Raise it until everything fits, then drop it below
  again → the line prints again (fitting re-arms it). `/kcd set units.focus.enabled true`. Result: pass (owner-marked 2026-10-10)
- **GRID-3. Icon size is live.** `units.target.icons.primarySize` from 24 to 96 (the row's range) → the
  grid resizes with no `/reload`. Result: pass (owner-marked 2026-10-10)
- **GRID-4. A cooldown starts.** `visibility = always`, cast Pummel at a dummy → its icon desaturates at
  once with a swipe, and with Annotations → Show cooldown text on, a countdown. Result: pass (owner-marked 2026-10-10)
- **GRID-5. The GCD is not a cooldown.** While Pummel cools down, cast an on-GCD spell → Pummel's
  swipe is not restarted or touched by the GCD. Result: pass (owner-marked 2026-10-10)
- **GRID-6. Two glow triggers, independent.** Primary glow trigger `target_casting_interruptible`,
  secondary `target_casting` → the primary glows only on hostile interruptible casts, the secondaries on
  any hostile cast. Result: pass (owner-marked 2026-10-10)
- **GRID-7. Ready again.** When Pummel comes off cooldown → the icon re-saturates and the swipe goes, with
  no `0.0` stuck on the text. Result: pass (owner-marked 2026-10-10)
- **GRID-8. The swipe runs smoothly.** Put a spell on a 30 s+ cooldown → the swipe animates without a
  stutter or restart and the countdown ticks continuously. Result: pass (owner-marked 2026-10-10)
- **GRID-9. Cooldown visuals hold to the end.** Same cooldown → the icon keeps the cooldown alpha and
  tint for all of it, final second included, and turns ready only when castable. Brightening early is
  the regression (the curves read the total length, not the remaining time). Result: pass (owner-marked 2026-10-10)
- **GRID-10. Changes land mid-cooldown.** While it runs, change glow type and glow color, and toggle
  cooldown text and the charges badge → each applies at once. Result: pass (owner-marked 2026-10-10)
- **GRID-11. Glow follows the target mid-cooldown.** With the spell still cooling and a
  `target_casting` or `target_casting_interruptible` trigger, the target starts and stops casting → the
  glow follows it. Result: pass (owner-marked 2026-10-10)
- **GRID-12. Charges in combat.** Spend and recharge a charged spell (a talented Mind Freeze) in combat
  → the badge keeps counting, though the count is secret. Result: pass (owner-marked 2026-10-10)
- **GRID-13. The charges badge inset.** Annotations → Show charges on a charged spell. At the defaults
  (X `-2`, Y `2`) → flush inside the bottom-right corner. X `-20` → 18 px left; Y `20` → 18 px up.
  `/kcd set units.target.icons.chargesOffsetX 900` → clamps to `32 px`, badge at the slider maximum.
  Result: pass (owner-marked 2026-10-10)
- **GRID-14. Grid strips carry no close mark.** `/kcd unlock` → the grid strips and cast bar strips
  have the `?` mark and no X (KickCD does not adopt the strip's close option, owner ruling X-03).
  Result: pass (owner-marked 2026-10-10)
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
- **GRID-17. The grid strip's tooltip sits beside the strip (TP-KC-01).** `/kcd unlock`, hover the
  Target grid's strip, then its `?` → each time the tooltip opens to the strip's RIGHT, its top level with
  the strip's top, not above the strip and not at the cursor; it covers neither the unit label nor the
  Focus grid above. Drag the grid until its strip nearly touches the right edge of the screen and hover
  again → the tooltip opens to the strip's LEFT instead. `/kcd set scale 1.5` and repeat both → the same
  two sides, fully on screen (the grid strip takes the master scale, so the flip is judged in screen
  pixels). Result: pass (owner-marked 2026-10-10)
- **GRID-18. `target_casting` glows on a friendly cast too (KC-03).** `/kcd set visibility always`,
  `/kcd set units.target.icons.primaryGlowTrigger target_casting`, an interrupt off cooldown. Target a
  friendly player and have them hard-cast (a heal, a hearthstone) → the primary icon starts glowing
  when the cast starts and stops when it ends or is canceled, every time, not stuck on or off. Set
  the trigger to `target_casting_interruptible` and repeat → no glow on the friendly cast. With
  `/kcd diagnostics`, the `IconGrid` section's `gate` line ends `any=true` while the friendly cast
  runs. Result: pass (owner-marked 2026-10-10)
- **GRID-19. The glow's style knobs apply at once, and only their own style's are live.** Grid → Icons →
  Ready glow, primary trigger `always`, an interrupt off cooldown, style `Pixel border` → under
  *Pixel border* and *Offset* the primary rows are live and every other style's primary rows are dimmed;
  the secondary column follows the secondary trigger and style on its own. Move Primary lines to `3`,
  thickness to `5`, length to `6` and untick Primary dark border → the running glow redraws with three
  thick short lines and no dark edge as each control moves, with no `/reload`. Switch the style to
  `Auto cast sparkles` → the *Pixel border* rows dim and the *Auto cast sparkles* rows wake; Primary
  particles `10`, scale `2` → more and bigger sparkles at once. `Button (rotating rays)` → the offsets
  dim; Primary frequency `1` → the rays turn faster. `Proc (flipbook)` → Primary duration `3` slows the
  loop; untick Primary start animation, then flip the trigger to `never` and back → the glow returns
  with no opening burst. Primary trigger `never` → the primary style and every primary knob dim, and
  the primary glow color stays live. Defaults on the page → every knob back to the defaults in
  `docs/schema.md`, and the glow looks as it did before the knobs (one-pixel lines with the dark edge). Result: pass (owner-marked 2026-10-23)
- **GRID-20. A hand-set glow knob is clamped.** `/kcd set units.target.icons.primaryGlowPixelLines 900`
  → clamps to `20`, the slider's maximum, as GRID-13's offset does. Edit
  `primaryGlowPixelLines = 900` and `primaryGlowPixelThickness = -5` into the SavedVariables file
  while logged out, log in with a pixel-style primary glow showing → the glow draws twenty one-pixel
  lines and no Lua error. Result: pass (owner-marked 2026-10-23)
- **GRID-21. The ready glow draws through LibKa0s-Glow-1.0 as it did before.** Grid → Icons → Ready
  glow, primary trigger `always`, an interrupt off cooldown. Cycle the primary style through
  `Button (rotating rays)`, `Proc (flipbook)`, `Pixel border` and `Auto cast sparkles`, then do the
  same for the secondary slot → each style draws as it did before the change, the proc opening burst
  plays once per start, and switching style leaves no stale glow of the previous style. With a
  pixel-style primary glow showing, move Primary lines, frequency and thickness and untick Primary
  dark border → the running glow restarts at once with the new values (GRID-19 again), and
  `/kcd set units.target.icons.primaryGlowPixelLines 900` still clamps to `20` (GRID-20). Primary
  trigger `target_casting_interruptible`, target a hostile caster → the glow lights only on
  interruptible casts; an uninterruptible cast neither glows nor shows. Rename
  `libs/LibCustomGlow-1.0` aside, `/reload`, `/kcd debug on` → one
  `[Init] LibCustomGlow-1.0 absent; no icon glows` line and no Lua error with a ready interrupt;
  restore the folder. Result: pass (owner-marked 2026-10-23)

## CAST

- **CAST-1. A cast on the bar.** Target a hostile caster mid-cast → the bar appears at cast start, fills
  over the cast's duration and goes at cast end; the spell name and remaining time draw and the spark
  moves along the fill. Result: pass (owner-marked 2026-10-10)
- **CAST-2. Auto-size tracks the visible grid.** `anchorMode PRIMARY`, `autoSize true`, `orientation
  HORIZONTAL`. Disable spells (`/kcd spells disable <id>`) and re-add them, and set `secondaryCols` 4
  then 2 → the bar's long side matches the grid's visible width, not its `rows × cols` capacity,
  shrinking and growing in place; the other side stays at `castbar.width` / `height`. Same with
  `VERTICAL` and height. Result: pass (owner-marked 2026-10-10)
- **CAST-3. Orientation resets grow direction.** Switch `orientation` → `growDirection` resets to that
  axis's default (`HORIZONTAL` → `RIGHT`, `VERTICAL` → `UP`). Result: pass (owner-marked 2026-10-10)
- **CAST-4. Per-state appearance.** Interruptible bar color `0.2 0.8 0.2 1`, uninterruptible
  `0.8 0.2 0.2 1` → an interruptible cast draws green with its border style and font; an
  uninterruptible one draws red, or fades to 0 under `target_casting_interruptible`. Result: pass (owner-marked 2026-10-10)
- **CAST-5. A mid-cast flip.** A boss or trash spell that flips interruptibility mid-cast
  (`UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE`) → the bar switches state and the glow follows,
  with no Lua error. Result: pass (owner-marked 2026-10-10)
- **CAST-6. Primary anchor mode.** `anchorMode PRIMARY`, unlocked → no strip on the cast bar, and the
  bar cannot be dragged by the strip, the mark or its body; it follows the grid when the grid is dragged.
  Result: pass (owner-marked 2026-10-10)
- **CAST-7. The strip names its unit.** `anchorMode FREE`, `/kcd unlock`, a cast bar on screen → a dark
  strip with a gold label directly above the bar reading **Target castbar** (and **Focus castbar** on
  the focus bar). Result: pass (owner-marked 2026-10-10)
- **CAST-8. Drag the strip.** Drag it → the bar moves; release, `/kcd lock`, `/reload` → the position
  sticks. Result: pass (owner-marked 2026-10-10)
- **CAST-9. The `?` mark drags too.** Drag the `?` on the strip → the bar moves. Result: pass (owner-marked 2026-10-10)
- **CAST-10. Strip tooltips.** Hover the strip, then the `?` → each shows the same tooltip, titled
  `KickCD castbar` and reading `Drag to move. Right-click for settings.` (prose, no locale key), in the
  same place beside the strip (CAST-15); the `?` brightens under the cursor. Result: pass (owner-marked 2026-10-10)
- **CAST-11. Right-click opens settings.** Out of combat, right-click the strip → the settings panel
  opens. Result: pass (owner-marked 2026-10-10)
- **CAST-12. Back to Free without leaving the panel.** From PRIMARY set Free again in the panel → the strip
  comes back (`ApplyLock` does not run on every route that changes `anchorMode`). Result: pass (owner-marked 2026-10-10)
- **CAST-13. Two bars at once.** `units.target.castbar.enabled` and `units.focus.castbar.enabled` true,
  `/kcd lock`, `/kcd set visibility always`. Target one hostile caster and focus another, both
  mid-cast → both bars animate at the same time and independently; each unit's second cast (no
  retarget) animates like its first; swap target and focus and repeat; names and times track on both
  and neither shows the other's spell. One frozen bar, or both showing the same fill, is a mis-bound
  `onUpdateScript`; a Lua error naming `Castbar.lua` and a nil `onUpdateScript` is too. Result: pass (owner-marked 2026-10-10)
- **CAST-14. An empowered cast.** Duel an Evoker. Target (then focus) them first, and only then have
  them start Fire Breath or Eternity Surge → the bar shows the empower, the `*_casting` visibility and glow follow
  it at once, and the bar clears on its release. A blank bar or a late glow means the
  `UNIT_SPELLCAST_EMPOWER_*` routes are missing ([midnight-quirks.md](midnight-quirks.md)). Result: pass (owner-marked 2026-10-10)
- **CAST-15. The cast bar strip's tooltip sits beside the strip, and flips at the edge (TP-KC-01).**
  `anchorMode FREE`, `/kcd unlock`, a cast bar on screen. Hover its strip → the tooltip opens to the
  strip's RIGHT, top edges level, not at the cursor. Drag the bar until the strip's right end is within a
  tooltip's width of the screen's right edge and hover again → the tooltip opens to the strip's LEFT, fully
  on screen. Result: pass (owner-marked 2026-10-10)
- **CAST-16. An empty grid hands the primary anchor to the grid frame (KC-01).** `anchorMode PRIMARY`,
  `/kcd set visibility always`, `/kcd lock`. Disable every spell on the current spec's list
  (`/kcd spells disable <id>` for each) → the grid draws no icons. Target a hostile caster → the bar
  draws at the grid's position (anchored to the grid frame), not hidden and not stranded where the old
  first icon sat; drag the grid while unlocked and the bar follows it. Re-enable one spell → the bar
  re-anchors under that icon. Result: pass (owner-marked 2026-10-10)
- **CAST-17. Retired 2026-10-23: now SIM-1** (the duration constructor probe).
- **CAST-18. Retired 2026-10-23: now SIM-2** (no change from the Compat unit readers).

## FOCUS

- **FOCUS-1. Focus defaults.** On a fresh profile → Focus is enabled and linked to Target, its grid at
  y = 260 above Target's (y = 120), with a small gap between Focus's cast timer and the Target label.
  Result: pass (owner-marked 2026-10-10)
- **FOCUS-2. Enabling Focus builds it live.** `/kcd set units.focus.enabled false`, `/reload` (so no
  Focus frames exist yet), `/kcd unlock` (a locked cast bar stays hidden until a real cast), then
  `/kcd set units.focus.enabled true` → a second grid (`KickCDIconGridFocus`) and the cast bar's
  placeholder (`KickCDCastbarFocus`) appear with no further `/reload`, the grid tracking the same spells
  as Target. Result: pass (owner-marked 2026-10-10)
- **FOCUS-3. Independent gating.** `/kcd lock`, `/kcd set visibility target_casting_interruptible`, a
  hostile target and a different hostile focus. Only the target casts → only the Target pair shows; only the focus casts → only the
  Focus pair; both cast → both. Result: pass (owner-marked 2026-10-10)
- **FOCUS-4. Disabling Focus.** `/kcd set units.focus.enabled false` → the Focus grid and bar go at once;
  Target is untouched. Result: pass (owner-marked 2026-10-10)
- **FOCUS-5. Enabling mid-cast.** Focus disabled, the focus mob mid-cast, `/kcd set units.focus.enabled
  true` → the Focus bar shows at once at the cast's current progress. Disable, let a new cast start,
  enable again → the same, no stale state. Result: pass (owner-marked 2026-10-10)
- **FOCUS-6. A linked Focus page.** Pick Focus in the band on each Grid entry → the full tab strip,
  every tab grayed and not clickable, and only the note *"Linked to Target. Untick 'Use same styling as
  Target' on the General page's Units tab to give Focus its own."* The page keeps its shape; picking
  Target restores color and clicks. Result: pass (owner-marked 2026-10-10)
- **FOCUS-7. Retired by item 020.** The linked-Focus note is plain text now and links nowhere; the tick
  it names is in the Units page's band. PANEL-32 checks the note.
- **FOCUS-8. Linked Focus mirrors Target live.** Change Target's `primarySize` → the linked Focus grid
  matches at once. Result: pass (owner-marked 2026-10-10)
- **FOCUS-9. Unlinking.** Untick General → Units → "Use same styling as Target", then open Grid → Icons
  on Focus → the strip and rows appear, seeded with Target's last-copied values (or defaults). The page
  was hidden when you unticked; it repaints on its next show. Result: pass (owner-marked 2026-10-10)
- **FOCUS-10. Unlinked edits stay on Focus.** Change `units.focus.icons.primarySize` → Target's grid does
  not change. Result: pass (owner-marked 2026-10-10)
- **FOCUS-11. Relinking reverts live.** Re-tick the box → Focus mirrors Target again at once and Icons
  collapses to the note under its grayed strip; your Focus values stop applying. Result: pass (owner-marked 2026-10-10)
- **FOCUS-12. The link controls.** General → Units shows `[Use same styling as Target] [Copy styling
  from Target]` on one line, the button in the right half, and neither control appears anywhere else.
  Result: pass (owner-marked 2026-10-10)
- **FOCUS-13. Copy styling from Target.** `/kcd resetall` (Focus linked, every styling row equal to
  Target's), then `/kcd set units.target.castbar.orientation VERTICAL`,
  `/kcd set units.target.castbar.growDirection DOWN`, `/kcd set units.target.icons.primarySize 50` and
  `/kcd debug on`; click General → Units → Copy styling from Target → every Focus `icons`, `castbar`,
  `label.style` row and `label.show` takes Target's value, `link` becomes false, Focus's bar is vertical
  and still grows Down (orientation's own reset to Up must not win). The console shows one
  `[Set] copy target→focus: 4 rows` line and no per-row `[Set] units.focus.…` lines: N counts the rows
  the copy changed, here the three Target rows you moved off their defaults plus the link. Then change
  Target → Focus does not follow (a one-time copy). Result: pass (owner-marked 2026-10-10)
- **FOCUS-14. The link from the slash, and Defaults.** `/kcd set units.focus.link false` → the tick
  clears on an open General page and the Grid entries grow their rows; `true` collapses them. With
  Focus unlinked, General's Defaults re-links it. Result: pass (owner-marked 2026-10-10)
- **FOCUS-15. Position and identity stay per unit.** Linked or not, drag the Focus grid → Target's does
  not move; Focus's label text stays its own. Result: pass (owner-marked 2026-10-10)
- **FOCUS-16. Unlinked Focus has its own alpha and tint.** Unlink first, then `visibility always`, both
  units enabled, and `/kcd set units.target.icons.cooldownAlpha 0.20`,
  `units.target.icons.cooldownTint 1 0.3 0.3 1`, `units.focus.icons.cooldownAlpha 0.90`,
  `units.focus.icons.cooldownTint 0.3 0.3 1 1`; unlock, part the grids, lock. Cast a real interrupt
  (cooldown over ~1.6 s) → Target's icon heavily dimmed and red, Focus's nearly bright and blue. Identical
  grids mean Focus inherits Target's curves. (While only the GCD runs both look ready; that is correct.)
  Result: pass (owner-marked 2026-10-10)
- **FOCUS-17. A Focus alpha change mid-cooldown.** With the settings panel open on Grid → Icons,
  mid-cooldown `/kcd set units.focus.icons.cooldownAlpha 0.40` → Focus changes while the cooldown runs;
  Target does not. Then, panel still open, pick Target and Focus in the band and click every tab on
  Icons, Cast bar and Text Label → the Unit picker lists exactly `Target` / `Focus` throughout (anchor
  points or text positions there are a stale refresher that survived the rebuild). Result: pass (owner-marked 2026-10-10)
- **FOCUS-18. An unrelated edit leaves the curves alone.** Mid-cooldown, change Target's Border style
  (Icons → Border) to a visibly different border → Target's edge changes and neither grid's alpha or
  tint shifts. Result: pass (owner-marked 2026-10-10)
- **FOCUS-19. Relinking mid-cooldown reverts the curves.** With FOCUS-16's values still set (Target
  0.20 and red, Focus 0.40 and blue), cast the interrupt again if its cooldown has ended, and while it
  runs tick General → Units → "Use same styling as Target" → Focus's icon takes Target's dim red at
  once, mid-cooldown, with no `/reload`. Clean up: Icons → Defaults with Target in the band; untick the
  box, Icons → Defaults with Focus in the band, and tick the box again. Result: pass (owner-marked 2026-10-10)

## LABEL

- **LABEL-1. The default label.** Grid → Text Label, Target → Show label is on and "Target" sits just
  above the grid. Untick → only the label goes, grid and bar stay; tick → back. General carries no
  label controls. Result: pass (owner-marked 2026-10-10)
- **LABEL-2. Label text.** Type "MainTank" in the Label text box and press Enter → the label changes at
  once. Result: pass (owner-marked 2026-10-10)
- **LABEL-3. Attach to.** Switch Attach to between `castbar` and `icons` → the label re-anchors; drag
  the grid → it follows. Result: pass (owner-marked 2026-10-10)
- **LABEL-4. Anchor pairs.** Walk Label anchor point and Attach point through several pairs (`TOP` /
  `BOTTOM`, `LEFT` / `RIGHT`) and vary the X and Y offsets → the label moves to match, and no pick
  raises an error. Result: pass (owner-marked 2026-10-10)
- **LABEL-5. Justify.** Step Horizontal and Vertical justify with multi-word text → the alignment moves.
  Result: pass (owner-marked 2026-10-10)
- **LABEL-6. Rotation.** Set Rotation to 45, then -90 → the label turns, and is upright at 0. At 45 the
  control is labeled `Rotation (degrees)` and `/kcd get units.target.label.style.rotation` echoes
  `45 deg`; neither shows an empty box where a degree sign used to be. Result: pass (owner-marked 2026-10-10)
- **LABEL-7. Font.** Change Font, Font size and Font flags → the label redraws each time. Result: pass (owner-marked 2026-10-10)
- **LABEL-8. Label color.** Pick a bright color → the text changes; switch Attach to → the color stays.
  Result: pass (owner-marked 2026-10-10)
- **LABEL-9. An unlinked Focus label.** Unlink Focus, set its text to "Kick this" and change its rotation
  or color → Target's label is unaffected; both show their own text and style; positions are
  independent. Relink → Focus's style mirrors Target's again and its text stays "Kick this". Result: pass (owner-marked 2026-10-10)
- **LABEL-10. Focus off hides its label.** Both labels shown, `/kcd set units.focus.enabled false` →
  the Focus label goes at once, Target's stays; enable → back. Result: pass (owner-marked 2026-10-10)
- **LABEL-11. The label follows General visibility.** `visibility target_casting`, Show label on,
  Attach to `castbar` → target not casting: grid, bar and label all hidden; cast starts: all three
  appear; cast stops: all hide. Same with Attach to `icons`. Result: pass (owner-marked 2026-10-10)
- **LABEL-12. Always means the label shows.** `visibility always`, Show label on, target not casting.
  Attach to `icons` → the label shows above the grid. Attach to `castbar` → the label still shows,
  placed against the hidden cast bar: it follows the grid's visibility, never the bar's own hiding
  when nothing is cast (a label parented to the bar used to vanish here). Result: pass (owner-marked 2026-10-10)
- **LABEL-13. The strip clears the label.** `/kcd unlock` with the label attached to the icons → the grid
  strip sits above the label text. Label off → the strip drops to the grid's top. Attach the label to the
  cast bar, or anchor it to the grid's bottom → the grid strip returns to the grid's top and the cast
  bar's strip clears the label instead. Result: pass (owner-marked 2026-10-10)
- **LABEL-14. The strip clears it straight after `/reload`.** Unlocked, `/reload`, no lock toggle →
  both strips ("Ka0s KickCD — Target" / "— Focus") sit fully above their labels with a small gap.
  Untick Show label on each unit (unlink Focus first) → that strip drops to just above its icons; tick
  → it climbs back. Font size 30 → the strip still clears it. `/kcd lock` hides both. Result: pass (owner-marked 2026-10-10)
- **LABEL-15. Rapid changes raise nothing.** Panel open on Text Label, flip Attach to between
  `castbar` and `icons` ten times fast; drag the X offset, Y offset and Rotation sliders end to end
  quickly several times; then cycle `/kcd set visibility` through `always`, `in_combat`,
  `target_casting` and `target_casting_interruptible` back to back → no Lua error at any point, and the
  label ends where the final values put it. Result: pass (owner-marked 2026-10-10)

## SPELLS

- **SPELLS-1. A spec swap rebuilds.** Switch spec → the watched list and the grid rebuild for the new
  spec's spells, no error. Result: pass (owner-marked 2026-10-10)
- **SPELLS-2. A talent swap rebuilds.** Swap a choice node that replaces an interrupt-adjacent spell →
  the list rebuilds at once, no spec swap needed. Result: pass (owner-marked 2026-10-10)
- **SPELLS-3. An open Spells page follows the spec.** With Settings → Spells open, switch spec → the
  spec dropdown moves to the new spec and its rows redraw. Result: pass (owner-marked 2026-10-10)
- **SPELLS-4. Pets.** On a Hunter, `/cast Call Pet 1` → the pet's interrupt joins the grid. Dismiss it
  → it leaves with no stale icon, and `/kcd debug spells` no longer lists it. Result: pass (owner-marked 2026-10-10)
- **SPELLS-5. The Cooldown Manager gate.** On the active spec, add a spell not tracked by the Cooldown
  Manager (on the page and with `/kcd spells add <id>`) → `Spell <name> (#<id>) is not tracked by the
  Blizzard Cooldown Manager for this specialization.`, and nothing is added. A tracked id is added.
  Result: pass (owner-marked 2026-10-10)
- **SPELLS-6. Names with spaces.** As a Shaman, `/kcd spells add Wind Shear` → Wind Shear is added, the
  name never split. Result: pass (owner-marked 2026-10-10)
- **SPELLS-7. Unknown class or spec.** `/kcd spells add <id> WARLORD 99999` → `Unknown class WARLORD`;
  `/kcd spells add <id> <CLASS> 99999` → `Unknown spec 99999 for <CLASS>`. Neither writes to
  `KickCDDB`. Result: pass (owner-marked 2026-10-10)
- **SPELLS-8. A spec swap with the page closed.** Close Settings, switch spec, open Spells → the Add box
  accepts only the new spec's Cooldown Manager spells. Result: pass (owner-marked 2026-10-10)
- **SPELLS-9. Editing another spec.** Pick another class and spec in the page's dropdown and add any
  valid spell id → accepted (the lenient path). Result: pass (owner-marked 2026-10-10)
- **SPELLS-10. The subcommands, live.** Page open, run `/kcd spells list`, `disable <id>`,
  `enable <id>`, `category <id> stun`, `remove <id>`, and `add <id> <CLASS> <SPEC>` → each works and
  the page's rows redraw after each write, no reopen. Result: pass (owner-marked 2026-10-10)
- **SPELLS-11. Reset one spec.** Edit two specs' lists, then `/kcd spells reset <CLASS> <SPEC>` on one →
  only that spec is rebuilt from the defaults. The page's Defaults button → only the selected spec.
  Result: pass (owner-marked 2026-10-10)
- **SPELLS-12. Reset every spec.** `/kcd spells resetall` → every spec's list is rebuilt. Result: pass (owner-marked 2026-10-10)
- **SPELLS-13. Drag to reorder.** Grab row 3's handle and drop it above row 1 in one gesture → the list
  and the grid's priority follow; one box and one handle per row; the drop line is in the list color;
  `/reload` keeps the order. The row strip looks as it did before the list moved onto `RenderGrid`
  (KickCD#10): no gap between rows, and a drop onto the fourth or a later row lands on that slot,
  not one off. Start a drag and press Esc → no stray line. Leave and re-enter the page
  twice → no handle or box left stranded. Result: pass (owner-marked 2026-10-10)
- **SPELLS-14. Row tooltips and the remove mark.** Hover a spell name → the spell tooltip; a category
  dropdown → the Category tooltip. The remove button draws the red catalog close mark. Result: pass (owner-marked 2026-10-10)
- **SPELLS-15. Other addons' panels are untouched.** Close Settings, open another Ka0s addon's panel
  (`/at config`), hover and click its labels → no KickCD spell tooltip, and every click lands. Result: pass (owner-marked 2026-10-10)
- **SPELLS-16. Racials survive a reset.** On a race with a racial cast-stopper, reset one of your own
  class's specs (Defaults or `/kcd spells reset`) → the racial is the last row. Reset another class's
  spec → no racial. Result: pass (owner-marked 2026-10-10)

## SIM

The simulator (`/kcd sim`, `LibKa0s-Sim-1.0`, KickCD#38). Unless a check says otherwise: solo, out of
combat, in the open world, the grids locked (`/kcd lock`), Target and Focus both enabled. Between
checks, `/kcd sim stop`. A simulation casts, sends and saves nothing; if any check leaves a change in
`KickCDDB`, a cast, or a chat message to anyone, that is the failure.

- **SIM-1. The duration constructor exists under the names Compat uses (KC-01, SM-KC-1).** Out of
  combat, run `/run local d=C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration(); print(d ~= nil, d and pcall(d.SetTimeFromStart, d, GetTime(), 10), d and d.GetRemainingDuration and d:GetRemainingDuration())`
  → it prints `true true` and a number close to `10`. Anything else means `Compat.NewDuration`'s
  constructor or setter name is wrong and it answers nil in the client, and the simulator refuses with
  `This client cannot build simulated cooldowns, so the simulator cannot run.` Result: pass (owner, 2026-10-23)
- **SIM-2. No behavior change from the Compat unit readers (KC-01, SM-KC-2).** No simulation running.
  `/kcd set visibility target_casting_interruptible`. Target a hostile caster casting an interruptible
  spell → the grid shows and the cast bar fills in its interruptible colors; an uninterruptible cast
  masks the grid exactly as before the move; a friendly caster does not open the grid. No Lua error.
  Result: pass (owner, 2026-10-23)
- **SIM-3. The `sim` verb is listed, and refused while disabled (KC-03, SM-KC-3).** `/kcd help` → the
  index lists `/kcd sim` with `Run a simulation of interrupts and cooldowns — try `/kcd sim``.
  `/kcd disable`, then `/kcd sim` → one tagged line, the library's disabled line naming `/kcd enable`,
  and nothing else. `/kcd enable`, then `/kcd sim` → it answers again (SIM-4). There is no launcher
  entry and no key binding for it. Result: pass (owner, 2026-10-23)
- **SIM-4. The panel, the usage and the auto-run (KC-05, SM-KC-4, SM-KC-15).** `/kcd set visibility
  always`, then `/kcd sim` → chat prints `Simulation: idle. Scenarios: pull, boss, miss, leave.` and the
  usage lines (`start <scenario>`, `run`, `step`, `pause`, `resume`, `restart`, `stop`, `status`,
  `panel`), and the step panel opens docked beside the Target grid with the `pull` steps previewed and
  inert. Read those lines against README's *Simulator* paragraph: they agree on the four scenarios, on
  nothing being cast, sent or saved, and on `/kcd sim stop` ending it. Press the panel's Start →
  `Simulation started (Mythic+ pull, several kickers): nothing is cast, nothing is saved, and your
  settings are not touched.`, and the run plays a step about every second on its own, each with
  `Simulation step <n> of <total>: <label>.` While it plays, click a step row two or more ahead → the
  run pauses, every step up to the clicked one plays, and it waits. The panel's Resume → it plays on to
  `Simulation finished: /kcd sim stop ends it.` `/kcd sim stop`, then `/kcd sim start boss` → it too
  plays on its own. Drag the panel, `/kcd sim stop`, `/reload` and `/kcd sim` → the panel is docked
  again (its position was session-only). `/kcd sim stop`, `/kcd reset visibility`. Result: pass (owner, 2026-10-23)
- **SIM-5. Each refusal prints its one line and starts nothing (KC-05, SM-KC-5).** Run
  `/kcd sim start pull` in each state below → exactly the line shown, no `Simulation started`, no
  strip, no step played, and the grid shows your real cooldowns:
  - `/kcd unlock` → `Lock the grids first (/kcd lock): unlocking is KickCD's preview.` (`/kcd lock`
    after);
  - attacking a training dummy → `A simulation cannot start in combat.`;
  - in a party → `A simulation cannot start in a group.`;
  - inside a dungeon, solo → `A simulation cannot start in an instance.`;
  - Target and Focus both unticked on General → Units →
    `Enable the Target or the Focus grid first: the simulation plays on them.` (re-tick both);
  - during `/kcd perf start` →
    `A performance capture is running: finish it first (/kcd perf finish).` (`/kcd perf finish`);
  - with a simulation already running → `A simulation is already running.`

  Result: pass (owner, 2026-10-23)
- **SIM-6. Real combat stops a simulation (KC-06, SM-KC-6).** `/kcd sim start pull`, then attack a
  training dummy → the simulation stops with `Simulation stopped: you entered combat.`, the strip and
  the step panel clear, and the real grid shows your real cooldowns. Result: pass (owner, 2026-10-23)
- **SIM-7. Unlock and resetall refuse during a simulation (KC-06, SM-KC-7).** During a simulation,
  `/kcd unlock` and the launcher's *Locked* entry each print `End the simulation first (/kcd sim stop).`
  and the grids stay locked; `/kcd resetall` prints the same line and resets nothing. Unticking
  General → *Lock frame* in the settings stops the simulation with
  `Simulation stopped: the grids were unlocked.` Result: pass (owner, 2026-10-23)
- **SIM-8. `disable` stops a simulation first (KC-06, SM-KC-8).** During a simulation,
  `/kcd disable` → `Simulation stopped: the addon stood down.` comes first, then the addon stands down.
  `/kcd enable` brings the grid back with your real cooldowns. Result: pass (owner, 2026-10-23)
- **SIM-9. Targeting and casting are absorbed; diagnostics name the session (KC-06, SM-KC-9).**
  During a simulation, target a real mob and cast at it → the simulation keeps running, and the grid
  and the cast bar keep showing the simulated world. `/kcd diagnostics` has a `[Sim]` section naming
  the scenario and the step (`sim: step=<pos>/<total>`); after `/kcd sim stop` it reads `sim: idle`.
  Result: pass (owner, 2026-10-23)
- **SIM-10. The `pull` scenario plays on the real grid (KC-08, SM-KC-10).** `/kcd set visibility
  target_casting`, then `/kcd sim start pull` → the grid appears as Shadowcaster starts its cast, your
  kick's swipe starts when you kick, Thrall's and Jaina's `[sim]` lines print, the CC step dims the
  other spells for a GCD, and when combat ends the grid returns to its idle state. Result: pass (owner, 2026-10-23)
- **SIM-11. The `boss` and `miss` scenarios (KC-08, SM-KC-11).** `/kcd sim start boss` → a 2-charge
  badge on your kick, counting 2 -> 1 -> 0 with the recharge swipe, and back to 2 on the expire step.
  `/kcd sim stop`, then `/kcd sim start miss` → the cast bar shows the uninterruptible cast colors, then
  the interruptible ones after the shield breaks. Result: pass (owner, 2026-10-23)
- **SIM-12. The `leave` scenario, and no strip over the grids (KC-08; KC-02 of the 2026-10-30 skin
  fonts run, D-13).** `/kcd sim start leave` → after Valeera leaves, the focus bar clears and the
  target bar picks up Bonecaller's cast mid-way, and your kick interrupts it. `/kcd sim stop`. Then
  `/kcd set visibility target_casting` and `/kcd sim start pull` → **no** cyan strip appears over
  either grid or label, before, between or during casts (image-46's "Simulation: Mythic+ pull, ..."
  bars are gone); the step panel beside the grid is the only sign a simulation runs. Untick Target,
  then Focus, in the settings → still no floating strip; no Lua error. Re-tick both, `/kcd sim stop`
  (`/kcd reset visibility` after). Re-opened: the strip was removed. Result:
- **SIM-13. The step panel stays up for the whole session (KC-02, D-13).** `/kcd sim start pull` → the
  step panel opens beside the grid with **no close mark** at its top right. Press **Escape** → the
  panel stays. Let the steps run → it stays up throughout. Its Stop row (or `/kcd sim stop`) ends the
  session. `/kcd sim panel` still hides and shows it on purpose. After the stop the panel shows its
  idle picker again with its **close mark back**; press **Escape** → it closes. `/kcd sim` → it opens
  idle with the close mark, and the mark closes it. Fail: a close mark, Escape taking it down, or the
  panel closing on its own mid-session; or, after the stop, no close mark or Escape leaving the idle
  panel up. Result:

## DIAG

- **DIAG-1. `/kcd debug spells`.** → `Cooldowns: class=<CLASS> spec=<SPEC> (<specID>)`, then one line
  per watched spell: `[<id>] <name> ready=… active=… cdObj=yes|nil chargeCdObj=yes|nil charges=…`,
  charges maybe `<secret>` in combat, and no remaining-time field. Result: pass (owner-marked 2026-10-10)
- **DIAG-2. `/kcd debug castbar`.** Target a hostile caster mid-cast → `castbar state (target)`, the
  cast record with `current.notInterruptible: type=…, isSecret=…`, then `configured colors` and
  `live SetStatusBarColor values` for both states. With no cast the dump stops at
  `no active cast tracked (current = nil)`. Set a hostile caster as focus: `/kcd debug castbar focus` →
  `castbar state (focus)`, and `/kcd debug interrupt focus` dumps the focus unit's cast info; a bare
  `/kcd debug castbar` still reports the target. `/kcd debug castbar bogus` → `unknown unit 'bogus',
  expected target or focus` and no dump. Result: pass (owner-marked 2026-10-10)
- **DIAG-3. Logging is session-only.** `/kcd debug on` → chat says `debug logging ON` and the `[Tag] …`
  trace lines go to the console, not chat; `off` → `debug logging OFF` and they stop; `toggle` flips
  it. `/reload` → off again; no saved setting holds it. Result: pass (owner-marked 2026-10-10)
- **DIAG-4. `/kcd debug window`.** → the console opens and closes; logging keeps its state either way.
  Result: pass (owner-marked 2026-10-10)
- **DIAG-5. `/kcd debug events`.** → `no rejected events` on a live client. `/kcd debug on`, `/reload`,
  turn it on again → the `[Init]` line ends at `profile '<name>'` with no `rejected event(s)` clause.
  Result: pass (owner-marked 2026-10-10)
- **DIAG-6. Bare `/kcd debug`.** → the console toggles and the debug subcommand list prints. Result: pass (owner-marked 2026-10-10)
- **DIAG-7. The combat trace.** Debug on, console open. Enter and leave combat → one
  `[Combat] entered`, one `[Combat] left`; nothing at login, nothing per tick. Result: pass (owner-marked 2026-10-10)
- **DIAG-8. A section's Defaults logs a count.** Move two Cast bar settings, press Cast bar's Defaults
  (Target in the band) → one `[Set] reset castbar: 2 rows`, no per-row `[Set]`. Again →
  `[Set] reset castbar: 0 rows`. Result: pass (owner-marked 2026-10-10)
- **DIAG-9. Reset all logs one line.** Move three settings, Reset all settings (or `/kcd resetall`) →
  exactly one `[Set] reset profile '<name>' to defaults (3 rows)`, no `[Set] reset all` and no
  `[Profile] switched`. Again at once → `(0 rows)`, never the schema's size. Result: pass (owner-marked 2026-10-10)
- **DIAG-10. The reset mute does not stick.** After DIAG-9, `/kcd set locked true` → its own
  `[Set] locked = true`. `/kcd set locked false` and press General's Defaults within a third of a
  second → `[Set] locked = false` prints before `[Set] reset general: …`. Result: pass (owner-marked 2026-10-10)
- **DIAG-11. The cast and grid traces.** `target_casting_interruptible`; the target starts and stops an
  interruptible cast → at the start one `[Cast] [target] cast gate: interruptible on` (`interruptible
  secret (combat-tainted)` where the client hides the flag), at the stop one
  `[Cast] [target] cast gate: interruptible none (no hostile cast)`; one
  `[IconGrid] [target] visibility target_casting_interruptible: shown` or `…: hidden` each time the
  grid's shown state actually changes; nothing on refreshes that move neither. Result: pass (owner-marked 2026-10-10)
- **DIAG-12. The open trace.** `/kcd config` out of combat → one `[Open] settings panel` per open. Result: pass (owner-marked 2026-10-10)
- **DIAG-13. The spell-list traces.** On the Spells page add, toggle, recategorize, drag, remove and
  reset a spec → exactly one write line each: `[Spells] add <id> to <CLASS>/<SPEC>: N spells`,
  `enable/disable <id> in …`, `category <id> = <cat> in …`, `move <from> -> <to> in …`,
  `remove <id> from …: N spells`, `reset <CLASS>/<SPEC>: N spells`. `/kcd spells remove` and
  `/kcd spells reset` log the same lines; `/kcd spells resetall` logs one
  `[Spells] resetall: N lists, M spells`. The page's drag list also traces its own gesture and
  repaint (`[Spells] grab …`, `drop …`, `released …`, `painted …`); those are not writes. Result: pass (owner-marked 2026-10-10)
- **DIAG-14. The setting trace.** Change a setting → one debounced `[Set] …` line after it settles; no
  echo, no per-keystroke lines. Result: pass (owner-marked 2026-10-10)
- **DIAG-15. No spam.** 30 s+ in combat with no target casts → no `[Combat]`, `[Cast]` or `[IconGrid]`
  lines beyond the transitions already logged. Result: pass (owner-marked 2026-10-10)
- **DIAG-16. The console header.** `/kcd debug window` → the title bar's `Debug: ON` (green) or
  `Debug: OFF` (red) label is there; Esc closes the window. Opening it raises no error. Result: pass (owner-marked 2026-10-10)
- **DIAG-17. The line counter and its cap.** Grow the log (debug on in combat) → the bottom-right reads
  `N / 3000 lines`, rising one per line; Clear → `0 / 3000 lines`, log empty. Fill it past the cap (a
  long combat, or twenty-odd `/kcd diagnostics`) → `3000 / 3000 lines` and it stays there; Copy opens
  without a hitch. Result: pass (owner-marked 2026-10-10)
- **DIAG-18. The scrollbar tracks.** With more lines than fit, wheel up and down → the thumb moves with
  it; drag the thumb → the log follows; no flicker. Thumb at the bottom is newest, at the top oldest.
  Result: pass (owner-marked 2026-10-10)
- **DIAG-19. Inert when it fits.** After Clear → the scrollbar still shows, thumb parked, ignoring wheel
  and drag, and the right gutter keeps its width. Result: pass (owner-marked 2026-10-10)
- **DIAG-20. The shared window edge.** On **Ka0s Default**, the console reads as a flat 1px black border
  with a 1px light-gray highlight inside it, a gold "Ka0s KickCD — Debug" title and a gray divider.
  Beside a second Ka0s addon's console on Ka0s Default → border, highlight, divider and title are
  indistinguishable. A difference means a host passing `applySkin` again or `libs/LibKa0s` drifting
  from `../LibKa0s` (fix upstream and re-vendor, never in `libs/`). Under any other skin the console
  wears KickCD's skin (SKIN-11). (Amended by KC-05, 2026-10-29: the console paints for the skin owner,
  its descriptor's `addonName`.) Result: pass (owner-marked 2026-10-30)
- **DIAG-21. The title bar marks.** → copy, clear and close are three small white glyphs from
  `libs/LibKa0s/media/icons/`, with no tooltips. A `×`, or the words Copy and Clear, means
  `addonName = addonName` fell out of `core/DebugLogSetup.lua`'s descriptor. Result: pass (owner-marked 2026-10-10)
- **DIAG-22. The copy window's close.** Click copy → `KickCDDebugCopyWindow` opens with a read-only box,
  and its close is the same mark. Result: pass (owner-marked 2026-10-10)
- **DIAG-23. The perf panel's close.** `/kcd perf start` → the step panel has exactly one close control,
  top right, level with the title about 6 px in: the same `close` mark as the console's, pixel for pixel
  side by side. A `×` means `addonName` stopped reaching the library's `PerfPanel`. Result: pass (owner-marked 2026-10-10)
- **DIAG-24. The perf close only hides.** Click it → the panel hides, the run is not canceled, and
  `/kcd perf report` still has the capture. Result: pass (owner-marked 2026-10-10)
- **DIAG-25. The console face is monospace.** → timestamps and `[tags]` line up in a column. A
  proportional face is the honest fallback (`media/fonts/` missing from the payload); no text at all is
  the failure. Result: pass (owner-marked 2026-10-10)
- **DIAG-26. The perf strings.** `/kcd perf start mylabel` → `perf run STARTED — <YYYY-MM-DD HH:MM>
  mylabel`; `/kcd perf finish`, then `/kcd perf report` → the report's `capture:` line names the same
  label. `/kcd perf start` with no label → the start line carries the timestamp alone (the library
  always stamps one, so `unlabeled` never shows); `/kcd perf cancel` → `perf run CANCELED — nothing
  saved`, one L. A doubled L means the string did not come from the vendored payload. Result: pass (owner-marked 2026-10-10)
- **DIAG-27. The README's bug-report steps.** From a fresh `/reload` with the console closed, follow
  README → *Reporting a bug* word for word → every step works and the paste holds the trace and the
  whole report. Result: pass (owner-marked 2026-10-10)
- **DIAG-28. `/kcd diagnostics` keeps the trace and copies clean.** Debug on, a few target casts, then
  `/kcd diagnostics` → the console opens if closed; the trace sits above
  `==== Ka0s KickCD diagnostics begin ====`; chat prints *Diagnostic report written to the debug
  console: N lines. Use Copy to share it.* Copy and paste → the trace, both markers
  (`==== Ka0s KickCD diagnostics end: N line(s) ====`), no `|c` escapes, and the counts agree. Result: pass (owner-marked 2026-10-10)
- **DIAG-29. The report's shape.** → `[State]` first after the `[Diag]` identity lines, sections in
  [debug.md](debug.md#kcd-diagnostics-the-report-debug-logging-14)'s order, no `section <name> failed`,
  about 100 to 200 lines on a default profile. Result: pass (owner-marked 2026-10-10)
- **DIAG-30. Ungated.** `/kcd debug off`, `/kcd diagnostics` → the full report, begin to end marker,
  with nothing missing: it lands whatever the flag read before the run. The run turns logging on
  first (DIAG-40), so afterwards the header reads `Debug: ON`. Result: pass (owner-marked 2026-10-10)
- **DIAG-31. While disabled, both forms.** `/kcd disable`, `/kcd diagnostics`,
  `/kcd debug diagnostics` → both write a full report; the state line reads
  `enabled stored=false, stood down=true, holds=…`; `cooldowns`, `icongrid`, `castbar` and `unitlabel` each
  print one `stood down: …` line; nothing stands up. `/kcd enable`. Result: pass (owner-marked 2026-10-10)
- **DIAG-32. No alias.** `/kcd diag` → `unknown command 'diag'` and the help index;
  `/kcd debug diag` → the unknown-word line and the debug list. Neither writes a report. Result: pass (owner-marked 2026-10-10)
- **DIAG-33. The long alias and any case.** `/kickcd diagnostics`, `/kickcd debug diagnostics` and
  `/kcd DIAGNOSTICS` → each writes the same report. Result: pass (owner-marked 2026-10-10)
- **DIAG-34. The console resizes.** `/kcd debug window` → a small grip sits in the bottom-right corner,
  clear of the `N / 3000 lines` counter. Drag it out and in on both axes → the window follows; the log,
  the scrollbar and the title-bar controls follow their edges, the counter and the thumb stay in step,
  and the lines and scroll position are kept. Drag it as small as it goes → it stops while the title and
  every title-bar control still fit side by side and a few lines show; nothing overlaps. Result: pass (owner-marked 2026-10-10)
- **DIAG-35. The console's size is for the session.** Resize the console, close it (Esc or the close
  mark) and reopen it → the same size, not the default. `/reload`, reopen → back at 700 × 344. Drag the
  window somewhere, resize it, `/reload` → the default size again, and the position behaves as it did
  before this change. `WTF/Account/<ACCOUNT>/SavedVariables/KickCD.lua` holds no console size. Result: pass (owner-marked 2026-10-10)
- **DIAG-36. Each console is its own.** Beside a second Ka0s addon's console (DIAG-20), resize KickCD's →
  the other keeps its size; resize the other → KickCD's does not move. Result: pass (owner-marked 2026-10-10)
- **DIAG-37. The copy window resizes.** Click copy → `KickCDDebugCopyWindow` has the same grip. Drag it
  on both axes → the text box widens and narrows with it, the scroll bar's down arrow stays clickable
  above the grip, and there is a minimum it will not go under. Close and reopen it → the same size;
  `/reload`, open it again → the default size. Resizing it leaves the console's size alone. Result: pass (owner-marked 2026-10-10)
- **DIAG-38. The perf panel resizes in width only.** `/kcd perf start` → the step panel has a grip in
  its bottom-right corner. Drag it → the width changes and every step row stretches to the new width;
  the height does not move, and the panel will not go narrower than it opened. `/kcd perf hide`,
  `/kcd perf show` → the same width; `/kcd perf cancel`, `/reload`, `/kcd perf start` → the default
  width again. Result: pass (owner-marked 2026-10-10)
- **DIAG-39. The Diagnostics link.** Bare `/kcd debug` → in the title bar, top left, the word
  **Diagnostics** sits just right of the `Debug: ON` / `Debug: OFF` label with a small gap, drawn
  orange in the same plain text as that label: no button art, border or background. Hover it → it
  brightens; move off → orange again. With logging off, click it → logging turns on first: the label
  reads `Debug: ON`, chat prints `debug logging ON`, and the console gains `[Debug] logging enabled`
  and the `[Init]` summary; then the report is written after them (begin to end marker, as DIAG-28,
  its header reading `debug logging: on`) with the one chat line giving its line count. Click it
  again → the report appends once more, with no second `logging enabled` line. Toggle the label
  between ON and OFF → the gap after it holds for either word. Drag the console in as far as it goes
  (DIAG-34) → the link still fits beside the label and the title. Result: pass (owner-marked 2026-10-10)
- **DIAG-40. Diagnostics turns logging on for the session.** `/reload` → logging is off (DIAG-3).
  `/kcd diagnostics` → chat prints `debug logging ON`, then the report's line-count line; the console
  holds `[Debug] logging enabled` and the `[Init]` summary ahead of the begin marker, the header reads
  `debug logging: on`, and the title-bar label reads `Debug: ON`. Change a setting → a `[Set]` line
  streams. `/reload` → logging is off again. `/kcd debug diagnostics`, or the console's Diagnostics
  link (DIAG-39) → the same: logging on for the session. `/reload` once more, then `/kcd debug on` and
  `/kcd diagnostics` → the report appends with no second `logging enabled` line. `/kcd debug off` →
  logging stops, and nothing turns it back on until the next report or `/kcd debug on`. Result: pass (owner-marked 2026-10-10)
- **DIAG-41. A Slash refusal shows in the console.** `/kcd debug on`, `/kcd debug window`. Type
  `/kcd frobnicate` → chat prints `unknown command 'frobnicate'` and the help index, and the console
  gains one `[Cmd] refused frobnicate: unknown verb` line. `/kcd set locked banana` → one
  `[Cmd] refused set locked: parse` line. `/kcd disable`, then `/kcd lock` → chat prints the disabled
  line, and the console gains one `[Cmd] refused lock: disabled`; `/kcd enable`. In combat,
  `/kcd profile Default` (with a second profile active) → `Can't switch profiles in combat.` in chat
  and one `[Cmd] refused profile Default: in combat`. No refusal is written twice, and none has a
  second line beside it naming the same verb. Result: pass (owner-marked 2026-10-10)
- **DIAG-42. A Lifecycle edge shows in the console.** `/kcd debug on`, `/kcd debug window`.
  `/kcd disable` → one `[Lifecycle] stood down: added disabled (holds: disabled)` line and no
  `[State] stood down` line. `/kcd disable` again → no new `[Lifecycle]` line (nothing changed).
  `/kcd enable` → one `[Lifecycle] stood up: released disabled (holds: none)`. Result: pass (owner-marked 2026-10-10)
- **DIAG-43. State lines land at the first enable.** `/reload`, then `/kcd debug on` → after
  `[Debug] logging enabled` and the `[Init]` summary, the console holds one `[Launcher] registered`
  line. `/kcd debug off`, `/kcd debug on` → no second `[Launcher] registered`. With
  `libs/LibCustomGlow-1.0` renamed aside and a `/reload`, `/kcd debug on` → one
  `[Init] LibCustomGlow-1.0 absent; no icon glows` line, and the `[Init]` summary carries no
  `missing` clause. Restore the folder. Result: pass (owner-marked 2026-10-10)
- **DIAG-44. Clear re-arms the change-gated lines.** `/kcd debug on`, `/kcd debug window`, open the
  settings on the General page. Drag the master scale slider back and forth → at most one
  `[Cooldowns] rebuild …` line, however long the drag. Click the console's clear control, then nudge
  the slider → exactly one `[Cooldowns] rebuild …` line, although the watched list did not change;
  keep dragging → no more. Result: pass (owner-marked 2026-10-10)
- **DIAG-45. The interrupt dump's secret sentinel.** In combat, target a hostile caster whose cast
  flags are secret and type `/kcd debug interrupt` → every secret-tainted position reads
  `isSecret=true  value=<secret>`, with no Lua error, the same spelling as `charges=<secret>` in
  `/kcd debug spells` (both are LibKa0s-Core's `NS.SECRET` now). Result: pass (owner-marked 2026-10-10)

## DEGRADED

Before the rename, `/kcd set units.target.castbar.anchorMode FREE`. With the library gone the degraded
`/kcd set` writes only `enabled` and `locked`, and the settings panel does not open, so the anchor mode
cannot be changed afterwards; an earlier reset puts it back to Primary. Then rename `libs/LibKa0s` to
`libs/LibKa0s_off` and `/reload` before DEGRADED-1.

- **DEGRADED-1. It degrades, it does not error.** → zero Lua errors at login; `/kcd` answers and the host
  verbs work. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-2. `/kcd list`.** → exactly `/kcd list is unavailable: the LibKa0s library did not load.`,
  tagged `[KCD]`. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-3. Disable and enable.** `/kcd disable` → `enabled = false`, the grids go, no error.
  `/kcd lock` → `Ka0s KickCD is disabled — enable it with /kcd enable`. `/kcd enable` →
  `enabled = true`, the grids return. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-4. Lock and unlock.** `/kcd unlock`, `/kcd lock` → each confirms and moves the lock.
  Result: pass (owner-marked 2026-10-10)
- **DEGRADED-5. Plain help rows.** `/kcd help` → rows read `/kcd <verb>  <desc>`: white, two spaces, no
  em-dash separator between verb and description (a description may carry its own em dash, as
  `disable`, `get`, `set`, `reset`, `spells`, `debug` and `perf` do). Result: pass (owner-marked 2026-10-10)
- **DEGRADED-6. One notice.** → the missing-library notice appears exactly once per session, naming
  `libs/LibKa0s`, however many lines print after it. Run DEGRADED-11's dump too: the notice comes
  before the dump, never once per dump line. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-7. The same sentence as the other addons.** Do the same rename on AbsorbTracker and
  ConsumableMaster → all three state the cause (`NS.LIBKA0S_MISSING`) identically, differing only in the
  addon name and the trailing consequence. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-8. Each seam names its own consequence.** `/kcd config` → opens nothing, one line about the
  settings panel; `/kcd debug` → its line about the debug console window; `/kcd perf` → its line
  saying performance measurement is unavailable. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-9. No report.** `/kcd diagnostics` and `/kcd debug diagnostics` → each prints
  `/kcd diagnostics is unavailable: the LibKa0s library did not load.` and nothing else. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-10. No profile verb.** `/kcd profile` and `/kcd profile Default` → each prints
  `/kcd profile is unavailable: the LibKa0s library did not load.` and switches nothing. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-11. The castbar dump prints tagged.** Target anything, `/kcd debug castbar` → the dump
  prints, every line tagged `[KCD]`. A Lua error naming `Castbar_Debug.lua` and a nil `emit` means
  `Util.print` is missing on the degraded path. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-12. The cast bar drags by its body.** Target's anchor mode set to Free before the rename (see
  above), `/kcd unlock` → the Target cast bar's preview shows with no strip, and drags by its body. No
  error. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-13. Restore.** Rename the folder back to `libs/LibKa0s` and `/reload` → the notice is gone
  and the console is back. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-14. Plain sub-help rows.** Run this before DEGRADED-13's restore. `/kcd debug` and
  `/kcd spells` → each prints its sub-list as plain `/kcd debug <verb>  <description>` (and
  `/kcd spells <verb>  <description>`) rows: no color, no em-dash separator, the same shape as
  DEGRADED-5's help rows, and no Lua error. `/kcd debug events` still answers. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-15. The interrupt dump still says `<secret>`.** Run this before DEGRADED-13's restore. In
  combat, target a hostile caster whose cast flags are secret, `/kcd debug interrupt` → the dump prints,
  every line tagged `[KCD]`, and every secret-tainted position reads `value=<secret>` (the stub's
  `NS.SECRET`), with no Lua error. Result: pass (owner-marked 2026-10-10)
- **DEGRADED-16. The HUD on its stored picks (KC-03).** Run this before DEGRADED-13's restore.
  `/kcd unlock` → the grids, cast bar and labels draw what each profile stores, with no skin engine to
  follow: on default picks Friz Quadrata, Blizzard Raid Bar and the 2 px Blizzard Tooltip edges, the
  pre-skin look; no face, texture or border is missing, and no skin picker opens at login. `/kcd lock`.
  Result: pass (owner-marked 2026-10-30)

## LAYER

Frame layering (item 030, KC-ZS): the order the HUD's pieces draw in, from `NS.Const.LAYERS`. Use
`/fstack` over a frame to read its strata and level where a check is hard to judge by eye.

- **LAYER-1. Icon text over the swipe and the border (KIC-Z01, Z02).** Annotations → Show cooldown
  text and Show charges on, a border of thickness 2 or more, a charged spell on cooldown → the
  countdown reads at full brightness while the swipe darkens the icon under it, and the charges badge
  draws over the border edge in its corner, not under it. The border edge is crisp over the swipe's
  sweep, never covered by it. Result: pass (owner, 2026-10-24)
- **LAYER-2. Charges and countdown draw above the proc glow (KIC-Z03, owner CALL-06).** Glow trigger
  `always`, then each of the four glow styles in turn, on a charged spell with the countdown showing →
  the glow draws over the icon, the swipe and the border, and the countdown and the charges badge draw
  over the glow and stay legible. Result: pass (owner, 2026-10-24)
- **LAYER-3. The cast bar's spark and text over its border (KIC-Z04).** A border of thickness 2 or
  more, name and time text at their inside edges, target a hostile caster → the spark and the text
  draw over the border edge rather than being cut by it, and the border is still not tinted by the
  fill color. Result: pass (owner, 2026-10-24)
- **LAYER-4. The cast bar draws over its grid (KIC-Z05).** `/kcd set units.target.castbar.anchorMode
  FREE`, `/kcd unlock`, drag the bar over the icon grid, `/kcd lock`, target a hostile caster with a
  glow showing → the bar draws over the icons and their glow wherever they overlap. `/kcd reset
  units.target.castbar.anchorMode`. Result: pass (owner, 2026-10-24)
- **LAYER-5. A label attached to the cast bar draws on it (KIC-Z06).** Label Attach to → Cast bar,
  anchor and relative point `CENTER` on `CENTER`, target a hostile caster → the label reads over the
  bar's fill and border during the cast; `/reload` and repeat → still on top. Attach to → Icons →
  the label draws over the icons too. Result: pass (owner, 2026-10-24)
- **LAYER-6. The drag strips are on top while unlocked (KIC-Z07).** `/kcd unlock` with the cast bar
  anchored above the grid (a `TOP_*` primary anchor), then with a FREE cast bar dragged over the grid
  → both strips and their `?` marks draw over the icons, the glow and the cast bar; each strip still
  takes the drag and its tooltip, and the `?` mark is not hidden under its strip.
  Result: pass (owner, 2026-10-24)
- **LAYER-7. Retired 2026-10-30: the sim strip it layered was removed** (KC-02 of the skin fonts run,
  ruling D-13; SIM-12 checks that no strip draws, SIM-13 that the step panel stays up).
- **LAYER-8. Tool windows raise on click and never bury a confirmation (KIC-Z10, LibKa0s LK-01).**
  Open the debug console (`/kcd debug window`), the perf panel (`/kcd perf`) and the sim panel
  (`/kcd sim`) together → clicking each raises it over the other two. General → Reset all settings
  (the confirmation shows), then
  `/kcd debug window` → the confirmation stays above the console. Result: pass (owner, 2026-10-24)
- **LAYER-9. The icon hover tooltip still works (KIC-Z01).** `/kcd lock`, icons Show tooltip on, hover
  an icon → the spell tooltip opens; the text overlay does not take the hover.
  Result: pass (owner, 2026-10-24)

## SKIN

The skinning rollout's checks (Ka0sAddonsCommonTasks `docs/2026-10-29-SKINNING_ROLLOUT/`, items KC-01 to
KC-05; owner rulings O2 and O3, decisions X3 to X6). Start from a **full client start** after installing
this build (see *Before you start*), and pick skins on `/kcd config` → General → **Skin**. The HUD is
the icon grids, cast bars and unit labels: `/kcd unlock` shows every enabled unit's grid and cast-bar
placeholder whatever the visibility mode, and a hostile caster shows the two cast states. `/kcd lock`
after each check. Every check also fails on a Lua error or a taint warning.

- **SKIN-1. Ka0s Default after the upgrade: the HUD's one visible change (O2, X5; KC-03).** On a
  profile saved by a build before this one, with every HUD font, texture and border left at its
  default, log in on **Ka0s Default** → the HUD changes in exactly these ways and no others: the
  countdown text, the cast bar's spell name and cast time, both unit labels and the charges badge read
  in **Prototype** (a squared, technical face; Oxanium before LibKa0s v1.82.0) instead of Friz Quadrata (the badge's was the client's
  number font); both cast-bar states fill with the **Ka0s Default** bar texture (dim at the top, a
  highlight low on the bar and a short lip) instead of Blizzard Raid Bar, in the same yellow and red;
  both cast-bar states and each icon draw a **flat 2 px edge** in the border color (black) where each
  drew the 2 px Blizzard Tooltip edge (the cast bar keeps an edge under every skin, KC-A1). Sizes, colors,
  opacity, the glow, the layout and every position are as before. The settings pages are as before
  (the Skin tab's **Ignore settings panel** is on). The debug console, perf panel and sim panel keep
  their edge and colors; their text reads in Prototype, the log lines in JetBrains Mono. Fail: any other
  changed color, size or position, a HUD string still in Friz Quadrata, a cast bar on Blizzard Raid
  Bar, or a cast bar with no border or still on the Blizzard Tooltip edge. Re-opened for LibKa0s
  v1.82.0 (KC-01): Ka0s Default's face is Prototype. Result:
- **SKIN-2. The reset runs once per profile and keeps your own picks (O2; KC-03).** Before installing
  this build, on a profile `SkinA` set Target's interruptible cast-bar texture to a bar that looks
  clearly different (Blizzard Raid Bar) and its cast-bar font to Arial Narrow, and give a second
  profile `SkinB` a different label font. Install, log in on `SkinA` → the interruptible bar wears the
  skin's texture; Units > Cast bar → its **Use the skin's texture** is ticked and the picker beside it
  is grayed and shows the skin's bar. The cast-bar text still reads in **Arial Narrow** with its **Use
  the skin's font** unticked: on the same load KC-03 hands a picked face back (SKIN-36), so only the
  texture and border picks follow the skin. Untick the texture box → Blizzard Raid Bar comes back at
  once. `/reload` → still Raid Bar, the box still unticked (`/kcd get
  units.target.castbar.interruptible.statusBarTextureFromSkin` prints false). Switch to `SkinB` → its
  label keeps its own face with its box unticked, and its textures and borders follow the skin (its
  first activation ran both steps). Switch back to `SkinA` → still Raid Bar and Arial Narrow. `/kcd get
  skin.hudReset` is not a setting and answers *Setting not found*. Fail: the reset running again after
  a reload or a profile switch, a stored pick lost, a picked face drawing the skin's font, or a profile
  that was not active at the upgrade left off the skin. Re-opened for LibKa0s v1.82.0 (KC-01, KC-03):
  Ka0s Default's face is Prototype, and a picked face now comes back unticked. Result:
- **SKIN-3. A new or reset profile follows the skin from the start (X3).** Create a profile `SkinNew`
  → every **Use the skin's ...** box on Units > Icons, Cast bar and Text label is ticked for both
  units, and the HUD looks as SKIN-1 describes. Untick one, then Profiles → Reset Profile → ticked
  again. Delete `SkinNew`. Result: pass (owner-marked 2026-10-30)
- **SKIN-4. The Skin tab (KC-01).** General → the strip reads `Master controls | Skin`, Skin last
  (there is no Keybindings tab). Skin shows a **Skin source** heading over *Ka0s skins* (on) and
  *EllesmereUI* (disabled with a line saying why, unless EllesmereUI is loaded and can skin this
  addon), a **Look** heading over the nine skins three to a line, each with its color swatches, a
  **Font and texture** heading (**Font** and **Texture**, both *Skin's default (X)*, where X is the skin's own face or bar), the Scope (**Ignore
  settings panel** on, **Ignore fonts** off), **Copy to every Ka0s addon…** and the note that skins
  change every visual element. Pick **Obsidian** → no reload, no Lua error; `/kcd get skin.skin`
  prints `obsidian`. `/kcd set skin.skin nosuchskin` is refused and nothing moves; `/kcd set skin.skin
  ka0s` → back to Ka0s Default, and the tab shows it. General → **Defaults** → Master controls reset,
  the skin untouched. Re-opened for LibKa0s v1.83.0 (KC-F01): the rows read *Skin's default (X)*.
  Result:
- **SKIN-5. Each skin, live, on the HUD (KC-03).** `/kcd unlock` with both units enabled, Focus
  unlinked, then pick each skin in turn: Obsidian, Azeroth, Glass, High Contrast, Ember, WoW Default,
  WoW Midnight, WoW Forever, then Ka0s Default again → with **no reload** every grid, cast bar and
  label repaints (SKIN-6 lists what each skin draws); the cast bar's yellow and red, the label's gold,
  the border color, the glow, the sizes and the positions never move. Back on Ka0s Default the HUD
  is exactly as SKIN-1 left it. Target a hostile caster under two skins → the live bar wears the skin
  in both states. Fail: a piece that keeps the old skin until `/reload`, or a color that changed with
  the skin. Result: pass (owner-marked 2026-10-30)
- **SKIN-6. What each skin draws on the HUD (KC-03; LibKa0s SkinDefs).** With every **Use the skin's
  ...** box ticked and no Font or Texture override: the HUD text reads in each skin's own HUD face (LibKa0s v1.83.0 moved six): Ka0s Default
  **Prototype**, Obsidian **Expressway**,
  Azeroth **Open Sans Semibold**, Glass **Avant Garde**, High Contrast **Doris PP**, Ember **Emblem**, WoW
  Midnight **Segoe UI Semibold**, WoW Forever **Fira Sans**, WoW Default **Friz Quadrata** (the shipped
  Ka0s Friz Quadrata TT, which reads differently from Ka0s Default even on a client whose own Friz file
  is Prototype). The cast bar's
  texture: Ka0s Default **Ka0s Default**; Obsidian **Ka0s Matte**; Azeroth **Ka0s Parchment**; Glass
  **Ka0s Glass Bar**; High Contrast **Ka0s Solid**; Ember **Ka0s Forge**; WoW Midnight **Ka0s Satin**;
  WoW Forever **Ka0s Classic**; WoW Default **Blizzard**. The icon border and both cast-bar states'
  borders take the skin's icon edge (KC-A1): a flat 1 px edge under Obsidian, Glass and WoW Forever, a
  flat 2 px edge under Ka0s Default, Azeroth, High Contrast, Ember and WoW Midnight, and the 2 px
  Blizzard Tooltip edge under WoW Default. Fail: a bar on another skin's texture, a white or missing
  fill, a cast bar or icon with no border, an edge of the wrong thickness, HUD text in Friz Quadrata
  under any skin but WoW Default, or an empty square where a letter should be. Re-opened for LibKa0s
  v1.82.0 (KC-01): the Ka0s Default and Obsidian faces moved. Re-opened for LibKa0s v1.83.0 (KC-F01): six
  more moved. Result:
- **SKIN-7. The "Use the skin's ..." boxes (KC-03).** On a non-default skin (Azeroth), Units > Icons
  → Appearance → Border and Annotations → Cooldown text, Cast bar → Text → Font (both texts) and each
  state's Bar and Border, and Text label → Font each carry one **Use the skin's ...** box (eight per
  unit). Ticked, the picker beside it is grayed and shows the skin's value, and the icon border's box
  and each cast-bar state's Border box also gray the thickness slider (the skin sets both). Untick
  each in turn → that one piece goes back to your own pick at once, the rest stay on the skin; tick
  it → back on the skin. Your colors, sizes, flags and shadows are never grayed and never move. Fail:
  a box that changes another piece, a picker that stays live while ticked, or a color, size or flag
  that follows the skin. Result: pass (owner-marked 2026-10-30)
- **SKIN-8. A linked Focus and Copy from Target (KC-03).** Focus linked → it draws exactly what Target
  draws under every skin, and its entries are inert as before. Unlink, untick Target's **Use the skin's
  font** on the cast bar, then Units → Focus → **Copy from Target** → Focus's box is unticked too and its
  bar draws Target's face. Result: pass (owner-marked 2026-10-30)
- **SKIN-9. The settings pages follow the skin (KC-01, KC-02).** On the Skin tab untick **Ignore
  settings panel**, pick **Obsidian**, then walk General, every Units entry (with the band's Unit
  picker, Enable this unit, Link to Target and Copy from Target), Spells (the class and spec picker,
  Add spell, every row's handle, icon, name, enable box, known mark, category dropdown and Remove mark)
  and Profiles (its dropdowns, edit box and buttons) → the nav rail, tabs, headings, check boxes,
  sliders, dropdowns, edit boxes, buttons and drawers wear Obsidian, in Expressway. Pick **Ka0s Default** →
  with no reload the pages wear the Ka0s look, not the game's: the tab strip, the drawer heads and the
  nav entries in Prototype (LibKa0s v1.81.0 retired the stock look under Ka0s Default). Tick **Ignore
  settings panel** → every page is stock again, live, the drawer heads back in the game's face. Open another Ka0s addon's and another AceGUI addon's settings between KickCD's pages a few
  times → theirs stay as they were every time (the AceGUI pool leak check). Fail: a control that keeps
  the old skin until `/reload`, a skinned control with Ignore settings panel on, or another addon's
  widget wearing KickCD's skin. Re-opened for LibKa0s v1.82.0 (KC-01): the
  Obsidian and Ka0s Default faces moved. Result:
- **SKIN-10. The Spells page's own colors and hints (KC-02; D5).** On Ka0s Default, Spells → the
  Remove mark rests in the same soft red, the add box's *not tracked* tag is the same orange, and
  hovering a row's Remove mark or its known mark opens a tooltip whose first line is the same gold as
  before this build. Under **Azeroth** with Ignore settings panel off → the Remove mark, the tag and the
  hint titles take Azeroth's colors; the tooltip frame itself stays Blizzard's. Tick **Ignore settings
  panel** (still Azeroth) → all three are back to the Ka0s Default red, orange and gold, like the rest
  of the page. Fail: any of the three in Azeroth's colors with the panel ignored. Result: pass (owner-marked 2026-10-30)
- **SKIN-11. The tool surfaces follow the skin (KC-01, KC-04).** Under **Azeroth**, `/kcd unlock` → both
  drag strips and their `?` marks wear Azeroth; open the debug console (`/kcd debug window`) and its copy
  window, the perf panel (`/kcd perf`) and the sim panel (`/kcd sim` a scenario)
  → each wears Azeroth: edge, title, buttons, labels, log lines, line counter, scroll bars, resize grip
  and the sim panel's dropdowns; a drag strip's tooltip takes Azeroth's tooltip colors; the console's
  log keeps JetBrains Mono. These
  are windows: ticking **Ignore settings panel** leaves them on Azeroth. With it unticked, drag a Spells
  row → the reorder ghost and drop line wear Azeroth; tick it → stock, like the rest of the page. Switch
  to **Ka0s Default** with the console open → it repaints with no reload and looks as SKIN-1 says.
  Re-opened for KC-02: the sim strip is
  gone. Result:
- **SKIN-12. A font override (KC-01; LibKa0s#63).** With **Ignore fonts** off, Skin tab → **Font** →
  a clearly different face → with no reload every HUD text whose **Use the skin's font** is ticked
  takes it, sized to keep Ka0s Default's width when it is a shipped Ka0s face and at the sizes it had
  when it is any other, and so do the skinned settings pages and the tool windows (the
  console's log keeps its monospace face); an unticked HUD text keeps your pick. Switch skins → the override stays. **Font** → *Skin's
  default (X)* → the skin's face is back. `/kcd get skin.font` shows the key while set and an empty value
  after. Re-opened for LibKa0s v1.83.0 (KC-F01): the row's name, and an override of a shipped face now
  scales. Result:
- **SKIN-13. A texture override (KC-01; LibKa0s#63).** **Texture** → a clearly different status bar →
  with no reload both cast-bar states take it (where their **Use the skin's texture** is ticked), each
  in its own color; the icons and the label do not change. *Skin's default (X)* → the skin's texture is
  back. Re-opened for LibKa0s v1.83.0 (KC-F01): the row's name. Result:
- **SKIN-14. Ignore fonts, the HUD included (KC-01; LibKa0s v1.81.0).** With Ignore settings panel
  off, a font override set and Target's cast-bar font set to Arial Narrow with its **Use the skin's
  font** ticked, `/kcd unlock` and tick **Ignore fonts** → with no reload the settings pages and tool
  windows go back to the game's own faces, and every HUD text draws its own font setting though its
  box stays ticked: the cast bar in Arial Narrow, the countdown and the labels in their pickers' faces,
  the charges badge in the game's number font. The grayed picker beside a ticked box shows the stored
  face, not the skin's. The override stays selected in **Font**. Untick Ignore fonts → the override's
  face is back on the panel and on every ticked HUD text. Result: pass (owner-marked 2026-10-30)
- **SKIN-15. EllesmereUI on (KC-01; LibKa0s SkinEUI).** With EllesmereUI loaded, its third-party
  skinning on and KickCD on in its Third-Party list → Skin → **Skin source** offers **EllesmereUI**;
  choose it → the settings pages (with Ignore settings panel off) and the tool windows take EllesmereUI's
  accent, panel color and font, live; the HUD draws Ka0s Default's HUD media (SKIN-1's look) while its
  boxes are ticked. Result: pass (owner-marked 2026-10-30)
- **SKIN-16. EllesmereUI off (KC-01).** Turn KickCD off in EllesmereUI's Third-Party list (or disable
  EllesmereUI) and `/reload` → the EllesmereUI choice is disabled with the failing condition and its
  fix listed, and KickCD wears its Ka0s skin, HUD included. Result: pass (owner-marked 2026-10-30)
- **SKIN-17. Back from EllesmereUI needs a reload (KC-01).** With EllesmereUI as the source, pick **Ka0s
  skins** → a reload is offered; after it the Ka0s skin shows. Switching to a profile whose source is
  Ka0s while EllesmereUI painted this session prints one line asking for `/reload`. Result: pass (owner-marked 2026-10-30)
- **SKIN-18. Copy to every Ka0s addon (KC-01).** With a second Ka0s addon that uses skins loaded, set a
  skin, a font and a texture here and press **Copy to every Ka0s addon…** → the confirmation names the
  font and texture; accept → the other addon wears them with no reload and its Skin tab shows them, and
  KickCD repaints once. With no other adopter loaded the button is disabled with *No other loaded Ka0s
  addon uses skins yet.* Result: pass (owner-marked 2026-10-30)
- **SKIN-19. Profiles (KC-01).** Give two profiles different skins, Font overrides and Scope, then
  switch between them on Profiles → each brings its own, HUD included, with no reload. Copy one onto
  the other → the copy's skin. Reset one → Ka0s Default, the overrides cleared, Ignore settings panel
  back on. General → Reset all settings → the same for the active profile. Result: pass (owner-marked 2026-10-30)
- **SKIN-20. Combat (KC-01, KC-03).** On a target dummy in combat, change the skin on the Skin tab and
  with `/kcd set skin.skin azeroth` → no Lua error and no taint warning; the HUD repaints at once and the
  interrupt still lands from your bars; the settings pages behave as for any other setting in combat.
  Result: pass (owner-marked 2026-10-30)
- **SKIN-21. The minimap button, tooltips and popups stay stock (E2, E3).** Under every skin, hover the
  minimap button and an icon on the grid (Show tooltip on), and open General → Reset all settings → the
  button, its tooltip, the spell tooltip frame and the confirmation popup look as before this build.
  Result: pass (owner-marked 2026-10-30)
- **SKIN-22. The first-run skin picker (KC-04; O3, X6).** On a character that never ran this build, log
  in → shortly after the world loads a small window titled **Choose a skin** opens about three quarters
  of the way up the screen, already in the profile's skin: **Ka0s KickCD** whole on its own line, then
  a dropdown showing the skin
  worn now, a gear button beside it (and **no eye**: KickCD has no window, and its simulator is a scripted session, not a preview mode),
  **Apply** under it and a close mark. Close it, `/reload` → it does not come back on that profile.
  Create a new profile → it opens again; reset that profile after closing it → again. Every existing
  profile shows it once too. Fail: an eye button, a title that still names the addon, the name cut off
  or missing above the dropdown, no window on a new or reset profile, or one on a profile that already
  closed it. Result: pass (owner-marked 2026-10-30)
- **SKIN-23. A pick previews; Apply saves; a close puts it back (KC-04).** With `/kcd unlock` (so the HUD
  shows) and the picker up on a fresh profile, pick **Obsidian** in its dropdown → the HUD, the drag
  strips and the picker repaint in Obsidian with no reload, and nothing is saved (`/kcd get skin.skin`
  still prints the skin it opened with). Press **Apply** → it closes and Obsidian stays; `/reload` →
  still Obsidian. On another fresh profile preview **Azeroth** and close with the close mark → back to
  the old skin, nothing saved, and the picker stays closed on that profile; the same with **Escape**.
  On a third, preview a skin, then `/kcd set skin.skin glass`, then close → the addon wears Glass, the
  stored skin. Result: pass (owner-marked 2026-10-30)
- **SKIN-24. The picker's gear (KC-04).** On a fresh profile preview **Obsidian** and press the gear →
  the settings panel opens on **General** with its **Skin** tab selected, showing Obsidian, and the
  picker closes; `/reload` → still Obsidian, no picker. In combat the gear says the panel cannot open
  and the picker stays up. Result: pass (owner-marked 2026-10-30)
- **SKIN-25. The picker and the addon switched off (KC-04).** With the picker up, `/kcd disable` → it
  closes without being marked seen, and a pending preview goes back to the stored skin; `/kcd enable`,
  `/reload` → it opens again. On a profile with the addon disabled, log in → no picker. Result: pass (owner-marked 2026-10-30)
- **SKIN-26. The picker and combat (KC-04).** Reset the profile, then `/reload` while in combat on a
  target dummy → no picker during combat; leave combat → it opens then, once. With the picker up and a
  preview pending, enter combat → picking, **Apply** and the gear each say they cannot be done in combat,
  the preview stays pending, and the close mark still closes it and puts the old skin back. Result: pass (owner-marked 2026-10-30)
- **SKIN-27. One picker across Ka0s addons (KC-04; LibKa0s PK-02).** With a second Ka0s addon that uses
  skins also on a fresh profile, `/reload` → one picker opens; close it → the other's opens. Reset both
  and `/reload` → on the first picker **Apply to all Ka0s addons** shows beside Apply; preview
  **Azeroth** and press it → both addons wear Azeroth with no reload, each keeps its own font, texture
  and Scope, and no second picker opens. Result: pass (owner-marked 2026-10-30)
- **SKIN-28. A profile switch with a preview pending (KC-04).** Give a profile `SkinB` **Azeroth** and
  close its picker. On a fresh profile on Ka0s Default preview **Obsidian**, then switch to `SkinB` → the
  picker closes and the addon wears Azeroth (never Obsidian or Ka0s Default). Switch back → Ka0s
  Default, and the picker opens there again. Result: pass (owner-marked 2026-10-30)
- **SKIN-29. Other Ka0s addons unchanged.** With KickCD on a non-default skin, open two other Ka0s
  addons' settings pages, consoles and HUDs → each looks exactly as before this build. Disable KickCD,
  `/reload` → still unchanged. Result: pass (owner-marked 2026-10-30)

- **SKIN-30. The Font outline (KC-01; LibKa0s v1.82.0, D-06).** General → Skin → under the Font and
  Texture menus and their Reset buttons, a **Font outline** dropdown reads **HUD text only** on a
  profile that never set one (LibKa0s v1.83.0, D-10), and a profile that had stored **All text** still
  reads it. With `/kcd unlock`, on **HUD text only** → the grids', cast bars' and labels' text is
  outlined, and the debug console's and sim panel's text is not. Pick **All text** → both are. Pick
  **Off** → every HUD text loses its
  outline too, live. `/kcd get skin.outline` prints `off`; `/kcd set skin.outline thick` is refused;
  `/kcd set skin.outline all` → outlined again. `/reload` → the mode stays. Tick **Ignore fonts** → the
  dropdown grays and the HUD keeps its outline whatever the mode. Switch profiles → each keeps its own
  mode. Fail: a mode that needs a reload, text outlined under Off, or a mode lost at `/reload`. Result:
- **SKIN-31. From skin on every Font flags menu (KC-01; D-07).** Units > Icons > Annotations > Cooldown
  text, Cast bar > Text > Font (both texts) and Text label > Font → each **Font flags** menu lists
  **From skin** first and shows it on a profile you never changed a flag on. With Font outline **Off**
  → those texts lose their outline; pick **Thick outline** on the cast bar's menu → that bar keeps a
  thick outline under Off, the rest follow the mode. Fail: a menu without From skin, a picked flag that
  follows the mode, or a From skin text that keeps its outline under Off. Result:
- **SKIN-32. The one-time flags step keeps your picks (KC-01; Addendum 01).** Before installing this
  build, on a profile `FlagsA` set Focus's cast-bar Font flags to **Monochrome** (Target's left at
  Outline) and leave a second profile `FlagsB` untouched. Install, log in on `FlagsA` → Target's menu
  shows **From skin**, Focus's still **Monochrome**. Switch to `FlagsB` → every menu on From skin. On
  `FlagsA` pick **Outline** on Target's menu, `/reload` → still **Outline**. Fail: a changed flag moved
  to From skin, or a menu put back on From skin after a reload. Result:
- **SKIN-33. `/kcd skin` (KC-01; D-16).** On a profile that has closed the skin picker, `/kcd help` → a
  `skin` row right after `config`, "Choose a skin: open the skin picker". `/kcd skin` → the picker a
  new profile shows opens (**Choose a skin**, **Ka0s KickCD** above the dropdown); a pick previews on
  the HUD, **Apply** saves, the close mark puts the skin back. In combat, `/kcd skin` twice → no picker
  and a gray line each time. Out of combat `/kcd disable`, then `/kcd skin` → one tagged line naming
  `/kcd enable` and no picker; `/kcd enable` after. Fail: "unknown command", a picker in combat or while
  disabled, or a single gray line for two tries. Result:
- **SKIN-34. HUD text is as wide in every skin (KC-01; D-08, D-09).** With `/kcd unlock` and every **Use
  the skin's font** box ticked, note how wide the cast bar's spell name, the countdown and the
  "Target" label read under **Ka0s Default**, then pick **Obsidian**, **Glass** and **WoW Forever** → the
  same strings take about the same width in each (Obsidian's text a point larger, Glass's and WoW
  Forever's a little smaller), and `/kcd get units.target.castbar.fontSize` prints the size you set.
  Untick the cast bar's box → under Obsidian it draws your font at your stored size. Fail: a text
  clearly wider or narrower than under Ka0s Default, or a stored size that changed. Result:
- **SKIN-35. The width parity of this addon's windows and strips (KC-01; D-08, D-12).** Under each of
  the nine skins with Font outline **All text**: the debug console (`/kcd debug`), its copy window, the
  sim step panel (`/kcd sim start pull`, then `/kcd sim stop`), the perf panel (`/kcd perf`) and the
  unlocked drag strips ("Ka0s KickCD — Target", "— Focus" and both cast bars) → no title, button label,
  row or strip title cut off or overrunning its frame, and each strip as wide as its title plus its
  help mark. Fail: an ellipsis or a clipped letter anywhere, or a strip whose title is cut short.
  Result:

- **SKIN-36. Your own HUD fonts come back (KC-03; D-15).** Before installing this build, on a profile
  `KeepA` on Ka0s Default, give Target's label the font **Ka0s Kait** (or any face from a media pack),
  Focus's cast bar **Arial Narrow**, and leave Target's cast bar and countdown at their defaults; check
  that each **Use the skin's font** box is ticked (they draw the skin's face). Install, log in on
  `KeepA` → the label draws in Kait and Focus's cast bar in Arial Narrow, each with its box unticked;
  Target's cast bar and countdown still follow the skin (boxes ticked, Prototype). Pick **Obsidian** →
  the two picked texts keep their faces and sizes; the others turn Expressway. Tick the label's box
  again, `/reload` and switch profiles back and forth → it stays ticked. A second profile `KeepB` with
  a picked face is changed the same way the first time it loads. Fail: a picked face still drawing the
  skin's font after the upgrade, a default text taken off the skin, or a re-ticked box unticked again.
  Result:

## Non-English client

A client set to a non-English locale; frFR is the reported case (issue #8), and an Elemental Shaman
reproduces it exactly.

- **LOC-1. The grid populates.** Log in on a fresh profile → the grid fills with the spec's default
  spells. The original bug was an empty grid with no error. Result: pass (owner-marked 2026-10-10)
- **LOC-2. `/kcd debug spells` speaks tokens.** → the English spec token beside the numeric id,
  `class=SHAMAN spec=ELEMENTAL (262)`, on every locale. Result: pass (owner-marked 2026-10-10)
- **LOC-3. The rebuild line.** Debug on → the `[Cooldowns] rebuild` line reads
  `SHAMAN(7) ELEMENTAL(262): N watched (...); M skipped (...)`, tokens and ids, not localized names.
  Result: pass (owner-marked 2026-10-10)
- **LOC-4. Both spec forms resolve.** `/kcd spells add 51490 ELEMENTAL` and
  `/kcd spells add 51490 Élémentaire` → the same list; the output echoes the English token. Result: pass (owner-marked 2026-10-10)
- **LOC-5. The page shows the client's names.** Settings → Spells → spec names in the client's language
  (`Élémentaire`) while the store holds `[262]`. Result: pass (owner-marked 2026-10-10)
- **LOC-6. The spec-key upgrade, per profile.** Log in with a `KickCDDB` saved by v1.2.0 or earlier with
  customized spell lists, `/reload`, inspect it → numeric spec keys, your entries intact under them.
  Switch to a second profile and check again → rekeyed too (the rekey runs on each profile as it is
  activated). Result: pass (owner-marked 2026-10-10)
- **LOC-7. The name cap counts characters (KC-02).** On a client whose spell names carry accents or a
  non-Latin script (French, Russian, Korean, Chinese), `/kcd set units.target.castbar.nameTruncate 4`
  and target a caster → the bar's spell name shows exactly four characters and a trailing `…`, with
  no broken glyph or box at the cut; a name of four characters or fewer shows whole, with no `…`.
  `/kcd reset units.target.castbar.nameTruncate` → the full name again. Result: pass (owner-marked 2026-10-10)

## Pending sign-off

On 2026-10-10 the owner marked every check in this file as passed, recorded on its `Result:` line as
`pass (owner-marked 2026-10-10)`; a check that already carried a dated owner pass keeps it. A check
added or rewritten after that date is listed here until its `Result:` line records a pass. Sign one
off on its own `Result:` line, then remove its row here.

On 2026-10-24 the owner reported that every check of the keybindings, settings layout and frame
layering run passed (LAYER-1 – 9 and PANEL-31 – 36), recorded on each one's `Result:` line as
`pass (owner, 2026-10-24)`. None was owed after that run.

On 2026-10-30 the owner reported that every check of the skinning rollout (KC-01 to KC-05 of
Ka0sAddonsCommonTasks `docs/2026-10-29-SKINNING_ROLLOUT/`), the skin overrides and the skin library
follow-ups (KC-RV to KC-02 of `docs/2026-10-30-SKIN_LIBRARY_FOLLOWUPS/`, LibKa0s v1.81.0) passed:
SKIN-1 – 29, DEGRADED-16, DIAG-20, PANEL-31 and PANEL-33 – 35, each recorded on its `Result:` line as
`pass (owner-marked 2026-10-30)`. None is owed after those runs.

LibKa0s v1.82.0 (KC-01 to KC-03 of `docs/2026-10-30-SKIN_FONTS_AND_FEEDBACK/`) re-opens SKIN-1, SKIN-2,
SKIN-6 and SKIN-9 (their expected faces moved: Prototype for Oxanium, Expressway for Inter), SKIN-11
and SIM-12 (the sim strip was removed, KC-02), and adds SKIN-30 – 36 and SIM-13; LAYER-7 is retired. Each is owed until its `Result:` line records a pass.

LibKa0s v1.83.0 (KC-F01 of `docs/2026-10-31-FONT_PICKERS_AND_SKIN_FACES/`) re-opens SKIN-4, SKIN-12 and
SKIN-13 (the rows read *Skin's default (X)*, and an override of a shipped face scales), and its new
faces, sizes and outline default fall on SKIN-6, SKIN-30, SKIN-34 and SKIN-35, already owed above.
