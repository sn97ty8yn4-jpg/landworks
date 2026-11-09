"""Test GLB hierarchy inspection and *non-automatic* rig worksheet generation."""
import json
import pathlib
import struct
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.rigging.scan_glb import inspect, read_glb, worksheet, node_matrix, world_point, ROLES


def fake_glb(path):
    doc = {
        'asset': {'version': '2.0'},
        'scene': 0,
        'scenes': [{'nodes': [0]}],
        'nodes': [
            {'name': 'root', 'children': [1], 'translation': [1, 2, 3]},
            {'name': 'front_wheel', 'mesh': 0, 'translation': [0, 1, 0]}
        ],
        'meshes': [{'name': 'turf_tyre', 'primitives': [{'attributes': {'POSITION': 0}, 'material': 0}]}],
        'materials': [{'name': 'Rubber'}],
        'accessors': [{'count': 8, 'min': [-1,-1,-1], 'max': [1,1,1]}],
    }
    payload = json.dumps(doc).encode('utf-8')
    payload += b' ' * (-len(payload) % 4)
    length = 12 + 8 + len(payload)
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, length) + struct.pack('<I4s', len(payload), b'JSON') + payload)
    return doc


class ScanTests(unittest.TestCase):
    def test_hierarchy_bounds_and_hash(self):
        with tempfile.TemporaryDirectory() as d:
            fn = pathlib.Path(d) / 'donor.glb'
            fake_glb(fn)
            info = inspect(fn, 'b7100')
            self.assertEqual(info['gltf_nodes'], 2)
            self.assertEqual(info['mesh_instances'], 1)
            mesh = info['mesh_nodes'][0]
            self.assertEqual(mesh['node_name'], 'front_wheel')
            self.assertEqual(mesh['bounds_gltf_y_up_m']['min'], [0.0, 2.0, 2.0])
            self.assertEqual(mesh['bounds_gltf_y_up_m']['max'], [2.0, 4.0, 4.0])
            self.assertIn('wheel_front', mesh['possible_roles_UNVERIFIED'])
            self.assertEqual(mesh['materials'], ['Rubber'])
            self.assertEqual(len(info['sha256']), 64)

    def test_no_unverified_auto_assignments(self):
        with tempfile.TemporaryDirectory() as d:
            fn = pathlib.Path(d) / 'donor.glb'
            fake_glb(fn)
            info = inspect(fn, 'kx080')
            recipe = worksheet(info, 'kx080')
            self.assertEqual(set(recipe['parts']), set(ROLES['kx080']))
            for part in recipe['parts'].values():
                self.assertEqual(part['objects'], [])
                self.assertEqual(part['part_scale_xyz'], [1,1,1])
                self.assertEqual(part['rest_rotation_xyz_deg_blender'], [0,0,0])

    def test_quaternion_translation(self):
        matrix = node_matrix({'translation': [5, 2, -1], 'scale': [2, 1, 1]})
        self.assertEqual(world_point(matrix, [1,1,1]), [7.0,3.0,0.0])

    def test_invalid_header_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            fn = pathlib.Path(d) / 'bad.glb'
            fn.write_bytes(b'not a glTF')
            with self.assertRaises(ValueError):
                read_glb(fn)


if __name__ == '__main__':
    unittest.main()
