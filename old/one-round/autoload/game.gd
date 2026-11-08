extends Node
## Run-level state (which room, totals), scene changes, input map and audio helpers.

const MAIN_SCENE := "res://scenes/main.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const MUSIC_FORWARD := "res://assets/audio/music.ogg"
const MUSIC_REVERSED := "res://assets/audio/music_reversed.ogg"

## Emitted when the graphics preset changes (F10). World re-applies its environment and lights.
signal quality_changed

var solo := false
## "high": SDFGI bounce light, soft shadows on every torch, volumetric fog.
## "low": no GI, shadows only on a few key lights, cheaper fog. Toggle with F10 or start with --low.
var quality := "high"
var in_run := false
var room_index := 0
var run_start := 0.0
var total_deaths := 0
var total_pincers := 0
var total_time := 0.0
var total_loot := 0
var best_chain := 0
var title_message := ""
## Mouse sensitivity multiplier (settings menu).
var sensitivity := 1.0
## Plays the eyes-open cinematic before the first room of a run.
var opening_seen := false
## Set by World while a run is loaded.
var world: Node = null

var _sounds := {}
var _music: AudioStreamPlayer


func _enter_tree() -> void:
	_setup_input()


const SETTINGS := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.lost.connect(_on_net_lost)
	_load_settings()
	if Net.cli.has("low"):
		quality = "low"
	# Fullscreen by default (project setting); --windowed for tests or two instances on one PC.
	if Net.cli.has("windowed") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		var screen := DisplayServer.window_get_current_screen()
		var ss := DisplayServer.screen_get_size(screen)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (ss - Vector2i(1600, 900)) / 2)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_fullscreen(not is_fullscreen())
	elif event.is_action_pressed("toggle_quality"):
		set_quality("low" if quality == "high" else "high")


func high_quality() -> bool:
	return quality == "high"


func set_quality(q: String) -> void:
	quality = q
	quality_changed.emit()
	save_settings()


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func set_sensitivity(v: float) -> void:
	sensitivity = clampf(v, 0.2, 3.0)
	save_settings()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "quality", quality)
	cf.set_value("game", "sensitivity", sensitivity)
	cf.save(SETTINGS)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return
	quality = String(cf.get_value("game", "quality", quality))
	sensitivity = float(cf.get_value("game", "sensitivity", sensitivity))


func _setup_input() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("crouch", KEY_CTRL)
	_key("crouch", KEY_C)
	_key("dash", KEY_F)
	_mouse("primary", MOUSE_BUTTON_LEFT)
	_mouse("throw", MOUSE_BUTTON_RIGHT)
	_key("interact", KEY_E)
	_key("ping", KEY_Q)
	_mouse("ping", MOUSE_BUTTON_MIDDLE)
	_key("restart", KEY_R)
	_key("swap_role", KEY_TAB)
	_key("release_mouse", KEY_ESCAPE)
	_key("toggle_fullscreen", KEY_F11)
	_key("toggle_quality", KEY_F10)


func _key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# --- Run flow ------------------------------------------------------------------

## Host calls this (rpc) to move everyone into the game scene.
@rpc("authority", "call_local", "reliable")
func start_run(solo_mode: bool) -> void:
	solo = solo_mode
	in_run = true
	opening_seen = false
	room_index = 0
	total_deaths = 0
	total_pincers = 0
	total_time = 0.0
	total_loot = 0
	best_chain = 0
	run_start = Net.now()
	get_tree().change_scene_to_file(GAME_SCENE)
	_start_music()


func return_to_title(message := "") -> void:
	in_run = false
	world = null
	title_message = message
	if _music:
		_music.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_SCENE)


func quit_to_title(message := "") -> void:
	Net.leave()
	return_to_title(message)


func _on_net_lost(reason: String) -> void:
	if in_run:
		quit_to_title(reason)


# --- Audio --------------------------------------------------------------------

func _stream(name: String, reversed: bool) -> AudioStream:
	var key := name + ("_r" if reversed else "")
	if not _sounds.has(key):
		var path := "res://assets/audio/%s/%s.wav" % ["reversed" if reversed else "forward", name]
		_sounds[key] = load(path) if ResourceLoader.exists(path) else null
	return _sounds[key]


## Play a sound. Anything NOEL does plays the reversed copy, on both PCs.
func sfx(name: String, reversed := false, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _stream(name, reversed)
	if stream == null:
		return
	if pos == null or world == null:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db + 4.0
		p3.pitch_scale = pitch
		p3.unit_size = 6.0
		p3.max_db = 6.0
		world.add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)


## Music slot: drop music.ogg (and a pre-reversed music_reversed.ogg) into assets/audio/.
## LEON's PC plays it forwards and NOEL's plays it reversed, both locked to the host clock.
func _start_music() -> void:
	var path := MUSIC_REVERSED if (Net.my_role == Util.B and not solo) else MUSIC_FORWARD
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.volume_db = -8.0
		add_child(_music)
	_music.stream = stream
	var length := stream.get_length()
	_music.play(fmod(maxf(Net.now() - run_start, 0.0), length) if length > 0.0 else 0.0)
