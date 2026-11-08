class_name LobbyScreen
extends Control
## Character select, split 50/50: LEON on the left, NOEL on the right. Click a side (or A / D)
## to claim it, then READY (Enter). When both agents are claimed and ready, a short countdown
## runs and the host starts the run.

signal leave_requested

const COUNTDOWN := 3.0

var _seats := {}
var _ready_btn: Button
var _leave_btn: Button
var _info: Label
var _count: Label
var _count_sub: Label
var _count_t := -1.0
var _auto := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_auto = Net.cli.has("host") or Net.cli.has("join")
	var bg := Ui.rect(Ui.INK)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_seats[Util.A] = _seat(Util.A, 0.0, 0.5)
	_seats[Util.B] = _seat(Util.B, 0.5, 1.0)
	var divider := Ui.rect(Color(1, 1, 1, 0.1))
	divider.anchor_left = 0.5
	divider.anchor_right = 0.5
	divider.anchor_bottom = 1.0
	divider.offset_right = 1
	add_child(divider)

	var head := Ui.label("CHOOSE YOUR AGENT", 15, Ui.MUTED, Ui.LABEL)
	head.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.grow_horizontal = Control.GROW_DIRECTION_BOTH
	head.offset_top = 36
	add_child(head)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -44
	add_child(bar)
	_leave_btn = Ui.button("LEAVE", Ui.TEXT, false, 15)
	_leave_btn.pressed.connect(func() -> void: leave_requested.emit())
	bar.add_child(_leave_btn)
	_ready_btn = Ui.button("READY", Ui.TEXT, true, 15)
	_ready_btn.custom_minimum_size.x = 170
	_ready_btn.pressed.connect(_toggle_ready)
	bar.add_child(_ready_btn)

	_info = Ui.label("", 14, Ui.MUTED, Ui.LABEL)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_bottom = -110
	add_child(_info)

	_count = Ui.label("", 120, Ui.TEXT, Ui.DISPLAY, 0)
	_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count.grow_vertical = Control.GROW_DIRECTION_BOTH
	_count.offset_top = -40
	add_child(_count)
	_count_sub = Ui.label("STARTING", 14, Ui.MUTED, Ui.LABEL)
	_count_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_count_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count_sub.offset_top = 50
	add_child(_count_sub)

	Net.roles_changed.connect(_refresh)
	_refresh()


func _seat(role: String, a0: float, a1: float) -> Dictionary:
	var c := Util.role_color(role)
	var left := role == Util.A
	var root := Control.new()
	root.anchor_left = a0
	root.anchor_right = a1
	root.anchor_bottom = 1.0
	root.clip_contents = true
	add_child(root)

	var tint := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(c.darkened(0.88), 1.0))
	g.set_color(1, Color(c.darkened(0.55), 1.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	tint.texture = gt
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tint)

	# The other agent's name, huge and faint, as a texture behind the figure.
	var ghost := Ui.label("LEON" if left else "NOEL", 300, Color(c, 0.06), Ui.DISPLAY, 10)
	ghost.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ghost.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ghost.grow_vertical = Control.GROW_DIRECTION_BOTH
	ghost.offset_top = -60
	root.add_child(ghost)

	var stage := Stage.portrait(role)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_top = 40
	root.add_child(stage)

	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(st, empty)
	hit.pressed.connect(func() -> void: _claim(role))
	root.add_child(hit)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	name_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	name_box.grow_horizontal = Control.GROW_DIRECTION_END if left else Control.GROW_DIRECTION_BEGIN
	name_box.offset_left = 64 if left else 0
	name_box.offset_right = 0 if left else -64
	name_box.offset_bottom = -150
	root.add_child(name_box)
	var align := HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	var tag := Ui.label("", 13, Ui.TEXT, Ui.LABEL)
	tag.horizontal_alignment = align
	name_box.add_child(tag)
	var nm := Ui.label(Util.role_name(role), 84, Ui.TEXT, Ui.DISPLAY)
	nm.horizontal_alignment = align
	name_box.add_child(nm)
	var line := Ui.rect(c, Vector2(56, 2))
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if left else Control.SIZE_SHRINK_END
	name_box.add_child(line)
	var sub := Ui.label("FORWARD  ·  FIRES THE ROUND" if left else "INVERTED  ·  RECALLS THE ROUND", 14, Color(c, 0.9), Ui.LABEL)
	sub.horizontal_alignment = align
	name_box.add_child(sub)

	var keyhint := Ui.label("A" if left else "D", 13, Ui.FAINT, Ui.NUMBER, 2)
	keyhint.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if left else Control.PRESET_TOP_RIGHT)
	keyhint.offset_left = 40 if left else -60
	keyhint.offset_right = 60 if left else -40
	keyhint.offset_top = 36
	root.add_child(keyhint)

	hit.mouse_entered.connect(func() -> void: _hover(role, true))
	hit.mouse_exited.connect(func() -> void: _hover(role, false))
	return {"root": root, "stage": stage, "tag": tag, "name": nm, "tint": tint, "hover": false, "c": c}


func _hover(role: String, on: bool) -> void:
	_seats[role].hover = on
	if on and Net.lobby_owner(role) == 0:
		Game.sfx("ui", false, null, -16.0, 1.4)
	_refresh()


func _claim(role: String) -> void:
	var holder := Net.lobby_owner(role)
	if holder == multiplayer.get_unique_id():
		return
	if holder != 0:
		Game.sfx("ui", false, null, -6.0, 0.6)
		return
	Game.sfx("catch", role == Util.B, null, -4.0)
	Net.pick(role)


func _toggle_ready() -> void:
	var me := Net.me()
	if me.role == "":
		return
	Net.set_ready(not me.ready)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_A, KEY_LEFT:
				_claim(Util.A)
			KEY_D, KEY_RIGHT:
				_claim(Util.B)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_toggle_ready()
			KEY_ESCAPE:
				leave_requested.emit()
			_:
				return
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var my_id := multiplayer.get_unique_id()
	var me := Net.me()
	for role: String in _seats:
		var s: Dictionary = _seats[role]
		var holder := Net.lobby_owner(role)
		var entry: Dictionary = Net.lobby.get(holder, {})
		var mine := holder != 0 and holder == my_id
		var taken := holder != 0
		var ready: bool = taken and entry.ready
		var tag: Label = s.tag
		if mine:
			tag.text = "YOU  ·  READY" if ready else "YOU"
			tag.add_theme_color_override("font_color", s.c)
		elif taken:
			tag.text = "PARTNER  ·  READY" if ready else "PARTNER"
			tag.add_theme_color_override("font_color", Ui.TEXT)
		else:
			tag.text = "OPEN" if Net.partner_connected() or me.role == "" else "WAITING FOR PARTNER"
			tag.add_theme_color_override("font_color", Ui.FAINT)
		var stage: Stage = s.stage
		var lit: bool = taken or s.hover
		var target := Color(1, 1, 1, 1) if lit else Color(0.38, 0.38, 0.42, 1)
		stage.create_tween().tween_property(stage, "modulate", target, 0.2)
		(s.tint as CanvasItem).create_tween().tween_property(s.tint, "modulate:a", 1.0 if lit else 0.55, 0.2)
		var gun: GunModel = stage.get_meta("gun")
		var body: Humanoid = stage.get_meta("body")
		gun.visible = ready
		body.aim = 0.85 if ready else 0.0
		body.aim_pitch = -0.25
	_ready_btn.disabled = me.role == ""
	_ready_btn.text = "CANCEL" if me.ready else "READY"
	var accent := Util.role_color(me.role) if me.role != "" else Ui.TEXT
	_ready_btn.add_theme_stylebox_override("normal", _fill(accent if not me.ready else Color(0, 0, 0, 0.3), me.ready))
	_ready_btn.add_theme_color_override("font_color", Ui.TEXT if me.ready else Ui.INK)
	_info.text = _info_text(me)
	if Net.all_ready():
		if _count_t == -1.0:
			_count_t = 0.4 if _auto else COUNTDOWN
			Game.sfx("card")
	else:
		_count_t = -1.0
	_count.visible = _count_t >= 0.0
	_count_sub.visible = _count.visible
	if _auto:
		_auto_step(me)


func _fill(c: Color, outline: bool) -> StyleBoxFlat:
	var sb := Ui.flat(c, 2, 1 if outline else 0, Color(1, 1, 1, 0.3))
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 11
	sb.content_margin_bottom = 11
	return sb


func _info_text(me: Dictionary) -> String:
	if not Net.partner_connected():
		if Net.is_host():
			var ips := Net.local_ips()
			return "WAITING FOR PARTNER  ·  YOUR ADDRESS  %s" % (ips[0] if not ips.is_empty() else "127.0.0.1")
		return "CONNECTING"
	if me.role == "":
		return "PICK AN AGENT"
	if not me.ready:
		return "PRESS READY WHEN SET"
	return "WAITING FOR PARTNER" if not Net.all_ready() else ""


## Command-line runs (tests, two local instances): claim the free agent and ready up.
func _auto_step(me: Dictionary) -> void:
	if me.role == "":
		var want := String(Net.cli.get("role", "A")).to_upper() if Net.is_host() else ""
		var role := Util.B if want == "B" else Util.A
		if want == "" or Net.lobby_owner(role) != 0:
			role = Util.A if Net.lobby_owner(Util.A) == 0 else Util.B
		if Net.lobby_owner(role) == 0:
			Net.pick(role)
	elif not me.ready:
		Net.set_ready(true)


func _process(delta: float) -> void:
	if _count_t < 0.0:
		return
	var before := ceili(_count_t)
	_count_t -= delta
	var n := ceili(maxf(_count_t, 0.0))
	_count.text = str(maxi(n, 1))
	if n != before and n > 0:
		Game.sfx("ui", false, null, -6.0, 0.9)
		_count.pivot_offset = _count.size * 0.5
		_count.scale = Vector2(1.25, 1.25)
		_count.create_tween().tween_property(_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _count_t <= 0.0:
		_count_t = -2.0
		_count.visible = false
		_count_sub.visible = false
		if Net.is_host() and Net.all_ready() and not Game.in_run:
			Game.start_run.rpc(false)
