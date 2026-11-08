class_name Ui
## Flat UI kit: one palette, three type roles, flat buttons. Everything in menus, HUD and
## cards is built from these so the game reads as one system.
##
##   DISPLAY  Cinzel, wide tracking. Titles and names only.
##   LABEL    Barlow SemiBold, tracked uppercase. Buttons, tags, small labels.
##   BODY     Barlow Medium. The rare sentence.
##   NUMBER   Barlow Condensed Bold. Timers, counts, ranks.

enum { DISPLAY, LABEL, BODY, NUMBER }

const INK := Color(0.035, 0.04, 0.05)
const PANEL := Color(0.055, 0.06, 0.075, 0.92)
const LINE := Color(1, 1, 1, 0.14)
const TEXT := Color(0.93, 0.94, 0.96)
const MUTED := Color(0.93, 0.94, 0.96, 0.5)
const FAINT := Color(0.93, 0.94, 0.96, 0.28)

const _FILES := {
	DISPLAY: "res://assets/fonts/Cinzel.ttf",
	LABEL: "res://assets/fonts/Barlow-SemiBold.ttf",
	BODY: "res://assets/fonts/Barlow-Medium.ttf",
	NUMBER: "res://assets/fonts/BarlowCondensed-Bold.ttf",
}

static var _fonts := {}


## A font for a type role. `spacing` is extra pixels between letters (tracking).
static func font(kind := LABEL, spacing := 0) -> Font:
	var key := "%d:%d" % [kind, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var path: String = _FILES[kind]
	var base: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing
	if kind == DISPLAY:
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 600}
	_fonts[key] = fv
	return fv


static func label(text: String, size: int, color := TEXT, kind := LABEL, spacing := -1) -> Label:
	var l := Label.new()
	l.text = text
	if spacing < 0:
		spacing = _default_spacing(kind, size)
	l.add_theme_font_override("font", font(kind, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _default_spacing(kind: int, size: int) -> int:
	match kind:
		DISPLAY: return maxi(2, int(size * 0.12))
		LABEL: return maxi(1, int(size * 0.14))
		_: return 0


static func flat(color: Color, radius := 0, border := 0, border_color := LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	sb.anti_aliasing = radius > 0
	return sb


static func rect(color: Color, size := Vector2.ZERO) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = size
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _pad(sb: StyleBox, h: float, v: float) -> StyleBox:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## A flat button. `primary` fills with the accent; otherwise a thin outline that fills on hover.
static func button(text: String, accent := TEXT, primary := false, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font(LABEL, _default_spacing(LABEL, size)))
	b.add_theme_font_size_override("font_size", size)
	var fg := INK if primary else TEXT
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK if primary else TEXT)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", FAINT)
	var hp := size * 1.6
	var vp := size * 0.75
	var normal := _pad(flat(accent if primary else Color(0, 0, 0, 0.25), 2, 0 if primary else 1,
		Color(1, 1, 1, 0.3)), hp, vp)
	var hover := _pad(flat(accent.lightened(0.15) if primary else accent, 2), hp, vp)
	var pressed := _pad(flat(accent.darkened(0.15), 2), hp, vp)
	var focus := _pad(flat(Color(0, 0, 0, 0), 2, 1, accent), hp, vp)
	var disabled := _pad(flat(Color(1, 1, 1, 0.04), 2, 1, Color(1, 1, 1, 0.08)), hp, vp)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.mouse_entered.connect(func() -> void: if not b.disabled: Game.sfx("ui", false, null, -16.0, 1.4))
	b.pressed.connect(func() -> void: Game.sfx("ui", false, null, -8.0))
	return b


## A large text-only menu entry (title screen). A thin accent bar grows in from the left on hover.
static func menu_item(text: String, accent := TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font(LABEL, 6))
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(TEXT, 0.72))
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_hover_pressed_color", accent)
	var empty := StyleBoxEmpty.new()
	_pad(empty, 0, 10)
	empty.content_margin_left = 28
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var bar := rect(accent, Vector2(3, 0))
	bar.size = Vector2(3, 26)
	bar.position = Vector2(0, 0)
	bar.scale = Vector2(1, 0)
	b.add_child(bar)
	var grow := func(on: bool) -> void:
		bar.position.y = (b.size.y - 26) * 0.5
		bar.pivot_offset = Vector2(0, 13)
		var tw := bar.create_tween().set_parallel()
		tw.tween_property(bar, "scale:y", 1.0 if on else 0.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(empty, "content_margin_left", 40.0 if on else 28.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func() -> void:
		Game.sfx("ui", false, null, -16.0, 1.4)
		grow.call(true))
	b.mouse_exited.connect(func() -> void: if not b.has_focus(): grow.call(false))
	b.focus_entered.connect(func() -> void: grow.call(true))
	b.focus_exited.connect(func() -> void: grow.call(false))
	b.pressed.connect(func() -> void: Game.sfx("ui", false, null, -8.0))
	return b


## A thin horizontal rule.
static func rule(width: float, color := LINE) -> ColorRect:
	return rect(color, Vector2(width, 1))


## A key cap: "LMB", "E", "TAB". Drawn into a Control by `draw_key`.
static func draw_key(ci: CanvasItem, pos: Vector2, key: String, accent: Color, size := 15) -> float:
	var f := font(NUMBER, 1)
	var tw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := maxf(tw + 14.0, size + 10.0)
	var h := size + 10.0
	var r := Rect2(pos - Vector2(0, h * 0.5), Vector2(w, h))
	ci.draw_rect(r, Color(0, 0, 0, 0.55))
	ci.draw_rect(r, Color(accent, 0.9), false, 1.5)
	ci.draw_string(f, Vector2(pos.x + (w - tw) * 0.5, pos.y + size * 0.36), key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(accent, 1.0))
	return w


static func fmt_time(t: float) -> String:
	return "%02d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


## Fade a control in, optionally sliding it from an offset.
static func appear(n: CanvasItem, delay := 0.0, from := Vector2(0, 12), dur := 0.35) -> void:
	n.modulate.a = 0.0
	var tw := n.create_tween().set_parallel()
	tw.tween_property(n, "modulate:a", 1.0, dur).set_delay(delay)
	# Never slide a container's child: the container owns its position.
	if n is Control and from != Vector2.ZERO and not (n.get_parent() is Container):
		var c := n as Control
		var to := c.position
		c.position = to + from
		tw.tween_property(c, "position", to, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
