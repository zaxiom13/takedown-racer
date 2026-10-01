class_name ArcadeCar
extends RigidBody3D
## Arcade raycast-wheel car. Spring/damper suspension per wheel, grip-curve tyres with a drift state,
## boost meter. Dimensions and suspension rates come from a Stunt Rally 3 .car file (converted to JSON
## by tools/sr3_car_to_glb.py); the handling itself is hand-tuned for feel, not realism.

signal boost_changed(amount: float)
signal drift_changed(drifting: bool)

@export_file("*.json") var car_json := "res://assets/cars/LK4/LK4.car.json"
@export var player_controlled := true
@export var paint_color := Color(0.75, 0.06, 0.04)

@export_group("Engine")
@export var top_speed_kmh := 200.0          ## replaced by the gear-derived value from .car when present
@export var accel := 11.0                    ## m/s^2 at standstill
@export var brake_decel := 18.0
@export var reverse_speed_kmh := 40.0
@export var drag := 0.0008                   ## quadratic air drag factor (per unit mass)

@export_group("Steering")
@export var max_steer_deg := 26.0
@export var high_speed_steer_deg := 7.0      ## steer lock at top speed
@export var steer_speed := 5.0

@export_group("Grip")
@export var grip := 1.6                      ## lateral friction coefficient (front + rear)
@export var drift_grip := 0.12               ## lateral grip multiplier while drifting (path is steered directly)
@export var drift_base_angle := 28.0         ## slip angle held with neutral steering (deg)
@export var drift_angle_range := 18.0        ## +- slip angle added by steering in/out
@export var drift_turn_rate := 26.0          ## deg/s the path curves at neutral steer
@export var drift_speed_loss := 0.04         ## fraction of speed lost per second while drifting
@export var roll_force_height := 0.15        ## 0 = tyre forces at contact (rolls), 1 = at CoM (never rolls)
@export var downforce := 2.5                 ## N per (m/s)^2

@export_group("Boost")
@export var boost_accel := 9.0
@export var boost_top_speed_mul := 1.3
@export var boost_drain := 0.28              ## meter per second
@export var drift_fill := 0.12               ## meter per second while drifting (scaled by speed)

var throttle := 0.0
var brake_input := 0.0
var steer_input := 0.0
var handbrake := false
var boost_held := false

var boost_meter := 0.5
var boosting := false
var drifting := false
var speed := 0.0                             ## signed forward speed m/s
var wheels_on_ground := 0

var _wheels: Array[Dictionary] = []
var _steer := 0.0
var _drift_timer := 0.0
var _drift_dir := 0.0
var _drift_release := 0.0
var _wheel_radius := 0.41
var _travel := 0.3
var _spring := 52000.0
var _bounce := 11000.0
var _rebound := 8000.0
var _spawn_xform: Transform3D
var _visual_root: Node3D


func _ready() -> void:
	_spawn_xform = global_transform
	_load_params()
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	_apply_paint(self)
	var wn := get_node_or_null("Wheels")
	if wn:
		set_wheel_nodes(["FL", "FR", "RL", "RR"].map(func(n: String) -> Node: return wn.get_node_or_null(n)))


func _load_params() -> void:
	var f := FileAccess.open(car_json, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	var tb: Dictionary = d.get("tire-both", {})
	_wheel_radius = tb.get("radius", _wheel_radius)
	var sf: Dictionary = d.get("suspension-front", {})
	_spring = sf.get("spring-constant", _spring)
	_bounce = sf.get("bounce", _bounce)
	_rebound = sf.get("rebound", _rebound)
	_travel = minf(sf.get("travel", 0.3), 0.35)  # long rally travel feels floaty; cap it
	max_steer_deg = d.get("steering", {}).get("max-angle", max_steer_deg)
	# mass = sum of mass particles + engine (+ driver), like SR3
	var m := 0.0
	for k: String in d:
		if k.begins_with("particle-") or k == "engine" or k == "driver":
			m += float(d[k].get("mass", 0.0))
	mass = m if m > 300.0 else 1300.0
	# top speed from gearing: rpm-limit / (top gear * final drive) * wheel circumference
	var eng: Dictionary = d.get("engine", {})
	var tr: Dictionary = d.get("transmission", {})
	var gears := int(tr.get("gears", 0))
	if gears > 0 and eng.has("rpm-limit"):
		var ratio: float = tr.get("gear-ratio-%d" % gears, 1.0) * d.get("differential", {}).get("final-drive", 4.0)
		top_speed_kmh = eng["rpm-limit"] / ratio / 60.0 * TAU * _wheel_radius * 3.6
	for wname: String in ["FL", "FR", "RL", "RR"]:
		var wd: Dictionary = d.get("wheel-" + wname, {})
		var p: Array = wd.get("position", [0.75 * (-1 if wname[1] == "L" else 1), -0.5, -1.3 if wname[0] == "F" else 1.2])
		var pos := Vector3(p[0], p[1], p[2])
		_wheels.append({
			"name": wname, "front": wname[0] == "F", "left": wname[1] == "L",
			"rest": pos,                         # wheel centre at full droop
			"mount": pos + Vector3.UP * _travel, # ray origin
			"compression": 0.0, "contact": false, "normal": Vector3.UP, "hit_pos": Vector3.ZERO,
			"spin": 0.0, "node": null,
		})
	# centre of mass a bit low for stability
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.25, 0.05)


func _apply_paint(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m and m.resource_name.ends_with("_body"):
				var pm := m.duplicate() as StandardMaterial3D
				pm.albedo_color = paint_color
				pm.metallic = 0.45
				pm.roughness = 0.22
				mi.set_surface_override_material(s, pm)
	for c in n.get_children():
		_apply_paint(c)


## Attach visual wheel nodes (called by the car scene once meshes are instanced).
func set_wheel_nodes(nodes: Array) -> void:
	for i in mini(nodes.size(), _wheels.size()):
		_wheels[i]["node"] = nodes[i]


func reset_to(xform: Transform3D) -> void:
	_spawn_xform = xform
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	drifting = false


func _physics_process(delta: float) -> void:
	if player_controlled:
		_read_input()
	var xf := global_transform
	var fwd := -xf.basis.z
	var right := xf.basis.x
	var up := xf.basis.y
	var vel := linear_velocity
	speed = vel.dot(fwd)
	var kmh := absf(speed) * 3.6

	# --- steering (speed sensitive) ---
	var lock := lerpf(max_steer_deg, high_speed_steer_deg, clampf(kmh / top_speed_kmh, 0.0, 1.0))
	if drifting:
		lock = max_steer_deg  # full lock available for counter-steer
	_steer = move_toward(_steer, steer_input * lock, steer_speed * max_steer_deg * delta)

	# --- drift state ---
	if not drifting and wheels_on_ground >= 3 and kmh > 50.0 and absf(steer_input) > 0.4:
		if handbrake or (brake_input > 0.4 and throttle > 0.4):
			_set_drifting(true)
			_drift_dir = signf(steer_input)
	if drifting:
		_drift_timer += delta
		# steering away from the drift (or letting go) for a moment straightens out
		if steer_input * _drift_dir < 0.1:
			_drift_release += delta
		else:
			_drift_release = 0.0
		if _drift_release > 0.35 or kmh < 30.0 or wheels_on_ground == 0 or brake_input > 0.5 and throttle < 0.1:
			_set_drifting(false)

	# --- suspension + tyres ---
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [get_rid()]
	query.collision_mask = 1
	wheels_on_ground = 0
	var load_per_wheel := mass * 9.8 / 4.0
	for w: Dictionary in _wheels:
		var origin: Vector3 = xf * (w["mount"] as Vector3)
		var ray_len := _travel + _wheel_radius
		query.from = origin
		query.to = origin - up * ray_len
		var hit := space.intersect_ray(query)
		var was_compression: float = w["compression"]
		if hit.is_empty():
			w["contact"] = false
			w["compression"] = 0.0
			continue
		wheels_on_ground += 1
		w["contact"] = true
		var dist := origin.distance_to(hit.position) - _wheel_radius
		var compression := clampf(_travel - dist, 0.0, _travel)
		w["compression"] = compression
		w["normal"] = hit.normal
		w["hit_pos"] = hit.position
		var comp_vel := (compression - was_compression) / delta
		var damper := _bounce if comp_vel > 0.0 else _rebound
		var susp := maxf(0.0, _spring * compression + damper * comp_vel)
		# bump stop
		if compression > _travel * 0.9:
			susp += (compression - _travel * 0.9) * _spring * 8.0
		var n: Vector3 = hit.normal
		var contact: Vector3 = hit.position
		apply_force(n * susp, contact - global_position)

		# tyre frame on the ground plane
		var w_fwd := fwd
		if w["front"]:
			w_fwd = fwd.rotated(up, deg_to_rad(-_steer))
		w_fwd = (w_fwd - n * w_fwd.dot(n)).normalized()
		var w_right := w_fwd.cross(n).normalized()
		var pt_vel := vel + angular_velocity.cross(contact - global_position)
		var side_v := pt_vel.dot(w_right)
		var tyre_load := maxf(susp, load_per_wheel * 0.3)

		# lateral: cancel sideways velocity, limited by friction circle
		var g := grip
		if drifting:
			g *= drift_grip
		elif handbrake and not w["front"]:
			g *= 0.7
		var lat_needed := -side_v * mass / 4.0 / delta
		var lat_max := g * tyre_load
		var lat := clampf(lat_needed, -lat_max, lat_max)
		# apply sideways force partly raised towards the CoM so hard cornering can't roll the car
		var rel := contact - global_position
		var com_world := global_basis * center_of_mass
		rel += up * (com_world - rel).dot(up) * (1.0 - roll_force_height)
		apply_force(w_right * lat, rel)

	# --- drive / brake (applied at the body for arcade stability) ---
	if wheels_on_ground > 0:
		var ground_factor := float(wheels_on_ground) / 4.0
		var top := top_speed_kmh / 3.6
		boosting = boost_held and boost_meter > 0.0 and speed > -1.0
		if boosting:
			top *= boost_top_speed_mul
		var drive := 0.0
		if throttle > 0.0 and speed < top:
			drive = throttle * accel * (1.0 - pow(maxf(speed, 0.0) / top, 2.0))
		if boosting:
			drive += boost_accel * (1.0 - clampf(speed / top, 0.0, 1.0)) + 2.0
		if brake_input > 0.0:
			if speed > 1.0:
				drive -= brake_input * brake_decel * (0.3 if drifting else 1.0)
			elif speed > -reverse_speed_kmh / 3.6:
				drive -= brake_input * accel * 0.6
		if handbrake and not drifting:
			drive -= signf(speed) * minf(absf(speed), 6.0)
		# rolling resistance when coasting
		if throttle == 0.0 and brake_input == 0.0:
			drive -= signf(speed) * minf(absf(speed), 1.2)
		apply_central_force(fwd * drive * mass * ground_factor)

		# drift: hold a slip angle chosen by the steering, curve the path, keep the speed
		if drifting:
			var steer_rel := steer_input * _drift_dir  # +1 = into the drift, -1 = counter-steer
			var target_slip := deg_to_rad(drift_base_angle + drift_angle_range * steer_rel) * _drift_dir
			var flat_v := Vector3(vel.x, 0.0, vel.z)
			var flat_fwd := Vector3(fwd.x, 0.0, fwd.z).normalized()
			if flat_v.length() > 1.0:
				var cur_slip := -flat_v.normalized().signed_angle_to(flat_fwd, Vector3.UP)
				var yaw_target := -(target_slip - cur_slip) * 5.0 - _drift_dir * deg_to_rad(drift_turn_rate) * (1.0 + 0.6 * steer_rel)
				var yaw_now := angular_velocity.dot(Vector3.UP)
				angular_velocity += Vector3.UP * (yaw_target - yaw_now) * minf(1.0, 8.0 * delta)
				var turn := -_drift_dir * deg_to_rad(drift_turn_rate) * (1.0 + 0.6 * steer_rel) * delta
				var new_v := flat_v.rotated(Vector3.UP, turn) * (1.0 - drift_speed_loss * delta)
				linear_velocity = Vector3(new_v.x, vel.y, new_v.z)
			boost_meter = minf(1.0, boost_meter + drift_fill * clampf(kmh / 120.0, 0.3, 1.5) * delta)
			boost_changed.emit(boost_meter)

		# straight-line yaw damping (stops twitchy wobble without killing drift)
		if not drifting:
			var yaw_rate := angular_velocity.dot(up)
			apply_torque(-up * yaw_rate * mass * 0.6)

	if boosting:
		boost_meter = maxf(0.0, boost_meter - boost_drain * delta)
		boost_changed.emit(boost_meter)

	# --- aero ---
	apply_central_force(-up * downforce * speed * speed)
	apply_central_force(-vel * vel.length() * drag * mass)

	# --- air control: level out & small pitch/roll steering ---
	if wheels_on_ground == 0:
		var level_axis := up.cross(Vector3.UP)
		apply_torque(level_axis * mass * 3.0)
		apply_torque(Vector3.UP * -steer_input * mass * 1.2)

	if player_controlled and Input.is_action_just_pressed("reset_car"):
		respawn_here()


func _process(delta: float) -> void:
	_update_wheel_visuals(delta)


func _update_wheel_visuals(delta: float) -> void:
	for w: Dictionary in _wheels:
		var node: Node3D = w["node"]
		if node == null:
			continue
		var rest: Vector3 = w["rest"]
		var c: float = w["compression"]
		node.position = rest + Vector3.UP * c
		w["spin"] = fmod(float(w["spin"]) + speed / _wheel_radius * delta, TAU)
		var steer_rad := deg_to_rad(-_steer) if w["front"] else 0.0
		var base := Basis(Vector3.UP, steer_rad) * Basis(Vector3.RIGHT, -float(w["spin"]))
		if w["left"]:
			base = base * Basis(Vector3.UP, PI)
		node.basis = base


func _read_input() -> void:
	throttle = Input.get_action_strength("accelerate")
	brake_input = Input.get_action_strength("brake")
	steer_input = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	handbrake = Input.is_action_pressed("handbrake")
	boost_held = Input.is_action_pressed("boost")


func _set_drifting(on: bool) -> void:
	if drifting == on:
		return
	drifting = on
	_drift_timer = 0.0
	drift_changed.emit(on)


## Put the car back on its wheels where it is (or at spawn if far below the world).
func respawn_here() -> void:
	var xf := global_transform
	if xf.origin.y < -50.0:
		reset_to(_spawn_xform)
		return
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	reset_to(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 1.5))


func get_speed_kmh() -> float:
	return absf(speed) * 3.6


func add_boost(amount: float) -> void:
	boost_meter = clampf(boost_meter + amount, 0.0, 1.0)
	boost_changed.emit(boost_meter)
