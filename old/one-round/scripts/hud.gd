class_name Hud
extends CanvasLayer
## In-game HUD, kept quiet: crosshair with key-cap prompts under it, small room, time, par and
## wave readout top-left, partner top-right, the team chain bottom-left, the revolver's cylinder
## bottom-right, world markers and short toasts. Esc opens a menu (controls, settings, restart,
## leave); the game keeps running.

const PING_LIFE := 4.0
const CHAIN_POP := 0.3
const CHAIN_BREAK := 1.2

var world: World

var _overlay: Overlay
var _toast := ""
var _toast_col := Color.WHITE
var _toast_t := 0.0
var _pings: Array = []
var _killflash := 0.0
var _lootflash := 0.0
var _chain_pop := 0.0
var _chain_break := 0.0
var _chain_lost := 0
var _menu: Control


func _ready() -> void:
	layer = 2
	_overlay = Overlay.new()
	_overlay.hud = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_build_menu()


func on_room_loaded() -> void:
	_pings.clear()
	_toast_t = 0.0
	_chain_pop = 0.0
	_chain_break = 0.0


func on_role_changed() -> void:
	pass


func loot_flash() -> void:
	_lootflash = 0.4


func enemy_killed() -> void:
	_killflash = 0.25


func chain_changed(old: int, value: int) -> void:
	if value > old:
		_chain_pop = CHAIN_POP
		_chain_break = 0.0
	else:
		_chain_break = CHAIN_BREAK
		_chain_lost = old


func toast(msg: String, color := Color.WHITE) -> void:
	_toast = msg.to_upper()
	_toast_col = color
	_toast_t = 2.6


func add_ping(role: String, pos: Vector3, enemy_id: int) -> void:
	_pings.append({"role": role, "pos": pos, "enemy": enemy_id, "t": PING_LIFE})


func _process(delta: float) -> void:
	_toast_t -= delta
	_killflash = maxf(_killflash - delta, 0.0)
	_lootflash = maxf(_lootflash - delta, 0.0)
	_chain_pop = maxf(_chain_pop - delta, 0.0)
	_chain_break = maxf(_chain_break - delta, 0.0)
	for p: Dictionary in _pings:
		p.t -= delta
	_pings = _pings.filter(func(p: Dictionary) -> bool: return p.t > 0.0)
	var show_menu := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and world != null and world.room != null
	if show_menu != _menu.visible:
		_menu.visible = show_menu
		if show_menu:
			Ui.appear(_menu, 0.0, Vector2.ZERO, 0.15)
	_overlay.queue_redraw()


## What the local player can do right now: pairs of [key, verb] shown under the crosshair.
func prompt() -> Array:
	var lp := world.local_player()
	if lp == null or world.room == null or not lp.alive:
		return []
	var rv := world.revolver
	var me := lp.role
	if rv.holder == me:
		if me == Util.A:
			match rv.bullet:
				Revolver.IN_GUN: return [["LMB", "FIRE"], ["RMB", "THROW"]]
				Revolver.LODGED: return [["RMB", "THROW TO NOEL"]]
				_: return []
		match rv.bullet:
			Revolver.LODGED: return [["LMB", "RECALL"], ["RMB", "THROW"]]
			Revolver.IN_GUN: return [["RMB", "THROW TO LEON"]]
			_: return []
	if world.held_prop(me) != null:
		return [["LMB", "THROW"], ["E", "DROP"]]
	if me == Util.B:
		var a := world.get_player(Util.A)
		if a.echo and lp.global_position.distance_to(a.global_position) < Player.REVIVE_RANGE:
			return [["HOLD E", "REVIVE LEON"]]
		if world.find_enemy_bullet(lp.eye(), lp.aim_dir(), Player.REVERSE_RANGE):
			return [["E", "REVERSE"]]
		if world.find_brazier(lp.eye(), lp.aim_dir()):
			return [["E", "REWIND FIRE"]]
		if world.find_prop(lp.eye(), lp.aim_dir(), Player.UNTHROW_RANGE):
			return [["E", "UN-THROW"]]
		var g := _aimed_glass(lp, Player.UNTHROW_RANGE, Util.L_WORLD | Util.L_GHOST | Util.L_GLASS)
		if g and not g.intact and g.restorable():
			return [["E", "RESTORE"]]
		return []
	if world.find_prop(lp.eye(), lp.aim_dir(), 3.5):
		return [["E", "GRAB"]]
	var gl := _aimed_glass(lp, Player.PUNCH_RANGE, Util.L_WORLD | Util.L_GLASS)
	if gl and gl.intact:
		return [["LMB", "SMASH"]]
	return []


func _aimed_glass(lp: Player, reach: float, mask: int) -> Glass:
	var q := PhysicsRayQueryParameters3D.create(lp.eye(), lp.eye() + lp.aim_dir() * reach, mask)
	var hit := lp.get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Glass:
		return hit.collider
	return null


# --- Esc menu -----------------------------------------------------------------------

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.visible = false
	add_child(_menu)
	var dim := Ui.rect(Color(Ui.INK, 0.78))
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	center.add_child(col)
	var title := Ui.label("ONE ROUND", 34, Ui.TEXT, Ui.DISPLAY, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var resume := Ui.button("RESUME", Ui.TEXT, true, 15)
	resume.pressed.connect(func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	row.add_child(resume)
	var restart := Ui.button("RESTART ROOM", Ui.TEXT, false, 15)
	restart.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if world:
			world.request_restart.rpc_id(1))
	row.add_child(restart)
	var leave := Ui.button("LEAVE", Util.RED, false, 15)
	leave.pressed.connect(func() -> void: Game.quit_to_title())
	row.add_child(leave)
	var panels := HBoxContainer.new()
	panels.add_theme_constant_override("separation", 16)
	col.add_child(panels)
	panels.add_child(Panels.controls())
	panels.add_child(Panels.settings())
	var note := Ui.label("THE GAME KEEPS RUNNING  ·  CLICK ANYWHERE TO RESUME", 12, Ui.FAINT, Ui.LABEL)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)


class Overlay extends Control:
	var hud: Hud

	func _draw() -> void:
		var world := hud.world
		if world == null or world.room == null:
			return
		var lp := world.local_player()
		if lp == null:
			return
		var vs := size
		var c := vs * 0.5
		var accent := Util.role_color(lp.role)

		if not lp.alive and lp.echo:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.09, 0.11, 0.5))
			_text(Ui.font(Ui.DISPLAY, 10), "ECHO", Vector2(c.x, c.y - 10), 54, Util.AMBER, true)
			_text(Ui.font(Ui.LABEL, 2), "NOEL CAN BRING YOU BACK", Vector2(c.x, c.y + 26), 14, Ui.MUTED, true)

		_markers(world, lp)
		if lp.alive:
			_crosshair(lp, c, accent)
		_room_info(world)
		_waves_info(world)
		_partner(world, lp)
		_revolver(world, lp)
		_chain(world)
		_slow(world)
		_toast(c)
		if Game.solo:
			var w := Ui.draw_key(self, Vector2(c.x - 70, vs.y - 32), "TAB", Ui.MUTED, 13)
			_text(Ui.font(Ui.LABEL, 2), "SWAP AGENT", Vector2(c.x - 70 + w + 10, vs.y - 27), 12, Ui.MUTED)

	func _text(f: Font, s: String, pos: Vector2, sz: int, col: Color, centered := false, right := false) -> void:
		var x := pos.x
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if centered:
			x -= w * 0.5
		elif right:
			x -= w
		draw_string_outline(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.45))
		draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	func _crosshair(lp: Player, c: Vector2, accent: Color) -> void:
		draw_circle(c, 2.2, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.5, Color.WHITE)
		var gap := 7.0
		for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + 6.0), Color(accent, 0.85), 1.5)
		if hud._killflash > 0.0:
			var k := hud._killflash / 0.25
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 7.0, c + d * (7.0 + 8.0 * k), Color(Util.RED, k), 2.0)
		# Cooldowns as thin arcs around the crosshair, only while recharging.
		var cds := [["reverse", Player.REVERSE_COOLDOWN], ["pull", Player.PULL_COOLDOWN]] if lp.role == Util.B \
			else [["punch", Player.PUNCH_COOLDOWN]]
		cds.append(["dash", Player.DASH_COOLDOWN])
		var r := 20.0
		for cd: Array in cds:
			var f := lp.cooldown_frac(cd[0], cd[1])
			if f < 1.0:
				draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
				draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, 48, Color(accent, 0.8), 2.0)
			r += 6.0
		if lp.revive_progress > 0.0:
			draw_arc(c, 34, -PI * 0.5, -PI * 0.5 + TAU * lp.revive_progress / Player.REVIVE_TIME, 64, Util.CYAN, 3.0)
		# Key-cap prompts.
		var items := hud.prompt()
		if items.is_empty():
			return
		var lf := Ui.font(Ui.LABEL, 2)
		var widths := []
		var total := 0.0
		for it: Array in items:
			var kw := maxf(Ui.font(Ui.NUMBER, 1).get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0, 23.0)
			var tw := lf.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			widths.append([kw, tw])
			total += kw + 8.0 + tw
		total += 24.0 * (items.size() - 1)
		var x := c.x - total * 0.5
		var y := c.y + 58.0
		for i in items.size():
			var it: Array = items[i]
			Ui.draw_key(self, Vector2(x, y), it[0], Color(1, 1, 1, 0.9), 13)
			x += widths[i][0] + 8.0
			_text(lf, it[1], Vector2(x, y + 5), 13, Color(1, 1, 1, 0.85))
			x += widths[i][1] + 24.0

	func _room_info(world: World) -> void:
		var data: Dictionary = Rooms.ALL[world.room_index]
		var df := Ui.font(Ui.DISPLAY, 3)
		_text(df, "%s  ·  %s" % [data.floor, data.name], Vector2(40, 50), 17, Ui.TEXT)
		var nf := Ui.font(Ui.NUMBER, 1)
		var lf := Ui.font(Ui.LABEL, 2)
		_text(nf, Ui.fmt_time(world.room_time), Vector2(40, 80), 22, Ui.TEXT)
		var x := 130.0
		var left := world.room.alive_enemies()
		_text(nf, str(left), Vector2(x, 80), 22, Util.RED if left > 0 else Ui.MUTED)
		_text(lf, "LEFT", Vector2(x + 8 + nf.get_string_size(str(left), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, 78), 11, Ui.MUTED)
		x += 70.0
		var lc := Color(1.0, 0.78, 0.35).lerp(Color.WHITE, hud._lootflash / 0.4)
		var d := Vector2(x + 5, 73)
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -6), d + Vector2(5, 0), d + Vector2(0, 6), d + Vector2(-5, 0)]), lc)
		_text(nf, str(world.room_loot), Vector2(x + 16, 80), 22, lc)

	## Par under the timer (amber once beaten, red once missed), then the wave or lift state.
	func _waves_info(world: World) -> void:
		var lf := Ui.font(Ui.LABEL, 2)
		var par: float = Rooms.ALL[world.room_index].par
		var pc := Ui.MUTED
		if world.par_beaten:
			pc = Util.AMBER
		elif world.door_open or world.room_time > par:
			pc = Util.RED
		_text(lf, "PAR " + Ui.fmt_time(par), Vector2(40, 104), 11, pc)
		_text(lf, world.waves.status(), Vector2(130, 104), 12, Util.RED if world.waves.in_final() else Ui.TEXT)

	func _partner(world: World, lp: Player) -> void:
		if Game.solo:
			return
		var partner := world.get_player(Util.other(lp.role))
		var col := Util.role_color(partner.role)
		var x := size.x - 40.0
		_text(Ui.font(Ui.DISPLAY, 4), Util.role_name(partner.role), Vector2(x - 18, 50), 17, col, false, true)
		var dot := Color(0.35, 0.95, 0.55) if partner.alive else (Util.CYAN if partner.echo else Util.RED)
		draw_circle(Vector2(x - 4, 44), 4.0, dot)
		var status := "" if partner.alive else ("ECHO" if partner.echo else "DOWN")
		if status != "":
			_text(Ui.font(Ui.LABEL, 2), status, Vector2(x, 72), 12, dot, false, true)

	func _revolver(world: World, lp: Player) -> void:
		var rv := world.revolver
		var cc := Vector2(size.x - 70, size.y - 70)
		var hold_col := Util.role_color(rv.holder) if rv.holder != "" else Color(0.7, 0.7, 0.72)
		draw_circle(cc, 30, Color(0, 0, 0, 0.45))
		draw_arc(cc, 30, 0, TAU, 48, Color(hold_col, 0.9), 1.5)
		for i in 6:
			var a := -PI * 0.5 + TAU * i / 6.0
			var p := cc + Vector2(cos(a), sin(a)) * 17.0
			if i == 0:
				match rv.bullet:
					Revolver.IN_GUN:
						draw_circle(p, 7, Util.WHITE_HOT)
					Revolver.FLYING:
						draw_circle(p, 6, Color(1, 1, 1, 0.3 + 0.3 * sin(Time.get_ticks_msec() / 50.0)))
					_:
						draw_arc(p, 6, 0, TAU, 16, Util.RED, 1.5)
			else:
				draw_arc(p, 6, 0, TAU, 16, Color(1, 1, 1, 0.22), 1.2)
		var who := "LOOSE"
		if rv.holder == lp.role:
			who = "YOURS"
		elif rv.holder != "":
			who = Util.role_name(rv.holder)
		var state := "LOADED"
		if rv.bullet == Revolver.FLYING:
			state = "IN FLIGHT"
		elif rv.bullet == Revolver.LODGED:
			state = "LODGED  %dM" % int(lp.eye().distance_to(rv.lodged_pos))
		var x := cc.x - 46
		_text(Ui.font(Ui.LABEL, 3), who, Vector2(x, cc.y - 4), 15, hold_col, false, true)
		_text(Ui.font(Ui.LABEL, 2), state, Vector2(x, cc.y + 16), 12, Ui.MUTED, false, true)

	## Bottom-left: the chain, its decay bar and what the next shot and recall get from it.
	func _chain(world: World) -> void:
		var ch := world.chain
		var broken := hud._chain_break / CHAIN_BREAK
		if ch.count == 0 and broken <= 0.0:
			return
		var nf := Ui.font(Ui.NUMBER, 1)
		var lf := Ui.font(Ui.LABEL, 2)
		var p := Vector2(40, size.y - 74)
		var num := "×%d" % (ch.count if ch.count > 0 else hud._chain_lost)
		var sz := int(40.0 + 10.0 * hud._chain_pop / CHAIN_POP)
		var col := Ui.TEXT.lerp(Util.RED, broken)
		if ch.count == 0:
			col.a = broken
		_text(nf, num, p, sz, col)
		var w := nf.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		_text(lf, "BROKEN" if broken > 0.0 else "CHAIN", p + Vector2(w + 10, -4), 12, Color(col, col.a * 0.7))
		if ch.count == 0:
			return
		var left := clampf(1.0 - ch.idle / Chain.DECAY, 0.0, 1.0)
		draw_rect(Rect2(p + Vector2(0, 10), Vector2(150, 2)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(p + Vector2(0, 10), Vector2(150 * left, 2)), Ui.TEXT if left > 0.25 else Util.RED)
		var x := p.x
		for recall: bool in [false, true]:
			var perk := Chain.perk(ch.count, recall)
			if perk == "":
				continue
			var tag := ("RECALL  " if recall else "SHOT  ") + perk
			_text(lf, tag, Vector2(x, p.y + 32), 11, Util.CYAN if recall else Util.AMBER)
			x += lf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0

	func _slow(world: World) -> void:
		var slow := world.slow_until - Net.now()
		if slow <= 0.0:
			return
		var col := Color(1.0, 0.8, 0.35)
		var w := 220.0
		var p := Vector2(size.x * 0.5 - w * 0.5, 44)
		_text(Ui.font(Ui.LABEL, 3), "TIME SLOWED", Vector2(size.x * 0.5, p.y), 12, col, true)
		draw_rect(Rect2(p + Vector2(0, 8), Vector2(w, 2)), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(p + Vector2(0, 8), Vector2(w * clampf(slow / 6.0, 0.0, 1.0), 2)), col)

	func _toast(c: Vector2) -> void:
		if hud._toast_t <= 0.0:
			return
		var a := clampf(hud._toast_t * 3.0, 0.0, 1.0)
		var f := Ui.font(Ui.LABEL, 2)
		var w := f.get_string_size(hud._toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var r := Rect2(c.x - w * 0.5 - 20, size.y * 0.22 - 18, w + 40, 34)
		draw_rect(r, Color(Ui.PANEL, 0.85 * a))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(hud._toast_col, a))
		draw_string(f, Vector2(r.position.x + 22, r.position.y + 22), hud._toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Ui.TEXT, a))

	## A marker in world space; clamps to the screen edge with an arrow when off-screen.
	func _marker(cam: Camera3D, pos: Vector3, col: Color, label: String, dist: float) -> void:
		var lf := Ui.font(Ui.LABEL, 2)
		var local := cam.global_transform.affine_inverse() * pos
		var behind := local.z > -0.05
		var sp := Vector2(local.x, -local.y) * 1000.0 + size * 0.5 if behind else cam.unproject_position(pos)
		var m := 46.0
		var inside := not behind and sp.x > m and sp.x < size.x - m and sp.y > m and sp.y < size.y - m
		if inside:
			var pts := PackedVector2Array([sp + Vector2(0, -7), sp + Vector2(6, 0), sp + Vector2(0, 7), sp + Vector2(-6, 0)])
			draw_colored_polygon(pts, Color(col, 0.95))
			_text(lf, "%s  %d" % [label, int(dist)], sp + Vector2(0, -14), 11, Color(col, col.a), true)
			return
		var c := size * 0.5
		var d := sp - c
		if d.length() < 0.01:
			d = Vector2.DOWN
		d = d.normalized()
		var half := c - Vector2(m, m)
		var s := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
		var p := c + d * s
		var perp := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([p + d * 10, p - d * 5 + perp * 7, p - d * 5 - perp * 7]), col)
		_text(lf, label, p - d * 22 + Vector2(0, 4), 11, col, true)

	func _markers(world: World, lp: Player) -> void:
		var cam := lp.cam
		var rv := world.revolver
		if rv.bullet == Revolver.LODGED:
			_marker(cam, rv.lodged_pos, Util.WHITE_HOT, "ROUND", lp.eye().distance_to(rv.lodged_pos))
		if rv.holder == "":
			var gp := rv.body.global_position + Vector3(0, 0.4, 0)
			_marker(cam, gp, Util.AMBER if rv.is_loaded() else Util.CYAN, "GUN", lp.eye().distance_to(gp))
		var partner := world.get_player(Util.other(lp.role))
		var pp := partner.global_position + Vector3(0, 2.0, 0)
		var pl := cam.global_transform.affine_inverse() * pp
		if not Game.solo and (pl.z > -0.05 or not get_viewport_rect().has_point(cam.unproject_position(pp))):
			_marker(cam, pp, Util.role_color(partner.role), Util.role_name(partner.role), lp.eye().distance_to(pp))
		for p: Dictionary in hud._pings:
			var pos: Vector3 = p.pos
			var eid: int = p.enemy
			if eid >= 0 and eid < world.room.enemies.size() and world.room.enemies[eid].alive:
				pos = world.room.enemies[eid].global_position + Vector3(0, 2.2, 0)
			var label := "ENEMY" if eid >= 0 else "HERE"
			var col := Util.role_color(p.role)
			col.a = clampf(p.t, 0.0, 1.0)
			_marker(cam, pos, col, label, lp.eye().distance_to(pos))
