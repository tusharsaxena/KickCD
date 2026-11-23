# Seed validation: Ka0s KickCD

The seed-validation contract `/dev-copilot:validate-seeds KickCD <flavor>` runs. The command supplies
the loop (clean tree, one date, status, derive, rule, apply, gate, hand-back) and its standing rules.
This file supplies KickCD's procedure: the tool, the files it writes, the precedent a ruling follows
and the gate. The headings below are the interface the command reads, so keep their names.

The seed is `defaults/Spells.lua`: per class and spec (numeric spec ids through `Const.SPEC`) the
default cast-stopper lists, `{ spellID, category, enabled }`, plus `NS.RaceCastStoppers`. It is
curated by hand from the community sheet its header names, and the tool re-checks it against one
pinned build of the client's own DB2 tables on wago.tools (Ka0s WoW Addon Standard `clients-§10`).
Each run ends in a frozen bundle under `docs/seed-research/`. The tool's own documentation is its
module docstring, `tools/seeds/seeds.py`. The first run is `docs/seed-research/2026-11-15-retail/`
(KickCD#39).

## Flavors

| Flavor | Source | Seed files | Tools |
| --- | --- | --- | --- |
| `retail` | wago.tools product `wow` (Retail live) | `defaults/Spells.lua` (hand-curated, tool-checked) | `tools/seeds/seeds.py` |
| `forever` | wago.tools product `wowf` (WoW Forever) | `defaults/Spells_Forever.lua` (tool-written, hand-ordered) | `tools/seeds/seeds.py --flavor forever` (`tools/seeds/forever.py`) |

The Forever lists are derived from product `wowf` on their own, never by filtering Retail's
(`clients-§5`): id 99 is Demoralizing Roar on Forever, 23920 is unlearnable and 19647 is only rank 2
of Spell Lock. Each flavor has its own rulings file (`tools/seeds/rulings_<flavor>.json`) and its
own bundles (`docs/seed-research/<date>-<flavor>/`), and every command takes `--flavor`
(`retail` by default). The first Forever run is `docs/seed-research/2026-11-23-forever/` (the
Forever port, MKF-KC-07).

## Rules

- **What KickCD needs is the cast's id.** KickCD tracks the cooldown of a spell the player (or the
  player's pet) casts: `core/Compat.lua`'s `IsSpellAvailable` asks `C_SpellBook` (the player's
  bank, then the pet's) about the seeded id, and `modules/Cooldowns.lua` polls
  `C_Spell.GetSpellCooldown` on it. So an aura id, or the id of a spell a cast triggers, is wrong
  in this file even when it names the right ability. This is the opposite of an aura tracker.
- **The tool writes what a run rules; curation stays by hand.** In a run, only `seeds.py apply`
  changes the lists: it inserts accepted candidates and removes ids whose flag was ruled `remove`,
  and never changes a category or a comment. Syncing the lists to the sheet stays the hand recipe in
  `docs/common-tasks.md` (*Add a tracked spell*), and the next run checks what it added. A run may
  also fix by hand a comment the `renamed` flag shows is stale, and the re-validation note in the
  file's header (below).
- **Rulings are data.** They live in `tools/seeds/rulings_<flavor>.json` (`rulings_retail.json`,
  `rulings_forever.json`), written only by `seeds.py rule`. A candidate is keyed `<CLASS>:<specID>:<id>`, a flag
  `shipped:<kind>:<CLASS>:<specID>:<id>` (a racial: `shipped:<kind>:RACE:<Race>:<id>`), never by
  build. A ruling holds until the thing it ruled on stops being proposed, and stays in the file as
  provenance after.
- **Precedent, in this order, never re-litigated:**
  1. a ruling already in the flavor's rulings file;
  2. the header of `defaults/Spells.lua`: index 1 is the primary interrupt (or, where the class has
     no kick, the spec's best cast-stopping CC); indices 2..N are **PvE-biased** secondary
     cast-stoppers in priority order; the categories are the closed set; the source is the sheet's
     columns Q, S, T, U, V and X, and columns R (dispels) and W (AoE slows) are excluded because
     neither stops a cast;
  3. the comments beside each entry (a talent, a hero tree, a pet, a replacement);
  4. `docs/scope.md`'s *Default spell coverage*;
  5. the `architecture-§5` row in `docs/ARCHITECTURE.md`: `category` is informational only (it
     drives no rendering, filtering or ordering), so a category that disagrees with DB2 is never
     urgent.
- **What "accept" means here.**
  - An **interrupt** (effect 68) that a spec reaches and its list lacks may be accepted on the
    data. The header admits interrupts without curation.
  - A **cast-stopping CC** candidate is a curation call. The header leaves the choice to the sheet
    and its PvE bias, so a CC candidate is rejected as `needs owner review: <why>` unless it
    corrects an id the list already ships for the same ability (for example the cast id in place of
    the aura id it applies).
  - A **flag** on an id no spec learns is ruled `remove` only when a replacement id for the same
    ability is accepted in the same run. Otherwise it is `keep`, with `needs owner review: <why>`.
    An id the player does not know is hidden in game (`IsSpellAvailable`), so a stale id costs
    nothing, and a wrongly removed one loses a tracked spell.
- **What to reject.** Self or ally movement (Disengage, Leap of Faith), cosmetic variants and ranks
  of an id already shipped (one id per ability), damage cooldowns whose CC is incidental, and
  anything the header excludes (dispels, slows, roots).
- **Evidence.** Each candidate and flag carries its own evidence in the bundle's `candidates.json`:
  the reach source (class skill line, spec spell, talent node, pet, PvP talent, racial line), the
  effects and mechanics on the id and its `EffectTriggerSpell` closure, and the same-family name
  bridge. The raw tables are in the bundle's `raw/`. DB2 says what a spec can learn, not what a
  player takes; when a ruling turns on what players do, say the evidence is thin.
- **Privacy.** No player name, realm or GUID goes into a bundle, a ruling or a commit.

## Flavor: retail

### Status

```sh
python3 tools/seeds/seeds.py status --flavor retail
```

Prints `CURRENT <build> (<bundle>)`, or `NEW <build> (last ruled <build>, <bundle>)`.

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor retail --bundle docs/seed-research/<date>-retail --date <date> --build <build>
```

It downloads 22 tables (about 75 MB on a new build, cached in the git-ignored
`tools/seeds/.cache/`), freezes them gzipped into the bundle's `raw/` (about 12 MB), and writes
`SOURCES.md` and `candidates.json`. It stops when the build has no class skill line for a class, or
when a `Const.SPEC` id is not that class's specialization on the build. `--replay` re-derives from
the bundle's `raw/` alone. Report the flag counts by kind, the candidate counts by group, and the
unruled count.

### Rule

```sh
python3 tools/seeds/seeds.py check --bundle docs/seed-research/<date>-retail
python3 tools/seeds/seeds.py rule --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-retail
```

`check` lists every unruled key and exits 1 while there is one. It must print `OK` after `rule`.

- **Candidates** (`accept` or `reject`):
  - `interrupt`: effect 68 on the cast or its trigger closure, a cooldown, reached by the spec in
    PvE (class line, spec spell, visible talent node or the spec's pet);
  - `cc`: a stun, incapacitate, fear, silence, knockback or pull on the same terms. A root is never
    proposed;
  - `hand`: `HAND_CANDIDATES` in `seeds.py`, each with its reason, for a cast whose effect DB2 links
    only through a server script.

  An accepted candidate goes into the place of a removed entry of the same name in the same list,
  else an interrupt after the interrupts the list leads with, else at the end.
- **Flags** (`keep` or `remove`; a `primary` flag is `keep` only, since the fix is a reorder by
  hand):
  - `unnamed`: the build has no such spell. Remove it unless the comment records why it ships.
  - `renamed`: check what the id is now. The same spell: fix the comment by hand. A reused id:
    remove it.
  - `unreachable`: no class line, spec spell, visible talent node, pet, PvP talent or racial line
    gives the spec this id. Follow the rule above: remove only with a replacement.
  - `category` and `no-evidence`: DB2 disagrees with the shipped category, or shows nothing (a
    server script, an area trigger or a summoned totem does the work). Keep, saying which.
  - `primary`: index 1 is not an interrupt although the spec reaches one.

### Apply

```sh
python3 tools/seeds/seeds.py report --bundle docs/seed-research/<date>-retail --date <date>
python3 tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-retail --date <date>
```

`report` comes before `apply`: once an id is applied a re-derive no longer proposes it, so
`RULINGS.md` has to be written while the candidates still include it. `apply` refuses while anything
is unruled and keeps the file's CRLF endings and column layout. A second `apply` changes nothing.

### After

- Roll the `Re-validated against` note in the header of `defaults/Spells.lua` to the build and date.
- Write the bundle's `ANALYSIS.md` by hand, in the 2026-11-15 bundle's shape: what changed between
  the builds, what was proposed, accepted and rejected and why, and what a later run should
  re-check.
- Add a check per changed list to `docs/smoke-tests.md`'s SPELLS section, and its *Pending sign-off*
  note, following SPELLS-17 and SPELLS-18. A run that changes no list adds none.
- Re-resolve any `defaults/Spells.lua` citation the docs suite flags.

### Stage

`defaults/Spells.lua`, `tools/seeds/rulings_retail.json`, `docs/seed-research/<date>-retail`,
`docs/smoke-tests.md`, plus any `tools/seeds/` or citation edits. Commit message:
`Seeds (retail): re-validated against <build> (<date>)`.

## Flavor: forever

The seed is `defaults/Spells_Forever.lua`: `NS.DefaultSpellsForever[CLASS][Const.SPEC_FOREVER.<CLASS>]`,
the same entry shape and closed categories as `defaults/Spells.lua`, and
`NS.RaceCastStoppersForever`. Forever reports one specialization per class (1482, 1484-1491), so
there is one list per class (owner ruling R6 of 2026-11-23), and the `Const.SPEC_FOREVER` alias is
the class token (`[SPEC.WARRIOR]`). The reach model, the rank folding and the hand candidates are
`tools/seeds/forever.py`'s module docstring. What differs from Retail:

- **Reach is per class.** wago.tools serves no `SpecializationSpells`, `SpecSetMember`,
  `TraitNodeXTraitCond`, `TraitTreeLoadout` or `PvpTalent` rows for `wowf`. A class reaches a spell
  on a talent-tree skill line `SkillRaceClassInfo` gives it alone, through a `SkillLineAbility` row
  whose `AcquireMethod` is not 3 (never learned: the rune grants and same-name clones), through its
  trait tree (`SkillLineXTraitTree`), or through a pet in `forever.PET_LINES`.
- **One candidate per rank family.** Every rank is its own id. A spec's candidates fold by name
  into one, keyed by its `Rank 1` id, carrying `ranks`; a family any rank of which the list ships
  is not proposed. Ship the rank-1 id, one entry per ability.
- **Hand candidates** are `forever.HAND_CANDIDATES`: the core spells with no cooldown, Freezing
  Trap, War Stomp in each class a Tauren plays, and the owner-optional spells no rule proposes, so
  each owner call is a ruling on record. A `racial` hand candidate is reached as a shipped racial is.
- **Order is by hand.** `apply` puts interrupts first, then CC, each in id order. The priority
  order (Pummel first for Warriors, R6) is a reorder by hand after the apply, with no id added or
  removed.

### Status

```sh
python3 tools/seeds/seeds.py status --flavor forever
```

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor forever --bundle docs/seed-research/<date>-forever --date <date> --build <build>
```

It reads the 17 tables `forever.TABLES` names (about 20 MB, cached in `tools/seeds/.cache/`) and
freezes them gzipped into `raw/` (about 1.5 MB). It stops when a class has no talent-tree line, or
when a `Const.SPEC_FOREVER` id is not that class's specialization on the build. `--replay`
re-derives from `raw/` alone.

### Rule

```sh
python3 tools/seeds/seeds.py check --flavor forever --bundle docs/seed-research/<date>-forever
python3 tools/seeds/seeds.py rule --flavor forever --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-forever
```

The candidate and flag kinds, and what accept, reject, keep and remove mean, are Retail's. The
precedent adds, after a ruling already in `rulings_forever.json`: the owner's rulings R6 and R7 of
2026-11-23 (one list per class, Pummel first; the core lists plus Gouge and Intercept) and the
research they rest on (Ka0sAddonsCommonTasks `docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT/`).

### Apply

```sh
python3 tools/seeds/seeds.py report --flavor forever --bundle docs/seed-research/<date>-forever --date <date>
python3 tools/seeds/seeds.py apply  --flavor forever --bundle docs/seed-research/<date>-forever --date <date>
```

An applied entry's comment reads `<name> (DB2 seed <date>)`. Then reorder by hand (above).

### After

- Roll the `Seeded against` note in the header of `defaults/Spells_Forever.lua` to the build and
  date, and write the bundle's `ANALYSIS.md` in the 2026-11-23 bundle's shape.
- Add a check per changed list to `docs/smoke-tests.md`'s SPELLS section.

### Stage

`defaults/Spells_Forever.lua`, `tools/seeds/rulings_forever.json`,
`docs/seed-research/<date>-forever`, `docs/smoke-tests.md`, plus any `tools/seeds/` edits. Commit
message: `Seeds (forever): re-validated against <build> (<date>)`.

## Gate

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
python3 -m unittest discover -s tools/seeds -p 'test_*.py'
```

The first two are `CLAUDE.md`'s green gate: luacheck reports 0 warnings and 0 errors, and the
headless suite 0 failed. The third is the tool's own tests (no network), both flavors' among them
(`test_seeds.py`, `test_forever.py`). A Forever seed run also runs the suite under the kit's forever
profile: `KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua`.

## Notes

- **Reach is per spec.** AuraMaster's join stops at the class. KickCD's lists are per spec, so the
  talent join also reads the CondType 1 spec-set conditions on a node and its node groups
  (`TraitCond`, `TraitNodeXTraitCond`, `TraitNodeGroupXTraitNode`, `TraitNodeGroupXTraitCond`,
  `SpecSetMember`) and the hero selection nodes that offer each hero subtree.
- **Pets are hand data.** No DB2 column ties a pet skill line to a class, so `PET_LINES` in
  `seeds.py` names the warlock and death knight pet lines and the summon that gates each per spec.
  Hunter family lines are left out: a hunter pet carries no interrupt here.
- **PvP talents and racials are reach for flags only**, never a candidate source: the header makes
  the lists PvE-biased, and racials are `NS.RaceCastStoppers`' business. A Dracthyr racial (Wing
  Buffet, Tail Swipe) is reachable for an Evoker this way.
- **What DB2 cannot see.** A server script, an area trigger or a summoned totem is not linked from
  the cast's `SpellEffect` rows. The family bridge (the same name in the same `SpellClassSet`)
  recovers most of them for a shipped id; the rest are `no-evidence` flags, ruled once.
- **Forever's racial lines** are named both `Racial - <race>` and `<race> Racial` (`Tauren
  Racial`); the forever flavor reads both.
- **The shared helper.** The fetch, cache, bundle and rulings shape is copied from AuraMaster's
  `tools/spell-research/`, not imported. Whether it becomes one shared helper is LibKa0s#91.
