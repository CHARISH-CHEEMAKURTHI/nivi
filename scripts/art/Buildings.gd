class_name Buildings
extends RefCounted
## Every Castle Level One structure, modelled from coloured primitives.
## Each model is centred on the origin in X/Z, sits on y = 0, and fits inside
## its footprint in tiles (1 tile = 1 world unit).

const MARGIN := 0.12

static func footprint(type: String) -> Vector2i:
	match type:
		"castle": return Vector2i(4, 4)
		"barracks_h", "barracks_l": return Vector2i(3, 3)
		"farm", "tavern", "hospital", "cavalry_outpost": return Vector2i(3, 2)
		"road", "wall", "builder_hut": return Vector2i(1, 1)
		_: return Vector2i(2, 2)

static func build(type: String) -> Mesh:
	var b := MeshBuilder.new()
	match type:
		"castle": _castle(b)
		"barracks_h": _barracks_h(b)
		"barracks_l": _barracks_l(b)
		"serge_mine": _mine(b, Palette.SERGE, Palette.SERGE_DARK)
		"jade_mine": _mine(b, Palette.JADE, Palette.JADE_DARK)
		"serge_storage": _serge_storage(b)
		"jade_storage": _jade_storage(b)
		"home": _home(b)
		"farm": _farm(b)
		"shop": _shop(b)
		"tavern": _tavern(b)
		"hospital": _hospital(b)
		"road": _road(b)
		"wall": _wall(b)
		"builder_hut": _builder_hut(b)
		"guard_station": _guard_station(b)
		"outpost": _outpost(b)
		"cavalry_outpost": _cavalry_outpost(b)
		"cannon": _cannon(b)
		_: b.box(Vector3.ZERO, Vector3(1, 1, 1), Palette.STONE)
	return b.commit()

# --- shared pieces ----------------------------------------------------------
static func _plinth(b: MeshBuilder, size: Vector2, h := 0.18, col := Palette.STONE_DARK) -> void:
	b.rounded_slab(Vector3(0, 0, 0), Vector3(size.x, h, size.y), 0.35, 3, col, col.lightened(0.12))

static func _banner(b: MeshBuilder, pos: Vector3, h: float, cloth: Color) -> void:
	b.cylinder(pos, 0.045, 0.045, h, Palette.WOOD_DARK, 5)
	b.box(pos + Vector3(0.04, h - 0.42, -0.06), Vector3(0.34, 0.3, 0.06), cloth)
	b.sphere(pos + Vector3(0, h + 0.05, 0), 0.07, Palette.GOLD, 6, 4)

static func _crenellations(b: MeshBuilder, center: Vector3, size: Vector2, step: float, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var x := -hx
	while x < hx - 0.01:
		var w: float = minf(step * 0.55, hx - x)
		b.box(Vector3(center.x + x + w * 0.5, center.y, center.z - hz + 0.09), Vector3(w, 0.2, 0.18), col)
		b.box(Vector3(center.x + x + w * 0.5, center.y, center.z + hz - 0.09), Vector3(w, 0.2, 0.18), col)
		x += step
	var z := -hz + step
	while z < hz - step - 0.01:
		b.box(Vector3(center.x - hx + 0.09, center.y, center.z + z), Vector3(0.18, 0.2, step * 0.55), col)
		b.box(Vector3(center.x + hx - 0.09, center.y, center.z + z), Vector3(0.18, 0.2, step * 0.55), col)
		z += step

static func _ore_pile(b: MeshBuilder, center: Vector3, r: float, col: Color, dark: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf() * 0.4
		var d := r * rng.randf_range(0.2, 0.8)
		var s := rng.randf_range(0.10, 0.19)
		b.box(center + Vector3(cos(a) * d, 0, sin(a) * d), Vector3(s, s * 1.5, s),
			col if i % 2 == 0 else dark, rng.randf() * TAU)

# --- the castle -------------------------------------------------------------
static func _castle(b: MeshBuilder) -> void:
	var s := 4.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.16, Palette.STONE_DARK)
	# curtain wall
	var wall_h := 0.85
	b.box(Vector3(0, 0.16, -s * 0.5 + 0.18), Vector3(s, wall_h, 0.36), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.box(Vector3(0, 0.16, s * 0.5 - 0.18), Vector3(s, wall_h, 0.36), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.box(Vector3(-s * 0.5 + 0.18, 0.16, 0), Vector3(0.36, wall_h, s), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.box(Vector3(s * 0.5 - 0.18, 0.16, 0), Vector3(0.36, wall_h, s), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	_crenellations(b, Vector3(0, 0.16 + wall_h, 0), Vector2(s, s), 0.52, Palette.STONE_LIGHT)
	# courtyard floor
	b.box(Vector3(0, 0.16, 0), Vector3(s - 0.7, 0.05, s - 0.7), Palette.STONE_DARK, 0.0, Palette.STONE_DARK.lightened(0.1))
	# corner towers
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (s * 0.5 - 0.16), 0.0, sz * (s * 0.5 - 0.16))
			b.cylinder(p, 0.34, 0.31, 1.5, Palette.STONE_LIGHT, 10, Palette.STONE)
			b.cylinder(p + Vector3(0, 1.5, 0), 0.38, 0.36, 0.14, Palette.STONE, 10)
			b.cylinder(p + Vector3(0, 1.64, 0), 0.4, 0.0, 0.62, Palette.PURPLE, 10)
	# keep
	b.box(Vector3(0, 0.21, 0), Vector3(1.75, 1.5, 1.75), Palette.STONE_LIGHT, 0.0, Palette.STONE)
	_crenellations(b, Vector3(0, 1.71, 0), Vector2(1.75, 1.75), 0.44, Palette.STONE)
	b.box(Vector3(0, 1.71, 0), Vector3(1.15, 0.5, 1.15), Palette.STONE_LIGHT)
	b.pyramid(Vector3(0, 2.21, 0), Vector3(1.35, 0.85, 1.35), Palette.PURPLE, 0.0, 0.08)
	_banner(b, Vector3(0, 3.0, 0), 0.7, Palette.CLOTH_RED)
	# windows and gate
	for sx2 in [-0.45, 0.45]:
		b.box(Vector3(sx2, 0.85, -0.89), Vector3(0.2, 0.34, 0.06), Palette.IRON_DARK)
	b.box(Vector3(0, 0.16, -s * 0.5 + 0.1), Vector3(0.62, 0.72, 0.2), Palette.WOOD_DARK)
	b.box(Vector3(0, 0.88, -s * 0.5 + 0.1), Vector3(0.62, 0.1, 0.22), Palette.WOOD)

# --- barracks ---------------------------------------------------------------
static func _barracks_h(b: MeshBuilder) -> void:
	var s := 3.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.14, Palette.DIRT)
	b.box(Vector3(-0.3, 0.14, 0), Vector3(1.95, 0.95, 2.1), Palette.PLASTER, 0.0, Palette.PLASTER)
	# timber framing
	for x in [-1.16, -0.44, 0.28]:
		b.box(Vector3(x, 0.14, -1.07), Vector3(0.1, 0.95, 0.06), Palette.WOOD_DARK)
	b.gable(Vector3(-0.3, 1.09, 0), Vector3(1.95, 0.8, 2.1), Palette.ROOF_RED, 0.0, 0.16)
	# shield over the door
	b.box(Vector3(-0.3, 0.55, -1.09), Vector3(0.36, 0.42, 0.07), Palette.CLOTH_BLUE)
	b.box(Vector3(-0.3, 0.68, -1.13), Vector3(0.1, 0.24, 0.04), Palette.STONE_LIGHT)
	b.box(Vector3(-0.3, 0.74, -1.13), Vector3(0.28, 0.08, 0.04), Palette.STONE_LIGHT)
	# training yard
	b.cylinder(Vector3(0.95, 0.14, 0.62), 0.07, 0.07, 0.62, Palette.WOOD_DARK, 6)
	b.box(Vector3(0.95, 0.62, 0.62), Vector3(0.44, 0.16, 0.16), Palette.THATCH)
	b.box(Vector3(0.95, 0.76, 0.62), Vector3(0.18, 0.16, 0.16), Palette.THATCH_DARK)
	# weapon rack
	b.box(Vector3(0.98, 0.14, -0.72), Vector3(0.5, 0.08, 0.14), Palette.WOOD)
	for i in 3:
		b.cylinder(Vector3(0.82 + i * 0.16, 0.2, -0.72), 0.03, 0.03, 0.66, Palette.WOOD_DARK, 5)
		b.cylinder(Vector3(0.82 + i * 0.16, 0.86, -0.72), 0.05, 0.0, 0.16, Palette.IRON, 5)
	_banner(b, Vector3(-1.2, 0.14, 0.95), 1.35, Palette.CLOTH_RED)

static func _barracks_l(b: MeshBuilder) -> void:
	var s := 3.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.14, Palette.DIRT)
	b.box(Vector3(-0.3, 0.14, 0), Vector3(1.95, 0.95, 2.1), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.gable(Vector3(-0.3, 1.09, 0), Vector3(1.95, 0.78, 2.1), Palette.ROOF_TEAL, 0.0, 0.16)
	# summoning circle in the yard
	b.cylinder(Vector3(0.92, 0.14, 0.0), 0.62, 0.62, 0.04, Palette.STONE_LIGHT, 16)
	b.cylinder(Vector3(0.92, 0.18, 0.0), 0.46, 0.46, 0.02, Palette.ROOF_TEAL, 16)
	b.cylinder(Vector3(0.92, 0.2, 0.0), 0.26, 0.26, 0.02, Palette.STONE_LIGHT, 12)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		b.box(Vector3(0.92 + cos(a) * 0.52, 0.18, sin(a) * 0.52), Vector3(0.12, 0.3, 0.12), Palette.ROOF_TEAL)
	# crystal on the gable
	b.cylinder(Vector3(-0.3, 1.82, 0), 0.12, 0.0, 0.34, Palette.JADE, 6)
	# paw mark by the door
	b.box(Vector3(-0.3, 0.6, -1.09), Vector3(0.3, 0.26, 0.06), Palette.PLASTER)
	b.box(Vector3(-0.3, 0.72, -1.12), Vector3(0.22, 0.1, 0.04), Palette.ROOF_TEAL)

# --- resources --------------------------------------------------------------
static func _mine(b: MeshBuilder, ore: Color, ore_dark: Color) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.DIRT_DARK)
	# rocky mound
	b.cylinder(Vector3(0.1, 0.12, 0.12), 0.72, 0.4, 0.68, Palette.ROCK_DARK, 8, Palette.ROCK)
	b.cylinder(Vector3(-0.44, 0.12, -0.32), 0.34, 0.2, 0.4, Palette.ROCK_DARK, 7)
	# ore seams breaking out of the rock face
	b.box(Vector3(-0.36, 0.5, 0.28), Vector3(0.2, 0.26, 0.2), ore, 0.6)
	b.box(Vector3(0.52, 0.42, 0.34), Vector3(0.17, 0.22, 0.17), ore_dark, 0.9)
	b.box(Vector3(0.34, 0.62, -0.22), Vector3(0.15, 0.2, 0.15), ore, 0.3)
	# tunnel mouth
	b.box(Vector3(0.0, 0.12, -0.66), Vector3(0.56, 0.5, 0.2), Color(0.09, 0.07, 0.06))
	b.box(Vector3(-0.32, 0.12, -0.72), Vector3(0.1, 0.62, 0.12), Palette.WOOD)
	b.box(Vector3(0.32, 0.12, -0.72), Vector3(0.1, 0.62, 0.12), Palette.WOOD)
	b.box(Vector3(0.0, 0.7, -0.72), Vector3(0.74, 0.11, 0.14), Palette.WOOD_LIGHT)
	# ore heaped by the tunnel mouth, ready to collect
	_ore_pile(b, Vector3(0.1, 0.8, 0.14), 0.34, ore, ore_dark, 7)
	_ore_pile(b, Vector3(-0.02, 0.12, -0.34), 0.34, ore, ore_dark, 3)
	# cart rails
	for i in 4:
		b.box(Vector3(0.0, 0.12, -0.82 + i * 0.0), Vector3(0.5, 0.03, 0.05), Palette.IRON_DARK)

static func _serge_storage(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.DIRT)
	b.box(Vector3(0, 0.12, 0), Vector3(1.3, 0.72, 1.3), Palette.WOOD, 0.0, Palette.WOOD_DARK)
	for y in [0.26, 0.6]:
		b.box(Vector3(0, y, 0), Vector3(1.38, 0.09, 1.38), Palette.IRON_DARK)
	for sx in [-0.65, 0.65]:
		b.box(Vector3(sx, 0.12, 0), Vector3(0.1, 0.72, 0.16), Palette.WOOD_LIGHT)
	_ore_pile(b, Vector3(0, 0.84, 0), 0.5, Palette.SERGE, Palette.SERGE_DARK, 11)

static func _jade_storage(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.STONE_DARK)
	b.box(Vector3(0, 0.12, 0), Vector3(1.3, 0.78, 1.3), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.box(Vector3(0, 0.9, 0), Vector3(1.42, 0.1, 1.42), Palette.STONE_LIGHT)
	b.box(Vector3(0, 0.12, -0.67), Vector3(0.44, 0.52, 0.08), Palette.IRON_DARK)
	_ore_pile(b, Vector3(0, 1.0, 0), 0.46, Palette.JADE, Palette.JADE_DARK, 5)

# --- support ----------------------------------------------------------------
static func _home(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.DIRT)
	b.box(Vector3(0, 0.12, 0), Vector3(1.24, 0.72, 1.12), Palette.PLASTER, 0.0, Palette.PLASTER)
	for x in [-0.42, 0.42]:
		b.box(Vector3(x, 0.12, -0.57), Vector3(0.08, 0.72, 0.05), Palette.WOOD_DARK)
	b.gable(Vector3(0, 0.84, 0), Vector3(1.24, 0.6, 1.12), Palette.THATCH, 0.0, 0.14)
	b.box(Vector3(0, 0.12, -0.58), Vector3(0.3, 0.5, 0.06), Palette.WOOD_DARK)
	b.box(Vector3(-0.42, 0.5, -0.59), Vector3(0.22, 0.2, 0.05), Palette.ROOF_BLUE)
	b.box(Vector3(0.4, 0.98, 0.2), Vector3(0.22, 0.46, 0.22), Palette.ROCK, 0.0, Palette.ROCK_DARK)

static func _farm(b: MeshBuilder) -> void:
	_plinth(b, Vector2(3.0 - MARGIN * 2, 2.0 - MARGIN * 2), 0.1, Palette.DIRT_DARK)
	# ploughed rows
	for i in 5:
		var z := -0.68 + i * 0.34
		b.box(Vector3(-0.35, 0.1, z), Vector3(1.85, 0.09, 0.2), Palette.DIRT)
		for j in 6:
			b.sphere(Vector3(-1.2 + j * 0.34, 0.22, z), 0.09, Palette.LEAF_LIGHT, 6, 4, 0.8)
	# fence
	for i in 7:
		b.cylinder(Vector3(-1.34 + i * 0.29, 0.1, -0.88), 0.035, 0.035, 0.3, Palette.WOOD, 5)
		b.cylinder(Vector3(-1.34 + i * 0.29, 0.1, 0.88), 0.035, 0.035, 0.3, Palette.WOOD, 5)
	b.box(Vector3(-0.35, 0.3, -0.88), Vector3(1.9, 0.05, 0.05), Palette.WOOD_LIGHT)
	b.box(Vector3(-0.35, 0.3, 0.88), Vector3(1.9, 0.05, 0.05), Palette.WOOD_LIGHT)
	# barn
	b.box(Vector3(1.05, 0.1, 0), Vector3(0.8, 0.6, 1.1), Palette.PLASTER)
	b.gable(Vector3(1.05, 0.7, 0), Vector3(0.8, 0.46, 1.1), Palette.ROOF_RED, 0.0, 0.12)
	b.box(Vector3(1.05, 0.1, -0.56), Vector3(0.28, 0.42, 0.05), Palette.WOOD_DARK)

static func _shop(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.STONE_DARK)
	b.box(Vector3(0, 0.12, 0.2), Vector3(1.2, 0.68, 0.76), Palette.PLASTER)
	b.gable(Vector3(0, 0.8, 0.2), Vector3(1.2, 0.44, 0.76), Palette.ROOF_SLATE, 0.0, 0.1)
	# striped awning
	for i in 5:
		var col: Color = Palette.CLOTH_RED if i % 2 == 0 else Palette.PLASTER
		b.box(Vector3(-0.48 + i * 0.24, 0.74, -0.34), Vector3(0.24, 0.06, 0.56), col)
	# counter with wares
	b.box(Vector3(0, 0.12, -0.42), Vector3(1.2, 0.34, 0.3), Palette.WOOD, 0.0, Palette.WOOD_LIGHT)
	b.box(Vector3(-0.32, 0.46, -0.42), Vector3(0.18, 0.14, 0.18), Palette.JADE)
	b.box(Vector3(0.0, 0.46, -0.42), Vector3(0.18, 0.14, 0.18), Palette.SERGE)
	b.box(Vector3(0.32, 0.46, -0.42), Vector3(0.18, 0.14, 0.18), Palette.CLOTH_BLUE)

static func _tavern(b: MeshBuilder) -> void:
	_plinth(b, Vector2(3.0 - MARGIN * 2, 2.0 - MARGIN * 2), 0.12, Palette.STONE_DARK)
	b.box(Vector3(-0.15, 0.12, 0), Vector3(2.0, 0.85, 1.4), Palette.WOOD, 0.0, Palette.WOOD_LIGHT)
	for x in [-1.0, -0.35, 0.3, 0.8]:
		b.box(Vector3(x, 0.12, -0.72), Vector3(0.08, 0.85, 0.05), Palette.WOOD_DARK)
	b.gable(Vector3(-0.15, 0.97, 0), Vector3(2.0, 0.58, 1.4), Palette.ROOF_SLATE, 0.0, 0.16)
	b.box(Vector3(-0.15, 0.12, -0.73), Vector3(0.36, 0.56, 0.06), Palette.WOOD_DARK)
	# hanging sign with a mug
	b.box(Vector3(0.95, 0.9, -0.72), Vector3(0.5, 0.06, 0.06), Palette.WOOD_DARK)
	b.box(Vector3(1.14, 0.54, -0.72), Vector3(0.34, 0.32, 0.05), Palette.THATCH)
	b.cylinder(Vector3(1.14, 0.6, -0.75), 0.09, 0.09, 0.16, Palette.GOLD, 8)
	b.box(Vector3(0.6, 0.98, 0.78), Vector3(0.24, 0.5, 0.24), Palette.ROCK, 0.0, Palette.ROCK_DARK)

static func _hospital(b: MeshBuilder) -> void:
	_plinth(b, Vector2(3.0 - MARGIN * 2, 2.0 - MARGIN * 2), 0.12, Palette.STONE_DARK)
	b.box(Vector3(0, 0.12, 0), Vector3(2.1, 0.86, 1.4), Color("f7f3ea"), 0.0, Color("fdfbf6"))
	b.gable(Vector3(0, 0.98, 0), Vector3(2.1, 0.5, 1.4), Palette.ROOF_SLATE, 0.0, 0.16)
	# red cross
	b.box(Vector3(0, 0.62, -0.73), Vector3(0.44, 0.16, 0.05), Palette.CLOTH_RED)
	b.box(Vector3(0, 0.48, -0.73), Vector3(0.16, 0.44, 0.05), Palette.CLOTH_RED)
	for x in [-0.72, 0.72]:
		b.box(Vector3(x, 0.4, -0.72), Vector3(0.3, 0.3, 0.05), Palette.ROOF_BLUE)
	b.box(Vector3(0, 0.12, 0.72), Vector3(0.4, 0.56, 0.05), Palette.WOOD)

static func _road(b: MeshBuilder) -> void:
	b.rounded_slab(Vector3(0, 0, 0), Vector3(0.98, 0.07, 0.98), 0.14, 2, Palette.ROCK_DARK, Palette.ROCK)
	b.box(Vector3(-0.22, 0.07, -0.22), Vector3(0.36, 0.02, 0.36), Palette.ROCK_LIGHT)
	b.box(Vector3(0.24, 0.07, 0.2), Vector3(0.34, 0.02, 0.32), Palette.ROCK_LIGHT)

static func _wall(b: MeshBuilder) -> void:
	b.box(Vector3(0, 0, 0), Vector3(0.92, 0.78, 0.92), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	b.box(Vector3(0, 0.78, 0), Vector3(1.0, 0.1, 1.0), Palette.STONE_LIGHT)
	for sx in [-0.31, 0.31]:
		for sz in [-0.31, 0.31]:
			b.box(Vector3(sx, 0.88, sz), Vector3(0.3, 0.18, 0.3), Palette.STONE_LIGHT)

# --- the builder's hut -------------------------------------------------------
static func _builder_hut(b: MeshBuilder) -> void:
	var s := 1.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.10, Palette.DIRT)
	# a small canvas pup-tent, big enough for one busy builder
	b.gable(Vector3(0, 0.10, 0), Vector3(0.62, 0.48, 0.6), Palette.THATCH, 0.0, 0.08)
	b.box(Vector3(0, 0.10, 0.02), Vector3(0.05, 0.3, 0.05), Palette.WOOD_DARK)
	# a leaning hammer and a small pile of planks out front
	b.box(Vector3(0.3, 0.28, -0.28), Vector3(0.05, 0.3, 0.05), Palette.WOOD_DARK, 0.5)
	b.box(Vector3(0.33, 0.42, -0.25), Vector3(0.14, 0.07, 0.09), Palette.IRON, 0.5)
	b.box(Vector3(-0.24, 0.13, -0.3), Vector3(0.3, 0.05, 0.1), Palette.WOOD)
	b.box(Vector3(-0.24, 0.19, -0.3), Vector3(0.28, 0.05, 0.09), Palette.WOOD_LIGHT)

# --- military ---------------------------------------------------------------
static func _guard_station(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.14, Palette.STONE_DARK)
	b.box(Vector3(-0.1, 0.14, 0), Vector3(1.2, 0.95, 1.2), Palette.STONE, 0.0, Palette.STONE_LIGHT)
	_crenellations(b, Vector3(-0.1, 1.09, 0), Vector2(1.2, 1.2), 0.4, Palette.STONE_LIGHT)
	b.box(Vector3(-0.1, 0.14, -0.62), Vector3(0.34, 0.56, 0.06), Palette.WOOD_DARK)
	b.box(Vector3(-0.42, 0.66, -0.63), Vector3(0.2, 0.2, 0.05), Palette.IRON_DARK)
	# spear rack
	for i in 3:
		b.cylinder(Vector3(0.62, 0.14, -0.3 + i * 0.28), 0.03, 0.03, 0.78, Palette.WOOD_DARK, 5)
		b.cylinder(Vector3(0.62, 0.92, -0.3 + i * 0.28), 0.05, 0.0, 0.18, Palette.IRON, 5)
	_banner(b, Vector3(-0.72, 0.14, 0.66), 1.2, Palette.CLOTH_BLUE)

static func _outpost(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.12, Palette.DIRT)
	# legs
	for sx in [-0.42, 0.42]:
		for sz in [-0.42, 0.42]:
			b.box(Vector3(sx, 0.12, sz), Vector3(0.13, 1.15, 0.13), Palette.WOOD_DARK)
	for y in [0.5, 0.9]:
		b.box(Vector3(0, y, -0.42), Vector3(0.96, 0.06, 0.06), Palette.WOOD)
		b.box(Vector3(0, y, 0.42), Vector3(0.96, 0.06, 0.06), Palette.WOOD)
	# platform, railing and roof
	b.box(Vector3(0, 1.27, 0), Vector3(1.3, 0.12, 1.3), Palette.WOOD, 0.0, Palette.WOOD_LIGHT)
	for sz2 in [-0.6, 0.6]:
		b.box(Vector3(0, 1.39, sz2), Vector3(1.3, 0.3, 0.08), Palette.WOOD_LIGHT)
	for sx2 in [-0.6, 0.6]:
		b.box(Vector3(sx2, 1.39, 0), Vector3(0.08, 0.3, 1.3), Palette.WOOD_LIGHT)
	for sx3 in [-0.52, 0.52]:
		b.cylinder(Vector3(sx3, 1.69, -0.52), 0.05, 0.05, 0.42, Palette.WOOD_DARK, 5)
		b.cylinder(Vector3(sx3, 1.69, 0.52), 0.05, 0.05, 0.42, Palette.WOOD_DARK, 5)
	b.pyramid(Vector3(0, 2.11, 0), Vector3(1.4, 0.5, 1.4), Palette.ROOF_RED, 0.0, 0.12)
	# ladder
	for i in 4:
		b.box(Vector3(0, 0.3 + i * 0.26, -0.72), Vector3(0.4, 0.05, 0.05), Palette.WOOD_LIGHT)

static func _cavalry_outpost(b: MeshBuilder) -> void:
	_plinth(b, Vector2(3.0 - MARGIN * 2, 2.0 - MARGIN * 2), 0.12, Palette.DIRT)
	# stable
	b.box(Vector3(-0.72, 0.12, 0), Vector3(1.4, 0.85, 1.5), Palette.WOOD, 0.0, Palette.WOOD_LIGHT)
	b.gable(Vector3(-0.72, 0.97, 0), Vector3(1.4, 0.52, 1.5), Palette.ROOF_RED, 0.0, 0.14)
	b.box(Vector3(-0.72, 0.12, -0.78), Vector3(0.62, 0.62, 0.06), Color(0.12, 0.09, 0.07))
	# paddock
	for i in 5:
		b.cylinder(Vector3(0.1 + i * 0.32, 0.12, -0.8), 0.04, 0.04, 0.42, Palette.WOOD, 5)
		b.cylinder(Vector3(0.1 + i * 0.32, 0.12, 0.8), 0.04, 0.04, 0.42, Palette.WOOD, 5)
	b.box(Vector3(0.74, 0.44, -0.8), Vector3(1.5, 0.06, 0.06), Palette.WOOD_LIGHT)
	b.box(Vector3(0.74, 0.44, 0.8), Vector3(1.5, 0.06, 0.06), Palette.WOOD_LIGHT)
	b.cylinder(Vector3(1.42, 0.12, 0), 0.04, 0.04, 0.42, Palette.WOOD, 5)
	b.box(Vector3(1.42, 0.44, 0), Vector3(0.06, 0.06, 1.6), Palette.WOOD_LIGHT)
	# hay and trough
	b.cylinder(Vector3(0.62, 0.12, 0.3), 0.26, 0.26, 0.34, Palette.THATCH, 8, Palette.THATCH_DARK)
	b.box(Vector3(1.0, 0.12, -0.3), Vector3(0.5, 0.18, 0.28), Palette.WOOD_DARK)

static func _cannon(b: MeshBuilder) -> void:
	var s := 2.0 - MARGIN * 2.0
	_plinth(b, Vector2(s, s), 0.14, Palette.STONE_DARK)
	b.cylinder(Vector3(0, 0.14, 0), 0.66, 0.6, 0.3, Palette.STONE, 12, Palette.STONE_LIGHT)
	b.cylinder(Vector3(0, 0.44, 0), 0.42, 0.38, 0.18, Palette.STONE_LIGHT, 10)
	# carriage and stubby barrel
	b.box(Vector3(0, 0.62, 0), Vector3(0.5, 0.22, 0.6), Palette.WOOD_DARK)
	b.cylinder(Vector3(0, 0.78, -0.1), 0.22, 0.2, 0.62, Palette.IRON_DARK, 10, Palette.IRON)
	b.cylinder(Vector3(0, 0.74, 0.22), 0.26, 0.26, 0.14, Palette.IRON, 10)
	# wheels
	for sx in [-0.3, 0.3]:
		b.cylinder(Vector3(sx, 0.5, 0.18), 0.22, 0.22, 0.09, Palette.WOOD, 10, Palette.WOOD_LIGHT)
	# charging crystals
	b.box(Vector3(0.48, 0.44, -0.4), Vector3(0.14, 0.2, 0.14), Palette.JADE)
	b.box(Vector3(-0.48, 0.44, -0.36), Vector3(0.12, 0.16, 0.12), Palette.JADE)
