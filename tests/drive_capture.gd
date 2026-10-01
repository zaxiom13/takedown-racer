extends SceneTree
## Scripted drive for tuning: presses inputs on a timeline, logs telemetry, saves screenshots.
## Needs a display (use xvfb-run). Usage:
##   godot --path . -s res://tests/drive_capture.gd -- <out_dir> [scene]

var out_dir := "user://capture"
var scene_path := "res://scenes/test_drive.tscn"
# [start_s, end_s, action, strength]
var timeline := [
	[0.0, 14.0, "accelerate", 1.0],
	[3.0, 5.0, "boost", 1.0],
	[7.0, 7.3, "handbrake", 1.0],
	[7.0, 10.5, "steer_right", 0.8],
	[11.0, 13.0, "steer_left", 0.6],
]
var shots := [1.0, 4.5, 8.0, 9.5, 13.5]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		scene_path = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(inst)
	var car: ArcadeCar = inst.get("car")
	var t := 0.0
	var next_log := 0.0
	var shot_i := 0
	var end_t := 0.0
	for e: Array in timeline:
		end_t = maxf(end_t, e[1])
	while t < end_t + 0.5:
		await physics_frame
		t += 1.0 / 60.0
		for e: Array in timeline:
			if t >= e[0] and t < e[1]:
				Input.action_press(e[2], e[3])
			elif t >= e[1] and t < e[1] + 0.02:
				Input.action_release(e[2])
		if t >= next_log and car:
			next_log += 0.5
			print("t=%5.2f kmh=%6.1f y=%5.2f wheels=%d drift=%s boost=%.2f yaw=%6.1f" % [t, car.get_speed_kmh(),
				car.global_position.y, car.wheels_on_ground, car.drifting, car.boost_meter, car.rotation_degrees.y])
		if shot_i < shots.size() and t >= shots[shot_i]:
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/shot_%02d.png" % [out_dir, shot_i])
			shot_i += 1
	quit()
