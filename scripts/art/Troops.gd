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

## A townsperson for the streets: the same figure as a soldier, in one of a
## few plain tunics picked by `seed`, without helmet or weapons.
static func citizen(seed: int) -> Mesh:
	var b := MeshBuilder.new()
	var tunics := [Palette.CLOTH_BLUE, Palette.CLOTH_RED, Palette.ROOF_TEAL, Palette.THATCH_DARK, Palette.PURPLE, Palette.LEAF]
	var hair := [Palette.WOOD_DARK, Palette.THATCH, Palette.IRON_DARK, Palette.WOOD]
	_person(b, tunics[seed % tunics.size()], Palette.WOOD, hair[(seed / 3) % hair.size()], 0.92)
	return b.commit()

static func _person(b: MeshBuilder, tunic: Color, trim: Color, helm: Color, scale := 1.0, origin := Vector3.ZERO) -> void:
	var s := scale
	var o := origin
	# legs, body, arms, head
	b.box(o + Vector3(-0.09 * s, 0, 0), Vector3(0.1 * s, 0.22 * s, 0.11 * s), Palette.WOOD_DARK)
	b.box(o + Vector3(0.09 * s, 0, 0), Vector3(0.1 * s, 0.22 * s, 0.11 * s), Palette.WOOD_DARK)
	b.box(o + Vector3(0, 0.22 * s, 0), Vector3(0.3 * s, 0.3 * s, 0.2 * s), tunic)
	b.box(o + Vector3(0, 0.3 * s, -0.02 * s), Vector3(0.33 * s, 0.09 * s, 0.22 * s), trim)
	b.box(o + Vector3(-0.19 * s, 0.24 * s, 0), Vector3(0.09 * s, 0.26 * s, 0.1 * s), tunic)
	b.box(o + Vector3(0.19 * s, 0.24 * s, 0), Vector3(0.09 * s, 0.26 * s, 0.1 * s), tunic)
	b.box(o + Vector3(0, 0.52 * s, 0), Vector3(0.19 * s, 0.17 * s, 0.18 * s), Palette.SKIN)
	b.box(o + Vector3(0, 0.63 * s, 0), Vector3(0.23 * s, 0.11 * s, 0.22 * s), helm)
	b.box(o + Vector3(0, 0.71 * s, 0), Vector3(0.09 * s, 0.08 * s, 0.09 * s), helm)

static func _knight(b: MeshBuilder) -> void:
	_person(b, Palette.CLOTH_BLUE, Palette.IRON, Palette.IRON)
	# shield and spear
	b.box(Vector3(-0.26, 0.24, -0.04), Vector3(0.06, 0.26, 0.2), Palette.CLOTH_RED)
	b.cylinder(Vector3(0.26, 0.1, 0.02), 0.022, 0.022, 0.78, Palette.WOOD_DARK, 5)
	b.cylinder(Vector3(0.26, 0.88, 0.02), 0.04, 0.0, 0.14, Palette.IRON, 5)

static func _cavalry(b: MeshBuilder) -> void:
	_unitone(b)
	_rider_figure(b, "cavalry")

## A soldier or the King riding their bonded Unitone: the water-horse with a
## figure in the saddle. `type` picks the rider's colours and weapon.
static func rider(type: String) -> Mesh:
	var b := MeshBuilder.new()
	_unitone(b)
	_rider_figure(b, type)
	return b.commit()

static func _rider_figure(b: MeshBuilder, type: String) -> void:
	var seat := Vector3(0, 0.58, 0.02)
	match type:
		"king":
			_person(b, Palette.PURPLE, Palette.GOLD, Palette.GOLD, 0.9, seat)
			for i in 3:
				b.box(seat + Vector3(-0.07 + i * 0.07, 0.72, 0), Vector3(0.045, 0.07, 0.045), Palette.GOLD)
			b.box(seat + Vector3(0, 0.26, 0.11), Vector3(0.27, 0.36, 0.045), Palette.CLOTH_RED)
			b.beam(seat + Vector3(0.24, 0.35, 0.02), seat + Vector3(0.24, 1.0, 0.02), 0.022, Palette.WOOD_DARK)
			b.box(seat + Vector3(0.24, 1.0, 0.02), Vector3(0.14, 0.14, 0.05), Palette.GOLD)
		"knight":
			_person(b, Palette.CLOTH_BLUE, Palette.IRON, Palette.IRON, 0.85, seat)
			b.box(seat + Vector3(-0.22, 0.2, -0.03), Vector3(0.05, 0.22, 0.17), Palette.CLOTH_RED)
			b.beam(seat + Vector3(0.22, 0.1, 0.02), seat + Vector3(0.22, 0.86, 0.02), 0.02, Palette.WOOD_DARK)
			b.cylinder(seat + Vector3(0.22, 0.86, 0.02), 0.035, 0.0, 0.12, Palette.IRON, 5)
		_:
			_person(b, Palette.CLOTH_RED, Palette.GOLD, Palette.IRON, 0.85, seat)
			# a lance couched forward
			b.beam(seat + Vector3(0.2, 0.4, 0.1), seat + Vector3(0.16, 0.5, -0.8), 0.022, Palette.WOOD_DARK, 0.012)
			b.cylinder(seat + Vector3(0.16, 0.5, -0.8), 0.03, 0.0, 0.1, Palette.IRON, 5)
	# stirrups and reins
	for sx in [-0.16, 0.16]:
		b.box(seat + Vector3(sx, -0.22, 0.02), Vector3(0.05, 0.05, 0.08), Palette.IRON_DARK)
	b.beam(seat + Vector3(-0.05, 0.18, -0.08), Vector3(-0.05, 0.9, -0.62), 0.008, Palette.WOOD_DARK)

static func _king(b: MeshBuilder) -> void:
	_person(b, Palette.PURPLE, Palette.GOLD, Palette.GOLD, 1.12)
	# crown points and a cape
	for i in 3:
		b.box(Vector3(-0.08 + i * 0.08, 0.82, 0), Vector3(0.05, 0.08, 0.05), Palette.GOLD)
	b.box(Vector3(0, 0.3, 0.13), Vector3(0.3, 0.42, 0.05), Palette.CLOTH_RED)
	b.cylinder(Vector3(0.3, 0.12, 0.02), 0.025, 0.025, 0.86, Palette.WOOD_DARK, 5)
	b.box(Vector3(0.3, 0.98, 0.02), Vector3(0.16, 0.16, 0.06), Palette.GOLD)


## The Unitone: the water-kin steed. A horse's build -- deep chest, arched
## neck, long head, four slim legs -- in river blues, with a mane and tail
## that stream out as pale, glowing water rather than hair.
static func _unitone(b: MeshBuilder) -> void:
	var body := Color("4fa8ff")
	var dark := Color("2b6fc4")
	var glow := Color("bfe4ff")
	var pale := Color("8fd0ff")
	# barrel, chest and rump
	b.ellipsoid(Vector3(0, 0.52, 0.02), Vector3(0.17, 0.17, 0.36), body)
	b.ellipsoid(Vector3(0, 0.54, -0.22), Vector3(0.16, 0.17, 0.16), body)
	b.ellipsoid(Vector3(0, 0.55, 0.28), Vector3(0.16, 0.16, 0.15), dark)
	# neck, arched up and forward
	b.beam(Vector3(0, 0.6, -0.28), Vector3(0, 0.9, -0.5), 0.1, body, 0.075, 7)
	# head and muzzle
	b.ellipsoid(Vector3(0, 0.93, -0.57), Vector3(0.075, 0.085, 0.15), body)
	b.ellipsoid(Vector3(0, 0.88, -0.7), Vector3(0.055, 0.055, 0.07), pale)
	for sx in [-0.045, 0.045]:
		b.beam(Vector3(sx, 0.99, -0.53), Vector3(sx * 1.4, 1.09, -0.51), 0.02, body, 0.006, 5)
		b.box(Vector3(sx * 1.4, 0.94, -0.65), Vector3(0.025, 0.025, 0.02), Palette.JADE)
	# legs: shoulder/hip down to a dark hoof
	for sx in [-0.09, 0.09]:
		for sz in [-0.22, 0.24]:
			var top := Vector3(sx, 0.44, sz)
			var knee := Vector3(sx * 1.05, 0.22, sz + (0.02 if sz > 0.0 else -0.02))
			var foot := Vector3(sx * 1.05, 0.0, sz)
			b.beam(top, knee, 0.05, body, 0.038, 6)
			b.beam(knee, foot, 0.036, dark, 0.03, 6)
			b.box(foot, Vector3(0.07, 0.04, 0.08), Palette.IRON_DARK)
	# mane: pale water streaming back along the crest
	var crest := [Vector3(0, 0.98, -0.5), Vector3(0, 0.92, -0.42), Vector3(0, 0.84, -0.35), Vector3(0, 0.76, -0.28)]
	for i in crest.size():
		var c: Vector3 = crest[i]
		b.sphere(c + Vector3(0, 0.05, 0), 0.06 - i * 0.006, glow, 6, 4, 1.0)
		b.sphere(c + Vector3(0.02, 0.1, 0.05 + i * 0.01), 0.04, pale, 5, 3, 1.3)
	# tail
	b.beam(Vector3(0, 0.58, 0.42), Vector3(0, 0.36, 0.62), 0.05, glow, 0.02, 6)
	b.sphere(Vector3(0, 0.3, 0.66), 0.05, pale, 5, 3, 1.4)
	b.sphere(Vector3(0.02, 0.44, 0.58), 0.045, glow, 5, 3, 1.0)

## The Firon: fire-kin, built like a bear. A low, heavy body on four thick
## legs, a broad head with a short muzzle and round ears, dark hide with
## ember-orange markings burning along the spine and shoulders.
static func _firon(b: MeshBuilder) -> void:
	var hide := Color("4a2a1e")
	var hide_dark := Color("34190f")
	var ember := Color("ff7a3c")
	var flame := Color("ffb347")
	b.ellipsoid(Vector3(0, 0.42, 0.02), Vector3(0.27, 0.3, 0.4), hide)
	b.ellipsoid(Vector3(0, 0.5, -0.2), Vector3(0.25, 0.26, 0.2), hide)
	# head, muzzle, ears, eyes
	b.ellipsoid(Vector3(0, 0.62, -0.42), Vector3(0.16, 0.15, 0.16), hide)
	b.ellipsoid(Vector3(0, 0.56, -0.56), Vector3(0.085, 0.07, 0.09), Color("6b4030"))
	b.box(Vector3(0, 0.6, -0.65), Vector3(0.05, 0.035, 0.03), hide_dark)
	for sx in [-0.11, 0.11]:
		b.sphere(Vector3(sx, 0.76, -0.4), 0.05, hide_dark, 6, 4)
		b.box(Vector3(sx * 0.6, 0.64, -0.57), Vector3(0.03, 0.03, 0.02), ember)
	# legs and paws
	for sx in [-0.16, 0.16]:
		for sz in [-0.22, 0.24]:
			b.beam(Vector3(sx, 0.3, sz), Vector3(sx * 1.1, 0.0, sz + 0.02), 0.085, hide, 0.07, 6)
			b.box(Vector3(sx * 1.1, 0.0, sz + 0.02), Vector3(0.16, 0.06, 0.17), hide_dark)
			for k in 3:
				b.box(Vector3(sx * 1.1 - 0.05 + k * 0.05, 0.0, sz - 0.07 + (0.0 if sz < 0.0 else 0.04)), Vector3(0.03, 0.03, 0.04), ember)
	# embers along the spine and shoulders, a sun mark on the flank
	for i in 6:
		var z := -0.28 + i * 0.12
		b.sphere(Vector3(0, 0.74 - absf(z) * 0.2, z), 0.05 - i * 0.003, ember if i % 2 == 0 else flame, 5, 3, 1.4)
	for sx in [-0.26, 0.26]:
		b.sphere(Vector3(sx, 0.48, 0.04), 0.06, ember, 6, 4, 0.5)
		b.sphere(Vector3(sx * 1.05, 0.48, 0.04), 0.035, flame, 5, 3, 0.5)
	# a short tail
	b.sphere(Vector3(0, 0.42, 0.44), 0.06, hide_dark, 5, 4)

## The Garuan: ground-kin, built like a kangaroo. Stands upright on two
## powerful legs and a thick counterbalancing tail, small forearms tucked in,
## tall ears, a pouch on the belly. Sandy hide with a darker back.
static func _garuan(b: MeshBuilder) -> void:
	var hide := Color("d8b27a")
	var dark := Color("a3804e")
	var belly := Color("efdcb5")
	# upright body, leaning a touch forward
	b.ellipsoid(Vector3(0, 0.5, 0.0), Vector3(0.16, 0.27, 0.15), hide)
	b.ellipsoid(Vector3(0, 0.42, -0.08), Vector3(0.11, 0.13, 0.07), belly)
	b.ellipsoid(Vector3(0, 0.58, 0.07), Vector3(0.13, 0.2, 0.1), dark)
	# head, muzzle, ears
	b.ellipsoid(Vector3(0, 0.88, -0.08), Vector3(0.09, 0.1, 0.13), hide)
	b.ellipsoid(Vector3(0, 0.84, -0.21), Vector3(0.05, 0.05, 0.07), dark)
	b.box(Vector3(0, 0.86, -0.28), Vector3(0.03, 0.025, 0.02), Color("3b2a1a"))
	for sx in [-0.05, 0.05]:
		b.beam(Vector3(sx, 0.95, -0.06), Vector3(sx * 1.9, 1.13, -0.03), 0.032, hide, 0.012, 5)
		b.box(Vector3(sx * 1.3, 0.9, -0.19), Vector3(0.025, 0.025, 0.02), Color("3b2a1a"))
	# forearms tucked in
	for sx in [-0.14, 0.14]:
		b.beam(Vector3(sx, 0.62, -0.04), Vector3(sx * 1.1, 0.5, -0.15), 0.032, hide, 0.026, 5)
		b.sphere(Vector3(sx * 1.1, 0.49, -0.16), 0.03, dark, 5, 3)
	# thighs, shins and the long feet
	for sx in [-0.12, 0.12]:
		b.ellipsoid(Vector3(sx, 0.3, 0.06), Vector3(0.08, 0.13, 0.1), hide)
		b.beam(Vector3(sx * 1.1, 0.2, 0.12), Vector3(sx * 1.15, 0.05, 0.02), 0.04, dark, 0.035, 5)
		b.box(Vector3(sx * 1.15, 0.0, -0.06), Vector3(0.08, 0.06, 0.3), dark)
	# tail, thick at the base and resting on the ground behind
	b.beam(Vector3(0, 0.3, 0.14), Vector3(0, 0.05, 0.55), 0.075, hide, 0.03, 6)
	b.sphere(Vector3(0, 0.04, 0.57), 0.035, dark, 5, 3)
