class_name WorldEnv
extends RefCounted
## Sunlight, sky and ambient tuning shared by the base and the raid scenes.

static func make_environment() -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("2f7fd0")
	mat.sky_horizon_color = Color("bfe3f5")
	mat.ground_bottom_color = Color("2f6ea0")
	mat.ground_horizon_color = Color("bfe3f5")
	mat.sun_angle_max = 22.0
	mat.sun_curve = 0.12
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfe0ea")
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = 1.0
	env.fog_enabled = false
	we.environment = env
	return we

static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 132, 0)
	sun.light_energy = 1.4
	sun.light_color = Color("fff3d8")
	sun.shadow_enabled = true
	# Leave directional_shadow_mode at its default of four parallel splits: the
	# single-split ORTHOGONAL mode spreads one map over the whole view distance
	# and the shadows fall away entirely at this scale.
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	return sun
