class_name RoadMeshBuilder
extends RefCounted
## Builds a road ribbon (top surface + side skirts) from a sampled centre line.
## UV.x = 0..1 across the road, UV.y = metres along it (for lane markings / tiling).

## centers: closed or open polyline. widths/banks: per point (banks in radians, + = right side down).
static func build(centers: PackedVector3Array, widths: PackedFloat32Array, banks: PackedFloat32Array,
		closed: bool, skirt := 0.6) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := centers.size()
	var count := n + 1 if closed else n
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_along := 0.0
	var prev_up := Vector3.UP
	for i in count:
		var idx := i % n
		var p := centers[idx]
		var nxt := centers[(idx + 1) % n] if (closed or idx < n - 1) else p + (p - centers[idx - 1])
		var prv := centers[(idx - 1 + n) % n] if (closed or idx > 0) else p - (nxt - p)
		var tangent := (nxt - prv).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		side = side.rotated(tangent, banks[idx])
		var up := side.cross(tangent).normalized()
		var hw := widths[idx] * 0.5
		var l := p - side * hw
		var r := p + side * hw
		if i > 0:
			along += centers[idx].distance_to(centers[(idx - 1 + n) % n])
			_quad(st, prev_l, prev_r, l, r, prev_up, up, Vector2(0, prev_along), Vector2(1, along))
			# skirts down the sides so the road edge never floats above terrain
			var down := Vector3.DOWN * skirt
			_quad(st, prev_l + down - side * 0.4, prev_l, l + down - side * 0.4, l, -side, -side,
				Vector2(-0.05, prev_along), Vector2(0, along))
			_quad(st, prev_r, prev_r + down + side * 0.4, r, r + down + side * 0.4, side, side,
				Vector2(1, prev_along), Vector2(1.05, along))
		prev_l = l
		prev_r = r
		prev_along = along
		prev_up = up
	st.generate_tangents()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n0: Vector3, n1: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	# a-b = previous row (left,right), c-d = current row
	# clockwise winding when seen from the normal side (Godot front faces)
	var verts := [a, d, b, a, c, d]
	var norms := [n0, n1, n0, n0, n1, n1]
	var uvs := [uv0, uv1, Vector2(uv1.x, uv0.y), uv0, Vector2(uv0.x, uv1.y), uv1]
	for k in 6:
		st.set_normal(norms[k])
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])
