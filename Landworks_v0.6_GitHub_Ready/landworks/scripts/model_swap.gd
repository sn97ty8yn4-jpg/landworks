# Optional model import boundary. Does not change collisions or vehicle physics.
# A split, correctly pivoted GLB replaces only its corresponding placeholder art.
extends RefCounted

static func place_visual(mount: Node3D, placeholder: Node3D, path: String) -> bool:
    if not ResourceLoader.exists(path):
        return false
    var resource := ResourceLoader.load(path)
    if not (resource is PackedScene):
        push_warning("Landworks: cannot open GLB as PackedScene: " + path)
        return false
    var candidate: Node = resource.instantiate()
    if not (candidate is Node3D):
        candidate.free()
        push_warning("Landworks: imported mesh root is not Node3D: " + path)
        return false
    candidate.name = "LicensedGLBVisual"
    mount.add_child(candidate)
    placeholder.visible = false
    return true
