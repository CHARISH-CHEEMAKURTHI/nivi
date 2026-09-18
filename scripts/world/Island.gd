class_name Island
extends Node3D
## The world the base sits on: a grass plateau ringed by beach, standing in an
## open sea, with trees, rocks and bushes scattered around the buildable area.
## `grid_size` must be set (BaseWorld uses the home Config.GRID, a raid uses
## the smaller Config.BATTLE_GRID) before this node enters the tree, since it
## drives everything built in _ready().

const TILE := 1.0       # world units per tile
const REFERENCE_GRID := 40.0   # the original island size these numbers were tuned for

@export var grid_size := 40
@export var seed_value := 1
@export var decorate := true
## The home island owns the sea; a second island placed on the same water
## (the forest) leaves it out rather than stacking two planes.
@export var sea := true
## A forest island has no buildable plot to keep clear: the trees run right
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
	var sand_half := grass_half + 2.6

	# --- sea ---------------------------------------------------------------
	if sea:
		var sea_mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		var sea_size: float = maxf(420.0, sand_half * 2.0 + 180.0)
		plane.size = Vector2(sea_size, sea_size)
		plane.subdivide_width = 96
		plane.subdivide_depth = 96
		sea_mi.mesh = plane
		var water_mat := ShaderMaterial.new()
		water_mat.shader = load("res://shaders/water.gdshader")
		water_mat.set_shader_parameter("island_half", Vector2(sand_half, sand_half))
		water_mat.set_shader_parameter("island_round", 7.0)
		sea_mi.material_override = water_mat
		sea_mi.position.y = -0.62
		sea_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sea_mi)

	# --- beach -------------------------------------------------------------
	var beach_b := MeshBuilder.new()
	beach_b.rounded_slab(Vector3(0, -1.6, 0), Vector3(sand_half * 2, 1.4, sand_half * 2), 7.0, 7,
		Palette.SAND_DARK, Palette.SAND)
	add_child(MeshBuilder.instance(beach_b.commit()))

	# --- grass plateau -----------------------------------------------------
	var soil_b := MeshBuilder.new()
	soil_b.rounded_slab(Vector3(0, -1.3, 0), Vector3(grass_half * 2, 1.2, grass_half * 2), 5.5, 7,
		Palette.DIRT, Palette.DIRT_DARK)
	add_child(MeshBuilder.instance(soil_b.commit()))

	var top_b := MeshBuilder.new()
	top_b.rounded_slab(Vector3(0, -0.1, 0), Vector3(grass_half * 2, 0.1, grass_half * 2), 5.5, 7,
		Palette.GRASS_DARK, Palette.GRASS)
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("island_half", Vector2(grass_half, grass_half))
	grass_mat.set_shader_parameter("island_round", 5.5)
	var top := MeshBuilder.instance(top_b.commit(), grass_mat)
	add_child(top)

	if decorate:
		_scatter(rng, grass_half)

## Trees, bushes and rocks, kept outside the buildable square. The count
## scales with the island's perimeter (roughly how the ring of decoration
## outside the build area itself grows) so a much bigger island does not read
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
			# the bridge on the west side
			if p.length() < 6.0 or (absf(p.y) < 1.8 and p.x < -grass_half + 9.0):
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
