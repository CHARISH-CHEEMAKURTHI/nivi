class_name Island
extends Node3D
## A plateau of grass on open land. The buildable square sits in the middle;
## trees, rocks and bushes are scattered around it, or right across it for a
## forest. `grid_size` must be set (the home kingdom uses Config.GRID, a raid
## the smaller Config.BATTLE_GRID) before this node enters the tree.
##
## The valley floor beyond and the mountains that wall it in are built
## separately by `add_ground_and_mountains`, since the kingdom and the forest
## share one valley.

const TILE := 1.0       # world units per tile
const REFERENCE_GRID := 40.0   # the original plot size these numbers were tuned for

@export var grid_size := 40
@export var seed_value := 1
@export var decorate := true
## A forest plot has no buildable square to keep clear: the trees run right
## across it, thinning to a meadow in the middle where the wild Nivians graze.
@export var forest := false

var HALF := 20.0

func _ready() -> void:
	HALF = grid_size * TILE * 0.5
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grass_half := HALF + 3.0
	var top_b := MeshBuilder.new()
	top_b.rounded_slab(Vector3(0, -0.08, 0), Vector3(grass_half * 2, 0.1, grass_half * 2), 5.5, 7,
		Palette.GRASS_DARK, Palette.GRASS)
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("island_half", Vector2(grass_half, grass_half))
	grass_mat.set_shader_parameter("island_round", 5.5)
	add_child(MeshBuilder.instance(top_b.commit(), grass_mat))
	if decorate:
		_scatter(rng, grass_half)

## The valley floor stretching to the horizon, and the ring of mountains that
## walls it in around `rect` (in world X/Z). `pass_center`/`pass_width` leave
## a gap in the ring: the mountain pass an army marches in through.
static func add_ground_and_mountains(parent: Node3D, rect: Rect2, pass_center: Vector3, pass_width: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ground := MeshBuilder.new()
	var span := maxf(rect.size.x, rect.size.y) * 2.0 + 400.0
	ground.rounded_slab(Vector3(rect.get_center().x, -0.42, rect.get_center().y), Vector3(span, 0.4, span), 2.0, 2,
		Palette.DIRT_DARK, Palette.GRASS_DARK.darkened(0.12))
	parent.add_child(MeshBuilder.instance(ground.commit()))

	var rocks := MeshBuilder.new()
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.end.x
	var z1 := rect.end.y
	# walk the perimeter, dropping a peak every few units in two staggered rows
	var edges := [
		[Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(0, 0, -1)],
		[Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(1, 0, 0)],
		[Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3(0, 0, 1)],
		[Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3(-1, 0, 0)],
	]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var out: Vector3 = e[2]
		var length := a.distance_to(b)
		var along := (b - a) / length
		var t := 0.0
		while t < length + 3.0:
			for row in 2:
				var p: Vector3 = a + along * (t + row * 2.3) + out * (5.0 + row * 7.5)
				if pass_width > 0.0 and p.distance_to(pass_center) < pass_width * 0.5 + row * 3.0:
					continue
				var h := rng.randf_range(6.0, 13.0) + row * 4.0
				var r := rng.randf_range(3.2, 5.6) + row * 1.2
				var col: Color = Palette.ROCK_DARK if rng.randf() < 0.5 else Palette.ROCK
				var jitter := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
				rocks.cylinder(p + jitter + Vector3(0, -0.4, 0), r, 0.0, h, col, 7)
				if h > 12.0:
					rocks.cylinder(p + jitter + Vector3(0, h * 0.72 - 0.4, 0), r * 0.3, 0.0, h * 0.28 + 0.2, Palette.STONE_LIGHT, 7)
			# foothills on the inside of the ring
			if rng.randf() < 0.55:
				var f: Vector3 = a + along * (t + 1.2) + out * 1.6
				if pass_width <= 0.0 or f.distance_to(pass_center) > pass_width * 0.5:
					rocks.sphere(f + Vector3(0, 0.1, 0), rng.randf_range(0.8, 1.6), Palette.ROCK, 6, 4, 0.7)
			t += 4.6
	parent.add_child(MeshBuilder.instance(rocks.commit()))

## Trees, bushes and rocks, kept outside the buildable square. The count
## scales with the plot's perimeter (roughly how the ring of decoration
## outside the build area itself grows) so a much bigger plot does not read
## as mostly bare.
func _scatter(rng: RandomNumberGenerator, grass_half: float) -> void:
	var b := MeshBuilder.new()
	var placed: Array[Vector2] = []
	var target := int(62 * (float(grid_size) / REFERENCE_GRID))
	var spacing := 1.9
	if forest:
		# wooded end to end rather than a ring: about one tree per nine tiles
		target = int(grass_half * grass_half * 4.0 / 9.0)
		spacing = 2.2
	var tries := 0
	while placed.size() < target and tries < target * 24:
		tries += 1
		var p := Vector2(rng.randf_range(-grass_half + 0.9, grass_half - 0.9), rng.randf_range(-grass_half + 0.9, grass_half - 0.9))
		if forest:
			# a meadow in the middle for the Nivians, and a clear lane in from
			# the kingdom on the north side
			if p.length() < 6.0 or (absf(p.x) < 1.8 and p.y < -grass_half + 9.0):
				continue
		elif abs(p.x) < HALF + 0.6 and abs(p.y) < HALF + 0.6:
			# keep the building area clear
			continue
		var clash := false
		for q in placed:
			if p.distance_to(q) < spacing:
				clash = true
				break
		if clash:
			continue
		placed.append(p)
		var roll: float = rng.randf()
		if roll < (0.8 if forest else 0.62):
			_tree(b, Vector3(p.x, 0, p.y), rng)
		elif roll < (0.94 if forest else 0.85):
			_bush(b, Vector3(p.x, 0, p.y), rng)
		else:
			_rock(b, Vector3(p.x, 0, p.y), rng)
	add_child(MeshBuilder.instance(b.commit()))

func _tree(b: MeshBuilder, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(1.5, 2.4)
	var lean := rng.randf_range(-0.06, 0.06)
	b.cylinder(pos, 0.17, 0.12, h, Palette.WOOD_DARK, 7)
	var leaf: Color = Palette.LEAF if rng.randf() < 0.6 else Palette.LEAF_DARK
	var top := pos + Vector3(lean, h, lean)
	b.sphere(top + Vector3(0, 0.45, 0), rng.randf_range(0.80, 1.05), leaf, 9, 6, 0.86)
	b.sphere(top + Vector3(0.42, 0.08, 0.16), rng.randf_range(0.48, 0.66), leaf.darkened(0.08), 8, 5, 0.9)
	b.sphere(top + Vector3(-0.34, 0.16, -0.26), rng.randf_range(0.46, 0.62), leaf.lightened(0.10), 8, 5, 0.9)

func _bush(b: MeshBuilder, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.42, 0.62)
	b.sphere(pos + Vector3(0, r * 0.72, 0), r, Palette.LEAF_LIGHT, 8, 5, 0.78)
	b.sphere(pos + Vector3(r * 0.7, r * 0.5, r * 0.2), r * 0.72, Palette.LEAF, 7, 4, 0.8)
	if rng.randf() < 0.4:
		b.sphere(pos + Vector3(-r * 0.5, r * 0.44, -r * 0.5), r * 0.6, Palette.LEAF_DARK, 7, 4, 0.8)

func _rock(b: MeshBuilder, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.34, 0.62)
	b.sphere(pos + Vector3(0, r * 0.5, 0), r, Palette.ROCK, 6, 4, 0.72)
	if rng.randf() < 0.6:
		b.sphere(pos + Vector3(r * 0.9, r * 0.28, r * 0.35), r * 0.6, Palette.ROCK_DARK, 6, 3, 0.7)
