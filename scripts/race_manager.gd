class_name RaceManager
extends Node
## Lap/checkpoint logic for one car on a TrackBuilder track. Checkpoints must be passed in order;
## crossing the start/finish (back near the start after the last checkpoint) completes a lap.

signal checkpoint_passed(index: int, split: float)
signal lap_completed(lap: int, lap_time: float)
signal race_finished(total_time: float)

@export var laps := 3
@export var countdown := 3.0

var track: TrackBuilder
var car: ArcadeCar
var checkpoints: Array[Dictionary] = []   ## {pos: Vector3, r: float}
var next_check := 0
var lap := 1
var race_time := 0.0
var lap_time := 0.0
var best_lap := 0.0
var last_lap := 0.0
var finished := false
var countdown_left := 0.0
var progress := 0.0                         ## distance driven along the line this race (m)
var _last_line_i := 0
var _start_pos: Vector3


func setup(t: TrackBuilder, c: ArcadeCar) -> void:
	track = t
	car = c
	_start_pos = t.start_transform().origin
	# order checkpoints by distance along the racing line from the start
	var n := t.line_points.size()
	var s_i := t.nearest_line_index(_start_pos)
	for e: Dictionary in t.info["checkpoints"]:
		var p := Vector3(e["p"][0], e["p"][1], e["p"][2])
		checkpoints.append({"pos": p, "r": float(e["r"]), "k": posmod(t.nearest_line_index(p) - s_i, n)})
	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["k"] < b["k"])
	# start/finish line acts as the last checkpoint of each lap
	checkpoints.append({"pos": _start_pos, "r": 14.0})
	# skip checkpoints that sit right on the start (would trigger instantly)
	while next_check < checkpoints.size() - 1 and checkpoints[next_check]["pos"].distance_to(_start_pos) < checkpoints[next_check]["r"]:
		next_check += 1
	_last_line_i = t.nearest_line_index(_start_pos)
	countdown_left = countdown
	car.respawn_provider = respawn_transform


func respawn_transform() -> Transform3D:
	var i := track.nearest_line_index(car.global_position)
	return track.line_transform(i, 1.2)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	if countdown_left > 0.0:
		countdown_left -= delta
		car.input_locked = countdown_left > 0.0
		return
	if finished:
		return
	race_time += delta
	lap_time += delta
	# progress along racing line (for HUD / later race positions)
	var i := track.nearest_line_index(car.global_position)
	var n := track.line_points.size()
	var step := posmod(i - _last_line_i + n / 2, n) - n / 2
	if absi(step) < 40:
		progress += float(step) * (track.line_length / n)
		_last_line_i = i
	# fell off the world
	if car.global_position.y < track.height_at(car.global_position.x, car.global_position.z) - 15.0:
		car.reset_to(respawn_transform())
	var cp: Dictionary = checkpoints[next_check]
	var to := car.global_position - (cp["pos"] as Vector3)
	if Vector2(to.x, to.z).length() < float(cp["r"]) and absf(to.y) < 12.0:
		if next_check == checkpoints.size() - 1:
			_complete_lap()
		else:
			checkpoint_passed.emit(next_check, lap_time)
			next_check += 1


func _complete_lap() -> void:
	last_lap = lap_time
	if best_lap == 0.0 or lap_time < best_lap:
		best_lap = lap_time
	lap_completed.emit(lap, lap_time)
	lap_time = 0.0
	next_check = 0
	if lap >= laps:
		finished = true
		race_finished.emit(race_time)
	else:
		lap += 1


static func fmt_time(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
