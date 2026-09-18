class_name Hud
extends CanvasLayer
## The whole interface: resource bars, the bottom button clusters, the side
## panel (build menu, building info, army, kingdom) and the pop-up windows.

signal request_build(type: String)
signal request_move(building_id: int)
signal request_attack(kingdom_id: String)
signal request_place_confirm
signal request_place_cancel
signal request_new_game
signal request_walk(on: bool)
signal request_throw
signal request_first_person(on: bool)
signal request_mount
signal walk_input(vector: Vector2)

var world: BaseWorld

var _res_fill: Dictionary = {}
var _res_label: Dictionary = {}
var _stat_label: Dictionary = {}
var _panel: PanelContainer
var _panel_title: Label
var _panel_body: VBoxContainer
var _panel_kind := ""
var _panel_arg: Variant = null
var _place_bar: PanelContainer
var _place_label: Label
var _btn_place: Button
var _btn_cancel: Button
var _btn_done: Button
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0
var _modal: Control
var _modal_body: VBoxContainer
var _refresh_timer := 0.0
var _bottom_bar: HBoxContainer
var _walk_bar: PanelContainer
var _walk_hint: Label
var _joystick: Joystick
var _btn_view: Button
var _btn_ride: Button

const GEM_SIZE := 30

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)
	_build_top(root)
	_build_bottom(root)
	_build_panel(root)
	_build_place_bar(root)
	_build_walk_bar(root)
	_build_toast(root)
	_build_modal(root)
	Game.resources_changed.connect(refresh_top)
	Game.army_changed.connect(refresh_top)
	Game.buildings_changed.connect(refresh_top)
	refresh_top()

# ---------------------------------------------------------------- pieces
static func gem_texture(color: Color, size := GEM_SIZE) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			# a faceted gem: diamond outline with a bright top-left facet
			var dx: float = absf(x + 0.5 - c) / c
			var dy: float = (y + 0.5 - c) / c
			var inside: float = dx + absf(dy) * 0.85
			if inside > 0.95:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var col: Color = color
			if inside > 0.78:
				col = color.darkened(0.45)
			elif dy < -0.1 and dx < 0.45:
				col = color.lightened(0.45)
			elif dy > 0.25:
				col = color.darkened(0.2)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## A five-pointed star, gold when earned and dull when not.
static func star_texture(filled: bool, size := 40) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	var outer := size * 0.47
	var inner := outer * 0.42
	var body: Color = Color("ffd24a") if filled else Color("6b5a3a")
	var edge: Color = Color("a97202") if filled else Color("4a3c26")
	var shine: Color = Color("fff3c0") if filled else Color("7d6a48")
	for y in size:
		for x in size:
			var dx := x + 0.5 - c
			var dy := y + 0.5 - c
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.001:
				img.set_pixel(x, y, shine)
				continue
			# radius of the star outline at this angle
			var a := atan2(dy, dx) + PI * 0.5
			var seg := fposmod(a, TAU / 5.0) / (TAU / 5.0)
			var t: float = absf(seg - 0.5) * 2.0
			var limit: float = lerp(inner, outer, t)
			if r > limit:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif r > limit - 2.0:
				img.set_pixel(x, y, edge)
			elif dy < -1.0 and r < limit * 0.7:
				img.set_pixel(x, y, shine)
			else:
				img.set_pixel(x, y, body)
	return ImageTexture.create_from_image(img)

## A row of three stars showing how many were earned.
static func star_row(earned: int, size := 40) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var t := TextureRect.new()
		t.texture = star_texture(i < earned, size)
		t.custom_minimum_size = Vector2(size, size)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(t)
	return row

func _gem(res: String, size := GEM_SIZE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = gem_texture(Config.RESOURCES[res]["color"], size)
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

func _button(text: String, variation := "", on_press := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(func() -> void: Sfx.play("tap"))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

func _label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	return l

# ---------------------------------------------------------------- top bar
func _build_top(root: Control) -> void:
	var bars := VBoxContainer.new()
	bars.position = Vector2(14, 12)
	bars.add_theme_constant_override("separation", 8)
	root.add_child(bars)
	for res in ["serge", "jade"]:
		var plaque := PanelContainer.new()
		plaque.theme_type_variation = "Plaque"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_gem(res))
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(158, 26)
		var bar := ProgressBar.new()
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.show_percentage = false
		bar.max_value = 1.0
		var fill := StyleBoxFlat.new()
		fill.bg_color = Config.RESOURCES[res]["color"]
		fill.set_corner_radius_all(8)
		bar.add_theme_stylebox_override("fill", fill)
		stack.add_child(bar)
		var value := _label("0", "ValueLabel")
		value.set_anchors_preset(Control.PRESET_FULL_RECT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stack.add_child(value)
		row.add_child(stack)
		plaque.add_child(row)
		bars.add_child(plaque)
		_res_fill[res] = bar
		_res_label[res] = value

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 7)
	stats.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stats.position = Vector2(0, 14)
	stats.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(stats)
	for entry in [["pop", "Pop"], ["joy", "Joy"], ["credits", "Credits"], ["army", "Army"], ["nivians", "King's Nivians"], ["season", "Season"]]:
		var plaque2 := PanelContainer.new()
		plaque2.theme_type_variation = "Plaque"
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		var cap := _label(entry[1], "ValueLabel")
		cap.add_theme_font_size_override("font_size", 14)
		cap.modulate = Color("e0bd82")
		row2.add_child(cap)
		var val := _label("-", "ValueLabel")
		row2.add_child(val)
		plaque2.add_child(row2)
		stats.add_child(plaque2)
		_stat_label[entry[0]] = val

func refresh_top() -> void:
	var cap := Game.capacities()
	for res in ["serge", "jade"]:
		var have: float = Game.state["resources"][res]
		var max_v: float = maxf(cap["storage"][res], 1.0)
		_res_fill[res].value = clampf(have / max_v, 0.0, 1.0)
		_res_label[res].text = "%d/%d" % [int(have), int(max_v)]
	var army := Game.army_summary()
	_stat_label["pop"].text = "%d/%d" % [Game.state["citizens"].size(), cap["pop_cap"]]
	_stat_label["joy"].text = "%d%%" % Game.happiness()
	var credits: int = Game.state["credits"]
	_stat_label["credits"].text = ("+%d" % credits) if credits > 0 else str(credits)
	_stat_label["army"].text = "%d/%d" % [army["housing"], army["housing_cap"]]
	_stat_label["nivians"].text = "%d/%d" % [Game.state["king"]["bonded"].size(), Config.BONDED_FOR_KING]
	_stat_label["season"].text = str(Game.state["season"])

# ---------------------------------------------------------------- bottom bar
func _build_bottom(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 14
	bar.offset_right = -14
	bar.offset_top = -86
	bar.offset_bottom = -14
	bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(bar)
	_bottom_bar = bar

	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.add_child(_button("Build", "GreenButton", func() -> void: show_build("resource")))
	left.add_child(_button("Army", "", func() -> void: show_army()))
	left.add_child(_button("Kingdom", "GoldButton", func() -> void: show_kingdom()))
	left.add_child(_button("Walk", "", func() -> void: request_walk.emit(true)))
	bar.add_child(left)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.add_child(_button("Collect", "GoldButton", func() -> void: _collect_all()))
	right.add_child(_button("Menu", "WoodButton", func() -> void: show_menu()))
	right.add_child(_button("Attack", "RedButton", func() -> void: show_attack()))
	bar.add_child(right)

func _collect_all() -> void:
	var got := Game.collect_all()
	if got["serge"] + got["jade"] <= 0.0:
		Sfx.play("error")
		toast("Nothing to collect yet.")
	else:
		Sfx.play("collect")
		toast("+%d Serge, +%d Jade" % [int(got["serge"]), int(got["jade"])])

# ---------------------------------------------------------------- side panel
func _build_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_top = 78
	_panel.offset_bottom = -96
	_panel.visible = false
	root.add_child(_panel)
	_layout_panel()
	get_viewport().size_changed.connect(_layout_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	var head := PanelContainer.new()
	head.theme_type_variation = "Ribbon"
	var head_row := HBoxContainer.new()
	_panel_title = _label("", "TitleLabel")
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_row.add_child(_panel_title)
	var close := _button("X", "RedButton", func() -> void: hide_panel())
	close.custom_minimum_size = Vector2(46, 0)
	head_row.add_child(close)
	head.add_child(head_row)
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_panel_body)

## Sized generously (so most panels never need to scroll), but always clamped
## to fit the actual screen width -- a fixed pixel width would run off the
## left edge of the screen on a narrow window or phone.
func _layout_panel() -> void:
	if _panel == null:
		return
	var vw: float = get_viewport().get_visible_rect().size.x
	var width: float = clampf(vw - 28.0, 320.0, 620.0)
	_panel.offset_left = -width - 14.0
	_panel.offset_right = -14.0

func hide_panel() -> void:
	if _panel.visible:
		Sfx.play("close")
	_panel.visible = false
	_panel_kind = ""
	if world != null:
		world.clear_selection()

func _open_panel(kind: String, arg: Variant, title: String) -> void:
	if not _panel.visible:
		Sfx.play("open")
	_panel_kind = kind
	_panel_arg = arg
	_panel_title.text = title
	_panel.visible = true
	for c in _panel_body.get_children():
		c.queue_free()

func _row(parent: Control, left: String, right: String) -> void:
	var h := HBoxContainer.new()
	var a := _label(left)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := _label(right)
	b.add_theme_color_override("font_color", UiTheme.INK)
	h.add_child(b)
	parent.add_child(h)

func _heading(parent: Control, text: String) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "Ribbon"
	var l := _label(text, "TitleLabel")
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	parent.add_child(p)

func _cost_row(cost: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	if cost.is_empty():
		h.add_child(_label("free", "MutedLabel"))
	for k in cost:
		h.add_child(_gem(k, 20))
		var l := _label(str(int(cost[k])))
		l.add_theme_font_size_override("font_size", 17)
		h.add_child(l)
	return h

# ---------------------------------------------------------------- build menu
func show_build(category: String) -> void:
	_open_panel("build", category, "Build")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	for cat in Config.CATEGORIES:
		var id: String = cat["id"]
		var btn := _button(cat["name"], "GoldButton" if id == category else "WoodButton",
			func() -> void: show_build(id))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		tabs.add_child(btn)
	_panel_body.add_child(tabs)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_panel_body.add_child(grid)

	for type in Config.BUILDINGS:
		var d: Dictionary = Config.BUILDINGS[type]
		if d["category"] != category:
			continue
		grid.add_child(_build_card(type, d))

	var hint := _label("Pick a building, drag it where you want it, then press Place.", "MutedLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.add_child(hint)

func _build_card(type: String, d: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(Thumb.building(type, 104))
	var name_l := _label(d["name"])
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_font_size_override("font_size", 16)
	col.add_child(name_l)
	col.add_child(_cost_row(d.get("cost", {})))
	var have := Game.count_type(type)
	var sub := "%d/%d" % [have, int(d["limit"])]
	if float(d["time"]) > 0.0:
		sub += "  %s" % BaseWorld._format_time(float(d["time"]))
	var sub_l := _label(sub, "MutedLabel")
	sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub_l)

	var err := ""
	if d.get("buildable", true) == false:
		err = "Already built"
	elif have >= int(d["limit"]):
		err = "Limit reached"
	elif not Game.can_afford(d.get("cost", {})):
		err = "Too expensive"
	if err != "":
		var e := _label(err, "MutedLabel")
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_theme_color_override("font_color", UiTheme.RED[2])
		col.add_child(e)
		card.modulate = Color(1, 1, 1, 0.55)
	else:
		var pick := _button("Build", "GreenButton", func() -> void:
			request_build.emit(type)
			hide_panel())
		pick.add_theme_font_size_override("font_size", 15)
		col.add_child(pick)
	card.add_child(col)
	return card

# ---------------------------------------------------------------- building info
func show_building(b: Dictionary) -> void:
	var d: Dictionary = Config.BUILDINGS[b["type"]]
	_open_panel("info", b["id"], "%s  Lv %d" % [d["name"], b["level"]])
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(Thumb.building(b["type"], 118))
	var blurb := _label(d["desc"], "MutedLabel")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.custom_minimum_size = Vector2(150, 0)
	top.add_child(blurb)
	_panel_body.add_child(top)

	if not Game.is_built(b):
		_row(_panel_body, "Under construction", BaseWorld._format_time(b["build_remaining"]))
	if int(d.get("hp", 0)) > 0:
		_row(_panel_body, "Hitpoints", str(int(d["hp"])))
	if d.has("produces"):
		var p: Dictionary = d["produces"]
		_row(_panel_body, "Production", "%d %s/min" % [int(float(p["per_second"]) * Game.production_multiplier() * 60.0), Config.RESOURCES[p["resource"]]["name"]])
		_row(_panel_body, "Stored", "%d/%d" % [int(b["stored"]), int(p["capacity"])])
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = float(p["capacity"])
		bar.value = b["stored"]
		var fill := StyleBoxFlat.new()
		fill.bg_color = Config.RESOURCES[p["resource"]]["color"]
		fill.set_corner_radius_all(8)
		bar.add_theme_stylebox_override("fill", fill)
		bar.custom_minimum_size = Vector2(0, 18)
		_panel_body.add_child(bar)
	var prov: Dictionary = d.get("provides", {})
	if prov.has("storage"):
		for k in prov["storage"]:
			_row(_panel_body, "%s capacity" % Config.RESOURCES[k]["name"], "+%d" % int(prov["storage"][k]))
	if prov.has("pop_cap"):
		_row(_panel_body, "Population capacity", "+%d" % int(prov["pop_cap"]))
	if prov.has("housing"):
		_row(_panel_body, "Army housing", "+%d%s" % [int(prov["housing"]), " (cavalry)" if prov.has("housing_for") else ""])
	if prov.has("happiness"):
		_row(_panel_body, "Happiness", "+%d" % int(prov["happiness"]))
	if prov.has("profession"):
		_row(_panel_body, "Employs", str(prov["profession"]))
	if prov.has("heal_speed"):
		_row(_panel_body, "Healing speed", "x%d" % int(prov["heal_speed"]))
	if d.has("defense"):
		var def: Dictionary = d["defense"]
		_row(_panel_body, "Range", "%.1f tiles" % float(def["range"]))
		_row(_panel_body, "Rate of fire", "%.1f/s" % (1.0 / float(def["rate"])))
		_row(_panel_body, "Damage", str(int(def["damage"])))
	if d.has("trains"):
		var names := []
		for t in d["trains"]:
			names.append(Config.UNITS[t]["name"])
		_row(_panel_body, "Trains", ", ".join(names))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	if d.has("produces") and Game.is_built(b):
		actions.add_child(_button("Collect %d" % int(b["stored"]), "GoldButton", func() -> void:
			var got := Game.collect(b)
			Sfx.play("collect" if got > 0 else "error")
			toast("+%d %s" % [int(got), Config.RESOURCES[d["produces"]["resource"]]["name"]] if got > 0 else "Storage is full.")
			show_building(b)))
	if d.has("trains") and Game.is_built(b):
		actions.add_child(_button("Train", "GreenButton", func() -> void: show_army()))
	if b["type"] == "castle":
		var up := _button("Upgrade", "GoldButton")
		up.disabled = true
		up.tooltip_text = "Castle Level Two is beyond this build."
		actions.add_child(up)
	actions.add_child(_button("Move", "WoodButton", func() -> void:
		request_move.emit(int(b["id"]))
		hide_panel()))
	if b["type"] != "castle":
		actions.add_child(_button("Demolish", "RedButton", func() -> void:
			Sfx.play("destroy")
			Game.remove_building(b)
			toast("Demolished. Half the cost came back.")
			hide_panel()))
	_panel_body.add_child(actions)

# ---------------------------------------------------------------- army
func show_army() -> void:
	_open_panel("army", null, "Army")
	var sum := Game.army_summary()
	_row(_panel_body, "Army housing", "%d/%d" % [sum["housing"], sum["housing_cap"]])
	_row(_panel_body, "Cavalry housing", "%d/%d" % [sum["cavalry"], sum["cavalry_cap"]])
	_row(_panel_body, "Ready / injured", "%d / %d" % [sum["ready"], sum["injured"]])

	for barracks in ["barracks_h"]:
		var bd: Dictionary = Config.BUILDINGS[barracks]
		_heading(_panel_body, bd["name"])
		if not Game.has_built(barracks):
			var note := "Under construction." if Game.count_type(barracks) > 0 else "Not built yet. Find it under Build, Army."
			_panel_body.add_child(_label(note, "MutedLabel"))
			continue
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_panel_body.add_child(grid)
		for type in bd["trains"]:
			grid.add_child(_unit_card(type))
		var queue: Array = Game.state["queues"][barracks]
		var q := HBoxContainer.new()
		q.add_theme_constant_override("separation", 6)
		if queue.is_empty():
			q.add_child(_label("Queue empty", "MutedLabel"))
		for i in queue.size():
			var item: Dictionary = queue[i]
			var idx := i
			var chip := _button("%s  %s" % [Config.UNITS[item["type"]]["name"], BaseWorld._format_time(item["remaining"])], "WoodButton",
				func() -> void:
					Game.cancel_training(barracks, idx)
					show_army())
			chip.add_theme_font_size_override("font_size", 14)
			chip.tooltip_text = "Tap to cancel"
			q.add_child(chip)
		_panel_body.add_child(q)

	_heading(_panel_body, "Roster")
	var roster := GridContainer.new()
	roster.columns = 4
	roster.add_theme_constant_override("h_separation", 6)
	roster.add_theme_constant_override("v_separation", 6)
	_panel_body.add_child(roster)
	roster.add_child(_roster_chip("king", "The King", Game.state["king"]["status"], Game.state["king"]["heal_remaining"], Game.state["king"]["bonded"]))
	for u in Game.state["army"]:
		var remaining: float = u["heal_remaining"] if u["status"] == "injured" else float(u.get("catch_remaining", 0.0))
		roster.add_child(_roster_chip(u["type"], Game.unit_name(u), u["status"], remaining, u["bonded"]))
	var note2 := _label("Every soldier bonds two Nivians, the King up to five. A Nivian lost in a raid sends its soldier to the forest for a while to bond another; the King catches his own there. Soldiers who fall may be lost for good; the injured heal faster with a Hospital.", "MutedLabel")
	note2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.add_child(note2)

func _unit_card(type: String) -> Control:
	var u: Dictionary = Config.UNITS[type]
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(Thumb.unit(type, 96))
	var n := _label(u["name"])
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	col.add_child(_cost_row(u["cost"]))
	var stat := _label("%d HP  %d ATK" % [int(u["hp"]), int(u["atk"])], "MutedLabel")
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(stat)
	var err := Game.train_error(type)
	if err == "":
		var b := _button("Train", "GreenButton", func() -> void:
			var e := Game.train(type)
			if e != "":
				Sfx.play("error")
				toast(e)
			else:
				Sfx.play("train")
			show_army())
		b.add_theme_font_size_override("font_size", 15)
		col.add_child(b)
	else:
		var e := _label(err, "MutedLabel")
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.add_theme_color_override("font_color", UiTheme.RED[2])
		col.add_child(e)
		card.modulate = Color(1, 1, 1, 0.6)
	card.add_child(col)
	return card

func _roster_chip(type: String, name: String, status: String, heal: float, bonded: Array = []) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.add_child(Thumb.unit(type, 64))
	var n := _label(name)
	n.add_theme_font_size_override("font_size", 14)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var status_text := "ready"
	if status == "injured":
		status_text = BaseWorld._format_time(heal / Game.capacities()["heal_speed"])
	elif status == "catching":
		status_text = "in the forest %s" % BaseWorld._format_time(heal)
	var s := _label(status_text, "MutedLabel")
	s.add_theme_font_size_override("font_size", 13)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	var names := []
	for kind in bonded:
		names.append(Config.UNITS[kind]["name"])
	var bl := _label(", ".join(names) if not names.is_empty() else "no Nivian", "MutedLabel")
	bl.add_theme_font_size_override("font_size", 12)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(bl)
	if status == "injured":
		card.modulate = Color(1, 0.8, 0.8, 0.85)
	elif status == "catching":
		card.modulate = Color(0.85, 1, 0.85, 0.9)
	card.add_child(col)
	return card

# ---------------------------------------------------------------- kingdom
func show_kingdom() -> void:
	_open_panel("kingdom", null, "Kingdom")
	var cap := Game.capacities()
	var hap := Game.happiness()
	_row(_panel_body, "Population", "%d/%d" % [Game.state["citizens"].size(), cap["pop_cap"]])
	_row(_panel_body, "Happiness", "%d%%" % hap)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = hap
	bar.custom_minimum_size = Vector2(0, 18)
	_panel_body.add_child(bar)
	var credits: int = Game.state["credits"]
	var align := "Beloved" if credits >= 20 else ("Respected" if credits > 0 else ("Neutral" if credits == 0 else ("Feared" if credits > -20 else "Tyrant")))
	_row(_panel_body, "Credits (karma)", "%d  %s" % [credits, align])
	_row(_panel_body, "Season", str(Game.state["season"]))
	var stats: Dictionary = Game.state["stats"]
	_row(_panel_body, "Born / passed away", "%d / %d" % [stats["born"], stats["died"]])

	_heading(_panel_body, "Decrees")
	var decrees := HBoxContainer.new()
	decrees.add_theme_constant_override("separation", 8)
	for id in Config.DECREES:
		var dd: Dictionary = Config.DECREES[id]
		var cd := float(Game.state["decree_cooldowns"].get(id, 0.0))
		var text: String = dd["name"] if cd <= 0.0 else "%s (%s)" % [dd["name"], BaseWorld._format_time(cd)]
		var btn := _button(text, "GreenButton" if id == "festival" else "GoldButton", func() -> void:
			var e := Game.decree(id)
			if e != "":
				Sfx.play("error")
				toast(e)
			else:
				Sfx.play("done" if id == "festival" else "collect")
			show_kingdom())
		btn.disabled = cd > 0.0
		btn.tooltip_text = dd["desc"]
		decrees.add_child(btn)
	_panel_body.add_child(decrees)
	var karma := _label("How you govern feeds the Credit system. High credits unlock rarer creatures such as Firon; a tyrant is left with the basics.", "MutedLabel")
	karma.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_body.add_child(karma)

	_heading(_panel_body, "Citizens")
	for c in Game.state["citizens"]:
		_row(_panel_body, "%s, %d" % [c["name"], c["age"]], c["profession"])

	_heading(_panel_body, "Creature types")
	for id in Config.CREATURES:
		var cr: Dictionary = Config.CREATURES[id]
		var t: Dictionary = Config.TYPE_RATIOS[cr["type"]]
		_row(_panel_body, "%s (%s)" % [cr["name"], cr["kin"]],
			"STR %d  MAG %d  DEF %d" % [int(t["strength"]), int(t["magic"]), int(t["defense"])])

	_heading(_panel_body, "Raids")
	_row(_panel_body, "Battles / wins / stars", "%d / %d / %d" % [stats["battles"], stats["wins"], stats["stars"]])
	_row(_panel_body, "Looted", "%d Serge, %d Jade" % [stats["looted_serge"], stats["looted_jade"]])
	_row(_panel_body, "Soldiers lost", str(stats["soldiers_lost"]))

	_heading(_panel_body, "Chronicle")
	var entries: Array = Game.state["log"]
	for i in mini(8, entries.size()):
		var e := _label(entries[i]["msg"], "MutedLabel")
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel_body.add_child(e)

# ---------------------------------------------------------------- place bar
func _build_place_bar(root: Control) -> void:
	_place_bar = PanelContainer.new()
	_place_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_place_bar.position = Vector2(0, -108)
	_place_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_place_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place_bar.visible = false
	root.add_child(_place_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_place_label = _label("")
	row.add_child(_place_label)
	_btn_place = _button("Place", "GreenButton", func() -> void: request_place_confirm.emit())
	row.add_child(_btn_place)
	_btn_cancel = _button("Cancel", "RedButton", func() -> void: request_place_cancel.emit())
	row.add_child(_btn_cancel)
	# Walls and roads commit as you drag, so there is nothing to "place" --
	# this one just ends the run.
	_btn_done = _button("Done", "GreenButton", func() -> void: request_place_cancel.emit())
	row.add_child(_btn_done)
	_place_bar.add_child(row)

## `line_mode` swaps the Place/Cancel pair for a single Done button, since a
## wall or road is already committed to the kingdom the instant it is dragged
## over, tile by tile -- there is nothing left to confirm.
func show_place_bar(type: String, line_mode := false) -> void:
	_place_label.text = ("Laying %s — drag across the ground" % Config.BUILDINGS[type]["name"]) if line_mode 		else "Placing %s" % Config.BUILDINGS[type]["name"]
	_btn_place.visible = not line_mode
	_btn_cancel.visible = not line_mode
	_btn_done.visible = line_mode
	_place_bar.visible = true

func hide_place_bar() -> void:
	_place_bar.visible = false

func set_place_valid(ok: bool) -> void:
	_place_label.modulate = Color.WHITE if ok else UiTheme.RED[1]

# ---------------------------------------------------------------- walking as the King
## An on-screen stick for phones and tablets: drag inside the ring, the King
## walks that way. Keyboard players just use WASD. Draws itself, so it needs
## no textures.
class Joystick extends Control:
	signal moved(vector: Vector2)
	const RADIUS := 64.0
	var _vec := Vector2.ZERO
	var _down := false
	func _init() -> void:
		custom_minimum_size = Vector2(RADIUS * 2, RADIUS * 2)
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _draw() -> void:
		var c := Vector2(RADIUS, RADIUS)
		draw_circle(c, RADIUS, Color(0.12, 0.08, 0.05, 0.55))
		draw_arc(c, RADIUS - 2.0, 0.0, TAU, 40, Color("e0bd82"), 3.0, true)
		draw_circle(c + _vec * (RADIUS - 22.0), 22.0, Color("e0bd82") if _down else Color(0.88, 0.74, 0.5, 0.8))
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			_down = event.is_pressed()
			_apply_stick(event.position if _down else Vector2(RADIUS, RADIUS))
			accept_event()
		elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _down:
			_apply_stick(event.position)
			accept_event()
	func _apply_stick(pos: Vector2) -> void:
		var v := (pos - Vector2(RADIUS, RADIUS)) / (RADIUS - 22.0)
		if v.length() > 1.0:
			v = v.normalized()
		if v.length() < 0.12:
			v = Vector2.ZERO
		_vec = v
		queue_redraw()
		moved.emit(v)

func _build_walk_bar(root: Control) -> void:
	_walk_bar = PanelContainer.new()
	_walk_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_walk_bar.position = Vector2(0, -14)
	_walk_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_walk_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_walk_bar.visible = false
	root.add_child(_walk_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_walk_hint = _label("")
	row.add_child(_walk_hint)
	row.add_child(_button("Throw", "GoldButton", func() -> void: request_throw.emit()))
	_btn_ride = _button("Ride", "", func() -> void: request_mount.emit())
	row.add_child(_btn_ride)
	_btn_view = _button("First person", "GreenButton", func() -> void: request_first_person.emit(world == null or not world.first_person))
	row.add_child(_btn_view)
	row.add_child(_button("Stop walking", "RedButton", func() -> void: request_walk.emit(false)))
	_walk_bar.add_child(row)

	_joystick = Joystick.new()
	_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joystick.position = Vector2(26, -Joystick.RADIUS * 2 - 26)
	_joystick.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_joystick.visible = false
	_joystick.moved.connect(func(v: Vector2) -> void: walk_input.emit(v))
	root.add_child(_joystick)

func show_walk_bar(on: bool) -> void:
	_walk_bar.visible = on
	_joystick.visible = on
	_bottom_bar.visible = not on
	if on:
		Sfx.play("open")
		_walk_hint.text = "Walking as the King: WASD, arrows or the stick. Cross the bridge east to the forest."
	refresh_walk_bar()

## Keeps the view toggle and the Ride label honest with what the world says.
func refresh_walk_bar() -> void:
	if world == null:
		return
	_btn_view.text = "Isometric view" if world.first_person else "First person"
	var bonded: Array = Game.state["king"]["bonded"]
	_btn_ride.disabled = bonded.is_empty()
	if world.mount != "":
		_btn_ride.text = "Riding %s" % Config.UNITS[world.mount]["name"]
	elif bonded.is_empty():
		_btn_ride.text = "Ride (no Nivian yet)"
	else:
		_btn_ride.text = "Ride"

# ---------------------------------------------------------------- toast
func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.theme_type_variation = "Plaque"
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(0, 118)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	root.add_child(_toast)
	_toast_label = _label("", "ValueLabel")
	_toast.add_child(_toast_label)

func toast(msg: String, seconds := 2.4) -> void:
	_toast_label.text = msg
	_toast.visible = true
	_toast_timer = seconds

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
	# keep live numbers fresh without rebuilding the panel every frame
	_refresh_timer += delta
	if _refresh_timer >= 0.5:
		_refresh_timer = 0.0
		refresh_top()
		if _walk_bar.visible and world != null:
			if world.king_in_forest():
				_walk_hint.text = "In the forest. Get within a few steps of a wild Nivian and Throw (Space), or tap it."
			elif world.first_person:
				_walk_hint.text = "Through the King's eyes: drag to look around, Q/E turn, WASD walks the way you face."
			else:
				_walk_hint.text = "Walking as the King: WASD, arrows or the stick. Cross the bridge east to the forest."
		if _panel.visible and _panel_kind == "info":
			var b := Game.find_building(int(_panel_arg))
			if b.is_empty():
				hide_panel()
			elif Config.BUILDINGS[b["type"]].has("produces") or not Game.is_built(b):
				show_building(b)

# ---------------------------------------------------------------- windows
func _build_modal(root: Control) -> void:
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	root.add_child(_modal)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.05, 0.01, 0.55)
	_modal.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(centre)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(540, 0)
	centre.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_modal_body)

func _open_modal(title: String) -> VBoxContainer:
	if not _modal.visible:
		Sfx.play("open")
	_modal.visible = true
	for c in _modal_body.get_children():
		c.queue_free()
	_heading(_modal_body, title)
	return _modal_body

func close_modal() -> void:
	if _modal.visible:
		Sfx.play("close")
	_modal.visible = false

func modal_open() -> bool:
	return _modal.visible

func show_attack() -> void:
	var body := _open_modal("Choose a Target")
	var ready := Game.ready_units().size()
	var intro := _label("You lead %d troop%s%s. Deploy them by tapping the ground, then direct them in the field." % [
		ready, "" if ready == 1 else "s",
		" and the King" if Game.state["king"]["status"] == "ready" else ""], "MutedLabel")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	if ready == 0 and Game.state["king"]["status"] != "ready":
		var warn := _label("Nobody is ready to fight. Train troops first.")
		warn.add_theme_color_override("font_color", UiTheme.RED[2])
		body.add_child(warn)
	for k in Config.ENEMY_KINGDOMS:
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		var col := VBoxContainer.new()
		col.add_child(_label(k["name"]))
		var desc := _label(k["desc"], "MutedLabel")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(desc)
		var loot := HBoxContainer.new()
		loot.add_theme_constant_override("separation", 6)
		loot.add_child(_gem("serge", 22))
		loot.add_child(_label(str(int(k["loot"]["serge"]))))
		loot.add_child(_gem("jade", 22))
		loot.add_child(_label(str(int(k["loot"]["jade"]))))
		loot.add_child(_label("   Cannons: %d" % int(k["cannons"]), "MutedLabel"))
		col.add_child(loot)
		var id: String = k["id"]
		col.add_child(_button("Attack", "RedButton", func() -> void:
			close_modal()
			request_attack.emit(id)))
		card.add_child(col)
		body.add_child(card)
	body.add_child(_button("Back", "WoodButton", func() -> void: close_modal()))

func show_menu() -> void:
	var body := _open_modal("Nivi")
	var blurb := _label("A kingdom builder at Castle Level One. Your progress saves itself.", "MutedLabel")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)
	body.add_child(_button("How to play", "", func() -> void: show_help()))
	_sound_toggles(body)
	body.add_child(_button("Save now", "GreenButton", func() -> void:
		Game.save_game()
		close_modal()
		toast("Kingdom saved.")))
	body.add_child(_button("New kingdom", "RedButton", func() -> void:
		close_modal()
		request_new_game.emit()))
	body.add_child(_button("Close", "WoodButton", func() -> void: close_modal()))

## Music and sound switches, remembered between sessions.
func _sound_toggles(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var music_btn := _button("", "", Callable())
	var sfx_btn := _button("", "", Callable())
	var label := func() -> void:
		music_btn.text = "Music: %s" % ("on" if Sfx.music_enabled else "off")
		music_btn.theme_type_variation = "GreenButton" if Sfx.music_enabled else "WoodButton"
		sfx_btn.text = "Sound: %s" % ("on" if Sfx.sfx_enabled else "off")
		sfx_btn.theme_type_variation = "GreenButton" if Sfx.sfx_enabled else "WoodButton"
	label.call()
	music_btn.pressed.connect(func() -> void:
		Sfx.music_enabled = not Sfx.music_enabled
		label.call())
	sfx_btn.pressed.connect(func() -> void:
		Sfx.sfx_enabled = not Sfx.sfx_enabled
		label.call())
	music_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(music_btn)
	row.add_child(sfx_btn)
	body.add_child(row)

func show_help() -> void:
	var body := _open_modal("How to Play")
	for line in [
		"Drag with one finger or the mouse to pan. Two fingers pan and pinch-zoom on a trackpad or touchscreen too.",
		"Scroll to zoom, or hold Q to zoom in and E to zoom out. WASD and the arrow keys pan.",
		"Tap a building to inspect it. Mines fill up over time, so tap them or press Collect.",
		"Build, pick a building, drag it where you want it and press Place.",
		"Walls and roads work differently: press down and drag across the ground in any direction to lay a whole run, the way Clash of Clans does. Press Done when you are finished, no need to confirm each tile.",
		"Homes raise the population. Every citizen bonds one Nivian, rarely two; the King can bond up to five.",
		"Press Walk (or K) to take the King on foot: WASD, the arrows or the on-screen stick move him and the camera follows. Cross the bridge east to the forest, get close to a wild Nivian and press Throw (Space) or tap it to throw a Nivian ball. The closer you are, the better it sticks.",
		"First person (or V) puts you behind the King's eyes: drag or Q/E to look around, WASD to walk the way you face. Ride climbs onto one of his Nivians for a faster trip; a Unitone is quickest. It works in raids too, once the King is deployed.",
		"Townsfolk and their Nivians walk the roads you lay and never leave them; with no roads they gather in the square before the Castle. Only the King goes wherever he pleases.",
		"A soldier who loses a Nivian in a raid walks to the forest on their own and comes back with another; the King's you catch yourself.",
		"Barracks H enlists citizens as soldiers. Each soldier automatically bonds two Nivians, who fight only when that soldier is sent into battle. Up to 15 soldiers, housed by Guard Stations, Outposts and the Cavalry Outpost.",
		"Attack picks a target. Deploy soldiers to the staging area, pick how many of each join the next order, then tap a building to send that squad, Nivians and all. Nobody attacks until told.",
		"Stars come from 50% destruction, the enemy Castle, and a clean sweep.",
		"Soldiers who fall may be lost for good. The rest heal, faster once you have a Hospital.",
	]:
		var l := _label("-  " + line, "MutedLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	body.add_child(_button("Close", "GreenButton", func() -> void: close_modal()))

func show_results(result: Dictionary, outcome: Dictionary, on_close: Callable) -> void:
	var stars := int(result["stars"])
	var body := _open_modal("%s  -  %s" % ["Victory" if stars > 0 else "Defeat", result["enemy_name"]])
	body.add_child(star_row(stars, 64))
	Sfx.play("victory" if stars > 0 else "defeat")
	body.add_child(_label(result["reason"], "MutedLabel"))
	_row(body, "Destruction", "%d%%" % int(round(float(result["destruction"]) * 100.0)))
	_row(body, "Loot", "%d Serge, %d Jade" % [int(result["loot"]["serge"]), int(result["loot"]["jade"])])
	_row(body, "Survivors", str(int(result["survivors"])))
	var dead := []
	for u in outcome["dead"]:
		dead.append(Config.UNITS[u["type"]]["name"])
	var hurt := []
	for u in outcome["injured"]:
		hurt.append(Config.UNITS[u["type"]]["name"])
	var lost_n := []
	for kind in outcome.get("nivians_lost", []):
		lost_n.append(Config.UNITS[kind]["name"])
	_row(body, "Lost for good", ", ".join(dead) if not dead.is_empty() else "none")
	_row(body, "Injured", ", ".join(hurt) if not hurt.is_empty() else "none")
	_row(body, "Nivians lost", ", ".join(lost_n) if not lost_n.is_empty() else "none")
	if not lost_n.is_empty():
		var fl := _label("Soldiers who lost a Nivian will walk to the forest for another. The King's must be caught by hand.", "MutedLabel")
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(fl)
	body.add_child(_button("Return home", "GreenButton", func() -> void:
		close_modal()
		on_close.call()))
