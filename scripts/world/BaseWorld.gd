class_name BaseWorld
extends Node3D
## The player's kingdom in 3D: keeps a model in sync with every building in the
## save, handles tapping to select, and runs the two build modes.
##
## Most buildings use "ghost" mode: a single translucent copy of the model
## follows your drag, and you confirm it with the Place button. Walls and
## roads use "line" mode instead, the way Clash of Clans lays them: press
## down and every tile you cross gets one immediately, in whatever direction
## you drag, with no Place button in the way — you just keep going until you
## press Done.

signal building_tapped(building: Dictionary)
signal ground_tapped(tile: Vector2i)
signal placement_changed(valid: bool)
signal caught(message: String, ok: bool)

var island: Island
var forest: Forest
var rig: CameraRig

# the King on foot: WASD / arrows or the on-screen stick steer him, the
# camera follows, and he can roam anywhere on land -- home island, bridge,
# forest -- but not through buildings
var walk_mode := false
var first_person := false             ## seen through the King's eyes; implies walk_mode
var joystick := Vector2.ZERO          ## set by the HUD's virtual stick
var king_pos := Vector3.ZERO
var mount := ""                       ## one of the King's bonded Nivians he is riding, or ""
var townsfolk: Townsfolk
var _king: Node3D
var _mount_node: Node3D = null
var _king_facing := 0.0
var _ball: Node3D = null
var _fp: FirstPersonCam

var _models: Dictionary = {}          ## building id -> Node3D
var _ghost: Node3D = null
var _ghost_type := ""
var _ghost_tile := Vector2i.ZERO
var _ghost_move_id := 0
var _selection: MeshInstance3D = null
var _selected_id := 0

# line mode (walls, roads)
var _line_mode := false
var _line_type := ""
var _line_marker: MeshInstance3D = null
var _line_last_tile := Vector2i.ZERO
var _line_has_last := false
const LINE_STEP_LIMIT := 400   ## a runaway drag falls back to a single tile past this

func _ready() -> void:
	add_child(WorldEnv.make_environment())
	add_child(WorldEnv.make_sun())
	island = Island.new()
	island.grid_size = Config.GRID
	add_child(island)
	forest = Forest.new()
	add_child(forest)
	rig = CameraRig.new()
	rig.bounds = Config.GRID * 0.5 + 2.0
	# the camera may travel east as far as the forest
	rig.bounds_max.x = forest.center.x + forest.half
	add_child(rig)
	_king = MeshBuilder.instance(Troops.build("king"))
	add_child(_king)
	var mid := Config.GRID / 2
	king_pos = Config.tile_to_world(mid, mid + 3)
	_king.position = king_pos
	_fp = FirstPersonCam.new()
	add_child(_fp)
	townsfolk = Townsfolk.new()
	add_child(townsfolk)
	rig.tapped.connect(_on_tapped)
	rig.pressed.connect(_on_pressed)
	rig.drag_moved.connect(_on_drag_moved)
	_selection = _make_marker(Color(0.4, 1.0, 0.6, 1), Color(0.6, 1.0, 0.75, 1))
	add_child(_selection)
	_selection.visible = false
	_line_marker = _make_marker(Color(0.4, 1.0, 0.6, 1), Color(0.6, 1.0, 0.75, 1))
	add_child(_line_marker)
	_line_marker.visible = false
	Game.buildings_changed.connect(rebuild)
	rebuild()

# ---------------------------------------------------------------- models
func rebuild() -> void:
	var seen := {}
	for b in Game.buildings():
		var id: int = b["id"]
		seen[id] = true
		if not _models.has(id):
			_models[id] = _spawn(b)
		_place_model(_models[id], b)
	for id in _models.keys():
		if not seen.has(id):
			_models[id].queue_free()
			_models.erase(id)

func _spawn(b: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshBuilder.instance(Buildings.build(b["type"]))
	mi.name = "Model"
	holder.add_child(mi)
	# a floating marker for "ready to collect" and "still building"
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 96
	tag.pixel_size = 0.006
	tag.outline_size = 28
	tag.modulate = Color.WHITE
	tag.outline_modulate = Color(0, 0, 0, 0.75)
	tag.visible = false
	holder.add_child(tag)
	add_child(holder)
	return holder

func _place_model(node: Node3D, b: Dictionary) -> void:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	var w := int(d["w"])
	var h := int(d["h"])
	node.position = Config.building_origin(b["x"], b["y"], w, h)
	var tag: Label3D = node.get_node("Tag")
	tag.position = Vector3(0, _tag_height(b["type"]), 0)

func _tag_height(type: String) -> float:
	match type:
		"castle": return 3.6
		"outpost": return 2.7
		"barracks_h", "tavern", "hospital": return 2.1
		"wall", "road": return 1.2
		_: return 1.7

func _process(delta: float) -> void:
	if walk_mode:
		_walk(delta)
	# keep the floating tags current: a coin when a mine is worth collecting,
	# a countdown while a building is going up
	for b in Game.buildings():
		var node: Node3D = _models.get(b["id"], null)
		if node == null:
			continue
		var tag: Label3D = node.get_node("Tag")
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		var model: Node3D = node.get_node("Model")
		if not Game.is_built(b):
			tag.text = _format_time(b["build_remaining"])
			tag.modulate = Color("9fe7ff")
			tag.visible = true
			model.scale = Vector3(1, 0.35, 1)
		else:
			model.scale = Vector3.ONE
			if d.has("produces") and b["stored"] >= float(d["produces"]["capacity"]) * 0.18:
				var res: String = d["produces"]["resource"]
				tag.text = str(int(b["stored"]))
				tag.modulate = Config.RESOURCES[res]["color"]
				tag.visible = true
				tag.position.y = _tag_height(b["type"]) + sin(Time.get_ticks_msec() * 0.004) * 0.12
			else:
				tag.visible = false

# ---------------------------------------------------------------- the King on foot
func set_walk_mode(on: bool) -> void:
	walk_mode = on
	joystick = Vector2.ZERO
	rig.keys_enabled = not on
	if on:
		clear_selection()
		rig.focus_on(king_pos, false)
		if rig.get_zoom() > 30.0:
			rig.set_zoom(22.0)
	elif first_person:
		set_first_person(false)

## Through the King's eyes. The isometric rig stays where it is (and stops
## panning on drags, since a drag now looks around); the King's own model is
## hidden so it does not fill the view.
func set_first_person(on: bool) -> void:
	if on and not walk_mode:
		set_walk_mode(true)
	first_person = on
	rig.blocked = on
	_fp.enable(on, _king_facing)
	_king.visible = not on
	if _mount_node != null:
		_mount_node.visible = not on
	if on:
		_fp.update_pose(king_pos, mount != "")
	else:
		rig.camera.make_current()
		_king_facing = _fp.yaw
		rig.focus_on(king_pos)

## Climb onto the next of the King's bonded Nivians, or down again after the
## last. Each kin has its own pace, so a Unitone is the fast ride.
func cycle_mount() -> String:
	var bonded: Array = Game.state["king"]["bonded"]
	if bonded.is_empty():
		mount = ""
	else:
		var i := bonded.find(mount)
		mount = "" if i == bonded.size() - 1 else str(bonded[i + 1])
	if _mount_node != null:
		_mount_node.queue_free()
		_mount_node = null
	if mount != "":
		_mount_node = MeshBuilder.instance(Troops.build(mount))
		_mount_node.visible = not first_person
		add_child(_mount_node)
	_place_king()
	return mount

func walk_speed() -> float:
	if mount == "":
		return Config.KING_WALK_SPEED
	return Config.KING_WALK_SPEED + 1.4 * float(Config.CREATURES[mount]["speed"])

func _place_king(bob := 0.0) -> void:
	var seat := 0.42 if mount != "" else 0.0
	_king.position = king_pos + Vector3(0, seat + bob, 0)
	_king.rotation.y = _king_facing
	if _mount_node != null:
		_mount_node.position = king_pos + Vector3(0, bob, 0)
		_mount_node.rotation.y = _king_facing
	if first_person:
		_fp.update_pose(king_pos, mount != "")

func _walk(delta: float) -> void:
	var move := joystick
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	if move.length() > 1.0:
		move = move.normalized()
	if move.length_squared() > 1e-4:
		# "up" walks the way the view faces: away from the isometric camera,
		# or straight ahead through the King's eyes
		var fwd: Vector3
		var right: Vector3
		if first_person:
			fwd = _fp.forward()
			right = _fp.right()
		else:
			fwd = -rig.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			right = rig.global_transform.basis.x
			right.y = 0.0
			right = right.normalized()
		var dir := (right * move.x - fwd * move.y).normalized()
		var step := dir * walk_speed() * delta
		var next := king_pos + step
		if _can_stand(next):
			king_pos = next
		elif _can_stand(Vector3(next.x, 0, king_pos.z)):
			king_pos.x = next.x
		elif _can_stand(Vector3(king_pos.x, 0, next.z)):
			king_pos.z = next.z
		# through his own eyes the King faces where he looks, not where he steps
		_king_facing = _fp.yaw if first_person else atan2(-dir.x, -dir.z)
		_place_king(absf(sin(Time.get_ticks_msec() * 0.014)) * 0.07)
	else:
		if first_person:
			_king_facing = _fp.yaw
		_place_king()
	if not first_person:
		rig.focus_on(king_pos)

## Land only, and never through a building (roads are fine to walk on).
func _can_stand(p: Vector3) -> bool:
	if not forest.on_land(p):
		return false
	var tile := Config.world_to_tile(p)
	var b := Game.building_at(tile.x, tile.y)
	if b.is_empty():
		return true
	return Config.BUILDINGS[b["type"]].get("flat", false)

func king_in_forest() -> bool:
	return forest.in_forest(king_pos)

## The Nivian ball: thrown at the nearest wild Nivian in reach. Whether it
## sticks depends on distance, and whether anyone can take the Nivian home
## is Game's call (the King fills his five first, then soldiers short of
## theirs).
func throw_ball() -> void:
	if not walk_mode or _ball != null:
		return
	var w := forest.nearest_wild(king_pos, Config.THROW_RANGE)
	if w.is_empty():
		Sfx.play("error")
		caught.emit("No wild Nivian in reach. Walk closer in the forest." if king_in_forest() else "The wild Nivians live in the forest, over the bridge to the east.", false)
		return
	var err := Game.catch_error(str(w["type"]))
	if err != "":
		Sfx.play("error")
		caught.emit(err, false)
		return
	var target: Vector3 = w["pos"]
	var dist: float = Vector2(target.x, target.z).distance_to(Vector2(king_pos.x, king_pos.z))
	_king_facing = atan2(-(target.x - king_pos.x), -(target.z - king_pos.z))
	var mb := MeshBuilder.new()
	mb.sphere(Vector3.ZERO, 0.17, Color("f4f4f0"), 8, 6)
	mb.box(Vector3(-0.19, -0.02, -0.19), Vector3(0.38, 0.04, 0.38), Color("d8452f"))
	_ball = MeshBuilder.instance(mb.commit())
	_ball.position = king_pos + Vector3(0, 0.8, 0)
	add_child(_ball)
	Sfx.play("deploy")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_ball, "position:x", target.x, 0.45)
	tw.tween_property(_ball, "position:z", target.z, 0.45)
	tw.tween_property(_ball, "position:y", 1.6, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_ball, "position:y", 0.3, 0.23).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: _ball_landed(w, dist))

func _ball_landed(w: Dictionary, dist: float) -> void:
	if _ball != null:
		_ball.queue_free()
		_ball = null
	var chance := Config.CATCH_CHANCE - clampf(dist / Config.THROW_RANGE, 0.0, 1.0) * 0.35
	var type := str(w["type"])
	if randf() < chance:
		forest.take(w)
		var who := Game.receive_nivian(type)
		Sfx.play("done")
		caught.emit("Caught a %s! It bonds with %s." % [Config.UNITS[type]["name"], who], true)
	else:
		forest.scare(w, king_pos)
		Sfx.play("error")
		caught.emit("The %s slipped out and bolted. Get closer and try again." % Config.UNITS[type]["name"], false)

static func _format_time(seconds: float) -> String:
	var s := int(ceil(maxf(seconds, 0.0)))
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return "%ds" % s

# ---------------------------------------------------------------- selection
func _make_marker(fill: Color, top: Color) -> MeshInstance3D:
	var b := MeshBuilder.new()
	b.rounded_slab(Vector3(0, 0.02, 0), Vector3(1, 0.02, 1), 0.18, 3, fill, top)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func select(b: Dictionary) -> void:
	if b.is_empty():
		clear_selection()
		return
	_selected_id = b["id"]
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	_selection.visible = true
	_selection.position = Config.building_origin(b["x"], b["y"], int(d["w"]), int(d["h"]))
	_selection.scale = Vector3(int(d["w"]) + 0.3, 1.0, int(d["h"]) + 0.3)

func clear_selection() -> void:
	_selected_id = 0
	_selection.visible = false

func selected_building() -> Dictionary:
	return Game.find_building(_selected_id) if _selected_id != 0 else {}

# ---------------------------------------------------------------- placing
func start_placing(type: String, move_id := 0) -> void:
	cancel_placing()
	rig.blocked = true
	if move_id == 0:
		var d: Dictionary = Config.BUILDINGS[type]
		if d.get("wall", false) or d.get("flat", false):
			_start_line(type)
			return
	_start_ghost(type, move_id)

func _start_ghost(type: String, move_id: int) -> void:
	_ghost_type = type
	_ghost_move_id = move_id
	_ghost = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Buildings.build(type)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.65)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(mi)
	var pad := MeshBuilder.new()
	var fp := Buildings.footprint(type)
	pad.rounded_slab(Vector3(0, 0.03, 0), Vector3(fp.x, 0.02, fp.y), 0.2, 3, Color.WHITE, Color.WHITE)
	var pad_mi := MeshInstance3D.new()
	pad_mi.name = "Pad"
	pad_mi.mesh = pad.commit()
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.4, 1, 0.5, 0.45)
	pad_mi.material_override = pm
	pad_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(pad_mi)
	add_child(_ghost)
	if move_id != 0:
		var b := Game.find_building(move_id)
		if not b.is_empty():
			move_ghost(Vector2i(b["x"], b["y"]))
			if _models.has(move_id):
				_models[move_id].visible = false
			return
	# drop it in the middle of what the player is looking at
	var focus := Config.world_to_tile(rig.position)
	var fp2 := Buildings.footprint(type)
	move_ghost(Vector2i(focus.x - fp2.x / 2, focus.y - fp2.y / 2))

func _start_line(type: String) -> void:
	_line_mode = true
	_line_type = type
	_line_has_last = false
	_line_marker.visible = false

func is_placing() -> bool:
	return _ghost != null or _line_mode

func is_line_mode() -> bool:
	return _line_mode

func placing_type() -> String:
	return _line_type if _line_mode else _ghost_type

func move_ghost(tile: Vector2i) -> void:
	if _ghost == null:
		return
	var fp := Buildings.footprint(_ghost_type)
	tile.x = clampi(tile.x, Config.BUILD_MIN, Config.BUILD_MAX - fp.x)
	tile.y = clampi(tile.y, Config.BUILD_MIN, Config.BUILD_MAX - fp.y)
	_ghost_tile = tile
	_ghost.position = Config.building_origin(tile.x, tile.y, fp.x, fp.y)
	var ok := Game.can_place(_ghost_type, tile.x, tile.y, _ghost_move_id)
	var pad: MeshInstance3D = _ghost.get_node("Pad")
	pad.material_override.albedo_color = Color(0.4, 1, 0.5, 0.45) if ok else Color(1, 0.3, 0.3, 0.5)
	placement_changed.emit(ok)

func ghost_tile() -> Vector2i:
	return _ghost_tile

func confirm_placing() -> String:
	if _ghost == null:
		return "Nothing to place."
	var tile := _ghost_tile
	if _ghost_move_id != 0:
		var b := Game.find_building(_ghost_move_id)
		if not Game.move_building(b, tile.x, tile.y):
			return "Cannot place there."
		cancel_placing()
		return ""
	var err := Game.build(_ghost_type, tile.x, tile.y)
	if err != "":
		return err
	cancel_placing()
	return ""

func cancel_placing() -> void:
	rig.blocked = false
	if _ghost_move_id != 0 and _models.has(_ghost_move_id):
		_models[_ghost_move_id].visible = true
	_ghost_move_id = 0
	_ghost_type = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_line_mode = false
	_line_type = ""
	_line_marker.visible = false

# ---------------------------------------------------------------- input
func _on_tapped(screen_pos: Vector2) -> void:
	# line mode places on press, not on tap-release; see _on_pressed
	if _line_mode:
		return
	if walk_mode:
		# a tap while walking throws at whatever is in reach
		throw_ball()
		return
	var world := rig.screen_to_ground(screen_pos)
	var tile := Config.world_to_tile(world)
	if is_placing():
		if tile == _ghost_tile:
			confirm_placing()
		else:
			move_ghost(Vector2i(tile.x - Buildings.footprint(_ghost_type).x / 2, tile.y - Buildings.footprint(_ghost_type).y / 2))
		return
	var b := Game.building_at(tile.x, tile.y)
	if b.is_empty():
		ground_tapped.emit(tile)
	else:
		building_tapped.emit(b)

## Line mode: the first tile of a new stroke, placed the instant you press down.
func _on_pressed(screen_pos: Vector2) -> void:
	if not _line_mode:
		return
	var tile := Config.world_to_tile(rig.screen_to_ground(screen_pos))
	_place_line_tile(tile)
	_line_last_tile = tile
	_line_has_last = true

## Line mode: every tile the drag crosses since the last one gets filled in,
## so a fast drag in any direction still lays an unbroken run. Ghost mode: the
## building just follows the finger, in whichever direction it goes.
func _on_drag_moved(screen_pos: Vector2) -> void:
	if not _line_mode:
		if _ghost != null:
			var t := Config.world_to_tile(rig.screen_to_ground(screen_pos))
			var fp := Buildings.footprint(_ghost_type)
			move_ghost(Vector2i(t.x - fp.x / 2, t.y - fp.y / 2))
		return
	var tile := Config.world_to_tile(rig.screen_to_ground(screen_pos))
	if not _line_has_last:
		_place_line_tile(tile)
		_line_last_tile = tile
		_line_has_last = true
		return
	if tile == _line_last_tile:
		_update_line_marker(tile)
		return
	for step in _tiles_between(_line_last_tile, tile):
		_place_line_tile(step)
	_line_last_tile = tile

func _place_line_tile(tile: Vector2i) -> void:
	_update_line_marker(tile)
	if Game.place_error(_line_type, tile.x, tile.y) != "":
		return
	if Game.build(_line_type, tile.x, tile.y) == "":
		Sfx.play("place", 1.0, 0.05)

func _update_line_marker(tile: Vector2i) -> void:
	_line_marker.visible = true
	_line_marker.position = Config.tile_to_world(tile.x, tile.y) + Vector3(0, 0.05, 0)
	var ok := Game.place_error(_line_type, tile.x, tile.y) == ""
	_line_marker.material_override.albedo_color = Color(0.4, 1, 0.5, 0.55) if ok else Color(1, 0.3, 0.3, 0.55)

## Every grid tile on the straight line from `a` (exclusive) to `b`
## (inclusive), so a quick drag never skips a tile between two mouse-motion
## events regardless of which way it runs.
static func _tiles_between(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	if maxi(absi(b.x - a.x), absi(b.y - a.y)) > LINE_STEP_LIMIT:
		out.append(b)
		return out
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	var guard := 0
	while (x != b.x or y != b.y) and guard < LINE_STEP_LIMIT:
		guard += 1
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
		out.append(Vector2i(x, y))
	return out
