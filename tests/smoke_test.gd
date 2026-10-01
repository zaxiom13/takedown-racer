extends SceneTree
## Headless smoke test: instantiates each scene, runs it for a few frames, quits.
## Run via tools/check.sh. Exit code 0 = all scenes loaded.

const SCENES := [
	"res://scenes/main.tscn",
]
const FRAMES_PER_SCENE := 120

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in SCENES:
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("SMOKE FAIL: cannot load %s" % path)
			_failed = true
			continue
		var inst := packed.instantiate()
		root.add_child(inst)
		for i in FRAMES_PER_SCENE:
			await physics_frame
		if inst.has_method("smoke_check"):
			var msg: String = inst.smoke_check()
			if msg != "":
				printerr("SMOKE FAIL: %s: %s" % [path, msg])
				_failed = true
		inst.queue_free()
		await process_frame
		print("SMOKE OK: %s" % path)
	quit(1 if _failed else 0)
