class_name Device
extends Node3D
## Puzzle pieces wired by channel. Triggers (plates, runes, braziers) power a channel; a
## channel is ON while every trigger on it is active. Gates on that channel (and the exit, if
## the room names it) open while it is ON. The host decides; everyone renders.
##
##   PLATE    held down by anyone standing on it, or by a prop resting on it
##   RUNE_F   lit by LEON's forward shot (amber crystal)
##   RUNE_R   lit by NOEL's recall (cyan crystal)
##   RUNE_P   needs both in one cycle: a pincer (white crystal)
##   BRAZIER  NOEL rewinds it to full fire; it burns down going forward
##   GATE     iron portcullis; blocks bodies but not bullets, sight or a thrown gun

enum { PLATE, RUNE_F, RUNE_R, RUNE_P, BRAZIER, GATE }

## Channel colours: kept clear of amber (LEON), cyan (NOEL) and red (enemies).
const CH_COLORS := [Color(0.9, 0.9, 0.9), Color(0.72, 0.42, 1.0), Color(0.35, 1.0, 0.45),
	Color(1.0, 0.45, 0.78), Color(1.0, 0.92, 0.45)]
const RUNE_H := 1.55
const RUNE_RADIUS := 0.5
const BRAZIER_RANGE := 4.0

var id := 0
var kind := PLATE
var channel := 1
## RUNE_*: seconds it stays lit (0 = for good). BRAZIER: seconds of fuel.
var hold := 0.0
var tile := Vector2i.ZERO
## GATE: true when the bars run along X (walls to the east and west).
var along_x := true
var room_height := 6.0

## Trigger: active. Gate: open.
var on := false
## Host time when an active trigger switches off (0 = never).
var until := 0.0
## RUNE_P: hit by a forward shot this cycle.
var primed := false

var _body: StaticBody3D
var _mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _crystal: MeshInstance3D
var _light: OmniLight3D
var _bars: Node3D
var _slab: Node3D
var _flame: MeshInstance3D
var _coals: MeshInstance3D
var _embers: GPUParticles3D
var _fire_light: OmniLight3D


func ch_color() -> Color:
	return CH_COLORS[channel % CH_COLORS.size()]


func is_trigger() -> bool:
	return kind != GATE


func is_rune() -> bool:
	return kind in [RUNE_F, RUNE_R, RUNE_P]


func active(now: float) -> bool:
	return on and (until <= 0.0 or now < until)


func rune_center() -> Vector3:
	return global_position + Vector3(0, RUNE_H, 0)


func _ready() -> void:
	match kind:
		PLATE: _build_plate()
		GATE: _build_gate()
		BRAZIER: _build_brazier()
		_: _build_rune()
	_refresh()


func _ring(radius: float, y: float, mat: Material, thick := 0.035) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thick
	tm.outer_radius = radius
	tm.rings = 32
	mi.mesh = tm
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_plate() -> void:
	_slab = Node3D.new()
	add_child(_slab)
	var s := Util.box(Vector3(1.1, 0.08, 1.1), Mats.trim())
	s.position.y = 0.04
	_slab.add_child(s)
	_ring_mat = Util.glow(ch_color(), 1.5)
	for i in 4:
		var e := Util.box(Vector3(1.14, 0.03, 0.05), _ring_mat)
		var a := i * PI * 0.5
		e.position = Vector3(sin(a) * 0.57, 0.07, cos(a) * 0.57)
		e.rotation.y = a
		_slab.add_child(e)
	var glyph := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.4, 0.4, 0.01)
	glyph.mesh = pm
	glyph.material_override = _ring_mat
	glyph.rotation.x = -PI * 0.5
	glyph.position.y = 0.085
	_slab.add_child(glyph)
	var frame := Util.box(Vector3(1.3, 0.02, 1.3), Mats.iron())
	frame.position.y = 0.01
	add_child(frame)


func _build_gate() -> void:
	_body = StaticBody3D.new()
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(Util.TILE, 3.2, 0.25) if along_x else Vector3(0.25, 3.2, Util.TILE)
	cs.shape = bs
	cs.position.y = 1.6
	_body.add_child(cs)
	add_child(_body)
	_bars = Node3D.new()
	add_child(_bars)
	var n := 9
	for i in n:
		var off := (i - (n - 1) * 0.5) * (Util.TILE / n)
		var bar := Util.cylinder(0.03, 3.2, Mats.iron(), 6)
		bar.position = Vector3(off, 1.6, 0) if along_x else Vector3(0, 1.6, off)
		_bars.add_child(bar)
		var tip := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.045
		cm.height = 0.14
		tip.mesh = cm
		tip.material_override = Mats.iron()
		tip.position = bar.position + Vector3(0, -1.64, 0)
		tip.rotation.x = PI
		_bars.add_child(tip)
	for y in [0.5, 1.7, 2.9]:
		var cross := Util.box(Vector3(Util.TILE, 0.06, 0.06) if along_x else Vector3(0.06, 0.06, Util.TILE), Mats.iron())
		cross.position.y = y
		_bars.add_child(cross)
	# A channel lamp in the lintel above.
	_ring_mat = Util.glow(ch_color(), 2.0)
	var lamp := Util.box(Vector3(0.28, 0.28, 0.06) if along_x else Vector3(0.06, 0.28, 0.28), _ring_mat)
	lamp.rotation = Vector3(0, 0, PI * 0.25) if along_x else Vector3(PI * 0.25, 0, 0)
	for s in [-1.0, 1.0]:
		var l := lamp.duplicate() as MeshInstance3D
		var face := Util.TILE * 0.5 + 0.04
		l.position = Vector3(0, 4.25, face * s) if along_x else Vector3(face * s, 4.25, 0)
		add_child(l)


func _build_rune() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Util.L_WORLD
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 0.75, 0.5)
	cs.shape = bs
	cs.position.y = 0.375
	_body.add_child(cs)
	add_child(_body)
	var base := Util.box(Vector3(0.7, 0.16, 0.7), Mats.trim())
	base.position.y = 0.08
	add_child(base)
	var col := Util.cylinder(0.17, 0.6, Mats.trim(), 8)
	(col.mesh as CylinderMesh).top_radius = 0.24
	col.position.y = 0.45
	add_child(col)
	var cup := Util.cylinder(0.3, 0.06, Mats.iron(), 12)
	cup.position.y = 0.77
	add_child(cup)
	var c := Util.AMBER if kind == RUNE_F else (Util.CYAN if kind == RUNE_R else Color.WHITE)
	_mat = Util.glow(c, 1.0)
	_crystal = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 4
	sm.rings = 2
	sm.radius = 0.5
	sm.height = 1.0
	_crystal.mesh = sm
	_crystal.material_override = _mat
	_crystal.scale = Vector3(0.36, 0.6, 0.36)
	_crystal.position.y = RUNE_H
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crystal)
	if kind == RUNE_P:
		# Half amber, half cyan shell around a white core.
		for i in 2:
			var half := Util.box(Vector3(0.05, 0.5, 0.05), Util.glow(Util.AMBER if i == 0 else Util.CYAN, 3.0))
			half.position = Vector3(-0.3 if i == 0 else 0.3, RUNE_H, 0)
			add_child(half)
	_ring_mat = Util.glow(ch_color(), 2.0)
	var r1 := _ring(0.42, RUNE_H, _ring_mat, 0.025)
	r1.rotation.x = PI * 0.5
	var r2 := _ring(0.42, RUNE_H, _ring_mat, 0.025)
	r2.rotation.z = PI * 0.5
	r1.set_meta("spin", 1.0)
	r2.set_meta("spin", -1.3)
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.omni_range = 4.0
	_light.position.y = RUNE_H
	_light.shadow_enabled = false
	add_child(_light)


func _build_brazier() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Util.L_WORLD
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.8, 1.15, 0.8)
	cs.shape = bs
	cs.position.y = 0.575
	_body.add_child(cs)
	add_child(_body)
	var parts := Mats.brazier(true)
	add_child(parts[0])
	_flame = parts[1]
	_fire_light = parts[2]
	_coals = parts[3]
	for c in (parts[0] as Node3D).get_children():
		if c is GPUParticles3D:
			_embers = c
	_fire_light.remove_from_group("flicker")
	_ring_mat = Util.glow(ch_color(), 2.0)
	_ring(0.5, 0.03, _ring_mat, 0.05).rotation = Vector3.ZERO
	var base := Util.cylinder(0.52, 0.04, Mats.trim(), 16)
	base.position.y = 0.02
	add_child(base)


## Called on every PC when the host broadcasts a change.
func set_state(is_on: bool, until_t: float) -> void:
	var was := on
	on = is_on
	until = until_t
	if kind == GATE and was != on:
		_body.collision_layer = 0 if on else Util.L_GATE
		var tw := create_tween()
		tw.tween_property(_bars, "position:y", 3.1 if on else 0.0, 0.7 if on else 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if on else Tween.EASE_IN)
		Game.sfx("door", false, global_position + Vector3(0, 1.5, 0), -4.0, 0.7 if on else 0.9)
	elif is_trigger() and was != on:
		if on:
			var c := Util.AMBER if kind == RUNE_F else (Util.CYAN if kind in [RUNE_R, BRAZIER] else ch_color())
			Fx.burst(get_parent(), global_position + Vector3(0, RUNE_H if is_rune() else 1.2, 0), c, 14, 2.5, 0.05, 0.4,
				kind == RUNE_R or kind == BRAZIER)
			Game.sfx("ping", kind == RUNE_R or kind == BRAZIER, global_position, -2.0, 0.7)
	_refresh()


func set_primed(p: bool) -> void:
	primed = p
	_refresh()


func _refresh() -> void:
	if kind == GATE:
		if _body and not on:
			_body.collision_layer = Util.L_GATE
		_ring_mat.albedo_color = ch_color() * (3.0 if on else 0.8)
		return
	if kind == PLATE:
		_slab.position.y = -0.04 if on else 0.0
		_ring_mat.albedo_color = ch_color() * (3.5 if on else 0.9)
		return


func _process(delta: float) -> void:
	var now := Net.now()
	var act := active(now)
	if is_rune():
		var base := Util.AMBER if kind == RUNE_F else (Util.CYAN if kind == RUNE_R else Color.WHITE)
		var left := 1.0
		if act and until > 0.0 and hold > 0.0:
			left = clampf((until - now) / hold, 0.0, 1.0)
		var e := 0.6
		if act:
			e = 2.0 + 3.0 * left + (sin(now * 20.0) * 1.5 if left < 0.3 else 0.0)
		elif primed:
			e = 2.5 + sin(now * 12.0)
			base = Util.AMBER
		_mat.albedo_color = base * e
		_light.light_energy = (1.5 + 2.0 * left) if act else (0.8 if primed else 0.15)
		_light.light_color = base
		_ring_mat.albedo_color = ch_color() * (3.0 if act else 0.8)
		_crystal.rotation.y += delta * (2.5 if act else 0.6)
		_crystal.position.y = RUNE_H + sin(now * 1.7 + id) * 0.05
		for c in get_children():
			if c.has_meta("spin"):
				(c as Node3D).rotate_y(delta * float(c.get_meta("spin")) * (2.0 if act else 0.4))
	elif kind == BRAZIER:
		var fuel := 0.0
		if act:
			fuel = 1.0 if until <= 0.0 else clampf((until - now) / maxf(hold, 0.01), 0.0, 1.0)
		_flame.visible = fuel > 0.0
		_flame.set_instance_shader_parameter("fuel", fuel)
		var flick := 1.0 + sin(now * 13.0 + id) * 0.08 + sin(now * 7.3) * 0.06
		_fire_light.light_energy = (0.4 + 3.4 * fuel) * flick if fuel > 0.0 else 0.0
		_fire_light.visible = fuel > 0.0
		(_coals.material_override as StandardMaterial3D).emission_energy_multiplier = 0.3 + 2.4 * fuel
		_embers.emitting = fuel > 0.15
		_ring_mat.albedo_color = ch_color() * (3.0 if act else 0.7)


## The plate's footprint on the floor (host checks bodies inside it).
func plate_has(p: Vector3) -> bool:
	var d := p - global_position
	return absf(d.x) < 0.7 and absf(d.z) < 0.7 and d.y > -0.3 and d.y < 0.9
