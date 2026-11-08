class_name Hud
extends Control
## In-run overlay in a brushed-ink style: minimap and stage plate (top left), boss bar (top),
## currency (top right), portrait with shield and health (bottom left), the ultimate dial and
## power/item tray (bottom centre), and abilities, ammo and the rendered gun (bottom right).

const INK := Color(0.025, 0.045, 0.05, 0.84)
const INK_SOLID := Color(0.012, 0.025, 0.03)
const HP := Color("8fe46c")
const HP_LOW := Color("ff5b5f")
const SHIELD := Color("5ccff0")
const GOLD := Color("ffd24a")
const CREAM := Color("fff4e0")
const TIME := Color("83d4c2")
const BOSS_HP := Color("f0c02c")
const BOSS_TRAIL := Color("e0363d")
const MAP_R := 74.0
const MAP_SCALE := MAP_R / 34.0
## Layout is authored for a 1080p canvas; this shrinks it to fit the real one.
const DESIGN_HEIGHT := 1080.0
const HUD_SCALE := 0.8
const UI_BLUR_SHADER: Shader = preload("res://shaders/ui_blur.gdshader")

var player: Player
var banner := ""
var banner_t := 0.0
var banner_color := CREAM
## Optional small line under the banner, e.g. the era's few words on arrival.
var banner_sub := ""
var run_time := 0.0
## Cutscene overlay set by Cutscene ({} when none) and its progress, 0..1.
var cine := {}
var cine_p := 0.0
var _font: Font
var _hero := ""
var _hp_shown := 100.0
var _shield_shown := 50.0
var _boss: Boss
var _boss_shown := 1.0
var _held := -1
var _swap_t := 0.0
var _pulse := 0.0
var _stats_blur: ColorRect
var _base := Transform2D.IDENTITY
## First-time ability tips: one per hero per launch for the E skill, and one for the ultimate.
var _tip_key := ""
var _tip_title := ""
var _tip_text := ""
var _tip_t := 0.0
var _tip_slot := ""
var _tips_seen := {}
var _fight_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud")
	_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_stats_blur = ColorRect.new()
	_stats_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_blur.show_behind_parent = true
	var blur_material := ShaderMaterial.new()
	blur_material.shader = UI_BLUR_SHADER
	_stats_blur.material = blur_material
	_stats_blur.hide()
	add_child(_stats_blur)


func show_banner(text: String, col := CREAM, sub := "") -> void:
	banner = text
	banner_color = col
	banner_sub = sub
	banner_t = 3.4 if sub != "" else 2.6


func set_hero(id: String) -> void:
	_hero = id


func _process(delta: float) -> void:
	banner_t = maxf(0.0, banner_t - delta)
	_swap_t = maxf(0.0, _swap_t - delta)
	_pulse += delta
	if player and not get_tree().paused:
		run_time += delta
		_tick_tips(delta)
	var stats_open := player != null and not get_tree().paused and Input.is_action_pressed("stats")
	if is_instance_valid(_stats_blur):
		_stats_blur.visible = stats_open
	if Run.held != _held:
		_swap_t = 1.6 if _held >= 0 else 0.0
		_held = Run.held
	# Trails ease down to the real value so recent damage reads as a pale chunk.
	var k := 1.0 - exp(-3.0 * delta)
	_hp_shown = Run.hp if Run.hp > _hp_shown else lerpf(_hp_shown, Run.hp, k)
	_shield_shown = Run.shield if Run.shield > _shield_shown else lerpf(_shield_shown, Run.shield, k)
	var bosses := get_tree().get_nodes_in_group("boss")
	var b: Boss = bosses[0] if not bosses.is_empty() else null
	if b != _boss:
		_boss = b
		_boss_shown = 1.0
	if _boss:
		_boss_shown = lerpf(_boss_shown, _boss.hp / _boss.max_hp, 1.0 - exp(-2.0 * delta))
	queue_redraw()


func _tick_tips(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive:
		_tip_t = 0.0
		return
	var def := Run.hero_def()
	_fight_t = _fight_t + delta if not get_tree().get_nodes_in_group("enemies").is_empty() else 0.0
	if _tip_t > 0.0:
		_tip_t -= delta
		var used: bool = player.cooldowns.e > 0.0 if _tip_slot == "e" else Run.ult < 100.0
		if used:
			_tip_t = minf(_tip_t, 0.3)
		return
	var e_id := "e:" + Run.hero
	var q_id := "q:" + Run.hero
	if Run.ult >= 100.0 and not _tips_seen.has(q_id):
		_tips_seen[q_id] = true
		_show_tip("q", "Q", "ULTIMATE READY: %s" % def.q.name.to_upper(), def.q.text, 10.0)
	elif _fight_t > 1.5 and player.cooldowns.e <= 0.0 and not _tips_seen.has(e_id):
		_tips_seen[e_id] = true
		_show_tip("e", "E", "USE YOUR SKILL: %s" % def.e.name.to_upper(), def.e.text, 9.0)


func _show_tip(slot: String, key: String, title: String, text: String, t: float) -> void:
	_tip_slot = slot
	_tip_key = key
	_tip_title = title
	_tip_text = text
	_tip_t = t
	Kit.sfx(player, "card", null, -4.0, 1.3)


func _draw_tip(s: Vector2) -> void:
	if _tip_t <= 0.0:
		return
	var a := clampf(_tip_t * 3.0, 0.0, 1.0)
	var pop := 1.0 + 0.06 * sin(_pulse * 6.0)
	var accent: Color = Run.hero_def().accent
	var key_w := maxf(30.0, _text_w(_tip_key, 20) + 16)
	var w := maxf(_text_w(_tip_title, 28) + key_w + 70, _text_w(_tip_text, 20) + 60)
	var c := Vector2(s.x * 0.5, s.y * 0.76)
	var plate := Rect2(c.x - w * 0.5, c.y - 30, w, 84)
	_slant(plate.grow(3), Color(INK_SOLID, a), 14)
	_slant(plate, Color(INK, 0.95 * a), 14)
	draw_rect(Rect2(plate.position + Vector2(14, 0), Vector2(w - 28, 4)), Color(accent, a))
	var kc := Vector2(plate.position.x + 30 + key_w * 0.5, c.y - 2)
	var kr := Rect2(kc - Vector2(key_w, 30) * 0.5 * pop, Vector2(key_w, 30) * pop)
	draw_rect(kr.grow(2), Color(INK_SOLID, a))
	draw_rect(kr, Color(accent, a))
	draw_string(_font, Vector2(kr.position.x, kc.y + 7), _tip_key, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x, 20, Color(INK_SOLID, a))
	_text(Vector2(kc.x + key_w * 0.5 + 14, c.y + 8), _tip_title, 28, Color(accent.lerp(CREAM, 0.4), a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5, 0.08)
	_text(Vector2(plate.position.x, c.y + 40), _tip_text, 20, Color(CREAM, a), HORIZONTAL_ALIGNMENT_CENTER, w, 4, 0.0)


## --- Drawing helpers ---------------------------------------------------------------

## Chunky outlined lettering, slightly skewed like brush lettering.
func _text(pos: Vector2, s: String, fsize: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 6, skew := 0.12) -> void:
	draw_set_transform_matrix(_base * Transform2D(Vector2(1, 0), Vector2(-skew, 1), pos))
	if outline > 0:
		draw_string_outline(_font, Vector2.ZERO, s, align, width, fsize, outline, Color(INK_SOLID, col.a))
	draw_string(_font, Vector2.ZERO, s, align, width, fsize, col)
	draw_set_transform_matrix(_base)


func _text_w(s: String, fsize: int) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


## A parallelogram leaning right, the base shape for bars and plates.
func _slant(rect: Rect2, col: Color, sk := -1.0) -> void:
	var k := rect.size.y * 0.5 if sk < 0.0 else sk
	draw_colored_polygon(PackedVector2Array([rect.position + Vector2(k, 0), rect.position + Vector2(rect.size.x, 0),
		rect.position + Vector2(rect.size.x - k, rect.size.y), rect.position + Vector2(0, rect.size.y)]), col)


## An ink brush stroke: blunt at the start, tapering to a point at the end.
func _brush(pos: Vector2, length: float, h: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(h * 0.2, h * 0.18), pos + Vector2(h * 0.9, 0), pos + Vector2(length * 0.7, h * 0.04),
		pos + Vector2(length, h * 0.22), pos + Vector2(length - h * 1.3, h * 0.82), pos + Vector2(length * 0.55, h),
		pos + Vector2(h * 0.5, h * 0.94), pos + Vector2(0, h * 0.6)]), col)


## A slanted bar with an ink rim, a pale trail (recent loss) and a glossy fill.
func _bar(rect: Rect2, frac: float, col: Color, trail := -1.0, trail_col := Color(1, 1, 1, 0.55)) -> void:
	_slant(rect.grow(3), INK_SOLID)
	_slant(rect, Color(0.08, 0.1, 0.11, 0.9))
	if trail > frac:
		_slant_part(rect, trail, trail_col)
	if frac > 0.0:
		_slant_part(rect, frac, col)
		_slant_part(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.32)), frac, Color(1, 1, 1, 0.28))


func _slant_part(rect: Rect2, frac: float, col: Color) -> void:
	var k := rect.size.y * 0.5
	var w := (rect.size.x - k) * clampf(frac, 0.0, 1.0) + k
	_slant(Rect2(rect.position, Vector2(w, rect.size.y)), col, k)


func _key(c: Vector2, label: String, fsize := 15) -> void:
	var w := maxf(22.0, _text_w(label, fsize) + 12)
	var r := Rect2(c - Vector2(w * 0.5, 11), Vector2(w, 22))
	draw_rect(r.grow(2), INK_SOLID)
	draw_rect(r, CREAM)
	draw_string(_font, Vector2(r.position.x, c.y + 6), label, HORIZONTAL_ALIGNMENT_CENTER, w, fsize, INK_SOLID)


## An action hint: a black ink plate holding a white key badge and the action in cream,
## centred on `c`, so it reads over bright snow and sand alike.
func _prompt(c: Vector2, key: String, text: String, fsize := 22) -> void:
	var key_w := maxf(22.0, _text_w(key, 15) + 12)
	var w := key_w + 14 + _text_w(text, fsize) + 36
	var h := fsize + 18.0
	var plate := Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h)
	_slant(plate.grow(3), INK_SOLID, 12)
	_slant(plate, Color(INK, 0.95), 12)
	_key(Vector2(plate.position.x + 18 + key_w * 0.5, c.y), key)
	_text(Vector2(plate.position.x + 18 + key_w + 12, c.y + fsize * 0.36), text, fsize, CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4, 0.0)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## A texture clipped to a circle (uv_c / uv_r pick the crop inside the texture).
func _circle_tex(c: Vector2, r: float, tex: Texture2D, uv_c := Vector2(0.5, 0.42), uv_r := 0.4) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var d := Vector2.from_angle(TAU * i / 40.0)
		pts.append(c + d * r)
		uvs.append(uv_c + d * uv_r)
	draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)


func _pie(c: Vector2, r: float, frac: float, col: Color) -> void:
	if frac <= 0.0:
		return
	var pts := PackedVector2Array([c])
	var steps := maxi(2, int(40 * frac))
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * frac * i / steps) * r)
	draw_colored_polygon(pts, col)


func _draw() -> void:
	if player == null:
		return
	if not cine.is_empty():
		var kc := size.y / DESIGN_HEIGHT
		_base = Transform2D.IDENTITY.scaled(Vector2(kc, kc))
		draw_set_transform_matrix(_base)
		_draw_boss_intro(size / kc)
		return
	# World-anchored marks stay in real screen space; everything else is scaled.
	_base = Transform2D.IDENTITY
	draw_set_transform_matrix(_base)
	_draw_enemy_bars()
	if player.gun.scoped():
		_draw_scope(size)
	elif Preferences.show_crosshair and player.gun.ads < 0.5:
		_draw_crosshair(size)
	var k := maxf(0.45, HUD_SCALE * Preferences.hud_scale * size.y / DESIGN_HEIGHT)
	_base = Transform2D.IDENTITY.scaled(Vector2(k, k))
	draw_set_transform_matrix(_base)
	var s := size / k
	_draw_map()
	_draw_currency(s)
	_draw_you(s)
	_draw_tray(s)
	_draw_kit(s)
	_draw_boss(s)
	_draw_clock(s)
	if player.prompt != "":
		_prompt(Vector2(s.x * 0.5, s.y * 0.66), "F", player.prompt.trim_prefix("[F]").strip_edges(), 24)
	_draw_tip(s)
	var wpn := Run.current_weapon()
	if not player.gun.reloading() and player.gun.ammo() <= int(Run.WEAPONS[wpn.id].mag * 0.25):
		_prompt(Vector2(s.x * 0.5, s.y * 0.5 + 64), "R", "Reload", 24)
	if player.hurt_flash > 0.0:
		var a := player.hurt_flash * 0.4
		var c := Color(1, 0.1, 0.15, a) if Run.shield <= 0.0 else Color(0.5, 0.85, 1.0, a * 0.6)
		for r in [Rect2(0, 0, s.x, 22), Rect2(0, s.y - 22, s.x, 22), Rect2(0, 0, 22, s.y), Rect2(s.x - 22, 0, 22, s.y)]:
			draw_rect(r, c)
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		var y := s.y * 0.25
		# Same solid ink plate as the action prompts so the text reads over bright floors.
		var w := _text_w(banner, 40) + 80
		var plate := Rect2(s.x * 0.5 - w * 0.5, y - 4, w, 60)
		_slant(plate.grow(3), Color(INK_SOLID, a), 14)
		_slant(plate, Color(INK, 0.95 * a), 14)
		_text(Vector2(plate.position.x, y + 41), banner, 40, Color(banner_color, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		if banner_sub != "":
			var sw := _text_w(banner_sub, 22) + 48
			var sub_plate := Rect2(s.x * 0.5 - sw * 0.5, y + 62, sw, 34)
			_slant(sub_plate, Color(INK, 0.9 * a), 10)
			_text(Vector2(sub_plate.position.x, y + 87), banner_sub, 22, Color(CREAM, a), HORIZONTAL_ALIGNMENT_CENTER, sw)
	if not get_tree().paused and Input.is_action_pressed("stats"):
		_draw_stats(s)


## --- Top left: minimap, stage plate, timer -----------------------------------------

func _draw_map() -> void:
	var c := Vector2(112, 112)
	# Stage plate first so the map disc overlaps its blunt end.
	_brush(Vector2(c.x + 20, 30), 400, 46, INK)
	draw_line(Vector2(c.x + 70, 84), Vector2(c.x + 330, 84), Color(INK_SOLID, 0.8), 3.0)
	_text(Vector2(c.x + 90, 64), "%d" % Run.act, 24, GOLD)
	_text(Vector2(c.x + 116, 64), Run.biome_name(), 24, CREAM)
	var rooms := Run.COMBAT_ROOMS + 1 + (1 if Run.is_boss_level() else 0)
	for i in rooms:
		var pc := Vector2(c.x + 98 + i * 22, 100)
		var big := i >= Run.COMBAT_ROOMS
		var col := GOLD if i < Run.room else (Color.WHITE if i == Run.room else Color(1, 1, 1, 0.3))
		_diamond(pc, 8.0 if big else 6.5, INK_SOLID)
		_diamond(pc, 5.5 if big else 4.0, col)
	# Disc with a heavy ink rim.
	draw_circle(c, MAP_R + 10, INK_SOLID)
	draw_circle(c, MAP_R, Color(0.07, 0.13, 0.13, 0.78))
	draw_arc(c, MAP_R * 0.55, 0, TAU, 40, Color(1, 1, 1, 0.07), 1.5)
	draw_arc(c, MAP_R + 4, -0.4, PI * 1.3, 48, Color(1, 1, 1, 0.1), 2.0, true)
	var yaw := player.global_rotation.y
	var origin := player.global_position
	var to_map := func(p: Vector3) -> Vector2:
		var d := Vector2(p.x - origin.x, p.z - origin.z).rotated(yaw) * MAP_SCALE
		return c + d.limit_length(MAP_R - 7)
	for n in get_tree().get_nodes_in_group("interact"):
		var col: Color = {"portal": Color("6fd8ff"), "chest": GOLD, "relic": TIME, "vendor": GOLD, "loot": Color.WHITE}.get(n.kind, Color.WHITE)
		_diamond(to_map.call(n.global_position), 8.0, INK_SOLID)
		_diamond(to_map.call(n.global_position), 5.5, col)
	for e in get_tree().get_nodes_in_group("enemies"):
		var p: Vector2 = to_map.call(e.global_position)
		var r := 7.0 if e is Boss else 4.0
		draw_circle(p, r + 1.5, INK_SOLID)
		draw_circle(p, r, Color("ff5a5e") if not e.elite else GOLD)
	var accent: Color = Run.hero_def().accent
	var arrow := PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 8), c + Vector2(0, 3), c + Vector2(-8, 8)])
	draw_colored_polygon(arrow, accent)
	arrow.append(arrow[0])
	draw_polyline(arrow, INK_SOLID, 2.0, true)
	# Run timer tag tucked under the disc.
	var secs := int(run_time)
	var tag := Rect2(c.x - 58, c.y + MAP_R + 2, 116, 28)
	_slant(tag, INK_SOLID, 10)
	_text(tag.position + Vector2(0, 21), "%dm %02ds" % [secs / 60, secs % 60], 18, CREAM, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 0)


func _draw_currency(s: Vector2) -> void:
	var y := 52.0
	var coins := "%d" % Run.coins
	var right := s.x - 40.0
	_text(Vector2(right - _text_w(coins, 30), y), coins, 30, GOLD)
	Icons.paint(self, "coin", Vector2(right - _text_w(coins, 30) - 22, y - 11), 14, Color.WHITE)
	var kills := "%d" % Run.kills
	var kx := right - _text_w(coins, 30) - 70
	_text(Vector2(kx - _text_w(kills, 30), y), kills, 30, Color("ffd9cf"))
	Icons.paint(self, "skull", Vector2(kx - _text_w(kills, 30) - 22, y - 11), 13, Color("ffb0a8"))


## --- Bottom left: portrait, shield and health ---------------------------------------

func _draw_you(s: Vector2) -> void:
	var d := Run.hero_def()
	var accent: Color = d.accent
	var pc := Vector2(108, s.y - 108)
	var bx := pc.x + 92
	var by := s.y - 142
	_brush(Vector2(pc.x + 10, by - 16), 470, 82, INK)
	# Weapon disc with a gear-tooth rim in the loadout's colour.
	for i in 12:
		var a := TAU * i / 12.0
		_diamond(pc + Vector2.from_angle(a) * 70, 9, INK_SOLID)
	draw_circle(pc, 72, INK_SOLID)
	draw_circle(pc, 65, accent.darkened(0.6))
	var held: Dictionary = Run.current_weapon()
	Icons.paint_weapon(self, Icons.for_weapon(held.id, held.tier, held.element), pc, 25)
	draw_arc(pc, 66, 0, TAU, 56, accent, 4.0, true)
	# Shield above health; the health bar sits a step left to follow the slant.
	var max_shield := Run.max_shield()
	var hp_max := Run.max_hp()
	var low := Run.hp <= hp_max * 0.3
	_bar(Rect2(bx + 10, by, 290, 13), Run.shield / max_shield, SHIELD, _shield_shown / max_shield)
	var hp_col := HP
	if low:
		hp_col = HP_LOW.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_pulse * 8.0)))
	_bar(Rect2(bx - 4, by + 22, 330, 22), Run.hp / hp_max, hp_col, _hp_shown / hp_max)
	var tx := bx + 334
	_text(Vector2(tx, by + 13), "%d/%d" % [ceili(Run.shield), roundi(max_shield)], 20, SHIELD, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	_text(Vector2(tx - 8, by + 42), "%d/%d" % [ceili(Run.hp), roundi(hp_max)], 24, hp_col, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)


## --- Bottom centre: ultimate dial and power/item tray ----------------------------

func _draw_tray(s: Vector2) -> void:
	_ult(Vector2(s.x * 0.5, s.y - 128), Run.hero_def())
	var tiles: Array = []
	for id in Run.powers:
		tiles.append([Icons.for_power(id), 0, TIME])
	for id in Run.items:
		tiles.append([Icons.for_item(id), Run.items[id], Run.item_color(id)])
	if tiles.is_empty():
		return
	var n := tiles.size()
	var step := 46.0
	var x0 := s.x * 0.5 - n * step * 0.5
	for i in n:
		var t: Array = tiles[i]
		var r := Rect2(x0 + i * step + 3, s.y - 64, 40, 40)
		draw_rect(r.grow(3), INK_SOLID)
		draw_rect(r, Color(t[2].darkened(0.75), 0.92))
		draw_rect(r, t[2], false, 2.0)
		Icons.paint(self, t[0], r.get_center(), 13, t[2])
		if t[1] > 1:
			_text(r.end + Vector2(-16, 2), "%d" % t[1], 15, CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, 0)


func _ult(c: Vector2, d: Dictionary) -> void:
	var frac := Run.ult / 100.0
	var ready := frac >= 1.0
	var accent: Color = d.accent
	var r := 32.0
	if ready:
		var p := 1.0 + sin(_pulse * 6.0) * 0.06
		draw_arc(c, (r + 9) * p, 0, TAU, 48, Color(accent, 0.7), 3.0, true)
	draw_circle(c, r + 6, INK_SOLID)
	draw_circle(c, r, Color(0.12, 0.13, 0.16))
	_pie(c, r, frac, Color(accent, 0.55 if not ready else 0.9))
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, accent, 4.0, true)
	draw_circle(c, r * 0.62, Color(INK_SOLID, 0.85))
	Icons.paint(self, d.q.id, c, 13, Color.WHITE if ready else Color(accent, 0.8))
	if not ready:
		_text(c + Vector2(-r - 30, -r + 6), "%d" % int(Run.ult), 18, CREAM, HORIZONTAL_ALIGNMENT_RIGHT, 36, 4)
	_key(c + Vector2(r + 4, r - 2), "Q", 13)


## Hold Tab to inspect the current build and the active weapon's derived stats.
func _draw_stats(s: Vector2) -> void:
	var accent: Color = Run.hero_def().accent
	var tiles := Run.powers.size() + Run.items.size()
	var panel_size := Vector2(minf(780.0, s.x - 40.0), 372.0 + (64.0 if tiles > 0 else 0.0))
	var panel := Rect2((s - panel_size) * 0.5, panel_size)
	draw_rect(panel.grow(4), INK_SOLID)
	draw_rect(panel, Color(0.04, 0.07, 0.08, 0.96))
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 4)), accent)
	# Header: hero, weapon and act on one slanted strip.
	var w: Dictionary = Run.current_weapon()
	var data: Dictionary = Run.WEAPONS[w.id]
	var tier_col: Color = Run.TIER_COLORS[w.tier]
	_text(panel.position + Vector2(28, 44), Run.weapon_name(w).to_upper(), 30, tier_col)
	Icons.paint_weapon(self, Icons.for_weapon(w.id, w.tier, w.element), panel.position + Vector2(panel.size.x - 92, 30), 22)
	draw_line(panel.position + Vector2(24, 62), panel.position + Vector2(panel.size.x - 24, 62), Color(1, 1, 1, 0.1), 2.0)
	var haste := 1.5 if player.haste_t > 0.0 else 1.0
	if player.ult_active("overclock"):
		haste *= 2.0
	var damage := Run.weapon_dmg(w) * Run.dmg_mult()
	var attack := [
		["dmg", "%.0f × %d" % [damage, data.pellets]],
		["rate", "%.1f /s" % (data.rate * Run.rate_mult() * haste)],
		["reload", "%.2f s" % player.gun.reload_total()],
		["crit", "%.0f%%" % (Run.crit_chance() * 100.0)],
		["critdmg", "%.1f×" % Run.crit_mult()],
		["elem", "%.0f%%" % clampf((0.3 + Run.stat("elem")) * 100.0, 0.0, 100.0)],
	]
	var defence := [
		["hp", "%d / %d" % [ceili(Run.hp), roundi(Run.max_hp())]],
		["shield", "%d / %d" % [ceili(Run.shield), roundi(Run.max_shield())]],
		["speed", "%.1f m/s" % (Player.SPEED * (1.0 + Run.stat("speed") + (0.5 if player.haste_t > 0.0 else 0.0)))],
		["cdr", "-%.0f%%  E %.1fs" % [(1.0 - Run.cd_mult()) * 100.0, player.cd_total("e")]],
		["coins", "+%.0f%%" % (Run.stat("coins") * 100.0)],
	]
	var col_w := (panel.size.x - 72.0) * 0.5
	var top := panel.position.y + 76.0
	var left := panel.position.x + 24.0
	var right := left + col_w + 24.0
	_text(Vector2(left, top + 16), "OFFENCE", 16, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 0, 0)
	_text(Vector2(right, top + 16), "SURVIVAL", 16, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 0, 0)
	for i in attack.size():
		_draw_stat_row(left, top + 26 + i * 42.0, col_w, attack[i][0], attack[i][1], i)
	for i in defence.size():
		_draw_stat_row(right, top + 26 + i * 42.0, col_w, defence[i][0], defence[i][1], i)
	if tiles == 0:
		return
	# Build tray: time powers then items, with stack counts.
	var ty := panel.end.y - 64.0
	draw_line(Vector2(panel.position.x + 24, ty - 8), Vector2(panel.end.x - 24, ty - 8), Color(1, 1, 1, 0.1), 2.0)
	var x := left
	for id in Run.powers:
		_stat_tile(Vector2(x, ty), Icons.for_power(id), TIME, 0)
		x += 50.0
	for id in Run.items:
		_stat_tile(Vector2(x, ty), Icons.for_item(id), Run.item_color(id), Run.items[id])
		x += 50.0


func _stat_tile(pos: Vector2, icon: String, col: Color, count: int) -> void:
	var r := Rect2(pos, Vector2(42, 42))
	draw_rect(r, Color(col.darkened(0.75), 0.95))
	draw_rect(r, col, false, 2.0)
	Icons.paint(self, icon, r.get_center(), 13, col)
	if count > 1:
		_text(r.end + Vector2(-15, 2), "%d" % count, 15, CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, 4, 0)


func _draw_stat_row(x: float, y: float, width: float, stat_id: String, value: String, i: int) -> void:
	if i % 2 == 0:
		draw_rect(Rect2(x, y, width, 38), Color(1, 1, 1, 0.04))
	var col: Color = Run.stat_color(stat_id)
	Icons.paint(self, Run.stat_icon(stat_id), Vector2(x + 20, y + 19), 10, col)
	_text(Vector2(x + 42, y + 26), Run.STAT_DEFS[stat_id].name, 18, CREAM, HORIZONTAL_ALIGNMENT_LEFT, width - 170, 0, 0)
	_text(Vector2(x + width - 150, y + 26), value, 19, col, HORIZONTAL_ALIGNMENT_RIGHT, 140, 0, 0)


## --- Bottom right: abilities, ammo, gun ---------------------------------------------

func _draw_kit(s: Vector2) -> void:
	var d := Run.hero_def()
	var gun := player.gun
	var w := Run.current_weapon()
	var data: Dictionary = Run.WEAPONS[w.id]
	var right := s.x - 36.0
	# Abilities as slanted tiles, left of the gun.
	_ability_tile(Vector2(right - 470, s.y - 96), d.e.id, "E", player.ready_frac("e"), player.cooldowns.e)
	_ability_tile(Vector2(right - 386, s.y - 96), d.shift.id, "SHIFT", player.ready_frac("shift"), player.cooldowns.shift)
	# The gun on an ink stroke.
	_brush(Vector2(right - 300, s.y - 122), 300, 70, INK)
	Icons.paint_weapon(self, Icons.for_weapon(w.id, w.tier, w.element), Vector2(right - 135, s.y - 88), 44)
	# Ammo: big current count over a smaller magazine size, right-aligned.
	var mag: int = data.mag
	var ammo_col := Color.WHITE if gun.ammo() > mag * 0.25 else HP_LOW
	if player.ult_active("overclock"):
		ammo_col = d.accent
	var mag_s := "/%d" % mag
	var ammo_s := "%d" % gun.ammo()
	var ay := s.y - 136.0
	_text(Vector2(right - _text_w(mag_s, 28), ay), mag_s, 28, Color(ammo_col, 0.85))
	_text(Vector2(right - _text_w(mag_s, 28) - _text_w(ammo_s, 50) - 4, ay), ammo_s, 50, ammo_col, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
	if gun.reloading():
		_bar(Rect2(right - 190, ay + 8, 186, 6), 1.0 - gun.reload_t / gun.reload_total(), CREAM)
	if _swap_t > 0.0:
		var a := clampf(_swap_t * 2.0, 0.0, 1.0)
		_text(Vector2(right - 400, ay - 52), Run.weapon_name(w), 20, Color(Run.TIER_COLORS[w.tier], a), HORIZONTAL_ALIGNMENT_RIGHT, 400, 5)
	# Fire mode and weapon slots along the bottom edge.
	_text(Vector2(right - 232, s.y - 22), "AUTO" if data.auto else "SEMI", 15, Color(CREAM, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	for i in Run.weapons.size():
		var held := i == Run.held
		var tier_col: Color = Run.TIER_COLORS[Run.weapons[i].tier]
		var x := right - 92 + i * 40 - (Run.weapons.size() - 2) * 40
		_text(Vector2(x, s.y - 14), "%d" % (i + 1), 34 if held else 24, CREAM if held else Color(tier_col, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 0.2)


func _ability_tile(c: Vector2, icon: String, key: String, frac: float, left: float) -> void:
	var ready := frac >= 1.0
	var accent: Color = Run.hero_def().accent
	var r := Rect2(c - Vector2(38, 27), Vector2(76, 54))
	_slant(r.grow(4), INK_SOLID, 18)
	_slant(r, Color(accent.darkened(0.7), 0.95) if ready else Color(0.1, 0.11, 0.13, 0.95), 16)
	if not ready:
		# Charge rises from the bottom of the tile.
		var h := r.size.y * frac
		_slant(Rect2(r.position.x, r.end.y - h, r.size.x - 16.0 * (1.0 - frac), h), Color(accent, 0.22), 16.0 * frac)
	Icons.paint(self, icon, c, 15, accent if ready else Color(1, 1, 1, 0.35))
	if not ready:
		_text(c + Vector2(-38, 10), "%.0f" % ceilf(left), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 76, 6, 0)
	_key(c + Vector2(-2, 36), key, 13)


## --- World-space: enemy bars, crosshair, boss --------------------------------------

func _draw_enemy_bars() -> void:
	var cam := player.cam
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Boss or (e.since_hit > 4.0 and not e.elite):
			continue
		var top: Vector3 = e.global_position + Vector3.UP * (e.size * 2.0 + 0.4)
		if cam.is_position_behind(top) or cam.global_position.distance_to(top) > 45.0:
			continue
		var p := cam.unproject_position(top)
		var w := 64.0
		_bar(Rect2(p.x - w * 0.5, p.y, w, 6), e.hp / e.max_hp, GOLD if e.elite else Color("ff4d5e"))


## Sniper scope: black all round a round lens, a thin reticle with mil ticks, a soft rim.
func _draw_scope(s: Vector2) -> void:
	var c := s * 0.5
	var r := s.y * 0.44
	var wide := s.length()
	draw_arc(c, r + wide * 0.5, 0, TAU, 96, INK_SOLID, wide)
	draw_arc(c, r + 6.0, 0, TAU, 96, Color(0.1, 0.12, 0.13), 12.0, true)
	draw_arc(c, r - 10.0, 0, TAU, 96, Color(0, 0, 0, 0.35), 22.0, true)
	var line := Color(0.02, 0.02, 0.02, 0.9)
	draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.12, 0), line, 5.0)
	draw_line(c + Vector2(r * 0.12, 0), c + Vector2(r, 0), line, 5.0)
	draw_line(c + Vector2(0, r * 0.12), c + Vector2(0, r), line, 5.0)
	draw_line(c + Vector2(-r * 0.12, 0), c + Vector2(r * 0.12, 0), line, 1.5)
	draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.12), line, 1.5)
	for i in range(1, 5):
		var d := r * 0.12 * i / 4.0 * 2.0
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
			var at: Vector2 = c + dir * d
			var across: Vector2 = Vector2(dir.y, dir.x) * 5.0
			draw_line(at - across, at + across, line, 1.5)
	draw_circle(c, 2.5, Color(1.0, 0.25, 0.2))
	if player.gun.hit_marker > 0.0:
		var hc := GOLD if player.gun.crit_marker else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 9, c + d * 18, hc, 2.5)


func _draw_crosshair(s: Vector2) -> void:
	var c := s * 0.5
	var gun := player.gun
	var gap := 5.0 if gun.aiming else 10.0 + gun._kick * 40.0
	var col := Color(1, 1, 1, 0.95)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * gap, c + d * (gap + 7), INK_SOLID, 4.0)
		draw_line(c + d * gap, c + d * (gap + 7), col, 2.0)
	draw_circle(c, 2.2, INK_SOLID)
	draw_circle(c, 1.4, col)
	if gun.hit_marker > 0.0:
		var hc := GOLD if gun.crit_marker else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 7, c + d * 15, INK_SOLID, 5.0)
			draw_line(c + d * 7, c + d * 15, hc, 2.5)


## --- Top centre: the room clock and the running time event --------------------------

func _draw_clock(s: Vector2) -> void:
	var arena := player.get_parent() as Arena
	if arena == null or arena.kind != "combat" or arena.done:
		return
	var cx := s.x * 0.5
	var y := 30.0
	_brush(Vector2(cx - 140, y), 280, 56, INK)
	var label := "OVERTIME"
	var col := HP_LOW.lerp(CREAM, 0.5 + 0.5 * sin(_pulse * 9.0))
	if not arena.overtime:
		var t := ceili(arena.par_t)
		label = "%d:%02d" % [t / 60, t % 60]
		col = HP_LOW if arena.par_t < 10.0 else CREAM
	_text(Vector2(cx - 100, y + 39), label, 32, col, HORIZONTAL_ALIGNMENT_CENTER, 200)
	if not arena.overtime:
		_bar(Rect2(cx - 80, y + 52, 160, 7), arena.par_t / arena.par, TIME)
	if arena.event == "":
		return
	var def: Dictionary = Arena.EVENTS[arena.event]
	var ey := y + 76
	_brush(Vector2(cx - 170, ey), 340, 50, INK)
	_text(Vector2(cx - 170, ey + 26), def.name, 24, def.color, HORIZONTAL_ALIGNMENT_CENTER, 340)
	_text(Vector2(cx - 170, ey + 44), def.text, 15, Color(CREAM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 340, 3, 0.0)
	_bar(Rect2(cx - 90, ey + 54, 180, 6), arena.event_t / arena.event_len, def.color)


func _draw_boss(s: Vector2) -> void:
	if _boss == null or _boss.dead:
		return
	var w := minf(720.0, s.x * 0.44)
	var x0 := (s.x - w) * 0.5 + 30.0
	var y := 74.0
	_brush(Vector2(x0 - 30, y - 12), w + 70, 48, INK)
	var frac := _boss.hp / _boss.max_hp
	_bar(Rect2(x0, y, w, 24), frac, BOSS_HP, _boss_shown, BOSS_TRAIL)
	_text(Vector2(x0, y + 19), "%d/%d" % [ceili(_boss.hp), roundi(_boss.max_hp)], 17, CREAM, HORIZONTAL_ALIGNMENT_CENTER, w, 4, 0)
	_text(Vector2(x0, y - 16), _boss.title.to_upper(), 30, Color("ffb347"), HORIZONTAL_ALIGNMENT_CENTER, w, 7)
	# Emblem: a spiked ink badge with a skull.
	var ec := Vector2(x0 - 34, y + 12)
	for i in 10:
		_diamond(ec + Vector2.from_angle(TAU * i / 10.0 - PI * 0.5) * 44, 12, INK_SOLID)
	draw_circle(ec, 46, INK_SOLID)
	draw_circle(ec, 39, Color("3a2b2b"))
	draw_arc(ec, 40, 0, TAU, 48, Color("ffb347"), 3.0, true)
	Icons.paint(self, "skull", ec, 22, CREAM)


## --- Cutscenes ------------------------------------------------------------------------

## Boss intro: letterbox bars, then the era, the boss's name and one line.
func _draw_boss_intro(s: Vector2) -> void:
	var p := cine_p
	var bars := clampf(minf(p / 0.1, (1.0 - p) / 0.08), 0.0, 1.0) * 110.0
	draw_rect(Rect2(0, 0, s.x, bars), INK_SOLID)
	draw_rect(Rect2(0, s.y - bars, s.x, bars), INK_SOLID)
	var a := clampf(minf((p - 0.3) / 0.12, (1.0 - p) / 0.1), 0.0, 1.0)
	var x := 110.0 - (1.0 - a) * 50.0
	_text(Vector2(x, s.y - 268), String(cine.era).to_upper(), 26, Color(GOLD, a))
	_text(Vector2(x, s.y - 186), String(cine.name).to_upper(), 76, Color("ffb347", a), HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	_text(Vector2(x, s.y - 140), cine.line, 28, Color(CREAM, a))
	_skip_hint(s, clampf(bars / 110.0, 0.0, 1.0))


func _skip_hint(s: Vector2, a: float) -> void:
	_text(Vector2(0, s.y - 44), "SPACE  skip", 20, Color(CREAM, 0.5 * a), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 60, 4)
