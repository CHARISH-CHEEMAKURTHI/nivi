extends Node
## Development helper. Run the game with
##   godot --path . -- --capture=user://shot.png --after=40 [--scene=battle]
## to render a few frames headlessly-ish and save a screenshot. Used to review
## the art without a desktop. Does nothing during normal play.

var _target := ""
var _after := 40
var _frames := 0
var _demo := ""
var _demo_done := false
var _wall_shot_pending := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_target = a.substr(10)
		elif a.begins_with("--after="):
			_after = int(a.substr(8))
		elif a.begins_with("--demo="):
			_demo = a.substr(7)
	set_process(_target != "" or _demo != "")

func _process(_delta: float) -> void:
	_frames += 1
	if _demo != "" and not _demo_done and _frames == maxi(8, _after - 60):
		_demo_done = true
		_run_demo()
	if _wall_shot_pending and _frames == _after - 10:
		_wall_shot_pending = false
		_draw_wall_run()
	if _target == "" or _frames < _after:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_target)
	print("[capture] wrote ", _target)
	get_tree().quit()

## Development helper: drive the game to a given screen so it can be reviewed.
func _run_demo() -> void:
	var main := get_tree().current_scene
	if main == null:
		return
	match _demo:
		"jam":
			_run_jam_test()
		"squad":
			_run_squad_test()
		"catch":
			await _run_catch_test()
		"view":
			await _run_view_test()
		"fp":
			main._on_walk(true)
			main._on_first_person(true)
			main.world._fp.yaw = 2.6
		"forest":
			main._on_walk(true)
			main.world.king_pos = main.world.forest.center + Vector3(-4, 0, 2)
			main.world.rig.set_zoom(26.0)
		"verify":
			await _run_verify()
		"econ":
			_run_econ()
		"audio":
			_dump_audio()
		"audiocheck":
			_check_audio()
		"raidmusic":
			_check_raid_music()
		"sim":
			_simulate_raid()
		"build":
			main.hud.show_build("resource")
		"buildcore":
			main.hud.show_build("core")
		"army":
			Game.state["resources"]["serge"] = 4000.0
			Game.state["resources"]["jade"] = 4000.0
			# finish each construction before starting the next, so this demo
			# is not limited by how many builders a fresh kingdom has
			for spec in [["barracks_h", 14, 12], ["guard_station", 14, 24], ["cavalry_outpost", 21, 24]]:
				Game.build(str(spec[0]), int(spec[1]), int(spec[2]))
				for b in Game.buildings():
					b["build_remaining"] = 0.0
			Game.train("knight")
			Game.train("cavalry")
			main.hud.show_army()
		"kingdom":
			main.hud.show_kingdom()
		"info":
			var castle := {}
			for b in Game.buildings():
				if b["type"] == "castle":
					castle = b
			main.world.select(castle)
			main.hud.show_building(castle)
		"place":
			main._on_request_build("cannon")
			main.world.move_ghost(Vector2i(24, 22))
		"zoomout":
			main.world.rig.set_zoom(200.0)
		"wallshot":
			Game.state["resources"]["serge"] = 100000.0
			Game.state["resources"]["jade"] = 100000.0
			main._on_request_build("wall")
			main.world.rig.set_zoom(30.0)
			main.world.rig.focus_on(Config.tile_to_world(20, 40))
			_wall_shot_pending = true
		"attack":
			main.hud.show_attack()
		"menu":
			main.hud.show_menu()
		"battle":
			var kin: Array = Config.CREATURES.keys()
			var soldier_types := ["knight", "knight", "cavalry", "cavalry"]
			for i in soldier_types.size():
				var bonded: Array[String] = [kin[i % kin.size()], kin[(i + 1) % kin.size()]]
				Game.add_unit(soldier_types[i], 0, bonded)
			main._on_attack("greywater")
			var b: BattleState = main.battle
			for u in b.available.duplicate():
				b.deploy(u["type"])
			b.select_squad("knight", 99)
			b.select_squad("cavalry", 99)
			var castle := {}
			for bld in b.buildings:
				if bld["type"] == "castle":
					castle = bld
			if not castle.is_empty():
				b.order_attack(int(castle["id"]))
			b.deploy("king", Vector2i(6, 18))
			# run the raid fast so a capture can show the fight, not the march
			Engine.time_scale = 7.0

## Headless check: run a raid to its end and report what happened.
func _simulate_raid() -> void:
	var kingdom: Dictionary = Config.ENEMY_KINGDOMS[1]
	var roster := []
	var soldier_types := ["knight", "knight", "knight", "cavalry", "cavalry"]
	var kin: Array = Config.CREATURES.keys()
	for i in soldier_types.size():
		var bonded: Array[String] = [kin[i % kin.size()], kin[(i + 1) % kin.size()]]
		roster.append({"id": i + 1, "type": soldier_types[i], "bonded": bonded})
	var b := BattleState.new(kingdom, roster, true)
	for u in roster:
		var e := b.deploy(u["type"])
		if e != "":
			print("[sim] deploy failed: ", e)
	b.deploy("king", Vector2i(3, 18))
	print("[sim] deployed ", b.units.size(), " units (", roster.size(), " soldiers + bonded Nivians + king)")

	# a balance check, not a command-UI check: send the whole staged army at
	# the enemy Castle in one squad order, same as a player would
	var castle := {}
	for bld in b.buildings:
		if bld["type"] == "castle":
			castle = bld
	b.select_squad("knight", 99)
	b.select_squad("cavalry", 99)
	if not castle.is_empty():
		var order_err := b.order_attack(int(castle["id"]))
		if order_err != "":
			print("[sim] order_attack failed: ", order_err)
	var t := 0.0
	var step := 1.0 / 30.0
	while not b.ended and t < 200.0:
		b.update(step)
		t += step
		if fmod(t, 20.0) < step:
			var alive := 0
			for u in b.units:
				if not u["dead"]:
					alive += 1
			print("[sim] t=%3d  destroyed=%3d%%  alive=%d  loot=%d/%d" % [
				int(t), int(b.destruction() * 100.0), alive, int(b.loot["serge"]), int(b.loot["jade"])])
	var r := b.result()
	print("[sim] END ", r["reason"], "  stars=", r["stars"], "  destruction=", int(float(r["destruction"]) * 100.0), "%",
		"  loot=", int(r["loot"]["serge"]), "/", int(r["loot"]["jade"]), "  fallen=", r["fallen"].size())
	get_tree().quit()

## Development helper: render every sound to disk so the audio can be checked
## without speakers.
func _dump_audio() -> void:
	var dir := "/tmp/nivi_audio"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in Sfx._sounds:
		var stream: AudioStreamWAV = Sfx._sounds[name]
		stream.save_to_wav("%s/sfx_%s.wav" % [dir, name])
		print("[audio] sfx %-10s %6.3fs" % [name, stream.get_length()])
	# music renders on a worker thread, so wait for it before saving
	var waited := 0.0
	while not Music._ready_to_play and waited < 60.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("[audio] music ready after %.1fs" % waited)
	for name in ["kingdom", "raid"]:
		var p: AudioStreamPlayer = Music._players[name]
		var st: AudioStreamWAV = p.stream
		st.save_to_wav("%s/music_%s.wav" % [dir, name])
		print("[audio] music %-8s %6.2fs loop=%s" % [name, st.get_length(), st.loop_mode != AudioStreamWAV.LOOP_DISABLED])
	get_tree().quit()

## Development helper: confirm the music actually reached a player and that the
## effect voices are wired up.
func _check_audio() -> void:
	var waited := 0.0
	while not Music._ready_to_play and waited < 60.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(2.5).timeout
	for name in ["kingdom", "raid"]:
		var p: AudioStreamPlayer = Music._players[name]
		print("[check] music %-8s playing=%s vol=%.1fdB stream=%s pos=%.2fs" % [
			name, p.playing, p.volume_db, p.stream != null, p.get_playback_position()])
	print("[check] sfx bank=%d voices=%d music_on=%s sfx_on=%s bus_music=%.1f bus_sfx=%.1f" % [
		Sfx._sounds.size(), Sfx._players.size(), Sfx.music_enabled, Sfx.sfx_enabled,
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))])
	Sfx.play("collect")
	await get_tree().create_timer(0.1).timeout
	var busy := 0
	for p2 in Sfx._players:
		if p2.playing:
			busy += 1
	print("[check] after one effect, voices playing=%d" % busy)
	get_tree().quit()

## Development helper: confirm the soundtrack follows the player into a raid
## and back home again.
func _check_raid_music() -> void:
	var main := get_tree().current_scene
	var waited := 0.0
	while not Music._ready_to_play and waited < 60.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(1.6).timeout
	print("[check] in the kingdom: current=%s kingdom_vol=%.1f raid_vol=%.1f" % [
		Music._current, Music._players["kingdom"].volume_db, Music._players["raid"].volume_db])
	Game.add_unit("knight")
	main._on_attack("ashford")
	await get_tree().create_timer(1.8).timeout
	print("[check] on the raid:   current=%s kingdom_vol=%.1f raid_vol=%.1f playing=%s" % [
		Music._current, Music._players["kingdom"].volume_db, Music._players["raid"].volume_db,
		Music._players["raid"].playing])
	main._finish_battle()
	await get_tree().create_timer(1.8).timeout
	print("[check] back home:     current=%s kingdom_vol=%.1f raid_vol=%.1f" % [
		Music._current, Music._players["kingdom"].volume_db, Music._players["raid"].volume_db])
	get_tree().quit()

# ---------------------------------------------------------------- verification
func _synth_button(pos: Vector2, index: int, is_pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = index
	e.pressed = is_pressed
	return e

func _synth_motion(pos: Vector2, rel: Vector2, held: bool) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return e

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _mouse_down(pos: Vector2) -> void:
	Input.parse_input_event(_synth_button(pos, MOUSE_BUTTON_LEFT, true))
	await _wait_frames(2)

func _mouse_move_to(from: Vector2, to: Vector2) -> void:
	Input.parse_input_event(_synth_motion(to, to - from, true))
	await _wait_frames(2)

func _mouse_up(pos: Vector2) -> void:
	Input.parse_input_event(_synth_button(pos, MOUSE_BUTTON_LEFT, false))
	await _wait_frames(2)

func _click(pos: Vector2, jitter: Vector2) -> void:
	await _mouse_down(pos)
	if jitter != Vector2.ZERO:
		await _mouse_move_to(pos, pos + jitter)
	await _mouse_up(pos + jitter)

## Headless check of every non-attack change in one pass: grid size,
## the camera deadzone, and multi-directional wall dragging.
func _run_verify() -> void:
	var main := get_tree().current_scene
	var world: BaseWorld = main.world
	var rig := world.rig
	var W := get_viewport().get_visible_rect().size

	print("[verify] home GRID=%d buildable=%dx%d (was 36x36, area x%.1f)" % [
		Config.GRID, Config.BUILD_MAX - Config.BUILD_MIN, Config.BUILD_MAX - Config.BUILD_MIN,
		pow(float(Config.BUILD_MAX - Config.BUILD_MIN), 2) / (36.0 * 36.0)])
	print("[verify] BATTLE_GRID=%d BATTLE_BUILD=%d..%d (unchanged raid map)" % [
		Config.BATTLE_GRID, Config.BATTLE_BUILD_MIN, Config.BATTLE_BUILD_MAX])

	Game.state["resources"]["serge"] = 200000.0
	Game.state["resources"]["jade"] = 200000.0
	var e1 := Game.build("home", 10, 10)
	var e2 := Game.place_error("home", 14, 10)
	print("[verify] build: '%s'   place_error at a second spot: '%s'" % [e1, e2])

	# --- camera deadzone: a jittery tap must not pan, a real drag must ----
	var start_pos := rig.position
	var tapped_flag := [false]
	var cb := func(_p): tapped_flag[0] = true
	rig.tapped.connect(cb)
	await _click(W * 0.5, Vector2(2, 1))
	print("[verify] tiny jitter (2px): camera moved=%.4f tapped=%s (expect ~0 / true)" % [
		rig.position.distance_to(start_pos), tapped_flag[0]])

	tapped_flag[0] = false
	var start_pos2 := rig.position
	await _mouse_down(W * 0.5)
	var last := W * 0.5
	for step in 8:
		var next: Vector2 = W * 0.5 + Vector2(260, 40) * (float(step + 1) / 8.0)
		await _mouse_move_to(last, next)
		last = next
	await _mouse_up(last)
	print("[verify] real drag (260px over 8 steps): camera moved=%.2f tapped=%s (expect large / false)" % [
		rig.position.distance_to(start_pos2), tapped_flag[0]])
	rig.tapped.disconnect(cb)
	rig.focus_on(Vector3.ZERO)

	# --- wall line placement, dragged through four different directions ---
	main._on_request_build("wall")
	await _wait_frames(1)
	print("[verify] entered line mode=%s" % world.is_line_mode())
	var before := Game.count_type("wall")
	var path := [Vector2i(10, 90), Vector2i(13, 90), Vector2i(13, 87), Vector2i(10, 87), Vector2i(10, 90)]
	var screen_of := func(t: Vector2i) -> Vector2:
		return rig.camera.unproject_position(Config.tile_to_world(t.x, t.y))
	var p0: Vector2 = screen_of.call(path[0])
	await _mouse_down(p0)
	var prev := p0
	for i in range(1, path.size()):
		var p1: Vector2 = screen_of.call(path[i])
		await _mouse_move_to(prev, p1)
		prev = p1
	await _mouse_up(prev)
	var after := Game.count_type("wall")
	print("[verify] wall line drag (right, up, left, down): placed %d walls this stroke" % (after - before))
	main._on_place_cancel()
	print("[verify] after Done: is_placing=%s line_mode=%s rig.blocked=%s" % [
		world.is_placing(), world.is_line_mode(), rig.blocked])

	# --- Q/E zoom shortcuts ------------------------------------------------
	rig.set_zoom(40.0)
	var zoom_before := rig.get_zoom()
	var q_event := InputEventKey.new()
	q_event.keycode = KEY_Q
	q_event.pressed = true
	Input.parse_input_event(q_event)
	await _wait_frames(1)
	for i in 20:
		rig._process(1.0 / 60.0)
	print("[verify] Q held (zoom in): %.1f -> %.1f (expect smaller)" % [zoom_before, rig.get_zoom()])
	q_event.pressed = false
	Input.parse_input_event(q_event)
	await _wait_frames(1)

	rig.set_zoom(40.0)
	var zoom_before2 := rig.get_zoom()
	var e_event := InputEventKey.new()
	e_event.keycode = KEY_E
	e_event.pressed = true
	Input.parse_input_event(e_event)
	await _wait_frames(1)
	for i in 20:
		rig._process(1.0 / 60.0)
	print("[verify] E held (zoom out): %.1f -> %.1f (expect larger)" % [zoom_before2, rig.get_zoom()])
	e_event.pressed = false
	Input.parse_input_event(e_event)
	await _wait_frames(1)
	rig.set_zoom(40.0)

	Game.save_game()
	print("[verify] DONE")
	get_tree().quit()

## Headless economy check: tally how much of a realistic early build order
## draws from each currency, and let both mines run for a long stretch to
## compare their output. Confirms Serge no longer dominates every sink.
func _run_econ() -> void:
	Game.state["resources"]["serge"] = 1000000.0
	Game.state["resources"]["jade"] = 1000000.0
	var spent := {"serge": 0.0, "jade": 0.0}
	var order := []
	for i in 40:
		order.append("wall")
	for i in 30:
		order.append("road")
	for i in 4:
		order.append("home")
	order.append_array(["farm", "guard_station", "shop", "hospital", "outpost"])
	var x := 10
	var y := 10
	for type in order:
		var before := {"serge": Game.state["resources"]["serge"], "jade": Game.state["resources"]["jade"]}
		var d: Dictionary = Config.BUILDINGS[type]
		var fp := Buildings.footprint(type)
		while Game.place_error(type, x, y) != "" and x < 110:
			x += fp.x + 1
			if x > 100:
				x = 10
				y += fp.y + 1
		Game.build(type, x, y)
		for b in Game.buildings():
			if b["build_remaining"] > 0.0:
				b["build_remaining"] = 0.0
		spent["serge"] += before["serge"] - Game.state["resources"]["serge"]
		spent["jade"] += before["jade"] - Game.state["resources"]["jade"]
	var total: float = spent["serge"] + spent["jade"]
	print("[econ] early build order spent %.0f Serge (%.0f%%) and %.0f Jade (%.0f%%)" % [
		spent["serge"], 100.0 * spent["serge"] / total, spent["jade"], 100.0 * spent["jade"] / total])

	# now let the two starting mines run for a long stretch and compare output
	Game.state["resources"]["serge"] = 0.0
	Game.state["resources"]["jade"] = 0.0
	for b in Game.buildings():
		if b["type"] in ["serge_mine", "jade_mine"]:
			b["stored"] = 0.0
	Game.advance(60.0)
	Game.collect_all()
	print("[econ] after 60 simulated seconds of mining (before the mines cap out): Serge=%d Jade=%d (ratio %.2f)" % [
		int(Game.state["resources"]["serge"]), int(Game.state["resources"]["jade"]),
		Game.state["resources"]["jade"] / maxf(Game.state["resources"]["serge"], 1.0)])
	get_tree().quit()

## For the wallshot demo: draw a short zig-zag wall run via the same signals
## a real drag would fire, so the screenshot shows actual placed walls.
func _draw_wall_run() -> void:
	var main := get_tree().current_scene
	var world: BaseWorld = main.world
	var rig := world.rig
	var pts := [Vector2i(16, 38), Vector2i(24, 38), Vector2i(24, 34), Vector2i(16, 34), Vector2i(16, 38)]
	world._on_pressed(rig.camera.unproject_position(Config.tile_to_world(pts[0].x, pts[0].y)))
	for i in range(1, pts.size()):
		world._on_drag_moved(rig.camera.unproject_position(Config.tile_to_world(pts[i].x, pts[i].y)))

## Headless check: two units approaching head-on through a one-tile gap used
## to push against each other forever. Confirms both eventually get through.
func _run_jam_test() -> void:
	var kingdom: Dictionary = Config.ENEMY_KINGDOMS[0]
	var b := BattleState.new(kingdom, [{"id": 1, "type": "knight"}, {"id": 2, "type": "knight"}], false)
	# a short wall out in an empty corner of the map, well clear of the
	# generated base, with a single-tile gate at x=5 -- forces two units
	# through the same choke point from opposite sides
	for x in range(2, 9):
		if x != 5:
			b.buildings.append({"id": 900 + x, "type": "wall", "x": x, "y": 10, "hp": 300.0, "max_hp": 300.0, "cool": 0.0})
	b._rebuild_grid()
	# spawned directly at exact tiles (bypassing the staging area) since this
	# test is about the pathfinding jam fix, not squad deployment
	b._spawn_unit("knight", Vector2i(5, 7), 0)
	b._spawn_unit("knight", Vector2i(5, 13), 0)
	if b.units.size() < 2:
		print("[jam] ABORT: spawn failed")
		get_tree().quit()
		return
	var u1: Dictionary = b.units[0]
	var u2: Dictionary = b.units[1]
	# send them past each other through the gate, not at a building
	b.move_to(Vector2i(5, 13), int(u1["id"]))
	b.move_to(Vector2i(5, 7), int(u2["id"]))
	var start1: Vector2 = u1["pos"]
	var start2: Vector2 = u2["pos"]
	var t := 0.0
	var step := 1.0 / 30.0
	var unstuck_at := -1.0
	var iterations := 0
	while t < 20.0 and iterations < 700:
		iterations += 1
		b.update(step)
		t += step
		if unstuck_at < 0.0 and u1["pos"].distance_to(start1) > 3.0 and u2["pos"].distance_to(start2) > 3.0:
			unstuck_at = t
	print("[jam] u1 moved=%.2f u2 moved=%.2f both_through_by=%s" % [
		u1["pos"].distance_to(start1), u2["pos"].distance_to(start2),
		("%.1fs" % unstuck_at) if unstuck_at > 0.0 else "NEVER"])
	get_tree().quit()

## Headless check of the staging/squad-command system: deployed soldiers must
## sit idle in the staging area until an explicit squad order sends them (and
## their bonded Nivians) at a chosen building, never auto-attacking on their
## own the way the old free-placement deployment did.
func _run_squad_test() -> void:
	var kingdom: Dictionary = Config.ENEMY_KINGDOMS[0]
	var roster := [
		{"id": 1, "type": "knight", "bonded": ["unitone", "garuan"]},
		{"id": 2, "type": "knight", "bonded": ["unitone", "firon"]},
		{"id": 3, "type": "cavalry", "bonded": ["garuan", "garuan"]},
	]
	var b := BattleState.new(kingdom, roster, false)
	for u in roster:
		var e := b.deploy(u["type"])
		if e != "":
			print("[squad] deploy failed: ", e)
	print("[squad] staged after deploy: %s (expect knight=2 cavalry=1)" % [b.staged_counts()])
	var riders := 0
	var escorts := 0
	for u in b.units:
		if str(u.get("mount", "")) != "":
			riders += 1
		if int(u.get("bonded_to", 0)) != 0:
			escorts += 1
	print("[squad] riders=%d escorts=%d (expect 2 riders, 4 escorts; nobody's Nivian is a unit of its own)" % [riders, escorts])
	print("[squad] total units on the muster ground: %d (expect 7: three soldiers, two of them riding a Unitone, plus four walking escorts)" % b.units.size())

	# nobody has been ordered anywhere yet -- run the clock and confirm not one
	# hit point of damage happens on its own
	var step := 1.0 / 30.0
	for i in 180:
		b.update(step)
	print("[squad] destruction after 6s with no orders: %.0f%% (expect 0%%)" % (b.destruction() * 100.0))

	# pick both knights (their four bonded Nivians come along) and send them
	# at the enemy Castle
	var picked := b.select_squad("knight", 2)
	var castle := {}
	for bld in b.buildings:
		if bld["type"] == "castle":
			castle = bld
	var order_err := b.order_attack(int(castle["id"]))
	print("[squad] picked=%d order_err='%s' selection cleared after order=%s" % [picked, order_err, b.selected_ids.is_empty()])

	# the un-ordered cavalry (and its two bonded Garuans) must still be idle
	var cav := {}
	for u in b.units:
		if u["type"] == "cavalry":
			cav = u
	var cav_start: Vector2 = cav["pos"]

	var t := 0.0
	var moved := false
	while t < 25.0 and not moved:
		b.update(step)
		t += step
		for u in b.units:
			if u["type"] == "knight" and u["attacking"]:
				moved = true
				break
	print("[squad] ordered knights reached and struck the Castle by t=%.1fs (expect well under 25s)" % t)
	print("[squad] un-ordered cavalry drifted=%.2f while its squadmates fought (expect ~0)" % cav["pos"].distance_to(cav_start))
	# the escorts went with their knights and stayed at their sides, not off on their own
	var far := 0
	for u in b.units:
		if int(u.get("bonded_to", 0)) != 0:
			var leader := b.find_unit(int(u["bonded_to"]))
			if u["pos"].distance_to(leader["pos"]) > 1.6:
				far += 1
	print("[squad] escorts more than 1.6 tiles from their soldier: %d (expect 0)" % far)
	for i in 300:
		b.update(step)
	var castle_now := {}
	for bld in b.buildings:
		if bld["type"] == "castle":
			castle_now = bld
	print("[squad] Castle HP 10s after first strike: %d/%d (expect below max)" % [int(castle_now["hp"]), int(castle_now["max_hp"])])
	get_tree().quit()

## Headless check of the forest and catching: the King can walk the home
## island, the bridge and the forest but not the sea; a Nivian ball catches
## the nearest wild Nivian and it bonds with the King (five at most, then
## soldiers short of theirs); a soldier who lost a Nivian in a raid walks to
## the forest and comes back with another; and a Nivian falling in a raid
## costs its person a Nivian, not their life.
func _run_catch_test() -> void:
	var main := get_tree().current_scene
	var world: BaseWorld = main.world
	var forest: Forest = world.forest
	var edge: float = Config.GRID * 0.5 + 3.0
	var land := Config.land_rect()
	print("[catch] forest centre z=%.1f half=%s wild=%d (expect %d), valley %s" % [forest.center.z, forest.half, forest.wild_count(), Config.WILD_NIVIANS, land])
	print("[catch] land: castle=%s lane=%s forest=%s beyond the east mountains=%s past the forest south=%s (expect T T T F F)" % [
		forest.on_land(Vector3.ZERO), forest.on_land(Vector3(0, 0, edge + 1.0)), forest.on_land(forest.center),
		forest.on_land(Vector3(land.end.x + 6.0, 0, 0)), forest.on_land(Vector3(0, 0, land.end.y + 6.0))])

	# walking: stick held for a second moves the King and the camera follows
	main._on_walk(true)
	var start := world.king_pos
	world.joystick = Vector2(0.0, -1.0)
	for i in 60:
		world._walk(1.0 / 60.0)
	world.joystick = Vector2.ZERO
	print("[catch] walked %.2f tiles in 1s (expect ~%.1f), camera on King=%s" % [
		world.king_pos.distance_to(start), Config.KING_WALK_SPEED, world.rig.position.distance_to(Vector3(world.king_pos.x, 0, world.king_pos.z)) < 0.01])
	# cannot walk into the castle
	var mid := Config.GRID / 2
	world.king_pos = Config.tile_to_world(mid, mid + 3)
	var castle_tile := Config.tile_to_world(mid, mid + 1)
	print("[catch] can stand on castle tile=%s, on open grass=%s (expect false / true)" % [world._can_stand(castle_tile), world._can_stand(world.king_pos)])

	# throwing outside the forest: refused with a hint
	var msgs := []
	var cb := func(m: String, _ok: bool) -> void: msgs.append(m)
	world.caught.connect(cb)
	world.throw_ball()
	print("[catch] throw from home: '%s'" % (msgs.back() if not msgs.is_empty() else "(nothing)"))

	# stand on top of a wild Nivian and throw until the King has caught two
	Game.state["credits"] = 0
	var caught := 0
	var throws := 0
	while caught < 2 and throws < 12:
		var w := forest.nearest_wild(forest.center, 100.0)
		if w.is_empty():
			break
		if w["type"] == "firon":
			# with no credits Firon refuses; prove that, then stand by another
			world.king_pos = w["pos"]
			world.throw_ball()
			print("[catch] Firon at 0 credits: '%s'" % msgs.back())
			forest.take(w)
			continue
		world.king_pos = w["pos"]
		throws += 1
		var before: int = Game.state["king"]["bonded"].size()
		world.throw_ball()
		await get_tree().create_timer(0.6).timeout
		if Game.state["king"]["bonded"].size() > before:
			caught += 1
	print("[catch] %d throws at point blank -> King's Nivians=%s (expect 2 within a few throws)" % [throws, Game.state["king"]["bonded"]])
	print("[catch] wild left=%d, respawn queued=%d (caught ones come back after %ds)" % [forest.wild_count(), forest._respawn.size(), int(Config.WILD_RESPAWN_SECONDS)])

	# fill the King to five, then the next catch must go to a soldier short of one
	while Game.state["king"]["bonded"].size() < Config.BONDED_FOR_KING:
		Game.receive_nivian("garuan")
	Game.state["queues"]["barracks_h"].clear()
	var soldier := Game.add_unit("knight", 0, ["unitone", "garuan"])
	print("[catch] King full: catch_error='%s' (expect nobody needs one)" % Game.catch_error("unitone"))
	soldier["bonded"].erase("garuan")
	print("[catch] soldier short one: catch_error='%s' -> receiver=%s bonded=%s" % [Game.catch_error("unitone"), Game.receive_nivian("unitone"), soldier["bonded"]])

	# a raid where a Nivian falls: the soldier lives, loses the Nivian, then
	# walks to the forest and returns with another after CATCH_SECONDS
	var king_before: int = Game.state["king"]["bonded"].size()
	var army_before: int = Game.state["army"].size()
	var outcome := Game.apply_battle_result({"stars": 1, "loot": {"serge": 0.0, "jade": 0.0}, "destruction": 0.5,
		"fallen": [{"id": soldier["id"], "type": "unitone"}, {"id": -1, "type": "garuan"}],
		"enemy_name": "Test", "reason": "test", "survivors": 0})
	print("[catch] after raid: soldiers %d->%d (expect same), soldier bonded=%s, King %d->%d, nivians_lost=%s" % [
		army_before, Game.state["army"].size(), soldier["bonded"], king_before, Game.state["king"]["bonded"].size(), outcome["nivians_lost"]])
	Game.advance(1.0)
	print("[catch] a second later the soldier is '%s' with %.0fs to go (expect catching)" % [soldier["status"], float(soldier.get("catch_remaining", 0.0))])
	Game.advance(Config.CATCH_SECONDS + 1.0)
	print("[catch] after the trip: '%s' bonded=%s (expect ready, two Nivians)" % [soldier["status"], soldier["bonded"]])
	main._on_walk(false)

	# enlisting: a soldier keeps the Nivian(s) they already bonded as a
	# civilian rather than being handed a fresh pair, and if that leaves them
	# one short they head for the forest for it the same as anyone else
	Game.state["resources"]["serge"] = 100000.0
	Game.state["resources"]["jade"] = 100000.0
	if not Game.has_built("barracks_h"):
		Game.build("barracks_h", 30, 30)
	if not Game.has_built("guard_station"):
		Game.build("guard_station", 40, 30)
	for b in Game.buildings():
		if b["type"] in ["barracks_h", "guard_station"]:
			b["build_remaining"] = 0.0
	# _free_citizen() enlists whoever is first in line, not necessarily the
	# citizen we just added, so give that one the single Nivian instead
	var recruit := Game._free_citizen()
	recruit["bonded"] = ["firon"]
	var train_err := Game.train("knight")
	var item: Dictionary = Game.state["queues"]["barracks_h"].back()
	print("[catch] enlist a one-Nivian citizen: train_err='%s' queued bonded=%s (expect just ['firon'], not a fresh pair)" % [train_err, item.get("bonded", [])])
	item["remaining"] = 0.0
	Game.advance(0.1)
	var recruit_unit := {}
	for u in Game.state["army"]:
		if u["citizen_id"] == recruit["id"]:
			recruit_unit = u
	print("[catch] fresh soldier this tick: status='%s' bonded=%s (expect catching, still just one)" % [recruit_unit.get("status", "?"), recruit_unit.get("bonded", [])])
	Game.advance(Config.CATCH_SECONDS + 1.0)
	print("[catch] after their own trip: status='%s' bonded=%s (expect ready, two Nivians incl. the original firon)" % [recruit_unit["status"], recruit_unit["bonded"]])

	print("[catch] DONE")
	get_tree().quit()

## Headless check of first person: the view switches to the King's eyes and
## back, WASD walks the way he looks, riding a Nivian is faster, townsfolk
## and their Nivians keep to the roads, and on a raid the King can be walked
## by hand and strikes what he reaches.
func _run_view_test() -> void:
	var main := get_tree().current_scene
	var world: BaseWorld = main.world
	var fp: FirstPersonCam = world._fp
	main._on_first_person(true)
	print("[view] first person on: walk=%s fp=%s fp cam current=%s iso cam current=%s king hidden=%s (expect all T, iso F)" % [
		world.walk_mode, world.first_person, fp.camera.current, world.rig.camera.current, not world._king.visible])
	# look north (-Z) and walk forward: he must move along -Z, not the camera's diagonal
	fp.yaw = 0.0
	var start := world.king_pos
	world.joystick = Vector2(0, -1)
	for i in 30:
		world._walk(1.0 / 60.0)
	var moved := world.king_pos - start
	print("[view] half a second forward facing north: dz=%.2f dx=%.2f (expect dz negative and dx 0; the Castle stands in his way after ~1.5)" % [moved.z, moved.x])
	fp.yaw = PI * 0.5   # look west (-X)
	start = world.king_pos
	for i in 30:
		world._walk(1.0 / 60.0)
	moved = world.king_pos - start
	print("[view] facing west: dx=%.2f dz=%.2f (expect dx about -2.5, dz 0)" % [moved.x, moved.z])
	world.joystick = Vector2.ZERO
	print("[view] eye height above the King's feet: %.2f (expect %.2f)" % [fp.position.y - world.king_pos.y, FirstPersonCam.EYE_ON_FOOT])

	# riding: no Nivian yet -> nothing to ride; with one -> faster
	print("[view] ride with no Nivian: '%s' speed=%.1f" % [world.cycle_mount(), world.walk_speed()])
	Game.state["king"]["bonded"] = ["garuan", "unitone"]
	print("[view] ride: %s speed=%.1f, then %s speed=%.1f, then '%s' speed=%.1f (expect garuan < unitone, then on foot)" % [
		world.cycle_mount(), world.walk_speed(), world.cycle_mount(), world.walk_speed(), world.cycle_mount(), world.walk_speed()])
	world.cycle_mount()
	print("[view] mounted eye height: %.2f (expect %.2f)" % [fp.position.y - world.king_pos.y, FirstPersonCam.EYE_MOUNTED])
	main._on_first_person(false)
	print("[view] back to isometric: fp=%s iso cam current=%s king visible=%s" % [world.first_person, world.rig.camera.current, world._king.visible])
	main._on_walk(false)

	# townsfolk: without roads they wait in the square; with a road loop they
	# walk it and never leave it
	var tf: Townsfolk = world.townsfolk
	var civilians := 0
	for c in Game.state["citizens"]:
		if c["profession"] != "Soldier":
			civilians += 1
	print("[view] townsfolk figures=%d civilians=%d (expect equal), roads=%d" % [tf.count(), civilians, tf._roads.size()])
	Game.state["resources"]["serge"] = 100000.0
	Game.state["resources"]["jade"] = 100000.0
	var mid := Config.GRID / 2
	for x in range(mid - 6, mid + 6):
		Game.build("road", x, mid + 9)
		Game.build("road", x, mid + 13)
	for y in range(mid + 10, mid + 13):
		Game.build("road", mid - 6, y)
		Game.build("road", mid + 5, y)
	print("[view] laid a road loop: roads=%d" % tf._roads.size())
	var off_road := 0
	var walked := 0.0
	var before: Array = []
	for f in tf._folk:
		before.append(f["pos"])
	for i in 600:
		tf._process(1.0 / 30.0)
		for f in tf._folk:
			if not tf.on_road(f["pos"]):
				off_road += 1
	for i in tf._folk.size():
		walked += (tf._folk[i]["pos"] as Vector3).distance_to(before[i])
	print("[view] 20s later: off-road samples=%d (expect 0), total displacement=%.1f (expect > 0), followers=%d" % [
		off_road, walked, tf._folk[0]["followers"].size() if not tf._folk.is_empty() else -1])

	# a raid: first person needs the King on the field, then walks him by hand
	Game.add_unit("knight", 0, ["unitone", "garuan"])
	main._on_attack("greywater")
	var bw: BattleWorld = main.battle_world
	var b: BattleState = main.battle
	var k := bw.king_unit()
	print("[view] raid opens with the King already mustered: deployed=%s on the muster ground=%s (expect true true)" % [
		b.king_deployed, BattleState.staging_rect_tiles().has_point(Vector2i(int(k["pos"].x), int(k["pos"].y)))])
	var err := bw.set_first_person(true)
	print("[view] King deployed: err='%s' directive=%s fp cam current=%s" % [err, k["directive"], bw._fp.camera.current])
	bw._fp.yaw = -PI * 0.5   # look east (+X), into the base
	var kstart: Vector2 = k["pos"]
	bw.joystick = Vector2(0, -1)
	for i in 60:
		bw._walk_king(1.0 / 60.0)
	bw.joystick = Vector2.ZERO
	print("[view] walked east for 1s: dx=%.2f dy=%.2f (expect dx about +%.1f)" % [k["pos"].x - kstart.x, k["pos"].y - kstart.y, float(Config.UNITS["king"]["speed"]) * 1.3])
	# straight into the nearest building: he stops at its wall and hits it
	var castle := {}
	for bld in b.buildings:
		if bld["type"] == "castle":
			castle = bld
	k["pos"] = Vector2(castle["x"] - 0.6, castle["y"] + 1.5)
	var before_hp: float = castle["hp"]
	bw.joystick = Vector2(0, -1)
	var t := 0.0
	while t < 4.0:
		bw._walk_king(1.0 / 30.0)
		b.update(1.0 / 30.0)
		t += 1.0 / 30.0
	bw.joystick = Vector2.ZERO
	print("[view] pushed at the Castle for 4s: inside it=%s (expect false), Castle hp %d -> %d (expect lower), directive still %s" % [
		not b._walkable(k["pos"]), int(before_hp), int(castle["hp"]), k["directive"]])
	bw.set_first_person(false)
	print("[view] off again: directive=%s iso cam current=%s" % [k["directive"], bw.rig.camera.current])
	print("[view] DONE")
	get_tree().quit()
