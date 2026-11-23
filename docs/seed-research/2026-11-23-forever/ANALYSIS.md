# Analysis: WoW Forever seed run, 2026-11-23 (build 1.60.1.71037)

The first run of the `forever` flavor of `tools/seeds/seeds.py` (`tools/seeds/forever.py`), for the
WoW Forever port (Ka0sAddonsCommonTasks `docs/2026-11-23-MULTIMETERS_KICKCD_FOREVER_PORT`, items
MKF-KC-07 and MKF-KC-08). There was no Forever list before it: the run derived against
`defaults/Spells_Forever.lua` with nine empty class lists and `NS.RaceCastStoppersForever =
{ Tauren = 20549 }`, so every reachable cast-stopper was a candidate. Every candidate is ruled in
`tools/seeds/rulings_forever.json`, and `RULINGS.md` beside this file lists each with its reason.
The membership calls are the owner's (rulings R6 and R7 of 2026-11-23, in the port's
`00_DESIGN.md`) plus the research's recorded exclusions; Claude wrote them down as data.

## The source

- **Build** 1.60.1.71037, wago.tools product `wowf`, the newest Forever build listed on 2026-11-23.
- **Tables.** The 17 tables in `SOURCES.md`, frozen gzipped in `raw/`. They are the CSVs the
  port's research downloaded from `https://wago.tools/db2/<Table>/csv?build=1.60.1.71037` that day,
  checked against that download's sha256 manifest before this run, and fed to `derive` as its cache;
  `derive --replay` reproduces `candidates.json` and `SOURCES.md` byte for byte from `raw/` alone.
- **Not served for `wowf`:** `SpecializationSpells`, `SpecSetMember`, `TraitNodeXTraitCond`,
  `TraitTreeLoadout` and `PvpTalent` (header-only or "Table not found"), which the Retail reach
  model needs. That is why the flavor has its own (below).

## How the forever flavor reaches a spell

- **One spec per class.** `ChrSpecialization` has one class-named row per class (1482 Mage, 1484
  Druid ... 1491 Warrior) and the pet spec 1493, which is no class's. The three talent trees are
  talent groups with no spec id, so a list is per class (`Const.SPEC_FOREVER`, owner ruling R6).
- **Class lines** are the talent-tree skill lines (`Arms`, `Fury`, `Protection` ...) whose
  `SkillRaceClassInfo.ClassMask` names exactly one Forever class. `Engraving` and `Runes` (masks of
  several classes) and `Mounts` (every class) are never class lines.
- **Learned** means a `SkillLineAbility` row on such a line whose `AcquireMethod` is not 3 (never
  learned). That keeps out every Season of Discovery rune grant the research found: Rebuke 425609,
  Skull Bash 410176, Shockwave 440488, Between the Eyes 400009 and Felguard Intercept 427745, and the
  same-name clones (Earth Shock 408681-408689 and 1220744-1220750, Kick 1775 and 3467).
- **Talents** join `TraitNode` to its class through `SkillLineXTraitTree` (nine trees, one per
  class). The old `Talent` table is not read: it misses Feral Charge 1238122.
- **Pets.** `PET_LINES` (hand data) gives the warlock's lines with their summons. Spell Lock is the
  Felhunter's (summon 691), Seduction the Succubus's (712). The Felguard's summon 427733 has no
  learn row, so its line reaches nothing. No hunter pet line carries an interrupt or a castable
  stop (the research's sweep, `forever-interrupt-data.md` 6).
- **Racials.** Forever names its racial lines both `Racial - <race>` and `<race> Racial`
  (`Tauren Racial` 124). As on Retail they are reach for flags only, never a rule's candidate.
- **Ranks.** Every rank is its own spell id. The flavor folds a spec's candidates into one per
  family (same name), keyed by the `Rank 1` id (`Spell.NameSubtext_lang`), and lists the family's
  `ranks` (the ids with a `Rank N` subtext, so Polymorph's Turtle 28271 and Pig 28272 are not
  ranks). A family any rank of which the list ships is not proposed again. KickCD stores one row
  per ability (`docs/validate-seeds.md`: one id per ability); resolving the highest known rank at
  run time is MKF-KC-09's rank table, whose rank lists these `ranks` match: they agree id for id
  with the research's `forever_seed_proposal.json`.
- **Hand candidates** (`forever.HAND_CANDIDATES`). The rules propose only spells with a cooldown
  and evidence DB2 links to the cast. Owner ruling R7 puts four spells with no cooldown in the core
  lists (Cheap Shot, Polymorph, Fear, Mind Control), Freezing Trap freezes through a game object
  the cast does not link, and War Stomp is a racial. Each is a hand candidate with its reason. The
  research's owner-optional spells that no rule proposes (Holy Wrath, Grounding Totem, Seduction,
  Pounce, Hibernate) are hand candidates too, so that R7's rejection of each is a ruling on record.
  `handMissing` is empty: the build names every hand id and the class reaches it.

## What was proposed: 41 candidates, 31 accepted, 10 rejected

7 interrupt candidates (Pummel, Shield Bash, Kick, Earth Shock, Counterspell, Spell Lock, Feral
Charge), all accepted: they are every interrupt a Forever class reaches. 34 CC candidates: 24
accepted, 10 rejected.

Accepted, by class (the list order is the next section's):

| Class | Accepted |
| --- | --- |
| Warrior | Pummel 6552, Shield Bash 72, Concussion Blow 12809, Intimidating Shout 5246, Intercept 20252, War Stomp 20549 |
| Paladin | Hammer of Justice 853, Repentance 20066 |
| Hunter | Scatter Shot 19503, Intimidation 19577, Freezing Trap 1499, War Stomp 20549 |
| Rogue | Kick 1766, Kidney Shot 408, Cheap Shot 1833, Blind 2094, Gouge 1776 |
| Priest | Silence 15487, Psychic Scream 8122, Mind Control 605 |
| Shaman | Earth Shock 8042, War Stomp 20549 |
| Mage | Counterspell 2139, Polymorph 118 |
| Warlock | Spell Lock 19244, Death Coil 6789, Howl of Terror 5484, Fear 5782 |
| Druid | Feral Charge 1238122, Bash 5211, War Stomp 20549 |

This is the research's core list (`forever-interrupt-data.md` 7) plus Gouge and Intercept (owner
ruling R7), plus War Stomp in the four classes a Tauren plays (critic L1: `Database:BuildSpells`
appends the player's racial to the profile creator's class only, so a shared Default profile would
give no other Tauren character War Stomp; the known filter hides it from a non-Tauren).

Rejected:

- **Owner-optional, not in R7:** Holy Wrath, Scare Beast, Confounding Flash, Grounding Totem,
  Seduction, Pounce, Hibernate.
- **Charge** 100: a stun by its trigger, but it cannot be cast in combat.
- **Turn Undead** 2878: one creature type, like Shackle Undead and Banish, which the research
  excluded as hard CC.
- **Ice Block** 11958: its freeze mechanic is on the mage.

No flag was raised: the lists were empty, and Tauren's War Stomp is on the Tauren racial line.

## The lists after `apply`, and the hand reorder

`apply` writes accepted candidates into their class's list, interrupts first, then CC, each group
in id order. Priority order is curation by hand (the contract: a `primary` flag is fixed by a
reorder by hand), so MKF-KC-08 reorders each list after the apply, with no id added or removed:
Pummel first for Warriors (owner ruling R6), then the research's core order, then Gouge and
Intercept, then War Stomp last. The categories stay what the tool proposed except where the
research's proposal names another in the closed set (`category` is informational only, the
`architecture-§5` row).

## What a later run should re-check

- **In game.** None of these ids has been cast on Forever by KickCD. The port's smoke sheet carries
  the checks. In particular: Feral Charge interrupts in bear forms only (the cat override 414924 is
  a leap with no interrupt, factcheck A); Silence's 3 s lockout 1241057 is linked by a server
  script; Pummel and Shield Bash share cooldown category 88; Earth Shock shares 19 with Flame and
  Frost Shock.
- **Ranks.** Whether a superseded rank stays known (`C_SpellBook.IsSpellKnown(1766)` after Kick
  rank 2) is UNKNOWN; the rank table must not assume either answer.
- **The reach model** is new. A later build that serves `TraitTreeLoadout` or spec rows, or a
  class that gains a second spec, needs `forever.py` revisited: the `derive` stops when a class has
  no talent-tree line, and a `Const.SPEC_FOREVER` id that is not its class's spec stops it too.
- **Hand data.** `PET_LINES` and `HAND_CANDIDATES` are hand data; a hand id the build stops naming
  lands in `handMissing`.
- **Runes.** Excluded by `AcquireMethod` 3. If Forever ever engraves again, Rebuke 425609 and Skull
  Bash 410176 become reachable interrupts and a later run proposes them.
