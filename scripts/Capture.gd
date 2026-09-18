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

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			_target = a.substr(10)
		elif a.begins_with("--after="):
			_after = int(a.substr(8))
		elif a.begins_with("--demo="):
			_demo = a.substr(7)
	set_process(_target != "")

func _process(_delta: float) -> void:
	_frames += 1
	if _demo != "" and not _demo_done and _frames == maxi(8, _after - 60):
		_demo_done = true
		_run_demo()
	if _frames < _after:
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
		"sim":
			_simulate_raid()
		"build":
			main.hud.show_build("resource")
		"army":
			Game.state["resources"]["serge"] = 4000.0
			Game.state["resources"]["jade"] = 4000.0
			Game.build("barracks_h", 14, 12)
			Game.build("barracks_l", 22, 12)
			Game.build("guard_station", 14, 24)
			Game.build("cavalry_outpost", 21, 24)
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
		"attack":
			main.hud.show_attack()
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
