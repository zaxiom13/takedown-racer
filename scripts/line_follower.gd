class_name LineFollower
extends Node
## Minimal AI driver: steers towards a look-ahead point on the track's racing line and slows for
## sharp bends. Drives the ArcadeCar it is attached to (sets player_controlled = false).

@export var lookahead_base := 10.0       ## m
@export var lookahead_per_kmh := 0.12    ## extra m per km/h
@export var corner_speed_scale := 1.0    ## >1 = braver
@export var lane_offset := 0.0           ## m right of the centre line

var track: TrackBuilder
var car: ArcadeCar
var _i := 0
var _stuck := 0.0


func setup(t: TrackBuilder, c: ArcadeCar) -> void:
	track = t
	car = c
	car.player_controlled = false
	_i = t.nearest_line_index(c.global_position)


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	var n := track.line_points.size()
	# advance the tracked index locally (cheap; avoids global search every tick)
	for k in 12:
		var a := track.line_points[_i].distance_squared_to(car.global_position)
		var b := track.line_points[(_i + 1) % n].distance_squared_to(car.global_position)
		if b < a:
			_i = (_i + 1) % n
		else:
			break
	var spacing := track.line_length / n
	var kmh := car.get_speed_kmh()
	var ahead := int((lookahead_base + kmh * lookahead_per_kmh) / spacing)
	var target := _offset_point((_i + ahead) % n)
	var local := car.global_transform.affine_inverse() * target
	var steer := clampf(atan2(local.x, -local.z) * 2.2, -1.0, 1.0)
	# curvature over the next ~60 m sets a target speed
	var p0 := track.line_points[_i]
	var p1 := track.line_points[(_i + int(25.0 / spacing)) % n]
	var p2 := track.line_points[(_i + int(55.0 / spacing)) % n]
	var d1 := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
	var d2 := Vector2(p2.x - p1.x, p2.z - p1.z).normalized()
	var bend := absf(d1.angle_to(d2))
	var target_kmh := lerpf(car.top_speed_kmh, 75.0, clampf(bend / 0.9, 0.0, 1.0)) * corner_speed_scale
	# crests: slow down if the road drops away after rising (would launch the car into the next bend)
	var crest := (p1.y - p0.y) / 25.0 - (p2.y - p1.y) / 30.0
	if crest > 0.06:
		target_kmh = minf(target_kmh, lerpf(150.0, 95.0, clampf((crest - 0.06) / 0.12, 0.0, 1.0)))
	car.steer_input = steer
	car.throttle = 1.0 if kmh < target_kmh else 0.0
	car.brake_input = clampf((kmh - target_kmh) / 30.0, 0.0, 1.0) if kmh > target_kmh + 8.0 else 0.0
	car.handbrake = false
	car.boost_held = car.boost_meter > 0.6 and bend < 0.15
	# stuck (wall, tree, upside down): back off, then respawn on the line
	_stuck = _stuck + _delta if kmh < 5.0 else maxf(0.0, _stuck - _delta * 2.0)
	if _stuck > 1.5:
		car.throttle = 0.0
		car.brake_input = 1.0
		car.steer_input = -steer
	if _stuck > 4.0:
		car.reset_to(track.line_transform(_i, 1.2))
		_stuck = 0.0


func _offset_point(i: int) -> Vector3:
	var n := track.line_points.size()
	var p := track.line_points[i]
	if lane_offset == 0.0:
		return p
	var f := track.line_points[(i + 1) % n] - p
	var right := Vector3(-f.z, 0, f.x).normalized()
	return p + right * lane_offset
