#!/usr/bin/env python3
"""Inspect downloaded GLB hierarchies and make *unassigned* rigging worksheets.

Pure stdlib, no Blender/Godot. Never guesses that wheels or hydraulic limbs are
separately rigged. All boxes are computed from the glTF POSITION accessor extrema
and declared node transforms, so results are useful for planning but are not an
exact collision or manufacturing measurement.
"""
from __future__ import annotations
import argparse
import hashlib
import itertools
import json
from math import sqrt
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = ROOT / 'landworks/assets/source'
REPORT_DIR = ROOT / 'landworks/assets/reports'
RECIPES = ROOT / 'tools/rigging/recipes'
SOURCES = {
    'b7100': 'garden-tractor-with-trailer.glb',
    'kx080': 'compact-tracked-excavator.glb',
}
ROLES = {
    'b7100': ['body', 'wheel_front', 'wheel_rear'],
    'kx080': ['track', 'upper', 'boom', 'stick', 'bucket'],
}
ROLE_HINTS = {
    'body': ['tractor', 'chassis', 'hood', 'body', 'seat', 'fender', 'bonnet'],
    'wheel_front': ['front', 'wheel', 'tyre', 'tire', 'rim'],
    'wheel_rear': ['rear', 'wheel', 'tyre', 'tire', 'rim'],
    'track': ['track', 'belt', 'crawler', 'shoe'],
    'upper': ['upper', 'cab', 'counterweight', 'turret', 'slew'],
    'boom': ['boom', 'liftarm'],
    'stick': ['stick', 'dipper', 'arm'],
    'bucket': ['bucket', 'tooth', 'teeth'],
}


def read_glb(path: Path) -> dict:
    with path.open('rb') as f:
        header = f.read(12)
        if len(header) != 12:
            raise ValueError('Missing GLB header')
        magic, version, length = struct.unpack('<4sII', header)
        if magic != b'glTF' or version != 2 or length != path.stat().st_size:
            raise ValueError('Invalid or incomplete GLB v2')
        n, typ = struct.unpack('<I4s', f.read(8))
        if typ != b'JSON' or n <= 0 or n > length - 20:
            raise ValueError('Missing valid JSON first chunk')
        data = json.loads(f.read(n))
        if not isinstance(data, dict) or data.get('asset', {}).get('version') != '2.0':
            raise ValueError('Not a glTF 2.0 document')
        return data


def matmul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def identity():
    return [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]


def node_matrix(node):
    if 'matrix' in node:
        flat = node['matrix']
        if len(flat) != 16:
            raise ValueError('node matrix must have 16 entries')
        return [[float(flat[c*4+r]) for c in range(4)] for r in range(4)]
    x, y, z, w = [float(v) for v in node.get('rotation', [0,0,0,1])]
    l = sqrt(x*x + y*y + z*z + w*w)
    if l < 1e-10:
        raise ValueError('invalid zero-length quaternion')
    x, y, z, w = [v/l for v in (x,y,z,w)]
    sx, sy, sz = [float(v) for v in node.get('scale', [1,1,1])]
    tx, ty, tz = [float(v) for v in node.get('translation', [0,0,0])]
    return [
        [(1-2*(y*y+z*z))*sx, 2*(x*y-z*w)*sy, 2*(x*z+y*w)*sz, tx],
        [2*(x*y+z*w)*sx, (1-2*(x*x+z*z))*sy, 2*(y*z-x*w)*sz, ty],
        [2*(x*z-y*w)*sx, 2*(y*z+x*w)*sy, (1-2*(x*x+y*y))*sz, tz],
        [0,0,0,1],
    ]


def world_point(matrix, p):
    return [sum(matrix[i][j] * p[j] for j in range(3)) + matrix[i][3] for i in range(3)]


def node_mesh_bounds(data, mesh_idx, transform):
    accs = data.get('accessors', [])
    mins, maxs = [], []
    vertex_count = 0
    material_names = []
    for primitive in data['meshes'][mesh_idx].get('primitives', []):
        attr = primitive.get('attributes', {})
        if 'POSITION' not in attr:
            continue
        idx = attr['POSITION']
        if not 0 <= idx < len(accs):
            raise ValueError(f'POSITION accessor index out of bounds: {idx}')
        acc = accs[idx]
        vertex_count += int(acc.get('count', 0))
        if len(acc.get('min', [])) != 3 or len(acc.get('max', [])) != 3:
            continue
        lo, hi = acc['min'], acc['max']
        for corner in itertools.product(*[(lo[i], hi[i]) for i in range(3)]):
            p = world_point(transform, corner)
            mins.append(p)
        mi = primitive.get('material')
        if isinstance(mi, int) and 0 <= mi < len(data.get('materials', [])):
            material_names.append(data['materials'][mi].get('name', f'material_{mi}'))
    if not mins:
        return None, vertex_count, sorted(set(material_names))
    return {'min': [round(min(p[i] for p in mins), 5) for i in range(3)],
            'max': [round(max(p[i] for p in mins), 5) for i in range(3)]}, vertex_count, sorted(set(material_names))


def inspect(path: Path, machine: str) -> dict:
    data = read_glb(path)
    nodes = data.get('nodes', [])
    if not nodes:
        raise ValueError('GLB has no nodes')
    children = {int(k) for n in nodes for k in n.get('children', [])}
    roots = data.get('scenes', [{}])[data.get('scene', 0)].get('nodes', []) if data.get('scenes') else []
    if not roots:
        roots = [i for i in range(len(nodes)) if i not in children]
    entries = []
    seen = set()
    def walk(idx: int, parent: list, path_items: list, ancestors: set):
        if idx in ancestors:
            raise ValueError('GLB has cycle in node graph')
        if not 0 <= idx < len(nodes):
            raise ValueError(f'Invalid child node index {idx}')
        node = nodes[idx]
        name = node.get('name', f'node_{idx}')
        path_items = path_items + [f'{name}[{idx}]']
        matrix = matmul(parent, node_matrix(node))
        if 'mesh' in node:
            mi = node['mesh']
            if not 0 <= mi < len(data.get('meshes', [])):
                raise ValueError(f'Invalid mesh index {mi}')
            box, count, materials = node_mesh_bounds(data, mi, matrix)
            mesh_name = data['meshes'][mi].get('name', f'mesh_{mi}')
            combined_name = (name + ' ' + mesh_name).lower()
            hints = [r for r, terms in ROLE_HINTS.items() if any(t in combined_name for t in terms)]
            entries.append({'gltf_node_index': idx, 'node_name': name, 'node_path': '/'.join(path_items),
                            'mesh_index': mi, 'mesh_name': mesh_name, 'vertices_declared': count,
                            'bounds_gltf_y_up_m': box, 'materials': materials, 'possible_roles_UNVERIFIED': hints})
        seen.add(idx)
        for child in node.get('children', []):
            walk(child, matrix, path_items, ancestors | {idx})
    for r in roots:
        walk(r, identity(), [], set())
    raw = path.read_bytes()
    return {'machine': machine, 'source_file': path.name, 'sha256': hashlib.sha256(raw).hexdigest(),
            'bytes': len(raw), 'gltf_nodes': len(nodes), 'mesh_instances': len(entries),
            'mesh_nodes': entries,
            'warning': 'Role hints are guesses based ONLY on names; Blender names can differ. Verify in Blender before rigging.'}


def worksheet(scan: dict, machine: str):
    """No automatic claims about art segmentation: entries are intentionally blank."""
    return {
        'schema_version': 1,
        'machine': machine,
        'source_glb': scan['source_file'],
        'expected_source_sha256': scan['sha256'],
        'source_to_machine': {'uniform_scale': 1.0, 'rotation_xyz_deg_blender_z_up': [0,0,0]},
        'parts': {role: {
            'objects': [],
            'pivot_source_blender_m': [0,0,0],
            'part_scale_xyz': [1,1,1],
            'rest_rotation_xyz_deg_blender': [0,0,0],
            'comment': 'Choose exact Blender mesh object names; enter hinge/axle position in donor model coordinates.'
        } for role in ROLES[machine]},
        'notes': 'Empty assignments deliberately require human mesh and pivot review. Do not output guessed Kubota geometry.'
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--machine', required=True, choices=list(SOURCES))
    p.add_argument('--input', type=Path, help='Override input GLB')
    p.add_argument('--report-dir', type=Path, default=REPORT_DIR)
    p.add_argument('--recipe-dir', type=Path, default=RECIPES)
    p.add_argument('--overwrite-recipe', action='store_true')
    args = p.parse_args(argv)
    path = args.input or (ASSET_DIR / SOURCES[args.machine])
    if not path.is_file():
        p.error(f'GLB not available: {path}. Download via tools/windows/DOWNLOAD_MODELS_WINDOWS.bat first.')
    scan = inspect(path, args.machine)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    args.recipe_dir.mkdir(parents=True, exist_ok=True)
    report = args.report_dir / f'{args.machine}_source_scan.json'
    report.write_text(json.dumps(scan, indent=2), encoding='utf-8')
    recipe = args.recipe_dir / f'{args.machine}.json'
    if not recipe.exists() or args.overwrite_recipe:
        recipe.write_text(json.dumps(worksheet(scan, args.machine), indent=2), encoding='utf-8')
        print('Created editable rig recipe:', recipe)
    else:
        print('Preserved existing rig recipe:', recipe)
    print('Source inspected:', path, '| mesh nodes:', scan['mesh_instances'])
    print('Mesh hierarchy report:', report)
    for row in scan['mesh_nodes'][:60]:
        print(f"  [{row['gltf_node_index']:3}] {row['node_path']} — {row['vertices_declared']} vertices | {', '.join(row['possible_roles_UNVERIFIED'])}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
