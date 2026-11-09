"""Offline structural checks of the pinned third-party installer and physics selector."""
import importlib.util
from pathlib import Path
import tempfile
import io
import zipfile
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1]
SP=ROOT/'tools'/'setup_physics_vendors.py'
spec=importlib.util.spec_from_file_location('physics_vendor',SP)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class PhysicsSetupTests(unittest.TestCase):
    def test_both_sources_pinned(self):
        self.assertEqual(set(mod.VENDORS),{'gevp','kv'})
        for key,v in mod.VENDORS.items():
            self.assertEqual(len(v['commit']),40)
            self.assertTrue(v['repository'])
    def test_extract_filters_wrong_addon(self):
        f=io.BytesIO()
        with zipfile.ZipFile(f,'w') as z:
            z.writestr('repo123/addons/gevp/scripts/test.gd','extends Node3D')
            z.writestr('repo123/addons/other/no.txt','NO')
        with tempfile.TemporaryDirectory() as d:
            with zipfile.ZipFile(io.BytesIO(f.getvalue())) as z:
                count=mod.safe_extract_selection(z,'gevp',Path(d))
            self.assertEqual(count,1)
            self.assertEqual((Path(d)/'scripts/test.gd').read_text(),'extends Node3D')
            self.assertFalse((Path(d)/'no.txt').exists())
    def test_selector_only_changes_physics_settings(self):
        selector_text=(ROOT/'tools'/'select_physics.py').read_text()
        self.assertIn('GodotPhysics3D',selector_text)
        self.assertIn('Jolt Physics',selector_text)
        self.assertIn('physics_ticks_per_second',selector_text)

if __name__=='__main__': unittest.main()
