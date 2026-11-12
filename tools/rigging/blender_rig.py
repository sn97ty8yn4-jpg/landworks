"""Blender 4.4+ bridge: inspect donor geometry, then export deliberately mapped parts.

Usage (from project root):
  blender -b -P tools/rigging/blender_rig.py -- --stage inspect --machine b7100
  blender -b landworks/assets/workbench/b7100.blend \
    -P tools/rigging/blender_rig.py -- --stage export --machine b7100

Inspect creates .blend workbench and a Blender mesh-object report. Open that .blend
and select/edit mesh objects. Fill in tools/rigging/recipes/<machine>.json with exact
Blender mesh object names and hinge coordinates in donor/Blender XYZ (Z up).
Export ONLY runs if parts are deliberately mapped. No fake auto rigging.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

try:
    import bpy
    from mathutils import Euler, Matrix, Vector
except ImportError as exc:
    raise SystemExit('Run inside Blender: bpy is required') from exc

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'landworks/assets/source'
REPORTS = ROOT / 'landworks/assets/reports'
WORKBENCH = ROOT / 'landworks/assets/workbench'
OUT = ROOT / 'landworks/assets/rigged'
RECIPES = ROOT / 'tools/rigging/recipes'
FILENAME = {'b7100': 'garden-tractor-with-trailer.glb',
            'kx080': 'compact-tracked-excavator.glb'}
OUTPUT_NAMES = {
    'b7100': {'body': 'b7100_body.glb', 'wheel_front': 'b7100_wheel_front.glb', 'wheel_rear': 'b7100_wheel_rear.glb'},
    'kx080': {'track': 'kx080_track.glb', 'upper': 'kx080_upper.glb', 'boom': 'kx080_boom.glb',
              'stick': 'kx080_stick.glb', 'bucket': 'kx080_bucket.glb'},
}


def args_parse():
    cmd = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=['inspect', 'export'], required=True)
    parser.add_argument('--machine', choices=list(FILENAME), required=True)
    parser.add_argument('--input', type=Path, help='Source GLB override for the inspection stage')
    parser.add_argument('--recipe', type=Path, help='Rig mapping override for export')
    parser.add_argument('--out', type=Path, default=OUT)
    parser.add_argument('--save-workbench', action='store_true', default=False)
    return parser.parse_args(cmd)


def import_source(path: Path):
    if not path.is_file():
        raise FileNotFoundError(f'Donor GLB missing: {path}. Run tools/windows/DOWNLOAD_MODELS_WINDOWS.bat first.')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()
    return [o for o in bpy.data.objects if o.type == 'MESH']


def collect_bounds(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return {'min_blender_z_up_m': [round(min(p[i] for p in pts), 5) for i in range(3)],
            'max_blender_z_up_m': [round(max(p[i] for p in pts), 5) for i in range(3)]}


def inspect(machine: str, path: Path, do_save: bool):
    mesh_objects = import_source(path)
    if not mesh_objects:
        raise ValueError('No mesh objects imported; inspect source GLB')
    REPORTS.mkdir(parents=True, exist_ok=True)
    report = {
        'machine': machine, 'donor': path.name,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'count': len(mesh_objects),
        'mesh_objects': [
            {'blender_name_EXACT': o.name, 'vertices': len(o.data.vertices), 'polygons': len(o.data.polygons),
             'parent': o.parent.name if o.parent else None, 'bounds': collect_bounds(o),
             'materials': [slot.material.name if slot.material else None for slot in o.material_slots]}
            for o in sorted(mesh_objects, key=lambda x: x.name)
        ],
        'warning': 'Do not infer separate moving parts from the word assembly. Verify each mesh and hinge in Blender.'
    }
    report_path = REPORTS / (machine + '_blender_meshes.json')
    report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'[Landworks] {len(mesh_objects)} Blender meshes; full report {report_path}')
    for o in report['mesh_objects']:
        print(f"    {o['blender_name_EXACT']:42s} {o['vertices']:8d} vertices {o['bounds']}")
    if do_save:
        WORKBENCH.mkdir(parents=True, exist_ok=True)
        blend = WORKBENCH / (machine + '.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(blend))
        print('[Landworks] Saved editable workbench:', blend)


def validate_recipe(recipe, machine: str, source_glb: Path):
    expected = OUTPUT_NAMES[machine]
    if recipe.get('schema_version') != 1 or recipe.get('machine') != machine:
        raise ValueError('Recipe schema version/machine mismatch')
    if recipe.get('source_glb') != FILENAME[machine]:
        raise ValueError('Recipe is for a different source GLB')
    expected_sha = recipe.get('expected_source_sha256')
    if source_glb.exists() and expected_sha:
        actual = hashlib.sha256(source_glb.read_bytes()).hexdigest()
        if actual != expected_sha:
            raise ValueError('Source GLB hash changed since scan; inspect again before exporting')
    source_frame = recipe.get('source_to_machine', {})
    scale = float(source_frame.get('uniform_scale', 1))
    angles = source_frame.get('rotation_xyz_deg_blender_z_up', [0,0,0])
    if not (0.01 <= scale <= 100) or len(angles) != 3 or not all(math.isfinite(float(a)) for a in angles):
        raise ValueError('Invalid source_to_machine transform')
    assignments = recipe.get('parts', {})
    if set(assignments) != set(expected):
        raise ValueError('Part roles must be exactly: ' + ', '.join(expected))
    taken = set()
    valid = {}
    for role in expected:
        item = assignments[role]
        names = item.get('objects', [])
        pivot = item.get('pivot_source_blender_m')
        if not names or not isinstance(names, list) or not all(isinstance(s, str) and s for s in names):
            raise ValueError(f'{role}: assign one or more Blender mesh names before export')
        if not isinstance(pivot, list) or len(pivot) != 3 or not all(math.isfinite(float(p)) for p in pivot):
            raise ValueError(f'{role}: invalid pivot, require 3 finite numbers')
        part_scale = item.get('part_scale_xyz', [1,1,1])
        part_rotate = item.get('rest_rotation_xyz_deg_blender', [0,0,0])
        if len(part_scale) != 3 or not all(0.01 <= float(v) <= 100 for v in part_scale):
            raise ValueError(f'{role}: part_scale_xyz must be three positive values')
        if len(part_rotate) != 3 or not all(math.isfinite(float(v)) for v in part_rotate):
            raise ValueError(f'{role}: invalid part rotation')
        matched = []
        for name in names:
            if name in taken:
                raise ValueError(f'{name} assigned twice — moving parts must not overlap')
            ob = bpy.data.objects.get(name)
            if ob is None or ob.type != 'MESH':
                raise ValueError(f'{role}: mesh {name!r} is not present in current Blender scene')
            taken.add(name)
            matched.append(ob)
        valid[role] = (matched, Vector(tuple(float(x) for x in pivot)),
                       [float(v) for v in part_scale], [math.radians(float(v)) for v in part_rotate])
    return valid, scale, [math.radians(float(a)) for a in angles]


def export_machine(machine: str, recipe_path: Path, out: Path):
    if not recipe_path.is_file():
        raise FileNotFoundError(f'Create recipe first with scan_glb.py: {recipe_path}')
    recipe = json.loads(recipe_path.read_text(encoding='utf-8'))
    source_glb = SOURCE / FILENAME[machine]
    if not any(o.type == 'MESH' for o in bpy.data.objects):
        import_source(source_glb)
    mapped, scale, angles = validate_recipe(recipe, machine, source_glb)
    frame = Euler(tuple(angles), 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((scale, scale, scale, 1))
    out.mkdir(parents=True, exist_ok=True)
    exported = {}
    for role, (objects, pivot, part_scale, part_rotate) in mapped.items():
        pivot_machine = frame @ pivot
        source_matrices = [(o, o.matrix_world.copy()) for o in objects]
        copies = []
        try:
            bpy.ops.object.select_all(action='DESELECT')
            for original, src_matrix in source_matrices:
                clone = original.copy()
                clone.data = original.data.copy()
                clone.animation_data_clear()
                bpy.context.scene.collection.objects.link(clone)
                clone.parent = None
                clone.name = f'LW_{role}_{original.name}'
                # Every exported part is expressed *about its own hinge/axle*
                # in the common machine body reference frame, not at its old root.
                part_basis = Euler(tuple(part_rotate), 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((*part_scale, 1))
                clone.matrix_world = part_basis @ Matrix.Translation(-pivot_machine) @ frame @ src_matrix
                clone.select_set(True)
                copies.append(clone)
            bpy.context.view_layer.objects.active = copies[0]
            filepath = out / OUTPUT_NAMES[machine][role]
            bpy.ops.export_scene.gltf(filepath=str(filepath), export_format='GLB',
                                      use_selection=True, export_yup=True,
                                      export_materials='EXPORT')
            if not filepath.is_file() or filepath.stat().st_size < 64:
                raise RuntimeError(f'Export failed: {filepath}')
            exported[role] = {'file': filepath.name, 'sha256': hashlib.sha256(filepath.read_bytes()).hexdigest(),
                              'bytes': filepath.stat().st_size, 'objects': [o.name for o in objects],
                              'pivot_source_blender_m': list(pivot), 'part_scale_xyz': part_scale,
                              'rest_rotation_xyz_deg_blender': [round(math.degrees(x),4) for x in part_rotate],
                              'pivot_machine_blender_m': [round(x, 6) for x in pivot_machine]}
            print(f'[Landworks] Exported {role}: {filepath.name} ({filepath.stat().st_size:,} bytes)')
        finally:
            for clone in copies:
                bpy.data.objects.remove(clone, do_unlink=True)
    report = {'machine': machine, 'source_glb': FILENAME[machine], 'recipe': recipe_path.name,
              'expected_source_sha256': recipe.get('expected_source_sha256'),
              'created_parts': exported,
              'warning': 'Visual-only exports. Check scale, pivots, fit and motion in Godot. Physics unchanged.'}
    report_file = out / (machine + '_rig_manifest.json')
    report_file.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('[Landworks] Export manifest:', report_file)


def main():
    opts = args_parse()
    if opts.stage == 'inspect':
        inspect(opts.machine, opts.input or SOURCE / FILENAME[opts.machine], True)
    else:
        export_machine(opts.machine, opts.recipe or RECIPES / (opts.machine + '.json'), opts.out)

if __name__ == '__main__':
    try:
        main()
    except Exception as err:
        print('[Landworks] Rig export failed:', type(err).__name__, err, file=sys.stderr)
        raise
