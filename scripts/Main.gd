extends Node3D
## Application root. Runs the kingdom, and swaps to the raid view and back.

var hud: Hud
var world: BaseWorld
var battle_world: BattleWorld
var battle_hud: BattleHud
var battle: BattleState
var _save_timer := 0.0
var _results_shown := false

func _ready() -> void:
	_enter_base()

# ---------------------------------------------------------------- base
func _enter_base() -> void:
	world = BaseWorld.new()
	add_child(world)
	hud = Hud.new()
	hud.world = world
	add_child(hud)
	world.building_tapped.connect(_on_building_tapped)
	world.ground_tapped.connect(func(_tile: Vector2i) -> void: hud.hide_panel())
	world.placement_changed.connect(func(ok: bool) -> void: hud.set_place_valid(ok))
	hud.request_build.connect(_on_request_build)
	hud.request_move.connect(_on_request_move)
	hud.request_place_confirm.connect(_on_place_confirm)
	hud.request_place_cancel.connect(_on_place_cancel)
	hud.request_attack.connect(_on_attack)
	hud.request_new_game.connect(_on_new_game)
	hud.request_walk.connect(_on_walk)
	hud.request_throw.connect(func() -> void: world.throw_ball())
	hud.walk_input.connect(func(v: Vector2) -> void: world.joystick = v)
	world.caught.connect(func(msg: String, ok: bool) -> void:
		hud.toast(msg)
		hud.refresh_top())
	world.rig.focus_on(Vector3.ZERO)
	world.rig.set_zoom(26.0)
	Music.play("kingdom")

func _on_building_tapped(b: Dictionary) -> void:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	# tapping a full mine collects it rather than opening the panel again
	if d.has("produces") and Game.is_built(b) and b["stored"] >= float(d["produces"]["capacity"]) * 0.18:
		var got := Game.collect(b)
		if got > 0.0:
			Sfx.play("collect")
			hud.toast("+%d %s" % [int(got), Config.RESOURCES[d["produces"]["resource"]]["name"]])
			world.select(b)
			return
	world.select(b)
	hud.show_building(b)

func _on_request_build(type: String) -> void:
	world.start_placing(type)
	hud.show_place_bar(type, world.is_line_mode())

func _on_request_move(id: int) -> void:
	var b := Game.find_building(id)
	if b.is_empty():
		return
	world.start_placing(b["type"], id)
	hud.show_place_bar(b["type"], false)

func _on_place_confirm() -> void:
	var err := world.confirm_placing()
	if err != "":
		Sfx.play("error")
		hud.toast(err)
		return
	Sfx.play("place")
	if not world.is_placing():
		hud.hide_place_bar()
	else:
		hud.show_place_bar(world.placing_type(), world.is_line_mode())
	hud.refresh_top()

func _on_place_cancel() -> void:
	world.cancel_placing()
	hud.hide_place_bar()

func _on_new_game() -> void:
	Game.wipe_save()
	Game.new_game()
	world.rebuild()
	hud.refresh_top()
	Sfx.play("done")
	hud.toast("A new kingdom rises.")

## Walking as the King: WASD or the on-screen stick move him, the camera
## follows, and Throw catches the nearest wild Nivian in the forest.
func _on_walk(on: bool) -> void:
	if world == null:
		return
	if on and world.is_placing():
		_on_place_cancel()
	world.set_walk_mode(on)
	hud.show_walk_bar(on)
	if on:
		hud.hide_panel()

# ---------------------------------------------------------------- raid
func _on_attack(kingdom_id: String) -> void:
	var kingdom := {}
	for k in Config.ENEMY_KINGDOMS:
		if k["id"] == kingdom_id:
			kingdom = k
	if kingdom.is_empty():
		return
	var roster := Game.ready_units()
	if roster.is_empty() and Game.state["king"]["status"] != "ready":
		hud.toast("Nobody is ready to fight.")
		return
	Game.save_game()
	Music.play("raid")
	if world.walk_mode:
		_on_walk(false)
	battle = BattleState.new(kingdom, roster, Game.state["king"]["status"] == "ready", Game.state["king"]["bonded"])
	_results_shown = false

	world.queue_free()
	world = null
	hud.queue_free()
	hud = null

	battle_world = BattleWorld.new()
	add_child(battle_world)
	battle_world.setup(battle)
	battle_hud = BattleHud.new()
	battle_hud.state = battle
	add_child(battle_hud)
	battle_world.tapped_building.connect(_on_battle_building)
	battle_world.tapped_ground.connect(_on_battle_ground)
	battle_world.tapped_unit.connect(_on_battle_unit)
	battle_hud.pick_troop.connect(_on_pick_troop)
	battle_hud.pick_squad.connect(func(type: String, count: int) -> void:
		battle.select_squad(type, count)
		battle_hud.refresh(battle_world.deploy_type))
	battle_hud.order_hold.connect(func() -> void: battle.hold(battle.selected_id))
	battle_hud.order_proceed.connect(func() -> void: battle.proceed(battle.selected_id))
	battle_hud.order_deselect.connect(_on_deselect)
	battle_hud.end_battle.connect(_on_end_battle)
	battle_hud.refresh("")

func _on_pick_troop(type: String) -> void:
	# the King is still placed by hand, tap the ground where he should land;
	# every other soldier deploys straight into the staging area
	if type == "king":
		battle_world.deploy_type = "" if battle_world.deploy_type == type else type
		battle.selected_id = 0
		battle_world.show_deploy_hint(battle_world.deploy_type != "")
		battle_hud.refresh(battle_world.deploy_type)
		return
	var err := battle.deploy(type)
	if err != "":
		Sfx.play("error")
		return
	Sfx.play("deploy")
	battle_hud.refresh(battle_world.deploy_type)

func _on_deselect() -> void:
	battle.selected_id = 0
	battle.clear_selection()
	battle_world.deploy_type = ""
	battle_world.show_deploy_hint(false)
	battle_hud.refresh("")

func _on_battle_unit(u: Dictionary) -> void:
	battle.selected_id = int(u["id"])
	battle_world.deploy_type = ""
	battle_world.show_deploy_hint(false)
	battle_hud.refresh("")

func _on_battle_building(b: Dictionary) -> void:
	if battle_world.deploy_type != "":
		return
	if not battle.selected_ids.is_empty():
		var err := battle.order_attack(int(b["id"]))
		if err != "":
			Sfx.play("error")
		else:
			Sfx.play("deploy")
		battle_hud.refresh("")
		return
	battle.focus(int(b["id"]), battle.selected_id)
	battle_hud.refresh("")

func _on_battle_ground(tile: Vector2i) -> void:
	if battle_world.deploy_type != "":
		var err := battle.deploy(battle_world.deploy_type, tile)
		if err != "":
			Sfx.play("error")
			return
		Sfx.play("deploy")
		if battle_world.deploy_type == "king" or int(battle.available_counts().get(battle_world.deploy_type, 0)) == 0:
			battle_world.deploy_type = ""
			battle_world.show_deploy_hint(false)
		battle_hud.refresh(battle_world.deploy_type)
		return
	if not battle.selected_ids.is_empty():
		Sfx.play("error")
		return
	if battle.selected_id != 0:
		battle.move_to(tile, battle.selected_id)

func _on_end_battle() -> void:
	if battle == null or battle.ended:
		return
	battle._end("You called the retreat." if battle.started else "No troops were committed.")

func _finish_battle() -> void:
	battle = null
	battle_world.queue_free()
	battle_world = null
	battle_hud.queue_free()
	battle_hud = null
	_enter_base()

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	Game.advance(delta)
	if hud != null:
		_save_timer += delta
		if _save_timer > 15.0:
			_save_timer = 0.0
			Game.save_game()
	if battle != null:
		battle_hud.refresh(battle_world.deploy_type)
		if battle.ended and not _results_shown:
			_results_shown = true
			if not battle.started:
				_finish_battle()
				return
			var result := battle.result()
			var outcome := Game.apply_battle_result(result)
			Game.save_game()
			battle_hud.show_results_via(result, outcome, _finish_battle)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		Game.save_game()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				if world != null and world.is_placing():
					_on_place_cancel()
				elif world != null and world.walk_mode and hud != null and not hud.modal_open():
					_on_walk(false)
				elif hud != null:
					hud.close_modal()
					hud.hide_panel()
			KEY_K:
				if world != null and hud != null and not hud.modal_open():
					_on_walk(not world.walk_mode)
			KEY_SPACE, KEY_F:
				if world != null and world.walk_mode:
					world.throw_ball()
			KEY_B:
				if hud != null:
					hud.show_build("resource")
			KEY_C:
				if hud != null:
					hud._collect_all()
