class_name Panels
## Small reusable panels shared by the title screen and the in-game menu.

const CONTROLS := [
	["W A S D", "Move"],
	["SPACE", "Jump"],
	["LMB", "Use: fire, recall, punch, pull"],
	["RMB", "Throw the gun"],
	["E", "Interact"],
	["Q", "Ping"],
	["R", "Restart room"],
	["ESC", "Menu"],
]


## A key cap as a Control.
static func key_cap(key: String, accent := Ui.TEXT) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := Ui.flat(Color(1, 1, 1, 0.04), 3, 1, Color(accent, 0.45))
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Ui.label(key, 16, accent, Ui.NUMBER, 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


static func _frame(title: String, width := 460.0) -> Array:
	var panel := PanelContainer.new()
	var sb := Ui.flat(Ui.PANEL, 4, 1, Ui.LINE)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 30
	sb.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(width, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(Ui.label(title, 15, Ui.MUTED, Ui.LABEL))
	box.add_child(Ui.rule(width - 72))
	return [panel, box]


static func controls(accent := Ui.TEXT) -> PanelContainer:
	var f := _frame("CONTROLS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	f[1].add_child(grid)
	for row: Array in CONTROLS:
		var cap := key_cap(row[0], accent)
		cap.size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(cap)
		grid.add_child(Ui.label(row[1], 18, Ui.TEXT, Ui.BODY))
	return f[0]


static func _toggle_row(name: String, options: Array, current: int, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Ui.label(name, 15, Ui.TEXT, Ui.LABEL)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var buttons: Array[Button] = []
	for i in options.size():
		var b := Ui.button(String(options[i]), Ui.TEXT, false, 13)
		b.toggle_mode = true
		b.button_pressed = i == current
		b.add_theme_color_override("font_pressed_color", Ui.INK)
		b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("hover"))
		buttons.append(b)
		row.add_child(b)
	for i in buttons.size():
		buttons[i].pressed.connect(func() -> void:
			for j in buttons.size():
				buttons[j].set_pressed_no_signal(j == i)
			on_pick.call(i))
	return row


static func settings() -> PanelContainer:
	var f := _frame("SETTINGS")
	var box: VBoxContainer = f[1]
	box.add_child(_toggle_row("GRAPHICS", ["HIGH", "LOW"], 0 if Game.high_quality() else 1,
		func(i: int) -> void: Game.set_quality("high" if i == 0 else "low")))
	box.add_child(_toggle_row("DISPLAY", ["FULLSCREEN", "WINDOW"], 0 if Game.is_fullscreen() else 1,
		func(i: int) -> void: Game.set_fullscreen(i == 0)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Ui.label("MOUSE", 15, Ui.TEXT, Ui.LABEL)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = Game.sensitivity
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.add_theme_stylebox_override("slider", _thin(Color(1, 1, 1, 0.18)))
	slider.add_theme_stylebox_override("grabber_area", _thin(Ui.TEXT))
	slider.add_theme_stylebox_override("grabber_area_highlight", _thin(Ui.TEXT))
	var dot := _dot_texture()
	slider.add_theme_icon_override("grabber", dot)
	slider.add_theme_icon_override("grabber_highlight", dot)
	row.add_child(slider)
	var val := Ui.label("%.2f" % Game.sensitivity, 18, Ui.MUTED, Ui.NUMBER)
	val.custom_minimum_size.x = 44
	row.add_child(val)
	slider.value_changed.connect(func(v: float) -> void:
		val.text = "%.2f" % v
		Game.set_sensitivity(v))
	box.add_child(row)
	return f[0]


static func _thin(c: Color) -> StyleBoxFlat:
	var sb := Ui.flat(c, 1)
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb


static func _dot_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			img.set_pixel(x, y, Color(1, 1, 1, clampf(6.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
