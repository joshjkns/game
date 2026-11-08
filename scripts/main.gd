extends Node
## Game flow: title → run of acts. Each act is COMBAT_ROOMS fights, then the
## shop, then the boss. Rooms are rebuilt from scratch.

var arena: Arena
var player: Player
var hud: Hud
var screens: Screens
var fade: ColorRect
var _title_cam: Camera3D
var _busy := false
var _title: TitleScene
var _ui_root: Control
var cutscene: Cutscene
## Background music: the title theme, then one loop per era. Two players to cross-fade.
const MUSIC_DB := -11.0
var _music: Array[AudioStreamPlayer] = []
var _music_track := ""
## Off under the autotest, which drives rooms on frame counts.
var cutscenes := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Run.DIFFICULTIES.has(Preferences.difficulty):
		Run.difficulty = Preferences.difficulty
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_ui_root)
	hud = Hud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(hud)
	fade = ColorRect.new()
	fade.color = Color(0.015, 0.05, 0.045, 0.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(fade)
	screens = Screens.new()
	screens.process_mode = Node.PROCESS_MODE_ALWAYS
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(screens)
	for i in 2:
		var mp := AudioStreamPlayer.new()
		mp.bus = "Master"
		mp.volume_db = -80.0
		add_child(mp)
		_music.append(mp)
	cutscene = Cutscene.new()
	cutscene.main = self
	add_child(cutscene)
	_sync_ui_layout()
	get_viewport().size_changed.connect(_sync_ui_layout)
	screens.start_pressed.connect(start_run)
	screens.choose_hero_pressed.connect(_show_hero_select)
	screens.hero_chosen.connect(_on_hero_chosen)
	screens.hero_previewed.connect(_on_hero_previewed)
	screens.difficulty_chosen.connect(_on_difficulty_chosen)
	screens.power_chosen.connect(_on_power)
	screens.shop_closed.connect(_close_menu)
	screens.resume_pressed.connect(_close_menu)
	screens.title_pressed.connect(to_title)
	screens.title_shown.connect(_on_title_shown)
	screens.era_previewed.connect(func(b): if _title and is_instance_valid(_title): _title.show_biome(b))
	screens.era_chosen.connect(_on_era_chosen)
	screens.era_closed.connect(_on_era_closed)
	if "--autotest" in OS.get_cmdline_user_args():
		cutscenes = false
		var t := Autotest.new()
		t.main = self
		add_child(t)
		return
	to_title()


func _sync_ui_layout() -> void:
	if not is_instance_valid(_ui_root):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_ui_root.position = Vector2.ZERO
	_ui_root.size = viewport_size


func to_title() -> void:
	get_tree().paused = false
	_menu_kind = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_world()
	_title = TitleScene.new()
	_title.map_shown.connect(screens.set_map_caption)
	add_child(_title)
	hud.player = null
	screens.show_title()
	play_music("title")


func play_music(track: String) -> void:
	if track == _music_track or DisplayServer.get_name() == "headless":
		return
	_music_track = track
	var old := _music[0]
	var new := _music[1]
	_music.reverse()
	new.stream = load("res://assets/audio/music/%s.wav" % track)
	new.volume_db = -40.0
	new.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(new, "volume_db", MUSIC_DB, 1.2)
	tw.tween_property(old, "volume_db", -80.0, 1.2)
	tw.chain().tween_callback(old.stop)


func _process(delta: float) -> void:
	if _title_cam and is_instance_valid(_title_cam):
		var t := Time.get_ticks_msec() / 1000.0 * 0.06
		_title_cam.global_position = Vector3(sin(t) * 20.0, 6.0, cos(t) * 20.0)
		_title_cam.look_at(Vector3(0, 2, 0))


func start_run() -> void:
	Run.start(Run.hero)
	_menu_kind = ""
	screens.close()
	get_tree().paused = false
	load_room()


func _show_hero_select() -> void:
	screens.show_hero_select()


func _on_title_shown() -> void:
	if _title and is_instance_valid(_title):
		_title.clear_weapon()
		_title.release_hold()


## Era select: start a fresh run, possibly part-way through. Later eras hand you a better gun and
## some coins so the jump in difficulty isn't a wall.
func _on_era_chosen(biome: String, boss: bool) -> void:
	Run.start(Run.hero)
	Run.act = TitleScene.BIOMES.find(biome) + 1
	if Run.act > 1:
		Run.weapons[0].tier = Run.act - 1
		Run.coins = 60 * (Run.act - 1)
	if boss:
		Run.room = Run.COMBAT_ROOMS + 1
	Run.hp = Run.max_hp()
	Run.shield = Run.max_shield()
	Run.changed.emit()
	_menu_kind = ""
	screens.close()
	get_tree().paused = false
	load_room()


func _on_hero_previewed(id: String) -> void:
	if _title and is_instance_valid(_title):
		_title.set_weapon(Heroes.DEFS[id].weapon)


func _on_hero_chosen(id: String) -> void:
	Run.hero = id
	screens.show_difficulty(Run.difficulty)


func _on_difficulty_chosen(id: String) -> void:
	Run.difficulty = id
	Preferences.set_difficulty(id)
	if _title and is_instance_valid(_title):
		_title.clear_weapon()
	screens.show_era_select()


func _on_era_closed() -> void:
	if _title and is_instance_valid(_title):
		_title.release_hold()


func _clear_world() -> void:
	cutscene.stop()
	if arena:
		arena.queue_free()
		remove_child(arena)
	arena = null
	player = null
	if _title:
		_title.queue_free()
		_title = null
	_title_cam = null


func room_kind() -> String:
	if Run.room < Run.COMBAT_ROOMS:
		return "combat"
	if Run.room == Run.COMBAT_ROOMS:
		return "shop"
	return "boss"


func load_room() -> void:
	_clear_world()
	arena = Arena.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	var kind := room_kind()
	play_music(Run.biome())
	arena.cinematic = cutscenes
	arena.build(kind)
	arena.prop_used.connect(_on_prop)
	if cutscenes:
		arena.boss_spawned.connect(cutscene.boss_intro)
		arena.cleared.connect(func(): if kind == "boss": cutscene.boss_outro())
	player = Player.new()
	arena.add_child(player)
	player.global_position = arena._floor_at(Arena.START) + Vector3.UP * 0.2
	player.died.connect(_on_died)
	hud.player = player
	hud.set_hero(Run.hero)
	if kind == "shop":
		Run.refresh_shop()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match kind:
		"combat":
			hud.show_banner("ROOM %d" % (Run.room + 1))
		"shop": hud.show_banner("SHOP", Hud.CREAM, "Prepare for the boss" if Run.is_boss_level() else "")
		"boss":
			if not cutscenes:
				hud.show_banner("BOSS")


func _unhandled_input(event: InputEvent) -> void:
	if cutscene.playing != "":
		for a in ["fire", "jump", "interact", "pause"]:
			if event.is_action_pressed(a):
				cutscene.skip()
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and player != null:
		if screens.is_open():
			if _menu_kind == "pause" and screens.has_pause_submenu():
				screens.back_from_submenu()
			elif not get_tree().paused or _menu_kind == "pause" or _menu_kind == "shop":
				_close_menu()
		else:
			_open_menu("pause")
			screens.show_pause()
	elif event is InputEventMouseButton and event.pressed and player and not screens.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


var _menu_kind := ""


func _open_menu(kind: String) -> void:
	_menu_kind = kind
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	if _menu_kind == "pick":
		return
	_menu_kind = ""
	screens.close()
	get_tree().paused = false
	if player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_prop(p: Prop) -> void:
	match p.kind:
		"portal":
			advance()
		"relic":
			_open_menu("pick")
			screens.show_pick(Run.power_choices())
		"vendor":
			_open_menu("shop")
			screens.show_shop()


func _on_power(id: String) -> void:
	if id != "":
		Run.take_power(id)
		hud.show_banner(Run.POWERS[id].name.to_upper())
	_menu_kind = ""
	_close_menu()


func advance() -> void:
	if _busy:
		return
	_busy = true
	Kit.sfx(self, "rewind", null, -2.0, 1.3)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.18)
	await tw.finished
	Run.room += 1
	var last := Run.COMBAT_ROOMS + (1 if Run.is_boss_level() else 0)
	if Run.room > last:
		if not Run.next_level():
			_busy = false
			fade.color.a = 0.0
			_end(true)
			return
	load_room()
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.25)
	_busy = false


func _on_died() -> void:
	await get_tree().create_timer(1.0).timeout
	_end(false)


func _end(won: bool) -> void:
	_open_menu("end")
	screens.show_end(won)
