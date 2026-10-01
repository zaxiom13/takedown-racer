extends Node3D
## Milestone 1 test scene: a procedurally built loop road on flat ground with ramps and props,
## the player car, chase cam, HUD and perf overlay.

const CAR_SCENE := preload("res://scenes/cars/lk4.tscn")
const ROAD_WIDTH := 16.0

## Loop control points (x, z); y is added from HEIGHTS.
const LOOP := [
	Vector2(0, 0), Vector2(0, -150), Vector2(20, -260), Vector2(90, -320), Vector2(190, -310),
	Vector2(260, -240), Vector2(250, -140), Vector2(190, -90), Vector2(170, -10), Vector2(230, 60),
	Vector2(230, 160), Vector2(150, 230), Vector2(40, 220), Vector2(0, 140),
]

var car: ArcadeCar
var _grain: NoiseTexture2D
var _road_pts := PackedVector3Array()


func _ready() -> void:
	_grain = NoiseTexture2D.new()
	_grain.width = 256
	_grain.height = 256
	_grain.seamless = true
	_grain.generate_mipmaps = true
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	_grain.noise = noise
	_build_environment()
	_build_ground()
	var start := _build_road()
	_build_props()
	car = CAR_SCENE.instantiate() as ArcadeCar
	car.name = "PlayerCar"
	add_child(car)
	car.reset_to(start)
	var cam := ChaseCamera.new()
	cam.name = "ChaseCamera"
	cam.target_path = car.get_path()
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	var hud := RaceHud.new()
	hud.car_path = car.get_path()
	add_child(hud)
	add_child(PerfOverlay.new())


func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.23, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.86)
	sky_mat.ground_horizon_color = Color(0.6, 0.65, 0.7)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.25)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.75, 0.85)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("grain", _grain)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)


## Returns the car start transform.
func _build_road() -> Transform3D:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	var n := LOOP.size()
	for i in n:
		var p: Vector2 = LOOP[i]
		var prev: Vector2 = LOOP[(i - 1 + n) % n]
		var nxt: Vector2 = LOOP[(i + 1) % n]
		var tan := (nxt - prev) * 0.25  # Catmull-Rom style handles
		curve.add_point(Vector3(p.x, 0.06, p.y), Vector3(-tan.x, 0, -tan.y), Vector3(tan.x, 0, tan.y))
	curve.add_point(curve.get_point_position(0), curve.get_point_in(0), curve.get_point_out(0))
	var pts := curve.get_baked_points()
	pts.remove_at(pts.size() - 1)
	_road_pts = pts
	var widths := PackedFloat32Array()
	var banks := PackedFloat32Array()
	var count := pts.size()
	for i in count:
		widths.append(ROAD_WIDTH)
		banks.append(0.0)
	var mesh := RoadMeshBuilder.build(pts, widths, banks, true)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	mat.set_shader_parameter("grain", _grain)
	mat.set_shader_parameter("lanes", 4.0)
	mesh.surface_set_material(0, mat)
	var body := StaticBody3D.new()
	body.name = "Road"
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)
	add_child(body)
	var p0 := pts[4]
	var dir := (pts[8] - pts[4]).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), p0 + Vector3.UP * 1.0)


func _build_props() -> void:
	# kicker ramps on the long back straight
	for z: float in [-60.0, -100.0]:
		_ramp(Vector3(5.0, 0.0, z), 5.0, 10.0, 12.0)
	# stacks of crates to smash
	var crate_mesh := BoxMesh.new()
	crate_mesh.size = Vector3.ONE
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.75, 0.5, 0.2)
	crate_mat.roughness = 0.8
	crate_mesh.material = crate_mat
	for row in 3:
		for col in 4 - row:
			var rb := RigidBody3D.new()
			rb.mass = 40.0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3.ONE
			cs.shape = bs
			rb.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.mesh = crate_mesh
			rb.add_child(mi)
			rb.position = Vector3(250.0 - 1.5 + col * 1.05 + row * 0.5, 0.56 + row * 1.02, -160.0)
			add_child(rb)
	# trees as a single MultiMesh for scale/speed reference (1 draw call per part)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 0
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 2.2
	crown.height = 7.0
	crown.radial_segments = 8
	crown.rings = 0
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.3, 0.2, 0.12)
	trunk.material = tm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.12, 0.27, 0.1)
	crown.material = cm
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var xforms: Array[Transform3D] = []
	while xforms.size() < 600:
		var p := Vector3(rng.randf_range(-500, 700), 0, rng.randf_range(-700, 500))
		if _near_road(p, 22.0):
			continue
		var s := rng.randf_range(0.8, 1.5)
		xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * s).rotated(Vector3.UP, rng.randf() * TAU), p))
	_multimesh(trunk, xforms, Vector3(0, 1.5, 0))
	_multimesh(crown, xforms, Vector3(0, 6.0, 0))


func _near_road(p: Vector3, dist: float) -> bool:
	for i in range(0, _road_pts.size(), 3):
		if Vector2(_road_pts[i].x - p.x, _road_pts[i].z - p.z).length() < dist:
			return true
	return false


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], offset: Vector3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t := xforms[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + t.basis * offset))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _ramp(pos: Vector3, width: float, length: float, angle_deg: float) -> void:
	var body := StaticBody3D.new()
	var h := length * tan(deg_to_rad(angle_deg))
	var pm := PrismMesh.new()
	pm.left_to_right = 1.0
	pm.size = Vector3(length, h, width)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	pm.material = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = pm.create_convex_shape()
	body.add_child(cs)
	# prism slopes up along +X; rotate so it rises along -Z (direction of travel on the straight)
	body.rotation_degrees.y = 90.0
	body.position = pos + Vector3.UP * h * 0.5
	add_child(body)


## Called by the headless smoke test after running for a while.
func smoke_check() -> String:
	if car == null:
		return "no car"
	if car.global_position.y < -5.0:
		return "car fell through the world"
	if car.wheels_on_ground < 3:
		return "car not resting on its wheels (%d on ground)" % car.wheels_on_ground
	return ""
