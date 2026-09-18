class_name CameraRig
extends Node3D
## Isometric camera. Drag to pan, wheel or pinch to zoom, WASD also pans.
## The rig sits on the ground at the point being looked at; the camera hangs
## back along the view direction with an orthographic projection.

const PITCH := -38.0
const YAW := 45.0
const MIN_ZOOM := 10.0
const MAX_ZOOM := 72.0

@export var bounds := 30.0

var camera: Camera3D
var _zoom := 40.0
var _dragging := false
var _drag_button := MOUSE_BUTTON_LEFT
var _last_pos := Vector2.ZERO
var _moved := 0.0
var _touches := {}
var _pinch := 0.0
## Set while the pointer is over the UI so the world ignores the gesture.
var blocked := false

signal tapped(screen_pos: Vector2)

func _ready() -> void:
	rotation_degrees = Vector3(PITCH, YAW, 0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom
	# Kept deliberately close: directional shadows and fog are measured as a
	# distance from the camera, and an orthographic view looks identical at any
	# distance, so hanging far back would push the base out of shadow range.
	camera.position = Vector3(0, 0, 40)
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)

func set_zoom(z: float) -> void:
	_zoom = clamp(z, MIN_ZOOM, MAX_ZOOM)
	camera.size = _zoom

func get_zoom() -> float:
	return _zoom

func focus_on(p: Vector3, immediate := true) -> void:
	if immediate:
		position = Vector3(p.x, 0, p.z)
	else:
		create_tween().tween_property(self, "position", Vector3(p.x, 0, p.z), 0.35).set_trans(Tween.TRANS_CUBIC)

## Where a screen point lands on the ground plane (y = 0).
func screen_to_ground(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 1e-5:
		return Vector3.ZERO
	var t := -origin.y / dir.y
	return origin + dir * t

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, _zoom / 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, _zoom * 1.12)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if blocked:
					return
				_dragging = true
				_drag_button = mb.button_index
				_last_pos = mb.position
				_moved = 0.0
			elif _dragging and mb.button_index == _drag_button:
				_dragging = false
				if _moved < 8.0 and mb.button_index == MOUSE_BUTTON_LEFT:
					tapped.emit(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_moved += mm.relative.length()
		_pan_by_screen(mm.relative)
		_last_pos = mm.position

func _zoom_at(screen: Vector2, target: float) -> void:
	var before := screen_to_ground(screen)
	set_zoom(target)
	var after := screen_to_ground(screen)
	position += before - after
	_clamp()

func _pan_by_screen(delta: Vector2) -> void:
	# convert a screen drag into movement across the ground plane
	var scale := _zoom / float(get_viewport().get_visible_rect().size.y)
	var right := global_transform.basis.x
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6:
		fwd = fwd.normalized()
	var up_on_ground := fwd / maxf(cos(deg_to_rad(PITCH)), 0.2)
	position -= right * delta.x * scale
	position -= up_on_ground * delta.y * scale
	_clamp()

func _clamp() -> void:
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	position.y = 0.0

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if move != Vector2.ZERO:
		_pan_by_screen(-move.normalized() * 620.0 * delta)
