class_name Forest
extends Node3D
## The wild wood just south of the kingdom, inside the same ring of
## mountains, joined to it by a dirt lane. Wild Nivians wander its meadow;
## the King walks down and throws a Nivian ball to catch one, and a soldier
## who lost theirs in a raid makes the same trip off-screen. Nothing here
## touches the save: caught Nivians are handed to Game, and the forest simply
## grows another one after a while.

var center := Vector3.ZERO
var half := Vector2.ZERO           ## half-extents of the forest plot

var _wild: Array = []              ## {type, node, pos, target, wait, flee, from}
var _respawn: Array = []           ## seconds until each replacement appears
var _rng := RandomNumberGenerator.new()
var _bob_seed := 0

func _ready() -> void:
	_rng.seed = 7
	center = Config.forest_center()
	half = Vector2(Config.FOREST_GRID * 0.5 + 3.0, Config.FOREST_GRID * 0.5 + 3.0)
	var plot := Island.new()
	plot.grid_size = Config.FOREST_GRID
	plot.seed_value = 7
	plot.forest = true
	plot.position = center
	add_child(plot)
	_build_lane()
	for i in Config.WILD_NIVIANS:
		_spawn_wild()

## A dirt lane from the kingdom's south edge down into the wood, so the way
## in reads on the map.
func _build_lane() -> void:
	var b := MeshBuilder.new()
	var z0: float = Config.GRID * 0.5 + 1.0
	var z1: float = center.z - half.y + 8.0
	b.rounded_slab(Vector3(0, 0.02, (z0 + z1) * 0.5), Vector3(3.0, 0.04, z1 - z0), 0.8, 3, Palette.DIRT, Palette.DIRT)
	for i in 6:
		var z := z0 + 1.0 + i * (z1 - z0 - 2.0) / 5.0
		b.sphere(Vector3(1.9, 0.06, z), 0.22, Palette.ROCK_DARK, 5, 3, 0.6)
		b.sphere(Vector3(-1.9, 0.06, z + 0.9), 0.2, Palette.ROCK, 5, 3, 0.6)
	add_child(MeshBuilder.instance(b.commit()))

# ---------------------------------------------------------------- walkable ground
## Whether a point on the ground is inside the valley: everything within the
## ring of mountains, kingdom and forest alike.
func on_land(p: Vector3) -> bool:
	return Config.land_rect().has_point(Vector2(p.x, p.z))

func in_forest(p: Vector3) -> bool:
	return absf(p.x - center.x) <= half.x and absf(p.z - center.z) <= half.y

# ---------------------------------------------------------------- wild Nivians
func _random_spot() -> Vector3:
	return center + Vector3(_rng.randf_range(-half.x + 2.5, half.x - 2.5), 0.0, _rng.randf_range(-half.y + 2.5, half.y - 2.5))

func _spawn_wild() -> void:
	var kinds: Array = Config.CREATURES.keys()
	var type: String = kinds[_rng.randi() % kinds.size()]
	var node := MeshBuilder.instance(Troops.build(type))
	add_child(node)
	var pos := _random_spot()
	node.position = pos
	_bob_seed += 1
	_wild.append({"type": type, "node": node, "pos": pos, "target": _random_spot(),
		"wait": _rng.randf_range(0.5, 2.5), "flee": 0.0, "from": Vector3.ZERO, "seed": _bob_seed})

func wild_count() -> int:
	return _wild.size()

## The nearest wild Nivian within `range` of a point, or an empty dictionary.
func nearest_wild(from: Vector3, range: float) -> Dictionary:
	var best := {}
	var best_d := range
	for w in _wild:
		var d: float = Vector2(w["pos"].x, w["pos"].z).distance_to(Vector2(from.x, from.z))
		if d < best_d:
			best_d = d
			best = w
	return best

## Removes a caught Nivian from the wood and schedules its replacement.
func take(w: Dictionary) -> void:
	if not _wild.has(w):
		return
	_wild.erase(w)
	(w["node"] as Node3D).queue_free()
	_respawn.append(Config.WILD_RESPAWN_SECONDS)

## A missed throw sends the Nivian bolting away from the thrower for a bit.
func scare(w: Dictionary, from: Vector3) -> void:
	w["flee"] = 2.6
	w["from"] = from
	w["wait"] = 0.0

func _process(delta: float) -> void:
	for i in range(_respawn.size() - 1, -1, -1):
		_respawn[i] -= delta
		if _respawn[i] <= 0.0:
			_respawn.remove_at(i)
			_spawn_wild()
	var t := Time.get_ticks_msec() * 0.001
	for w in _wild:
		var node: Node3D = w["node"]
		var pos: Vector3 = w["pos"]
		var speed := 0.8 + float(Config.CREATURES[w["type"]]["speed"]) * 0.45
		var moving := false
		var dir := Vector3.ZERO
		if w["flee"] > 0.0:
			w["flee"] -= delta
			dir = pos - w["from"]
			dir.y = 0.0
			if dir.length_squared() < 1e-4:
				dir = Vector3(1, 0, 0)
			dir = dir.normalized()
			var next := pos + dir * speed * 2.4 * delta
			if in_forest(next):
				pos = next
				moving = true
			else:
				w["flee"] = 0.0
				w["target"] = _random_spot()
		elif w["wait"] > 0.0:
			w["wait"] -= delta
		else:
			var to: Vector3 = w["target"] - pos
			to.y = 0.0
			if to.length() < 0.3:
				w["wait"] = _rng.randf_range(0.8, 3.2)
				w["target"] = _random_spot()
			else:
				dir = to.normalized()
				pos += dir * speed * delta
				moving = true
		w["pos"] = pos
		node.position = pos
		if moving:
			# Node3D faces -Z, so the yaw that points a model along `dir` is
			# atan2(-x, -z) -- the same rule the troops use in a raid.
			node.rotation.y = atan2(-dir.x, -dir.z)
			node.position.y = absf(sin(t * 7.0 + float(w["seed"]))) * 0.06
