class_name TrackBuilder
extends Node3D
## Builds a converted Stunt Rally 3 track (see tools/sr3_track_convert.py) at load time:
## chunked terrain mesh + HeightMapShape3D from terrain.f32, splat-shaded; road.glb with collision;
## vegetation as chunked MultiMeshes with visibility ranges; sky, sun and fog from track.json.

@export_dir var track_dir := "res://assets/tracks/Atm2-RedOakPark"
@export var terrain_chunk_cells := 64
@export var veg_cell_size := 120.0
@export var veg_visibility := 320.0

var info: Dictionary
var line_points := PackedVector3Array()   ## racing line in driving order
var line_widths := PackedFloat32Array()
var line_dist := PackedFloat32Array()      ## cumulative distance along the line
var line_length := 0.0
var _heights := PackedFloat32Array()
var _n := 0
var _spacing := 1.0
var _origin := Vector3.ZERO


func build() -> void:
	info = JSON.parse_string(FileAccess.get_file_as_string(track_dir + "/track.json"))
	_build_line()
	_build_environment()
	_build_terrain()
	_build_road()
	_build_vegetation()


func start_transform() -> Transform3D:
	var s: Dictionary = info["start"]
	var p := Vector3(s["p"][0], s["p"][1], s["p"][2])
	var f := Vector3(s["fwd"][0], 0, s["fwd"][2]).normalized()
	return Transform3D(Basis.looking_at(f, Vector3.UP), p)


## Terrain height (bilinear) at world x, z.
func height_at(x: float, z: float) -> float:
	var gx := clampf((x - _origin.x) / _spacing, 0.0, _n - 1.001)
	var gz := clampf((z - _origin.z) / _spacing, 0.0, _n - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var a := lerpf(_heights[iz * _n + ix], _heights[iz * _n + ix + 1], fx)
	var b := lerpf(_heights[(iz + 1) * _n + ix], _heights[(iz + 1) * _n + ix + 1], fx)
	return lerpf(a, b, fz)


## Nearest racing-line index to a world position (brute force over a stride, then refine).
func nearest_line_index(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in range(0, line_points.size(), 4):
		var d := line_points[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	for i in range(best - 4, best + 5):
		var j := posmod(i, line_points.size())
		var d := line_points[j].distance_squared_to(p)
		if d < bd:
			bd = d
			best = j
	return best


## Transform on the racing line at index i, facing the driving direction.
func line_transform(i: int, lift := 1.0) -> Transform3D:
	var n := line_points.size()
	var p := line_points[posmod(i, n)]
	var f := line_points[posmod(i + 3, n)] - p
	f.y = 0.0
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), p + Vector3.UP * lift)


func _build_line() -> void:
	var total := 0.0
	for e: Dictionary in info["line"]:
		var p := Vector3(e["p"][0], e["p"][1], e["p"][2])
		if line_points.size() > 0:
			total += line_points[line_points.size() - 1].distance_to(p)
		line_points.append(p)
		line_widths.append(e["w"])
		line_dist.append(total)
	line_length = total + line_points[line_points.size() - 1].distance_to(line_points[0])


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_file: String = info["sky"]["file"]
	if sky_file != "":
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(track_dir + "/" + sky_file)
		pm.energy_multiplier = 1.0
		sky.sky_material = pm
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(-float(info["sky"]["yaw"])), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.2
	if info.get("fog") != null:
		var fog: Dictionary = info["fog"]
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = Color(fog["color"][0], fog["color"][1], fog["color"][2])
		env.fog_depth_begin = fog["start"]
		env.fog_depth_end = fog["end"] * 1.2
		env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	var li: Dictionary = info.get("light", {"pitch": 45.0, "yaw": 0.0})
	sun.rotation_degrees = Vector3(-float(li["pitch"]), float(li["yaw"]) + 180.0, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_terrain() -> void:
	var t: Dictionary = info["terrain"]
	_n = int(t["size"])
	_spacing = t["spacing"]
	_origin = Vector3(t["origin"][0], 0, t["origin"][2])
	_heights = FileAccess.get_file_as_bytes(track_dir + "/terrain.f32").to_float32_array()
	# collision: heights pre-divided so the shape can be scaled uniformly by the grid spacing
	var body := StaticBody3D.new()
	body.name = "Terrain"
	var hs := HeightMapShape3D.new()
	hs.map_width = _n
	hs.map_depth = _n
	var scaled := _heights.duplicate()
	for i in scaled.size():
		scaled[i] /= _spacing
	hs.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = hs
	cs.scale = Vector3.ONE * _spacing
	var half := (_n - 1) * 0.5 * _spacing
	cs.position = _origin + Vector3(half, 0, half)
	body.add_child(cs)
	add_child(body)
	# render mesh, chunked for frustum culling
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("splat", load(track_dir + "/splat.png"))
	mat.set_shader_parameter("origin_size", Vector4(_origin.x, _origin.z, (_n - 1) * _spacing, 0))
	var layers: Array = t["layers"]
	for i in 4:
		var L: Dictionary = layers[mini(i, layers.size() - 1)]
		mat.set_shader_parameter("layer%d" % i, load(track_dir + "/" + L["file"]))
		mat.set_shader_parameter("scale%d" % i, float(L["scale"]))
	var normals := _terrain_normals()
	var c := terrain_chunk_cells
	for cz in range(0, _n - 1, c):
		for cx in range(0, _n - 1, c):
			var mi := MeshInstance3D.new()
			mi.mesh = _terrain_chunk(cx, cz, mini(cx + c, _n - 1), mini(cz + c, _n - 1), normals)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mi)


func _terrain_normals() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(_n * _n)
	for z in _n:
		for x in _n:
			var hl := _heights[z * _n + maxi(x - 1, 0)]
			var hr := _heights[z * _n + mini(x + 1, _n - 1)]
			var hd := _heights[maxi(z - 1, 0) * _n + x]
			var hu := _heights[mini(z + 1, _n - 1) * _n + x]
			out[z * _n + x] = Vector3(hl - hr, 2.0 * _spacing, hd - hu).normalized()
	return out


func _terrain_chunk(x0: int, z0: int, x1: int, z1: int, normals: PackedVector3Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var w := x1 - x0 + 1
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			verts.append(_origin + Vector3(x * _spacing, _heights[z * _n + x], z * _spacing))
			norms.append(normals[z * _n + x])
	for z in z1 - z0:
		for x in x1 - x0:
			var a := z * w + x
			idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_road() -> void:
	var scene := (load(track_dir + "/road.glb") as PackedScene).instantiate()
	var meshes := {}
	_collect_meshes(scene, meshes)
	scene.free()
	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	grain.noise = noise
	var road_mat := ShaderMaterial.new()
	road_mat.shader = load("res://shaders/road.gdshader")
	road_mat.set_shader_parameter("grain", grain)
	road_mat.set_shader_parameter("lanes", 2.0)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.62, 0.63, 0.66)
	rail_mat.metallic = 0.6
	rail_mat.roughness = 0.4
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := StaticBody3D.new()
	body.name = "Road"
	for key: String in meshes:
		var mesh: Mesh = meshes[key]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = rail_mat if key.begins_with("rail") else road_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var tri := mesh.create_trimesh_shape()
		tri.backface_collision = true
		cs.shape = tri
		body.add_child(cs)
	add_child(body)


func _collect_meshes(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D:
		out[String(n.name).to_lower()] = (n as MeshInstance3D).mesh
	for c in n.get_children():
		_collect_meshes(c, out)


func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m:
			return m
	return null


func _build_vegetation() -> void:
	var veg: Dictionary = info.get("vegetation", {})
	var root := Node3D.new()
	root.name = "Vegetation"
	add_child(root)
	for name: String in veg:
		var path := "%s/veg/%s.glb" % [track_dir, name]
		if not ResourceLoader.exists(path):
			continue
		var scene := (load(path) as PackedScene).instantiate()
		var mesh := _first_mesh(scene)
		scene.free()
		# bucket instances into cells so each MultiMesh can be culled / range-limited on its own
		var cells := {}
		for e: Array in veg[name]:
			var key := Vector2i(floori(e[0] / veg_cell_size), floori(e[2] / veg_cell_size))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(e)
		for key: Vector2i in cells:
			var list: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in list.size():
				var e: Array = list[i]
				var b := Basis(Vector3.UP, deg_to_rad(e[3])).scaled(Vector3.ONE * float(e[4]))
				mm.set_instance_transform(i, Transform3D(b, Vector3(e[0], e[1], e[2])))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = veg_visibility
			mmi.visibility_range_end_margin = 30.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(mmi)
			# trunk collision (cylinders) so trees are solid
			var body := StaticBody3D.new()
			for e: Array in list:
				var col := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.35 * float(e[4])
				cyl.height = 6.0
				col.shape = cyl
				col.position = Vector3(e[0], e[1] + 3.0, e[2])
				body.add_child(col)
			root.add_child(body)
