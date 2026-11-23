#!/usr/bin/env python3
"""tools/seeds/forever.py: the `forever` flavor of seeds.py (WoW Forever, wago.tools product `wowf`).

WHAT THIS IS
    seeds.py's loop, rules and file writers, pointed at WoW Forever: defaults/Spells_Forever.lua
    (NS.DefaultSpellsForever, keyed by Const.SPEC_FOREVER), tools/seeds/rulings_forever.json and
    docs/seed-research/<date>-forever/. Run it through seeds.py with `--flavor forever`; this module
    only supplies what differs. A Forever list is derived from Forever's own tables, never by
    filtering Retail's (clients-§5): id 99 is Demoralizing Roar there, 23920 is unlearnable and
    19647 is only rank 2 of Spell Lock.

WHY A REACH MODEL OF ITS OWN
    wago.tools serves no SpecializationSpells, SpecSetMember, TraitNodeXTraitCond or
    TraitTreeLoadout rows for `wowf`, and every class has ONE specialization (1482, 1484-1491; 1493
    is the pet spec), so reach is per class:
      - class lines: the talent-tree skill lines (Arms, Fury, ...) a class owns, read from
        SkillRaceClassInfo.ClassMask when it names exactly one Forever class. A line every class
        shares (Engraving, Runes, Mounts) is never a class line.
      - class spells: SkillLineAbility rows on those lines whose AcquireMethod is not 3 (never
        learned). That one rule keeps out the Season of Discovery rune grants (Rebuke 425609,
        Skull Bash 410176, Shockwave 440488) and the unreachable same-name clones.
      - talents: TraitDefinition -> TraitNodeEntry -> TraitNodeXTraitNodeEntry -> TraitNode, the
        node's TraitTree tied to its class through SkillLineXTraitTree. The old Talent table is
        not used: it misses Feral Charge 1238122.
      - pets: PET_LINES below, gated on a reachable summon (the Felguard's summon has no learn row).
      - racials: the "Racial - <race>" and "<race> Racial" lines, reach for flags only.

RANKS: ONE CANDIDATE PER FAMILY
    Every rank is its own spell id on Forever. KickCD stores one row per ability (one id per
    ability, docs/validate-seeds.md), and the rank table resolves the highest known rank at run
    time, so a spec's candidates are folded by name: one candidate per family, keyed by its
    "Rank 1" id (Spell.NameSubtext_lang), else its lowest id, carrying `ranks`. A family any rank
    of which the list already ships is not proposed again.

HAND CANDIDATES
    The rules propose only spells with a cooldown, and never a racial. The owner's ruling R7
    (2026-11-23: "core plus Rogue Gouge and Warrior Intercept") puts four spells with no cooldown
    in the core lists, and the critic's L1 seeds War Stomp in every Tauren class's list (a shared
    profile appends the racial for its creator's class only). Those are HAND_CANDIDATES, still
    ruled like any other.

Python 3.8+ and its standard library only.
"""

from __future__ import annotations

import re
from collections import defaultdict

import seeds
from seeds import as_int, iter_csv, norm

TABLES = (
    ("SpellName", "names: the `unnamed` and `renamed` flags, the rank families, every report row"),
    ("Spell", "NameSubtext_lang: the `Rank 1` subtext that names a family's first rank"),
    ("SpellEffect", "Effect 68 INTERRUPT_CAST, EffectMechanic, knockback and pull effects, EffectTriggerSpell for the closure"),
    ("SpellCategories", "spell-level Mechanic, and ChargeCategory for a charged cooldown"),
    ("SpellMechanic", "mechanic id -> name, the table MECHANIC_CATEGORIES is written against"),
    ("SpellCooldowns", "RecoveryTime / CategoryRecoveryTime: a candidate needs a cooldown"),
    ("SpellCategory", "ChargeRecoveryTime of a charged spell"),
    ("SpellClassOptions", "SpellClassSet, the spell family the name bridge requires"),
    ("SkillLine", "the talent-tree, pet and racial skill lines"),
    ("SkillRaceClassInfo", "ClassMask: the one class a talent-tree skill line belongs to"),
    ("SkillLineAbility", "spells on a class, pet or racial line; AcquireMethod 3 is never learned"),
    ("ChrSpecialization", "specialization id -> class (one per class on Forever)"),
    ("SkillLineXTraitTree", "talent tree -> its class's skill line"),
    ("TraitDefinition", "talent definitions: SpellID and VisibleSpellID"),
    ("TraitNodeEntry", "definition -> node entry"),
    ("TraitNodeXTraitNodeEntry", "node entry -> node"),
    ("TraitNode", "node -> talent tree"),
)

# ChrSpecialization.ClassID -> class token, Forever's nine classes; the ClassMask bit is ClassID - 1.
CLASS_BY_CLASS_ID = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST",
                     7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
CLASS_BY_BIT = {1 << (cid - 1): token for cid, token in CLASS_BY_CLASS_ID.items()}
NEVER_LEARNED = 3   # SkillLineAbility.AcquireMethod (TrinityCore SkillLineAbilityAcquireMethod)
RACIAL_SKILL_CATEGORY = 9
RACIAL_SUFFIX = " Racial"

# The pet lines a warlock casts through, each with the summon that gates it (hand data: no DB2
# column ties a pet line to a class). Spell Lock is taught by grimoire items to the Felhunter.
# The Felguard's summon (427733) has no learn row on 71037, so its line reaches nothing. Hunter
# family lines are left out: no hunter pet carries an interrupt or a castable stop (the sweep in
# the bundle's ANALYSIS.md), and Intimidation 19577 is the hunter's own cast.
PET_LINES = {
    "Pet - Felhunter": ("WARLOCK", 691),
    "Pet - Succubus": ("WARLOCK", 712),
    "Pet - Imp": ("WARLOCK", 688),
    "Pet - Voidwalker": ("WARLOCK", 697),
    "Pet - Felguard": ("WARLOCK", 427733),
}

_NO_CD = "no cooldown, so no rule proposes it; core by the owner's ruling R7 (2026-11-23)"
_TRAP = ("Freezing Trap: the freeze is the trap's own 3355/14308/14309, which DB2 reaches through a "
         "game object, not the cast's effects; core by the owner's ruling R7 (2026-11-23)")
_OPTIONAL = ("in the research's owner-optional column (inputs/research/forever-interrupt-data.md 7); "
             "proposed so the owner's ruling R7 (core plus Gouge and Intercept only) is on record")
_STOMP = ("War Stomp, the Tauren racial, in every class a Tauren plays (critic L1: a shared "
          "profile appends the racial for its creator's class only); hidden when not known")

# (class, Const.SPEC_FOREVER alias, id, category, why). A Forever alias is its class token.
HAND_CANDIDATES = (
    ("ROGUE", "ROGUE", 1833, "stun", "Cheap Shot: " + _NO_CD),
    ("MAGE", "MAGE", 118, "incapacitate", "Polymorph: " + _NO_CD),
    ("WARLOCK", "WARLOCK", 5782, "fear", "Fear: " + _NO_CD),
    ("PRIEST", "PRIEST", 605, "incapacitate", "Mind Control: " + _NO_CD),
    ("HUNTER", "HUNTER", 1499, "incapacitate", _TRAP),
    ("PALADIN", "PALADIN", 2812, "stun", "Holy Wrath (its stun 429147 is linked by a server script): " + _OPTIONAL),
    ("SHAMAN", "SHAMAN", 8177, "other", "Grounding Totem (a totem redirects one spell): " + _OPTIONAL),
    ("WARLOCK", "WARLOCK", 6358, "incapacitate", "Seduction (the Succubus; no cooldown): " + _OPTIONAL),
    ("DRUID", "DRUID", 9005, "stun", "Pounce (no cooldown): " + _OPTIONAL),
    ("DRUID", "DRUID", 2637, "incapacitate", "Hibernate (no cooldown): " + _OPTIONAL),
    ("WARRIOR", "WARRIOR", 20549, "racial", _STOMP),
    ("HUNTER", "HUNTER", 20549, "racial", _STOMP),
    ("SHAMAN", "SHAMAN", 20549, "racial", _STOMP),
    ("DRUID", "DRUID", 20549, "racial", _STOMP),
)


class ForeverBuild(seeds.Build):
    """seeds.Build with WoW Forever's reach (the module docstring) and each spell's rank subtext."""

    def __init__(self, tables: dict):
        self.subtext = {as_int(r["ID"]): (r.get("NameSubtext_lang") or "").strip()
                        for r in iter_csv(tables["Spell"])}
        super().__init__(tables)

    def _reach_inputs(self, tables: dict) -> None:
        class_specs = self._read_specs(tables)
        lines = {as_int(r["ID"]): (r.get("DisplayName_lang") or "", as_int(r["CategoryID"]))
                 for r in iter_csv(tables["SkillLine"])}
        class_lines = tree_lines(tables, lines)
        missing = set(class_specs) - set(class_lines.values())
        if missing:
            raise SystemExit("No talent-tree skill line for %s: SkillRaceClassInfo changed shape."
                             % ", ".join(sorted(missing)))
        pet_lines = {lid: PET_LINES[name] for lid, (name, _c) in lines.items() if name in PET_LINES}
        racial_lines = {lid: racial_name(name) for lid, (name, cat) in lines.items()
                        if cat == RACIAL_SKILL_CATEGORY and racial_name(name)}
        self._read_abilities(tables, class_lines, pet_lines, racial_lines)
        self.spec_spells = defaultdict(set)   # no such table on Forever
        self.pvp_spells = defaultdict(set)    # no PvP talents on Forever
        self.talent_spells = tree_spells_by_spec(tables, class_lines, class_specs)

    def _read_specs(self, tables: dict) -> dict:
        """spec_class and spec_name, the nine class specs (the pet spec has no class); returns
        `{class: specs}`."""
        self.spec_class, self.spec_name = {}, {}
        class_specs = defaultdict(set)
        for r in iter_csv(tables["ChrSpecialization"]):
            token = CLASS_BY_CLASS_ID.get(as_int(r.get("ClassID")))
            if token:
                self.spec_class[as_int(r["ID"])] = token
                self.spec_name[as_int(r["ID"])] = r.get("Name_lang") or ""
                class_specs[token].add(as_int(r["ID"]))
        return class_specs

    def _read_abilities(self, tables: dict, class_lines: dict, pet_lines: dict,
                        racial_lines: dict) -> None:
        """class_spells, pet_spells and racial from the learned SkillLineAbility rows."""
        self.class_spells = defaultdict(set)
        self.pet_spells = defaultdict(set)
        self.racial = defaultdict(set)
        for r in iter_csv(tables["SkillLineAbility"]):
            spell, line = as_int(r["Spell"]), as_int(r["SkillLine"])
            if not spell or as_int(r.get("AcquireMethod")) == NEVER_LEARNED:
                continue
            if line in class_lines:
                self.class_spells[class_lines[line]].add(spell)
            elif line in pet_lines:
                self.pet_spells[pet_lines[line]].add(spell)
            elif line in racial_lines:
                self.racial[spell].add(norm(racial_lines[line]))


def tree_lines(tables: dict, lines: dict) -> dict:
    """`{skill line: class}`: the class-category lines whose SkillRaceClassInfo mask names exactly
    one Forever class (a line several classes share, Engraving or Runes, is no class's)."""
    out = {}
    for r in iter_csv(tables["SkillRaceClassInfo"]):
        token = CLASS_BY_BIT.get(as_int(r.get("ClassMask")) & 0xFFFFFFFF)
        line = as_int(r["SkillID"])
        if token and lines.get(line, ("", 0))[1] == seeds.CLASS_SKILL_CATEGORY:
            out[line] = token
    return out


def racial_name(name: str) -> str:
    """The race a racial line names, in either of Forever's shapes, else ""."""
    if name.startswith(seeds.RACIAL_PREFIX):
        return name[len(seeds.RACIAL_PREFIX):]
    if name.endswith(RACIAL_SUFFIX):
        return name[:-len(RACIAL_SUFFIX)]
    return ""


def tree_spells_by_spec(tables: dict, class_lines: dict, class_specs: dict) -> dict:
    """`{spec: spells}` a class's talent tree grants. A Forever class has one spec and one tree,
    so every node of the tree is visible to it; no spec-set gate exists to read."""
    tree_class = {}
    for r in iter_csv(tables["SkillLineXTraitTree"]):
        token = class_lines.get(as_int(r["SkillLineID"]))
        if token:
            tree_class[as_int(r["TraitTreeID"])] = token
    definition_spells = defaultdict(set)
    for r in iter_csv(tables["TraitDefinition"]):
        for column in ("SpellID", "VisibleSpellID"):
            if as_int(r.get(column)):
                definition_spells[as_int(r["ID"])].add(as_int(r[column]))
    entry_definition = {as_int(r["ID"]): as_int(r.get("TraitDefinitionID"))
                        for r in iter_csv(tables["TraitNodeEntry"])}
    node_tree = {as_int(r["ID"]): as_int(r["TraitTreeID"]) for r in iter_csv(tables["TraitNode"])}
    out = defaultdict(set)
    for r in iter_csv(tables["TraitNodeXTraitNodeEntry"]):
        token = tree_class.get(node_tree.get(as_int(r["TraitNodeID"]), 0))
        if not token:
            continue
        for spell in definition_spells.get(entry_definition.get(as_int(r["TraitNodeEntryID"]), 0), ()):
            for spec in class_specs.get(token, ()):
                out[spec].add(spell)
    return out


def _representative(db: ForeverBuild, group: list) -> dict:
    """The candidate that stands for a family: a hand entry (its category is a ruling's), else
    the `Rank 1` id, else the lowest id."""
    hand = [c for c in group if "hand" in c["evidence"]]
    if hand:
        return hand[0]
    first = [c for c in group if db.subtext.get(c["id"], "").lower() == "rank 1"]
    return (first or sorted(group, key=lambda c: c["id"]))[0]


RANK_SUBTEXT = re.compile(r"^Rank \d+$")


def family_ranks(db: ForeverBuild, ids: set) -> list:
    """The ranks of a same-name family: the ids whose subtext is `Rank N` when any is (Polymorph's
    Turtle and Pig variants are their own spells, not ranks), else every id."""
    ranked = {i for i in ids if RANK_SUBTEXT.match(db.subtext.get(i, ""))}
    return sorted(ranked or ids)


def collapse_ranks(db: ForeverBuild, block: dict, found: list) -> list:
    """One candidate per rank family (the module docstring), sorted by id; a family any rank of
    which the list ships is dropped. `ranks` is every id of the family the spec reaches (with or
    without a cooldown), plus the candidates themselves (a racial is not in reach())."""
    shipped = {(db.names.get(e["id"]) or "").lower() for e in block["entries"]}
    reached = defaultdict(set)
    for spell in db.reach(block["spec"]):
        reached[(db.names.get(spell) or "").lower()].add(spell)
    groups, order = defaultdict(list), []
    for cand in found:
        name = cand["name"].lower()
        if name in shipped:
            continue
        if name not in groups:
            order.append(name)
        groups[name].append(cand)
    out = []
    for name in order:
        rep = dict(_representative(db, groups[name]))
        rep["ranks"] = family_ranks(db, {c["id"] for c in groups[name]} | reached.get(name, set()))
        out.append(rep)
    return sorted(out, key=lambda c: c["id"])


FOREVER = seeds.Flavor(
    "forever", "WoW Forever", "wowf", seeds.ROOT / "defaults" / "Spells_Forever.lua",
    seeds.HERE / "rulings_forever.json", "SPEC_FOREVER", TABLES, ForeverBuild,
    hand=HAND_CANDIDATES, finish=collapse_ranks, comment="%s (DB2 seed %s)")
