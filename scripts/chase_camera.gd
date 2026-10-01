class_name ChaseCamera
extends Camera3D
## Spring chase cam: follows behind the target car, widens FOV with speed/boost and drives the
## motion-blur post effect. C toggles between far/near chase.

@export var target_path: NodePath
@export var distance := 5.4
@export var height := 1.8
@export var look_ahead := 3.0
@export var follow_stiffness := 9.0
@export var base_fov := 68.0
@export var max_fov := 88.0
@export var boost_fov_kick := 8.0
@export var blur_start_kmh := 110.0

var target: ArcadeCar
var _views := [Vector2(5.4, 1.8), Vector2(7.5, 2.4)]
var _view := 0
var _blur: ShaderMaterial
var _fov_extra := 0.0
var _shake := 0.0


func _ready() -> void:
	target = get_node_or_null(target_path) as ArcadeCar
	var layer := CanvasLayer.new()
	layer.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur = ShaderMaterial.new()
	_blur.shader = load("res://shaders/motion_blur.gdshader")
	rect.material = _blur
	layer.add_child(rect)
	add_child(layer)
	if target:
		global_position = target.global_position + target.global_basis.z * distance + Vector3.UP * height


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle"):
		_view = (_view + 1) % _views.size()
		distance = _views[_view].x
		height = _views[_view].y


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var tpos := target.global_position
	# follow the velocity direction when moving fast (shows drift angle), else car heading
	var heading := -target.global_basis.z
	var vel := target.linear_velocity
	vel.y = 0.0
	if vel.length() > 8.0:
		heading = heading.slerp(vel.normalized(), 0.55)
	heading.y = 0.0
	heading = heading.normalized() if heading.length() > 0.01 else Vector3.FORWARD
	var desired := tpos - heading * distance + Vector3.UP * height
	var t := 1.0 - exp(-follow_stiffness * delta)
	global_position = global_position.lerp(desired, t)
	# keep a minimum distance so the camera never clips into the car on hard stops
	var to_cam := global_position - tpos
	if to_cam.length() < distance * 0.7:
		global_position = tpos + to_cam.normalized() * distance * 0.7
	# pull in if terrain/road/trees block the view of the car
	var pivot := tpos + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(pivot, global_position + (global_position - pivot).normalized() * 0.4)
	q.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = (hit.position as Vector3) + ((hit.normal as Vector3) * 0.3)
	var look := tpos + heading * look_ahead + Vector3.UP * 0.8
	if _shake > 0.0:
		look += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.15
		_shake = move_toward(_shake, 0.0, delta * 2.0)
	look_at(look, Vector3.UP)

	var kmh := target.get_speed_kmh()
	var speed_t := clampf(kmh / 260.0, 0.0, 1.0)
	_fov_extra = lerpf(_fov_extra, boost_fov_kick if target.boosting else 0.0, 1.0 - exp(-4.0 * delta))
	fov = lerpf(base_fov, max_fov, speed_t * speed_t) + _fov_extra
	var blur := clampf((kmh - blur_start_kmh) / 160.0, 0.0, 1.0)
	if target.boosting:
		blur = minf(1.0, blur + 0.35)
	_blur.set_shader_parameter("strength", blur)
