# Analysis: Retail seed validation, 2026-11-15 (build 12.1.5.70783)

KickCD#39. The first run of `tools/seeds/seeds.py`. It checks every list in `defaults/Spells.lua`
(the per-class and per-spec cast-stopper defaults, and `NS.RaceCastStoppers`) against the live
Retail build on wago.tools (product `wow`, 12.1.5.70783). Before this run the lists had only ever
been cross-referenced by hand against the community sheet the file's header names. Every flag and
candidate is ruled in `tools/seeds/rulings_retail.json`, and `RULINGS.md` beside this file lists
each one with its reason. The rulings were made by Claude under the contract's conservative rules
(`docs/validate-seeds.md`, `## Rules`): accept only what the data clearly supports and the header
admits, and mark the rest `needs owner review`. They await the owner's review.

## What was checked

| Check | Result |
| --- | --- |
| Shipped entries (distinct ids) | 186 (79): 181 entries in 40 spec lists, and 5 racials |
| Ids the build does not name (`unnamed`) | 0 |
| Names that disagree with the comment (`renamed`) | 0 |
| Ids the spec cannot reach (`unreachable`) | 13 flags on 6 ids |
| Category disagreeing with DB2 (`category`) | 3 flags on one id (Song of Chi-Ji) |
| No cast-stopping evidence at all (`no-evidence`) | 3 (Frostwyrm's Fury, Bull Rush, Arcane Pulse) |
| Index 1 not an interrupt though the spec reaches one (`primary`) | 0 |
| Interrupt candidates (effect 68, reached, with a cooldown, not shipped) | 1 |
| Cast-stopping CC candidates | 58 (55 by rule, 3 hand) |

Five lists do not lead with an interrupt: Balance and Restoration Druid, Holy Paladin, Discipline
and Holy Priest. None of those specs reaches an effect-68 spell with a cooldown in PvE, except
Balance, whose index 1, Solar Beam, is itself the interrupt (effect 68 through 97547).

## What changed in the file

Two abilities were shipped under an id the player never learns on 12.1.5. KickCD polls the cooldown
of the cast (`IsPlayerSpell`, `GetSpellCooldown`), so both were hidden in game. Each is corrected in
place, in the same slot of the same list:

| Lists | Shipped | Now | Why |
| --- | --- | --- | --- |
| Death Knight Frost, Unholy | `108194` Asphyxiate | `221562` Asphyxiate | 108194 has no learn row on the build (no class line, spec spell, talent or PvP talent). 221562 is the Asphyxiate talent every DK spec sees, with the same 45 s stun; Blood already shipped it |
| Paladin Holy, Protection, Retribution | `105421` Blinding Light | `115750` Blinding Light | 105421 is the disorient the spell applies: no cooldown, no learn row. 115750 is the cast (90 s), on every paladin spec's talent tree. DB2 links the two only through the family bridge (the cast carries a dummy effect), so 115750 is a hand candidate in `HAND_CANDIDATES` |

The header of `defaults/Spells.lua` gains a note naming the build, the tool and the rulings file.
Blood's own `221562` line still reads `-- Asphyxiate (Blood)`. The aside is only history now: the
id serves all three specs.

## What was ruled, and why

### Flags: 5 removed (the two corrections above), 14 kept

Kept with `needs owner review`. DB2 shows no way for the spec to learn these ids, but it cannot rule
out what it does not model, and a stale id costs nothing in game (`IsSpellAvailable` hides it):

- **Wailing Arrow `392060`** (Beast Mastery, Marksmanship). Its two TraitDefinitions sit on no
  talent node on 12.1.5. A different id, `355589` Wailing Arrow, is on the Hunter class line with a
  60 s cooldown and a silence; it may be the one the Dark Ranger casts now. Check in game.
- **Repentance `20066`** (all three paladin lists). No learn row of any kind, and no other
  Repentance id a paladin reaches.
- **Silence `15487`** (Discipline). `SpecializationSpells` grants it to Shadow only, and no talent
  node a Discipline priest sees carries it.
- **Psychic Horror `64044`** (Discipline, Shadow). Its TraitDefinition sits on no talent node, and it
  is not a PvP talent.
- **Song of Chi-Ji `198898`** (all three monk lists), a `category` flag. DB2 gives its effect
  (198909) the `asleep` mechanic, an incapacitate, where the file says `fear`. The category is
  informational only (the `architecture-§5` row), so nothing changes until the owner retags it.
- **Arcane Pulse `260364`** (Nightborne). DB2 shows damage and a slow, no cast-stopping effect.

Kept as recorded curation: **Frostwyrm's Fury `279302`** (its stun is the Absolute Zero talent's,
cast through an area trigger, and the comment says so) and **Bull Rush `255654`** (its knockdown
carries no mechanic in DB2).

### Candidates: 5 accepted (the corrections), 54 rejected

- **The one interrupt candidate**, Unholy's `91802` Shambling Rush, is the ghoul's leap in Dark
  Transformation: effect 68 through 91807, but only on that form. Rejected for owner review; the
  Unholy list's interrupt is Mind Freeze.
- **CC the header leaves to the sheet**, rejected for owner review: the ghoul's stuns (Gnaw,
  Monstrous Blow), Turn Evil, Gouge, Dominate Mind, the Sayaad's Seduction, Jailer's Judgment (a
  class-line row and nothing else), Wailing Arrow `355589`, and two abilities a sibling list already
  ships: Supernova for Fire and Frost (Arcane ships it) and Thunderstorm for Enhancement (Elemental
  and Restoration ship it). DB2 shows each node visible to those specs on 12.1.5. Whether the sheet
  wants them is the owner's call.
- **Rejected outright**: 24 cosmetic Hex variants (8 ids in each shaman list; Hex 51514 ships, one
  id per ability), Leap of Faith (it pulls an ally), Clash (a gap closer), and Fists of Fury and
  Summon Infernal (damage cooldowns whose stun is incidental).

## How the tool decides

- **Reach is per spec.** A spec reaches an id through its class skill line, its
  `SpecializationSpells`, a talent node it can see, or a pet it can summon (`PET_LINES`). A node is
  visible to a spec when the spec's loadout carries the tree and no CondType 1 condition on the node
  or its node groups names a spec set without it. A hero node also needs the hero selection node
  that offers its subtree to be visible. PvP talents and racial lines count for flags only.
- **Evidence is the cast's own.** Effect 68 for an interrupt; `SpellCategories.Mechanic` and
  `SpellEffect.EffectMechanic`, named by `SpellMechanic`, for the CC categories; effects 98 and 144
  (knockback) and 124 and 145 (pull) aimed at an enemy. Each is closed over `EffectTriggerSpell` to
  depth 3. For a shipped id only, the family bridge (the same name in the same `SpellClassSet`) adds
  what a server script or an area trigger hides. On this build it confirms 16 shipped ids that
  would otherwise be flagged, among them Skull Bash, Storm Bolt, Shockwave, Maim, Intimidation,
  Solar Beam's silence, the three sigils and Capacitor Totem.
- **A candidate needs a cooldown.** A cooldown tracker has nothing to show for a spell without one,
  and the rule also keeps passive talents out.

## What a later run should re-check

- The owner's calls on the `needs owner review` rulings above. An owner call that changes a list is
  a hand edit (the sheet recipe in `docs/common-tasks.md`) or a changed ruling; either way the next
  run starts from it.
- Wailing Arrow: which of `392060` and `355589` a Dark Ranger casts on the live client.
- Whether Repentance and Psychic Horror return to a talent tree on a later build. If they stay
  gone, the owner may remove them.
- The in-game smoke checks SPELLS-17 and SPELLS-18 (`docs/smoke-tests.md`): the corrected ids show
  and track their cooldowns.
- `PET_LINES` and `HAND_CANDIDATES` are hand data. A new pet line or a changed summon id needs them
  touched, and a hand candidate the build stops naming lands in `candidates.json`'s `handMissing`
  (empty on this build).
