class_name BaseWorld
extends Node3D
## The player's kingdom in 3D: keeps a model in sync with every building in the
## save, handles tapping to select, and runs the drag-to-place build mode.

signal building_tapped(building: Dictionary)
signal ground_tapped(tile: Vector2i)
signal placement_changed(valid: bool)

var island: Island
var rig: CameraRig

var _models: Dictionary = {}          ## building id -> Node3D
var _ghost: Node3D = null
var _ghost_type := ""
var _ghost_tile := Vector2i.ZERO
var _ghost_move_id := 0
var _selection: MeshInstance3D = null
var _selected_id := 0
var _tile_marker: MeshInstance3D = null

func _ready() -> void:
	add_child(WorldEnv.make_environment())
	add_child(WorldEnv.make_sun())
	island = Island.new()
	add_child(island)
	rig = CameraRig.new()
	rig.bounds = Config.GRID * 0.5 + 2.0
	add_child(rig)
	rig.tapped.connect(_on_tapped)
	_selection = _make_selection_marker()
	add_child(_selection)
	_selection.visible = false
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
		"barracks_h", "barracks_l", "tavern", "hospital": return 2.1
		"wall", "road": return 1.2
		_: return 1.7

func _process(_delta: float) -> void:
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

static func _format_time(seconds: float) -> String:
	var s := int(ceil(maxf(seconds, 0.0)))
	if s >= 60:
		return "%d:%02d" % [s / 60, s % 60]
	return "%ds" % s

# ---------------------------------------------------------------- selection
func _make_selection_marker() -> MeshInstance3D:
	var b := MeshBuilder.new()
	b.rounded_slab(Vector3(0, 0.02, 0), Vector3(1, 0.02, 1), 0.18, 3, Color(0.4, 1.0, 0.6, 1), Color(0.6, 1.0, 0.75, 1))
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

func is_placing() -> bool:
	return _ghost != null

func placing_type() -> String:
	return _ghost_type

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
	var type := _ghost_type
	cancel_placing()
	# walls and roads are laid in runs, so stay in build mode when affordable
	var d: Dictionary = Config.BUILDINGS[type]
	if (d.get("wall", false) or d.get("flat", false)) and Game.place_error(type, tile.x, tile.y + 1) == "":
		start_placing(type)
		move_ghost(Vector2i(tile.x, tile.y + 1))
	return ""

func cancel_placing() -> void:
	if _ghost_move_id != 0 and _models.has(_ghost_move_id):
		_models[_ghost_move_id].visible = true
	_ghost_move_id = 0
	_ghost_type = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null

# ---------------------------------------------------------------- input
func _on_tapped(screen_pos: Vector2) -> void:
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

## Drag support while in build mode: the ghost follows the finger.
func _unhandled_input(event: InputEvent) -> void:
	if not is_placing():
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		var world := rig.screen_to_ground((event as InputEventMouseMotion).position)
		var tile := Config.world_to_tile(world)
		var fp := Buildings.footprint(_ghost_type)
		move_ghost(Vector2i(tile.x - fp.x / 2, tile.y - fp.y / 2))
		get_viewport().set_input_as_handled()
