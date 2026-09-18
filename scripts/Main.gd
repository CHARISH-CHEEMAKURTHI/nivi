extends Node3D
## Showcase: every Castle Level One building laid out on the island.

const LAYOUT := [
	["castle", 0, -2], ["barracks_h", -6, -6], ["barracks_l", 6, -6],
	["serge_mine", -10, 0], ["jade_mine", 10, 0],
	["serge_storage", -10, 4], ["jade_storage", 10, 4],
	["home", -5, 3], ["home", -2, 3], ["home", 1, 3],
	["farm", 5, 4], ["shop", -8, -3], ["tavern", 5, 8], ["hospital", -5, 8],
	["guard_station", -9, -9], ["outpost", 9, -9], ["cavalry_outpost", 1, 8],
	["cannon", -3, -7], ["cannon", 3, -7],
]

func _ready() -> void:
	add_child(WorldEnv.make_environment())
	add_child(WorldEnv.make_sun())
	add_child(Island.new())

	for entry in LAYOUT:
		var type: String = entry[0]
		var fp := Buildings.footprint(type)
		var mi := MeshBuilder.instance(Buildings.build(type))
		# snap to the tile grid: a footprint's centre lands on a half-tile when the
		# footprint is odd, on a whole tile when it is even
		mi.position = Vector3(float(entry[1]) + (0.0 if fp.x % 2 == 0 else 0.5), 0.0,
			float(entry[2]) + (0.0 if fp.y % 2 == 0 else 0.5))
		add_child(mi)

	# a short stretch of wall and road to show them in context
	for i in 9:
		var w := MeshBuilder.instance(Buildings.build("wall"))
		w.position = Vector3(-4.5 + i, 0, -10.5)
		add_child(w)
	for i in 6:
		var r := MeshBuilder.instance(Buildings.build("road"))
		r.position = Vector3(0.5, 0.0, 1.5 + i)
		add_child(r)

	var rig := CameraRig.new()
	add_child(rig)
	rig.set_zoom(15.0)
	rig.focus_on(Vector3(0, 0, -2))
