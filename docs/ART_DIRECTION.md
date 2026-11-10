# Painted countryside: scene rendering & engineering access

Art direction is the user-approved concept render: warm illustrated countryside,
soft sky/clouds, detailed vintage Kubota tractor, orange KX080 work excavator,
woodland, flowered meadow, timber workshop, contrasting cut banks and granular
spoils. This work is **3D geometry drawn by Godot**, not a 2D image pasted onto
the scene, and not the original concept illustration packed into the game.

The new art modules:
- `art_scene.gd`: colour-graded 140m meadow, sculpted barn, wood fences,
  procedurally instanced grass/flowers/pebbles, trees, clouds and stake details
- `machine_art.gd`: proportioned decorative shells on the EXISTING B7100HST
  and KX080 Jolt bodies, turf tread bars, hydraulic rods updated to match
  moving joint transforms, and a visually open-toothed bucket
- `sandbox_world.gd`: painterly procedural sky, warm sun, ambient light,
  gentle atmospheric fog, and a 65-degree follow camera

**Visual realism vs engineering fidelity:** mesh geometry is an improved
hand-modelled approximation, not exact OEM CAD or a licensed scan. The physics
still uses the validated rigid-body collision shells, not the polygon detail.
Final OEM fidelity requires appropriately licensed segmented source assets
at the actual centre distances, pivot positions, linkages and hydraulic pin
locations. Imported GLBs for tractor body/wheels still override fallback art.

### Access to soil pad

Work-area entrance is a real simulation check: the KX080's four contact-patch
crawler drives from the yard toward negative Z onto the physical 18m pad.
The previous 45mm hidden collision lip is now inset under the yard, and the
1,500kg crate is moved aside outside automated pushing cases. A successful
test must actually cross the boundary with contact and without tipping.

### Continuous integration

`.github/workflows/visual-ci.yml` runs:
1. Godot 4.6.1 script/asset import
2. real crawler entry (headless Jolt physics)
3. two **actual software-rendered frames** of the playable Godot scene
   via xvfb/Mesa and GL Compatibility renderer
4. PNG validation and downloadable screenshots in GitHub Actions artifacts.

Visual art changes should not be accepted on import alone. Real rendered
frame verification is required, plus previously established 13 physics
scenarios and powered earthmoving conservation tests.
