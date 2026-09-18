class_name BattleHud
extends CanvasLayer
## The raid interface: clock and score along the top, troop cards along the
## bottom, and the orders you can give whatever is selected.

signal pick_troop(type: String)
signal pick_squad(type: String, count: int)
signal order_hold
signal order_proceed
signal order_deselect
signal end_battle
signal request_first_person(on: bool)
signal walk_input(vector: Vector2)

var state: BattleState
var _time: Label
var _destroyed: Label
var _star_box: PanelContainer
var _star_holder: HBoxContainer
var _stars_shown := -1
var _loot: Dictionary = {}
var _hint: Label
var _selected: Label
var _troop_row: HBoxContainer
var _troop_key := ""
var _staging_row: HBoxContainer
var _staging_key := ""
var _btn_view: Button
var _joystick: Hud.Joystick
var _world: BattleWorld

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)

	var top := HBoxContainer.new()
	top.position = Vector2(14, 12)
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	_time = _plaque(top, "Time", "2:30")
	_destroyed = _plaque(top, "Destroyed", "0%")
	_star_box = PanelContainer.new()
	_star_box.theme_type_variation = "Plaque"
	_star_holder = HBoxContainer.new()
	_star_box.add_child(_star_holder)
	top.add_child(_star_box)
	_set_stars(0)
	_loot["serge"] = _plaque(top, "Serge", "0")
	_loot["jade"] = _plaque(top, "Jade", "0")
	var end := Button.new()
	end.text = "End Raid"
	end.theme_type_variation = "RedButton"
	end.pressed.connect(func() -> void:
		Sfx.play("tap")
		end_battle.emit())
	top.add_child(end)

	var hint_panel := PanelContainer.new()
	hint_panel.theme_type_variation = "Plaque"
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.position = Vector2(0, 72)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(hint_panel)
	_hint = Label.new()
	_hint.theme_type_variation = "ValueLabel"
	hint_panel.add_child(_hint)

	var orders := PanelContainer.new()
	orders.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	orders.position = Vector2(0, -168)
	orders.grow_horizontal = Control.GROW_DIRECTION_BOTH
	orders.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(orders)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 8)
	_selected = Label.new()
	_selected.text = "All troops"
	_selected.custom_minimum_size = Vector2(150, 0)
	orow.add_child(_selected)
	orow.add_child(_order_button("Hold", "GoldButton", func() -> void: order_hold.emit()))
	orow.add_child(_order_button("Proceed", "GreenButton", func() -> void: order_proceed.emit()))
	orow.add_child(_order_button("Deselect", "WoodButton", func() -> void: order_deselect.emit()))
	_btn_view = _order_button("First person", "GreenButton", func() -> void:
		request_first_person.emit(_world == null or not _world.first_person))
	orow.add_child(_btn_view)
	orders.add_child(orow)

	_joystick = Hud.Joystick.new()
	_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joystick.position = Vector2(26, -Hud.Joystick.RADIUS * 2 - 26)
	_joystick.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_joystick.visible = false
	_joystick.moved.connect(func(v: Vector2) -> void: walk_input.emit(v))
	root.add_child(_joystick)

	_staging_row = HBoxContainer.new()
	_staging_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_staging_row.position = Vector2(0, -92)
	_staging_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_staging_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_staging_row.add_theme_constant_override("separation", 10)
	root.add_child(_staging_row)

	_troop_row = HBoxContainer.new()
	_troop_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_troop_row.position = Vector2(0, -16)
	_troop_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_troop_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_troop_row.add_theme_constant_override("separation", 10)
	root.add_child(_troop_row)

func _set_stars(earned: int) -> void:
	if earned == _stars_shown:
		return
	if earned > _stars_shown and _stars_shown >= 0:
		Sfx.play("star")
	_stars_shown = earned
	for c in _star_holder.get_children():
		c.queue_free()
	for i in 3:
		var t := TextureRect.new()
		t.texture = Hud.star_texture(i < earned, 30)
		t.custom_minimum_size = Vector2(30, 30)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_star_holder.add_child(t)

func _order_button(text: String, variation: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.pressed.connect(func() -> void: Sfx.play("tap"))
	b.pressed.connect(cb)
	return b

func _plaque(parent: Control, caption: String, value: String) -> Label:
	var p := PanelContainer.new()
	p.theme_type_variation = "Plaque"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if caption != "":
		if caption in ["Serge", "Jade"]:
			var gem := TextureRect.new()
			gem.texture = Hud.gem_texture(Config.RESOURCES[caption.to_lower()]["color"], 24)
			gem.custom_minimum_size = Vector2(24, 24)
			gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(gem)
		else:
			var cap := Label.new()
			cap.text = caption
			cap.theme_type_variation = "ValueLabel"
			cap.add_theme_font_size_override("font_size", 14)
			cap.modulate = Color("e0bd82")
			row.add_child(cap)
	var val := Label.new()
	val.text = value
	val.theme_type_variation = "ValueLabel"
	val.custom_minimum_size = Vector2(46, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(val)
	p.add_child(row)
	parent.add_child(p)
	return val

func set_world(w: BattleWorld) -> void:
	_world = w

func refresh(deploy_type: String) -> void:
	if state == null:
		return
	var fp := _world != null and _world.first_person
	_btn_view.text = "Isometric view" if fp else "First person"
	_btn_view.disabled = not state.king_deployed
	_joystick.visible = fp
	_time.text = BaseWorld._format_time(state.time_left)
	_destroyed.text = "%d%%" % int(round(state.destruction() * 100.0))
	_set_stars(state.stars())
	_loot["serge"].text = str(int(state.loot["serge"]))
	_loot["jade"].text = str(int(state.loot["jade"]))

	var sel := state.find_unit(state.selected_id) if state.selected_id != 0 else {}
	var squad_n := state.selected_ids.size()
	if squad_n > 0:
		_selected.text = "%d picked" % squad_n
	elif sel.is_empty():
		_selected.text = "All troops"
	else:
		_selected.text = "%s  %d HP" % [Config.UNITS[sel["type"]]["name"], int(ceil(sel["hp"]))]
	if fp:
		_hint.text = "Through the King's eyes: WASD or the stick walk him, drag or Q/E look around. He strikes whatever is in reach."
	elif not state.started:
		_hint.text = "Pick a troop below to send them to the staging area."
	elif squad_n > 0:
		_hint.text = "Tap a building to send this squad at it."
	elif not sel.is_empty():
		_hint.text = "Tap the ground to move the King." if sel["type"] == "king" else "Tap a building to focus this troop."
	else:
		_hint.text = "Use the staging area below to pick soldiers, or tap a deployed troop to give it orders."

	_refresh_staging()

	var counts := state.available_counts()
	var types: Array = counts.keys()
	types.sort()
	if state.king_available and not state.king_deployed:
		types.push_front("king")
	var key := str(types) + str(counts) + deploy_type
	if key == _troop_key:
		return
	_troop_key = key
	for c in _troop_row.get_children():
		c.queue_free()
	if types.is_empty():
		var none := Label.new()
		none.text = "No troops left"
		none.theme_type_variation = "ValueLabel"
		_troop_row.add_child(none)
		return
	for type in types:
		_troop_row.add_child(_troop_card(type, int(counts.get(type, 1)), type == deploy_type))

func _troop_card(type: String, count: int, active: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	if active:
		card.modulate = Color(1.0, 0.92, 0.6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(Thumb.unit(type, 74))
	var n := Label.new()
	n.text = "%s  x%d" % [Config.UNITS[type]["name"], count] if type != "king" else "The King"
	n.add_theme_font_size_override("font_size", 14)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var pick := Button.new()
	pick.text = "Deploy"
	pick.theme_type_variation = "GreenButton" if not active else "GoldButton"
	pick.add_theme_font_size_override("font_size", 14)
	pick.pressed.connect(func() -> void:
		Sfx.play("tap")
		pick_troop.emit(type))
	col.add_child(pick)
	card.add_child(col)
	return card

## The staging area: soldiers already deployed, standing by for a squad
## command. Rebuilt whenever the staged counts or the current pick change.
func _refresh_staging() -> void:
	var counts := state.staged_counts()
	var types: Array = counts.keys()
	types.sort()
	var picks := {}
	for type in types:
		picks[type] = state.selected_count(type)
	var key := str(counts) + str(picks)
	if key == _staging_key:
		return
	_staging_key = key
	for c in _staging_row.get_children():
		c.queue_free()
	if types.is_empty():
		return
	for type in types:
		_staging_row.add_child(_staging_card(type, int(counts[type]), int(picks[type])))

func _staging_card(type: String, staged: int, picked: int) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	if picked > 0:
		card.modulate = Color(1.0, 0.92, 0.6)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(Thumb.unit(type, 60))
	var n := Label.new()
	n.text = "%s  staged %d" % [Config.UNITS[type]["name"], staged]
	n.add_theme_font_size_override("font_size", 13)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var minus := Button.new()
	minus.text = "-"
	minus.theme_type_variation = "WoodButton"
	minus.custom_minimum_size = Vector2(34, 0)
	minus.disabled = picked <= 0
	minus.pressed.connect(func() -> void:
		Sfx.play("tap")
		pick_squad.emit(type, picked - 1))
	row.add_child(minus)
	var count_l := Label.new()
	count_l.text = str(picked)
	count_l.theme_type_variation = "ValueLabel"
	count_l.custom_minimum_size = Vector2(28, 0)
	count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_l)
	var plus := Button.new()
	plus.text = "+"
	plus.theme_type_variation = "GreenButton"
	plus.custom_minimum_size = Vector2(34, 0)
	plus.disabled = picked >= staged
	plus.pressed.connect(func() -> void:
		Sfx.play("tap")
		pick_squad.emit(type, picked + 1))
	row.add_child(plus)
	col.add_child(row)
	card.add_child(col)
	return card

## The results window, shown over the battlefield when the raid ends.
func show_results_via(result: Dictionary, outcome: Dictionary, on_close: Callable) -> void:
	var sheet := Hud.new()
	sheet.name = "Results"
	add_child(sheet)
	sheet.show_results(result, outcome, on_close)
