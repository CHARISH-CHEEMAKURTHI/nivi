class_name FirstPersonCam
extends Node3D
## The King's own eyes: a perspective camera carried at head height wherever
## he stands, in the kingdom or on a raid. Drag (mouse or finger) or hold Q/E
## to look around; whoever moves the King feeds `update_pose` every frame.
## Nothing here moves him -- BaseWorld and BattleWorld own that -- so the same
## node serves both scenes.

const LOOK_SENSITIVITY := 0.0042
const TURN_RATE := 1.9             ## radians per second for Q/E
const EYE_ON_FOOT := 1.05
const EYE_MOUNTED := 1.45

var camera: Camera3D
var yaw := 0.0
var pitch := -0.12
var enabled := false

func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 78.0
	camera.near = 0.08
	camera.far = 420.0
	camera.current = false
	add_child(camera)
	set_process(false)

## Takes over (or hands back) the viewport. `facing` seeds the look direction
## from the way the King is already turned so the view does not snap.
func enable(on: bool, facing := yaw) -> void:
	enabled = on
	camera.current = on
	set_process(on)
	if on:
		yaw = facing

func update_pose(feet: Vector3, mounted: bool) -> void:
	position = feet + Vector3(0, EYE_MOUNTED if mounted else EYE_ON_FOOT, 0)
	rotation = Vector3(pitch, yaw, 0.0)

## Ground-plane forward and right for whoever walks the King, so "W" always
## means "the way I am looking".
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		yaw += TURN_RATE * delta
	if Input.is_key_pressed(KEY_E):
		yaw -= TURN_RATE * delta

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var rel := Vector2.ZERO
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		rel = (event as InputEventMouseMotion).relative
	elif event is InputEventScreenDrag:
		rel = (event as InputEventScreenDrag).relative
	else:
		return
	yaw -= rel.x * LOOK_SENSITIVITY
	pitch = clampf(pitch - rel.y * LOOK_SENSITIVITY, -1.15, 0.95)
