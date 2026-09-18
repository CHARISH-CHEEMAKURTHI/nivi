class_name Forest
extends Node3D
## The wild wood off the home island's east coast, joined to it by a plank
## bridge. Wild Nivians wander its meadow; the King walks over and throws a
## Nivian ball to catch one, and a soldier who lost theirs in a raid makes the
## same trip off-screen. Nothing here touches the save: caught Nivians are
## handed to Game, and the forest simply grows another one after a while.

var center := Vector3.ZERO
var half := 0.0                    ## grass half-extent of the forest island

var _wild: Array = []              ## {type, node, pos, target, wait, flee, from}
var _respawn: Array = []           ## seconds until each replacement appears
var _rng := RandomNumberGenerator.new()
var _bob_seed := 0

func _ready() -> void:
	_rng.seed = 7
	center = Config.forest_center()
	half = Config.FOREST_GRID * 0.5 + 3.0
	var island := Island.new()
	island.grid_size = Config.FOREST_GRID
	island.seed_value = 7
	island.sea = false
	island.forest = true
	island.position = center
	add_child(island)
	_build_bridge()
	for i in Config.WILD_NIVIANS:
		_spawn_wild()

## The plank bridge along z = 0, from the home island's grass edge to the
## forest's, with posts and a rail down each side.
func _build_bridge() -> void:
	var b := MeshBuilder.new()
	var x0: float = Config.GRID * 0.5 + 3.0 - 1.2
	var x1: float = center.x - half + 1.2
	var n := int(ceil((x1 - x0) / 0.62))
	for i in n:
		var px := x0 + i * 0.62 + 0.31
		b.box(Vector3(px, 0.0, 0), Vector3(0.58, 0.14, 3.2), Palette.WOOD if i % 2 == 0 else Palette.WOOD_LIGHT)
	for sz in [-1.5, 1.5]:
		b.box(Vector3((x0 + x1) * 0.5, -0.12, sz), Vector3(x1 - x0, 0.16, 0.22), Palette.WOOD_DARK)
		b.box(Vector3((x0 + x1) * 0.5, 0.86, sz), Vector3(x1 - x0, 0.08, 0.1), Palette.WOOD_DARK)
		var x := x0 + 0.4
		while x < x1:
			b.box(Vector3(x, 0.0, sz), Vector3(0.14, 0.94, 0.14), Palette.WOOD_DARK)
			x += 3.0
	# pilings down into the water
	var x2 := x0 + 1.5
	while x2 < x1:
		for sz2 in [-1.2, 1.2]:
			b.cylinder(Vector3(x2, -1.4, sz2), 0.13, 0.13, 1.4, Palette.WOOD_DARK, 6)
		x2 += 3.0
	add_child(MeshBuilder.instance(b.commit()))

# ---------------------------------------------------------------- walkable ground
## Whether a point on the ground is land the King can stand on: the home
## island, the bridge, or the forest island.
func on_land(p: Vector3) -> bool:
	var home_half: float = Config.GRID * 0.5 + 3.0
	if absf(p.x) <= home_half and absf(p.z) <= home_half:
		return true
	if p.x >= home_half - 1.5 and p.x <= center.x - half + 1.5 and absf(p.z) <= 1.4:
		return true
	return absf(p.x - center.x) <= half and absf(p.z - center.z) <= half

func in_forest(p: Vector3) -> bool:
	return absf(p.x - center.x) <= half and absf(p.z - center.z) <= half

# ---------------------------------------------------------------- wild Nivians
func _random_spot() -> Vector3:
	var r := half - 2.5
	return center + Vector3(_rng.randf_range(-r, r), 0.0, _rng.randf_range(-r, r))

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
