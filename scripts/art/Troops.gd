class_name Troops
extends RefCounted
## Soldiers, creatures and the King, modelled the same way as the buildings.
## Each stands on y = 0 facing -Z, roughly one tile tall at most.

static func build(type: String) -> Mesh:
	var b := MeshBuilder.new()
	match type:
		"knight": _knight(b)
		"cavalry": _cavalry(b)
		"king": _king(b)
		"unitone": _unitone(b)
		"firon": _firon(b)
		"garuan": _garuan(b)
		_: b.box(Vector3.ZERO, Vector3(0.3, 0.6, 0.3), Palette.CLOTH_BLUE)
	return b.commit()

static func _person(b: MeshBuilder, tunic: Color, trim: Color, helm: Color, scale := 1.0) -> void:
	var s := scale
	# legs, body, arms, head
	b.box(Vector3(-0.09 * s, 0, 0), Vector3(0.1 * s, 0.22 * s, 0.11 * s), Palette.WOOD_DARK)
	b.box(Vector3(0.09 * s, 0, 0), Vector3(0.1 * s, 0.22 * s, 0.11 * s), Palette.WOOD_DARK)
	b.box(Vector3(0, 0.22 * s, 0), Vector3(0.3 * s, 0.3 * s, 0.2 * s), tunic)
	b.box(Vector3(0, 0.3 * s, -0.02 * s), Vector3(0.33 * s, 0.09 * s, 0.22 * s), trim)
	b.box(Vector3(-0.19 * s, 0.24 * s, 0), Vector3(0.09 * s, 0.26 * s, 0.1 * s), tunic)
	b.box(Vector3(0.19 * s, 0.24 * s, 0), Vector3(0.09 * s, 0.26 * s, 0.1 * s), tunic)
	b.box(Vector3(0, 0.52 * s, 0), Vector3(0.19 * s, 0.17 * s, 0.18 * s), Palette.SKIN)
	b.box(Vector3(0, 0.63 * s, 0), Vector3(0.23 * s, 0.11 * s, 0.22 * s), helm)
	b.box(Vector3(0, 0.71 * s, 0), Vector3(0.09 * s, 0.08 * s, 0.09 * s), helm)

static func _knight(b: MeshBuilder) -> void:
	_person(b, Palette.CLOTH_BLUE, Palette.IRON, Palette.IRON)
	# shield and spear
	b.box(Vector3(-0.26, 0.24, -0.04), Vector3(0.06, 0.26, 0.2), Palette.CLOTH_RED)
	b.cylinder(Vector3(0.26, 0.1, 0.02), 0.022, 0.022, 0.78, Palette.WOOD_DARK, 5)
	b.cylinder(Vector3(0.26, 0.88, 0.02), 0.04, 0.0, 0.14, Palette.IRON, 5)

static func _cavalry(b: MeshBuilder) -> void:
	# mount
	b.box(Vector3(0, 0.3, 0.02), Vector3(0.34, 0.26, 0.66), Palette.WOOD)
	b.box(Vector3(0, 0.3, -0.3), Vector3(0.22, 0.3, 0.2), Palette.WOOD)
	b.box(Vector3(0, 0.56, -0.36), Vector3(0.18, 0.18, 0.26), Palette.WOOD_LIGHT)
	for sx in [-0.13, 0.13]:
		for sz in [-0.22, 0.22]:
			b.box(Vector3(sx, 0, sz), Vector3(0.09, 0.3, 0.09), Palette.WOOD_DARK)
	b.box(Vector3(0, 0.34, 0.36), Vector3(0.1, 0.24, 0.1), Palette.WOOD_DARK)
	# rider
	var r := MeshBuilder.new()
	_person(r, Palette.CLOTH_RED, Palette.GOLD, Palette.IRON, 0.85)
	b.box(Vector3(0, 0.56, 0.0), Vector3(0.26, 0.26, 0.18), Palette.CLOTH_RED)
	b.box(Vector3(0, 0.82, 0.0), Vector3(0.17, 0.15, 0.16), Palette.SKIN)
	b.box(Vector3(0, 0.92, 0.0), Vector3(0.21, 0.1, 0.2), Palette.IRON)
	b.cylinder(Vector3(0.2, 0.5, 0.02), 0.022, 0.022, 0.72, Palette.WOOD_DARK, 5)
	b.cylinder(Vector3(0.2, 1.22, 0.02), 0.04, 0.0, 0.13, Palette.IRON, 5)

static func _king(b: MeshBuilder) -> void:
	_person(b, Palette.PURPLE, Palette.GOLD, Palette.GOLD, 1.12)
	# crown points and a cape
	for i in 3:
		b.box(Vector3(-0.08 + i * 0.08, 0.82, 0), Vector3(0.05, 0.08, 0.05), Palette.GOLD)
	b.box(Vector3(0, 0.3, 0.13), Vector3(0.3, 0.42, 0.05), Palette.CLOTH_RED)
	b.cylinder(Vector3(0.3, 0.12, 0.02), 0.025, 0.025, 0.86, Palette.WOOD_DARK, 5)
	b.box(Vector3(0.3, 0.98, 0.02), Vector3(0.16, 0.16, 0.06), Palette.GOLD)

static func _unitone(b: MeshBuilder) -> void:
	var body := Color("4fa8ff")
	var dark := Color("2b6fc4")
	b.box(Vector3(0, 0.26, 0.02), Vector3(0.3, 0.24, 0.6), body)
	b.box(Vector3(0, 0.3, -0.28), Vector3(0.2, 0.26, 0.18), body)
	b.box(Vector3(0, 0.52, -0.34), Vector3(0.16, 0.16, 0.24), Color("bfe4ff"))
	b.box(Vector3(0, 0.64, -0.3), Vector3(0.07, 0.1, 0.07), Palette.JADE)
	for sx in [-0.11, 0.11]:
		for sz in [-0.2, 0.2]:
			b.box(Vector3(sx, 0, sz), Vector3(0.08, 0.27, 0.08), dark)
	b.box(Vector3(0, 0.3, 0.33), Vector3(0.08, 0.2, 0.1), dark)

static func _firon(b: MeshBuilder) -> void:
	var body := Color("ff7a3c")
	var dark := Color("b8461b")
	b.box(Vector3(0, 0.22, 0), Vector3(0.44, 0.34, 0.56), body)
	b.box(Vector3(0, 0.5, -0.26), Vector3(0.28, 0.24, 0.24), body)
	b.box(Vector3(-0.1, 0.72, -0.26), Vector3(0.1, 0.1, 0.08), dark)
	b.box(Vector3(0.1, 0.72, -0.26), Vector3(0.1, 0.1, 0.08), dark)
	b.box(Vector3(0, 0.5, -0.4), Vector3(0.14, 0.12, 0.08), Color("ffd08a"))
	for sx in [-0.16, 0.16]:
		for sz in [-0.18, 0.18]:
			b.box(Vector3(sx, 0, sz), Vector3(0.14, 0.24, 0.14), dark)

static func _garuan(b: MeshBuilder) -> void:
	var body := Color("d8b27a")
	var dark := Color("a3804e")
	b.box(Vector3(0, 0.2, 0.06), Vector3(0.3, 0.36, 0.34), body)
	b.box(Vector3(0, 0.5, -0.06), Vector3(0.24, 0.22, 0.26), body)
	b.box(Vector3(-0.07, 0.7, -0.06), Vector3(0.07, 0.16, 0.07), dark)
	b.box(Vector3(0.07, 0.7, -0.06), Vector3(0.07, 0.16, 0.07), dark)
	b.box(Vector3(0, 0.5, -0.2), Vector3(0.12, 0.1, 0.08), Palette.SKIN)
	b.box(Vector3(0, 0, 0.02), Vector3(0.26, 0.22, 0.3), dark)
	b.box(Vector3(0, 0.06, 0.34), Vector3(0.12, 0.12, 0.34), dark)
	for sx in [-0.16, 0.16]:
		b.box(Vector3(sx, 0.3, 0.0), Vector3(0.08, 0.22, 0.08), body)
