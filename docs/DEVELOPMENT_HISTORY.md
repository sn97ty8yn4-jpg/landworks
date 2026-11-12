# Landworks v0.6 — working-load scenarios

New scenes: `landworks/scenes/tractor_work_lab.tscn` (tractor + dynamic single-axle trailer, 0–800 kg payloads, 0–6° ground) and `landworks/scenes/excavator_work_lab.tscn` (unfrozen 8.17 t KX080 proxy, rigid body boom and load, physical slewing upper assembly, ground-contact tracks, 250–1000 kg payloads). See `docs/V06_FIELD_TRIALS.md` for cases and limitations. `RUN_FIELD_TESTS_WINDOWS.bat` runs all seven cases using your Godot 4.6 executable and validates genuine CSV outputs; offline Python calculations are explicitly separate. **No Godot runtime test was possible in the authoring environment.**

---

# Landworks v0.5 — 3-engine tractor comparison + force-based excavator

**New standalone Godot 4.6 scenes, extending the v0.4 project without removing it:**

1. **`landworks/scenes/physics_comparison_lab.tscn`** — automatic side-by-side physics test of the baseline B7100 proxy vs **KV Vehicle** vs **Godot Easy Vehicle Physics**, with separate implementations and actual Godot-derived telemetry CSV output. Run `SETUP_PHYSICS_WINDOWS.bat` first (Python 3 + internet). If the add-ons are missing, the UI reports them as unavailable — it does NOT fabricate data.
2. **`landworks/scenes/physical_excavator_lab.tscn`** — actual gravity-affected rigid-body boom/stick/bucket, torque-limited `HingeJoint3D` motors and 250/500 kg suspended physics payload attached with a `PinJoint3D`. Automatic or manual hydraulic-*control proxy*; actual hydraulic circuits are NOT simulated.
3. Original **`landworks/scenes/test_yard.tscn`** remains intact (visual-only v0.4 excavator, baseline tractor).

**Detailed test instructions, code audit, licence references and acceptance thresholds: `docs/V05_EVALUATION.md`.**

## First run

1. Install Godot 4.6 and Python 3 on Windows; unzip the entire folder.
2. Double-click `SETUP_PHYSICS_WINDOWS.bat` and restart Godot after it downloads the pinned MIT packages. The project defaults to **Jolt Physics at 120 Hz**. `RESTORE_BASELINE_PHYSICS_WINDOWS.bat` can restore GodotPhysics3D at 60 Hz for A/B testing.
3. Open `project.godot` in Godot, then open each `.tscn` above and press **F6** (Run Current Scene).
4. From the main yard, D-pad left/F5 opens the tractor comparison, D-pad right/F4 opens the physical lift lab; Circle/F4 returns to the yard. Observe the benchmark and load test. The benchmark writes results into `user://landworks_comparison_samples.csv` and `user://landworks_comparison_summary.csv`. The project shows the save location in its Output panel. To turn the recorded CSV into a comparison report, run `ANALYSE_BENCH_WINDOWS.bat` and supply the CSV path; the script refuses missing or invalid measurements.

## Limitations

The numerical handling comparison has **not yet been run**: the authoring environment has no Godot executable or installed vendor packages and cannot fetch binaries. The scripts implement the comparisons and physical joints but require runtime testing on the target PC. The excavator's lower chassis is deliberately anchored for an isolated load-lifting test, and the HingeJoint motors are not a calibrated hydraulic-pressure system. No exact Kubota donor mesh is bundled. The v0.2–0.4 GLB downloading/rigging pipeline and documentation are preserved.

## Existing assets and rigging

Use `DOWNLOAD_MODELS_WINDOWS.bat`, `SCAN_MODELS_WINDOWS.bat`, `INSPECT_IN_BLENDER_WINDOWS.bat` and `EXPORT_RIGS_WINDOWS.bat` for the previously identified CC0 tractor and excavator visual donors. Their actual models are not included because original binary downloads could not be verified. See `docs/RIGGING_GUIDE.md` and `docs/ASSET_SOURCES.md`.

## Offline source checks

```cmd
python -m unittest discover -s tests -p "test_*.py" -v
python tests/check_project.py
```

These are structural checks, not substitute simulations. `COPYING-NOTES.md` covers code and model licensing.


## First integrated sandbox

Open the project in Godot 4.6.1 and Run (F6 for the sandbox scene).
The default scene now combines the real powered-joint excavator, HST tractor,
loaded trailer and movable loads in one collision world. See
`docs/SANDBOX.md` for controls, scene layout and physical test methodology.
