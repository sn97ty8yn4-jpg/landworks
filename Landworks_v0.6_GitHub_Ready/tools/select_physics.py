#!/usr/bin/env python3
"""Explicitly select a 3D physics backend, preserving a timestamp-free backup."""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'project.godot'
ENGINES = {'jolt': 'Jolt Physics', 'baseline': 'GodotPhysics3D'}

def select(name: str):
    original = PROJECT.read_text(encoding='utf-8')
    backup = ROOT / 'project.godot.physics-original.bak'
    if not backup.exists():
        backup.write_text(original, encoding='utf-8')
    engine = ENGINES[name]
    physics = re.search(r'(?m)^\[physics\]\s*\n(?P<section>(?:(?!^\[).*(?:\n|$))*)',original)
    if not physics:
        raise ValueError('[physics] section missing; no changes applied')
    section = physics.group('section')
    if '3d/physics_engine=' not in section or 'common/physics_ticks_per_second=' not in section:
        raise ValueError('Expected physics settings missing; no changes applied')
    updated = re.sub(r'(?m)^3d/physics_engine=.*$', '3d/physics_engine="%s"' % engine, section)
    ticks = 120 if name == 'jolt' else 60
    updated = re.sub(r'(?m)^common/physics_ticks_per_second=.*$', 'common/physics_ticks_per_second=%d' % ticks, updated)
    result = original[:physics.start('section')] + updated + original[physics.end('section'):]
    PROJECT.write_text(result, encoding='utf-8')
    print('Set Godot physics:',engine,'at',ticks,'Hz; restart Godot.')
    print('Previous project.godot stored as:',backup)

if __name__ == '__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('mode',choices=['jolt','baseline'])
    select(ap.parse_args().mode)
