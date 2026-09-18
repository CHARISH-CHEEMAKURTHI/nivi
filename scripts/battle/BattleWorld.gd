class_name BattleWorld
extends Node3D
## The raid, drawn: the enemy island, its buildings, your troops moving across
## it, cannon fire and the wreckage left behind.

signal tapped_building(building: Dictionary)
signal tapped_ground(tile: Vector2i)
signal tapped_unit(unit: Dictionary)

var state: BattleState
var rig: CameraRig
var deploy_type := ""

var _building_nodes: Dictionary = {}
var _unit_nodes: Dictionary = {}
var _shot_nodes: Array = []
var _deploy_hint: MeshInstance3D
var _selection: MeshInstance3D
var _shot_mesh: Dictionary = {}

func setup(battle: BattleState) -> void:
	state = battle
	add_child(WorldEnv.make_environment())
	add_child(WorldEnv.make_sun())
	var island := Island.new()
	island.seed_value = int(state.kingdom["seed"])
	add_child(island)
	rig = CameraRig.new()
	rig.bounds = Config.GRID * 0.5 + 2.0
	add_child(rig)
	rig.tapped.connect(_on_tapped)
	rig.set_zoom(46.0)

	for b in state.buildings:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		var node := MeshBuilder.instance(Buildings.build(b["type"]))
		node.position = Config.building_origin(b["x"], b["y"], int(d["w"]), int(d["h"]))
		add_child(node)
		_building_nodes[b["id"]] = node

	_selection = _ring(Color(0.45, 1.0, 0.6, 0.85))
	add_child(_selection)
	_selection.visible = false
	_deploy_hint = _ring(Color(1.0, 0.95, 0.5, 0.7))
	add_child(_deploy_hint)
	_deploy_hint.visible = false

	for kind in ["cannon", "fire", "water", "normal"]:
		var mb := MeshBuilder.new()
		var col: Color = Palette.IRON_DARK
		if kind == "fire":
			col = Color("ff7a3c")
		elif kind == "water":
			col = Color("4fa8ff")
		elif kind == "normal":
			col = Color("ffe08a")
		mb.sphere(Vector3.ZERO, 0.14, col, 7, 5)
		_shot_mesh[kind] = mb.commit()

func _ring(col: Color) -> MeshInstance3D:
	var b := MeshBuilder.new()
	b.rounded_slab(Vector3(0, 0.03, 0), Vector3(1, 0.02, 1), 0.2, 3, col, col)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func tile_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x - Config.GRID * 0.5, 0.0, p.y - Config.GRID * 0.5)

func _process(delta: float) -> void:
	if state == null or state.ended:
		return
	state.update(delta)
	_sync_units()
	_sync_shots()
	for e in state.events:
		_play_event(e)

func _sync_units() -> void:
	for u in state.units:
		var id: int = u["id"]
		if u["dead"]:
			if _unit_nodes.has(id):
				_fall(_unit_nodes[id])
				_unit_nodes.erase(id)
			continue
		if not _unit_nodes.has(id):
			var node := MeshBuilder.instance(Troops.build(u["type"]))
			add_child(node)
			_unit_nodes[id] = node
		var n: Node3D = _unit_nodes[id]
		n.position = tile_to_world(u["pos"])
		n.rotation.y = u["facing"]
		# a small bob while walking so they do not look like they are gliding
		if not u["attacking"]:
			n.position.y = absf(sin(Time.get_ticks_msec() * 0.011 + id)) * 0.055
	if state.selected_id != 0:
		var sel := state.find_unit(state.selected_id)
		if sel.is_empty() or sel["dead"]:
			_selection.visible = false
		else:
			_selection.visible = true
			_selection.position = tile_to_world(sel["pos"]) + Vector3(0, 0.01, 0)
			_selection.scale = Vector3(0.9, 1, 0.9)
	else:
		_selection.visible = false

func _sync_shots() -> void:
	for n in _shot_nodes:
		n.queue_free()
	_shot_nodes.clear()
	for p in state.projectiles:
		var mi := MeshInstance3D.new()
		mi.mesh = _shot_mesh.get(p["kind"], _shot_mesh["cannon"])
		mi.material_override = MeshBuilder.material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = tile_to_world(p["pos"]) + Vector3(0, float(p["height"]), 0)
		add_child(mi)
		_shot_nodes.append(mi)

func _play_event(e: Dictionary) -> void:
	match e["kind"]:
		"destroyed":
			var id: int = e["id"]
			if not _building_nodes.has(id):
				return
			var node: Node3D = _building_nodes[id]
			var b := state.find_building(id)
			var d: Dictionary = Config.BUILDINGS[b["type"]]
			node.queue_free()
			var rubble := MeshBuilder.new()
			var rng := RandomNumberGenerator.new()
			rng.seed = id * 7
			for i in int(d["w"]) * int(d["h"]) * 3:
				var px := rng.randf_range(-0.4, 0.4) * int(d["w"])
				var pz := rng.randf_range(-0.4, 0.4) * int(d["h"])
				rubble.box(Vector3(px, 0, pz), Vector3(rng.randf_range(0.16, 0.34), rng.randf_range(0.08, 0.2), rng.randf_range(0.16, 0.34)),
					Palette.ROCK_DARK if i % 2 == 0 else Palette.DIRT_DARK, rng.randf() * TAU)
			var wreck := MeshBuilder.instance(rubble.commit())
			wreck.position = Config.building_origin(b["x"], b["y"], int(d["w"]), int(d["h"]))
			add_child(wreck)
			_building_nodes[id] = wreck
			_puff(wreck.position + Vector3(0, 0.4, 0))
		"hit":
			_spark(tile_to_world(e["pos"]) + Vector3(0, 0.5, 0), e.get("type", "cannon"))
		"muzzle":
			_spark(tile_to_world(e["pos"]) + Vector3(0, 0.8, 0), "cannon")
		"fell":
			pass

func _puff(at: Vector3) -> void:
	var b := MeshBuilder.new()
	for i in 5:
		var a := TAU * i / 5.0
		b.sphere(Vector3(cos(a) * 0.3, sin(i) * 0.1, sin(a) * 0.3), 0.32, Color(0.55, 0.5, 0.45), 6, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.75)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.2, 2.2, 2.2), 0.9)
	tw.tween_property(mi, "position", at + Vector3(0, 0.9, 0), 0.9)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(mi.queue_free)

func _spark(at: Vector3, kind: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _shot_mesh.get(kind, _shot_mesh["cannon"])
	mi.material_override = MeshBuilder.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(2.6, 2.6, 2.6), 0.16)
	tw.tween_callback(mi.queue_free)

func _fall(node: Node3D) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "rotation:x", -PI * 0.5, 0.35)
	tw.tween_property(node, "position:y", -0.25, 0.5)
	tw.tween_property(node, "scale", Vector3(0.9, 0.05, 0.9), 0.6).set_delay(0.3)
	tw.chain().tween_callback(node.queue_free)

func show_deploy_hint(show_it: bool) -> void:
	_deploy_hint.visible = show_it

func _unhandled_input(event: InputEvent) -> void:
	if deploy_type == "" or not (event is InputEventMouseMotion):
		return
	var world := rig.screen_to_ground((event as InputEventMouseMotion).position)
	var tile := Config.world_to_tile(world)
	_deploy_hint.visible = true
	_deploy_hint.position = Config.tile_to_world(tile.x, tile.y)
	var ok := state.can_deploy_at(tile)
	_deploy_hint.material_override.albedo_color = Color(0.5, 1, 0.6, 0.6) if ok else Color(1, 0.35, 0.35, 0.6)

func _on_tapped(screen_pos: Vector2) -> void:
	if state == null or state.ended:
		return
	var world := rig.screen_to_ground(screen_pos)
	var tile := Config.world_to_tile(world)
	var xz := Vector2(world.x + Config.GRID * 0.5, world.z + Config.GRID * 0.5)
	var unit := state.unit_near(xz)
	if not unit.is_empty() and deploy_type == "":
		tapped_unit.emit(unit)
		return
	var b := state.building_at(tile.x, tile.y)
	if not b.is_empty() and b["hp"] > 0.0:
		tapped_building.emit(b)
		return
	tapped_ground.emit(tile)
