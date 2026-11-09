"""Static project-preflight checks; NOT a substitute for running Godot."""
from pathlib import Path
import re

base = Path(__file__).resolve().parents[1]
assert (base / "project.godot").exists()
scene = (base / "landworks/scenes/test_yard.tscn").read_text()
assert 'res://landworks/scripts/test_yard.gd' in scene
scripts = sorted((base / "landworks/scripts").glob("*.gd"))
assert len(scripts) >= 6

for script in scripts:
    code = script.read_text()
    assert code.startswith('#') or code.startswith('extends '), script
    assert 'extends ' in code, script
    for ref in re.findall(r'preload\("res://([^\"]+)"\)', code):
        assert (base / ref).exists(), f'{script.name} preloads missing {ref}'
    # Lightweight delimiter check, ignoring quoted strings and comments.
    bracket_stack = []
    opening = {"(": ")", "[": "]", "{": "}"}
    in_string = False
    escaped = False
    for lineno, line in enumerate(code.splitlines(), 1):
        for char in line:
            if not in_string and char == '#':
                break
            if in_string:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    in_string = False
                continue
            if char == '"':
                in_string = True
            elif char in opening:
                bracket_stack.append((opening[char], lineno))
            elif char in ')]}':
                assert bracket_stack and bracket_stack[-1][0] == char, f'{script}:{lineno}: unexpected {char}'
                bracket_stack.pop()
    assert not in_string and not bracket_stack, f'unbalanced delimiters in {script}'
    print(f'PASS {script.relative_to(base)} ({len(code.splitlines())} lines)')

print('PASS: source paths and static delimiters; runtime remains untested')
