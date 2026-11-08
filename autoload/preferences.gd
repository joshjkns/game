extends Node
## Persistent user options, separate from the per-run state in Run.

const CONFIG_PATH := "user://settings.cfg"

var master_volume := 1.0
var mouse_sensitivity := 1.0
var field_of_view := 88.0
var fullscreen := false
var show_crosshair := true
var camera_shake := true
## Multiplier on the HUD's base size.
var hud_scale := 1.0
## Last difficulty played; the picker opens on it.
var difficulty := "medium"
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
		mouse_sensitivity = clampf(float(config.get_value("controls", "mouse_sensitivity", mouse_sensitivity)), 0.4, 2.0)
		field_of_view = clampf(float(config.get_value("video", "field_of_view", field_of_view)), 70.0, 110.0)
		show_crosshair = bool(config.get_value("video", "show_crosshair", show_crosshair))
		camera_shake = bool(config.get_value("video", "camera_shake", camera_shake))
		hud_scale = clampf(float(config.get_value("video", "hud_scale", hud_scale)), 0.6, 1.4)
		difficulty = String(config.get_value("game", "difficulty", difficulty))
		if config.has_section_key("video", "fullscreen"):
			fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
			_apply_fullscreen()
	_apply_master_volume()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer.timeout.connect(_save)
	add_child(_save_timer)


func _exit_tree() -> void:
	_save()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_master_volume()
	_schedule_save()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.4, 2.0)
	_schedule_save()


func set_field_of_view(value: float) -> void:
	field_of_view = clampf(value, 70.0, 110.0)
	_schedule_save()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()
	_schedule_save()


func set_crosshair_visible(value: bool) -> void:
	show_crosshair = value
	_schedule_save()


func set_camera_shake(value: bool) -> void:
	camera_shake = value
	_schedule_save()


func set_hud_scale(value: float) -> void:
	hud_scale = clampf(value, 0.6, 1.4)
	_schedule_save()


func set_difficulty(value: String) -> void:
	difficulty = value
	_schedule_save()


func _apply_master_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_linear(bus, master_volume)


func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _schedule_save() -> void:
	if is_instance_valid(_save_timer):
		_save_timer.start()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("video", "field_of_view", field_of_view)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "show_crosshair", show_crosshair)
	config.set_value("video", "camera_shake", camera_shake)
	config.set_value("video", "hud_scale", hud_scale)
	config.set_value("game", "difficulty", difficulty)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Couldn't save settings: %s" % error_string(error))
