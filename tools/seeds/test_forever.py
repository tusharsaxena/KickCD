"""tools/seeds/test_forever.py: offline tests for the `forever` flavor (forever.py; no network).

Run: python3 -m unittest discover -s tools/seeds -p 'test_*.py'

The build is a tiny WoW Forever fixture: two classes (WARRIOR 1491, WARLOCK 1490) with one spec
each, the pet spec 1493, tree skill lines with SkillRaceClassInfo masks, a multi-class rune line,
a never-learned row, a talent on a trait tree joined through SkillLineXTraitTree, a pet line
gated on its summon, ranked families named by Spell.NameSubtext_lang, and two racial lines in
both of Forever's naming shapes.
"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import seeds  # noqa: E402
import forever  # noqa: E402

SPEC_IDS = {"WARRIOR": 1491, "WARLOCK": 1490}

FIXTURE = {
    "SpellName": ["ID,Name_lang",
                  "6552,Pummel", "6554,Pummel", "6553,Pummel", "72,Shield Bash", "425609,Rune Kick",
                  "440488,Rune Stun", "12809,Concussion Blow", "5246,Intimidating Shout",
                  "5247,Intimidating Shout Fear", "7384,Overpower", "20549,War Stomp",
                  "691,Summon Felhunter", "19244,Spell Lock", "19647,Spell Lock",
                  "427733,Summon Felguard", "427745,Felguard Intercept", "5782,Fear"],
    "Spell": ["ID,NameSubtext_lang",
              "6552,Rank 1", "6554,Rank 2", "6553,Glyphed", "72,Rank 1", "19244,Rank 1", "19647,Rank 2"],
    "SpellEffect": ["ID,SpellID,DifficultyID,Effect,EffectAura,EffectMechanic,EffectTriggerSpell,ImplicitTarget_0",
                    "1,6552,0,68,0,0,0,6", "2,6554,0,68,0,0,0,6", "14,6553,0,68,0,0,0,6", "3,72,0,68,0,0,0,6",
                    "4,425609,0,68,0,0,0,6",         # a rune interrupt: never learned
                    "5,440488,0,6,12,12,0,6",        # a rune stun on the multi-class line
                    "6,12809,0,6,12,12,0,6",         # the talent stun
                    "7,5246,0,64,0,0,5247,6",        # the shout triggers the fear
                    "8,5247,0,6,7,5,0,6",
                    "9,19244,0,68,0,0,0,6", "10,19647,0,68,0,0,0,6",
                    "11,427745,0,68,0,0,0,6",        # the Felguard's: its summon is unreachable
                    "12,20549,0,6,12,12,0,6",        # War Stomp stuns
                    "13,5782,0,6,7,5,0,6"],          # Fear fears, with no cooldown
    "SpellCategories": ["ID,SpellID,DifficultyID,Mechanic,ChargeCategory"],
    "SpellMechanic": ["ID,StateName_lang", "5,fleeing", "12,stunned"],
    "SpellCooldowns": ["ID,SpellID,DifficultyID,RecoveryTime,CategoryRecoveryTime",
                       "1,6552,0,10000,0", "2,6554,0,10000,0", "12,6553,0,10000,0", "3,72,0,12000,0",
                       "4,425609,0,10000,0", "5,440488,0,30000,0", "6,12809,0,45000,0",
                       "7,5246,0,180000,0", "8,19244,0,30000,0", "9,19647,0,30000,0",
                       "10,427745,0,30000,0", "11,20549,0,90000,0"],
    "SpellCategory": ["ID,ChargeRecoveryTime"],
    "SpellClassOptions": ["ID,SpellID,SpellClassSet"],
    "SkillLine": ["DisplayName_lang,ID,CategoryID,ParentSkillLineID",
                  "Arms,26,7,0", "Protection,257,7,0", "Demonology,354,7,0",
                  '"Pet - Felhunter",189,7,0', '"Pet - Felguard",2887,7,0', "Engraving,2851,7,0",
                  '"Tauren Racial",124,9,0', '"Racial - Human",754,9,0'],
    "SkillRaceClassInfo": ["ID,SkillID,ClassMask",
                           "1,26,1", "2,257,1", "3,354,256", "4,2851,1503"],
    "SkillLineAbility": ["ID,SkillLine,Spell,ClassMask,SupercedesSpell,AcquireMethod",
                         "1,26,6552,0,0,0", "2,26,6554,0,6552,0", "14,26,6553,0,0,0", "3,257,72,0,0,0",
                         "4,26,425609,0,0,3",       # never learned (a rune grant)
                         "5,2851,440488,1,0,0",     # a rune line every class shares
                         "6,26,5246,0,0,0", "7,26,7384,0,0,0",
                         "8,354,691,256,0,0", "9,189,19244,0,0,0", "10,189,19647,0,19244,0",
                         "11,2887,427745,0,0,0", "12,124,20549,0,0,2", "13,354,5782,0,0,0"],
    "ChrSpecialization": ["ID,ClassID,Name_lang", "1491,1,Warrior", "1490,9,Warlock",
                          "1493,0,Default"],
    "SkillLineXTraitTree": ["ID,SkillLineID,TraitTreeID", "1,26,1117", "2,354,1116"],
    "TraitDefinition": ["ID,SpellID,VisibleSpellID", "1,12809,0"],
    "TraitNodeEntry": ["ID,TraitDefinitionID,TraitSubTreeID", "11,1,0"],
    "TraitNodeXTraitNodeEntry": ["ID,TraitNodeID,TraitNodeEntryID", "1,101,11"],
    "TraitNode": ["ID,TraitTreeID,TraitSubTreeID", "101,1117,0"],
}

SEEDS = """-- defaults/Spells_Forever.lua (fixture)
local _, NS = ...
local SPEC = NS.Const.SPEC_FOREVER

NS.DefaultSpellsForever = {

    WARRIOR = {
        [SPEC.WARRIOR] = {
        },
    },

    WARLOCK = {
        [SPEC.WARLOCK] = {
            { spellID = 19647,  category = "interrupt",    enabled = true }, -- Spell Lock
        },
    },
}

NS.RaceCastStoppersForever = {
    Tauren = 20549, -- War Stomp
    Human  = 6552,  -- Pummel
}
"""

HAND = (("WARRIOR", "WARRIOR", 20549, "racial", "the Tauren racial in a Tauren class's list"),
        ("WARLOCK", "WARLOCK", 5782, "fear", "no cooldown: core by the owner's ruling"),
        ("WARLOCK", "WARLOCK", 427745, "interrupt", "the Felguard's: its summon is unreachable"))


def write_fixture(root: Path) -> dict:
    out = {}
    for table, _why in forever.TABLES:
        path = root / ("%s.csv" % table)
        path.write_text("\n".join(FIXTURE[table]) + "\n", encoding="utf-8")
        out[table] = path
    return out


class Fixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.db = forever.ForeverBuild(write_fixture(cls.tmp))
        cls.seeds = seeds.parse_seeds(SEEDS, SPEC_IDS, "defaults/Spells_Forever.lua")
        flavor = forever.FOREVER
        cls.flavor = seeds.Flavor(flavor.client, flavor.label, flavor.product, flavor.seeds_path,
                                  flavor.rulings_path, flavor.spec_table, flavor.tables,
                                  flavor.build_cls, hand=HAND, finish=flavor.finish,
                                  comment=flavor.comment)
        cls.doc = seeds.derive(cls.db, cls.seeds, "1.60.1.1", "2026-11-23", cls.flavor)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def cand(self, key):
        return next((c for c in self.doc["candidates"] if c["key"] == key), None)

    def keys(self):
        return {c["key"] for c in self.doc["candidates"]}


class TestFlavor(unittest.TestCase):
    def test_the_flavor_names_its_own_files_and_product(self):
        f = seeds.get_flavor("forever")
        self.assertIs(f, forever.FOREVER)
        self.assertEqual((f.client, f.product, f.suffix, f.spec_table),
                         ("forever", "wowf", "-forever", "SPEC_FOREVER"))
        self.assertEqual(f.seeds_path.name, "Spells_Forever.lua")
        self.assertEqual(f.rulings_path.name, "rulings_forever.json")
        self.assertIs(f.build_cls, forever.ForeverBuild)

    def test_retail_is_unchanged_by_the_registry(self):
        r = seeds.get_flavor("retail")
        self.assertEqual((r.client, r.product, r.seeds_path.name, r.rulings_path.name),
                         ("retail", "wow", "Spells.lua", "rulings_retail.json"))
        self.assertIs(r.tables, seeds.TABLES)
        with self.assertRaises(SystemExit):
            seeds.get_flavor("classic")

    def test_command_line_defaults_follow_the_flavor(self):
        args = seeds.parse_args(["check", "--flavor", "forever", "--bundle", "b"])
        self.assertEqual(args.rulings.name, "rulings_forever.json")
        self.assertEqual(args.seeds.name, "Spells_Forever.lua")
        args = seeds.parse_args(["check", "--bundle", "b"])
        self.assertEqual(args.rulings.name, "rulings_retail.json")

    def test_the_forever_spec_table_comes_from_constants(self):
        ids = forever.FOREVER.spec_ids()
        self.assertEqual(ids, {"WARRIOR": 1491, "PALADIN": 1486, "HUNTER": 1485, "ROGUE": 1488,
                               "PRIEST": 1487, "SHAMAN": 1489, "MAGE": 1482, "WARLOCK": 1490,
                               "DRUID": 1484})
        self.assertEqual(seeds.read_spec_ids()["ELEMENTAL"], 262)   # Retail's table is untouched

    def test_hand_candidates_carry_the_core_spells_no_rule_proposes(self):
        by_id = {}
        for klass, alias, spell, category, why in forever.HAND_CANDIDATES:
            self.assertEqual(klass, alias, "a Forever spec alias is its class token")
            self.assertIn(category, seeds.CATEGORIES)
            self.assertTrue(why)
            by_id.setdefault(spell, set()).add(klass)
        for spell in (1833, 118, 5782, 605):        # Cheap Shot, Polymorph, Fear, Mind Control
            self.assertIn(spell, by_id)
        self.assertIn(1499, by_id)                  # Freezing Trap: the freeze is the trap's
        # The owner's optional column, proposed so that each R7 rejection is a ruling on record.
        for spell in (2812, 8177, 6358, 9005, 2637):
            self.assertIn(spell, by_id)
        self.assertEqual(by_id[20549], {"WARRIOR", "HUNTER", "SHAMAN", "DRUID"})


class TestReach(Fixture):
    def test_class_lines_come_from_the_skill_class_mask(self):
        r = self.db.reach(1491)
        self.assertIn("class skill line", r[6552])
        self.assertIn(72, r)                          # the second tree's line
        self.assertNotIn(5782, r)                     # a warlock line

    def test_never_learned_and_shared_rune_lines_are_not_reach(self):
        r = self.db.reach(1491)
        self.assertNotIn(425609, r)
        self.assertNotIn(440488, r)

    def test_talents_join_through_the_tree_skill_line(self):
        self.assertIn("talent", self.db.reach(1491)[12809])
        self.assertNotIn(12809, self.db.reach(1490))

    def test_pet_spells_need_a_reachable_summon(self):
        r = self.db.reach(1490)
        self.assertIn(19244, r)
        self.assertNotIn(427745, r)                   # Summon Felguard has no learn row

    def test_racials_in_both_naming_shapes_are_flag_reach_only(self):
        self.assertNotIn(20549, self.db.reach(1491))
        self.assertIn(20549, self.db.flag_reach(1491))
        self.assertEqual(self.db.racial[20549], {"tauren"})

    def test_the_pet_spec_is_no_class(self):
        self.assertNotIn(1493, self.db.spec_class)


class TestCandidates(Fixture):
    def test_one_candidate_per_rank_family_at_rank_1(self):
        c = self.cand("WARRIOR:1491:6552")
        self.assertEqual((c["group"], c["category"]), ("interrupt", "interrupt"))
        self.assertEqual(c["ranks"], [6552, 6554])     # a same-name variant is no rank
        self.assertNotIn("WARRIOR:1491:6554", self.keys())
        self.assertNotIn("WARRIOR:1491:6553", self.keys())

    def test_a_family_with_any_rank_shipped_is_not_proposed(self):
        self.assertFalse(any(k.startswith("WARLOCK:1490:196") or k == "WARLOCK:1490:19244"
                             for k in self.keys()))

    def test_cc_and_talent_candidates(self):
        self.assertEqual(self.cand("WARRIOR:1491:12809")["category"], "stun")
        self.assertEqual(self.cand("WARRIOR:1491:5246")["category"], "fear")
        self.assertEqual(self.cand("WARRIOR:1491:72")["ranks"], [72])

    def test_never_proposed(self):
        keys = self.keys()
        for key in ("WARRIOR:1491:425609", "WARRIOR:1491:440488", "WARRIOR:1491:7384",
                    "WARLOCK:1490:427745"):
            self.assertNotIn(key, keys)

    def test_hand_candidates(self):
        stomp = self.cand("WARRIOR:1491:20549")
        self.assertEqual(stomp["category"], "racial")
        self.assertIn("hand", stomp["evidence"])
        self.assertTrue(any(r.startswith("racial") for r in stomp["reach"]))
        self.assertEqual(self.cand("WARLOCK:1490:5782")["category"], "fear")
        self.assertEqual([m["id"] for m in self.doc["handMissing"]], [427745])

    def test_the_doc_names_the_forever_client(self):
        self.assertEqual((self.doc["client"], self.doc["product"]), ("forever", "wowf"))

    def test_race_flags(self):
        flags = {f["key"] for f in self.doc["flags"]}
        self.assertIn("shipped:unreachable:RACE:Human:6552", flags)
        self.assertFalse(any(k.endswith(":RACE:Tauren:20549") and "unreachable" in k for k in flags))


class TestApply(Fixture):
    def test_a_first_run_fills_an_empty_list_interrupts_first_and_is_idempotent(self):
        rulings = {c["key"]: {"ruling": "accept", "reason": "x"} for c in self.doc["candidates"]}
        rulings.update({f["key"]: {"ruling": "keep", "reason": "x"} for f in self.doc["flags"]})
        text = SEEDS.replace("\n", "\r\n")
        new, changes = seeds.apply_text(text, self.doc, rulings, "2026-11-23", SPEC_IDS,
                                        forever.FOREVER.comment)
        self.assertEqual(len(changes), len(self.doc["candidates"]))
        self.assertNotIn("\n", new.replace("\r\n", ""))
        lines = new.split("\r\n")
        at = lines.index("        [SPEC.WARRIOR] = {")
        block = lines[at + 1:lines.index("        },", at)]
        cats = [seeds.ENTRY.match(line).group("cat") for line in block]
        self.assertEqual(cats[:2], ["interrupt", "interrupt"])
        self.assertNotIn("interrupt", cats[2:])
        self.assertIn("-- Pummel (DB2 seed 2026-11-23)", new)
        template = seeds.DEFAULT_ENTRY_TEMPLATE
        for line in block:
            self.assertEqual(line.index("category ="), template.index("category ="))
        again, more = seeds.apply_text(new, self.doc, rulings, "2026-11-23", SPEC_IDS)
        self.assertEqual((again, more), (new, []))

    def test_a_bundle_of_the_other_flavor_is_refused(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            (tmp / "candidates.json").write_text(json.dumps({"client": "retail"}))
            with self.assertRaises(SystemExit):
                seeds.load_candidates(tmp, forever.FOREVER)
            self.assertEqual(seeds.load_candidates(tmp, seeds.RETAIL)["client"], "retail")
        finally:
            shutil.rmtree(tmp)


class TestReports(Fixture):
    def test_sources_and_rulings_name_the_flavor(self):
        sources = seeds.format_sources_md(self.doc, "2026-11-23", forever.FOREVER)
        self.assertIn("# Sources: WoW Forever seed validation, 2026-11-23", sources)
        self.assertIn("product `wowf`", sources)
        self.assertIn("`defaults/Spells_Forever.lua`", sources)
        self.assertIn("SkillRaceClassInfo", sources)
        md = seeds.format_rulings_md(self.doc, {}, "2026-11-23", forever.FOREVER)
        self.assertIn("# Rulings: WoW Forever seed validation", md)
        self.assertIn("tools/seeds/rulings_forever.json", md)

    def test_status_reads_only_forever_bundles(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            for name, build in (("2026-11-15-retail", "12.1"), ("2026-11-23-forever", "1.60")):
                (tmp / name).mkdir()
                (tmp / name / "candidates.json").write_text(json.dumps({"build": build}))
            found = seeds.bundles(tmp, forever.FOREVER.suffix)
            self.assertEqual(seeds.status_line("1.60", found), "CURRENT 1.60 (2026-11-23-forever)")
        finally:
            shutil.rmtree(tmp)


class TestCommittedRun(unittest.TestCase):
    """The committed 71037 run: every key its candidates.json carries is ruled in the rulings
    file, which is what `seeds.py check --flavor forever` prints OK for."""

    def test_the_committed_bundle_is_fully_ruled(self):
        bundles = seeds.bundles(seeds.RESEARCH, forever.FOREVER.suffix)
        self.assertTrue(bundles, "no docs/seed-research/*-forever bundle")
        doc = seeds.load_candidates(bundles[-1], forever.FOREVER)
        rulings = seeds.load_rulings(forever.FOREVER.rulings_path)
        self.assertEqual(seeds.unruled_keys(doc, rulings), [])
        for name in ("SOURCES.md", "RULINGS.md", "ANALYSIS.md"):
            self.assertTrue((bundles[-1] / name).exists(), name)
        for table, _why in forever.TABLES:
            self.assertTrue((bundles[-1] / "raw" / ("%s.csv.gz" % table)).exists(), table)


if __name__ == "__main__":
    unittest.main()
