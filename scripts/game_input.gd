extends Node
## Autoload: registers input actions (keyboard + gamepad) so project.godot stays readable.

const ACTIONS := {
	"accelerate": [KEY_W, KEY_UP, JOY_BUTTON_A, "axis:%d" % JOY_AXIS_TRIGGER_RIGHT],
	"brake": [KEY_S, KEY_DOWN, JOY_BUTTON_X, "axis:%d" % JOY_AXIS_TRIGGER_LEFT],
	"steer_left": [KEY_A, KEY_LEFT, "axis:-%d" % JOY_AXIS_LEFT_X],
	"steer_right": [KEY_D, KEY_RIGHT, "axis:%d" % JOY_AXIS_LEFT_X],
	"handbrake": [KEY_SPACE, JOY_BUTTON_RIGHT_SHOULDER],
	"boost": [KEY_SHIFT, KEY_N, JOY_BUTTON_B],
	"reset_car": [KEY_R, JOY_BUTTON_BACK],
	"camera_toggle": [KEY_C, JOY_BUTTON_Y],
	"toggle_perf": [KEY_F3],
	"pause": [KEY_ESCAPE, JOY_BUTTON_START],
}


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		for binding: Variant in ACTIONS[action]:
			InputMap.action_add_event(action, _make_event(binding))


func _make_event(binding: Variant) -> InputEvent:
	if binding is String:
		var s: String = (binding as String).trim_prefix("axis:")
		var ev := InputEventJoypadMotion.new()
		ev.axis = absi(int(s)) as JoyAxis
		ev.axis_value = -1.0 if s.begins_with("-") else 1.0
		return ev
	if binding >= KEY_SPACE:
		var k := InputEventKey.new()
		k.physical_keycode = binding
		return k
	var b := InputEventJoypadButton.new()
	b.button_index = binding
	return b
