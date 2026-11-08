class_name Glass
extends StaticBody3D
## Anything LEON can break and NOEL can put back. Intact: solid. Broken: only a ghost stays,
## which NOEL's un-break ray can hit. Kinds:
##   WARD     a leaded crystal pane (blocks people and enemy rounds, never the revolver round)
##   BRIDGE   a plank bridge over a chasm, one object per connected span
##   CRUMBLE  a cracked flagstone over a chasm: collapses a moment after someone steps on it
##   POT      a loot urn: LEON smashes it and coins spill out (cannot be restored)
##   RELIC    starts shattered: NOEL restores it and a gem drops (once)
## Rim colour shows who can act on it: amber (LEON can break it), cyan (NOEL can restore it).

enum { WARD, BRIDGE, CRUMBLE, POT, RELIC }

const HEIGHT := 3.0

var id := 0
var kind := WARD
var vertical := true
var tile := Vector2i.ZERO
var tiles: Array[Vector2i] = []
## BRIDGE: footprint in metres (x, z).
var span := Vector2(Util.TILE, Util.TILE)
var room: Room
var intact := true
var rewarded := false

var _pane: Node3D
var _pane_mat: StandardMaterial3D
var _rim_mat: StandardMaterial3D
var _ghost: Node3D
var _pieces: Array[Node3D] = []
var _cs: CollisionShape3D
var _warn_tw: Tween


func _ready() -> void:
	collision_layer = Util.L_GLASS
	collision_mask = 0
	if tiles.is_empty():
		tiles.append(tile)
	_cs = CollisionShape3D.new()
	add_child(_cs)
	_rim_mat = Util.glow(Util.AMBER, 2.0, 0.8)
	match kind:
		WARD: _build_ward()
		BRIDGE: _build_bridge()
		CRUMBLE: _build_crumble()
		POT: _build_pot()
		RELIC: _build_relic()


func _shape(size: Vector3, y: float) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	_cs.shape = bs
	_cs.position.y = y


func _outline(sx: float, sz: float, y: float, mat: Material) -> Node3D:
	var n := Node3D.new()
	for s in [-1.0, 1.0]:
		var a := Util.box(Vector3(sx, 0.03, 0.05), mat)
		a.position = Vector3(0, y, sz * 0.5 * s)
		n.add_child(a)
		var b := Util.box(Vector3(0.05, 0.03, sz), mat)
		b.position = Vector3(sx * 0.5 * s, y, 0)
		n.add_child(b)
	add_child(n)
	return n


func _build_ward() -> void:
	var size := Vector3(0.1, HEIGHT, Util.TILE) if vertical else Vector3(Util.TILE, HEIGHT, 0.1)
	_shape(size, HEIGHT * 0.5)
	_pane = Node3D.new()
	add_child(_pane)
	_pane_mat = Util.mat(Color(1.0, 0.75, 0.4), 0.25, 0.22, 0.03, 0.2)
	var pane := Util.box(size - Vector3(0.06, 0, 0.06 if vertical else 0) * 0.0, _pane_mat)
	pane.position.y = HEIGHT * 0.5
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pane.add_child(pane)
	# Lead came: a diamond lattice across the pane.
	var lead := Util.mat(Color(0.08, 0.07, 0.07), 0.0, 1.0, 0.5, 0.7)
	var along := Vector3(0, 0, 1) if vertical else Vector3(1, 0, 0)
	for i in 6:
		var bar := Util.box(Vector3(0.11, 0.025, 0.11) + along * (Util.TILE * 1.4 - 0.11), lead)
		bar.position.y = 0.3 + i * 0.5
		bar.rotation = Vector3(0.6, 0, 0) if vertical else Vector3(0, 0, 0.6)
		bar.scale = Vector3(1, 1, 0.75) if vertical else Vector3(0.75, 1, 1)
		_pane.add_child(bar)
		var bar2 := bar.duplicate() as MeshInstance3D
		bar2.rotation = -bar.rotation
		_pane.add_child(bar2)
	for y in [0.03, HEIGHT - 0.03]:
		var rim := Util.box(Vector3(0.14, 0.06, 0.14) + along * (Util.TILE - 0.14), _rim_mat)
		rim.position.y = y
		add_child(rim)
	for s in [-1.0, 1.0]:
		var post := Util.box(Vector3(0.16, HEIGHT, 0.16), Mats.iron())
		post.position = along * s * (Util.TILE * 0.5 - 0.08) + Vector3(0, HEIGHT * 0.5, 0)
		add_child(post)
		var strip := Util.box(Vector3(0.17, HEIGHT - 0.4, 0.04 if vertical else 0.17), _rim_mat)
		strip.position = post.position
		if not vertical:
			strip.scale = Vector3(1, 1, 0.25)
		add_child(strip)


func _build_bridge() -> void:
	_shape(Vector3(span.x, 0.3, span.y), -0.15)
	var along_x := span.x >= span.y
	var length := span.x if along_x else span.y
	var width := span.y if along_x else span.x
	var n := int(length / 0.32)
	for i in n:
		var plank := Util.box(Vector3(0.28, 0.08, width - 0.1) if along_x else Vector3(width - 0.1, 0.08, 0.28), Mats.wood())
		var off := (i - (n - 1) * 0.5) * (length / n)
		plank.position = Vector3(off, -0.05, 0) if along_x else Vector3(0, -0.05, off)
		plank.rotation.y = randf_range(-0.04, 0.04)
		add_child(plank)
		_pieces.append(plank)
	for s in [-1.0, 1.0]:
		var beam := Util.box(Vector3(length, 0.16, 0.14) if along_x else Vector3(0.14, 0.16, length), Mats.dark_wood())
		beam.position = Vector3(0, -0.16, s * (width * 0.5 - 0.1)) if along_x else Vector3(s * (width * 0.5 - 0.1), -0.16, 0)
		add_child(beam)
		_pieces.append(beam)
		var rope := Util.cylinder(0.02, length, Util.mat(Color(0.45, 0.36, 0.24), 0.0, 1.0, 0.95), 5)
		rope.rotation = Vector3(0, 0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0, 0)
		rope.position = Vector3(0, 0.9, s * (width * 0.5 - 0.06)) if along_x else Vector3(s * (width * 0.5 - 0.06), 0.9, 0)
		add_child(rope)
		_pieces.append(rope)
		var trim := Util.box(Vector3(length, 0.03, 0.03) if along_x else Vector3(0.03, 0.03, length), _rim_mat)
		trim.position = beam.position + Vector3(0, 0.1, 0)
		add_child(trim)
		_pieces.append(trim)
	for e in [-1.0, 1.0]:
		for s in [-1.0, 1.0]:
			var post := Util.box(Vector3(0.12, 1.1, 0.12), Mats.dark_wood())
			post.position = Vector3(e * length * 0.5, 0.45, s * (width * 0.5 - 0.06)) if along_x \
				else Vector3(s * (width * 0.5 - 0.06), 0.45, e * length * 0.5)
			add_child(post)
	_ghost = _outline(span.x - 0.1, span.y - 0.1, 0.0, Util.glow(Util.CYAN, 2.0, 0.5))
	_ghost.visible = false


func _build_crumble() -> void:
	_shape(Vector3(Util.TILE, 0.4, Util.TILE), -0.2)
	var slab := Util.box(Vector3(Util.TILE - 0.04, 0.4, Util.TILE - 0.04), Mats.floor_stone())
	slab.position.y = -0.2
	add_child(slab)
	_pieces.append(slab)
	var crack_mat := Util.glow(Color(0.9, 0.5, 0.2), 0.9)
	for i in 3:
		var c := Util.box(Vector3(Util.TILE * randf_range(0.4, 0.8), 0.005, 0.025), crack_mat)
		c.position = Vector3(randf_range(-0.3, 0.3), 0.003, randf_range(-0.4, 0.4))
		c.rotation.y = randf() * PI
		add_child(c)
		_pieces.append(c)
	_rim_mat.albedo_color = Color(Util.AMBER * 1.2, 0.6)
	_ghost = _outline(Util.TILE - 0.1, Util.TILE - 0.1, 0.0, Util.glow(Util.CYAN, 2.0, 0.5))
	_ghost.visible = false


func _build_pot() -> void:
	_shape(Vector3(0.6, 0.9, 0.6), 0.45)
	_pane = Node3D.new()
	add_child(_pane)
	var body := Util.sphere(0.3, Mats.clay())
	body.scale = Vector3(1, 1.15, 1)
	body.position.y = 0.38
	_pane.add_child(body)
	var neck := Util.cylinder(0.13, 0.22, Mats.clay(), 12)
	(neck.mesh as CylinderMesh).top_radius = 0.17
	neck.position.y = 0.76
	_pane.add_child(neck)
	var band := Util.cylinder(0.305, 0.05, Mats.gold(), 16)
	band.position.y = 0.42
	_pane.add_child(band)
	var foot := Util.cylinder(0.16, 0.08, Mats.clay(), 12)
	foot.position.y = 0.04
	_pane.add_child(foot)
	_pane.rotation.y = randf() * TAU


func _build_relic() -> void:
	_shape(Vector3(0.8, 1.4, 0.8), 0.7)
	var ped := Util.box(Vector3(0.8, 0.7, 0.8), Mats.trim())
	ped.position.y = 0.35
	add_child(ped)
	_pane = Node3D.new()
	_pane.position.y = 0.7
	add_child(_pane)
	var gm := Util.mat(Color(1.0, 0.75, 0.3), 0.8, 1.0, 0.2, 1.0)
	for s in [-1.0, 1.0]:
		var bulb := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22 if s > 0 else 0.02
		cm.bottom_radius = 0.02 if s > 0 else 0.22
		cm.height = 0.3
		bulb.mesh = cm
		bulb.material_override = gm
		bulb.position.y = 0.33 + 0.15 * s
		_pane.add_child(bulb)
		var cap := Util.cylinder(0.26, 0.04, Mats.gold(), 14)
		cap.position.y = 0.33 + 0.32 * s
		_pane.add_child(cap)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 1.5
	l.omni_range = 4.0
	l.position.y = 0.4
	_pane.add_child(l)
	# Shards lying around the pedestal while it is broken.
	_ghost = Node3D.new()
	add_child(_ghost)
	for i in 7:
		var sh := Util.box(Vector3(randf_range(0.08, 0.18), 0.05, randf_range(0.06, 0.14)), gm)
		sh.position = Vector3(randf_range(-0.3, 0.3), 0.73, randf_range(-0.3, 0.3))
		sh.rotation = Vector3(randf(), randf() * TAU, randf())
		_ghost.add_child(sh)
	var shimmer := Util.cylinder(0.42, 0.01, Util.glow(Util.CYAN, 1.5, 0.4), 20)
	shimmer.position.y = 0.71
	_ghost.add_child(shimmer)


func center() -> Vector3:
	match kind:
		WARD: return global_position + Vector3(0, 1.4, 0)
		POT: return global_position + Vector3(0, 0.45, 0)
		RELIC: return global_position + Vector3(0, 0.9, 0)
	return global_position + Vector3(0, 0.1, 0)


## Thrown things (props, the gun) only shatter panes and pots, never bridges or floors.
func fragile() -> bool:
	return kind == WARD or kind == POT


func restorable() -> bool:
	return kind != POT


## Does this block a tile (for enemy pathing) in the given state?
func solid_when(is_intact: bool) -> bool:
	return is_intact if kind in [WARD, POT, RELIC] else not is_intact


## Shake and glow before a crumbling floor gives way.
func warn() -> void:
	if not intact:
		return
	if _warn_tw and _warn_tw.is_valid():
		return
	_warn_tw = create_tween()
	for i in 8:
		_warn_tw.tween_property(self, "position:y", -0.03 if i % 2 == 0 else 0.0, 0.05)
	Fx.burst(get_parent(), global_position + Vector3(0, 0.05, 0), Color(0.6, 0.5, 0.4), 8, 1.0, 0.05, 0.4, false)
	Game.sfx("lodge", false, global_position, -6.0, 0.5)


func set_intact(on: bool, actor: String, with_fx := true) -> void:
	if on == intact:
		return
	intact = on
	if on:
		collision_layer = Util.L_GLASS
	else:
		collision_layer = 0 if kind == POT else Util.L_GHOST
	if room:
		for t in tiles:
			room.set_glass_solid(t, solid_when(on))
	var reversed := actor == Util.B
	match kind:
		WARD:
			_pane.visible = on
			_rim_mat.albedo_color = Color(Util.AMBER * 2.0 if on else Util.CYAN * 2.0, 0.8 if on else 0.35)
		BRIDGE, CRUMBLE:
			_ghost.visible = not on
			_animate_pieces(on, with_fx)
			position.y = 0.0
		POT:
			_pane.visible = on
		RELIC:
			_pane.visible = on
			_ghost.visible = not on
	if not with_fx:
		return
	var spread := Vector3.ONE
	var col := Color(1.0, 0.8, 0.5)
	match kind:
		WARD:
			spread = Vector3(1, 1, 0.3) if not vertical else Vector3(0.3, 1, 1)
		BRIDGE:
			col = Color(0.5, 0.32, 0.18)
		CRUMBLE:
			col = Color(0.4, 0.37, 0.33)
		POT:
			col = Color(0.55, 0.3, 0.18)
		RELIC:
			col = Color(1.0, 0.75, 0.3)
	if on:
		col = Util.CYAN
	Fx.burst(get_parent(), center(), col, 26, 3.0, 0.1, 0.6, on, spread)
	Game.sfx("glass", reversed, center(), 0.0, 0.6 if kind in [BRIDGE, CRUMBLE] else 1.0)


## Planks and slabs drop into the chasm; restoring plays it backwards.
func _animate_pieces(on: bool, with_fx: bool) -> void:
	for p in _pieces:
		if not p.has_meta("rest"):
			p.set_meta("rest", p.transform)
		var rest: Transform3D = p.get_meta("rest")
		var fallen := rest
		fallen.origin += Vector3(randf_range(-0.4, 0.4), -6.0 - randf() * 3.0, randf_range(-0.4, 0.4))
		fallen.basis = Basis.from_euler(Vector3(randf() * 2.0, randf() * 2.0, randf() * 2.0)) * rest.basis
		if not with_fx:
			p.transform = rest if on else fallen
			p.visible = on
			continue
		p.visible = true
		var tw := p.create_tween()
		if on:
			p.transform = fallen
			tw.tween_property(p, "transform", rest, 0.5 + randf() * 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(p, "transform", fallen, 0.9 + randf() * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void: p.visible = intact)
