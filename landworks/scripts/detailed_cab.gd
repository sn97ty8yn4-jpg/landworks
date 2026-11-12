# Camera and controls fitted to the recovered detailed GLB, not the old shell.
# The four moving nodes contain the original geometry and original materials.
extends Node3D
# Seated eye point in the upper structure's own frame. The original rig and
# the KX080-3 model place the floor at different heights, so it is settable.
const EYE := Vector3(-0.58,2.25,-0.08)
var EYE_OVERRIDE := EYE
var camera: Camera3D
var head: Node3D
var controls: Array[Node3D] = []
var commands := {"boom":0.0,"stick":0.0,"bucket":0.0,"slew":0.0,"left_track":0.0,"right_track":0.0}
var smooth := commands.duplicate()
var seated := false
var yaw := 0.0
var pitch := -15.0

var levers_rigged := false

func attach(part: Node3D) -> void:
    # The original upper rig exposes four moving controls. The KX080-3 model
    # has a modelled but unsplit interior, so the seated camera works there
    # while the levers stay static; report which case applies, never pretend.
    var found: Array[Node3D] = []
    for key in ["CabLeftJoystick","CabRightJoystick","CabLeftTravel","CabRightTravel"]:
        var control := part.find_child(key,true,false) as Node3D
        if control == null:
            found.clear()
            break
        found.append(control)
    controls = found
    levers_rigged = not controls.is_empty()
    head = Node3D.new()
    head.position = EYE_OVERRIDE
    add_child(head)
    camera = Camera3D.new()
    camera.name = "DetailedCabCamera"
    camera.fov = 74.0
    camera.near = 0.035
    camera.far = 2800.0
    head.add_child(camera)
    look(0.0,0.0)

func set_seated(value: bool) -> void:
    seated = value
    camera.current = value

func look(horizontal: float, vertical: float) -> void:
    yaw = clampf(yaw+horizontal,-118.0,118.0)
    pitch = clampf(pitch+vertical,-65.0,38.0)
    head.rotation_degrees = Vector3(pitch,yaw,0)

func reset_look() -> void:
    yaw = 0.0
    pitch = -15.0
    look(0,0)

func _process(delta: float) -> void:
    if controls.is_empty(): return
    for key in smooth:
        smooth[key] = lerpf(float(smooth[key]),clampf(float(commands.get(key,0.0)),-1.0,1.0),1.0-exp(-delta*16.0))
    var left := Vector2(float(smooth["slew"]),float(smooth["stick"])).limit_length(1.0)
    var right := Vector2(float(smooth["bucket"]),float(smooth["boom"])).limit_length(1.0)
    controls[0].rotation = Vector3(left.y,0,-left.x)*deg_to_rad(16.0)
    controls[1].rotation = Vector3(right.y,0,-right.x)*deg_to_rad(16.0)
    controls[2].rotation.x = -deg_to_rad(12.0)*float(smooth["left_track"])
    controls[3].rotation.x = -deg_to_rad(12.0)*float(smooth["right_track"])
