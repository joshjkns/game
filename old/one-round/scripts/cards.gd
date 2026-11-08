class_name Cards
extends CanvasLayer
## Full-screen moments, flat and short: the opening (eyes open on the cylinder), room title,
## death, rewind, the pincer cut-in, room results and the final card.

## Eyelids over the whole screen (world, viewmodel and all): an almond-shaped opening with
## the view blurred through the screen texture's mipmaps while waking.
const LIDS := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// 0 = eyes shut, 1 = wide open.
uniform float open = 0.0;
// Mip level to sample (blur while waking).
uniform float blur = 4.0;

void fragment() {
	vec3 col = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	vec2 p = SCREEN_UV - 0.5;
	p.x *= 1.5;
	float lid = open * 0.8 * max(1.0 - pow(abs(p.x) * 1.1, 2.0), 0.0);
	float mask = 1.0 - smoothstep(-0.08, 0.02, abs(p.y) - lid);
	float vig = 1.0 - smoothstep(0.3, 0.95, length(p));
	COLOR = vec4(col * mask * mix(0.5, 1.0, mix(vig, 1.0, open * open)), 1.0);
}
"""

var _root: Control
var _lids: ColorRect
var _lids_mat: ShaderMaterial


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_lids_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LIDS
	_lids_mat.shader = sh
	_lids = Ui.rect(Color.WHITE)
	_lids.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lids.material = _lids_mat
	_lids.visible = false
	add_child(_lids)


func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size


func _clear() -> void:
	for c in _root.get_children():
		c.queue_free()


func _card() -> Control:
	_clear()
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(card)
	return card


func _fill(parent: Control, color: Color) -> ColorRect:
	var r := Ui.rect(color)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r


## A label centred horizontally at a fraction of screen height.
func _centered(parent: Control, text: String, size: int, color: Color, kind: int, y: float, spacing := -1) -> Label:
	var l := Ui.label(text, size, color, kind, spacing)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(l)
	return l


func _line(parent: Control, y: float, w: float, color: Color, delay := 0.0) -> ColorRect:
	var r := Ui.rect(color, Vector2(w, 1))
	r.anchor_left = 0.5
	r.anchor_right = 0.5
	r.anchor_top = y
	r.anchor_bottom = y
	r.offset_left = -w * 0.5
	r.offset_right = w * 0.5
	r.pivot_offset = Vector2(w * 0.5, 0)
	r.scale = Vector2(0, 1)
	parent.add_child(r)
	r.create_tween().tween_property(r, "scale:x", 1.0, 0.5).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return r


func _out(card: Control, at: float, dur := 0.3) -> void:
	var tw := card.create_tween()
	tw.tween_interval(at)
	tw.tween_property(card, "modulate:a", 0.0, dur)
	tw.tween_callback(card.queue_free)


# --- Opening ------------------------------------------------------------------------

func _set_lids(v: float) -> void:
	_lids_mat.set_shader_parameter("open", v)


func _set_blur(v: float) -> void:
	_lids_mat.set_shader_parameter("blur", v)


## Eyes opening: a crack, a blink, then wide open as the blur clears. Closes nothing at the
## end; the lids just fade away. Takes `dur` seconds.
func eyes_open(dur: float) -> void:
	_lids.visible = true
	_set_lids(0.0)
	_set_blur(4.5)
	var tw := _lids.create_tween()
	tw.tween_interval(0.4)
	tw.tween_method(_set_lids, 0.0, 0.3, 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_lids, 0.3, 0.03, 0.14)
	tw.tween_interval(0.1)
	tw.tween_method(_set_lids, 0.03, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_blur, 4.5, 0.0, 1.3).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(maxf(dur - 2.5, 0.0))
	tw.tween_method(_set_lids, 1.0, 1.6, 0.4)
	tw.tween_callback(close_lids)


func close_lids() -> void:
	_lids.visible = false


# --- Room cards ---------------------------------------------------------------------

## Room title. Returns how long it stays up (the host waits this long before the room starts).
## `light`: a faint scrim only, for when the title lands over live play (after the opening).
func room_intro(index: int, data: Dictionary, light := false) -> float:
	var card := _card()
	_fill(card, Color(0, 0, 0, 0.3 if light else 0.7))
	var depth := _centered(card, "DEPTH %s  ·  %d / %d" % [data.floor, index + 1, Rooms.RUN_LENGTH], 14,
		Color(data.get("accent", Ui.TEXT), 0.9), Ui.LABEL, 0.42)
	var title := _centered(card, String(data.name), 64, Ui.TEXT, Ui.DISPLAY, 0.5, 12)
	_line(card, 0.575, 120.0, Color(1, 1, 1, 0.35), 0.15)
	Ui.appear(depth, 0.05, Vector2(0, 8))
	Ui.appear(title, 0.1, Vector2(0, 10), 0.5)
	Game.sfx("card", false, null, -4.0)
	_out(card, 2.0, 0.4)
	return 2.4


func rewind() -> void:
	var card := _card()
	var tint := _fill(card, Color(Util.CYAN, 0.0))
	var tw := tint.create_tween()
	tw.tween_property(tint, "color:a", 0.35, 0.08)
	tw.tween_property(tint, "color:a", 0.0, 0.5)
	# A thin scan line sweeping upward: time running back.
	var scan := Ui.rect(Color(Util.CYAN, 0.9))
	scan.anchor_right = 1.0
	scan.anchor_top = 1.0
	scan.anchor_bottom = 1.0
	scan.offset_bottom = 2
	card.add_child(scan)
	var vs := _vs()
	scan.create_tween().tween_property(scan, "position:y", -10.0, 0.45).from(vs.y).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var l := _centered(card, "REWIND", 22, Util.CYAN, Ui.DISPLAY, 0.5, 16)
	Ui.appear(l, 0.0, Vector2.ZERO, 0.1)
	var t2 := l.create_tween()
	t2.tween_interval(0.45)
	t2.tween_property(l, "modulate:a", 0.0, 0.2)
	_out(card, 0.7, 0.1)
	Game.sfx("rewind")


func death() -> void:
	var card := _card()
	var flash := _fill(card, Color(0.9, 0.08, 0.1, 0.75))
	flash.create_tween().tween_property(flash, "color", Color(0.02, 0.0, 0.0, 0.82), 0.4)
	var l := _centered(card, "TIME FRACTURED", 44, Ui.TEXT, Ui.DISPLAY, 0.48, 10)
	Ui.appear(l, 0.15, Vector2(0, 6), 0.4)
	var sub := _centered(card, "REWINDING", 13, Ui.MUTED, Ui.LABEL, 0.56)
	Ui.appear(sub, 0.5, Vector2.ZERO)
	_line(card, 0.535, 90.0, Color(Util.RED, 0.8), 0.2)
	_out(card, 1.5, 0.2)


## TEMPORAL PINCER: amber from the left, cyan from the right, a black band across. About a second.
func cutin() -> void:
	var vs := _vs()
	var card := _card()
	for side in 2:
		var c := Util.AMBER if side == 0 else Util.CYAN
		var half := Ui.rect(c, Vector2(vs.x * 0.5, vs.y))
		half.position = Vector2(0 if side == 0 else vs.x * 0.5, 0)
		card.add_child(half)
		half.modulate.a = 0.85
		var from := -vs.x * 0.5 if side == 0 else vs.x
		half.create_tween().tween_property(half, "position:x", half.position.x, 0.14).from(from) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		var nm := Ui.label("LEON" if side == 0 else "NOEL", 120, Color(Ui.INK, 0.9), Ui.DISPLAY, 18)
		nm.position = Vector2(vs.x * 0.06, vs.y * 0.12) if side == 0 else Vector2(vs.x * 0.58, vs.y * 0.66)
		card.add_child(nm)
		Ui.appear(nm, 0.05, Vector2(-80 if side == 0 else 80, 0), 0.2)
	var band := Ui.rect(Ui.INK, Vector2(vs.x, 120))
	band.position = Vector2(0, vs.y * 0.5 - 60)
	band.pivot_offset = Vector2(vs.x * 0.5, 60)
	band.scale = Vector2(1, 0)
	card.add_child(band)
	band.create_tween().tween_property(band, "scale:y", 1.0, 0.12).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var title := _centered(card, "TEMPORAL PINCER", 52, Ui.TEXT, Ui.DISPLAY, 0.5, 14)
	title.pivot_offset = Vector2(vs.x * 0.5, 30)
	title.scale = Vector2(1.6, 1.6)
	title.modulate.a = 0.0
	var tt := title.create_tween().set_parallel()
	tt.tween_property(title, "scale", Vector2.ONE, 0.16).set_delay(0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(title, "modulate:a", 1.0, 0.08).set_delay(0.18)
	_out(card, 0.95, 0.2)


func results(data: Dictionary, time: float, deaths: int, pincers: int, rank: String, loot := 0) -> void:
	var card := _card()
	_fill(card, Color(Ui.INK, 0.86))
	var head := _centered(card, "DEPTH CLEARED", 14, Color(0.35, 0.95, 0.55), Ui.LABEL, 0.2)
	var title := _centered(card, String(data.name), 46, Ui.TEXT, Ui.DISPLAY, 0.27, 10)
	Ui.appear(head, 0.0)
	Ui.appear(title, 0.08)
	_line(card, 0.335, 200.0, Ui.LINE, 0.1)

	var rk_col := Util.AMBER if rank == "S" else Ui.TEXT
	var rk := _centered(card, rank, 150, rk_col, Ui.DISPLAY, 0.5, 0)
	rk.pivot_offset = Vector2(_vs().x * 0.5, 90)
	rk.scale = Vector2(1.8, 1.8)
	rk.modulate.a = 0.0
	var rt := rk.create_tween().set_parallel()
	rt.tween_property(rk, "scale", Vector2.ONE, 0.22).set_delay(0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rt.tween_property(rk, "modulate:a", 1.0, 0.12).set_delay(0.9)
	rt.chain().tween_callback(func() -> void: Game.sfx("pincer", false, null, -6.0, 1.5))
	var rl := _centered(card, "RANK", 12, Ui.MUTED, Ui.LABEL, 0.62)
	Ui.appear(rl, 0.9)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 64)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.anchor_right = 1.0
	stats.anchor_top = 0.72
	stats.anchor_bottom = 0.72
	card.add_child(stats)
	var rows := [["TIME", Ui.fmt_time(time)], ["DEATHS", str(deaths)], ["PINCERS", str(pincers)], ["LOOT", str(loot)]]
	for i in rows.size():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var v := Ui.label(rows[i][1], 34, Ui.TEXT, Ui.NUMBER, 1)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(v)
		var k := Ui.label(rows[i][0], 11, Ui.MUTED, Ui.LABEL)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(k)
		stats.add_child(cell)
		Ui.appear(cell, 0.3 + i * 0.1)
	Game.sfx("card")
	_out(card, 4.6)


func final(time: float, deaths: int, pincers: int, loot := 0) -> void:
	var card := _card()
	_fill(card, Color(Ui.INK, 0.96))
	var t := _centered(card, "THE ORDER FALLS", 56, Ui.TEXT, Ui.DISPLAY, 0.36, 14)
	Ui.appear(t, 0.1, Vector2(0, 10), 0.6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.anchor_right = 1.0
	row.anchor_top = 0.46
	row.anchor_bottom = 0.46
	card.add_child(row)
	var a := Ui.label("LEON", 22, Util.AMBER, Ui.DISPLAY, 8)
	var dot := Ui.label("·", 22, Ui.FAINT, Ui.DISPLAY, 0)
	var b := Ui.label("NOEL", 22, Util.CYAN, Ui.DISPLAY, 8)
	row.add_child(a)
	row.add_child(dot)
	row.add_child(b)
	Ui.appear(row, 0.5)
	var s := _centered(card, "%s   ·   %d DEATHS   ·   %d PINCERS   ·   %d LOOT" % [Ui.fmt_time(time), deaths, pincers, loot],
		15, Ui.MUTED, Ui.LABEL, 0.6)
	Ui.appear(s, 0.9)
	Game.sfx("pincer")
