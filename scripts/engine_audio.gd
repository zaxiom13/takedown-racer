class_name EngineAudio
extends Node3D
## Engine sound: crossfades between fixed-RPM loops (1000..9000 rpm) and pitch-shifts between them.
## RPM comes from a simple fake gearbox driven by the car's speed. Also plays the boost whoosh.

@export var sample_dir := "res://assets/audio/engines/tsu-%d.ogg"
@export var sample_count := 9
@export var gears := 6
@export var idle_rpm := 1000.0
@export var max_rpm := 7000.0
@export var volume_db := -6.0

var car: ArcadeCar
var rpm := 1000.0
var _players: Array[AudioStreamPlayer3D] = []
var _boost: AudioStreamPlayer3D
var _gear := 1


func _ready() -> void:
	car = get_parent() as ArcadeCar
	for i in sample_count:
		var p := AudioStreamPlayer3D.new()
		var s := load(sample_dir % (i + 1)) as AudioStreamOggVorbis
		s.loop = true
		p.stream = s
		p.volume_db = -80.0
		p.unit_size = 12.0
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	_boost = AudioStreamPlayer3D.new()
	var bs := load("res://assets/audio/boost_whoosh.ogg") as AudioStreamOggVorbis
	bs.loop = true
	_boost.stream = bs
	_boost.volume_db = -80.0
	add_child(_boost)
	for p in _players:
		p.play()
	_boost.play()


func _process(delta: float) -> void:
	if car == null:
		return
	var top := car.top_speed_kmh * (car.boost_top_speed_mul if car.boosting else 1.0)
	var t := clampf(car.get_speed_kmh() / top, 0.0, 1.0)
	# gear bands: each gear covers an equal slice of top speed, rpm sweeps 45% -> 100% within it
	var gear_f := t * gears
	var gear := clampi(int(gear_f) + 1, 1, gears)
	var in_gear := gear_f - (gear - 1)
	if gear != _gear:
		_gear = gear
	var target := lerpf(max_rpm * 0.45, max_rpm, in_gear) if t > 0.02 else idle_rpm
	if car.drifting or car.wheels_on_ground == 0:
		target = maxf(target, max_rpm * (0.8 if car.throttle > 0.0 else 0.5))
	target = lerpf(target * 0.75, target, maxf(car.throttle, 0.3))
	rpm = lerpf(rpm, target, 1.0 - exp(-10.0 * delta))
	var idx_f := clampf(rpm / 1000.0 - 1.0, 0.0, sample_count - 1.001)
	var lo := int(idx_f)
	var frac := idx_f - lo
	var load_db := lerpf(-6.0, 0.0, car.throttle)
	for i in _players.size():
		var p := _players[i]
		var w := 0.0
		if i == lo:
			w = 1.0 - frac
		elif i == lo + 1:
			w = frac
		p.volume_db = volume_db + load_db + linear_to_db(maxf(w, 0.0001))
		p.pitch_scale = clampf(rpm / ((i + 1) * 1000.0), 0.5, 2.0)
	var bt := 1.0 if car.boosting else 0.0
	_boost.volume_db = lerpf(_boost.volume_db, -4.0 if bt > 0.0 else -60.0, 1.0 - exp(-6.0 * delta))


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_boost.stop()
	_boost.stream = null
