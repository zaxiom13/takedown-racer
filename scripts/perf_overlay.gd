class_name PerfOverlay
extends CanvasLayer
## FPS / frame-time overlay. Keep in every playable scene. F3 toggles.

var _label: Label
var _accum := 0.0
var _frames := 0
var _worst_ms := 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_perf"):
		visible = not visible


func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if _accum >= 0.5:
		var avg_ms := _accum / _frames * 1000.0
		_label.text = "%d fps  %.1f ms (worst %.1f)\n%s  draws %d  prims %dk" % [
			Engine.get_frames_per_second(), avg_ms, _worst_ms,
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000]
		_accum = 0.0
		_frames = 0
		_worst_ms = 0.0
