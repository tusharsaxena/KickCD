# Sources: WoW Forever seed validation, 2026-11-23

Written by `tools/seeds/seeds.py derive`. Frozen: never edited after the run, apart from the hand-written `ANALYSIS.md` beside it.

| Field | Value |
| --- | --- |
| Client | `forever` (wago.tools product `wowf`) |
| Build | `1.60.1.71037` |
| Run date | 2026-11-23 (the run's `--date` argument; the tool never reads the clock) |
| Builds API | <https://wago.tools/api/builds> |
| User-Agent | `KickCD-seed-validation/1.0 (+https://github.com/tusharsaxena/KickCD)` |
| Seed file | `defaults/Spells_Forever.lua`: 1 entries, 1 distinct ids |

## Tables

| Table | Why | URL |
| --- | --- | --- |
| `SpellName` | names: the `unnamed` and `renamed` flags, the rank families, every report row | <https://wago.tools/db2/SpellName/csv?build=1.60.1.71037> |
| `Spell` | NameSubtext_lang: the `Rank 1` subtext that names a family's first rank | <https://wago.tools/db2/Spell/csv?build=1.60.1.71037> |
| `SpellEffect` | Effect 68 INTERRUPT_CAST, EffectMechanic, knockback and pull effects, EffectTriggerSpell for the closure | <https://wago.tools/db2/SpellEffect/csv?build=1.60.1.71037> |
| `SpellCategories` | spell-level Mechanic, and ChargeCategory for a charged cooldown | <https://wago.tools/db2/SpellCategories/csv?build=1.60.1.71037> |
| `SpellMechanic` | mechanic id -> name, the table MECHANIC_CATEGORIES is written against | <https://wago.tools/db2/SpellMechanic/csv?build=1.60.1.71037> |
| `SpellCooldowns` | RecoveryTime / CategoryRecoveryTime: a candidate needs a cooldown | <https://wago.tools/db2/SpellCooldowns/csv?build=1.60.1.71037> |
| `SpellCategory` | ChargeRecoveryTime of a charged spell | <https://wago.tools/db2/SpellCategory/csv?build=1.60.1.71037> |
| `SpellClassOptions` | SpellClassSet, the spell family the name bridge requires | <https://wago.tools/db2/SpellClassOptions/csv?build=1.60.1.71037> |
| `SkillLine` | the talent-tree, pet and racial skill lines | <https://wago.tools/db2/SkillLine/csv?build=1.60.1.71037> |
| `SkillRaceClassInfo` | ClassMask: the one class a talent-tree skill line belongs to | <https://wago.tools/db2/SkillRaceClassInfo/csv?build=1.60.1.71037> |
| `SkillLineAbility` | spells on a class, pet or racial line; AcquireMethod 3 is never learned | <https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.71037> |
| `ChrSpecialization` | specialization id -> class (one per class on Forever) | <https://wago.tools/db2/ChrSpecialization/csv?build=1.60.1.71037> |
| `SkillLineXTraitTree` | talent tree -> its class's skill line | <https://wago.tools/db2/SkillLineXTraitTree/csv?build=1.60.1.71037> |
| `TraitDefinition` | talent definitions: SpellID and VisibleSpellID | <https://wago.tools/db2/TraitDefinition/csv?build=1.60.1.71037> |
| `TraitNodeEntry` | definition -> node entry | <https://wago.tools/db2/TraitNodeEntry/csv?build=1.60.1.71037> |
| `TraitNodeXTraitNodeEntry` | node entry -> node | <https://wago.tools/db2/TraitNodeXTraitNodeEntry/csv?build=1.60.1.71037> |
| `TraitNode` | node -> talent tree | <https://wago.tools/db2/TraitNode/csv?build=1.60.1.71037> |

Every table is frozen gzipped in `raw/`, and `seeds.py derive --replay` re-derives this bundle from them alone.

## Per-spec counts

| Class | Spec | Reach | Shipped | Interrupts reached | Candidates |
| --- | --- | --- | --- | --- | --- |
| WARRIOR | WARRIOR (1491) | 309 | 0 | 72, 1671, 1672, 6552, 6554 | 7 |
| PALADIN | PALADIN (1486) | 341 | 0 | none | 4 |
| HUNTER | HUNTER (1485) | 493 | 0 | none | 5 |
| ROGUE | ROGUE (1488) | 269 | 0 | 1766, 1767, 1768, 1769 | 5 |
| PRIEST | PRIEST (1487) | 411 | 0 | none | 4 |
| SHAMAN | SHAMAN (1489) | 350 | 0 | 8042, 8044, 8045, 8046, 10412, 10413, 10414 | 3 |
| MAGE | MAGE (1482) | 348 | 0 | 2139 | 3 |
| WARLOCK | WARLOCK (1490) | 446 | 0 | 19244, 19647 | 5 |
| DRUID | DRUID (1484) | 388 | 0 | 1238122 | 5 |
