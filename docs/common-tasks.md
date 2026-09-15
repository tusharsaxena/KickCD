# Common tasks

Recipes for the changes made most often in this addon, plus the house rules every one of them obeys.
The mid-level architecture — boundaries, the message contract, the Compat-vs-State separation — lives
in [module-map.md](module-map.md), [message-bus.md](message-bus.md) and
[compat-layer.md](compat-layer.md); this file is the "how do I actually do it" page.

The house rules below were `docs/conventions.md` until standard v2.23.0 retired that filename. They
are here rather than in `ARCHITECTURE.md` because every recipe on this page depends on them, and a
rule you have to go to another file to find is a rule that gets broken.

## Recipes

### Add a setting

One row, one file, and everything else follows. A schema row automatically gains `/kcd get`, `/kcd
set`, `/kcd list`, the per-panel **Defaults** button, and the General → **Reset all settings** sweep —
so **do not** write a parallel mutator for a field that already has a row.

1. Pick the panel file under `settings/` that owns the option (`General.lua`, `Icons.lua`,
   `Castbar.lua`, `Label.lua`, `Spells.lua`, `Profiles.lua`).
2. Add one `add{ … }` block: `panel`, `section`, `group`, `path`, `type`, `label`, `desc`, `default`,
   plus `values` for a `string` enum or `min`/`max`/`step` for a number. **`group` is the tab**, and
   the strip is partitioned in declaration order, so put the new row *inside the run of rows that
   group already owns* — a row appended after the array has left its group prints that tab a second
   time further down the page, which is visible only in game. Order within the run is the layout: the
   flow engine pairs consecutive rows two per line, so put a mode beside the thing it modes and rest
   beside hover rather than one above the other.

   **A font, border, bar or color block is COMPOSED, never typed out** (`options-ui-§16`/`§17`) —
   call `H.FontGroup` / `H.BorderGroup` / `H.BarGroup` / `H.ColorPair` and hand the result to
   `H.AddComposed(rows, stamp)`, passing `keys` for any leaf whose stored name this addon already
   shipped, because the composer changes what is *declared* and never what is *stored*. A
   hand-written color row is anti-pattern #73 and reddens `tests/test_schema.lua`, which asserts
   that every `color` row is followed immediately by a `useClassColor*` companion, declares
   `startsLine`, carries the class-color note in its tooltip, and never carries `disabledIf`.

3. Add the `default` to `DEFAULT_PROFILE` in `defaults/Profile.lua` at the matching path. That table
   is the **only** place a profile default is hardcoded (`savedvariables-§2`); the schema row's
   `default` and the profile entry must agree.
4. Add the `label`/`desc` strings to `locales/enUS.lua`, in **pure ASCII** — a glyph the
   settings-panel font does not carry draws as an empty box in game and nothing else ever says so.
5. Update the page → tab → count table in `tests/test_schema.lua` and in
   [settings-panel.md](settings-panel.md). The test fails until you do, which is the point.
6. If the option needs to do something beyond being stored, wire it where the value is read — not in
   the row. Settings writes originating outside `settings/Panel*.lua` route through
   `Helpers.SetAndRefresh(path, value)` so they share the panel's write-notify-refresh path.

### Add a slash command

1. Append an entry to the `COMMANDS` table in `core/KickCD.lua` (around `:156`), shaped
   `{"verb", "One-line description", function(rest) … end}`.
2. The handler takes **`(rest)` only** — everything after the verb, case and internal spacing
   preserved. It does **not** take `self`: `LibKa0s-Slash-1.0`'s dispatcher calls it with the
   remainder alone, and a handler still expecting `self` silently reads the rest of the line as its
   `self` and the argument as `nil`. `tests/test_slash.lua` covers exactly that mistake.
3. Nothing else to plumb. `NS.COMMANDS` is published at `core/KickCD.lua:199` and is the single source
   for both `/kcd help` and the settings panel's command list, so a new verb surfaces in chat **and**
   in the UI.
4. `perf` is a **reserved** verb across the collection (`slash-commands-§2`) and is already registered
   here — do not shadow it.

### Add a tracked spell

`defaults/Spells.lua` holds the per-class-and-spec default cast-stopper lists, seeded by
`Database:BuildSpells()` on first profile creation (see [schema.md](schema.md) for merge semantics).

1. Find the `[CLASS][SPEC.NAME]` list. Class keys are the locale-independent token from `UnitClass()`'s
   second return; spec keys are Blizzard's **numeric** specialization IDs written through the readable
   `Const.SPEC` aliases. Both are locale-invariant on purpose — spec keys were uppercased spec *names*
   once, and a frFR Elemental Shaman derived `"ELEMENTAIRE"`, missed the `"ELEMENTAL"` key and tracked
   nothing at all (issue #8).
2. Index 1 is the primary interrupt (or, where the class has no kick, the spec's best cast-stopping
   CC). Indices 2..N are PvE-biased secondary cast-stoppers in priority order.
3. `category` comes from the closed set: `interrupt`, `stun`, `knockback`, `incapacitate`, `silence`,
   `root`, `fear`, `displace`, `racial`, `other`.
4. An existing profile does **not** pick up the new entry automatically — `/kcd resetall` re-seeds
   every spec's spell list, and that is what a tester needs to run.

### Add a locale string

Add the key to `locales/enUS.lua`. Reference it as `L["…"]` — never a bare literal in panel or chat
code (`localization-§1`).

`tests/test_locale.lua` gates both halves of that, and it is worth knowing which half it gates where.
A key used anywhere the TOC loads and left undefined here is red — that is how three cast-bar `desc`
sentences got reworded at the call site and never added (KICKCD-R-03). A bare prose literal added to a
file under `settings/` is red too, until it is either wrapped or given a class in that file's residue
register. Chat text outside `settings/` — the `/kcd` verbs in `core/KickCD.lua`, the debug dumps — is
still bare English and is **not** gated; the rule above still applies to it, nothing enforces it yet.

### Add a message

Declare it in the emitter's file header, add it to [message-bus.md](message-bus.md) in the same
change, and keep the two in sync. A module that names the messages it emits or listens to and then
drifts from the code is worse than one that names none.

## House rules

### Module file structure

- Module files open with a one-paragraph header explaining the module's job and its message contract.
- Closed-set adherence: a module that names messages it emits or listens to keeps that list in sync
  with the actual code and with [message-bus.md](message-bus.md).

### Saved variables

- Saved variables live under `KickCDDB`; the active profile shape is `DEFAULT_PROFILE` in
  `defaults/Profile.lua` — the only place a profile default is hardcoded (`savedvariables-§2`). New
  persistent fields go in that table, with a comment explaining the shape and any 12.0 secret-value
  caveats. See [schema.md](schema.md).
- Modules read/write `NS.db.profile` directly but treat the schema as defined in `core/Database.lua` —
  the saved-variable boundary is centralized there. The exception is per-unit appearance
  (`icons`/`castbar`): those go through `NS.Units.Icons(unit)` / `NS.Units.Castbar(unit)` so link
  resolution (a linked focus reading target's tables) stays in one place — see `core/Units.lua`.
- Anchor format is fixed: `{ point, relativePoint, x, y }` relative to UIParent. No `relativeTo` frame
  references.

### Frame names

- Global frame names stay literally `KickCD` (see [scope.md](scope.md)): `KickCDIconGrid`,
  `KickCDCastbar`, `KickCDDebugWindow` — no addon-name prefixing games.
- **Deviation recorded as intentional** (per CLAUDE.md's flag-deviations rule): the target/focus
  dual-tracking feature extends this with a `Focus`-suffixed sibling per per-unit frame —
  `KickCDIconGridFocus`, `KickCDCastbarFocus` — rather than breaking the convention. Target keeps the
  exact legacy unsuffixed name (macros and other addons may already reference `KickCDIconGrid` /
  `KickCDCastbar`); focus is unambiguously suffixed rather than using a numeric or generic index,
  since "target" and "focus" are the addon's actual unit vocabulary. A third unit would follow the
  same `KickCD<Widget><UnitTitleCase>` pattern.
- **Deviation recorded as intentional** (extending the note above): the single text-label feature's
  `modules/UnitLabel.lua` follows the same pattern — `KickCDUnitLabelTarget` / `KickCDUnitLabelFocus`.
  Each frame is *created* on `UIParent` (so it exists before any attach frame does), but
  `UnitLabel:Apply` `SetParent`s it onto the unit's **icon grid** (`IconGrid:GetGridFrame(unit)`,
  falling back to the attach frame if the grid isn't up yet) every time it re-anchors, while
  `SetPoint`-ing to the resolved attach frame (the unit's cast bar or icon grid) for position only.
  This is deliberate: parenting onto the grid — not the attach frame — means the label inherits the
  grid's shown state and effective alpha for free, so the label follows the addon's General visibility
  exactly like the grid does, with no separate visibility re-implementation. Parenting onto the cast
  bar instead would make the label cast-gated (the cast bar additionally `:Hide()`s itself whenever
  there is no active cast, independent of the visibility mode) — a real bug this convention fixed:
  with `visibility = Always` and no active cast, a label attached to the cast bar went invisible even
  though the grid was always shown.

### Settings layer

- Settings reads/writes originating outside the settings panel files (`settings/Panel*.lua`) — slash
  commands, keybinds — route through `Helpers.SetAndRefresh(path, value)` so they share the panel
  widgets' write-notify-refresh code path. Direct `db.profile` writes are reserved for places where no
  schema row exists: the frame anchors, named state whose owner (`Units`) and every writer
  [ARCHITECTURE.md](ARCHITECTURE.md#settings-schema) lists, and the profile bootstrap. A new anchor
  writer gets a line in that list.
- New schema rows automatically gain `/kcd get|set|list` coverage, the per-panel Defaults reset, and
  the General → "Reset all settings" reset. Don't add a parallel mutator for a field that already has
  a schema row.
- `Helpers.SetAndRefresh` is defined in `settings/Panel_Render.lua` (peeled from `Panel.lua`), which
  loads after `core/KickCD.lua`. Slash commands firing before `settings/` has loaded (between
  `OnInitialize` and `PLAYER_LOGIN`) hit a fallback path that writes directly to `db.profile` and emits
  `Ka0s_KickCD_CONFIG_CHANGED`. The fallback is intentional; don't reorder the TOC to "fix" it without
  revisiting that path.

### Chat output

- Chat output goes through `Util.print` (or `NS.Util.print`) — never the global `print`, and never
  your own `|cff…KickCD|r:` prefix. `Util.print` prepends the single shared `NS.PREFIX` chat tag (a
  cyan `[KCD]` banner, defined once in `core/Constants.lua`); passing your own produces a double
  banner. Any other chat site that needs the tag references `NS.PREFIX` rather than re-spelling the
  color code. The help printers in `core/KickCD.lua` are the only callers that color anything else
  (yellow for the slash invocation, white for the description).
- **No chat line ends in a trailing `:`** (`slash-commands-§4`). A list is introduced by its header
  text alone — write `configured colors`, not `configured colors:`. The rule covers **every** chat
  line, not just `/kcd help`: diagnostic dump headers in `modules/Castbar_Debug.lua` and
  `core/Compat.lua`'s `DebugInterrupt` are chat lines too, and both files carried violations that two
  separate sweeps missed. A colon *mid*-line (`"name: " .. value`) is fine; the rule is about the last
  character a player reads. Guarded by `tests/test_slash_style.lua` — see
  [testing.md](testing.md#the-source-scan-guard).
- **A chat sink threaded through helpers is a parameter named `emit`, never `print`.** A dump that
  splits across several local helpers passes the sink down rather than each helper reaching for
  `NS.Util.print` again — `modules/Castbar_Debug.lua` does this eight times. Name that parameter
  `emit`, and name the local that resolves it `emit` too. Calling it `print` shadows the Lua global
  inside every one of those functions, so `print(...)` in the body no longer means what a reader
  scanning for `slash-commands-§4` violations assumes it means, and `tests/test_source_style.lua`
  cannot tell the shadow from a bare global read either. `settings/Slash.lua:61`'s `out(line)` is the
  same idea one level up, where the sink is a module-level local rather than an argument.

### 12.0 secret-value rule of thumb

- **Secret numbers.** Operate on `isActive` / `isEnabled` (plain bools) for decisions; pass the
  `cdObject` from `Compat.GetSpellCooldownDuration` opaquely to C methods
  (`SetCooldownFromDurationObject`, `SetFormattedText`, `EvaluateTotalDuration` /
  `EvaluateRemainingDuration`); never bind
  `:GetRemainingDuration()` to a Lua local in combat. Visual decisions that depend on a cooldown's timings
  (the GCD-vs-real-CD filter) live in C-side curves built by `IconGrid.BuildCurves` and applied via
  `SetAlphaFromBoolean` / `SetVertexColor`. That filter reads the cooldown's **total** length, not
  its remaining time — near the end of a real cooldown the two are indistinguishable.
- **Secret bools and strings.** Never compare `UnitCastingInfo.notInterruptible` / `name` / `texture` /
  `spellID` in Lua; either pass straight to a Blizzard C method that accepts secrets
  (`Texture:SetTexture`, `FontString:SetText`, `Frame:SetAlphaFromBoolean`,
  `C_CurveUtil.EvaluateColorValueFromBoolean`) or use `NS.State.IsHostileUnitCasting` for the truthy
  "is something casting" check.
- **Visibility / glow / interruptibility decisions** that depend on `notInterruptible` MUST go through
  the two-step gate (`NS.State.IsHostileUnitCasting` for show + `NS.State.ApplyInterruptibleAlpha` for
  filter; both in `core/State.lua`, not `core/Compat.lua` — these are addon visibility decisions, not
  API normalization). The full pattern catalog is in [midnight-quirks.md](midnight-quirks.md).

### Compat / State / Constants split

- `core/Compat.lua` is API normalization only (spell-info shims, cast-info record building).
- `core/State.lua` owns shared mutable state (the event-driven combat flag) and visibility helpers
  (`IsHostileUnitCasting`, `ApplyInterruptibleAlpha`).
- `core/Constants.lua` owns shared magic numbers under `NS.Const` (`GCD_UPPER`, panel paddings,
  castbar text insets).
- New constants and shared state belong in those namespaces, not as module-local locals duplicated
  across files. **Don't add visibility decisions or shared state to Compat.**

### Lua / runtime

All code is plain Lua 5.1 (WoW's runtime). No external Lua deps beyond vendored Ace3 / LSM /
LibCustomGlow.

### Linting

`luacheck .` must report **0 warnings and 0 errors**. The tree is clean on both counts, so a new
warning is a regression rather than background noise to scroll past — fix the code first, and reach
for a suppression only when the warning is wrong about this file.

**There is no top-level `ignore` in `.luacheckrc`, and none is coming back** (lint.md, `M4-11`).
This page used to describe one — `212/self`, `212/event`, `211/addonName` — and to call it
"allowances true everywhere". They were not true everywhere. `M4c-06` removed the three lines and
`luacheck .` went from 0/0 to **61 warnings**, of which **32 were defects rather than conventions**:
twenty-nine files opening `local addonName, NS = ...` over a folder name they never read, two named
receivers in the test tree, and one `NS.Slash:PrintHelp` forwarder nothing called. All thirty-two
were fixed at source. `212/event`, meanwhile, matched nothing at all — a stale suppression nobody
could tell from a live one while it was switched on everywhere. `tests/test_lintconfig.lua` is the
gate that keeps the blanket out, and it fails rather than skips when it cannot read the config.

Suppressions come in two forms, and the choice between them is about scope:

- **One file → a `files[...]` stanza in `.luacheckrc`.** The key names the single `.lua` file that
  earns the code, and the entry names the code AND the variable, in luacheck's `<code>/<variable>`
  form. Nine stanzas exist today, all `212/self`, all on files whose methods a calling convention
  reaches with the colon — the AceAddon modules, the AceEvent handler registered by name, the
  `LibKa0s-Slash-1.0` degradation stub — and each carries a comment naming the obligation that
  forces the receiver. An argument that falls out of use under any other name, in those nine files
  or in the other 84, still reports. `libs/`,
  `tests/_kit/`, `_dev/`, `docs/audits/` and `docs/reviews/` are excluded from linting outright.
  **The rest of `tests/` is linted** — the suites, `run.lua`, `perf.lua` and `wow_mock.lua` are this
  addon's code and are held to the same gate as `core/`. `tests/_kit/` is the one carve-out inside
  that tree, because it is a byte copy of LibKa0s' `testkit/` and is linted there as source. A run
  reporting fewer files than `luacheck . --formatter plain | tail -1` says today is a run that has
  stopped checking half the Lua in the repo.
- **One line → an inline directive.** Write `-- luacheck: ignore <code>/<name>` immediately above the
  offending line, with a comment saying why the warning doesn't apply. Never the bare
  `-- luacheck: ignore` with no code after it: that silences every warning in scope and is the
  blanket wearing a different hat, which is why `tests/test_lintconfig.lua` scans every tracked
  `.lua` for it. The live example is
  `tests/test_perfsetup.lua`'s `firstWatchedSpell`, which suppresses `512` (loop is executed at most
  once): returning on the first iteration is how you take an arbitrary element of a set in Lua, so
  the warning is right about the control flow and wrong about the intent. The one before it was
  `core/LSMPatch.lua`, which kept the bootstrap header while using neither name half nor `NS` and so
  suppressed `211/NS` locally rather than widening a repo-wide allowance; that file is gone — its
  wrapper is `lib.__PatchLSM30Border()` in LibKa0s now.

Prefer the inline form for anything genuinely local, and prefer FIXING the code to either. An unused
variable is usually a real defect or dead code, and a `542` is usually a missing case — reach for a
stanza only where the code is right as written, and say why beside it.

### Global lookup form

When a Blizzard / WoW global is read, the form depends on the symbol: a standing list always carries
the `_G.` prefix, and outside that list the form follows whether the module guards the symbol.

- **The standing `_G.` list — prefix everywhere, and this half is gated.** `C_Spell`, `C_Timer`,
  `C_CurveUtil`, `issecretvalue`, `InCombatLockdown`, `IsLoggedIn`, `UnitCastingInfo`,
  `UnitChannelInfo`, `UnitCastingDuration`, `UnitChannelDuration`, `UnitExists`, `UnitCanAttack`,
  `UnitName`, `UnitIsDead`, `GameFontNormal`, `STANDARD_TEXT_FONT`, every legacy `GetSpell*` /
  `IsSpell*` / `IsPlayerSpell` / `IsUsableSpell`, `print` (used as a fallback), and the cast-event API
  surface. The `_G.` form makes the "this might not exist" intent obvious and matches
  `core/Compat.lua`. `tests/test_source_style.lua` reads this list and fails on a bare read of any
  name on it — so a name added here must be added there in the same change, and vice versa.
- **Guarded somewhere → `_G.X` everywhere, as guidance.** If a module ever guards a symbol (`if X
  then`, `X and X(...)`, `... or X`), write `_G.X` for **every** reference to that symbol in that
  module, including reads inside the guard's protected block. Applied per module, which is why
  `UnitClass` is `_G.UnitClass` throughout `core/KickCD.lua` and `settings/Spells.lua` (both guard it)
  and bare in `modules/IconGrid.lua`, `modules/Cooldowns.lua` and `core/Database.lua` (none do).
  **Not gated, and the residue is why:** `LibStub`, `Settings`, `GameTooltip`, `Enum`,
  `DEFAULT_CHAT_FRAME`, `C_CooldownViewer` and `RAID_CLASS_COLORS` are all guarded and all bare, at
  roughly seventy sites. Bringing them in is a mechanical sweep with no reader on the other side, so
  the rule binds new and edited code and the standing list above is what the suite measures.
- **Never guarded → bare `X`.** A trusted baseline global the surrounding code does not short-circuit
  on: `UnitClass`, `UnitRace`, `UnitIsUnit`, `CreateFrame`, `Mixin`, `Enum`, `CreateColor`.
- **Spec APIs are wrapped, not read raw.** The deprecated `GetSpecialization` /
  `GetSpecializationInfo` globals route through `NS.Compat.GetSpecialization()` /
  `NS.Compat.GetSpecializationInfo(i)` — no direct calls to the globals remain outside
  `core/Compat.lua`.
- **Same symbol, same form across all reads within a module.** Do not mix `_G.X` and bare `X` for the
  same global. If a change adds a guard for a symbol that is bare today, sweep the module.

### Line endings

CRLF on every tracked text file. The repo's `.gitattributes` enforces `* text=auto eol=crlf`, so git's
smudge filter normalizes on checkout — the working tree should never contain LF-terminated source
files. The tree was normalized in commits `b6b9853` / `a74251a` / `3ba3ca3`. New files should match the
surrounding files in their directory.

### US English

Every word a person wrote in this repository is US English — labels, chat text, comments,
identifiers and Markdown prose alike. `localization-§5` publishes the canonical `BRITISH` /
`ALLOWED` pair, and `tests/test_spelling.lua` carries both lists whole and sweeps everything git
tracks. The rule is not taste. A locale key *is* the English source string (`localization-§1`), so a
British spelling wrapped in `NS.L` is frozen into every translation that derives from it, and
correcting it later orphans the key without a sound.

Four things are out of scope, and each is named in the gate rather than inferred from a pattern:
`libs/` and `tests/_kit/`, which are vendored and not ours to respell; the frozen dated bundles under
`docs/audits/`, `docs/reviews/`, `docs/automated-tests/`, `docs/revendor/` and `docs/perf-analysis/`,
which record what was true on a past day; and the gate's own copy of the lists. One narrower waiver
sits beside them, per file and per word: `docs/smoke-tests.md`'s session-3 perf check quotes two
forbidden spellings in order to tell the reader that a double L in the client means the string did
not come from the vendored payload, so correcting the quote would delete the check.
