class_name Townsfolk
extends Node3D
## The citizens out and about, each with their bonded Nivian trailing behind.
## They keep to the roads: a figure walks a random route from road tile to
## road tile and never steps onto the grass, so laying roads is what opens the
## town up to them. Without any road they wait in the square before the
## Castle. Soldiers are stationed indoors and do not appear. Only the King
## may roam wherever he likes.

const WALK_SPEED := 1.55
const FOLLOW_GAP := 0.75

var _folk: Array = []              ## {cid, node, pos, tile, from, target, wait, dir, followers, seed}
var _roads: Dictionary = {}        ## Vector2i -> true
var _rng := RandomNumberGenerator.new()
var _sync_timer := 0.0

func _ready() -> void:
	_rng.seed = 11
	Game.buildings_changed.connect(_rebuild_roads)
	_rebuild_roads()
	_sync()

## True while the point sits on a road tile (or in the Castle square when
## there are no roads yet).
func on_road(p: Vector3) -> bool:
	if _roads.is_empty():
		return true
	return _roads.has(Config.world_to_tile(p))

func count() -> int:
	return _folk.size()

func _rebuild_roads() -> void:
	_roads.clear()
	for b in Game.buildings():
		if b["type"] == "road" and Game.is_built(b):
			_roads[Vector2i(b["x"], b["y"])] = true
	for f in _folk:
		if not _roads.is_empty() and not _roads.has(f["tile"]):
			_settle(f)
		elif _roads.is_empty():
			_settle(f)

## The square in front of the Castle gate, where townsfolk gather when there
## is no road to walk.
func _square_spot(index: int) -> Vector3:
	for b in Game.buildings():
		if b["type"] == "castle":
			var d: Dictionary = Config.BUILDINGS["castle"]
			var gate := Config.tile_to_world(b["x"] + int(d["w"]) / 2, b["y"] + int(d["h"]) + 1)
			return gate + Vector3(float(index % 5) - 2.0, 0.0, float(index / 5) * 0.9) * 1.1
	return Vector3.ZERO

func _random_road() -> Vector2i:
	var keys := _roads.keys()
	return keys[_rng.randi() % keys.size()]

## Puts a figure somewhere legal: a random road tile, or their spot in the
## square when there are no roads.
func _settle(f: Dictionary) -> void:
	if _roads.is_empty():
		f["tile"] = Vector2i(-1, -1)
		f["pos"] = _square_spot(int(f["seed"]))
	else:
		f["tile"] = _random_road()
		f["pos"] = Config.tile_to_world(f["tile"].x, f["tile"].y)
	f["target"] = f["pos"]
	f["from"] = f["tile"]
	f["wait"] = _rng.randf_range(0.2, 1.5)
	(f["node"] as Node3D).position = f["pos"]
	for fl in f["followers"]:
		fl["pos"] = f["pos"] + Vector3(_rng.randf_range(-0.4, 0.4), 0, 0.6)
		(fl["node"] as Node3D).position = fl["pos"]

func _sync() -> void:
	var want := {}
	for c in Game.state["citizens"]:
		if c["profession"] != "Soldier":
			want[int(c["id"])] = c
	for i in range(_folk.size() - 1, -1, -1):
		var f: Dictionary = _folk[i]
		if not want.has(f["cid"]):
			(f["node"] as Node3D).queue_free()
			for fl in f["followers"]:
				(fl["node"] as Node3D).queue_free()
			_folk.remove_at(i)
		else:
			want.erase(f["cid"])
	for cid in want:
		var c: Dictionary = want[cid]
		var node := MeshBuilder.instance(Troops.citizen(cid))
		add_child(node)
		var followers: Array = []
		for kind in c.get("bonded", []):
			var fn := MeshBuilder.instance(Troops.build(str(kind)))
			add_child(fn)
			followers.append({"type": kind, "node": fn, "pos": Vector3.ZERO})
		var f := {"cid": cid, "node": node, "pos": Vector3.ZERO, "tile": Vector2i(-1, -1), "from": Vector2i(-1, -1),
			"target": Vector3.ZERO, "wait": 0.0, "dir": Vector3(0, 0, -1), "followers": followers, "seed": _folk.size()}
		_folk.append(f)
		_settle(f)

func _next_tile(f: Dictionary) -> Vector2i:
	var here: Vector2i = f["tile"]
	var options: Array = []
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = here + step
		if _roads.has(t):
			options.append(t)
	if options.is_empty():
		return here
	# prefer not to turn straight back the way they came
	if options.size() > 1 and options.has(f["from"]):
		options.erase(f["from"])
	return options[_rng.randi() % options.size()]

func _process(delta: float) -> void:
	_sync_timer += delta
	if _sync_timer >= 1.0:
		_sync_timer = 0.0
		_sync()
	var t := Time.get_ticks_msec() * 0.001
	for f in _folk:
		var node: Node3D = f["node"]
		var moving := false
		if _roads.is_empty():
			node.position = f["pos"]
		elif f["wait"] > 0.0:
			f["wait"] -= delta
			node.position = f["pos"]
		else:
			var to: Vector3 = f["target"] - f["pos"]
			to.y = 0.0
			if to.length() < 0.06:
				f["pos"] = f["target"]
				var nxt := _next_tile(f)
				if nxt == f["tile"]:
					f["wait"] = _rng.randf_range(0.6, 2.0)
				else:
					f["from"] = f["tile"]
					f["tile"] = nxt
					f["target"] = Config.tile_to_world(nxt.x, nxt.y)
					if _rng.randf() < 0.18:
						f["wait"] = _rng.randf_range(0.4, 1.6)
			else:
				var dir := to.normalized()
				var step := minf(WALK_SPEED * delta, to.length())
				f["pos"] += dir * step
				f["dir"] = dir
				moving = true
			node.position = f["pos"]
			if moving:
				node.rotation.y = atan2(-f["dir"].x, -f["dir"].z)
				node.position.y = absf(sin(t * 8.0 + float(f["seed"]))) * 0.05
		# bonded Nivians trail behind in a short line
		var behind: Vector3 = f["pos"]
		for k in f["followers"].size():
			var fl: Dictionary = f["followers"][k]
			var want: Vector3 = behind - f["dir"] * FOLLOW_GAP
			var gap: Vector3 = want - fl["pos"]
			gap.y = 0.0
			if gap.length() > 0.05:
				var mv := gap.normalized() * minf(WALK_SPEED * 1.25 * delta, gap.length())
				fl["pos"] += mv
				(fl["node"] as Node3D).rotation.y = atan2(-gap.x, -gap.z)
				(fl["node"] as Node3D).position = fl["pos"] + Vector3(0, absf(sin(t * 8.0 + k)) * 0.05, 0)
			else:
				(fl["node"] as Node3D).position = fl["pos"]
			behind = fl["pos"]
