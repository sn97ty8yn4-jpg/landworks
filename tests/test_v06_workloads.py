import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parent.parent

def module(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

class V06WorkTests(unittest.TestCase):
    def setUp(self):
        self.engineering=module('eng',ROOT/'tools/engineering_precheck.py')

    def test_loads_increase_required_boom_torque(self):
        e=self.engineering
        t=[e.boom_torque(m) for m in (250,500,1000)]
        self.assertTrue(t[0]<t[1]<75000<t[2])

    def test_hill_and_payload_increase_resistance(self):
        e=self.engineering
        a=e.towing_forces(400,0)['resistance_N']
        b=e.towing_forces(400,6)['resistance_N']
        c=e.towing_forces(800,6)['resistance_N']
        self.assertTrue(a<b<c)

    def test_physical_tow_hitch_and_dynamic_trailer(self):
        tractor=(ROOT/'landworks/scripts/tractor_work_lab.gd').read_text()
        trailer=(ROOT/'landworks/scripts/work_trailer.gd').read_text()
        self.assertIn('PinJoint3D.new()',tractor)
        self.assertIn('intersect_ray(query)',trailer)
        self.assertIn('apply_force(',trailer)
        self.assertIn('work_speed_limit_kmh', (ROOT/'landworks/scripts/tractor.gd').read_text())
        for scenario in ('flat_empty','flat_400','hill_400','hill_800'):
            self.assertIn(scenario,tractor)

    def test_excavator_has_unfrozen_track_chassis_and_powered_slew(self):
        s=(ROOT/'landworks/scripts/excavator_work_lab.gd').read_text()
        for required in ('HingeJoint3D', 'PinJoint3D', 'test_mass.mass',
                         'MAX_IMPULSE', 'undercarriage.apply_force', 'peak_tilt_deg',
                         'ground_contact_count', '_motor_impulse'):
            # Inherited link joints and mass are in the original file; make sure
            # the work test itself actually uses a physics payload and motors.
            if required=='test_mass.mass': self.assertIn('test_mass.mass = initial_payload_mass',s)
            elif required=='PinJoint3D': self.assertIn('PinJoint3D',s)
            elif required=='HingeJoint3D':self.assertIn('HingeJoint3D',s)
            elif required=='MAX_IMPULSE':self.assertIn('_motor_impulse(',s)
            else: self.assertIn(required,s)
        self.assertNotIn('undercarriage.freeze = true',s)
        self.assertIn('upper.mass = 4710.0',s)
        self.assertIn('undercarriage.mass = 2200.0',s)

    def test_missing_engine_never_claims_results(self):
        w=module('runner',ROOT/'tools/run_work_tests.py')
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse((Path(d)/'tractor_flat_400_summary.csv').exists())
            with self.assertRaises(RuntimeError):
                w.validate_sample(Path(d)/'no_file.csv','flat_400')
        self.assertEqual(len(w.CASE_SCENES),13)

    def test_mathematical_surrogates_are_separate_outputs(self):
        s=(ROOT/'tools/surrogate_dynamics.py').read_text()
        self.assertIn('NOT Godot tests',s)
        self.assertIn('ground_stop_angle',s)
        self.assertIn('surrogate_summary.csv',s)

if __name__=='__main__': unittest.main()
