extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var failures: Array[String] = []
func check(value: bool, reason: String) -> void:
    if not value: failures.append(reason)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var world = WORLD.instantiate()
    root.add_child(world)
    var cab = world.machine_visuals.cab
    cab.set_process(false)
    cab.commands = {"boom":1.0,"stick":1.0,"bucket":1.0,"slew":1.0,"left_track":1.0,"right_track":-1.0}
    cab._process(1.0)
    for i in range(2):
        check(absf(cab.controls[i].rotation.length()-deg_to_rad(16))<0.001,"Joystick diagonal exceeds circular gate")
    check(cab.controls[2].rotation.x<0 and cab.controls[3].rotation.x>0,"Track controls do not pivot oppositely")
    world._select_machine(1)
    var event := InputEventKey.new()
    event.keycode = KEY_V
    event.pressed = true
    world._unhandled_input(event)
    check(cab.seated and cab.camera.current,"V did not enter cab")
    check(cab.head.global_position.distance_to(world.digger.upper.to_global(cab.EYE))<0.001,"Seat is not attached to upper carriage")
    cab.look(1000,1000)
    check(cab.yaw==118.0 and cab.pitch==38.0,"Head look limits")
    cab.reset_look()
    world._select_machine(0)
    check(not cab.seated and world.camera.current,"Machine switch did not restore follow camera")
    cab.commands = {}
    cab._process(2.0)
    for control in cab.controls: check(control.rotation.length()<0.001,"Control did not return to neutral")
    for failure in failures: push_error(failure)
    print("DETAILED_CAB ","PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
