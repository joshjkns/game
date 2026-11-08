class_name Screens
extends Control
## Full-screen menus: title, power pick, shop, pause and run end.
## Each show_* rebuilds its content; main.gd listens to the signals.

signal start_pressed
signal choose_hero_pressed
signal hero_chosen(id: String)
signal hero_previewed(id: String)
signal difficulty_chosen(id: String)
signal power_chosen(id: String)
signal shop_closed
signal resume_pressed
signal title_pressed
signal title_shown
signal era_previewed(biome: String)
signal era_chosen(biome: String, boss: bool)
signal era_closed

## Same ink palette as the HUD.
const INK := Color(0.025, 0.045, 0.05, 0.92)
const INK_SOLID := Color(0.012, 0.025, 0.03)
const CARD := Color(0.04, 0.07, 0.08, 0.95)
const CARD_HOVER := Color(0.07, 0.11, 0.12, 0.97)
const CREAM := Color("fff4e0")
const GOLD := Color("ffe08b")
const TIME := Color("83d4c2")
## Run setup screens: left edge of the info column.
const HERO_INFO_X := 52.0
const UI_BLUR_SHADER: Shader = preload("res://shaders/ui_blur.gdshader")

var _big: Font
var _ui: Font
var _body: Font
var _root: Control
var _selected_hero := "pip"
var _hero_cards: Dictionary = {}
var _hero_abilities: VBoxContainer
var _hero_play: Button
var _hero_info: VBoxContainer
var _hero_select_open := false
var _difficulty_open := false
var _era_open := false
var _selected_difficulty := "medium"
var _difficulty_rows: Dictionary = {}
var _kit: Array = []
var _kit_accent := GOLD
var _submenu_return_to_pause := false
var _map_caption: Label
var _map_title := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_ui = _big
	_body = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	hide()


func is_open() -> bool:
	return visible


func close() -> void:
	hide()
	_hero_select_open = false
	_difficulty_open = false
	_era_open = false
	if _root:
		_root.queue_free()
		_root = null


func _open() -> VBoxContainer:
	_open_canvas()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	return v


func _open_canvas() -> Control:
	close()
	show()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_material := ShaderMaterial.new()
	blur_material.shader = UI_BLUR_SHADER
	backdrop.material = blur_material
	_root.add_child(backdrop)
	return _root


## A clear canvas over the live 3D backdrop, with a linear ink wash from `from` (clear) to `to`.
func _open_plain(from: Vector2, to: Vector2, alpha: float) -> Control:
	close()
	show()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var grad := Gradient.new()
	grad.set_color(0, Color(INK_SOLID, 0.0))
	grad.set_color(1, Color(INK_SOLID, alpha))
	var wash_tex := GradientTexture2D.new()
	wash_tex.gradient = grad
	wash_tex.fill_from = from
	wash_tex.fill_to = to
	var wash := TextureRect.new()
	wash.texture = wash_tex
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(wash)
	return _root


func _label(parent: Node, text: String, font: Font, fsize: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER, brush := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK_SOLID)
	l.add_theme_constant_override("outline_size", 10 if fsize > 30 else (5 if font == _big and fsize >= 18 else 0))
	parent.add_child(l)
	if fsize >= 40 and brush:
		var ink := InkBrush.new()
		ink.show_behind_parent = true
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.add_child(ink)
	return l


## Slanted ink tile with a solid ink rim and an accent edge, like the HUD's ability tiles.
func _style(col: Color, border: Color, width := 0, skew := 0.18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.border_width_bottom = maxi(width, 4)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(18)
	sb.skew = Vector2(skew, 0)
	sb.shadow_color = INK_SOLID
	sb.shadow_size = 4
	sb.anti_aliasing = true
	return sb


func _button(parent: Node, text: String, accent := GOLD, min_w := 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 56)
	b.add_theme_font_override("font", _ui)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_stylebox_override("normal", _style(CARD, accent))
	b.add_theme_stylebox_override("hover", _style(CARD_HOVER, accent, 2))
	b.add_theme_stylebox_override("pressed", _style(accent.darkened(0.5), accent, 2))
	b.add_theme_stylebox_override("focus", _style(CARD_HOVER, accent, 2))
	b.add_theme_stylebox_override("disabled", _style(Color(0.05, 0.06, 0.07, 0.85), Color(1, 1, 1, 0.15)))
	b.add_theme_color_override("font_outline_color", INK_SOLID)
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.pressed.connect(func(): Kit.sfx(self, "ui", null, -8.0))
	parent.add_child(b)
	return b


func _flat_button(parent: Node, text: String, min_w := 320.0, fsize := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(min_w, 50)
	b.add_theme_font_override("font", _ui)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color("f5faf5"))
	b.add_theme_color_override("font_hover_color", Color("c8f3d7"))
	b.add_theme_color_override("font_pressed_color", Color("a5d9c0"))
	b.add_theme_color_override("font_focus_color", Color("c8f3d7"))
	b.add_theme_color_override("font_outline_color", INK_SOLID)
	b.add_theme_constant_override("outline_size", 5)
	# Text-only until hovered, then an ink slant with a gold edge slides in behind it.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 22
	empty.content_margin_right = 22
	var lit := _style(INK, GOLD, 0, 0.3)
	lit.border_width_bottom = 0
	lit.border_width_left = 5
	lit.content_margin_left = 22
	lit.content_margin_right = 22
	lit.content_margin_top = 4
	lit.content_margin_bottom = 4
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	for state in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, lit)
	b.pressed.connect(func(): Kit.sfx(self, "ui", null, -8.0))
	parent.add_child(b)
	return b


func _glass_panel(parent: Node, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var style := _panel_style(Run.hero_def().accent if Run.hero != "" else GOLD)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


## Big ink panel matching the HUD stat sheet: solid ink rim and a coloured top bar.
func _panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.08, 0.96)
	style.border_color = accent
	style.border_width_top = 5
	style.shadow_color = INK_SOLID
	style.shadow_size = 5
	return style


func _coin_display(parent: Node, amount: int, fsize: int, icon_size: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var icon := Icons.new()
	icon.icon = "coin"
	icon.color = GOLD
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var value := _label(row, "%d" % amount, _big, fsize, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## Card button plus its content column. Tall cards use a gentler slant than buttons so
## the corners don't cut into the text, and the card grows to fit whatever goes inside.
func _card_shell(parent: Node, accent: Color, separation: int) -> Array:
	const W := 260.0
	const H := 300.0
	const PAD_X := 30.0
	const PAD_TOP := 20.0
	const PAD_BOTTOM := 20.0
	var b := _button(parent, "", accent, W)
	b.custom_minimum_size = Vector2(W, H)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(state)
		sb.skew = Vector2(0.06, 0)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = PAD_X; v.offset_right = -PAD_X; v.offset_top = PAD_TOP; v.offset_bottom = -PAD_BOTTOM
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", separation)
	b.add_child(v)
	v.minimum_size_changed.connect(func():
		b.custom_minimum_size.y = maxf(H, v.get_combined_minimum_size().y + PAD_TOP + PAD_BOTTOM))
	return [b, v]


## A tall card: accent strip, title, body text and an optional footer (price / tag).
func _card(parent: Node, title: String, body: String, accent: Color, footer := "", tag := "", icon_id := "", icon_color := Color.WHITE) -> Button:
	var parts := _card_shell(parent, accent, 8)
	var b: Button = parts[0]
	var v: VBoxContainer = parts[1]
	if tag != "":
		_label(v, tag.to_upper(), _ui, 14, accent, HORIZONTAL_ALIGNMENT_LEFT)
	if icon_id != "":
		var icon_center := CenterContainer.new()
		icon_center.custom_minimum_size.y = 75 if icon_id.begins_with("weapon_") else 52
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(icon_center)
		var item_icon := Icons.new()
		item_icon.icon = icon_id
		item_icon.color = icon_color
		item_icon.custom_minimum_size = Vector2(150, 75) if icon_id.begins_with("weapon_") else Vector2(48, 48)
		item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(item_icon)
	var t := _label(v, title, _big, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var d := _label(v, body, _body, 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if footer != "":
		_coin_display(v, int(footer), 26, 22.0)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Stat items use one clear icon and compact effect rows instead of a paragraph.
func _item_card(parent: Node, id: String, price: int, owned: int) -> Button:
	var item: Dictionary = Run.ITEMS[id]
	var accent: Color = Run.item_color(id)
	var parts := _card_shell(parent, accent, 6)
	var b: Button = parts[0]
	var v: VBoxContainer = parts[1]
	var tag := _label(v, Run.item_group_label(id).to_upper(), _ui, 14, accent, HORIZONTAL_ALIGNMENT_LEFT)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_center := CenterContainer.new()
	icon_center.custom_minimum_size.y = 50
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_center)
	var icon := Icons.new()
	icon.icon = Run.item_icon(id)
	icon.color = accent
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)
	var title := _label(v, item.name, _big, 27, Color("f5faf5"), HORIZONTAL_ALIGNMENT_LEFT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for stat_id in Run.item_effect_ids(id):
		_add_item_effect(v, id, stat_id)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	if owned > 0:
		var count := _label(v, "OWNED ×%d" % owned, _ui, 14, Color("c6ddd1"), HORIZONTAL_ALIGNMENT_LEFT)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_display(v, price, 24, 22.0)
	return b


func _add_item_effect(parent: Node, item_id: String, stat_id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var color_id := "hp" if stat_id == "heal" else stat_id
	var icon := Icons.new()
	icon.icon = Run.stat_icon(color_id)
	icon.color = Run.stat_color(color_id)
	icon.custom_minimum_size = Vector2(21, 21)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var col: Color = Run.stat_color(color_id)
	if stat_id != "heal" and Run.ITEMS[item_id].stats[stat_id] < 0.0:
		col = Color("ff817b")
	var effect := _label(row, Run.item_effect_text(item_id, stat_id), _ui, 17, col, HORIZONTAL_ALIGNMENT_LEFT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _owned_items_row(parent: Node) -> void:
	if Run.items.is_empty():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := _label(row, "KIT", _ui, 15, TIME)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in Run.items:
		var chip := HBoxContainer.new()
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_theme_constant_override("separation", 3)
		var effects := PackedStringArray()
		for stat_id in Run.item_effect_ids(id):
			effects.append(Run.item_effect_text(id, stat_id))
		chip.tooltip_text = "%s · %s" % [Run.ITEMS[id].name, ", ".join(effects)]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(chip)
		var icon := Icons.new()
		icon.icon = Run.item_icon(id)
		icon.color = Run.item_color(id)
		icon.custom_minimum_size = Vector2(25, 25)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var count := _label(chip, "×%d" % Run.items[id], _ui, 14, Color("dcebe1"))
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_title() -> void:
	_submenu_return_to_pause = false
	# No blur here: the maps are the backdrop. A soft ink wash from below keeps the menu legible.
	_open_plain(Vector2(0.5, 0.1), Vector2(0.5, 1.0), 0.6)
	var column := VBoxContainer.new()
	column.anchor_left = 0.0
	column.anchor_right = 1.0
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_top = 40
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	_root.add_child(column)
	var logo := Logo.new(88, false)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(logo)
	column.add_child(_spacer(26))
	var play := _title_item(column, "PLAY")
	play.pressed.connect(func(): choose_hero_pressed.emit())
	_title_item(column, "CONTROLS").pressed.connect(show_how_to_play)
	_title_item(column, "SETTINGS").pressed.connect(show_settings)
	_title_item(column, "CREDITS").pressed.connect(show_credits)
	_title_item(column, "QUIT").pressed.connect(func(): get_tree().quit())
	play.grab_focus.call_deferred()
	# The map currently on screen, captioned quietly bottom-left.
	_map_caption = _label(_root, "", _body, 18, Color(CREAM, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	_map_caption.add_theme_constant_override("outline_size", 4)
	_map_caption.anchor_top = 1.0
	_map_caption.anchor_bottom = 1.0
	_map_caption.offset_left = 40
	_map_caption.offset_top = -56
	_map_caption.offset_bottom = -30
	_map_caption.offset_right = 600
	_map_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_map_caption(_map_title)
	title_shown.emit()


func set_map_caption(title: String) -> void:
	_map_title = title
	if is_instance_valid(_map_caption):
		_map_caption.text = title


func _title_item(parent: Node, text: String) -> MenuItem:
	var b := _menu_item(parent, text, 30, GOLD, true)
	b.custom_minimum_size.x = 260
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## A bare word you can pick: dim cream, lit in its accent with a dash beside it when focused.
func _menu_item(parent: Node, text: String, fsize: int, accent: Color, centered := false) -> MenuItem:
	var b := MenuItem.new()
	b.text = text
	b.accent = accent
	b.centered = centered
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = roundf(fsize * 1.45)
	b.add_theme_font_override("font", _big)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color(CREAM, 0.7))
	for state in ["font_hover_color", "font_focus_color", "font_hover_pressed_color", "font_pressed_color"]:
		b.add_theme_color_override(state, accent)
	b.add_theme_color_override("font_outline_color", INK_SOLID)
	b.add_theme_constant_override("outline_size", 6)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	b.pressed.connect(func(): Kit.sfx(self, "ui", null, -8.0))
	parent.add_child(b)
	return b


## The one solid button on a screen: a flat block in the accent colour with ink text.
func _primary_button(parent: Node, text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 58)
	b.add_theme_font_override("font", _big)
	b.add_theme_font_size_override("font_size", 30)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, INK_SOLID)
	_tint_primary(b, accent)
	b.pressed.connect(func(): Kit.sfx(self, "ui", null, -8.0))
	parent.add_child(b)
	return b


func _tint_primary(b: Button, accent: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = accent
		if state == "hover":
			sb.bg_color = accent.lightened(0.2)
		elif state != "normal":
			sb.bg_color = accent.darkened(0.15)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		b.add_theme_stylebox_override(state, sb)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(CREAM, 0.85)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(5)
	ring.set_expand_margin_all(5)
	b.add_theme_stylebox_override("focus", ring)


func show_how_to_play(from_pause := false) -> void:
	_submenu_return_to_pause = from_pause
	_open_canvas()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := _glass_panel(center, Vector2(820, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	_label(v, "CONTROLS", _big, 50, Color("f5faf5"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cols)
	var left := _controls_column(cols)
	_controls_section(left, "MOVEMENT", [
		[["W", "A", "S", "D"], "Move"],
		[["SPACE"], "Jump"],
		[["SHIFT"], "Mobility"],
	])
	_controls_section(left, "COMBAT", [
		[["LMB"], "Fire"],
		[["RMB"], "Aim"],
		[["R"], "Reload"],
		[["1"], "Weapon 1"],
		[["2"], "Weapon 2"],
	])
	var right := _controls_column(cols)
	_controls_section(right, "ABILITIES", [
		[["E"], "Skill"],
		[["Q"], "Ultimate"],
	])
	_controls_section(right, "GENERAL", [
		[["F"], "Interact"],
		[["TAB"], "Stats (hold)"],
		[["ESC"], "Pause"],
	])
	v.add_child(_spacer(2))
	var back := _flat_button(v, "BACK", 300, 25)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_return_from_submenu)
	back.grab_focus.call_deferred()


func _controls_column(parent: Node) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size.x = 330
	parent.add_child(col)
	return col


func _controls_section(parent: Node, title: String, rows: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	parent.add_child(box)
	_label(box, title, _ui, 18, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	for row in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		box.add_child(h)
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 4)
		keys.custom_minimum_size.x = 150
		h.add_child(keys)
		for k in row[0]:
			_keycap(keys, k)
		var action := _label(h, row[1], _body, 21, Color("e0ece5"), HORIZONTAL_ALIGNMENT_LEFT)
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A raised keyboard key: rounded, lighter face with a thick darker bottom edge.
func _keycap(parent: Node, key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.18, 0.19)
	style.border_color = Color(0.32, 0.4, 0.41)
	style.set_border_width_all(1)
	style.border_width_bottom = 4
	style.set_corner_radius_all(6)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	cap.add_theme_stylebox_override("panel", style)
	cap.custom_minimum_size = Vector2(32, 32)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(cap)
	_label(cap, key, _ui, 15, CREAM)
	return cap


func show_settings(from_pause := false) -> void:
	_submenu_return_to_pause = from_pause
	_open_canvas()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := _glass_panel(center, Vector2(700, 610))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 13)
	panel.add_child(v)
	_label(v, "SETTINGS", _big, 50, Color("f5faf5"))
	_add_setting_slider(v, "MASTER VOLUME", 0.0, 1.0, 0.01, Preferences.master_volume, "percent", Callable(Preferences, "set_master_volume"), true)
	_add_setting_slider(v, "MOUSE SENSITIVITY", 0.4, 2.0, 0.05, Preferences.mouse_sensitivity, "multiplier", Callable(Preferences, "set_mouse_sensitivity"))
	_add_setting_slider(v, "FIELD OF VIEW", 70.0, 110.0, 1.0, Preferences.field_of_view, "fov", Callable(Preferences, "set_field_of_view"))
	_add_setting_slider(v, "HUD SCALE", 0.6, 1.4, 0.05, Preferences.hud_scale, "percent", Callable(Preferences, "set_hud_scale"))
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.alignment = HORIZONTAL_ALIGNMENT_CENTER
	fullscreen.button_pressed = Preferences.fullscreen
	_style_check(fullscreen)
	fullscreen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullscreen.custom_minimum_size.y = 36
	fullscreen.toggled.connect(Preferences.set_fullscreen)
	v.add_child(fullscreen)
	var crosshair := CheckButton.new()
	crosshair.text = "Show crosshair"
	crosshair.alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.button_pressed = Preferences.show_crosshair
	_style_check(crosshair)
	crosshair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crosshair.custom_minimum_size.y = 36
	crosshair.toggled.connect(Preferences.set_crosshair_visible)
	v.add_child(crosshair)
	var shake := CheckButton.new()
	shake.text = "Camera shake"
	shake.alignment = HORIZONTAL_ALIGNMENT_CENTER
	shake.button_pressed = Preferences.camera_shake
	_style_check(shake)
	shake.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shake.custom_minimum_size.y = 36
	shake.toggled.connect(Preferences.set_camera_shake)
	v.add_child(shake)
	var back := _flat_button(v, "BACK", 300, 25)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_return_from_submenu)
	back.grab_focus.call_deferred()


func _return_from_submenu() -> void:
	var return_to_pause := _submenu_return_to_pause
	_submenu_return_to_pause = false
	if return_to_pause:
		show_pause()
	else:
		show_title()


func has_pause_submenu() -> bool:
	return _submenu_return_to_pause


func back_from_submenu() -> void:
	_return_from_submenu()


func _add_setting_slider(parent: Node, title: String, minimum: float, maximum: float, step: float, value: float, value_format: String, setter: Callable, add_test := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 38
	parent.add_child(row)
	var label := _label(row, title, _ui, 17, Color("e1eee5"), HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size.x = 150
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 28
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	_style_slider(slider)
	row.add_child(slider)
	var value_label := _label(row, _format_setting(value, value_format), _ui, 17, Color("f5faf5"))
	value_label.custom_minimum_size.x = 58
	slider.value_changed.connect(func(next_value: float):
		setter.call(next_value)
		value_label.text = _format_setting(next_value, value_format))
	if add_test:
		var test := _flat_button(row, "TEST", 64, 17)
		test.custom_minimum_size.y = 36
		test.pressed.connect(func(): Kit.sfx(self, "ping", null, -8.0))


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.1, 0.11)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	track.shadow_color = INK_SOLID
	track.shadow_size = 3
	track.skew = Vector2(0.5, 0)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", _diamond_icon(CREAM))
	slider.add_theme_icon_override("grabber_highlight", _diamond_icon(GOLD))


## A small ink-rimmed diamond texture for slider grabbers.
func _diamond_icon(col: Color) -> Texture2D:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 22:
			var d := absf(x - 10.5) + absf(y - 10.5)
			if d <= 7.5:
				img.set_pixel(x, y, col)
			elif d <= 10.5:
				img.set_pixel(x, y, INK_SOLID)
	return ImageTexture.create_from_image(img)


func _style_check(c: CheckButton) -> void:
	c.add_theme_font_override("font", _ui)
	c.add_theme_font_size_override("font_size", 20)
	c.add_theme_color_override("font_color", CREAM)
	c.add_theme_color_override("font_hover_color", GOLD)
	c.add_theme_color_override("font_pressed_color", CREAM)
	c.add_theme_color_override("font_outline_color", INK_SOLID)
	c.add_theme_constant_override("outline_size", 5)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "disabled"]:
		c.add_theme_stylebox_override(state, empty)
	var lit := _style(INK, GOLD, 0, 0.3)
	lit.border_width_bottom = 0
	lit.border_width_left = 5
	lit.set_content_margin_all(4)
	for state in ["hover", "hover_pressed", "focus"]:
		c.add_theme_stylebox_override(state, lit)


func _format_setting(value: float, value_format: String) -> String:
	match value_format:
		"percent":
			return "%d%%" % roundi(value * 100.0)
		"multiplier":
			return "%.2fx" % value
		"fov":
			return "%d°" % roundi(value)
	return "%.0f" % value


func show_credits() -> void:
	_open_canvas()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	_label(v, "CREDITS", _big, 62, Color("f5faf5"))
	var logo := Logo.new(54, false)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	_label(v, "Built with Godot", _body, 22, Color("d2e4db"))
	v.add_child(_spacer(10))
	var back := _flat_button(v, "Back", 300, 28)
	back.pressed.connect(show_title)
	back.grab_focus.call_deferred()


## --- Run setup: weapon, difficulty, era -------------------------------------------
## All three share one layout: a plain column on the left over an ink wash, BACK under it,
## and the title backdrop (the era maps) on the right.

func _setup_column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.anchor_right = 0.46
	col.anchor_bottom = 1.0
	col.offset_left = HERO_INFO_X
	col.offset_top = 40
	col.offset_bottom = -100
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	_root.add_child(col)
	if title != "":
		_label(col, title, _big, 44, CREAM, HORIZONTAL_ALIGNMENT_LEFT, false)
		col.add_child(_spacer(18))
	return col


func _back_link(on_back: Callable) -> MenuItem:
	var back := _menu_item(_root, "BACK", 22, CREAM)
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = HERO_INFO_X
	back.offset_right = HERO_INFO_X + 110
	back.offset_top = -80
	back.offset_bottom = -44
	back.pressed.connect(on_back)
	return back


## Last step before a run: pick where in time to start (or skip right to that era's boss).
## Focusing a row swaps the title backdrop to that era's map.
func show_era_select() -> void:
	_open_plain(Vector2(0.62, 0.0), Vector2(0.0, 0.0), 0.85)
	_era_open = true
	var col := _setup_column("ERA")
	var first: Button
	for biome: String in TitleScene.BIOMES:
		var row := _era_row(col, biome)
		if first == null:
			first = row
	_back_link(_back_to_difficulty)
	first.grab_focus.call_deferred()


func _back_to_difficulty() -> void:
	era_closed.emit()
	show_difficulty(Run.difficulty)


## The era's name, and a small BOSS to skip ahead.
func _era_row(parent: Node, biome: String) -> Button:
	var accent: Color = Arena.PALETTES[biome].accent
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	parent.add_child(h)
	var row := _menu_item(h, Run.biome_name(biome).to_upper(), 34, accent)
	row.custom_minimum_size.x = 340
	var boss := _menu_item(h, "BOSS", 20, Color("ff6a5e"))
	boss.custom_minimum_size.x = 70
	boss.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for b: Button in [row, boss]:
		b.focus_entered.connect(func(): era_previewed.emit(biome))
	row.pressed.connect(func(): era_chosen.emit(biome, false))
	boss.pressed.connect(func(): era_chosen.emit(biome, true))
	return row


func show_hero_select(selected := "") -> void:
	_selected_hero = selected if Heroes.DEFS.has(selected) else Run.hero
	if not Heroes.DEFS.has(_selected_hero):
		_selected_hero = Heroes.ORDER[0]
	# The maps keep touring on the right; an ink wash from the left carries the details.
	_open_plain(Vector2(0.62, 0.0), Vector2(0.0, 0.0), 0.85)
	_hero_select_open = true
	_hero_info = _setup_column("")
	# Top right: the loadouts as a strip of weapon pictures.
	var roster := HBoxContainer.new()
	roster.anchor_left = 1.0
	roster.anchor_right = 1.0
	roster.offset_top = 36
	roster.offset_right = -44
	roster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	roster.add_theme_constant_override("separation", 6)
	_root.add_child(roster)
	_hero_cards.clear()
	for hero_id: String in Heroes.ORDER:
		var card := _roster_card(roster, hero_id)
		_hero_cards[hero_id] = card
		card.pressed.connect(func(): _select_hero(hero_id))
		card.focus_entered.connect(func(): _select_hero(hero_id))
	_back_link(show_title)
	_hero_play = _primary_button(_root, "PLAY", GOLD)
	_hero_play.anchor_left = 1.0
	_hero_play.anchor_right = 1.0
	_hero_play.anchor_top = 1.0
	_hero_play.anchor_bottom = 1.0
	_hero_play.offset_left = -48 - 220
	_hero_play.offset_right = -48
	_hero_play.offset_top = -44 - 58
	_hero_play.offset_bottom = -44
	_hero_play.pressed.connect(func(): hero_chosen.emit(_selected_hero))
	_select_hero(_selected_hero)
	_hero_play.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _era_open and visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			Kit.sfx(self, "ui", null, -8.0)
			_back_to_difficulty()
		return
	if _difficulty_open and visible:
		_difficulty_input(event)
		return
	if not _hero_select_open or not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Kit.sfx(self, "ui", null, -8.0)
		show_title()
	elif event is InputEventKey and event.pressed and not event.echo:
		var slot: int = event.keycode - KEY_1
		if slot >= 0 and slot < Heroes.ORDER.size():
			get_viewport().set_input_as_handled()
			Kit.sfx(self, "ui", null, -8.0)
			_select_hero(Heroes.ORDER[slot])


## After the weapon: pick how hard the run is. Picking one moves on.
func show_difficulty(selected := "") -> void:
	_selected_difficulty = selected if Run.DIFFICULTIES.has(selected) else Run.difficulty
	_open_plain(Vector2(0.62, 0.0), Vector2(0.0, 0.0), 0.85)
	_difficulty_open = true
	var col := _setup_column("DIFFICULTY")
	_difficulty_rows.clear()
	for i in Run.DIFFICULTY_ORDER.size():
		var id: String = Run.DIFFICULTY_ORDER[i]
		var d: Dictionary = Run.DIFFICULTIES[id]
		var row := _menu_item(col, String(d.name).to_upper(), 38, d.color)
		row.custom_minimum_size.x = 360
		row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# Skulls for severity, tucked against the row's right edge.
		var skulls := HBoxContainer.new()
		skulls.anchor_left = 1.0
		skulls.anchor_right = 1.0
		skulls.anchor_top = 0.5
		skulls.anchor_bottom = 0.5
		skulls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		skulls.grow_vertical = Control.GROW_DIRECTION_BOTH
		skulls.add_theme_constant_override("separation", 2)
		skulls.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(skulls)
		for s in Run.DIFFICULTY_ORDER.size():
			var skull := Icons.new()
			skull.icon = "skull"
			skull.color = Color(d.color, 0.9) if s <= i else Color(1, 1, 1, 0.12)
			skull.custom_minimum_size = Vector2(20, 20)
			skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
			skulls.add_child(skull)
		_difficulty_rows[id] = row
		row.focus_entered.connect(func(): _selected_difficulty = id)
		row.pressed.connect(func(): difficulty_chosen.emit(id))
	_back_link(func(): show_hero_select(Run.hero))
	_select_difficulty.call_deferred(_selected_difficulty)


func _difficulty_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Kit.sfx(self, "ui", null, -8.0)
		show_hero_select(Run.hero)
	elif event is InputEventKey and event.pressed and not event.echo:
		var slot: int = event.keycode - KEY_1
		if slot >= 0 and slot < Run.DIFFICULTY_ORDER.size():
			get_viewport().set_input_as_handled()
			Kit.sfx(self, "ui", null, -8.0)
			_select_difficulty(Run.DIFFICULTY_ORDER[slot])


func _select_difficulty(id: String) -> void:
	if not Run.DIFFICULTIES.has(id) or not _difficulty_rows.has(id):
		return
	_selected_difficulty = id
	var row: Button = _difficulty_rows[id]
	if is_instance_valid(row) and row.is_inside_tree():
		row.grab_focus()


## A loadout's weapon in the roster strip; the picked one is lit and underlined.
func _roster_card(parent: Node, id: String) -> Button:
	var weapon: String = Heroes.DEFS[id].weapon
	var card := Button.new()
	card.custom_minimum_size = Vector2(108, 64)
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = Run.WEAPONS[weapon].name
	card.pressed.connect(func(): Kit.sfx(self, "ui", null, -8.0))
	parent.add_child(card)
	var portrait := TextureRect.new()
	portrait.texture = Icons.weapon_texture(weapon)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 8
	portrait.offset_right = -8
	portrait.offset_top = 4
	portrait.offset_bottom = -8
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(portrait)
	return card


func _style_roster_card(card: Button, accent: Color, selected: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(INK_SOLID, 0.7 if selected else 0.5)
	normal.border_color = accent if selected else Color(CREAM, 0.0)
	normal.border_width_bottom = 4
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(0)
	var hover: StyleBoxFlat = normal.duplicate()
	if not selected:
		hover.border_color = Color(CREAM, 0.4)
	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	card.modulate = Color.WHITE if selected else Color(0.58, 0.6, 0.6)


func _select_hero(id: String) -> void:
	if not Heroes.DEFS.has(id):
		return
	var changed := id != _selected_hero or _hero_info.get_child_count() == 0
	_selected_hero = id
	var d: Dictionary = Heroes.DEFS[id]
	for hero_id: String in Heroes.ORDER:
		_style_roster_card(_hero_cards[hero_id], Heroes.DEFS[hero_id].accent, hero_id == id)
	_tint_primary(_hero_play, d.accent)
	if not changed:
		return
	for child in _hero_info.get_children():
		child.free()
	var weapon: Dictionary = Run.WEAPONS[d.weapon]
	_label(_hero_info, String(weapon.name).to_upper(), _big, 64, CREAM, HORIZONTAL_ALIGNMENT_LEFT, false)
	_label(_hero_info, _weapon_line(d), _body, 20, d.accent, HORIZONTAL_ALIGNMENT_LEFT)
	_hero_info.add_child(_spacer(12))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	_hero_info.add_child(stats)
	_hero_stat(stats, "heart", Color("ff6b6b"), int(d.hp), "health")
	_hero_stat(stats, "shield", Color("8fd8ff"), int(d.shield), "shield")
	_hero_info.add_child(_spacer(30))
	_kit = _hero_kit(d)
	_kit_accent = d.accent
	_hero_abilities = VBoxContainer.new()
	_hero_abilities.add_theme_constant_override("separation", 14)
	_hero_info.add_child(_hero_abilities)
	for entry: Dictionary in _kit:
		_kit_row(entry)
	# Slide the new details in.
	_hero_info.modulate.a = 0.0
	_hero_info.position.x = HERO_INFO_X - 24
	var tw := create_tween().set_parallel()
	tw.tween_property(_hero_info, "modulate:a", 1.0, 0.22)
	tw.tween_property(_hero_info, "position:x", HERO_INFO_X, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hero_previewed.emit(id)


func _hero_stat(parent: Node, icon_id: String, col: Color, value: int, caption: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var icon := Icons.new()
	icon.icon = icon_id
	icon.color = col
	icon.custom_minimum_size = Vector2(20, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	_label(row, str(value), _big, 22, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	var cap := _label(row, caption, _body, 17, Color(CREAM, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## The weapon's numbers in one line, e.g. "9 damage, 40 rounds, 12 shots a second."
func _weapon_line(d: Dictionary) -> String:
	var weapon: Dictionary = Run.WEAPONS[d.weapon]
	var dmg := "%d damage" % int(weapon.dmg)
	if weapon.pellets > 1:
		dmg += " x %d pellets" % weapon.pellets
	var text := "%s, %d rounds, %s shots a second." % [dmg, weapon.mag, ("%.1f" % weapon.rate).trim_suffix(".0")]
	if weapon.kind == "shell":
		text += " Shells explode."
	return text


## The abilities that come with a weapon: key, icon, name, cooldown and what it does.
func _hero_kit(d: Dictionary) -> Array:
	var kit := []
	for key: String in ["shift", "e", "q"]:
		var a: Dictionary = d[key]
		var tag := "ultimate" if key == "q" else ("%.1f" % a.cd).trim_suffix(".0") + "s"
		kit.append({"key": key.to_upper(), "icon": a.id, "name": a.name, "tag": tag, "text": a.text})
	return kit


func _kit_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_hero_abilities.add_child(row)
	var key := _label(row, entry.key, _big, 15, CREAM)
	key.custom_minimum_size = Vector2(50, 28)
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	key.add_theme_constant_override("outline_size", 0)
	var cap := StyleBoxFlat.new()
	cap.bg_color = Color(INK_SOLID, 0.5)
	cap.border_color = Color(CREAM, 0.4)
	cap.set_border_width_all(2)
	cap.set_corner_radius_all(4)
	key.add_theme_stylebox_override("normal", cap)
	var icon_box := CenterContainer.new()
	icon_box.custom_minimum_size = Vector2(60, 30)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon_box)
	var icon := Icons.new()
	icon.icon = entry.icon
	icon.color = _kit_accent
	icon.custom_minimum_size = Vector2(58, 29) if entry.key == "LMB" else Vector2(28, 28)
	icon_box.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	text.add_child(head)
	_label(head, entry.name, _big, 20, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	if entry.tag != "":
		var tag := _label(head, entry.tag, _body, 16, GOLD if entry.tag == "ultimate" else Color(CREAM, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var desc := _label(text, entry.text, _body, 16, Color(CREAM, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func show_pick(choices: Array) -> void:
	var v := _open()
	_label(v, "PICK A POWER", _big, 56)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	for id in choices:
		var p: Dictionary = Run.POWERS[id]
		var c := _card(h, p.name, p.text, TIME, "", "Time power", Icons.for_power(id), TIME)
		c.pressed.connect(func(): power_chosen.emit(id))
	if choices.is_empty():
		var b := _button(v, "CONTINUE")
		b.pressed.connect(func(): power_chosen.emit(""))


func show_shop() -> void:
	var v := _open()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	v.add_child(head)
	_label(head, "SHOP", _big, 52)
	_coin_display(head, Run.coins, 40, 34.0)
	if Run.is_boss_level():
		_label(v, "Prepare for the boss", _body, 22, Color(CREAM, 0.7))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	for i in 4:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		h.add_child(col)
		var o: Dictionary = Run.shop_offers[i]
		if o.is_empty():
			var sold := _card(col, "Sold", "", Color(0.4, 0.4, 0.45))
			sold.disabled = true
			sold.size_flags_vertical = Control.SIZE_EXPAND_FILL
			continue
		var c: Button
		if o.kind == "weapon":
			var w: Dictionary = o.weapon
			var d: Dictionary = Run.WEAPONS[w.id]
			var weapon_color: Color = Run.ELEMENTS[w.element].color if w.element != "" else Run.TIER_COLORS[w.tier]
			var body := "%d dmg × %d  ·  %.1f/s\n%d rounds" % [Run.weapon_dmg(w), d.pellets, d.rate, d.mag]
			if w.element != "":
				body += "\n%s rounds" % {"fire": "Burning", "shock": "Chaining", "rust": "Corroding"}[w.element]
			c = _card(col, Run.weapon_name(w), body, Run.TIER_COLORS[w.tier], "%d" % o.price,
				"%s weapon" % Run.TIER_NAMES[w.tier], Icons.for_weapon(w.id, w.tier, w.element), weapon_color)
		else:
			c = _item_card(col, o.id, o.price, Run.stack(o.id))
		# Cards in a row stretch to the tallest so the lock buttons line up.
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.disabled = Run.coins < o.price
		c.pressed.connect(func():
			if Run.buy(i):
				Kit.sfx(self, "catch", null, -6.0)
				show_shop())
		var lock := _button(col, "LOCKED" if Run.shop_locked[i] else "LOCK", Color(0.6, 0.6, 0.7), 260.0)
		lock.custom_minimum_size.y = 40
		lock.add_theme_font_size_override("font_size", 18)
		lock.pressed.connect(func():
			Run.shop_locked[i] = not Run.shop_locked[i]
			show_shop())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var rr := _button(row, "REROLL", TIME)
	rr.disabled = Run.coins < Run.reroll_price()
	rr.pressed.connect(func():
		if Run.reroll():
			show_shop())
	_coin_display(row, Run.reroll_price(), 24, 22.0)
	var leave := _button(row, "LEAVE")
	leave.pressed.connect(func(): shop_closed.emit())
	_owned_items_row(v)


func show_pause() -> void:
	_submenu_return_to_pause = false
	_open_canvas()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := _glass_panel(center, Vector2(480, 450))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_label(v, "PAUSED", _big, 58, Color("f5faf5"))
	v.add_child(_spacer(8))
	var r := _flat_button(v, "RESUME", 360, 27)
	r.alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.pressed.connect(func(): resume_pressed.emit())
	r.grab_focus.call_deferred()
	var settings := _flat_button(v, "SETTINGS", 360, 27)
	settings.alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func(): show_settings(true))
	var controls := _flat_button(v, "CONTROLS", 360, 27)
	controls.alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.pressed.connect(func(): show_how_to_play(true))
	var title := _flat_button(v, "QUIT TO TITLE", 360, 25)
	title.alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.pressed.connect(func(): title_pressed.emit())


func show_end(won: bool) -> void:
	var v := _open()
	_label(v, "VICTORY" if won else "DEFEAT", _big, 96, GOLD if won else Color("ff5a5e"))
	_label(v, "%s     Act %d     %d kills" % [Run.DIFFICULTIES[Run.difficulty].name, Run.act, Run.kills], _ui, 28)
	var b := _button(v, "NEW RUN")
	b.pressed.connect(func(): start_pressed.emit())
	b.grab_focus.call_deferred()
	var t := _button(v, "TITLE", Color(0.6, 0.6, 0.7))
	t.pressed.connect(func(): title_pressed.emit())


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


## The HUD's ink brush stroke, drawn behind a big title label's text.
class InkBrush extends Control:
	func _ready() -> void:
		get_parent().draw.connect(queue_redraw)

	func _draw() -> void:
		var l := get_parent() as Label
		if l == null:
			return
		var font := l.get_theme_font("font")
		var fsize := l.get_theme_font_size("font_size")
		var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + fsize * 1.6
		var h := fsize * 1.05
		var x := 0.0
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER: x = (size.x - w) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT: x = size.x - w
			_: x = -fsize * 0.5
		var p := Vector2(x, (size.y - h) * 0.5)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(h * 0.2, h * 0.18), p + Vector2(h * 0.9, 0), p + Vector2(w * 0.7, h * 0.04),
			p + Vector2(w, h * 0.22), p + Vector2(w - h * 1.3, h * 0.82), p + Vector2(w * 0.55, h),
			p + Vector2(h * 0.5, h * 0.94), p + Vector2(0, h * 0.6)]), Color(0.025, 0.045, 0.05, 0.84))


## A menu word that lights up in its accent while focused. Hovering focuses it, so mouse
## and keys share one highlight.
class MenuItem extends Button:
	var accent := Color("ffe08b")
	var centered := false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_entered.connect(grab_focus)
