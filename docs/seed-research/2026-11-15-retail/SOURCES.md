# Sources: Retail seed validation, 2026-11-15

Written by `tools/seeds/seeds.py derive`. Frozen: never edited after the run, apart from the hand-written `ANALYSIS.md` beside it.

| Field | Value |
| --- | --- |
| Client | `retail` (wago.tools product `wow`) |
| Build | `12.1.5.70783` |
| Run date | 2026-11-15 (the run's `--date` argument; the tool never reads the clock) |
| Builds API | <https://wago.tools/api/builds> |
| User-Agent | `KickCD-seed-validation/1.0 (+https://github.com/tusharsaxena/KickCD)` |
| Seed file | `defaults/Spells.lua`: 186 entries, 79 distinct ids |

## Tables

| Table | Why | URL |
| --- | --- | --- |
| `SpellName` | names: the `unnamed` and `renamed` flags, and every report row | <https://wago.tools/db2/SpellName/csv?build=12.1.5.70783> |
| `SpellEffect` | Effect 68 INTERRUPT_CAST, EffectMechanic, knockback and pull effects, EffectTriggerSpell for the closure | <https://wago.tools/db2/SpellEffect/csv?build=12.1.5.70783> |
| `SpellCategories` | spell-level Mechanic, and ChargeCategory for a charged cooldown | <https://wago.tools/db2/SpellCategories/csv?build=12.1.5.70783> |
| `SpellMechanic` | mechanic id -> name, the table MECHANIC_CATEGORIES is written against | <https://wago.tools/db2/SpellMechanic/csv?build=12.1.5.70783> |
| `SpellCooldowns` | RecoveryTime / CategoryRecoveryTime: a candidate needs a cooldown | <https://wago.tools/db2/SpellCooldowns/csv?build=12.1.5.70783> |
| `SpellCategory` | ChargeRecoveryTime of a charged spell | <https://wago.tools/db2/SpellCategory/csv?build=12.1.5.70783> |
| `SpellClassOptions` | SpellClassSet, the spell family the name bridge requires | <https://wago.tools/db2/SpellClassOptions/csv?build=12.1.5.70783> |
| `SkillLine` | class skill lines, pet lines and the racial lines | <https://wago.tools/db2/SkillLine/csv?build=12.1.5.70783> |
| `SkillLineAbility` | spells on a class, pet or racial skill line | <https://wago.tools/db2/SkillLineAbility/csv?build=12.1.5.70783> |
| `SpecializationSpells` | spells a specialization grants | <https://wago.tools/db2/SpecializationSpells/csv?build=12.1.5.70783> |
| `PvpTalent` | PvP talents per spec: reach for the flags only, never a candidate source | <https://wago.tools/db2/PvpTalent/csv?build=12.1.5.70783> |
| `ChrSpecialization` | specialization id -> class and name | <https://wago.tools/db2/ChrSpecialization/csv?build=12.1.5.70783> |
| `TraitDefinition` | talent definitions: SpellID and VisibleSpellID | <https://wago.tools/db2/TraitDefinition/csv?build=12.1.5.70783> |
| `TraitNodeEntry` | definition -> node entry, and a hero subtree's selection entry | <https://wago.tools/db2/TraitNodeEntry/csv?build=12.1.5.70783> |
| `TraitNodeXTraitNodeEntry` | node entry -> node | <https://wago.tools/db2/TraitNodeXTraitNodeEntry/csv?build=12.1.5.70783> |
| `TraitNode` | node -> talent tree and hero subtree | <https://wago.tools/db2/TraitNode/csv?build=12.1.5.70783> |
| `TraitTreeLoadout` | talent tree -> the specializations that load it | <https://wago.tools/db2/TraitTreeLoadout/csv?build=12.1.5.70783> |
| `TraitCond` | a node's visibility condition (CondType 1) on a spec set | <https://wago.tools/db2/TraitCond/csv?build=12.1.5.70783> |
| `TraitNodeXTraitCond` | conditions on a node | <https://wago.tools/db2/TraitNodeXTraitCond/csv?build=12.1.5.70783> |
| `TraitNodeGroupXTraitNode` | node -> node group | <https://wago.tools/db2/TraitNodeGroupXTraitNode/csv?build=12.1.5.70783> |
| `TraitNodeGroupXTraitCond` | conditions on a node group | <https://wago.tools/db2/TraitNodeGroupXTraitCond/csv?build=12.1.5.70783> |
| `SpecSetMember` | spec set -> its specializations | <https://wago.tools/db2/SpecSetMember/csv?build=12.1.5.70783> |

Every table is frozen gzipped in `raw/`, and `seeds.py derive --replay` re-derives this bundle from them alone.

## Per-spec counts

| Class | Spec | Reach | Shipped | Interrupts reached | Candidates |
| --- | --- | --- | --- | --- | --- |
| DEATHKNIGHT | BLOOD (250) | 174 | 6 | 47528 | 0 |
| DEATHKNIGHT | FROST_DK (251) | 173 | 5 | 47528 | 1 |
| DEATHKNIGHT | UNHOLY (252) | 190 | 4 | 47528, 91802 | 4 |
| DEMONHUNTER | HAVOC (577) | 175 | 4 | 183752 | 0 |
| DEMONHUNTER | VENGEANCE (581) | 181 | 6 | 183752 | 0 |
| DEMONHUNTER | DEVOURER (1480) | 168 | 4 | 183752 | 0 |
| DRUID | BALANCE (102) | 231 | 5 | 78675 | 0 |
| DRUID | FERAL (103) | 227 | 6 | none | 0 |
| DRUID | GUARDIAN (104) | 230 | 5 | none | 0 |
| DRUID | RESTORATION_DRUID (105) | 231 | 4 | none | 0 |
| EVOKER | DEVASTATION (1467) | 162 | 4 | 351338 | 0 |
| EVOKER | PRESERVATION (1468) | 168 | 4 | 351338 | 0 |
| EVOKER | AUGMENTATION (1473) | 130 | 4 | 351338 | 0 |
| HUNTER | BEASTMASTERY (253) | 201 | 6 | 147362 | 1 |
| HUNTER | MARKSMANSHIP (254) | 204 | 5 | 147362 | 1 |
| HUNTER | SURVIVAL (255) | 202 | 4 | 187707 | 1 |
| MAGE | ARCANE (62) | 244 | 6 | 2139 | 0 |
| MAGE | FIRE (63) | 243 | 5 | 2139 | 1 |
| MAGE | FROST_MAGE (64) | 243 | 5 | 2139 | 1 |
| MONK | BREWMASTER (268) | 232 | 5 | 116705 | 1 |
| MONK | MISTWEAVER (270) | 243 | 5 | 116705 | 0 |
| MONK | WINDWALKER (269) | 259 | 5 | 116705 | 1 |
| PALADIN | HOLY_PALADIN (65) | 232 | 3 | none | 3 |
| PALADIN | PROTECTION_PALADIN (66) | 226 | 5 | 31935, 96231 | 3 |
| PALADIN | RETRIBUTION (70) | 212 | 4 | 96231 | 3 |
| PRIEST | DISCIPLINE (256) | 170 | 4 | none | 2 |
| PRIEST | HOLY_PRIEST (257) | 172 | 3 | none | 2 |
| PRIEST | SHADOW (258) | 178 | 4 | none | 2 |
| ROGUE | ASSASSINATION (259) | 186 | 4 | 1766 | 1 |
| ROGUE | OUTLAW (260) | 186 | 4 | 1766 | 1 |
| ROGUE | SUBTLETY (261) | 192 | 4 | 1766 | 1 |
| SHAMAN | ELEMENTAL (262) | 250 | 4 | 57994 | 8 |
| SHAMAN | ENHANCEMENT (263) | 228 | 3 | 57994 | 9 |
| SHAMAN | RESTORATION_SHAMAN (264) | 238 | 4 | 57994 | 8 |
| WARLOCK | AFFLICTION (265) | 241 | 5 | 19647 | 1 |
| WARLOCK | DEMONOLOGY (266) | 261 | 6 | 19647, 89766 | 1 |
| WARLOCK | DESTRUCTION (267) | 242 | 5 | 19647 | 2 |
| WARRIOR | ARMS (71) | 241 | 3 | 6552 | 0 |
| WARRIOR | FURY (72) | 244 | 3 | 6552 | 0 |
| WARRIOR | PROTECTION_WARRIOR (73) | 244 | 6 | 6552, 386071 | 0 |
