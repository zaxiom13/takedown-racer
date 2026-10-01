class_name RaceHud
extends CanvasLayer
## Speedometer + boost meter. Later milestones add lap/position/timers here.

@export var car_path: NodePath

var car: ArcadeCar
var _speed: Label
var _boost_bar: ProgressBar
var _boost_label: Label
var _info: Label
var _race_label: Label
var _center: Label
var _flash := 0.0
var race: RaceManager


func _ready() -> void:
	layer = 10
	car = get_node_or_null(car_path) as ArcadeCar
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -330
	box.offset_right = -24
	box.offset_top = -130
	box.offset_bottom = -20
	box.alignment = BoxContainer.ALIGNMENT_END
	add_child(box)
	_speed = _label(54)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_speed)
	_boost_label = _label(16)
	_boost_label.text = "BOOST"
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_boost_label)
	_boost_bar = ProgressBar.new()
	_boost_bar.custom_minimum_size = Vector2(300, 18)
	_boost_bar.max_value = 1.0
	_boost_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(1.0, 0.55, 0.05)
	fg.set_corner_radius_all(3)
	_boost_bar.add_theme_stylebox_override("background", bg)
	_boost_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(_boost_bar)
	_info = _label(22)
	_info.anchor_left = 0.5
	_info.anchor_right = 0.5
	_info.offset_left = -200
	_info.offset_right = 200
	_info.offset_top = 60
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	_race_label = _label(22)
	_race_label.position = Vector2(24, 60)
	add_child(_race_label)
	_center = _label(72)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.35
	_center.offset_left = -400
	_center.offset_right = 400
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_center)


## Hook up lap/checkpoint display.
func set_race(r: RaceManager) -> void:
	race = r
	r.checkpoint_passed.connect(func(_i: int, split: float) -> void: _show("%s" % RaceManager.fmt_time(split), 1.2))
	r.lap_completed.connect(func(l: int, lt: float) -> void: _show("LAP %d  %s" % [l, RaceManager.fmt_time(lt)], 2.0))
	r.race_finished.connect(func(total: float) -> void: _show("FINISH  %s" % RaceManager.fmt_time(total), 999.0))


func _show(text: String, secs: float) -> void:
	_center.text = text
	_flash = secs


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _process(_delta: float) -> void:
	if car == null:
		return
	_speed.text = "%d km/h" % roundi(car.get_speed_kmh())
	_boost_bar.value = car.boost_meter
	var full := car.boost_meter >= 0.999
	_boost_label.text = "BOOST  FULL" if full else "BOOST"
	_boost_bar.modulate = Color(1.6, 1.4, 1.0) if car.boosting else Color.WHITE
	_info.text = "DRIFT!" if car.drifting else ""
	if race:
		_race_label.text = "LAP %d/%d\nTIME %s\nBEST %s\nCHECKPOINT %d/%d" % [mini(race.lap, race.laps), race.laps,
			RaceManager.fmt_time(race.race_time), RaceManager.fmt_time(race.best_lap) if race.best_lap > 0.0 else "-:--.--",
			race.next_check, race.checkpoints.size()]
		if race.countdown_left > 0.0:
			_center.text = str(ceili(race.countdown_left))
		elif race.countdown_left > -0.8 and race.race_time < 0.8:
			_center.text = "GO!"
		elif _flash > 0.0:
			_flash -= _delta
		else:
			_center.text = ""
