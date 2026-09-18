extends Node
## The kingdom: state, the clock that advances it, and saving.
## Buildings, citizens and units are plain dictionaries so the whole thing
## serialises to JSON without ceremony.

signal resources_changed
signal buildings_changed
signal army_changed
signal logged(message: String)

var state: Dictionary = {}

func _ready() -> void:
	if not load_game():
		new_game()

# ---------------------------------------------------------------- lifecycle
func new_game() -> void:
	state = {
		"version": Config.SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"resources": {"serge": 600.0, "jade": 600.0},
		"credits": 0,
		"happiness_mod": 0.0,
		"decree_cooldowns": {},
		"buildings": [],
		"citizens": [],
		"army": [],
		"queues": {"barracks_h": []},
		"king": {"status": "ready", "heal_remaining": 0.0, "bonded": []},
		"next_id": 1,
		"time": 0.0,
		"season": 1,
		"season_timer": 0.0,
		"growth_timer": 0.0,
		"stats": {"battles": 0, "wins": 0, "stars": 0, "looted_serge": 0, "looted_jade": 0,
			"soldiers_lost": 0, "born": 0, "died": 0},
		"log": [],
	}
	var mid := Config.GRID / 2
	add_building("castle", mid - 2, mid - 2, true)
	add_building("serge_mine", mid - 7, mid + 1, true)
	add_building("jade_mine", mid + 5, mid + 1, true)
	add_building("home", mid - 4, mid + 6, true)
	add_building("home", mid + 2, mid + 6, true)
	for i in 5:
		add_citizen(18 + i * 6)
	# The King starts bonded to two Nivians, and can grow to a maximum of five.
	state["king"]["bonded"] = ["unitone", "garuan"]
	train("knight")
	assign_professions()
	log_line("Welcome, my liege. Your kingdom awaits its first orders.")

func log_line(msg: String) -> void:
	var entries: Array = state["log"]
	entries.push_front({"t": state["time"], "msg": msg})
	if entries.size() > 30:
		entries.resize(30)
	logged.emit(msg)

func next_id() -> int:
	var n: int = state["next_id"]
	state["next_id"] = n + 1
	return n

func add_building(type: String, tx: int, ty: int, done := false) -> Dictionary:
	var d: Dictionary = Config.BUILDINGS[type]
	var b := {
		"id": next_id(), "type": type, "x": tx, "y": ty, "level": 1,
		"build_remaining": 0.0 if done else float(d["time"]), "stored": 0.0,
	}
	state["buildings"].append(b)
	buildings_changed.emit()
	return b

func add_citizen(age := -1) -> Dictionary:
	var bonded: Array[String] = [Config.CREATURES.keys()[randi() % Config.CREATURES.keys().size()]]
	if randf() < Config.RARE_SECOND_CREATURE_CHANCE:
		bonded.append(Config.CREATURES.keys()[randi() % Config.CREATURES.keys().size()])
	var c := {
		"id": next_id(),
		"name": Config.NAMES[randi() % Config.NAMES.size()],
		"age": age if age > 0 else 16 + randi() % 20,
		"profession": "Citizen",
		"bonded": bonded,
	}
	state["citizens"].append(c)
	return c

## Enlisting a citizen as a soldier bonds them to exactly two Nivians, who
## only fight alongside their soldier when that soldier is sent into battle.
func add_unit(type: String, citizen_id := 0, bonded: Array[String] = []) -> Dictionary:
	var u := {"id": next_id(), "type": type, "status": "ready", "heal_remaining": 0.0, "citizen_id": citizen_id, "bonded": bonded}
	state["army"].append(u)
	army_changed.emit()
	return u

# ---------------------------------------------------------------- queries
func buildings() -> Array:
	return state["buildings"]

func find_building(id: int) -> Dictionary:
	for b in state["buildings"]:
		if b["id"] == id:
			return b
	return {}

func is_built(b: Dictionary) -> bool:
	return b["build_remaining"] <= 0.0

func count_type(type: String) -> int:
	var n := 0
	for b in state["buildings"]:
		if b["type"] == type:
			n += 1
	return n

func has_built(type: String) -> bool:
	for b in state["buildings"]:
		if b["type"] == type and is_built(b):
			return true
	return false

func building_at(tx: int, ty: int) -> Dictionary:
	for b in state["buildings"]:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if tx >= b["x"] and tx < b["x"] + int(d["w"]) and ty >= b["y"] and ty < b["y"] + int(d["h"]):
			return b
	return {}

func can_place(type: String, tx: int, ty: int, ignore_id := 0) -> bool:
	var d: Dictionary = Config.BUILDINGS[type]
	var w := int(d["w"])
	var h := int(d["h"])
	if tx < Config.BUILD_MIN or ty < Config.BUILD_MIN or tx + w > Config.BUILD_MAX or ty + h > Config.BUILD_MAX:
		return false
	for b in state["buildings"]:
		if b["id"] == ignore_id:
			continue
		var o: Dictionary = Config.BUILDINGS[b["type"]]
		if tx < b["x"] + int(o["w"]) and tx + w > b["x"] and ty < b["y"] + int(o["h"]) and ty + h > b["y"]:
			return false
	return true

## Everything the finished buildings provide, totalled up.
func capacities() -> Dictionary:
	var cap := {"storage": {"serge": 0.0, "jade": 0.0}, "pop_cap": 0, "housing": 0,
		"housing_cavalry": 0, "happiness": 0.0, "heal_speed": 1.0, "hospital": false}
	for b in state["buildings"]:
		if not is_built(b):
			continue
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if not d.has("provides"):
			continue
		var p: Dictionary = d["provides"]
		if p.has("storage"):
			for k in p["storage"]:
				cap["storage"][k] += float(p["storage"][k])
		if p.has("pop_cap"):
			cap["pop_cap"] += int(p["pop_cap"])
		if p.has("housing"):
			if p.get("housing_for", "") == "cavalry":
				cap["housing_cavalry"] += int(p["housing"])
			else:
				cap["housing"] += int(p["housing"])
		if p.has("happiness"):
			cap["happiness"] += float(p["happiness"])
		if p.has("heal_speed"):
			cap["heal_speed"] = maxf(cap["heal_speed"], float(p["heal_speed"]))
			cap["hospital"] = true
	return cap

func happiness() -> int:
	var cap := capacities()
	var h := 50.0 + minf(cap["happiness"], 40.0)
	h -= maxf(0.0, state["citizens"].size() - cap["pop_cap"]) * 6.0
	h += state["happiness_mod"]
	h += clampf(state["credits"] / 4.0, -10.0, 10.0)
	return int(round(clampf(h, 0.0, 100.0)))

func production_multiplier() -> float:
	return 0.6 + happiness() / 100.0 * 0.8

func housing_used(pool: String) -> int:
	var want_cavalry := pool == "cavalry"
	var used := 0
	var types: Array[String] = []
	for u in state["army"]:
		types.append(str(u["type"]))
	for key in state["queues"]:
		for item in state["queues"][key]:
			types.append(str(item["type"]))
	for type in types:
		if (type == "cavalry") == want_cavalry:
			used += int(Config.UNITS[type]["housing"])
	return used

func army_summary() -> Dictionary:
	var cap := capacities()
	var ready := 0
	var injured := 0
	for u in state["army"]:
		if u["status"] == "ready":
			ready += 1
		else:
			injured += 1
	return {
		"housing": housing_used("army"), "housing_cap": cap["housing"],
		"cavalry": housing_used("cavalry"), "cavalry_cap": cap["housing_cavalry"],
		"ready": ready, "injured": injured,
	}

func ready_units() -> Array:
	var out := []
	for u in state["army"]:
		if u["status"] == "ready":
			out.append(u)
	return out

# ---------------------------------------------------------------- resources
func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if state["resources"][k] < float(cost[k]):
			return false
	return true

func spend(cost: Dictionary) -> void:
	for k in cost:
		state["resources"][k] -= float(cost[k])
	resources_changed.emit()

func add_resources(delta: Dictionary) -> Dictionary:
	var cap: Dictionary = capacities()["storage"]
	var gained := {}
	for k in delta:
		var before: float = state["resources"][k]
		state["resources"][k] = minf(cap[k], before + float(delta[k]))
		gained[k] = state["resources"][k] - before
	resources_changed.emit()
	return gained

func collect(b: Dictionary) -> float:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	if not d.has("produces") or b["stored"] < 1.0:
		return 0.0
	var res: String = d["produces"]["resource"]
	var got := add_resources({res: floor(b["stored"])})
	b["stored"] -= got[res]
	return got[res]

func collect_all() -> Dictionary:
	var total := {"serge": 0.0, "jade": 0.0}
	for b in state["buildings"]:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if d.has("produces") and is_built(b):
			total[d["produces"]["resource"]] += collect(b)
	return total

# ---------------------------------------------------------------- building
func place_error(type: String, tx: int, ty: int) -> String:
	var d: Dictionary = Config.BUILDINGS[type]
	if d.get("buildable", true) == false:
		return "That cannot be built."
	if count_type(type) >= int(d["limit"]):
		return "Limit reached for %s at Castle Level One." % d["name"]
	if not can_afford(d.get("cost", {})):
		return "Not enough resources."
	if not can_place(type, tx, ty):
		return "Cannot place there."
	return ""

func build(type: String, tx: int, ty: int) -> String:
	var err := place_error(type, tx, ty)
	if err != "":
		return err
	var d: Dictionary = Config.BUILDINGS[type]
	spend(d.get("cost", {}))
	add_building(type, tx, ty, float(d["time"]) <= 0.0)
	if float(d["time"]) > 0.0:
		log_line("Construction of %s has begun." % d["name"])
	assign_professions()
	return ""

func move_building(b: Dictionary, tx: int, ty: int) -> bool:
	if not can_place(b["type"], tx, ty, b["id"]):
		return false
	b["x"] = tx
	b["y"] = ty
	buildings_changed.emit()
	return true

func remove_building(b: Dictionary) -> bool:
	if b["type"] == "castle":
		return false
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	var refund := {}
	for k in d.get("cost", {}):
		refund[k] = floor(float(d["cost"][k]) * 0.5)
	state["buildings"].erase(b)
	add_resources(refund)
	assign_professions()
	log_line("%s demolished. Half its cost was recovered." % d["name"])
	buildings_changed.emit()
	return true

# ---------------------------------------------------------------- training
func train_error(type: String) -> String:
	if not Config.UNITS.has(type) or Config.UNITS[type].get("hidden", false):
		return "Unknown unit."
	var u: Dictionary = Config.UNITS[type]
	var barracks: String = u["barracks"]
	if not has_built(barracks):
		return "Requires a finished %s." % Config.BUILDINGS[barracks]["name"]
	if state["army"].size() >= Config.MAX_SOLDIERS:
		return "You already command %d soldiers, the most Castle Level One allows." % Config.MAX_SOLDIERS
	if not can_afford(u["cost"]):
		return "Not enough resources."
	var cap := capacities()
	if type == "cavalry":
		if housing_used("cavalry") + int(u["housing"]) > cap["housing_cavalry"]:
			return "No room. Build a Cavalry Outpost."
	elif housing_used("army") + int(u["housing"]) > cap["housing"]:
		return "No room. Build Guard Stations or Outposts."
	if _free_citizen().is_empty():
		return "No citizens left to enlist. Build Homes and let the population grow."
	if state["queues"][barracks].size() >= 8:
		return "That training queue is full."
	return ""

func _free_citizen() -> Dictionary:
	for c in state["citizens"]:
		if c["profession"] != "Soldier":
			return c
	return {}

func train(type: String) -> String:
	var err := train_error(type)
	if err != "":
		return err
	var u: Dictionary = Config.UNITS[type]
	spend(u["cost"])
	# Enlisting turns a civilian into a soldier and bonds them to two Nivians,
	# who fight only when this soldier is sent into battle.
	var c := _free_citizen()
	c["profession"] = "Soldier"
	var bonded: Array[String] = []
	var kin: Array = Config.CREATURES.keys()
	for i in Config.BONDED_PER_SOLDIER:
		bonded.append(kin[randi() % kin.size()])
	var item := {"type": type, "remaining": float(u["time"]), "citizen_id": c["id"], "bonded": bonded}
	state["queues"][u["barracks"]].append(item)
	army_changed.emit()
	return ""

func cancel_training(barracks: String, index: int) -> void:
	var q: Array = state["queues"][barracks]
	if index < 0 or index >= q.size():
		return
	var item: Dictionary = q[index]
	q.remove_at(index)
	add_resources(Config.UNITS[item["type"]]["cost"])
	if item["citizen_id"] != 0:
		for c in state["citizens"]:
			if c["id"] == item["citizen_id"]:
				c["profession"] = "Citizen"
	assign_professions()
	army_changed.emit()

## Give civilians a job based on the support buildings that exist.
func assign_professions() -> void:
	var jobs: Array[String] = []
	for b in state["buildings"]:
		if not is_built(b):
			continue
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if d.has("provides") and d["provides"].has("profession"):
			jobs.append(str(d["provides"]["profession"]))
		if d.has("produces"):
			jobs.append("Miner")
	var i := 0
	for c in state["citizens"]:
		if c["profession"] == "Soldier":
			continue
		c["profession"] = jobs[i] if i < jobs.size() else "Citizen"
		i += 1

func decree(id: String) -> String:
	var d: Dictionary = Config.DECREES[id]
	if float(state["decree_cooldowns"].get(id, 0.0)) > 0.0:
		return "Not yet. The people need time."
	if d.has("cost"):
		if not can_afford(d["cost"]):
			return "Not enough resources."
		spend(d["cost"])
	if d.has("gain"):
		add_resources(d["gain"])
	state["happiness_mod"] += float(d["happiness"])
	state["credits"] = clampi(state["credits"] + int(d["credits"]), -100, 100)
	state["decree_cooldowns"][id] = float(d["cooldown"])
	log_line("The people celebrate. Your standing grows." if id == "festival" else "Taxes were raised. The people grumble.")
	return ""

# ---------------------------------------------------------------- the clock
func advance(delta: float) -> void:
	# Large jumps (offline progress) are applied in one-second slices so the
	# timers inside behave exactly as they would in real time.
	var left := delta
	while left > 0.0:
		_tick(minf(left, 1.0))
		left -= 1.0

func _tick(dt: float) -> void:
	state["time"] += dt
	var cap := capacities()
	var mult := production_multiplier()
	var dirty := false

	for b in state["buildings"]:
		var d: Dictionary = Config.BUILDINGS[b["type"]]
		if b["build_remaining"] > 0.0:
			b["build_remaining"] -= dt
			if b["build_remaining"] <= 0.0:
				b["build_remaining"] = 0.0
				log_line("%s is complete." % d["name"])
				Sfx.play("done")
				dirty = true
				buildings_changed.emit()
			continue
		if d.has("produces"):
			b["stored"] = minf(float(d["produces"]["capacity"]), b["stored"] + float(d["produces"]["per_second"]) * mult * dt)

	for barracks in state["queues"]:
		var q: Array = state["queues"][barracks]
		if q.is_empty() or not has_built(barracks):
			continue
		var item: Dictionary = q[0]
		item["remaining"] -= dt
		if item["remaining"] <= 0.0:
			q.remove_at(0)
			add_unit(item["type"], item["citizen_id"], item.get("bonded", []))
			log_line("%s has finished training." % Config.UNITS[item["type"]]["name"])
			Sfx.play("train")

	for u in state["army"]:
		if u["status"] == "injured":
			u["heal_remaining"] -= dt * cap["heal_speed"]
			if u["heal_remaining"] <= 0.0:
				u["status"] = "ready"
				u["heal_remaining"] = 0.0
				army_changed.emit()
	var king: Dictionary = state["king"]
	if king["status"] == "injured":
		king["heal_remaining"] -= dt * cap["heal_speed"]
		if king["heal_remaining"] <= 0.0:
			king["status"] = "ready"

	for k in state["decree_cooldowns"]:
		state["decree_cooldowns"][k] = maxf(0.0, float(state["decree_cooldowns"][k]) - dt)
	if state["happiness_mod"] > 0.0:
		state["happiness_mod"] = maxf(0.0, state["happiness_mod"] - dt * 0.25)
	elif state["happiness_mod"] < 0.0:
		state["happiness_mod"] = minf(0.0, state["happiness_mod"] + dt * 0.25)

	# population growth
	var hap := happiness()
	if state["citizens"].size() < cap["pop_cap"] and hap >= 35:
		state["growth_timer"] += dt * (0.5 + hap / 100.0)
		if state["growth_timer"] >= 20.0:
			state["growth_timer"] = 0.0
			var c := add_citizen(16)
			state["stats"]["born"] += 1
			log_line("%s came of age and joined the kingdom." % c["name"])
			dirty = true

	# seasons: ageing and natural death
	state["season_timer"] += dt
	if state["season_timer"] >= Config.SEASON_SECONDS:
		state["season_timer"] -= Config.SEASON_SECONDS
		state["season"] += 1
		var gone := []
		for c in state["citizens"]:
			c["age"] += 1
			if c["age"] >= 70 and randf() < 0.08 + (c["age"] - 70) * 0.02:
				gone.append(c)
		for c in gone:
			state["citizens"].erase(c)
			state["stats"]["died"] += 1
			log_line("%s passed away peacefully at %d." % [c["name"], c["age"]])
			for u in state["army"]:
				if u["citizen_id"] == c["id"]:
					state["army"].erase(u)
					army_changed.emit()
					break
		if not gone.is_empty():
			dirty = true

	if dirty:
		assign_professions()

# ---------------------------------------------------------------- after a raid
func apply_battle_result(result: Dictionary) -> Dictionary:
	var stats: Dictionary = state["stats"]
	stats["battles"] += 1
	if int(result["stars"]) > 0:
		stats["wins"] += 1
	stats["stars"] += int(result["stars"])
	var got := add_resources(result["loot"])
	stats["looted_serge"] += int(got.get("serge", 0))
	stats["looted_jade"] += int(got.get("jade", 0))

	var cap := capacities()
	var base_heal := 45.0 if cap["hospital"] else 150.0
	var outcome := {"dead": [], "injured": []}
	for fallen in result["fallen"]:
		if fallen["type"] == "king":
			state["king"]["status"] = "injured"
			state["king"]["heal_remaining"] = 60.0
			continue
		var unit := {}
		for u in state["army"]:
			if u["id"] == int(fallen["id"]):
				unit = u
				break
		if unit.is_empty():
			continue
		var is_human: bool = Config.UNITS[unit["type"]]["kind"] == "human"
		# Soldier death is permanent (design document, section 13).
		if is_human and randf() < 0.4:
			state["army"].erase(unit)
			if unit["citizen_id"] != 0:
				for c in state["citizens"]:
					if c["id"] == unit["citizen_id"]:
						state["citizens"].erase(c)
						break
			stats["soldiers_lost"] += 1
			outcome["dead"].append(unit)
		else:
			unit["status"] = "injured"
			unit["heal_remaining"] = base_heal * (1.0 if is_human else 0.7)
			outcome["injured"].append(unit)

	var delta := (2 if int(result["stars"]) >= 2 else 0) - (1 if not outcome["dead"].is_empty() else 0)
	state["credits"] = clampi(state["credits"] + delta, -100, 100)
	log_line("Raid on %s: %d star(s), %d%% destroyed." % [result["enemy_name"], int(result["stars"]), int(round(float(result["destruction"]) * 100.0))])
	assign_professions()
	army_changed.emit()
	return outcome

# ---------------------------------------------------------------- saving
func save_game() -> bool:
	state["saved_at"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(Config.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(state))
	f.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(Config.SAVE_PATH):
		return false
	var f := FileAccess.open(Config.SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != Config.SAVE_VERSION:
		return false
	state = data
	var away := clampf(Time.get_unix_time_from_system() - float(state.get("saved_at", 0.0)), 0.0, Config.OFFLINE_CAP)
	if away > 5.0:
		advance(away)
		log_line("You were away for %d minute(s). The mines kept working." % int(away / 60.0))
	return true

func wipe_save() -> void:
	if FileAccess.file_exists(Config.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Config.SAVE_PATH))
