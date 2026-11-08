extends Control
## Title screen and lobby. HOST opens the lobby; JOIN asks for the host's address first.
## PRACTICE starts a one-PC session (Tab swaps agents).

var _backdrop: Stage
var _home: Control
var _menu: VBoxContainer
var _join: VBoxContainer
var _ip: LineEdit
var _status: Label
var _modal: Control
var _lobby: LobbyScreen
var _top: HBoxContainer

static var _last_ip := "127.0.0.1"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.failed.connect(_on_failed)
	Net.lost.connect(_on_lost)
	Net.roles_changed.connect(_sync_screen)
	if Game.title_message != "":
		_say(Game.title_message)
		Game.title_message = ""
	_sync_screen()
	_auto_from_cli()


func _build() -> void:
	_backdrop = Stage.backdrop()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	# Darken the left third so the menu reads over the scene.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(Ui.INK, 0.92))
	g.add_point(0.45, Color(Ui.INK, 0.55))
	g.set_color(g.get_point_count() - 1, Color(Ui.INK, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.75
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_home = Control.new()
	_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_home)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.offset_left = 110
	col.add_theme_constant_override("separation", 0)
	_home.add_child(col)

	var title := Ui.label("ONE ROUND", 64, Ui.TEXT, Ui.DISPLAY, 14)
	col.add_child(title)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 10)
	col.add_child(under)
	under.add_child(Ui.rect(Util.AMBER, Vector2(28, 2)))
	under.add_child(Ui.rect(Util.CYAN, Vector2(28, 2)))
	for c in under.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag := Ui.label("ONE GUN  ·  TWO DIRECTIONS", 13, Ui.MUTED, Ui.LABEL)
	under.add_child(tag)
	col.add_child(_spacer(56))

	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", 0)
	col.add_child(rail)
	var line := Ui.rect(Ui.LINE, Vector2(1, 0))
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(line)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	rail.add_child(_menu)
	var host := Ui.menu_item("HOST GAME", Util.AMBER)
	host.pressed.connect(_on_host)
	_menu.add_child(host)
	var join := Ui.menu_item("JOIN GAME", Util.CYAN)
	join.pressed.connect(_show_join.bind(true))
	_menu.add_child(join)
	var solo := Ui.menu_item("PRACTICE")
	solo.pressed.connect(_on_solo)
	_menu.add_child(solo)
	var quit := Ui.menu_item("QUIT")
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu.add_child(quit)

	_join = VBoxContainer.new()
	_join.add_theme_constant_override("separation", 14)
	_join.visible = false
	rail.add_child(_join)
	var jl := Ui.label("HOST ADDRESS", 13, Ui.MUTED, Ui.LABEL)
	_join.add_child(_indent(jl))
	_ip = LineEdit.new()
	_ip.text = _last_ip
	_ip.placeholder_text = "192.168.0.10"
	_ip.custom_minimum_size = Vector2(300, 0)
	_ip.add_theme_font_override("font", Ui.font(Ui.NUMBER, 2))
	_ip.add_theme_font_size_override("font_size", 30)
	_ip.add_theme_color_override("font_color", Ui.TEXT)
	_ip.add_theme_color_override("font_placeholder_color", Ui.FAINT)
	_ip.add_theme_color_override("caret_color", Util.CYAN)
	var under_line := StyleBoxFlat.new()
	under_line.bg_color = Color(0, 0, 0, 0)
	under_line.border_width_bottom = 1
	under_line.border_color = Color(1, 1, 1, 0.3)
	under_line.content_margin_bottom = 6
	var under_focus := under_line.duplicate() as StyleBoxFlat
	under_focus.border_color = Util.CYAN
	under_focus.border_width_bottom = 2
	_ip.add_theme_stylebox_override("normal", under_line)
	_ip.add_theme_stylebox_override("focus", under_focus)
	_ip.text_submitted.connect(func(_t: String) -> void: _on_join())
	_join.add_child(_indent(_ip))
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 10)
	var connect_btn := Ui.button("CONNECT", Util.CYAN, true, 15)
	connect_btn.pressed.connect(_on_join)
	jrow.add_child(connect_btn)
	var back := Ui.button("BACK", Ui.TEXT, false, 15)
	back.pressed.connect(_show_join.bind(false))
	jrow.add_child(back)
	_join.add_child(_indent(jrow))

	col.add_child(_spacer(40))
	_status = Ui.label("", 14, Util.RED, Ui.LABEL)
	_status.custom_minimum_size = Vector2(420, 20)
	col.add_child(_indent(_status, 29))

	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 28)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_top.offset_right = -48
	_top.offset_top = 36
	_home.add_child(_top)
	_top.add_child(_top_link("CONTROLS", func() -> void: _open_modal(Panels.controls())))
	_top.add_child(_top_link("SETTINGS", func() -> void: _open_modal(Panels.settings())))

	var ver := Ui.label("F11 FULLSCREEN  ·  F10 GRAPHICS", 11, Ui.FAINT, Ui.LABEL)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -48
	ver.offset_bottom = -32
	_home.add_child(ver)

	# Hold a black curtain until the 3D backdrop has drawn (its shaders compile on the first
	# frames), then fade it, so the title never hitches or pops in.
	var curtain := Ui.rect(Color.BLACK)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(curtain)
	_lift_curtain(curtain)


func _lift_curtain(curtain: ColorRect) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	if not is_instance_valid(curtain):
		return
	var tw := curtain.create_tween()
	tw.tween_property(curtain, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(curtain.queue_free)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _indent(c: Control, px := 28) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


func _top_link(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Ui.font(Ui.LABEL, 3))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Ui.MUTED)
	b.add_theme_color_override("font_hover_color", Ui.TEXT)
	b.add_theme_color_override("font_pressed_color", Ui.TEXT)
	b.pressed.connect(on_press)
	b.pressed.connect(func() -> void: Game.sfx("ui", false, null, -8.0))
	return b


# --- Screens ----------------------------------------------------------------------

func _show_join(on: bool) -> void:
	_menu.visible = not on
	_join.visible = on
	_say("")
	if on:
		Ui.appear(_join, 0.0, Vector2.ZERO, 0.2)
		_ip.grab_focus()
		_ip.caret_column = _ip.text.length()
	else:
		Ui.appear(_menu, 0.0, Vector2.ZERO, 0.2)


## Show the lobby whenever we are in one, the home screen otherwise.
func _sync_screen() -> void:
	var want := Net.in_lobby()
	if want and _lobby == null:
		_close_modal()
		_lobby = LobbyScreen.new()
		_lobby.leave_requested.connect(_leave_lobby)
		add_child(_lobby)
		_lobby.modulate.a = 0.0
		Game.sfx("card")
		_fade_in(_lobby)
	elif not want and _lobby != null:
		var l := _lobby
		_lobby = null
		var tw := l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, 0.2)
		tw.tween_callback(l.queue_free)
		_show_join(false)
	_home.visible = _lobby == null
	_backdrop.visible = true


## Fade in once the new screen's 3D portraits have drawn a couple of frames.
func _fade_in(c: Control) -> void:
	for i in 2:
		await RenderingServer.frame_post_draw
	if is_instance_valid(c):
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.25)


func _leave_lobby() -> void:
	Net.leave()
	_sync_screen()


func _open_modal(panel: Control) -> void:
	_close_modal()
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_modal)
	var dim := Ui.rect(Color(0, 0, 0, 0.6))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_modal())
	_modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	box.add_child(panel)
	var close := Ui.button("CLOSE", Ui.TEXT, false, 14)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close_modal)
	box.add_child(close)
	Ui.appear(box, 0.0, Vector2.ZERO, 0.2)
	Game.sfx("card", false, null, -6.0)


func _close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		if _modal:
			_close_modal()
		elif _join.visible:
			_show_join(false)
		get_viewport().set_input_as_handled()


func _say(text: String, color := Util.RED) -> void:
	_status.text = text.to_upper()
	_status.add_theme_color_override("font_color", color)


# --- Actions ------------------------------------------------------------------------

func _on_host() -> void:
	var role := ""
	if Net.cli.has("host"):
		role = Util.B if String(Net.cli.get("role", "A")).to_upper() == "B" else Util.A
	var err := Net.host(role)
	if err != OK:
		_say("Could not host on port %d (%s)" % [Net.PORT, error_string(err)])
	_sync_screen()


func _on_join() -> void:
	var ip := _ip.text.strip_edges()
	if ip == "":
		_ip.grab_focus()
		return
	_last_ip = ip
	var err := Net.join(ip)
	if err == OK:
		_say("Connecting to %s" % ip, Ui.MUTED)
	else:
		_say("Could not connect (%s)" % error_string(err))


func _on_solo() -> void:
	Net.leave()
	Net.my_role = Util.A
	Net.roles = {1: Util.A}
	Game.start_run(true)


func _on_failed(reason: String) -> void:
	_say(reason)
	_sync_screen()


func _on_lost(reason: String) -> void:
	if Game.in_run:
		return
	_say(reason, Ui.MUTED if Net.is_host() else Util.RED)
	_sync_screen()


func _auto_from_cli() -> void:
	if Game.in_run:
		return
	if Net.cli.has("solo"):
		_on_solo.call_deferred()
	elif Net.cli.has("host") and not Net.is_connected_peer():
		_on_host()
	elif Net.cli.has("join") and not Net.is_connected_peer():
		_ip.text = String(Net.cli.join)
		_on_join()
