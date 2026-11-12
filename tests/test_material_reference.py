"""Reference conservation and force-gate tests; not Godot runtime acceptance."""
import math
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from material_reference import PROFILES, SoilBatch, cut_if_feasible, ledger


class MaterialReferenceTests(unittest.TestCase):
    def assertLedgerEqual(self, before, after):
        self.assertAlmostEqual(before[0], after[0], places=9)
        self.assertAlmostEqual(before[1], after[1], places=9)

    def test_profiles_are_valid_grading_and_saturation(self):
        for name, p in PROFILES.items():
            with self.subTest(name=name):
                self.assertAlmostEqual(sum(p["grading"].values()), 1.0, places=9)
                self.assertGreaterEqual(p["void_ratio_loose"], p["void_ratio_bank"])
                self.assertLess(p["void_ratio_min"], p["void_ratio_bank"])
                b = SoilBatch.bank(name, 1.0)
                self.assertLessEqual(b.saturation, 1.0)
                self.assertEqual(b.free_water_kg, 0)

    def test_bank_volume_is_exact(self):
        for name in PROFILES:
            self.assertAlmostEqual(SoilBatch.bank(name, 0.15).bulk_volume_m3, 0.15, places=11)

    def test_soil_solids_and_water_balance_after_loosen(self):
        s = SoilBatch.bank("moist_silty_clay", 0.1)
        before = ledger({"s": s})
        s.loosen()
        self.assertGreater(s.bulk_volume_m3, 0.1)
        self.assertLedgerEqual(before, ledger({"s": s}))

    def test_compaction_reduces_volume_not_mass(self):
        s = SoilBatch.bank("moist_topsoil", 0.2)
        s.loosen()
        before = ledger({"s": s})
        v = s.bulk_volume_m3
        d = s.compact(20000)
        self.assertGreater(d, 0)
        self.assertLess(s.bulk_volume_m3, v)
        self.assertLedgerEqual(before, ledger({"s": s}))

    def test_no_compaction_from_zero_energy(self):
        s = SoilBatch.bank("dry_sand", 0.15)
        v = s.bulk_volume_m3
        self.assertEqual(s.compact(0), 0)
        self.assertEqual(s.bulk_volume_m3, v)

    def test_excess_water_becomes_free_water(self):
        s = SoilBatch.bank("moist_silty_clay", 0.1)
        startwater = s.pore_water_kg + s.free_water_kg
        s.add_water(100)
        self.assertAlmostEqual(s.pore_water_kg + s.free_water_kg, startwater + 100)
        self.assertAlmostEqual(s.saturation, 1)
        self.assertGreater(s.free_water_kg, 0)

    def test_split_then_merge_preserves_components(self):
        s = SoilBatch.bank("moist_silty_clay", 0.2)
        before = ledger({"s": s})
        a = s.split_bulk_volume(0.07)
        self.assertLedgerEqual(before, ledger({"bank": s, "cut": a}))
        s.merge(a)
        self.assertLedgerEqual(before, ledger({"s": s}))
        self.assertAlmostEqual(s.bulk_volume_m3, 0.2, places=10)

    def test_mixing_retains_distinct_materials(self):
        clay = SoilBatch.bank("moist_silty_clay", 0.1)
        gravel = SoilBatch.bank("loose_gravel", 0.04)
        before = ledger({"a": clay, "b": gravel})
        clay.merge(gravel)
        self.assertIn("moist_silty_clay", clay.dry_kg)
        self.assertIn("loose_gravel", clay.dry_kg)
        self.assertLedgerEqual(before, ledger({"a": clay}))

    def test_disturbance_softens_cohesive_cut(self):
        s = SoilBatch.bank("moist_silty_clay", 0.2)
        before = s.face_resistance_n(0.7, 0.18)
        s.remould(3.0)
        self.assertLess(s.face_resistance_n(0.7, 0.18), before)
        self.assertGreater(s.damage, .9)

    def test_resistance_increases_with_depth(self):
        s = SoilBatch.bank("moist_silty_clay", 0.2)
        self.assertEqual(s.face_resistance_n(0.7, 0), 0)
        self.assertGreater(s.face_resistance_n(0.7, 0.3), s.face_resistance_n(0.7, 0.15))

    def test_underpowered_tool_removes_nothing(self):
        s = SoilBatch.bank("moist_silty_clay", 0.3)
        before = ledger({"bank": s})
        needed = s.face_resistance_n(0.7, 0.2)
        r = cut_if_feasible(s, 0.7, 0.2, 0.3, needed * 0.5, 1e6, 0.25)
        self.assertEqual(r.bank_volume_m3, 0)
        self.assertLedgerEqual(before, ledger({"bank": s}))

    def test_stalled_tool_removes_nothing(self):
        s = SoilBatch.bank("moist_silty_clay", 0.3)
        r = cut_if_feasible(s, 0.7, 0.2, 0.0, 1e6, 1e6, 0.25)
        self.assertEqual(r.bank_volume_m3, 0)

    def test_feasible_cut_conserves_masses_and_swells(self):
        s = SoilBatch.bank("moist_silty_clay", 0.3)
        before = ledger({"bank": s})
        r = cut_if_feasible(s, 0.7, 0.2, 0.3, 1e6, 1e6, 0.25)
        self.assertGreater(r.bank_volume_m3, 0)
        self.assertGreater(r.loose_volume_m3, r.bank_volume_m3)
        self.assertLedgerEqual(before, ledger({"bank": s, "bucket": r.captured}))

    def test_work_limited_cut_is_partial(self):
        bank = SoilBatch.bank("moist_silty_clay", 0.3)
        need = bank.face_resistance_n(0.7, 0.2) * 0.3
        r = cut_if_feasible(bank, 0.7, 0.2, 0.3, 1e6, need * 0.25, 0.25)
        self.assertAlmostEqual(r.bank_volume_m3, 0.7 * 0.2 * 0.3 * 0.25, places=9)

    def test_bucket_room_limits_bank_removal(self):
        bank = SoilBatch.bank("moist_silty_clay", 1.0)
        r = cut_if_feasible(bank, 0.7, 0.2, 0.4, 1e6, 1e6, 0.015)
        self.assertLessEqual(r.loose_volume_m3, 0.015 + 1e-12)
        self.assertGreater(bank.bulk_volume_m3, 0.9)

    def test_repeated_compaction_has_diminishing_settlement(self):
        s = SoilBatch.bank("moist_topsoil", 0.2)
        s.loosen()
        first = s.compact(1000)
        second = s.compact(1000)
        self.assertGreater(first, second)
        self.assertGreater(second, 0.0)

    def test_saturated_compaction_expelled_water_is_conserved(self):
        s = SoilBatch.bank("moist_silty_clay", 0.15)
        needed = s.pore_volume_m3 * 1000.0 - s.pore_water_kg
        s.add_water(needed)
        before = ledger({"s": s})
        old_free = s.free_water_kg
        s.compact(50000)
        self.assertAlmostEqual(s.saturation, 1.0)
        self.assertGreater(s.free_water_kg, old_free)
        self.assertLedgerEqual(before, ledger({"s": s}))

    def test_remould_only_changes_structure_not_mass(self):
        s = SoilBatch.bank("wet_sticky_clay", 0.3)
        before = ledger({"s": s})
        volume = s.bulk_volume_m3
        s.remould(0.5)
        self.assertEqual(s.bulk_volume_m3, volume)
        self.assertLedgerEqual(before, ledger({"s": s}))

    def test_no_cut_if_zero_work(self):
        s = SoilBatch.bank("dry_sand", 0.3)
        before = ledger({"bank": s})
        r = cut_if_feasible(s, 0.75, 0.2, 0.3, 1e6, 0, 0.25)
        self.assertEqual(r.bank_volume_m3, 0)
        self.assertLedgerEqual(before, ledger({"bank": s}))

    def test_negative_inputs_rejected(self):
        b = SoilBatch.bank("dry_sand", 0.5)
        with self.assertRaises(ValueError):
            b.add_water(-1)
        with self.assertRaises(ValueError):
            b.compact(-1)
        with self.assertRaises(ValueError):
            b.split_bulk_volume(0.8)

    def test_wet_clay_more_adhesive_than_dry_sand(self):
        self.assertGreater(PROFILES["wet_sticky_clay"]["steel_adhesion_pa"],
                           PROFILES["dry_sand"]["steel_adhesion_pa"])

    def test_all_outputs_finite(self):
        for name in PROFILES:
            b=SoilBatch.bank(name, 0.1)
            b.loosen();b.remould(.03);b.compact(200)
            for value in [b.bulk_volume_m3,b.pore_water_kg,b.free_water_kg,b.saturation,b.face_resistance_n(.75,.2)]:
                self.assertTrue(math.isfinite(value))


if __name__ == "__main__":
    unittest.main()
