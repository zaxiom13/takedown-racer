extends SceneTree
## Lets the LineFollower AI drive the player car around the race track; logs laps/checkpoints and
## saves screenshots. Usage: godot --path . -s res://tests/race_capture.gd -- <out_dir> [seconds]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/cap"
	var secs := float(args[1]) if args.size() > 1 else 90.0
	var s: Node = (load("res://scenes/race.tscn") as PackedScene).instantiate()
	s.set("laps", 1)
	root.add_child(s)
	var race: RaceManager = s.race
	var ai := LineFollower.new()
	s.add_child(ai)
	ai.setup(s.track, s.car)
	race.checkpoint_passed.connect(func(i: int, t: float) -> void: print("checkpoint %d at %.2f" % [i, t]))
	race.lap_completed.connect(func(l: int, t: float) -> void: print("LAP %d: %.2f" % [l, t]))
	race.race_finished.connect(func(t: float) -> void: print("FINISHED %.2f" % t))
	var t := 0.0
	var next_shot := float(args[2]) if args.size() > 2 else 2.0
	var shot_every := float(args[3]) if args.size() > 3 else 12.0
	var shot := 0
	while t < secs and not race.finished:
		await physics_frame
		t += 1.0 / 60.0
		if t >= next_shot and DisplayServer.get_name() != "headless":
			next_shot += shot_every
			await process_frame
			root.get_viewport().get_texture().get_image().save_png("%s/race_%02d.png" % [out, shot])
			shot += 1
		if int(t * 60) % 300 == 0:
			print("t=%.0f kmh=%.0f pos=%s progress=%.0f/%.0f" % [t, s.car.get_speed_kmh(), s.car.global_position.snapped(Vector3.ONE), race.progress, s.track.line_length])
	quit()
