"""tools/seeds/test_seeds.py: offline tests for seeds.py (no network).

Run: python3 -m unittest discover -s tools/seeds -p 'test_*.py'

The build is a tiny fixture written into a temporary directory: one class (WARRIOR) with two
specs (71 Arms, 73 Protection) and one pet line, enough to exercise every reach source, every
evidence path, every flag kind, both candidate groups, the rulings guard and the writer.
"""

import gzip
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import seeds  # noqa: E402

SPEC_IDS = {"ARMS": 71, "PROTECTION_WARRIOR": 73}

# One CSV per table: a header row, then rows. Only the columns seeds.py reads.
FIXTURE = {
    "SpellName": ["ID,Name_lang",
                  "6552,Pummel", "100,Charge", "200,Storm Bolt", "201,Storm Bolt",
                  "300,Shout", "400,Hamstring", "500,Shockwave", "600,Old Bash", "700,Bash Aura",
                  "800,Disrupting Shout", "900,Leap", "950,Pet Bite", "960,Summon Hound",
                  "970,War Stomp", "980,Hero Kick", "990,Spec Stun", "991,Passive Stun",
                  "992,Slam"],
    "SpellEffect": ["ID,SpellID,DifficultyID,Effect,EffectAura,EffectMechanic,EffectTriggerSpell,ImplicitTarget_0",
                    "1,6552,0,68,0,0,0,6",       # Pummel interrupts
                    "2,100,0,96,0,0,0,6",        # Charge: no cast-stopping effect
                    "3,200,0,3,0,0,0,6",         # Storm Bolt cast: a dummy (server script)
                    "4,201,0,6,12,12,0,6",       # Storm Bolt stun aura (same name, same family)
                    "5,300,0,64,0,0,301,6",      # Shout triggers 301
                    "6,301,0,6,7,5,0,6",         # ... which fears (fleeing)
                    "7,400,0,6,0,7,0,6",         # Hamstring roots: never a candidate
                    "8,800,0,68,0,0,0,6",        # Disrupting Shout interrupts
                    "9,900,0,144,0,0,0,1",       # Leap knocks the CASTER: no evidence
                    "10,950,0,68,0,0,0,6",       # the pet interrupts
                    "11,980,0,68,0,0,0,6",       # the hero talent interrupts
                    "12,990,0,6,12,12,0,6",      # Spec Stun stuns
                    "13,991,0,6,12,12,0,6",      # Passive Stun stuns, but has no cooldown
                    "14,500,1,6,12,12,0,6",      # a heroic-difficulty row: ignored
                    "15,992,0,98,0,0,0,6"],      # Slam knocks the target back
    "SpellCategories": ["ID,SpellID,DifficultyID,Mechanic,ChargeCategory",
                        "1,970,0,12,0", "2,800,0,0,5"],
    "SpellMechanic": ["ID,StateName_lang", "5,fleeing", "7,rooted", "12,stunned"],
    "SpellCooldowns": ["ID,SpellID,DifficultyID,RecoveryTime,CategoryRecoveryTime",
                       "1,6552,0,0,15000", "2,200,0,30000,0", "3,300,0,90000,0", "4,400,0,0,0",
                       "5,900,0,20000,0", "6,950,0,24000,0", "7,980,0,15000,0", "8,990,0,40000,0",
                       "9,970,0,90000,0", "10,992,0,30000,0"],
    "SpellCategory": ["ID,ChargeRecoveryTime", "5,45000"],
    "SpellClassOptions": ["ID,SpellID,SpellClassSet", "1,200,4", "2,201,4"],
    "SkillLine": ["DisplayName_lang,ID,CategoryID,ParentSkillLineID"]
                 + ["%s,%d,7,0" % (name, 10 + i) for i, name in enumerate(seeds.CLASS_SKILL_LINE_NAMES)]
                 + ['"Pet - Felhunter",50,7,0', '"Racial - Tauren",60,9,0'],
    "SkillLineAbility": ["ID,SkillLine,Spell,ClassMask",
                         "1,10,6552,0", "2,10,100,0", "3,10,200,0", "4,10,400,0", "5,10,900,0",
                         "6,50,950,0", "7,60,970,16383", "8,10,992,0"],
    "SpecializationSpells": ["ID,SpecID,SpellID", "1,73,800", "2,71,960"],
    "PvpTalent": ["ID,SpecID,SpellID", "1,71,600"],
    "ChrSpecialization": ["ID,ClassID,Name_lang", "71,1,Arms", "73,1,Protection"],
    "TraitDefinition": ["ID,SpellID,VisibleSpellID", "1,300,0", "2,990,0", "3,980,0", "4,991,0"],
    "TraitNodeEntry": ["ID,TraitDefinitionID,TraitSubTreeID",
                       "11,1,0", "12,2,0", "13,3,0", "14,4,0", "15,0,7"],
    "TraitNodeXTraitNodeEntry": ["ID,TraitNodeID,TraitNodeEntryID",
                                 "1,101,11", "2,102,12", "3,103,13", "4,104,14", "5,105,15"],
    "TraitNode": ["ID,TraitTreeID,TraitSubTreeID",
                  "101,1,0",   # Shout: class node, every spec
                  "102,1,0",   # Spec Stun: gated to Protection through its node group
                  "103,1,7",   # Hero Kick: hero subtree 7
                  "104,1,0",   # Passive Stun: class node
                  "105,1,0"],  # the hero selection node offering subtree 7, gated to Arms
    "TraitTreeLoadout": ["ID,TraitTreeID,ChrSpecializationID", "1,1,71", "2,1,73"],
    "TraitCond": ["ID,CondType,SpecSetID", "1,1,2", "2,1,1", "3,2,1"],
    "TraitNodeXTraitCond": ["ID,TraitCondID,TraitNodeID", "1,2,105", "2,3,101"],
    "TraitNodeGroupXTraitNode": ["ID,TraitNodeGroupID,TraitNodeID", "1,9,102"],
    "TraitNodeGroupXTraitCond": ["ID,TraitCondID,TraitNodeGroupID", "1,1,9"],
    "SpecSetMember": ["ID,ChrSpecializationID,SpecSet", "1,71,1", "2,73,2"],
}

SEEDS = """-- defaults/Spells.lua (fixture)
local _, NS = ...
local SPEC = NS.Const.SPEC

NS.DefaultSpells = {

    WARRIOR = {
        [SPEC.ARMS] = {
            { spellID = 6552,   category = "interrupt", enabled = true }, -- Pummel
            { spellID = 200,    category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 300,    category = "stun",      enabled = true }, -- Shout (category is wrong)
            { spellID = 100,    category = "stun",      enabled = true }, -- Charge
            { spellID = 600,    category = "stun",      enabled = true }, -- Old Bash
            { spellID = 400,    category = "root",      enabled = true }, -- Hamstrung
            { spellID = 12345,  category = "other",     enabled = true }, -- Gone Spell
        },
        [SPEC.PROTECTION_WARRIOR] = {
            { spellID = 200,    category = "stun",      enabled = true }, -- Storm Bolt
            { spellID = 900,    category = "other",     enabled = true }, -- Leap
        },
    },
}

NS.RaceCastStoppers = {
    Tauren = 970, -- War Stomp
    Orc    = 990, -- Spec Stun
}
"""


def write_fixture(root: Path, gz: bool = False) -> dict:
    out = {}
    for table, _why in seeds.TABLES:
        text = "\n".join(FIXTURE[table]) + "\n"
        path = root / ("%s.csv%s" % (table, ".gz" if gz else ""))
        if gz:
            with gzip.open(path, "wt", encoding="utf-8", newline="") as handle:
                handle.write(text)
        else:
            path.write_text(text, encoding="utf-8")
        out[table] = path
    return out


class Fixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp())
        cls.db = seeds.Build(write_fixture(cls.tmp))
        cls.seeds = seeds.parse_seeds(SEEDS, SPEC_IDS)
        cls.doc = seeds.derive(cls.db, cls.seeds, "1.0.0.1", "2026-11-15")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def flag_keys(self):
        return {f["key"] for f in self.doc["flags"]}

    def cand(self, key):
        return next((c for c in self.doc["candidates"] if c["key"] == key), None)


class TestParse(Fixture):
    def test_lists_and_races(self):
        specs = {(b["class"], b["spec"]): b for b in self.seeds["specs"]}
        self.assertEqual(len(specs[("WARRIOR", 71)]["entries"]), 7)
        self.assertEqual([e["id"] for e in specs[("WARRIOR", 73)]["entries"]], [200, 900])
        self.assertEqual([(r["race"], r["id"]) for r in self.seeds["races"]], [("Tauren", 970), ("Orc", 990)])

    def test_category_outside_the_closed_set_is_refused(self):
        bad = SEEDS.replace('category = "root"', 'category = "slow"')
        with self.assertRaises(SystemExit):
            seeds.parse_seeds(bad, SPEC_IDS)

    def test_unknown_spec_alias_is_refused(self):
        with self.assertRaises(SystemExit):
            seeds.parse_seeds(SEEDS, {"ARMS": 71})

    def test_spec_ids_come_from_constants(self):
        ids = seeds.read_spec_ids()
        self.assertEqual(ids["ELEMENTAL"], 262)
        self.assertEqual(ids["DEVOURER"], 1480)


class TestReach(Fixture):
    def test_sources(self):
        arms, prot = self.db.reach(71), self.db.reach(73)
        self.assertIn("class skill line", arms[6552])
        self.assertIn(800, prot)                       # a spec spell of Protection only
        self.assertNotIn(800, arms)
        self.assertIn(300, arms)                       # a class talent node
        self.assertIn(300, prot)                       # CondType 2 (granted) does not gate

    def test_node_group_spec_gate(self):
        self.assertIn(990, self.db.reach(73))
        self.assertNotIn(990, self.db.reach(71))

    def test_hero_subtree_gate(self):
        self.assertIn(980, self.db.reach(71))
        self.assertNotIn(980, self.db.reach(73))

    def test_pet_spells_need_the_summon(self):
        # the Felhunter line is WARLOCK's: never a warrior's, whatever the summon
        self.assertNotIn(950, self.db.reach(71))

    def test_flag_reach_adds_pvp_and_racials(self):
        self.assertNotIn(600, self.db.reach(71))
        self.assertIn("PvP talent", self.db.flag_reach(71)[600])
        self.assertIn(970, self.db.flag_reach(73))


class TestEvidence(Fixture):
    def test_interrupt_is_effect_68(self):
        self.assertIn("interrupt", self.db.evidence(6552))
        self.assertNotIn("interrupt", self.db.evidence(100))

    def test_trigger_closure(self):
        self.assertEqual(sorted(self.db.evidence(300)), ["fear"])

    def test_family_bridge_confirms_but_never_proposes(self):
        self.assertEqual(self.db.own_evidence(200), {})
        self.assertIn("stun", self.db.evidence(200))

    def test_caster_movement_is_not_a_knockback(self):
        self.assertEqual(self.db.evidence(900), {})
        self.assertIn("knockback", self.db.evidence(992))

    def test_heroic_rows_are_ignored(self):
        self.assertEqual(self.db.evidence(500), {})

    def test_charge_cooldown(self):
        self.assertEqual(self.db.cooldown[800], 45000)


class TestFlags(Fixture):
    def test_each_kind(self):
        keys = self.flag_keys()
        self.assertIn("shipped:unnamed:WARRIOR:71:12345", keys)
        self.assertIn("shipped:renamed:WARRIOR:71:400", keys)       # Hamstrung vs Hamstring
        self.assertIn("shipped:category:WARRIOR:71:300", keys)      # a fear shipped as stun
        self.assertIn("shipped:no-evidence:WARRIOR:71:100", keys)   # Charge
        self.assertNotIn("shipped:unreachable:WARRIOR:71:400", keys)  # on the class line
        self.assertIn("shipped:primary:WARRIOR:73:200", keys)       # Prot reaches 800

    def test_no_false_flags(self):
        keys = self.flag_keys()
        self.assertNotIn("shipped:renamed:WARRIOR:71:300", keys)    # the aside is ignored
        self.assertNotIn("shipped:unreachable:WARRIOR:71:600", keys)  # a PvP talent
        self.assertNotIn("shipped:no-evidence:WARRIOR:73:900", keys)  # "other" is never checked
        self.assertNotIn("shipped:category:WARRIOR:71:200", keys)   # the bridge confirms it
        self.assertFalse(any(k.startswith("shipped:primary:WARRIOR:71") for k in keys))

    def test_racials(self):
        keys = self.flag_keys()
        self.assertNotIn("shipped:unreachable:RACE:Tauren:970", keys)
        self.assertIn("shipped:unreachable:RACE:Orc:990", keys)


class TestCandidates(Fixture):
    def test_interrupt_candidate(self):
        c = self.cand("WARRIOR:73:800")
        self.assertEqual((c["group"], c["category"]), ("interrupt", "interrupt"))
        self.assertIn("WARRIOR:71:980", {x["key"] for x in self.doc["candidates"]})

    def test_cc_candidate(self):
        self.assertEqual(self.cand("WARRIOR:73:990")["category"], "stun")
        self.assertEqual(self.cand("WARRIOR:71:992")["category"], "knockback")

    def test_never_proposed(self):
        keys = {c["key"] for c in self.doc["candidates"]}
        self.assertNotIn("WARRIOR:71:991", keys)    # no cooldown
        self.assertNotIn("WARRIOR:73:400", keys)    # a root
        self.assertNotIn("WARRIOR:71:6552", keys)   # already shipped in that list
        self.assertNotIn("WARRIOR:73:200", keys)    # Storm Bolt: shipped there
        self.assertNotIn("WARRIOR:71:600", keys)    # a PvP talent is never a source
        self.assertNotIn("WARRIOR:73:6552", {c["key"] for c in self.doc["candidates"]
                                              if c["group"] == "cc"})

    def test_hand_candidates(self):
        missing = []
        block = next(b for b in self.seeds["specs"] if b["spec"] == 73)
        hand = (("WARRIOR", "PROTECTION_WARRIOR", 100, "other", "why"),
                ("WARRIOR", "PROTECTION_WARRIOR", 980, "interrupt", "not reached"))
        out = seeds.hand_candidates(self.db, block, self.db.reach(73), missing, hand)
        self.assertEqual([c["id"] for c in out], [100])
        self.assertEqual([m["id"] for m in missing], [980])


class TestRulings(unittest.TestCase):
    def test_validation(self):
        r = {}
        seeds.set_ruling(r, "WARRIOR:73:800", "accept", "why")
        seeds.set_ruling(r, "shipped:unnamed:WARRIOR:71:12345", "remove", "gone")
        for key, ruling in (("WARRIOR:73:800", "keep"), ("shipped:unnamed:WARRIOR:71:1", "accept"),
                            ("shipped:primary:WARRIOR:73:200", "remove"),
                            ("shipped:bogus:WARRIOR:73:200", "keep"), ("warrior:73:1", "accept")):
            with self.assertRaises(SystemExit):
                seeds.set_ruling(r, key, ruling, "why")
        with self.assertRaises(SystemExit):
            seeds.set_ruling(r, "WARRIOR:73:800", "accept", "  ")

    def test_status_line(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            self.assertTrue(seeds.status_line("2.0", []).startswith("NEW 2.0"))
            b = tmp / "2026-11-15-retail"
            b.mkdir()
            (b / "candidates.json").write_text(json.dumps({"build": "1.0"}))
            self.assertEqual(seeds.status_line("1.0", seeds.bundles(tmp)), "CURRENT 1.0 (2026-11-15-retail)")
            self.assertTrue(seeds.status_line("2.0", seeds.bundles(tmp)).startswith("NEW 2.0 (last ruled 1.0"))
        finally:
            shutil.rmtree(tmp)


class TestApply(Fixture):
    def rulings(self, overrides=None):
        r = {}
        for c in self.doc["candidates"]:
            r[c["key"]] = {"ruling": "reject", "reason": "x"}
        for f in self.doc["flags"]:
            r[f["key"]] = {"ruling": "keep", "reason": "x"}
        for key, ruling in (overrides or {}).items():
            r[key] = {"ruling": ruling, "reason": "x"}
        return r

    def test_refuses_while_unruled(self):
        # The mutation-checked guard: with plan_apply's unruled check removed this goes red.
        rulings = self.rulings()
        del rulings[self.doc["candidates"][0]["key"]]
        with self.assertRaises(SystemExit) as ctx:
            seeds.apply_text(SEEDS, self.doc, rulings, "2026-11-15", SPEC_IDS)
        self.assertIn("unruled", str(ctx.exception))

    def test_nothing_accepted_changes_nothing(self):
        text = SEEDS.replace("\n", "\r\n")
        new, changes = seeds.apply_text(text, self.doc, self.rulings(), "2026-11-15", SPEC_IDS)
        self.assertEqual((new, changes), (text, []))

    def test_writes_keep_layout_and_crlf_and_are_idempotent(self):
        text = SEEDS.replace("\n", "\r\n")
        rulings = self.rulings({"WARRIOR:73:800": "accept", "WARRIOR:73:990": "accept",
                                "shipped:unnamed:WARRIOR:71:12345": "remove"})
        new, changes = seeds.apply_text(text, self.doc, rulings, "2026-11-15", SPEC_IDS)
        self.assertEqual(len(changes), 3)
        self.assertNotIn("\n", new.replace("\r\n", ""))
        lines = new.split("\r\n")
        prot = lines.index("        [SPEC.PROTECTION_WARRIOR] = {")
        self.assertIn("spellID = 800,", lines[prot + 1])          # an interrupt leads the list
        self.assertIn("spellID = 990,", lines[prot + 4])          # CC goes last
        template = lines[prot + 2]
        for line in (lines[prot + 1], lines[prot + 4]):
            self.assertEqual(line.index("category ="), template.index("category ="))
            self.assertEqual(line.index("enabled ="), template.index("enabled ="))
        self.assertNotIn("12345", new)
        again, more = seeds.apply_text(new, self.doc, rulings, "2026-11-15", SPEC_IDS)
        self.assertEqual((again, more), (new, []))

    def test_a_corrected_id_takes_the_removed_slot(self):
        doc = json.loads(json.dumps(self.doc))
        doc["flags"].append({"key": "shipped:unreachable:WARRIOR:71:100", "kind": "unreachable",
                             "class": "WARRIOR", "spec": 71, "alias": "ARMS", "id": 100,
                             "name": "Charge"})
        doc["candidates"].append({"key": "WARRIOR:71:2100", "class": "WARRIOR", "spec": 71,
                                  "alias": "ARMS", "id": 2100, "name": "Charge",
                                  "group": "cc", "category": "stun"})
        rulings = self.rulings({"shipped:unreachable:WARRIOR:71:100": "remove", "WARRIOR:71:2100": "accept"})
        new, _ = seeds.apply_text(SEEDS, doc, rulings, "2026-11-15", SPEC_IDS)
        lines = new.split("\n")
        arms = lines.index("        [SPEC.ARMS] = {")
        self.assertIn("spellID = 2100,", lines[arms + 4])         # where 100 was

    def test_race_removal(self):
        rulings = self.rulings({"shipped:unreachable:RACE:Orc:990": "remove"})
        new, changes = seeds.apply_text(SEEDS, self.doc, rulings, "2026-11-15", SPEC_IDS)
        self.assertEqual(changes, ["RACE Orc: -990"])
        self.assertNotIn("Orc", new)


class TestBundle(unittest.TestCase):
    def test_freeze_is_deterministic_and_replays(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            src = tmp / "SpellName.csv"
            src.write_text("ID,Name_lang\n1,A\n", encoding="utf-8")
            seeds.freeze(src, tmp / "a.csv.gz")
            seeds.freeze(src, tmp / "b.csv.gz")
            self.assertEqual((tmp / "a.csv.gz").read_bytes(), (tmp / "b.csv.gz").read_bytes())
            self.assertEqual(list(seeds.iter_csv(tmp / "a.csv.gz")), [{"ID": "1", "Name_lang": "A"}])
        finally:
            shutil.rmtree(tmp)

    def test_replay_refuses_a_missing_member(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            with self.assertRaises(SystemExit):
                seeds.bundle_tables(tmp, "1.0", True, tmp / "cache")
        finally:
            shutil.rmtree(tmp)

    def test_derive_from_gzipped_members(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            db = seeds.Build(write_fixture(tmp, gz=True))
            self.assertIn("interrupt", db.evidence(6552))
        finally:
            shutil.rmtree(tmp)

    def test_text_is_written_crlf(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            seeds.write_text(tmp / "x.md", "a\nb\r\nc\n")
            self.assertEqual((tmp / "x.md").read_bytes(), b"a\r\nb\r\nc\r\n")
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
