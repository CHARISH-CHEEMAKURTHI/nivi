class_name Thumb
extends RefCounted
## Little 3D previews for the build menu and army cards. Each one is a tiny
## viewport holding the real model, lit the same way as the world, rendered
## once and then reused.

static func viewport_for_mesh(mesh: Mesh, size := 128, frame := 2.4, height := 0.9) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	# Its own world, or the preview's lights and camera would join the island
	# and wash the whole scene out.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("dfeaf2")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	vp.msaa_3d = Viewport.MSAA_4X

	var mi := MeshBuilder.instance(mesh)
	vp.add_child(mi)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 140, 0)
	light.light_energy = 1.35
	light.light_color = Color("fff3d8")
	vp.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -40, 0)
	fill.light_energy = 0.45
	fill.light_color = Color("cfe0ea")
	vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = frame
	# Aimed by building the transform directly: look_at() needs the node to be
	# inside the tree, and this camera is set up before the viewport is added.
	cam.transform = Transform3D(Basis(), Vector3(7, 7, 7)).looking_at(Vector3(0, height, 0), Vector3.UP)
	cam.near = 0.05
	cam.far = 40.0
	vp.add_child(cam)
	return vp

static func building(type: String, size := 128) -> Control:
	var fp := Buildings.footprint(type)
	var frame: float = maxf(fp.x, fp.y) * 1.25 + 0.9
	return _wrap(viewport_for_mesh(Buildings.build(type), size, frame, frame * 0.22), size)

static func unit(type: String, size := 108) -> Control:
	return _wrap(viewport_for_mesh(Troops.build(type), size, 2.1, 0.55), size)

static func _wrap(vp: SubViewport, size: int) -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(size, size)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(vp)
	return box
