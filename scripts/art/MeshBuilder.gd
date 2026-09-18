class_name MeshBuilder
extends RefCounted
## Builds low-poly models out of coloured primitives, all baked into one mesh.
## Every face gets its own vertices and a flat normal, which gives the crisp
## faceted look of a stylised strategy game once the sun and shadows hit it.
## Colour lives in the vertex data, so a whole building needs only one material.

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.specular = 0.12
	return m

## Wrap a built mesh in a ready-to-use instance with the shared material and
## the shadow mode two-sided geometry needs.
static func instance(mesh: Mesh, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat != null else material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

## Adds a triangle whose outward side is the one you get from the right-hand
## rule on (a, b, c). Godot treats the OPPOSITE winding as front-facing, and a
## two-sided material flips the normal on back-facing fragments, which would
## light the face from behind -- so the indices are emitted reversed to keep the
## visible side and the normal in agreement.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	var base := _v.size()
	for p in [a, b, c]:
		_v.push_back(p)
		_n.push_back(nrm)
		_c.push_back(col)
	_i.push_back(base); _i.push_back(base + 2); _i.push_back(base + 1)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri(a, b, c, col)
	tri(a, c, d, col)

## Axis-aligned box. `pos` is the centre of its base, so things sit on the ground.
func box(pos: Vector3, size: Vector3, col: Color, yaw := 0.0, top_col := Color(0, 0, 0, 0)) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := pos.y
	var y1 := pos.y + size.y
	var corners: Array[Vector2] = [Vector2(-hx, -hz), Vector2(-hx, hz), Vector2(hx, hz), Vector2(hx, -hz)]
	var p: Array[Vector2] = []
	for c2: Vector2 in corners:
		var r: Vector2 = c2.rotated(yaw)
		p.append(Vector2(pos.x + r.x, pos.z + r.y))
	var top: Color = top_col if top_col.a > 0.0 else col
	# top and bottom
	quad(Vector3(p[0].x, y1, p[0].y), Vector3(p[1].x, y1, p[1].y), Vector3(p[2].x, y1, p[2].y), Vector3(p[3].x, y1, p[3].y), top)
	quad(Vector3(p[3].x, y0, p[3].y), Vector3(p[2].x, y0, p[2].y), Vector3(p[1].x, y0, p[1].y), Vector3(p[0].x, y0, p[0].y), col.darkened(0.3))
	# walls
	for k in 4:
		var a: Vector2 = p[k]
		var b: Vector2 = p[(k + 1) % 4]
		var shade: Color = col.darkened(0.12) if k % 2 == 0 else col
		quad(Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), Vector3(a.x, y0, a.y), shade)

## Rounded-corner slab, used for the island, plazas and chunky bases.
func rounded_slab(center: Vector3, size: Vector3, radius: float, segs: int, side_col: Color, top_col: Color) -> void:
	var pts := _rounded_rect(Vector2(center.x, center.z), Vector2(size.x, size.z) * 0.5, radius, segs)
	var y0 := center.y
	var y1 := center.y + size.y
	# top as a fan
	var mid := Vector3(center.x, y1, center.z)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		tri(mid, Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), top_col)
	# skirt
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		quad(Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), side_col)

func _rounded_rect(c: Vector2, half: Vector2, r: float, segs: int) -> PackedVector2Array:
	r = minf(r, minf(half.x, half.y))
	var out := PackedVector2Array()
	var offsets: Array[Vector2] = [
		Vector2(half.x - r, half.y - r),
		Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r),
		Vector2(half.x - r, -half.y + r),
	]
	var starts: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	for k in offsets.size():
		var o: Vector2 = offsets[k]
		var a0: float = starts[k]
		for step in range(segs + 1):
			var a: float = a0 + PI * 0.5 * (float(step) / float(segs))
			out.push_back(c + o + Vector2(cos(a), sin(a)) * r)
	return out

## Cylinder / cone / truncated cone. `pos` is the centre of the base.
func cylinder(pos: Vector3, r_bottom: float, r_top: float, height: float, col: Color, segs := 12, top_col := Color(0, 0, 0, 0)) -> void:
	var y0 := pos.y
	var y1 := pos.y + height
	var top: Color = top_col if top_col.a > 0.0 else col.lightened(0.06)
	for s in segs:
		var a0 := TAU * float(s) / float(segs)
		var a1 := TAU * float(s + 1) / float(segs)
		var b0 := Vector3(pos.x + cos(a0) * r_bottom, y0, pos.z + sin(a0) * r_bottom)
		var b1 := Vector3(pos.x + cos(a1) * r_bottom, y0, pos.z + sin(a1) * r_bottom)
		var t0 := Vector3(pos.x + cos(a0) * r_top, y1, pos.z + sin(a0) * r_top)
		var t1 := Vector3(pos.x + cos(a1) * r_top, y1, pos.z + sin(a1) * r_top)
		var shade := col
		if r_top > 0.001:
			quad(b0, t0, t1, b1, shade)
			tri(Vector3(pos.x, y1, pos.z), t1, t0, top)
		else:
			tri(b0, Vector3(pos.x, y1, pos.z), b1, shade)
		tri(Vector3(pos.x, y0, pos.z), b0, b1, col.darkened(0.35))

## Gabled roof: a triangular prism ridged along X (yaw rotates it).
func gable(pos: Vector3, size: Vector3, col: Color, yaw := 0.0, overhang := 0.0) -> void:
	var hx := size.x * 0.5 + overhang
	var hz := size.z * 0.5 + overhang
	var y0 := pos.y
	var y1 := pos.y + size.y
	var f := func(x: float, z: float) -> Vector2:
		var r := Vector2(x, z).rotated(yaw)
		return Vector2(pos.x + r.x, pos.z + r.y)
	var a: Vector2 = f.call(-hx, -hz)
	var b: Vector2 = f.call(hx, -hz)
	var c: Vector2 = f.call(hx, hz)
	var d: Vector2 = f.call(-hx, hz)
	var ridge_a: Vector2 = f.call(-hx, 0.0)
	var ridge_b: Vector2 = f.call(hx, 0.0)
	var light := col.lightened(0.10)
	var dark := col.darkened(0.14)
	quad(Vector3(a.x, y0, a.y), Vector3(ridge_a.x, y1, ridge_a.y), Vector3(ridge_b.x, y1, ridge_b.y), Vector3(b.x, y0, b.y), light)
	quad(Vector3(c.x, y0, c.y), Vector3(ridge_b.x, y1, ridge_b.y), Vector3(ridge_a.x, y1, ridge_a.y), Vector3(d.x, y0, d.y), dark)
	tri(Vector3(b.x, y0, b.y), Vector3(ridge_b.x, y1, ridge_b.y), Vector3(c.x, y0, c.y), col)
	tri(Vector3(d.x, y0, d.y), Vector3(ridge_a.x, y1, ridge_a.y), Vector3(a.x, y0, a.y), col)
	quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(c.x, y0, c.y), Vector3(d.x, y0, d.y), col.darkened(0.4))

## Four-sided pyramid roof.
func pyramid(pos: Vector3, size: Vector3, col: Color, yaw := 0.0, overhang := 0.0) -> void:
	var hx := size.x * 0.5 + overhang
	var hz := size.z * 0.5 + overhang
	var y0 := pos.y
	var apex := Vector3(pos.x, pos.y + size.y, pos.z)
	var flat: Array[Vector2] = [Vector2(-hx, -hz), Vector2(-hx, hz), Vector2(hx, hz), Vector2(hx, -hz)]
	var p: Array[Vector3] = []
	for c2: Vector2 in flat:
		var r: Vector2 = c2.rotated(yaw)
		p.append(Vector3(pos.x + r.x, y0, pos.z + r.y))
	for k in 4:
		var shade: Color = col.lightened(0.09) if k % 2 == 0 else col.darkened(0.11)
		tri(p[(k + 1) % 4], apex, p[k], shade)
	quad(p[3], p[2], p[1], p[0], col.darkened(0.4))

## Blobby sphere, used for tree canopies and bushes.
func sphere(center: Vector3, radius: float, col: Color, segs := 10, rings := 6, squash := 1.0) -> void:
	for r in rings:
		var p0 := PI * float(r) / float(rings)
		var p1 := PI * float(r + 1) / float(rings)
		for s in segs:
			var t0 := TAU * float(s) / float(segs)
			var t1 := TAU * float(s + 1) / float(segs)
			var pt := func(phi: float, theta: float) -> Vector3:
				return center + Vector3(sin(phi) * cos(theta) * radius, cos(phi) * radius * squash, sin(phi) * sin(theta) * radius)
			var a: Vector3 = pt.call(p0, t0)
			var b: Vector3 = pt.call(p1, t0)
			var c: Vector3 = pt.call(p1, t1)
			var d: Vector3 = pt.call(p0, t1)
			var shade := col
			if r == 0:
				tri(c, b, a, shade)
			elif r == rings - 1:
				tri(d, b, a, shade)
			else:
				quad(d, c, b, a, shade)

func is_empty() -> bool:
	return _v.is_empty()

func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_INDEX] = _i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
