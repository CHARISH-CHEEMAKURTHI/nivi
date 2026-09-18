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
		"rush":
			Game.state["resources"]["gems"] = 500.0
			Game.build("home", 20, 20)
			var b := {}
			for bl in Game.buildings():
				if bl["type"] == "home" and bl["build_remaining"] > 0.0:
					b = bl
			main.world.select(b)
			main.hud.show_building(b)
		"army":
			Game.state["resources"]["serge"] = 4000.0
			Game.state["resources"]["jade"] = 4000.0
			# finish each construction before starting the next, so this demo
			# is not limited by how many builders a fresh kingdom has
			for spec in [["barracks_h", 14, 12], ["barracks_l", 22, 12], ["guard_station", 14, 24], ["cavalry_outpost", 21, 24]]:
				Game.build(str(spec[0]), int(spec[1]), int(spec[2]))
				for b in Game.buildings():
					b["build_remaining"] = 0.0
			Game.train("knight")
			Game.train("cavalry")
			Game.train("garuan")
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
			for t in ["knight", "knight", "cavalry", "garuan", "unitone", "unitone", "firon"]:
				Game.add_unit(t)
			main._on_attack("greywater")
			var b: BattleState = main.battle
			var spots := [Vector2i(6, 18), Vector2i(7, 20), Vector2i(6, 22), Vector2i(8, 17),
				Vector2i(7, 24), Vector2i(9, 21), Vector2i(8, 26), Vector2i(10, 19)]
			var i := 0
			for u in b.available.duplicate():
				b.deploy(u["type"], spots[i % spots.size()])
				i += 1
			b.deploy("king", spots[i % spots.size()])
			# run the raid fast so a capture can show the fight, not the march
			Engine.time_scale = 7.0

## Headless check: run a raid to its end and report what happened.
func _simulate_raid() -> void:
	var kingdom: Dictionary = Config.ENEMY_KINGDOMS[1]
	var roster := []
	var types := ["knight", "knight", "cavalry", "garuan", "garuan", "unitone", "unitone", "firon"]
	for i in types.size():
		roster.append({"id": i + 1, "type": types[i]})
	var b := BattleState.new(kingdom, roster, true)
	var spots := [Vector2i(4, 20), Vector2i(4, 18), Vector2i(4, 22), Vector2i(5, 19),
		Vector2i(5, 21), Vector2i(3, 20), Vector2i(4, 16), Vector2i(4, 24)]
	var i2 := 0
	for u in roster:
		var e := b.deploy(u["type"], spots[i2 % spots.size()])
		if e != "":
			print("[sim] deploy failed: ", e)
		i2 += 1
	b.deploy("king", Vector2i(3, 18))
	print("[sim] deployed ", b.units.size(), " of ", roster.size() + 1)
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

## Headless check of every non-attack change in one pass: grid size, builders,
## gems, the camera deadzone, and multi-directional wall dragging.
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

	# --- builders --------------------------------------------------------
	Game.state["resources"]["serge"] = 200000.0
	Game.state["resources"]["jade"] = 200000.0
	Game.state["resources"]["gems"] = 5000.0
	var cap := Game.capacities()
	print("[verify] builders base=%d busy=%d" % [cap["builders"], Game.builders_busy()])
	var e1 := Game.build("home", 10, 10)
	var e2 := Game.build("home", 14, 10)
	var e3 := Game.place_error("home", 10, 14)
	print("[verify] two builds: '%s' / '%s'   third while both busy: '%s'" % [e1, e2, e3])
	for b in Game.buildings():
		if b["type"] == "home" and b["build_remaining"] > 0.0:
			b["build_remaining"] = 0.0
			break
	var e4 := Game.place_error("home", 10, 14)
	print("[verify] after one finishes, third now: '%s' (expect allowed)" % e4)

	# --- gems + builder's hut + rush -------------------------------------
	var hut_err := Game.build("builder_hut", 20, 10)
	print("[verify] builder_hut build: '%s'  gems left=%d" % [hut_err, int(Game.state["resources"]["gems"])])
	for b in Game.buildings():
		if b["type"] == "builder_hut":
			var cost := Game.rush_cost(b)
			var rr := Game.rush_build(b)
			print("[verify] hut rush cost=%d result='%s' built=%s" % [cost, rr, Game.is_built(b)])
	print("[verify] builders after hut=%d" % Game.capacities()["builders"])

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
	order.append_array(["farm", "guard_station", "shop", "barracks_l", "hospital", "outpost"])
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
