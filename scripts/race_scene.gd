extends Node3D
## Milestone 2: race on a converted SR3 track — player car, laps/checkpoints, HUD, perf overlay.

const CAR_SCENE := preload("res://scenes/cars/lk4.tscn")

@export_dir var track_dir := "res://assets/tracks/Atm2-RedOakPark"
@export var laps := 3

var car: ArcadeCar
var track: TrackBuilder
var race: RaceManager


func _ready() -> void:
	track = TrackBuilder.new()
	track.name = "Track"
	track.track_dir = track_dir
	add_child(track)
	track.build()
	car = CAR_SCENE.instantiate() as ArcadeCar
	car.name = "PlayerCar"
	add_child(car)
	car.reset_to(track.start_transform())
	race = RaceManager.new()
	race.laps = laps
	add_child(race)
	race.setup(track, car)
	var cam := ChaseCamera.new()
	cam.target_path = car.get_path()
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	var hud := RaceHud.new()
	hud.car_path = car.get_path()
	add_child(hud)
	hud.set_race(race)
	add_child(PerfOverlay.new())


func smoke_check() -> String:
	if car == null:
		return "no car"
	if car.wheels_on_ground < 3:
		return "car not resting on its wheels at start (%d on ground, y=%.2f)" % [car.wheels_on_ground, car.global_position.y]
	return ""
