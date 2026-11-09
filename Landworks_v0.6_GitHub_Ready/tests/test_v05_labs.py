"""Static integration gates. These DO NOT assert the physics actually works."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class V05Labs(unittest.TestCase):
    def test_bench_has_real_vendor_engines(self):
        s=(ROOT/'landworks/scripts/vehicle_bench_factory.gd').read_text()
        self.assertIn('addons/gevp/scripts/vehicle.gd',s)
        self.assertIn('addons/gevp/scripts/wheel.gd',s)
        self.assertIn('addons/kv-vehicle/scene/instantiable/kv-wheel.tscn',s)
        self.assertIn('kv-engine.tscn',s)
        self.assertIn('kv-drivetrain.tscn',s)
        self.assertIn('kv-breaks.tscn',s)
        self.assertIn('const MASS := 573.0',s)
        self.assertIn('const FRONT_RADIUS := 0.26035',s)
        self.assertIn('const REAR_RADIUS := 0.36830',s)
    def test_bench_logs_actual_body_states(self):
        s=(ROOT/'landworks/scripts/physics_comparison_lab.gd').read_text()
        for token in ['body.linear_velocity','body.global_position','body.rotation_degrees',
                      'landworks_comparison_summary.csv','landworks_comparison_samples.csv',
                      'NOT INSTALLED','GEVP','KV','BASELINE']:
            self.assertIn(token,s)
        self.assertTrue((ROOT/'landworks/scenes/physics_comparison_lab.tscn').exists())
    def test_excavator_has_force_joints_and_mass(self):
        s=(ROOT/'landworks/scripts/physical_excavator_lab.gd').read_text()
        for token in ['HingeJoint3D.new()', 'PinJoint3D.new()',
                      'PARAM_MOTOR_MAX_IMPULSE','PARAM_MOTOR_TARGET_VELOCITY',
                      'test_mass = RigidBody3D.new()', 'test_mass.mass = 250.0',
                      'test_mass.mass = 500.0', 'undercarriage.freeze = true',
                      '_joint_angle(']:
            self.assertIn(token,s)
        self.assertTrue((ROOT/'landworks/scenes/physical_excavator_lab.tscn').exists())
        self.assertNotIn('boom.rotation.x =',s)
    def test_jolt_120hz_set_as_initial_default(self):
        s=(ROOT/'project.godot').read_text()
        self.assertIn('3d/physics_engine="Jolt Physics"',s)
        self.assertIn('common/physics_ticks_per_second=120',s)

if __name__=='__main__':
    unittest.main()
