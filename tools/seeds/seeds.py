#!/usr/bin/env python3
"""tools/seeds/seeds.py: re-validate KickCD's cast-stopper seeds against a wago.tools build (KickCD#39).

WHAT THIS IS
    defaults/Spells.lua is hand-curated from a community sheet (the file's header names it). Nothing
    checked it against the game after a patch, so a renamed spell, a talent that moved to another
    spec or a new interrupt went unnoticed. This tool reads one pinned Retail build's DB2 tables
    (wago.tools product `wow`) and turns what it finds into FLAGS on shipped ids and CANDIDATES for
    ids the lists lack. Each needs a ruling, recorded as data in rulings_retail.json and keyed by
    class, spec and id, never by build, so a re-run on a later build shows only what is new.

    KickCD tracks the COOLDOWN OF THE CAST: core/Compat.lua's IsSpellAvailable asks IsPlayerSpell /
    IsSpellKnown(id[, true]) about the seeded id, and modules/Cooldowns.lua polls
    C_Spell.GetSpellCooldown on it. So the id that matters is the one the player (or the pet)
    casts, never the aura it applies. Reach is checked for that id alone; the trigger closure below
    is evidence about what the cast does, not a source of ids to ship.

    Flags (key `shipped:<kind>:<CLASS>:<specID>:<id>`, or `shipped:<kind>:RACE:<Race>:<id>` for
    NS.RaceCastStoppers; ruled keep or remove):
        unnamed      the build's SpellName has no row for the id
        renamed      the build's name disagrees with the comment beside it (asides in parentheses
                     are ignored)
        unreachable  the spec cannot reach the id: not on its class skill line, not a spell of the
                     spec, not on a talent node the spec can see, not a spell of a pet the spec
                     can summon (a racial: not on any "Racial - <race>" skill line)
        category     the id's own effects (closed over EffectTriggerSpell, plus the same-family
                     name bridge) show cast-stopping evidence, and none of it is the shipped
                     category
        no-evidence  the id shows no cast-stopping evidence at all (a server script, an area
                     trigger or a summoned totem does the work, which DB2 does not link)
        primary      index 1 is not one of the spec's interrupts although the spec reaches one
                     (the header: "Index 1 is the primary interrupt")

    Candidates (key `<CLASS>:<specID>:<id>`, ruled accept or reject), only for specs the file
    seeds, only ids the spec itself reaches, never ids already in that spec's list, and only ids
    with a cooldown (a cooldown tracker has nothing to show for a spell without one):
        interrupt    the id interrupts: SpellEffect effect 68 (INTERRUPT_CAST) on it or its closure
        cc           the id stuns, incapacitates, fears, silences, knocks back or displaces, by
                     SpellCategories.Mechanic / SpellEffect.EffectMechanic (named by SpellMechanic)
                     or a knockback / pull effect. Roots are never proposed: a root does not stop
                     a cast. The file's header makes CC a curation call (PvE-biased, priority
                     order), so a CC candidate is a proposal for the owner, not a conclusion.

THE STEPS (docs/validate-seeds.md is the contract /dev-copilot:validate-seeds runs)
    python3 tools/seeds/seeds.py status
    python3 tools/seeds/seeds.py derive --bundle docs/seed-research/<date>-retail --date <date> [--build <v>] [--replay]
    python3 tools/seeds/seeds.py check  --bundle docs/seed-research/<date>-retail
    python3 tools/seeds/seeds.py rule   --tsv rulings.tsv --bundle docs/seed-research/<date>-retail
    python3 tools/seeds/seeds.py report --bundle docs/seed-research/<date>-retail --date <date>
    python3 tools/seeds/seeds.py apply  --bundle docs/seed-research/<date>-retail --date <date>

    `derive` pins one build (--build, else the live `wow` build from the builds API), streams each
    table into the git-ignored .cache/, freezes a gzipped copy of every table it read into the
    bundle's raw/, and writes SOURCES.md and candidates.json. `--replay` re-derives from raw/ alone,
    with no network and no cache. `rule` is the only writer of rulings_retail.json. `check` exits 1
    while anything is unruled. `report` writes RULINGS.md (run it before `apply`). `apply` refuses
    while anything is unruled, writes accepted candidates into defaults/Spells.lua and removes ids
    whose flag was ruled `remove`, keeping the file's CRLF endings and column layout; a second
    `apply` changes nothing. It never changes a category or a comment on its own.

    Every date is an argument; the tool never reads the clock.

SHARED HELPER
    The fetch, cache, bundle and rulings shape is copied from AuraMaster's
    tools/spell-research/ (research.py, retail.py, sid_seeds.py), not imported across repos.
    Whether that code becomes one shared helper, and where it lives, is LibKa0s#91.

Python 3.8+ and its standard library only.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import shutil
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SEEDS_PATH = ROOT / "defaults" / "Spells.lua"
CONSTANTS_PATH = ROOT / "core" / "Constants.lua"
RULINGS_PATH = HERE / "rulings_retail.json"
RESEARCH = ROOT / "docs" / "seed-research"
CACHE_DIR = HERE / ".cache"

CLIENT = "retail"
PRODUCT = "wow"
BUNDLE_SUFFIX = "-retail"

BUILDS_URL = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
# wago.tools answers HTTP 403 to urllib's default agent (clients-§10): say who is asking.
USER_AGENT = "KickCD-seed-validation/1.0 (+https://github.com/tusharsaxena/KickCD)"
DOWNLOAD_CHUNK = 1 << 20  # SpellEffect is ~57 MB: always streamed, never read into one string

# The tables a run reads, with why. This tuple IS the fetch list and what SOURCES.md records.
TABLES = (
    ("SpellName", "names: the `unnamed` and `renamed` flags, and every report row"),
    ("SpellEffect", "Effect 68 INTERRUPT_CAST, EffectMechanic, knockback and pull effects, EffectTriggerSpell for the closure"),
    ("SpellCategories", "spell-level Mechanic, and ChargeCategory for a charged cooldown"),
    ("SpellMechanic", "mechanic id -> name, the table MECHANIC_CATEGORIES is written against"),
    ("SpellCooldowns", "RecoveryTime / CategoryRecoveryTime: a candidate needs a cooldown"),
    ("SpellCategory", "ChargeRecoveryTime of a charged spell"),
    ("SpellClassOptions", "SpellClassSet, the spell family the name bridge requires"),
    ("SkillLine", "class skill lines, pet lines and the racial lines"),
    ("SkillLineAbility", "spells on a class, pet or racial skill line"),
    ("SpecializationSpells", "spells a specialization grants"),
    ("PvpTalent", "PvP talents per spec: reach for the flags only, never a candidate source"),
    ("ChrSpecialization", "specialization id -> class and name"),
    ("TraitDefinition", "talent definitions: SpellID and VisibleSpellID"),
    ("TraitNodeEntry", "definition -> node entry, and a hero subtree's selection entry"),
    ("TraitNodeXTraitNodeEntry", "node entry -> node"),
    ("TraitNode", "node -> talent tree and hero subtree"),
    ("TraitTreeLoadout", "talent tree -> the specializations that load it"),
    ("TraitCond", "a node's visibility condition (CondType 1) on a spec set"),
    ("TraitNodeXTraitCond", "conditions on a node"),
    ("TraitNodeGroupXTraitNode", "node -> node group"),
    ("TraitNodeGroupXTraitCond", "conditions on a node group"),
    ("SpecSetMember", "spec set -> its specializations"),
)

CATEGORIES = ("interrupt", "stun", "knockback", "incapacitate", "silence", "root", "fear",
              "displace", "racial", "other")
# A candidate's proposed category: the first evidence in this order.
PROPOSE_ORDER = ("interrupt", "stun", "incapacitate", "fear", "silence", "knockback", "displace")
CC_CATEGORIES = frozenset(PROPOSE_ORDER) - {"interrupt"}

INTERRUPT_EFFECT = 68
# SpellEffect.Effect values that move the target (TrinityCore's SpellEffectName numbering).
MOVEMENT_EFFECTS = {98: "knockback", 144: "knockback", 124: "displace", 145: "displace"}
# ImplicitTarget_0 values that point a movement effect at the caster or an ally (Disengage,
# Vengeful Retreat): a self-knockback moves the player, not the caster KickCD wants stopped.
FRIENDLY_TARGETS = frozenset({1, 21, 57})  # UNIT_CASTER, UNIT_TARGET_ALLY, UNIT_TARGET_PARTY
APPLY_AURA = 6
# SpellMechanic.StateName_lang -> the KickCD categories that mechanic is evidence for. A mechanic
# names what the target suffers; one can fit more than one of KickCD's informational categories
# (a horror is a fear that holds the target in place, a knockback mechanic is set on pulls too).
MECHANIC_CATEGORIES = {
    "stunned": ("stun",),
    "charmed": ("incapacitate",),
    "disoriented": ("incapacitate",),
    "asleep": ("incapacitate",),
    "incapacitated": ("incapacitate",),
    "polymorphed": ("incapacitate",),
    "banished": ("incapacitate",),
    "shackled": ("incapacitate",),
    "sapped": ("incapacitate",),
    "frozen": ("incapacitate", "root"),
    "fleeing": ("fear",),
    "turned": ("fear",),
    "horrified": ("fear", "incapacitate"),
    "silenced": ("silence",),
    "rooted": ("root",),
    "knockbacked": ("knockback", "displace"),
}
TRIGGER_DEPTH = 3

CLASS_SKILL_LINE_NAMES = {
    "Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE",
    "Priest": "PRIEST", "Death Knight": "DEATHKNIGHT", "Shaman": "SHAMAN", "Mage": "MAGE",
    "Warlock": "WARLOCK", "Monk": "MONK", "Druid": "DRUID", "Demon Hunter": "DEMONHUNTER",
    "Evoker": "EVOKER",
}
# ChrSpecialization.ClassID -> class token (ClassID 1 is WARRIOR ... 13 is EVOKER).
CLASS_BY_CLASS_ID = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST",
                     6: "DEATHKNIGHT", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 10: "MONK",
                     11: "DRUID", 12: "DEMONHUNTER", 13: "EVOKER"}
CLASS_SKILL_CATEGORY = 7
RACIAL_SKILL_CATEGORY = 9
RACIAL_PREFIX = "Racial - "
# The pet skill lines whose spells a class casts through its pet, and the summon that gates them
# per spec: a pet spell is reachable by a spec that reaches the summon. Hand data, because no DB2
# column ties a pet line to a class (every row's ClassMask is 0). Hunter family lines are left out:
# a hunter pet carries no interrupt, and its CC is the hunter's own cast (Intimidation 19577).
PET_LINES = {
    "Pet - Felhunter": ("WARLOCK", 691),    # Summon Felhunter: Spell Lock 19647
    "Pet - Felguard": ("WARLOCK", 30146),   # Summon Felguard: Axe Toss 89766
    "Wrathguard": ("WARLOCK", 30146),       # the Felguard's Wrathguard form, same summon
    "Pet - Imp": ("WARLOCK", 688),
    "Pet - Voidwalker": ("WARLOCK", 697),
    "Pet - Succubus": ("WARLOCK", 366222),  # Summon Sayaad
    "Pet - Ghoul": ("DEATHKNIGHT", 46584),  # Raise Dead (the permanent ghoul)
}
VISIBLE_COND = 1  # TraitCond.CondType 1: the node is shown only to the condition's spec set

# THE HAND CANDIDATES: a cast id the rules cannot propose because DB2 links its effect to the cast
# only through a server script (the cast carries a dummy effect, the CC is on another id), each
# with why. Proposed like any candidate for its spec when the spec reaches it, and still ruled;
# one the build no longer names or the spec cannot reach goes to candidates.json's `handMissing`.
# (class, Const.SPEC alias, id, category, why). Evidence: the bundle's ANALYSIS.md.
HAND_CANDIDATES = (
    ("PALADIN", "HOLY_PALADIN", 115750, "incapacitate",
     "Blinding Light's cast (90 s cooldown); the list ships 105421, the disorient it applies, which no spec learns"),
    ("PALADIN", "PROTECTION_PALADIN", 115750, "incapacitate",
     "Blinding Light's cast (90 s cooldown); the list ships 105421, the disorient it applies, which no spec learns"),
    ("PALADIN", "RETRIBUTION", 115750, "incapacitate",
     "Blinding Light's cast (90 s cooldown); the list ships 105421, the disorient it applies, which no spec learns"),
)

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
CANDIDATE_RULINGS = ("accept", "reject")
FLAG_RULINGS = ("keep", "remove")
FLAG_KINDS = ("unnamed", "renamed", "unreachable", "category", "no-evidence", "primary")
KEY = re.compile(r"^(?:shipped:(?P<kind>[a-z-]+):)?(?P<owner>[A-Z]+):(?P<scope>\w+):(?P<id>\d+)$")


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def as_int(value) -> int:
    if not value:
        return 0
    try:
        return int(value)
    except ValueError:
        try:
            return int(float(value))
        except ValueError:
            return 0


def write_text(path: Path, text: str) -> None:
    """Write a committed text file with CRLF terminators: the repo pins `* text=auto eol=crlf`
    (line-endings-§2) and tests/_kit/test_eol.lua checks every tracked file. Bytes, so no Python
    version's newline handling decides it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


def write_json(path: Path, doc) -> None:
    write_text(path, json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------------
# wago.tools: the build, the cache, the bundle's raw/
# ---------------------------------------------------------------------------

def http_get(url: str, accept: str = "*/*"):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    try:
        return urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as err:
        raise SystemExit("HTTP %s fetching %s: %s" % (err.code, url, err.reason))
    except urllib.error.URLError as err:
        raise SystemExit("Could not reach %s: %s (a run that is not --replay needs the network)"
                         % (url, err.reason))


def live_build(product: str = PRODUCT) -> str:
    data = json.load(http_get(BUILDS_URL, accept="application/json"))
    builds = data.get(product) or []
    if not builds:
        raise SystemExit("The builds API returned no '%s' builds; pass --build." % product)
    return builds[0]["version"]


def fetch_table(table: str, build: str, cache_dir: Path) -> Path:
    """Stream one table's CSV for `build` into the cache (a `.part` renamed on completion)."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    dest = cache_dir / ("%s-%s.csv" % (table, build))
    if dest.exists():
        return dest
    url = CSV_URL.format(table=table, build=build)
    tmp = dest.with_suffix(".csv.part")
    log("  %-26s fetching %s" % (table, url))
    with http_get(url, accept="text/csv") as response, tmp.open("wb") as handle:
        shutil.copyfileobj(response, handle, DOWNLOAD_CHUNK)
    tmp.replace(dest)
    return dest


def freeze(source: Path, member: Path) -> None:
    """Gzip a cached table into the bundle. mtime 0 keeps a re-freeze byte-identical."""
    member.parent.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as src, member.open("wb") as raw, \
            gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as dst:
        shutil.copyfileobj(src, dst, DOWNLOAD_CHUNK)


def bundle_tables(bundle: Path, build: str, replay: bool, cache_dir: Path) -> dict:
    """`{table: path}` for every table in TABLES: the bundle's raw/ member on --replay (a missing
    one is fatal), else the cache, frozen into raw/."""
    out = {}
    for table, _why in TABLES:
        member = bundle / "raw" / ("%s.csv.gz" % table)
        if replay:
            if not member.exists():
                raise SystemExit("--replay: %s has no raw/%s.csv.gz; it cannot reproduce its numbers."
                                 % (bundle, table))
        else:
            freeze(fetch_table(table, build, cache_dir), member)
        out[table] = member
    return out


def iter_csv(path: Path):
    """One row at a time, as a dict keyed by header name (never by position, clients-§10)."""
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8", newline="") as handle:
            yield from csv.DictReader(handle)
        return
    with path.open("r", encoding="utf-8", newline="") as handle:
        yield from csv.DictReader(handle)


def base_row(row: dict) -> bool:
    return as_int(row.get("DifficultyID")) == 0


# ---------------------------------------------------------------------------
# The build's facts
# ---------------------------------------------------------------------------

class Build:
    """The facts one build's tables give about spells: names, effects, mechanics, cooldowns,
    families and per-spec reach. Built once per run from `{table: path}`."""

    def __init__(self, tables: dict):
        self.names = {as_int(r["ID"]): r.get("Name_lang") or "" for r in iter_csv(tables["SpellName"])}
        self.mechanic_names = {as_int(r["ID"]): (r.get("StateName_lang") or "").strip()
                               for r in iter_csv(tables["SpellMechanic"])}
        self.effects = defaultdict(list)  # spell -> [(effect, aura, mechanic, trigger)]
        for r in iter_csv(tables["SpellEffect"]):
            if base_row(r):
                self.effects[as_int(r["SpellID"])].append(
                    (as_int(r["Effect"]), as_int(r["EffectAura"]), as_int(r["EffectMechanic"]),
                     as_int(r["EffectTriggerSpell"]), as_int(r.get("ImplicitTarget_0"))))
        self.mechanic = {}
        charge_category = {}
        for r in iter_csv(tables["SpellCategories"]):
            if base_row(r):
                spell = as_int(r["SpellID"])
                self.mechanic[spell] = as_int(r["Mechanic"])
                if as_int(r["ChargeCategory"]):
                    charge_category[spell] = as_int(r["ChargeCategory"])
        charge_time = {as_int(r["ID"]): as_int(r["ChargeRecoveryTime"])
                       for r in iter_csv(tables["SpellCategory"])}
        self.cooldown = {}
        for r in iter_csv(tables["SpellCooldowns"]):
            if base_row(r):
                self.cooldown[as_int(r["SpellID"])] = max(as_int(r["RecoveryTime"]),
                                                          as_int(r["CategoryRecoveryTime"]))
        for spell, cat in charge_category.items():
            self.cooldown[spell] = max(self.cooldown.get(spell, 0), charge_time.get(cat, 0))
        self.family = {as_int(r["SpellID"]): as_int(r["SpellClassSet"])
                       for r in iter_csv(tables["SpellClassOptions"])}
        self.by_name = defaultdict(list)
        for spell, name in self.names.items():
            if name:
                self.by_name[name.lower()].append(spell)
        self._evidence = {}
        self._reach_inputs(tables)

    # -- reach --------------------------------------------------------------

    def _reach_inputs(self, tables: dict) -> None:
        self.spec_class = {}
        self.spec_name = {}
        for r in iter_csv(tables["ChrSpecialization"]):
            token = CLASS_BY_CLASS_ID.get(as_int(r.get("ClassID")))
            if token:
                self.spec_class[as_int(r["ID"])] = token
                self.spec_name[as_int(r["ID"])] = r.get("Name_lang") or ""
        lines = {}
        for r in iter_csv(tables["SkillLine"]):
            lines[as_int(r["ID"])] = (r.get("DisplayName_lang") or "", as_int(r["CategoryID"]),
                                      as_int(r["ParentSkillLineID"]))
        class_lines = {lid: CLASS_SKILL_LINE_NAMES[name] for lid, (name, cat, parent) in lines.items()
                       if cat == CLASS_SKILL_CATEGORY and not parent and name in CLASS_SKILL_LINE_NAMES}
        missing = set(CLASS_SKILL_LINE_NAMES.values()) - set(class_lines.values())
        if missing:
            raise SystemExit("No class skill line for %s: a renamed class or a localized export."
                             % ", ".join(sorted(missing)))
        pet_lines = {lid: PET_LINES[name] for lid, (name, _c, _p) in lines.items() if name in PET_LINES}
        # By name: "Racial - Pandaren" sits in category 5, the other racial lines in 9.
        racial_lines = {lid: name[len(RACIAL_PREFIX):] for lid, (name, _c, _p) in lines.items()
                        if name.startswith(RACIAL_PREFIX)}
        self.class_spells = defaultdict(set)   # class -> spells on its class skill line
        self.pet_spells = defaultdict(set)     # (class, summon) -> pet spells
        self.racial = defaultdict(set)         # spell -> races (normalized names)
        for r in iter_csv(tables["SkillLineAbility"]):
            spell, line = as_int(r["Spell"]), as_int(r["SkillLine"])
            if not spell:
                continue
            if line in class_lines:
                self.class_spells[class_lines[line]].add(spell)
            elif line in pet_lines:
                self.pet_spells[pet_lines[line]].add(spell)
            elif line in racial_lines:
                self.racial[spell].add(norm(racial_lines[line]))
        self.spec_spells = defaultdict(set)
        for r in iter_csv(tables["SpecializationSpells"]):
            if as_int(r["SpellID"]):
                self.spec_spells[as_int(r["SpecID"])].add(as_int(r["SpellID"]))
        self.pvp_spells = defaultdict(set)
        for r in iter_csv(tables["PvpTalent"]):
            if as_int(r["SpellID"]):
                self.pvp_spells[as_int(r["SpecID"])].add(as_int(r["SpellID"]))
        self.talent_spells = trait_spells_by_spec(tables)

    def reach(self, spec: int) -> dict:
        """`{spell: [sources]}` a spec reaches in PvE: its class line, its spec spells, the talent
        nodes it can see, and the spells of the pets it can summon. Candidates come from this."""
        token = self.spec_class.get(spec)
        out = defaultdict(list)
        for spell in self.class_spells.get(token, ()):
            out[spell].append("class skill line")
        for spell in self.spec_spells.get(spec, ()):
            out[spell].append("spec spell")
        for spell in self.talent_spells.get(spec, ()):
            out[spell].append("talent")
        for (klass, summon), spells in self.pet_spells.items():
            if klass == token and summon in out:
                for spell in spells:
                    out[spell].append("pet (summon %d)" % summon)
        return out

    def flag_reach(self, spec: int) -> dict:
        """reach() plus what a shipped id may also be: a PvP talent of the spec, or a racial (an
        Evoker's Wing Buffet is the Dracthyr racial). Never a candidate source: the header makes
        the lists PvE-biased, and a racial is NS.RaceCastStoppers' business."""
        out = self.reach(spec)
        for spell in self.pvp_spells.get(spec, ()):
            out[spell].append("PvP talent")
        for spell, races in self.racial.items():
            out[spell].append("racial (%s)" % ", ".join(sorted(races)))
        return out

    # -- evidence -----------------------------------------------------------

    def own_evidence(self, spell: int) -> dict:
        """`{category: [why]}` from the spell and its EffectTriggerSpell closure."""
        out = defaultdict(list)
        seen = set()
        stack = [(spell, 0)]
        while stack:
            current, depth = stack.pop()
            if current in seen or depth > TRIGGER_DEPTH:
                continue
            seen.add(current)
            where = "" if current == spell else " via %d %s" % (current, self.names.get(current, ""))
            mech = self.mechanic_names.get(self.mechanic.get(current, 0))
            for cat in MECHANIC_CATEGORIES.get(mech, ()):
                out[cat].append("mechanic %s%s" % (mech, where))
            for effect, _aura, mechanic, trigger, target in self.effects.get(current, ()):
                if effect == INTERRUPT_EFFECT:
                    out["interrupt"].append("effect 68%s" % where)
                if effect in MOVEMENT_EFFECTS and target not in FRIENDLY_TARGETS:
                    out[MOVEMENT_EFFECTS[effect]].append("effect %d%s" % (effect, where))
                name = self.mechanic_names.get(mechanic)
                for cat in MECHANIC_CATEGORIES.get(name, ()):
                    out[cat].append("effect mechanic %s%s" % (name, where))
                if trigger:
                    stack.append((trigger, depth + 1))
        return {k: sorted(set(v)) for k, v in out.items()}

    def evidence(self, spell: int) -> dict:
        """own_evidence plus the family bridge: every other id with exactly this name in the same
        non-zero SpellClassSet, which is how DB2 ties a cast to the spell a server script or an
        area trigger casts in its place (Skull Bash 106839 -> 93985)."""
        if spell in self._evidence:
            return self._evidence[spell]
        out = defaultdict(list)
        for cat, why in self.own_evidence(spell).items():
            out[cat].extend(why)
        family = self.family.get(spell, 0)
        name = (self.names.get(spell) or "").lower()
        if family and name:
            for other in self.by_name.get(name, ()):
                if other != spell and self.family.get(other) == family:
                    for cat, why in self.own_evidence(other).items():
                        out[cat].append("bridge %d: %s" % (other, why[0]))
        self._evidence[spell] = {k: sorted(set(v)) for k, v in out.items()}
        return self._evidence[spell]


def norm(text: str) -> str:
    return re.sub(r"[^a-z]", "", (text or "").lower())


def trait_spells_by_spec(tables: dict) -> dict:
    """`{spec: spells}` granted by a talent node the spec can see.

        TraitDefinition (SpellID, VisibleSpellID) <- TraitNodeEntry <- TraitNodeXTraitNodeEntry
          -> TraitNode (TraitTreeID, TraitSubTreeID) <- TraitTreeLoadout (the specs of the tree)

    AuraMaster's research.py stops at the class (a class tree serves every spec of the class).
    KickCD's lists are per spec, so two more gates are read: a node, or a node group it belongs
    to, carrying a CondType 1 condition on a spec set is visible only to that set's specs; and a
    hero node (TraitSubTreeID) is visible only to the specs whose hero selection node offers its
    subtree, gated the same way.
    """
    definition_spells = defaultdict(set)
    for r in iter_csv(tables["TraitDefinition"]):
        for column in ("SpellID", "VisibleSpellID"):
            if as_int(r.get(column)):
                definition_spells[as_int(r["ID"])].add(as_int(r[column]))
    entry_definition, entry_subtree = {}, {}
    for r in iter_csv(tables["TraitNodeEntry"]):
        entry_definition[as_int(r["ID"])] = as_int(r.get("TraitDefinitionID"))
        if as_int(r.get("TraitSubTreeID")):
            entry_subtree[as_int(r["ID"])] = as_int(r["TraitSubTreeID"])
    node_entries = defaultdict(list)
    for r in iter_csv(tables["TraitNodeXTraitNodeEntry"]):
        node_entries[as_int(r["TraitNodeID"])].append(as_int(r["TraitNodeEntryID"]))
    nodes = {as_int(r["ID"]): (as_int(r["TraitTreeID"]), as_int(r.get("TraitSubTreeID")))
             for r in iter_csv(tables["TraitNode"])}
    tree_specs = defaultdict(set)
    for r in iter_csv(tables["TraitTreeLoadout"]):
        tree_specs[as_int(r["TraitTreeID"])].add(as_int(r["ChrSpecializationID"]))
    spec_sets = defaultdict(set)
    for r in iter_csv(tables["SpecSetMember"]):
        spec_sets[as_int(r["SpecSet"])].add(as_int(r["ChrSpecializationID"]))
    cond_specs = {}
    for r in iter_csv(tables["TraitCond"]):
        if as_int(r["CondType"]) == VISIBLE_COND and as_int(r.get("SpecSetID")):
            cond_specs[as_int(r["ID"])] = spec_sets.get(as_int(r["SpecSetID"]), set())
    node_conds = defaultdict(list)
    for r in iter_csv(tables["TraitNodeXTraitCond"]):
        node_conds[as_int(r["TraitNodeID"])].append(as_int(r["TraitCondID"]))
    group_conds = defaultdict(list)
    for r in iter_csv(tables["TraitNodeGroupXTraitCond"]):
        group_conds[as_int(r["TraitNodeGroupID"])].append(as_int(r["TraitCondID"]))
    for r in iter_csv(tables["TraitNodeGroupXTraitNode"]):
        node_conds[as_int(r["TraitNodeID"])].extend(group_conds.get(as_int(r["TraitNodeGroupID"]), ()))

    def visible_to(node: int) -> set:
        tree, _sub = nodes.get(node, (0, 0))
        specs = set(tree_specs.get(tree, ()))
        gates = [cond_specs[c] for c in node_conds.get(node, ()) if c in cond_specs]
        if gates:
            specs &= set().union(*gates)
        return specs

    subtree_specs = defaultdict(set)
    for node, entries in node_entries.items():
        subtrees = [entry_subtree[e] for e in entries if e in entry_subtree]
        if subtrees:
            specs = visible_to(node)
            for sub in subtrees:
                subtree_specs[sub] |= specs

    out = defaultdict(set)
    for node, entries in node_entries.items():
        if node not in nodes:
            continue
        specs = visible_to(node)
        sub = nodes[node][1]
        if sub:
            specs &= subtree_specs.get(sub, set())
        if not specs:
            continue
        for entry in entries:
            for spell in definition_spells.get(entry_definition.get(entry, 0), ()):
                for spec in specs:
                    out[spec].add(spell)
    return out


# ---------------------------------------------------------------------------
# defaults/Spells.lua
# ---------------------------------------------------------------------------

CLASS_OPEN = re.compile(r"^    (?P<cls>[A-Z]+) = \{\s*$")
SPEC_OPEN = re.compile(r"^        \[SPEC\.(?P<alias>[A-Z_]+)\] = \{\s*$")
ENTRY = re.compile(r'^(?P<indent>\s*)\{ spellID = (?P<id>\d+),\s*category = "(?P<cat>\w+)",\s*'
                   r'enabled = (?P<enabled>true|false) \},\s*(?:-- (?P<comment>.*?))?\s*$')
BLOCK_CLOSE = re.compile(r"^        \},\s*$")
RACE_OPEN = re.compile(r"^NS\.RaceCastStoppers = \{\s*$")
RACE_ENTRY = re.compile(r"^\s*(?P<race>\w+)\s*=\s*(?P<id>\d+),\s*(?:-- (?P<comment>.*?))?\s*$")
ASIDE = re.compile(r"\s*\([^)]*\)\s*$")


def read_spec_ids(path: Path = CONSTANTS_PATH) -> dict:
    """`Const.SPEC` from core/Constants.lua: alias -> numeric spec id."""
    text = path.read_text(encoding="utf-8")
    block = re.search(r"Const\.SPEC = \{(.*?)\n\}", text, re.S)
    if not block:
        raise SystemExit("%s: no Const.SPEC table." % path)
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"(\w+) = (\d+)", block.group(1))}


def comment_name(comment: str) -> str:
    return ASIDE.sub("", comment or "").strip()


def read_seeds(path: Path = SEEDS_PATH, spec_ids: dict | None = None) -> dict:
    return parse_seeds(path.read_bytes().decode("utf-8"), spec_ids, str(path))


def parse_seeds(text: str, spec_ids: dict | None = None, path: str = "defaults/Spells.lua") -> dict:
    """`{"specs": [{class, alias, spec, open, close, entries: [{id, category, enabled, comment,
    line}]}], "races": [{race, id, comment, line}]}`, line numbers 0-based. Refuses a category
    outside the closed set and a spec alias Const.SPEC lacks."""
    spec_ids = read_spec_ids() if spec_ids is None else spec_ids
    lines = text.replace("\r\n", "\n").split("\n")
    specs, races = [], []
    klass, current, in_races = None, None, False
    for number, line in enumerate(lines):
        if RACE_OPEN.match(line):
            in_races = True
            continue
        if in_races:
            m = RACE_ENTRY.match(line)
            if m:
                races.append({"race": m.group("race"), "id": int(m.group("id")),
                              "comment": m.group("comment") or "", "line": number})
            elif line.startswith("}"):
                in_races = False
            continue
        m = CLASS_OPEN.match(line)
        if m:
            klass = m.group("cls")
            continue
        m = SPEC_OPEN.match(line)
        if m and klass:
            alias = m.group("alias")
            if alias not in spec_ids:
                raise SystemExit("%s:%d: SPEC.%s is not in Const.SPEC." % (path, number + 1, alias))
            current = {"class": klass, "alias": alias, "spec": spec_ids[alias], "entries": [],
                       "open": number}
            specs.append(current)
            continue
        if current is not None:
            m = ENTRY.match(line)
            if m:
                if m.group("cat") not in CATEGORIES:
                    raise SystemExit("%s:%d: category %r is outside the closed set."
                                     % (path, number + 1, m.group("cat")))
                current["entries"].append({"id": int(m.group("id")), "category": m.group("cat"),
                                           "enabled": m.group("enabled") == "true",
                                           "comment": m.group("comment") or "", "line": number})
            elif BLOCK_CLOSE.match(line):
                current["close"] = number
                current = None
    if not specs:
        raise SystemExit("%s: no class/spec lists found." % path)
    return {"specs": specs, "races": races}


# ---------------------------------------------------------------------------
# Flags and candidates
# ---------------------------------------------------------------------------

def spec_interrupts(db: Build, reach: dict) -> set:
    """The interrupts a spec reaches in PvE: effect 68 on the cast or its own trigger closure
    (the family bridge is not used to propose, only to confirm a shipped id), with a cooldown."""
    return {s for s in reach if "interrupt" in db.own_evidence(s) and db.cooldown.get(s, 0) > 0}


def entry_flags(db: Build, block: dict, reach: dict, interrupts: set) -> list:
    out = []
    owner, scope = block["class"], str(block["spec"])
    for index, entry in enumerate(block["entries"]):
        spell, cat = entry["id"], entry["category"]
        name = db.names.get(spell, "")
        base = {"class": owner, "spec": block["spec"], "alias": block["alias"], "id": spell,
                "name": name, "comment": entry["comment"], "category": cat}
        kinds = []
        if not name:
            kinds.append(("unnamed", ""))
        else:
            wanted = comment_name(entry["comment"])
            if wanted and wanted.lower() != name.lower():
                kinds.append(("renamed", "the build names it %s" % name))
            if spell not in reach:
                kinds.append(("unreachable", "no class line, spec spell, visible talent or pet"))
            ev = db.evidence(spell)
            if cat != "other":
                if not ev:
                    kinds.append(("no-evidence", "no cast-stopping effect or mechanic in DB2"))
                elif cat not in ev:
                    kinds.append(("category", "DB2 shows " + ", ".join(sorted(ev))))
        if index == 0 and interrupts and "interrupt" not in (db.evidence(spell) if name else {}):
            kinds.append(("primary", "the spec reaches " + ", ".join(
                "%d %s" % (s, db.names.get(s, "")) for s in sorted(interrupts))))
        for kind, detail in kinds:
            row = dict(base)
            row.update({"key": "shipped:%s:%s:%s:%d" % (kind, owner, scope, spell), "kind": kind,
                        "detail": detail, "evidence": db.evidence(spell) if name else {}})
            out.append(row)
    return out


def race_flags(db: Build, races: list) -> list:
    out = []
    for entry in races:
        spell, name = entry["id"], db.names.get(entry["id"], "")
        kinds = []
        if not name:
            kinds.append(("unnamed", ""))
        else:
            wanted = comment_name(entry["comment"])
            if wanted and wanted.lower() != name.lower():
                kinds.append(("renamed", "the build names it %s" % name))
            if norm(entry["race"]) not in db.racial.get(spell, set()):
                kinds.append(("unreachable", "not on the Racial - %s skill line" % entry["race"]))
            if not db.evidence(spell):
                kinds.append(("no-evidence", "no cast-stopping effect or mechanic in DB2"))
        for kind, detail in kinds:
            out.append({"key": "shipped:%s:RACE:%s:%d" % (kind, entry["race"], spell), "kind": kind,
                        "class": "RACE", "spec": entry["race"], "alias": entry["race"], "id": spell,
                        "name": name, "comment": entry["comment"], "category": "racial",
                        "detail": detail, "evidence": db.evidence(spell) if name else {}})
    return out


def hand_candidates(db: Build, block: dict, reach: dict, missing: list,
                    entries=HAND_CANDIDATES) -> list:
    """HAND_CANDIDATES for this spec that the build names, the spec reaches and the list lacks."""
    shipped = {e["id"] for e in block["entries"]}
    out = []
    for klass, alias, spell, category, why in entries:
        if (klass, alias) != (block["class"], block["alias"]) or spell in shipped:
            continue
        if not db.names.get(spell) or spell not in reach:
            missing.append({"class": klass, "alias": alias, "id": spell, "why": why})
            continue
        out.append({"key": "%s:%d:%d" % (klass, block["spec"], spell), "class": klass,
                    "spec": block["spec"], "alias": alias, "id": spell, "name": db.names[spell],
                    "group": "interrupt" if category == "interrupt" else "cc", "category": category,
                    "evidence": dict(db.evidence(spell), hand=[why]),
                    "cooldownMs": db.cooldown.get(spell, 0), "reach": sorted(set(reach[spell]))})
    return out


def spec_candidates(db: Build, block: dict, reach: dict) -> list:
    shipped = {e["id"] for e in block["entries"]}
    out = []
    for spell in sorted(reach):
        if spell in shipped or db.cooldown.get(spell, 0) <= 0 or not db.names.get(spell):
            continue
        ev = db.own_evidence(spell)
        proposed = next((c for c in PROPOSE_ORDER if c in ev), None)
        if proposed is None:
            continue
        out.append({"key": "%s:%d:%d" % (block["class"], block["spec"], spell),
                    "class": block["class"], "spec": block["spec"], "alias": block["alias"],
                    "id": spell, "name": db.names[spell],
                    "group": "interrupt" if proposed == "interrupt" else "cc",
                    "category": proposed, "evidence": ev, "cooldownMs": db.cooldown[spell],
                    "reach": sorted(set(reach[spell]))})
    return out


def derive(db: Build, seeds: dict, build: str, date: str) -> dict:
    candidates, flags, specs, missing = [], [], [], []
    for block in seeds["specs"]:
        if db.spec_class.get(block["spec"]) != block["class"]:
            raise SystemExit("SPEC.%s (%d) is not a %s specialization on this build."
                             % (block["alias"], block["spec"], block["class"]))
        reach = db.reach(block["spec"])
        interrupts = spec_interrupts(db, reach)
        flags.extend(entry_flags(db, block, db.flag_reach(block["spec"]), interrupts))
        found = spec_candidates(db, block, reach)
        found += [c for c in hand_candidates(db, block, reach, missing)
                  if c["key"] not in {f["key"] for f in found}]
        candidates.extend(found)
        specs.append({"class": block["class"], "spec": block["spec"], "alias": block["alias"],
                      "name": db.spec_name.get(block["spec"], ""), "reach": len(reach),
                      "shipped": len(block["entries"]),
                      "interrupts": sorted(interrupts), "candidates": len(found)})
    flags.extend(race_flags(db, seeds["races"]))
    shipped = sum(len(b["entries"]) for b in seeds["specs"]) + len(seeds["races"])
    distinct = {e["id"] for b in seeds["specs"] for e in b["entries"]} | {r["id"] for r in seeds["races"]}
    return {"client": CLIENT, "product": PRODUCT, "build": build, "date": date,
            "tool": "tools/seeds/seeds.py derive", "shippedEntries": shipped,
            "shippedIds": len(distinct), "specs": specs, "candidates": candidates, "flags": flags,
            "handMissing": missing}


# ---------------------------------------------------------------------------
# Rulings
# ---------------------------------------------------------------------------

def load_rulings(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save_rulings(path: Path, rulings: dict) -> None:
    write_text(path, json.dumps(rulings, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def read_tsv(path: Path) -> list:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit("%s: a ruling line is key<TAB>ruling<TAB>reason; got %r" % (path, line))
        out.append(tuple(p.strip() for p in parts))
    return out


def set_ruling(rulings: dict, key: str, ruling: str, reason: str) -> None:
    match = KEY.match(key)
    if not match:
        raise SystemExit("%r is not <CLASS>:<spec>:<id> or shipped:<kind>:<CLASS>:<spec>:<id>." % key)
    kind = match.group("kind")
    if kind and kind not in FLAG_KINDS:
        raise SystemExit("%r: unknown flag kind %r." % (key, kind))
    allowed = FLAG_RULINGS if kind else CANDIDATE_RULINGS
    if kind == "primary":
        allowed = ("keep",)  # removing index 1 is not what a primary flag asks; reorder by hand
    if ruling not in allowed:
        raise SystemExit("ruling for %s must be %s; got %r." % (key, " or ".join(allowed), ruling))
    reason = (reason or "").strip()
    if not reason or "\n" in reason:
        raise SystemExit("reason for %s must be one non-empty line." % key)
    rulings[key] = {"ruling": ruling, "reason": reason}


def load_candidates(bundle: Path) -> dict:
    path = bundle / "candidates.json"
    if not path.exists():
        raise SystemExit("%s has no candidates.json: run derive first." % bundle)
    return json.loads(path.read_text(encoding="utf-8"))


def all_keys(doc: dict) -> list:
    return [c["key"] for c in doc["candidates"]] + [f["key"] for f in doc["flags"]]


def unruled_keys(doc: dict, rulings: dict) -> list:
    return [k for k in all_keys(doc) if k not in rulings]


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

def plan_apply(doc: dict, rulings: dict) -> tuple:
    """`(inserts, removals)`. Refuses while anything is unruled."""
    unruled = unruled_keys(doc, rulings)
    if unruled:
        raise SystemExit("apply refused: %d key(s) unruled (seeds.py check lists them)." % len(unruled))
    inserts = [c for c in doc["candidates"] if rulings[c["key"]]["ruling"] == "accept"]
    removals = [f for f in doc["flags"] if rulings[f["key"]]["ruling"] == "remove"]
    return inserts, removals


def format_entry(template: str, spell: int, category: str, comment: str) -> str:
    """An entry line in the block's own layout: `category` and `enabled` start in the columns
    they start in on `template` (another entry of the same block), at least one space apart."""
    indent = re.match(r"\s*", template).group(0)
    cat_col, en_col = template.index("category ="), template.index("enabled =")
    line = "%s{ spellID = %d," % (indent, spell)
    line += " " * max(1, cat_col - len(line))
    line += 'category = "%s",' % category
    line += " " * max(1, en_col - len(line))
    return line + "enabled = true }, -- %s" % comment


def apply_text(text: str, doc: dict, rulings: dict, date: str, spec_ids: dict | None = None) -> tuple:
    """`(new text, change log)` for defaults/Spells.lua's text. Line endings are kept.

    Where an accepted candidate goes in its spec's list, which is the priority order:
      - in the place of a removed entry of the same name in the same list (a corrected id);
      - else an interrupt after the interrupts the list leads with (index 1 is the primary);
      - else at the end of the list.
    """
    inserts, removals = plan_apply(doc, rulings)
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    changes = []
    drop = set()
    replaced = {}  # (class, spec, name) -> the line of a removed entry of that name
    seeds = parse_seeds("\n".join(lines), spec_ids)
    blocks = {(b["class"], b["spec"]): b for b in seeds["specs"]}
    for flag in removals:
        if flag["class"] == "RACE":
            for race in seeds["races"]:
                if race["race"] == flag["spec"] and race["id"] == flag["id"]:
                    drop.add(race["line"])
                    changes.append("RACE %s: -%d" % (flag["spec"], flag["id"]))
            continue
        block = blocks.get((flag["class"], flag["spec"]))
        for entry in block["entries"] if block else ():
            if entry["id"] == flag["id"] and entry["line"] not in drop:
                drop.add(entry["line"])
                replaced.setdefault((flag["class"], flag["spec"], (flag["name"] or "").lower()), entry["line"])
                changes.append("%s %s: -%d" % (flag["class"], flag["alias"], flag["id"]))
    added = defaultdict(list)  # line index -> lines to insert before it
    for cand in inserts:
        block = blocks.get((cand["class"], cand["spec"]))
        if block is None or any(e["id"] == cand["id"] for e in block["entries"]):
            continue
        entries = [e for e in block["entries"] if e["line"] not in drop]
        template = lines[(entries or block["entries"])[0]["line"]]
        comment = "%s (DB2 re-validation %s)" % (cand["name"], date)
        line = format_entry(template, cand["id"], cand["category"], comment)
        slot = replaced.get((cand["class"], cand["spec"], cand["name"].lower()))
        if slot is not None:
            at = slot  # the same ability under its right id: it takes the removed entry's place
        elif cand["category"] == "interrupt":
            lead = 0
            while lead < len(entries) and entries[lead]["category"] == "interrupt":
                lead += 1
            at = entries[lead]["line"] if lead < len(entries) else block["close"]
        else:
            at = block["close"]
        added[at].append(line)
        changes.append("%s %s: +%d %s (%s)" % (cand["class"], cand["alias"], cand["id"],
                                               cand["name"], cand["category"]))
    out = []
    for index, line in enumerate(lines):
        out.extend(added.get(index, ()))
        if index not in drop:
            out.append(line)
    return newline.join(out), changes


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

def _cell(text) -> str:
    return str(text or "").replace("|", "\\|")


def _evidence(ev: dict) -> str:
    return "; ".join("%s: %s" % (k, ", ".join(v[:2])) for k, v in sorted(ev.items()))


def format_rulings_md(doc: dict, rulings: dict, date: str) -> str:
    tally = defaultdict(int)
    for key in all_keys(doc):
        tally[rulings.get(key, {}).get("ruling", "unruled")] += 1
    unruled = unruled_keys(doc, rulings)
    out = ["# Rulings: Retail seed validation, %s (build %s)" % (doc["date"], doc["build"]), "",
           "Generated by `tools/seeds/seeds.py report` on %s from this bundle's `candidates.json` "
           "and `tools/seeds/rulings_retail.json`. Do not edit by hand." % date, "",
           "%d shipped entries (%d distinct ids), %d flags, %d candidates: %s." % (
               doc["shippedEntries"], doc["shippedIds"], len(doc["flags"]), len(doc["candidates"]),
               ", ".join("%d %s" % (n, r) for r, n in sorted(tally.items()))), ""]
    if unruled:
        out += ["## Unruled: %d" % len(unruled), ""] + ["- `%s`" % k for k in unruled] + [""]
    out += ["## Shipped-id flags: %d" % len(doc["flags"]), ""]
    if doc["flags"]:
        out += ["| Kind | Class | Spec | Id | Build name | Category | Detail | Ruling | Reason |",
                "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for f in doc["flags"]:
            r = rulings.get(f["key"], {})
            out.append("| %s | %s | %s | `%d` | %s | %s | %s | %s | %s |" % (
                f["kind"], f["class"], f["alias"], f["id"], _cell(f["name"]), f["category"],
                _cell(f["detail"]), r.get("ruling", "**unruled**"), _cell(r.get("reason"))))
    else:
        out.append("None.")
    out.append("")
    for group, title in (("interrupt", "Interrupt candidates"), ("cc", "Cast-stopping CC candidates")):
        rows = [c for c in doc["candidates"] if c["group"] == group]
        out += ["## %s: %d" % (title, len(rows)), ""]
        if not rows:
            out += ["None.", ""]
            continue
        out += ["| Class | Spec | Id | Name | Proposed | Cooldown | Evidence | Ruling | Reason |",
                "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for c in rows:
            r = rulings.get(c["key"], {})
            out.append("| %s | %s | `%d` | %s | %s | %gs | %s | %s | %s |" % (
                c["class"], c["alias"], c["id"], _cell(c["name"]), c["category"],
                c["cooldownMs"] / 1000.0, _cell(_evidence(c["evidence"])),
                r.get("ruling", "**unruled**"), _cell(r.get("reason"))))
        out.append("")
    return "\n".join(out)


def format_sources_md(doc: dict, date: str) -> str:
    out = ["# Sources: Retail seed validation, %s" % date, "",
           "Written by `tools/seeds/seeds.py derive`. Frozen: never edited after the run, apart from "
           "the hand-written `ANALYSIS.md` beside it.", "",
           "| Field | Value |", "| --- | --- |",
           "| Client | `%s` (wago.tools product `%s`) |" % (CLIENT, PRODUCT),
           "| Build | `%s` |" % doc["build"],
           "| Run date | %s (the run's `--date` argument; the tool never reads the clock) |" % date,
           "| Builds API | <%s> |" % BUILDS_URL,
           "| User-Agent | `%s` |" % USER_AGENT,
           "| Seed file | `defaults/Spells.lua`: %d entries, %d distinct ids |" % (doc["shippedEntries"], doc["shippedIds"]),
           "", "## Tables", "", "| Table | Why | URL |", "| --- | --- | --- |"]
    for table, why in TABLES:
        url = CSV_URL.format(table=table, build=doc["build"])
        out.append("| `%s` | %s | <%s> |" % (table, why, url))
    out += ["", "Every table is frozen gzipped in `raw/`, and `seeds.py derive --replay` re-derives "
            "this bundle from them alone.", "",
            "## Per-spec counts", "", "| Class | Spec | Reach | Shipped | Interrupts reached | Candidates |",
            "| --- | --- | --- | --- | --- | --- |"]
    for s in doc["specs"]:
        out.append("| %s | %s (%d) | %d | %d | %s | %d |" % (
            s["class"], s["alias"], s["spec"], s["reach"], s["shipped"],
            ", ".join(str(i) for i in s["interrupts"]) or "none", s["candidates"]))
    out.append("")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def _date(value: str) -> str:
    if not DATE_RE.match(value):
        raise argparse.ArgumentTypeError("a date is YYYY-MM-DD; got %r" % value)
    return value


def bundles(root: Path) -> list:
    return sorted(p for p in root.glob("*" + BUNDLE_SUFFIX) if (p / "candidates.json").exists())


def status_line(live: str, found: list) -> str:
    """`CURRENT <build> (<bundle>)` or `NEW <build> ...`; the first word is what
    /dev-copilot:validate-seeds reads."""
    if not found:
        return "NEW %s (no bundle yet)" % live
    last = found[-1]
    built = json.loads((last / "candidates.json").read_text(encoding="utf-8"))["build"]
    if built == live:
        return "CURRENT %s (%s)" % (live, last.name)
    return "NEW %s (last ruled %s, %s)" % (live, built, last.name)


def cmd_status(args) -> int:
    print(status_line(live_build(), bundles(args.root)))
    return 0


def cmd_derive(args) -> int:
    build = args.build
    if args.replay and not build:
        build = load_candidates(args.bundle)["build"]
    if not build:
        build = live_build()
    log("Build %s (%s)" % (build, "replay" if args.replay else "wago.tools"))
    tables = bundle_tables(args.bundle, build, args.replay, args.cache_dir)
    db = Build(tables)
    doc = derive(db, read_seeds(args.seeds), build, args.date)
    write_json(args.bundle / "candidates.json", doc)
    write_text(args.bundle / "SOURCES.md", format_sources_md(doc, args.date))
    unruled = unruled_keys(doc, load_rulings(args.rulings))
    groups = defaultdict(int)
    for c in doc["candidates"]:
        groups[c["group"]] += 1
    kinds = defaultdict(int)
    for f in doc["flags"]:
        kinds[f["kind"]] += 1
    log("%d shipped entries (%d ids); flags %s; candidates %s; %d unruled" % (
        doc["shippedEntries"], doc["shippedIds"], dict(kinds), dict(groups), len(unruled)))
    return 0


def cmd_rule(args) -> int:
    todo = [(k, args.ruling, args.reason) for k in (args.key or ())]
    if args.tsv:
        todo += read_tsv(args.tsv)
    if not todo:
        raise SystemExit("rule needs --key (with --ruling and --reason) or --tsv.")
    known = set(all_keys(load_candidates(args.bundle))) if args.bundle else None
    rulings = load_rulings(args.rulings)
    for key, ruling, reason in todo:
        if known is not None and key not in known:
            raise SystemExit("%s is not a candidate or flag in %s/candidates.json." % (key, args.bundle))
        set_ruling(rulings, key, ruling, reason)
    save_rulings(args.rulings, rulings)
    log("Recorded %d ruling(s) in %s" % (len(todo), args.rulings))
    return 0


def cmd_check(args) -> int:
    doc = load_candidates(args.bundle)
    unruled = unruled_keys(doc, load_rulings(args.rulings))
    if not unruled:
        print("OK: every candidate and flag in %s is ruled." % args.bundle.name)
        return 0
    rows = {c["key"]: c for c in doc["candidates"]}
    rows.update({f["key"]: f for f in doc["flags"]})
    print("%d unruled:" % len(unruled))
    for key in unruled:
        print("  %s  %s" % (key, rows[key]["name"]))
    return 1


def cmd_report(args) -> int:
    doc = load_candidates(args.bundle)
    write_text(args.bundle / "RULINGS.md", format_rulings_md(doc, load_rulings(args.rulings), args.date))
    log("Wrote %s" % (args.bundle / "RULINGS.md"))
    return 0


def cmd_apply(args) -> int:
    doc = load_candidates(args.bundle)
    text = args.seeds.read_bytes().decode("utf-8")
    new, changes = apply_text(text, doc, load_rulings(args.rulings), args.date)
    if new != text:
        args.seeds.write_bytes(new.encode("utf-8"))
    for line in changes:
        log("  " + line)
    log("%d change(s) to %s" % (len(changes), args.seeds))
    return 0


def parse_args(argv):
    p = argparse.ArgumentParser(description="Re-validate KickCD's cast-stopper seeds against a wago.tools build.")
    p.add_argument("--rulings", type=Path, default=RULINGS_PATH)
    p.add_argument("--seeds", type=Path, default=SEEDS_PATH)
    p.add_argument("--cache-dir", type=Path, default=CACHE_DIR)
    sub = p.add_subparsers(dest="command", required=True)
    st = sub.add_parser("status", help="is the live Retail build newer than the newest bundle?")
    st.add_argument("--flavor", choices=(CLIENT,), default=CLIENT)
    st.add_argument("--root", type=Path, default=RESEARCH)
    d = sub.add_parser("derive", help="flags and candidates into the bundle")
    d.add_argument("--flavor", choices=(CLIENT,), default=CLIENT)
    d.add_argument("--bundle", type=Path, required=True)
    d.add_argument("--date", type=_date, required=True)
    d.add_argument("--build")
    d.add_argument("--replay", action="store_true", help="read only the bundle's raw/, no network")
    r = sub.add_parser("rule", help="record rulings (the only writer of the rulings file)")
    r.add_argument("--key", action="append")
    r.add_argument("--ruling")
    r.add_argument("--reason")
    r.add_argument("--tsv", type=Path)
    r.add_argument("--bundle", type=Path, help="refuse keys this bundle does not carry")
    for name in ("check", "report", "apply"):
        c = sub.add_parser(name)
        c.add_argument("--bundle", type=Path, required=True)
        if name != "check":
            c.add_argument("--date", type=_date, required=True)
    return p.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    return {"status": cmd_status, "derive": cmd_derive, "rule": cmd_rule, "check": cmd_check,
            "report": cmd_report, "apply": cmd_apply}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
