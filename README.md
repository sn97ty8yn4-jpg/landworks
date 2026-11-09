# Landworks — Godot machinery simulator

Open-source machinery simulator prototype targeting **Godot 4.6.1 Standard (GDScript)**.

**Project status:** GitHub development environment is being configured. The v0.6 source package must be imported into this repository before real physics tests can run. Do not confuse mathematical/offline screening with measurements from a Godot process.

## Development scope

- Kubota B7100 HST compact tractor: turf tyres, hydrostatic drive, towing and loaded hill work.
- Kubota KX080-3 excavator: crawler movement, powered boom/stick/bucket constraints, real load handling and chassis stability.
- Trial physics integrations: Godot Jolt, KV Vehicle, Godot Easy Vehicle Physics.
- Deformable terrain and precise machines are later milestones.

## Setup

1. Obtain **Landworks Godot v0.6 Working Load Field Trials** from the ChatGPT project discussion.
2. Extract the ZIP and copy **the contents of the inner `landworks_v0_6` folder** into this repository's root. The root must contain `project.godot`, `landworks/`, `tools/`, `tests/`, `docs/`. Preserve the existing `.github/` folder.
3. Commit and push the changes.
4. Open **Actions** and inspect **Godot CI / Headless field trials**. The runner installs Godot and tests the project independently of a local PC.

For local development: open `project.godot` in **Godot 4.6.1 Standard**, enable Jolt and run the tractor or excavator lab scenes. To run the seven physics scenarios locally:

```bash
python tools/run_work_tests.py --godot godot --case all
```

The CI workflow separates **Python source/unit checks**, **Godot editor import/parsing**, and **actual headless physics telemetry**. The latter needs successful simulation, no parse errors and complete CSV samples. A numerical result is not regarded as verified until a Godot run produces it.

## Source/assets licensing

Upstream dependencies and CC0 model listings must be reviewed before bundling assets. The existing v0.6 project contains licence notes; commercial Kubota brand/model imagery is not automatically under a reusable licence.

## Relationship to Tinybox

Build and validate the machinery in this standalone Godot project first. Later, integrate the machines into a separate Tinybox fork with careful consideration of its AGPLv3 licence.
