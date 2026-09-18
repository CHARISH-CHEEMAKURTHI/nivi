class_name BattleState
extends RefCounted
## A raid on an enemy kingdom. Pure logic: no nodes, no rendering.
## Troops follow a small set of rules, as the design document asks -- pick a
## target, walk to it, break a wall if one is in the way, hit it until it falls
## -- and the player can override that at any moment.

const TILE_CENTER := 0.5

var kingdom: Dictionary
var buildings: Array = []
var units: Array = []
var projectiles: Array = []
var events: Array = []              ## things the view should react to this frame

var time_left := 0.0
var elapsed := 0.0
var started := false
var ended := false
var end_reason := ""

var available: Array = []           ## roster entries not yet deployed
var king_available := false
var king_deployed := false
var king_bonded: Array = []     ## the King's own Nivians; they land beside him
var selected_id := 0            ## a single already-committed unit, tapped for Hold/Proceed micromanagement
var selected_ids: Array = []    ## soldiers picked in the staging area, pending a squad command

var loot := {"serge": 0.0, "jade": 0.0}
var _loot_total := {}
var _loot_weights := 0.0
var _next_id := 1
var _empty_timer := 0.0
var _astar := AStarGrid2D.new()

func _init(kingdom_data: Dictionary, roster: Array, king_ready: bool, king_creatures: Array = []) -> void:
	kingdom = kingdom_data
	time_left = Config.BATTLE_TIME
	king_available = king_ready
	king_bonded = king_creatures.duplicate()
	for u in roster:
		available.append({"id": u["id"], "type": u["type"], "bonded": u.get("bonded", [])})
	_loot_total = kingdom["loot"].duplicate()
	buildings = _generate_base()
	for b in buildings:
		_loot_weights += float(Config.BUILDINGS[b["type"]].get("loot", 0.0))
	_rebuild_grid()

# ---------------------------------------------------------------- enemy base
func _generate_base() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(kingdom["seed"])
	var list: Array = []
	var mid := Config.BATTLE_GRID / 2

	var fits := func(type: String, tx: int, ty: int) -> bool:
		var d: Dictionary = Config.BUILDINGS[type]
		if tx < Config.BATTLE_BUILD_MIN or ty < Config.BATTLE_BUILD_MIN or tx + int(d["w"]) > Config.BATTLE_BUILD_MAX or ty + int(d["h"]) > Config.BATTLE_BUILD_MAX:
			return false
		for o in list:
			var od: Dictionary = Config.BUILDINGS[o["type"]]
			if tx < o["x"] + int(od["w"]) and tx + int(d["w"]) > o["x"] and ty < o["y"] + int(od["h"]) and ty + int(d["h"]) > o["y"]:
				return false
		return true

	var put := func(type: String, tx: int, ty: int) -> bool:
		if not fits.call(type, tx, ty):
			return false
		var d: Dictionary = Config.BUILDINGS[type]
		# The id comes from the list itself: a lambda captures plain values by
		# copy, so a counter declared outside would never actually advance and
		# every building would end up sharing one id.
		list.append({"id": list.size() + 1, "type": type, "x": tx, "y": ty,
			"hp": float(d["hp"]), "max_hp": float(d["hp"]), "cool": 0.0})
		return true

	put.call("castle", mid - 2, mid - 2)
	put.call("serge_storage", mid - 6, mid - 6)
	put.call("jade_storage", mid + 4, mid - 6)
	var cannon_spots := [[mid - 4, mid + 3], [mid + 2, mid + 3], [mid, mid - 6], [mid - 7, mid]]
	for i in int(kingdom["cannons"]):
		put.call("cannon", cannon_spots[i][0], cannon_spots[i][1])
	if not put.call("barracks_h", mid + 4, mid - 1):
		put.call("guard_station", mid + 5, mid - 1)
	put.call("guard_station", mid - 8, mid + 1)
	put.call("outpost", mid + 6, mid + 4)
	put.call("farm", mid - 2, mid + 7)

	# wall rings with a gate on each
	var rings := int(kingdom["wall_rings"])
	for r in rings:
		var pad := 6 + r * 3
		var x0 := mid - pad
		var x1 := mid + pad - 1
		var y0 := mid - pad
		var y1 := mid + pad - 1
		var gate_x := x0 + 2 + rng.randi() % maxi(1, (x1 - x0 - 3))
		var gate_y := y0 + 2 + rng.randi() % maxi(1, (y1 - y0 - 3))
		for x in range(x0, x1 + 1):
			if x != gate_x:
				put.call("wall", x, y0)
			if x != gate_x + 1:
				put.call("wall", x, y1)
		for y in range(y0 + 1, y1):
			if y != gate_y:
				put.call("wall", x0, y)
			if y != gate_y + 1:
				put.call("wall", x1, y)

	# mines and homes scattered outside the walls
	var outer := [[mid - 13, mid - 12], [mid + 10, mid - 12], [mid - 13, mid + 9], [mid + 10, mid + 9]]
	put.call("serge_mine", outer[0][0], outer[0][1])
	put.call("jade_mine", outer[1][0], outer[1][1])
	put.call("serge_mine", outer[2][0], outer[2][1])
	put.call("jade_mine", outer[3][0], outer[3][1])
	var placed := 0
	var tries := 0
	while placed < int(kingdom["homes"]) and tries < 300:
		tries += 1
		var hx := Config.BATTLE_BUILD_MIN + rng.randi() % (Config.BATTLE_BUILD_MAX - Config.BATTLE_BUILD_MIN - 2)
		var hy := Config.BATTLE_BUILD_MIN + rng.randi() % (Config.BATTLE_BUILD_MAX - Config.BATTLE_BUILD_MIN - 2)
		if absi(hx - mid) < 10 and absi(hy - mid) < 10:
			continue
		if put.call("home", hx, hy):
			placed += 1
	return list

# ---------------------------------------------------------------- pathfinding
func _rebuild_grid() -> void:
	_astar.region = Rect2i(0, 0, Config.BATTLE_GRID, Config.BATTLE_GRID)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in Config.BATTLE_GRID:
		for x in Config.BATTLE_GRID:
			_astar.set_point_solid(Vector2i(x, y), false)
			_astar.set_point_weight_scale(Vector2i(x, y), 1.0)
	for b in buildings:
		if b["hp"] <= 0.0:
			continue
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if d.get("passable", false):
			continue
		for j in int(d["h"]):
			for i in int(d["w"]):
				var p := Vector2i(b["x"] + i, b["y"] + j)
				if d.get("wall", false):
					# walls are crossable, but only by breaking them, so they cost a lot
					_astar.set_point_weight_scale(p, 24.0)
				else:
					_astar.set_point_solid(p, true)

func _ring_tiles(b: Dictionary) -> Array:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	var out := []
	for x in range(b["x"] - 1, b["x"] + int(d["w"]) + 1):
		for y in range(b["y"] - 1, b["y"] + int(d["h"]) + 1):
			var inside_x: bool = x >= b["x"] and x < b["x"] + int(d["w"])
			var inside_y: bool = y >= b["y"] and y < b["y"] + int(d["h"])
			if inside_x and inside_y:
				continue
			if not inside_x and not inside_y:
				continue      # corners are out of reach
			if x < 0 or y < 0 or x >= Config.BATTLE_GRID or y >= Config.BATTLE_GRID:
				continue
			if _astar.is_point_solid(Vector2i(x, y)):
				continue
			out.append(Vector2i(x, y))
	return out

func _path_to(from: Vector2, goals: Array) -> Array:
	if goals.is_empty():
		return []
	var start := Vector2i(clampi(int(from.x), 0, Config.BATTLE_GRID - 1), clampi(int(from.y), 0, Config.BATTLE_GRID - 1))
	var best: Array = []
	var best_len := 1e9
	for g in goals:
		var path := _astar.get_id_path(start, g)
		if path.is_empty():
			continue
		if path.size() < best_len:
			best_len = path.size()
			best = path
	return best

# ---------------------------------------------------------------- deployment
func available_counts() -> Dictionary:
	var c := {}
	for u in available:
		c[u["type"]] = int(c.get(u["type"], 0)) + 1
	return c

func can_deploy_at(tile: Vector2i) -> bool:
	if tile.x < 1 or tile.y < 1 or tile.x >= Config.BATTLE_GRID - 1 or tile.y >= Config.BATTLE_GRID - 1:
		return false
	for j in range(-1, 2):
		for i in range(-1, 2):
			var b := building_at(tile.x + i, tile.y + j)
			if not b.is_empty() and b["hp"] > 0.0:
				return false
	return true

## Two rows just inside the map edge, at y < BATTLE_BUILD_MIN, where no
## enemy building can ever be generated -- a standing area safely clear of
## the base where every deployed soldier (and their bonded Nivians) wait on
## a squad command instead of wandering in and fighting on their own.
func _staging_tile(index: int) -> Vector2i:
	var span: int = Config.BATTLE_GRID - 4
	return Vector2i(2 + (index % span), mini(index / span, Config.BATTLE_BUILD_MIN - 1))

func deploy(type: String, tile := Vector2i(-1, -1)) -> String:
	if ended:
		return "The raid is over."
	if type == "king":
		if not king_available or king_deployed:
			return "The King is not available."
		if not can_deploy_at(tile):
			return "Drop him clear of enemy buildings."
		king_deployed = true
		var king_id := _spawn_unit("king", tile, 0)
		# roster id -1 marks a Nivian as the King's own when it falls
		for creature_type in king_bonded:
			_spawn_unit(str(creature_type), tile, -1, king_id)
		started = true
		return ""
	var idx := -1
	for i in available.size():
		if available[i]["type"] == type:
			idx = i
			break
	if idx < 0:
		return "No more of those."
	var roster_id := int(available[idx]["id"])
	var bonded: Array = available[idx].get("bonded", [])
	available.remove_at(idx)
	var stage := _staging_tile(units.size())
	# A soldier and their bonded Nivians land together in the staging area and
	# hold there -- they never pick a fight on their own. They only move out,
	# together, once a squad command sends them at a building.
	var soldier_id := _spawn_unit(type, stage, roster_id, 0, "hold")
	for creature_type in bonded:
		_spawn_unit(str(creature_type), stage, roster_id, soldier_id, "hold")
	started = true
	return ""

func _spawn_unit(type: String, tile: Vector2i, roster_id: int, bonded_to := 0, directive := "auto") -> int:
	var d: Dictionary = Config.UNITS[type]
	var id := _next_id
	units.append({
		"id": id, "roster_id": roster_id, "type": type, "bonded_to": bonded_to,
		"pos": Vector2(tile.x + TILE_CENTER + randf_range(-0.3, 0.3), tile.y + TILE_CENTER + randf_range(-0.3, 0.3)),
		"hp": float(d["hp"]), "max_hp": float(d["hp"]), "cooldown": 0.0,
		"target_id": 0, "wall_id": 0, "path": [], "path_i": 0, "repath": 0.0,
		"directive": directive, "focus_id": 0, "move_to": Vector2i(-1, -1),
		"facing": 0.0, "dead": false, "attacking": false, "stuck_timer": 0.0, "stuck_anchor": Vector2.ZERO,
		"committed": directive != "hold",
	})
	_next_id += 1
	return id

# ---------------------------------------------------------------- squads
## Soldiers waiting in the staging area, grouped by type -- what the squad
## picker shows. Their bonded Nivians tag along automatically and never
## appear here on their own.
func staged_counts() -> Dictionary:
	var c := {}
	for u in units:
		if not u["dead"] and u["directive"] == "hold" and int(u.get("bonded_to", 0)) == 0 and u["type"] != "king":
			c[u["type"]] = int(c.get(u["type"], 0)) + 1
	return c

## Marks up to `count` staged soldiers of `type` for the next squad command,
## replacing any previous pick of that same type but keeping picks of other
## types, so e.g. Knights and Cavalry can be combined into one order. Passing
## 0 clears that type's pick. Returns how many were actually selected.
func select_squad(type: String, count: int) -> int:
	var kept: Array = []
	for id in selected_ids:
		var u := find_unit(id)
		if not u.is_empty() and u["type"] != type:
			kept.append(id)
	selected_ids = kept
	if count <= 0:
		return 0
	var picked := 0
	for u in units:
		if picked >= count:
			break
		if u["dead"] or u["directive"] != "hold" or int(u.get("bonded_to", 0)) != 0 or u["type"] != type:
			continue
		selected_ids.append(int(u["id"]))
		picked += 1
	return picked

func clear_selection() -> void:
	selected_ids.clear()

## How many of `type` are currently picked for the next squad command.
func selected_count(type: String) -> int:
	var n := 0
	for id in selected_ids:
		var u := find_unit(id)
		if not u.is_empty() and u["type"] == type:
			n += 1
	return n

## The squad command: everything currently picked (plus their bonded
## Nivians) marches on the named building together, and stays on it until it
## falls or a new order is given.
func order_attack(building_id: int) -> String:
	if selected_ids.is_empty():
		return "Pick some soldiers from the staging area first."
	var b := find_building(building_id)
	if b.is_empty() or b["hp"] <= 0.0:
		return "That building is already destroyed."
	for id in selected_ids:
		focus(building_id, int(id))
	selected_ids.clear()
	return ""

# ---------------------------------------------------------------- queries
func building_at(tx: int, ty: int) -> Dictionary:
	for b in buildings:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if tx >= b["x"] and tx < b["x"] + int(d["w"]) and ty >= b["y"] and ty < b["y"] + int(d["h"]):
			return b
	return {}

func find_building(id: int) -> Dictionary:
	for b in buildings:
		if b["id"] == id:
			return b
	return {}

func find_unit(id: int) -> Dictionary:
	for u in units:
		if u["id"] == id:
			return u
	return {}

func unit_near(world_xz: Vector2, radius := 0.8) -> Dictionary:
	var best := {}
	var best_d := radius
	for u in units:
		if u["dead"]:
			continue
		var d: float = u["pos"].distance_to(world_xz)
		if d < best_d:
			best_d = d
			best = u
	return best

## Angle a Node3D (whose forward is -Z by Godot convention) needs for its
## rotation.y so it visibly faces `dir`, given our world (x, z) is stored here
## as a Vector2(x, z). Facing math is easy to get backwards -- this is the one
## place it happens, so every caller goes through it.
static func _face(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)

func _center_of(b: Dictionary) -> Vector2:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	return Vector2(b["x"] + int(d["w"]) * 0.5, b["y"] + int(d["h"]) * 0.5)

func _distance_to(b: Dictionary, p: Vector2) -> float:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	var x0 := float(b["x"])
	var y0 := float(b["y"])
	var x1 := x0 + int(d["w"])
	var y1 := y0 + int(d["h"])
	var dx: float = maxf(maxf(x0 - p.x, 0.0), p.x - x1)
	var dy: float = maxf(maxf(y0 - p.y, 0.0), p.y - y1)
	return sqrt(dx * dx + dy * dy)

func alive_buildings(filter := "") -> Array:
	var out := []
	for b in buildings:
		if b["hp"] <= 0.0:
			continue
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if d.get("passable", false):
			continue
		match filter:
			"non_wall":
				if d.get("wall", false):
					continue
			"defense":
				if b["type"] != "cannon":
					continue
			"resource":
				if not d.has("loot"):
					continue
		out.append(b)
	return out

func countable() -> Array:
	var out := []
	for b in buildings:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if d.get("wall", false) or d.get("passable", false):
			continue
		out.append(b)
	return out

func destruction() -> float:
	var all := countable()
	if all.is_empty():
		return 0.0
	var down := 0
	for b in all:
		if b["hp"] <= 0.0:
			down += 1
	return float(down) / float(all.size())

func castle_down() -> bool:
	for b in buildings:
		if b["type"] == "castle":
			return b["hp"] <= 0.0
	return true

func stars() -> int:
	var s := 0
	var d := destruction()
	if d >= 0.5:
		s += 1
	if castle_down():
		s += 1
	if d >= 1.0:
		s += 1
	return s

# ---------------------------------------------------------------- orders
## A command targeted at a soldier also reaches their bonded Nivians, so they
## answer the same order together rather than fighting on their own.
func _matches_order(u: Dictionary, unit_id: int) -> bool:
	if unit_id == 0:
		return true
	if u["id"] == unit_id:
		return true
	return int(u.get("bonded_to", 0)) == unit_id

func focus(building_id: int, unit_id := 0) -> void:
	for u in units:
		if u["dead"]:
			continue
		if not _matches_order(u, unit_id):
			continue
		u["directive"] = "focus"
		u["focus_id"] = building_id
		u["target_id"] = 0
		u["wall_id"] = 0
		u["path"] = []
		u["committed"] = true
		u["repath"] = 0.0

func hold(unit_id := 0) -> void:
	for u in units:
		if u["dead"]:
			continue
		if not _matches_order(u, unit_id):
			continue
		u["directive"] = "hold"
		u["path"] = []

## Resumes a unit paused mid-fight with Hold. Never sends a soldier straight
## from the staging area into an unordered auto-attack -- only a unit that
## has already been given a squad command (focus) responds to Proceed.
func proceed(unit_id := 0) -> void:
	for u in units:
		if u["dead"] or not u.get("committed", false):
			continue
		if not _matches_order(u, unit_id):
			continue
		u["directive"] = "auto"
		u["focus_id"] = 0
		u["target_id"] = 0
		u["path"] = []
		u["repath"] = 0.0

func move_to(tile: Vector2i, unit_id: int) -> void:
	var u := find_unit(unit_id)
	if u.is_empty() or u["dead"]:
		return
	if tile.x < 0 or tile.y < 0 or tile.x >= Config.BATTLE_GRID or tile.y >= Config.BATTLE_GRID:
		return
	if _astar.is_point_solid(tile):
		return
	for other in units:
		if not other["dead"] and _matches_order(other, unit_id):
			other["directive"] = "move"
			other["move_to"] = tile
			other["target_id"] = 0
			other["wall_id"] = 0
			other["path"] = _path_to(other["pos"], [tile])
			other["path_i"] = 0

# ---------------------------------------------------------------- simulation
func update(dt: float) -> void:
	if ended:
		return
	events.clear()
	if started:
		time_left -= dt
		elapsed += dt
	for u in units:
		if not u["dead"]:
			_update_unit(u, dt)
	_separate()
	for b in buildings:
		if b["type"] == "cannon" and b["hp"] > 0.0:
			_update_cannon(b, dt)
	_update_projectiles(dt)

	if time_left <= 0.0:
		_end("Time is up.")
	elif destruction() >= 1.0:
		_end("Total victory. The kingdom lies in ruins.")
	elif started and available.is_empty() and (not king_available or king_deployed):
		var any_alive := false
		for u in units:
			if not u["dead"]:
				any_alive = true
				break
		if not any_alive:
			_empty_timer += dt
			if _empty_timer > 1.5:
				_end("Your army has fallen.")

func _end(reason: String) -> void:
	ended = true
	end_reason = reason

func _choose_target(u: Dictionary) -> Dictionary:
	var d: Dictionary = Config.UNITS[u["type"]]
	if u["directive"] == "focus" and u["focus_id"] != 0:
		var f := find_building(int(u["focus_id"]))
		if not f.is_empty() and f["hp"] > 0.0:
			return f
		u["directive"] = "auto"
		u["focus_id"] = 0
	var pool := alive_buildings("non_wall")
	if pool.is_empty():
		var any := alive_buildings()
		return any[0] if not any.is_empty() else {}
	var prefer := str(d.get("prefer", "any"))
	if prefer != "any":
		var liked := alive_buildings(prefer)
		if not liked.is_empty():
			pool = liked
	var best := {}
	var best_d := 1e9
	for b in pool:
		var dist := _distance_to(b, u["pos"])
		if dist < best_d:
			best_d = dist
			best = b
	return best

func _update_unit(u: Dictionary, dt: float) -> void:
	var d: Dictionary = Config.UNITS[u["type"]]
	u["cooldown"] = maxf(0.0, u["cooldown"] - dt)
	u["repath"] -= dt
	u["attacking"] = false

	var wall := find_building(int(u["wall_id"])) if u["wall_id"] != 0 else {}
	if not wall.is_empty() and wall["hp"] <= 0.0:
		u["wall_id"] = 0
		u["path"] = []
		wall = {}
	var target := find_building(int(u["target_id"])) if u["target_id"] != 0 else {}
	if not target.is_empty() and target["hp"] <= 0.0:
		u["target_id"] = 0
		u["path"] = []
		target = {}
	# A unit still holding in the staging area (or freshly told to hold) never
	# picks a target on its own -- it stands there until a squad command sends
	# it in. Only "auto" (mopping up after its focus target fell) and "focus"
	# pick a target for themselves; "move" and "hold" never do.
	if u["directive"] != "move" and u["directive"] != "hold" and target.is_empty():
		target = _choose_target(u)
		if target.is_empty():
			return
		u["target_id"] = target["id"]
		u["path"] = []

	var hitting: Dictionary = wall if not wall.is_empty() else ({} if u["directive"] == "move" else target)
	if not hitting.is_empty() and _distance_to(hitting, u["pos"]) <= float(d["range"]) + 0.35:
		u["attacking"] = true
		u["stuck_timer"] = 0.0
		u["stuck_anchor"] = u["pos"]
		var c := _center_of(hitting)
		u["facing"] = _face(c - u["pos"])
		if u["cooldown"] <= 0.0:
			u["cooldown"] = float(d["rate"])
			if float(d["range"]) > 1.2:
				projectiles.append({"kind": str(d.get("element", "water")), "pos": u["pos"], "height": 0.6,
					"target_building": int(hitting["id"]), "target_unit": 0, "speed": 9.0, "damage": float(d["atk"])})
			else:
				events.append({"kind": "melee", "pos": u["pos"]})
				_damage_building(hitting, float(d["atk"]))
		return
	if u["directive"] == "hold":
		u["stuck_timer"] = 0.0
		u["stuck_anchor"] = u["pos"]
		return

	# Jam recovery: two units can end up nose to nose in a gateway or a narrow
	# gap, each trying to occupy the tile the other is standing on. Nothing
	# routes around a live unit (only buildings are obstacles to the
	# pathfinder), so without this they push against each other forever. If a
	# unit has made almost no progress for a little while, it steps to one
	# side -- consistently, by id parity, so a symmetric face-off actually
	# resolves instead of both units picking the same side -- and re-plans.
	u["stuck_timer"] = float(u.get("stuck_timer", 0.0)) + dt
	if u["stuck_timer"] >= 0.6:
		var anchor: Vector2 = u.get("stuck_anchor", u["pos"])
		var moved: float = u["pos"].distance_to(anchor)
		u["stuck_timer"] = 0.0
		u["stuck_anchor"] = u["pos"]
		if moved < 0.2:
			var aim: Vector2 = u["pos"] + Vector2(1, 0)
			if not target.is_empty():
				aim = _center_of(target)
			var dir: Vector2 = aim - u["pos"]
			if dir.length() < 0.01:
				dir = Vector2(1, 0)
			dir = dir.normalized()
			var side := 1.0 if (int(u["id"]) % 2 == 0) else -1.0
			u["pos"] += Vector2(-dir.y, dir.x) * side * 0.55
			u["path"] = []
			u["path_i"] = 0
			u["repath"] = 0.0

	# walk
	if u["path"].is_empty() and u["repath"] <= 0.0:
		u["repath"] = 1.2
		if u["directive"] == "move":
			u["path"] = _path_to(u["pos"], [u["move_to"]])
		else:
			u["path"] = _path_to(u["pos"], _ring_tiles(target))
		u["path_i"] = 0
		if u["path"].is_empty():
			u["target_id"] = 0
			return
	if u["path"].is_empty() or u["path_i"] >= u["path"].size():
		# Walked the whole path without arriving: drop it and work out a new one
		# on the next tick rather than standing still forever.
		if u["directive"] == "move":
			u["directive"] = "auto"
			u["move_to"] = Vector2i(-1, -1)
		u["path"] = []
		u["path_i"] = 0
		u["repath"] = minf(u["repath"], 0.0)
		return
	var node: Vector2i = u["path"][u["path_i"]]
	# a wall across the path has to come down first
	var blocker := building_at(node.x, node.y)
	if not blocker.is_empty() and blocker["hp"] > 0.0 and Config.BUILDINGS[blocker["type"]].get("wall", false) and u["directive"] != "move":
		u["wall_id"] = blocker["id"]
		return
	var goal := Vector2(node.x + TILE_CENTER, node.y + TILE_CENTER)
	var delta: Vector2 = goal - u["pos"]
	var dist: float = delta.length()
	var step := float(d["speed"]) * dt
	if dist <= step:
		u["pos"] = goal
		u["path_i"] += 1
	else:
		u["pos"] += delta / dist * step
	if dist > 0.001:
		u["facing"] = _face(delta)

## Nudge troops apart so they do not pile onto one pixel.
func _separate() -> void:
	for i in units.size():
		var a: Dictionary = units[i]
		if a["dead"]:
			continue
		for j in range(i + 1, units.size()):
			var b: Dictionary = units[j]
			if b["dead"]:
				continue
			var delta: Vector2 = b["pos"] - a["pos"]
			var d := delta.length()
			if d >= 0.42:
				continue
			if d < 0.001:
				delta = Vector2(randf() - 0.5, randf() - 0.5)
				d = delta.length()
			var push := delta / d * 0.03
			a["pos"] -= push
			b["pos"] += push

func _update_cannon(b: Dictionary, dt: float) -> void:
	var def: Dictionary = Config.BUILDINGS["cannon"]["defense"]
	b["cool"] = maxf(0.0, float(b["cool"]) - dt)
	var c := _center_of(b)
	var best := {}
	var best_d := float(def["range"])
	for u in units:
		if u["dead"]:
			continue
		var dist := c.distance_to(u["pos"])
		if dist < best_d:
			best_d = dist
			best = u
	b["aim"] = int(best["id"]) if not best.is_empty() else 0
	if best.is_empty() or b["cool"] > 0.0:
		return
	b["cool"] = float(def["rate"])
	projectiles.append({"kind": "cannon", "pos": c, "height": 0.8,
		"target_building": 0, "target_unit": int(best["id"]), "speed": 14.0, "damage": float(def["damage"])})
	events.append({"kind": "muzzle", "pos": c})

func _update_projectiles(dt: float) -> void:
	var keep := []
	for p in projectiles:
		var goal: Vector2
		if p["target_unit"] != 0:
			var tu := find_unit(int(p["target_unit"]))
			if tu.is_empty() or tu["dead"]:
				continue
			goal = tu["pos"]
		else:
			var tb := find_building(int(p["target_building"]))
			if tb.is_empty() or tb["hp"] <= 0.0:
				continue
			goal = _center_of(tb)
		var delta: Vector2 = goal - p["pos"]
		var dist: float = delta.length()
		var step := float(p["speed"]) * dt
		if dist <= step:
			if p["target_unit"] != 0:
				_damage_unit(find_unit(int(p["target_unit"])), float(p["damage"]))
			else:
				_damage_building(find_building(int(p["target_building"])), float(p["damage"]))
			events.append({"kind": "hit", "pos": goal, "type": p["kind"]})
		else:
			p["pos"] += delta / dist * step
			keep.append(p)
	projectiles = keep

func _damage_building(b: Dictionary, amount: float) -> void:
	if b.is_empty() or b["hp"] <= 0.0:
		return
	b["hp"] -= amount
	if b["hp"] > 0.0:
		return
	b["hp"] = 0.0
	events.append({"kind": "destroyed", "id": int(b["id"])})
	var weight := float(Config.BUILDINGS[b["type"]].get("loot", 0.0))
	if weight > 0.0 and _loot_weights > 0.0:
		for k in _loot_total:
			loot[k] += round(float(_loot_total[k]) * weight / _loot_weights)
	_rebuild_grid()
	for u in units:
		if u["target_id"] == b["id"] or u["wall_id"] == b["id"]:
			u["path"] = []
			u["repath"] = 0.0
			if u["wall_id"] == b["id"]:
				u["wall_id"] = 0
			if u["target_id"] == b["id"]:
				u["target_id"] = 0

func _damage_unit(u: Dictionary, amount: float) -> void:
	if u.is_empty() or u["dead"]:
		return
	var d: Dictionary = Config.UNITS[u["type"]]
	u["hp"] -= amount * (1.0 - float(d.get("armor", 0.0)))
	if u["hp"] > 0.0:
		return
	u["hp"] = 0.0
	u["dead"] = true
	if selected_id == u["id"]:
		selected_id = 0
	events.append({"kind": "fell", "id": int(u["id"]), "pos": u["pos"]})

func result() -> Dictionary:
	var fallen := []
	var survivors := 0
	for u in units:
		if u["dead"]:
			fallen.append({"id": u["roster_id"], "type": u["type"]})
		else:
			survivors += 1
	return {
		"enemy_name": kingdom["name"], "stars": stars(), "destruction": destruction(),
		"loot": {"serge": loot["serge"], "jade": loot["jade"]},
		"fallen": fallen, "survivors": survivors, "reason": end_reason,
	}
