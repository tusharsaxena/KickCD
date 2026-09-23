# 02 - Candidates

`revendor-libka0s` Step 5, for the v1.54.2 -> v1.55.0 re-vendor recorded in `01_DELTA.md`.

Sources, in the playbook's order:

- `git -C ../LibKa0s log --oneline v1.54.2..v1.55.0`, and the `CHANGELOG.md` block `## v1.55.0 - 2026-09-23`
  (`../LibKa0s/CHANGELOG.md:13`).
- The API documents of the three new majors: `../LibKa0s/docs/api/Compat/version-1-docs.md`,
  `docs/api/Bus/version-1-docs.md`, `docs/api/Schema/version-1-docs.md`. No existing major's minor
  moved (`01_DELTA.md` 3c), so there is no old/new pair of documents to diff for a consumed major.
- The three design specs' per-consumer adoption deltas, which the orchestrator named as the candidate
  source for this run (`Ka0sAddonsCommonTasks/docs/2026-09-22-SUITE_STANDARDS_AND_LIBKA0S_SWEEP/3b-specs/`):
  `compat.md` section 8 (8.0 common, 8.2 KickCD), `bus.md` section 12 (common block, "Catalog only" KickCD),
  `schema.md` section 11 (common block; KickCD is not among the nine adopters it lists).

Prior declines: `gh issue list --search "LibKa0s" --state all` returns no Compat, Bus or Schema issue
(the two LibKa0s declines on file are #12 Widgets and #14 Item). `grep -rn 'LibKa0s' docs --include='*.md'`
filtered for `declin|not adopt|exempt` finds no recorded refusal of any of the three majors. Nothing is
settled; every candidate below is open.

## Class A - delivered by the copy (not offered)

- **Test kit revision 25.** The layout-section-1 cap census gate (`tests/_kit/test_layout_cap.lua`), the
  `.gitattributes` body case in `test_eol`, the (basename, directory) suite-declaration key with
  shadow and unreferenced reporting, and the commit SHA in the automated-test record. Wired and green
  in the re-vendor commit 523d05a (`01_DELTA.md`, Phase 5 report). Nothing further is owed.
- **The three new library files load.** `libs/LibKa0s/{Compat,Bus,Schema}.lua` arrive through
  `LibKa0s.xml`, which `tests/run.lua:53` derives the load list from (`Loader.xmlFiles`), so the harness
  loads them with no edit (compat.md 8.0: KickCD is one of the deriving hosts).

## Class B - host change required

None. The v1.55.0 block changes no existing `.lua` file in the payload
(`../LibKa0s/CHANGELOG.md:13-18`), so no consumed major gained a descriptor field, a member or a row type.

## Class C - whole-module adoption (three candidates)

`01_DELTA.md` 3e: the addon resolves Core, Env, Lifecycle, Pool, Media, DebugLog, Launcher, Perf, Slash,
Options and Widgets, and none of Compat, Bus or Schema. KickCD ships its own copy of each concern, so
**all three replace host code** rather than adding to it.

### C1. `LibKa0s-Compat-1.0` - route the spell/spec readers and the secret guard through the major

- **What.** Wire `NS.Compat.GetSpellCooldown`, `GetSpellTexture`, `GetSpellInfo`, `GetSpecialization`,
  `GetSpecializationInfo` to the library's members, and add the missing secret seam `NS.Compat.IsSecret`
  wired from the major with the guard stub. Replace every inline `_G.issecretvalue(` call with it.
- **Evidence.** `3b-specs/compat.md:465-485` (8.2 KickCD); the member contracts
  `../LibKa0s/docs/api/Compat/version-1-docs.md:137-242` (Degradation, how a host wires it, the gate);
  `libs/LibKa0s/Compat.lua:162-297`. The spec's measurement of 12 inline calls holds today:
  `grep -rn '_G\.issecretvalue(' core modules settings defaults | wc -l` -> 12 (`core/Compat.lua:86, 380, 393`,
  `modules/Castbar_Debug.lua:95`, `modules/IconGrid.lua:334, 1186`, `modules/Cooldowns.lua:122, 251, 252,
  289, 290`, `modules/Castbar.lua:303`).
- **Files.** `core/Compat.lua`; `modules/{Cooldowns,IconGrid,Castbar,Castbar_Debug}.lua`;
  `tests/test_compat_api.lua`, `tests/test_compat.lua`, `tests/test_surface_parity.lua`, `tests/run.lua`
  (surface-source row); `docs/compat-layer.md`, `docs/ARCHITECTURE.md`.
- **Behavior changes the spec names** (all on rungs a 12.x client does not take, or on bad input):
  legacy `GetSpellCooldown` reads `isEnabled == 0` as disabled (J6); legacy `GetSpellInfo` drops the rank
  instead of reporting it as the icon (row 4); `GetSpellTexture` returns exactly one value;
  `GetSpecializationInfo(nil)` answers nil without calling the client (J12). A LibKa0s-absent load now
  answers the readers' absent values instead of calling the client (reader arm).
- **Recommendation: adopt.** It closes a recorded gap (C2-F04, "no seam at all" for the secret test,
  `compat.md:36-39`), deletes 76 lines of duplicated ladder (`compat.md:19`), and no live caller reads a
  return the change moves (`compat.md:470-476`).
- **Blast radius: replaces host code.** Five function bodies and twelve call expressions move; every call
  site keeps calling `NS.Compat.X`.

### C2. `LibKa0s-Bus-1.0` - declare-once message table, PascalCase wire names, `Catalog`

- **What.** Declare `NS.MSG` for the five messages and sweep the literal call sites onto it (the
  `architecture-section-4` declare-once MUST); then rename the wire strings to PascalCase in that one table
  (naming-cheatsheet, `<Event>` is PascalCase, MUST) and wrap it in `Bus.Catalog`. The factory
  `NS.NewBusTarget` (`core/KickCD.lua:46-52`) and the AceAddon-module receivers stay; no tracked record.
- **Evidence.** `3b-specs/bus.md:628-636` (KickCD, "Catalog only", sequenced: constants first, rename
  second); `../LibKa0s/docs/api/Bus/version-1-docs.md` section `Catalog` (`:184-221`);
  `libs/LibKa0s/Bus.lua` `lib.Catalog`. The spec's measurement holds:
  `grep -rn 'Message("Ka0s_KickCD_' core modules settings | wc -l` -> 23 lines across 8 files
  (`grep -rln ... | wc -l` -> 8). The test tree types the literal on 30 lines across 10 files
  (`grep -rn '"Ka0s_KickCD_' tests/*.lua | wc -l` -> 30).
- **Files.** `core/Constants.lua` (the table's home: KickCD has no `core/Bus.lua`, `architecture-section-4`);
  `core/{Database,State}.lua`, `modules/{Cooldowns,IconGrid,UnitLabel,Castbar}.lua`,
  `settings/{Panel,Spells}.lua`; ten test files; `docs/ARCHITECTURE.md` `## Message bus`,
  `docs/message-bus.md` and the live docs that name a wire string.
- **Recommendation: adopt**, as two commits inside the one candidate because the spec sequences it
  (`Catalog` refuses a SCREAMING_SNAKE suffix, so the wrap cannot land before the rename). It closes a
  recorded gap (debt row 9+13; the declare-once MUST is unmet today).
- **Blast radius: replaces host code** (23 literals become constant reads). No player-visible change: the
  wire strings are internal to KickCD and nothing outside the addon registers for them
  (`grep -rln 'Ka0s_KickCD_' --include='*.lua' .` from the collection root, KickCD excluded, finds one
  file, `LibKa0s/tests/test_bus.lua:123`, a `Catalog` refusal fixture and not a listener).

### C3. `LibKa0s-Schema-1.0` - the settings schema runtime

- **What.** Replace the host's schema runtime in `settings/Panel.lua` (path resolver `Resolve` `:53`,
  `Helpers.Get` `:125`, `sameValue` `:239`, bulk bracket `:251-333`, `Helpers.Set` `:380`,
  `Helpers.ValidateSchema` `:500`) with a `LibKa0s-Schema-1.0` instance.
- **Evidence.** `3b-specs/schema.md:465-603` lists nine adopters (AbsorbTracker, PartyFrameEnhanced,
  AuraMaster, MultiMeters, BankLedger, LootHistory, PanelMaster, PrettyChat, WhatGroup) and prescribes no
  KickCD delta; its survey (`schema.md:6-15`) did not read KickCD. The common block
  (`schema.md:467-482`) binds the descriptors to the instance directly **only when the host has no pre-seam
  gate**, and KickCD's `Helpers.Set(path, section, value)` carries a section argument the library's `Set`
  does not take, a session/global special-path table in front of the write (`settings/Panel.lua:73-122`,
  `:386-395`) and the master-switch hook taken in the same turn as the write (`:417`).
- **Recommendation: decline, not now.** There is no spec delta to apply, and working out one is a design
  survey this run was not given. Worth doing later: it is duplication the major was built to end.
- **Blast radius: would replace host code** (the whole write seam of every setting).

## Order (rule 4: live defect, then recorded gap, then new capability; smallest blast radius first)

No candidate fixes a live defect: the Compat corrections sit on legacy rungs a 12.x client never takes
(`compat.md:122-133`). C1 and C2 both close a recorded gap; C1 is the smaller (one core file, four
modules, no wire change), so it goes first. C3 is declined without an attempt, because there is no
prescribed delta to attempt.
