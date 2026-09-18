class_name CameraRig
extends Node3D
## Isometric camera. Drag to pan, wheel or pinch to zoom, WASD/arrows or Q/E
## also work. The rig sits on the ground at the point being looked at; the
## camera hangs back along the view direction with an orthographic projection.
##
## Handles mouse, real multi-touch (phones/tablets) and trackpad gestures
## (two-finger pan, pinch zoom) as three separate input paths, so a touchpad
## behaves like a touchpad instead of being forced through mouse-only logic.
## A small deadzone gates every pointer path: the camera does not move at all
## until the press has travelled past it, so a light tap (or a jittery
## trackpad click) always reaches whatever is under it instead of nudging the
## view and losing the tap.

const PITCH := -38.0
const YAW := 45.0
const MIN_ZOOM := 10.0
const MAX_ZOOM := 220.0
const DEADZONE := 6.0            ## screen pixels before a press counts as a drag
const KEY_ZOOM_RATE := 1.15      ## multiplicative zoom speed per second for Q/E
const PAN_GESTURE_SCALE := 45.0  ## screen-pixel-equivalent per trackpad pan unit

@export var bounds := 30.0

var camera: Camera3D
var _zoom := 40.0

# single-pointer press (mouse button or one finger)
var _pointer_down := false
var _pan_active := false
var _accum := Vector2.ZERO
var _drag_button := MOUSE_BUTTON_LEFT

# real multi-touch
var _touches: Dictionary = {}       ## touch index -> last Vector2 position
var _touch_pan_active := false
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 0.0
var _touch_mid_prev := Vector2.ZERO

## Set while the pointer is over the UI, or while the game wants exclusive
## control of drags (placing a building, laying a wall), so the world ignores
## the gesture instead of panning underneath it.
var blocked := false

signal tapped(screen_pos: Vector2)
signal pressed(screen_pos: Vector2)
signal drag_moved(screen_pos: Vector2)
signal released(screen_pos: Vector2)

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
	camera.far = 420.0
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

# ---------------------------------------------------------------- mouse + wheel
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventPanGesture:
		# trackpad two-finger scroll (mainly macOS): pan, never zoom
		if not blocked:
			_pan_by_screen((event as InputEventPanGesture).delta * PAN_GESTURE_SCALE)
	elif event is InputEventMagnifyGesture:
		# trackpad pinch: factor > 1 means "spread fingers", i.e. zoom in
		if not blocked:
			var mg := event as InputEventMagnifyGesture
			_zoom_at(mg.position, _zoom / maxf(mg.factor, 0.01))
	elif event is InputEventScreenTouch:
		_on_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event as InputEventScreenDrag)

func _on_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(mb.position, _zoom / 1.12)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(mb.position, _zoom * 1.12)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
		if not blocked:
			_pan_by_screen(Vector2(-70.0, 0))
	elif mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
		if not blocked:
			_pan_by_screen(Vector2(70.0, 0))
	elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			# `blocked` only ever suppresses the camera actually panning (see
			# _continue_press); the press itself must still be tracked so a
			# placement mode in progress keeps getting its pressed/drag_moved/
			# tapped signals.
			if _touches.size() > 0:
				return
			_drag_button = mb.button_index
			_begin_press(mb.position)
		elif _pointer_down and mb.button_index == _drag_button:
			_end_press(mb.position)

func _on_mouse_motion(mm: InputEventMouseMotion) -> void:
	if not _pointer_down:
		return
	_continue_press(mm.relative, mm.position)

# ---------------------------------------------------------------- shared drag logic
## Used by both the mouse-button path and a single finger touching the screen.
func _begin_press(pos: Vector2) -> void:
	_pointer_down = true
	_pan_active = false
	_accum = Vector2.ZERO
	pressed.emit(pos)

func _continue_press(relative: Vector2, pos: Vector2) -> void:
	drag_moved.emit(pos)
	# The deadzone/pan-active classification always runs, even while blocked,
	# so a real drag is still remembered as a drag (and so never fires
	# `tapped` on release) -- only the actual camera movement is skipped while
	# something else (placing a building, laying a wall) owns the drag.
	_accum += relative
	if not _pan_active:
		if _accum.length() <= DEADZONE:
			return
		_pan_active = true
		if not blocked:
			_pan_by_screen(_accum)
		_accum = Vector2.ZERO
	elif not blocked:
		_pan_by_screen(relative)

func _end_press(pos: Vector2) -> void:
	_pointer_down = false
	if not _pan_active:
		tapped.emit(pos)
	released.emit(pos)

# ---------------------------------------------------------------- real touch
func _on_screen_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_begin_press(t.position)
		elif _touches.size() == 2:
			# a second finger joined: abandon any single-finger tap/pan in
			# progress and start a pinch from here
			_pointer_down = false
			_pan_active = false
			_touch_pan_active = true
			var pts := _touches.values()
			_pinch_start_dist = maxf((pts[0] as Vector2).distance_to(pts[1] as Vector2), 1.0)
			_pinch_start_zoom = _zoom
			_touch_mid_prev = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
	else:
		_touches.erase(t.index)
		if _touches.size() < 2:
			_touch_pan_active = false
		if _touches.is_empty() and _pointer_down:
			_end_press(t.position)
		else:
			_pointer_down = false

func _on_screen_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	_touches[d.index] = d.position
	if _touches.size() == 1 and _pointer_down:
		_continue_press(d.relative, d.position)
	elif _touches.size() == 2 and _touch_pan_active:
		var pts := _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var dist := maxf(a.distance_to(b), 1.0)
		if not blocked:
			# pinch to zoom, from the gesture's own start (stable even if one
			# finger moves more than the other), plus a two-finger pan
			set_zoom(_pinch_start_zoom * (_pinch_start_dist / dist))
			var mid := (a + b) * 0.5
			_pan_by_screen(_touch_mid_prev - mid)
		_touch_mid_prev = (a + b) * 0.5

# ---------------------------------------------------------------- camera math
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
	if move != Vector2.ZERO and not blocked:
		_pan_by_screen(-move.normalized() * 620.0 * delta)
	# Q zooms in, E zooms out: a steady multiplicative rate so it feels the
	# same whether you are zoomed in tight or pulled all the way back.
	if Input.is_key_pressed(KEY_Q):
		set_zoom(_zoom / pow(KEY_ZOOM_RATE, delta * 6.0))
	if Input.is_key_pressed(KEY_E):
		set_zoom(_zoom * pow(KEY_ZOOM_RATE, delta * 6.0))
