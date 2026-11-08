class_name Room
extends Node3D
## Builds one dungeon room from an ASCII map (see Rooms) on every PC.
## Gameplay objects (props, breakables, devices, hazards) are created in scan order, so they
## get the same ids everywhere. Enemies arrive later in waves (see Waves) and take the next id
## on every PC. Decoration uses a seeded RNG for the same reason.

const PIT_DEPTH := 14.0
## Tiles with no solid floor under them (bridges and crumbling floor bring their own).
const HOLES := "_bzk"
## Wave spawn markers (plain floor otherwise).
const SPAWNS := "!?$%&"
## Clear height under a crawlway (n).
const CRAWL_GAP := 1.0

var data: Dictionary
var w := 0
var h := 0
var height := 6.0
var rows: Array = []
var starts := {}
var gun_start := Vector3.ZERO
var enemies: Array[Enemy] = []
var props: Array[Prop] = []
var glass: Array[Glass] = []
var devices: Array[Device] = []
var hazards: Array[Hazard] = []
## Spawn marker character -> floor position.
var spawns := {}
var astar := AStarGrid2D.new()
var lift_rect := Rect2()
var exit_channel := 0
var accent := Color(0.3, 1.0, 0.7)

var _rng := RandomNumberGenerator.new()
var _door_body: StaticBody3D
var _door_l: Node3D
var _door_r: Node3D
var _portal_mat: ShaderMaterial
var _pad_mat: StandardMaterial3D
var _portal_light: OmniLight3D
var _lines := {}
var _flicker: Array[OmniLight3D] = []
var _torch_count := 0
var _candle_lights := 0


static func tile_pos(c: int, r: int) -> Vector3:
	return Vector3(c * Util.TILE, 0.0, r * Util.TILE)


func tile_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi(p.x / Util.TILE), 0, w - 1), clampi(roundi(p.z / Util.TILE), 0, h - 1))


func at(c: int, r: int) -> String:
	if c < 0 or r < 0 or c >= w or r >= h:
		return "#"
	return String(rows[r])[c]


func _key(ch: String) -> Array:
	var keys: Dictionary = data.get("keys", {})
	return keys.get(ch, [])


func _is_wall(c: int, r: int) -> bool:
	var ch := at(c, r)
	return ch == "#" or ch == "D"


func _is_hole(c: int, r: int) -> bool:
	return HOLES.contains(at(c, r)) and _key(at(c, r)).is_empty()


## Floor you can see and stand on (not wall, not hole).
func _is_floor(c: int, r: int) -> bool:
	return not _is_wall(c, r) and not _is_hole(c, r)


func build(room_data: Dictionary) -> void:
	data = room_data
	rows = data.map
	h = rows.size()
	w = String(rows[0]).length()
	height = data.get("height", 6.0)
	exit_channel = data.get("exit", 0)
	accent = data.get("accent", accent)
	_rng.seed = hash(String(data.name))
	var t := Util.TILE

	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

	_build_shell()
	var prop_n := 0
	var seen_spans := {}
	for r in h:
		var row: String = rows[r]
		for c in row.length():
			var ch := row[c]
			var p := tile_pos(c, r)
			var cell := Vector2i(c, r)
			var key := _key(ch)
			if not key.is_empty():
				_device(String(key[0]), key, cell)
				continue
			if ch >= "1" and ch <= "9":
				_gate(int(ch), cell)
				continue
			if SPAWNS.contains(ch):
				spawns[ch] = p
				continue
			match ch:
				"#", "D":
					astar.set_point_solid(cell)
				"_":
					astar.set_point_solid(cell)
				"O":
					_pillar(p)
					astar.set_point_solid(cell)
				"c":
					_crates(p)
					astar.set_point_solid(cell)
				"r":
					_barrels(p)
					astar.set_point_solid(cell)
				"t":
					_table(p)
					astar.set_point_solid(cell)
				"S":
					_statue(p, r)
					astar.set_point_solid(cell)
				"i":
					_decor_brazier(p)
					astar.set_point_solid(cell)
				"L":
					_chandelier(p)
				"n":
					_crawlway(p)
					astar.set_point_solid(cell)
				"o":
					pass  # skylight: handled by the ceiling
				"|", "-":
					var g := _new_glass(Glass.WARD, cell)
					g.vertical = ch == "|"
					add_child(g)
					astar.set_point_solid(cell)
				"u", "U":
					var g := _new_glass(Glass.POT if ch == "u" else Glass.RELIC, cell)
					if ch == "U":
						g.set_meta("start_broken", true)
					add_child(g)
					astar.set_point_solid(cell, ch == "u")
				"b", "z":
					if not seen_spans.has(cell):
						_bridge(cell, seen_spans, ch == "z")
				"k":
					var g := _new_glass(Glass.CRUMBLE, cell)
					add_child(g)
				"s", "f", "h", "v":
					var hz := Hazard.new()
					hz.id = hazards.size()
					hz.kind = {"s": Hazard.SPIKES, "f": Hazard.FIRE, "h": Hazard.BLADE_X, "v": Hazard.BLADE_Z}[ch]
					hz.phase = (c + r) * 0.33 if ch == "s" else float(hazards.size()) * 0.9
					hz.room_height = height
					hz.position = p
					hazards.append(hz)
					add_child(hz)
					astar.set_point_weight_scale(cell, 10.0)
				"p":
					var pr := Prop.new()
					pr.id = props.size()
					pr.kind = prop_n % 3
					prop_n += 1
					pr.position = p + Vector3(0, 0.5, 0)
					props.append(pr)
					add_child(pr)
				"A", "B":
					starts[ch] = p
				"G":
					gun_start = p
	# Broken bridges and crumbled floors start broken (after ids are fixed).
	for g in glass:
		if g.has_meta("start_broken"):
			g.set_intact(false, "", false)
	_build_lift()
	_dress()
	_build_lines()
	apply_quality()


## Called in the same order on every PC (by the wave spawn RPC), so ids match.
func add_enemy(kind: int, pos: Vector3, yaw: float) -> Enemy:
	var e := Enemy.new()
	e.id = enemies.size()
	e.kind = kind
	e.fire_interval = data.fire_interval
	e.room = self
	e.position = pos
	e.home_yaw = yaw
	enemies.append(e)
	add_child(e)
	return e


func _new_glass(kind: int, cell: Vector2i) -> Glass:
	var g := Glass.new()
	g.id = glass.size()
	g.kind = kind
	g.tile = cell
	g.position = tile_pos(cell.x, cell.y)
	g.room = self
	glass.append(g)
	return g


## A bridge is one object per connected span of b / z tiles.
func _bridge(start: Vector2i, seen: Dictionary, broken: bool) -> void:
	var ch := at(start.x, start.y)
	var span: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		span.append(c)
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not seen.has(n) and at(n.x, n.y) == ch:
				seen[n] = true
				stack.append(n)
	var lo := span[0]
	var hi := span[0]
	for c in span:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var g := _new_glass(Glass.BRIDGE, lo)
	g.tiles = span
	g.span = Vector2((hi.x - lo.x + 1) * Util.TILE, (hi.y - lo.y + 1) * Util.TILE)
	g.position = (tile_pos(lo.x, lo.y) + tile_pos(hi.x, hi.y)) * 0.5
	if broken:
		g.set_meta("start_broken", true)
	add_child(g)
	for c in span:
		astar.set_point_solid(c, broken)


func _device(kind_name: String, key: Array, cell: Vector2i) -> void:
	var d := Device.new()
	d.id = devices.size()
	d.kind = {"plate": Device.PLATE, "rune_f": Device.RUNE_F, "rune_r": Device.RUNE_R,
		"rune_p": Device.RUNE_P, "brazier": Device.BRAZIER}[kind_name]
	d.channel = int(key[1])
	d.hold = float(key[2]) if key.size() > 2 else 0.0
	d.tile = cell
	d.room_height = height
	d.position = tile_pos(cell.x, cell.y)
	devices.append(d)
	add_child(d)
	if d.kind != Device.PLATE:
		astar.set_point_solid(cell)


func _gate(ch: int, cell: Vector2i) -> void:
	var d := Device.new()
	d.id = devices.size()
	d.kind = Device.GATE
	d.channel = ch
	d.tile = cell
	d.room_height = height
	d.along_x = _is_wall(cell.x - 1, cell.y) or _is_wall(cell.x + 1, cell.y)
	d.position = tile_pos(cell.x, cell.y)
	devices.append(d)
	add_child(d)
	astar.set_point_solid(cell)


func set_glass_solid(tile: Vector2i, solid: bool) -> void:
	astar.set_point_solid(tile, solid)


func set_gate_solid(d: Device) -> void:
	astar.set_point_solid(d.tile, not d.on)


# --- Shell: floor, walls, pits, water, ceiling -----------------------------------

func _slab(center: Vector3, size: Vector3, mat: Material, layer := Util.L_WORLD) -> StaticBody3D:
	var b := Util.solid(size, mat, layer)
	b.position = center
	add_child(b)
	return b


func _mesh(mi: MeshInstance3D, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


## Calls f(r, c0, c1) for every horizontal run of tiles where pred(c, r) holds.
func _runs(pred: Callable, f: Callable) -> void:
	for r in h:
		var c := 0
		while c < w:
			if not pred.call(c, r):
				c += 1
				continue
			var c0 := c
			while c < w and pred.call(c, r):
				c += 1
			f.call(r, c0, c - 1)


func _run_center(r: int, c0: int, c1: int, y: float) -> Vector3:
	return Vector3((c0 + c1) * 0.5 * Util.TILE, y, r * Util.TILE)


func _build_shell() -> void:
	var t := Util.TILE
	# Floor.
	_runs(func(c: int, r: int) -> bool: return not _is_hole(c, r) and at(c, r) != "w",
		func(r: int, c0: int, c1: int) -> void:
			_slab(_run_center(r, c0, c1, -0.25), Vector3((c1 - c0 + 1) * t, 0.5, t), Mats.floor_stone()))
	# Water: an invisible floor at 0 with a glowing surface just below it.
	_runs(func(c: int, r: int) -> bool: return at(c, r) == "w",
		func(r: int, c0: int, c1: int) -> void:
			var n := c1 - c0 + 1
			_slab(_run_center(r, c0, c1, -0.25), Vector3(n * t, 0.5, t), null)
			var surf := Util.box(Vector3(n * t, 0.02, t), Mats.water(accent))
			surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mesh(surf, _run_center(r, c0, c1, -0.07))
			for i in range(0, n, 4):
				var l := OmniLight3D.new()
				l.light_color = accent
				l.light_energy = 0.7
				l.omni_range = 4.5
				l.position = tile_pos(c0 + i, r) + Vector3(0, 0.4, 0)
				add_child(l))
	# Walls: merged runs, full height.
	_runs(func(c: int, r: int) -> bool: return at(c, r) == "#",
		func(r: int, c0: int, c1: int) -> void:
			_slab(_run_center(r, c0, c1, height * 0.5), Vector3((c1 - c0 + 1) * t, height, t), Mats.wall()))
	# Chasms: lined shafts with mist and a faint glow far below.
	var pit_glow := Util.mat(accent * 0.3, 0.6, 1.0, 1.0)
	_runs(func(c: int, r: int) -> bool: return _is_hole(c, r) or HOLES.contains(at(c, r)),
		func(r: int, c0: int, c1: int) -> void:
			var n := c1 - c0 + 1
			_mesh(Util.box(Vector3(n * t, 0.2, t), pit_glow), _run_center(r, c0, c1, -PIT_DEPTH))
			var fog := FogVolume.new()
			fog.size = Vector3(n * t, 7.0, t)
			fog.position = _run_center(r, c0, c1, -5.0)
			var fm := FogMaterial.new()
			fm.density = 0.5
			fm.albedo = Color(0.15, 0.15, 0.17)
			fm.emission = accent * 0.04
			fog.material = fm
			add_child(fog)
			if n >= 2:
				var l := OmniLight3D.new()
				l.light_color = accent
				l.light_energy = 1.2
				l.omni_range = 9.0
				l.position = _run_center(r, c0, c1, -5.0)
				add_child(l))
	for r in h:
		for c in w:
			if not HOLES.contains(at(c, r)) or not _key(at(c, r)).is_empty():
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(c, r) + d
				if HOLES.contains(at(n.x, n.y)) and _key(at(n.x, n.y)).is_empty():
					continue
				var dv := Vector3(d.x, 0, d.y)
				var size := Vector3(0.3, PIT_DEPTH, t) if d.x != 0 else Vector3(t, PIT_DEPTH, 0.3)
				_slab(tile_pos(c, r) + dv * (t * 0.5 - 0.15) + Vector3(0, -PIT_DEPTH * 0.5, 0), size, Mats.pit_wall())
				# A worn lip along the edge.
				var lip := Util.box(Vector3(0.18, 0.12, t) if d.x != 0 else Vector3(t, 0.12, 0.18), Mats.trim())
				_mesh(lip, tile_pos(c, r) + dv * (t * 0.5 + 0.06) + Vector3(0, 0.02, 0))
	# Ceiling, with holes for skylights.
	_runs(func(c: int, r: int) -> bool: return at(c, r) != "o",
		func(r: int, c0: int, c1: int) -> void:
			_slab(_run_center(r, c0, c1, height + 0.25), Vector3((c1 - c0 + 1) * t, 0.5, t), Mats.ceiling()))
	# Beams across the hall.
	for r in range(2, h - 1, 3):
		var beam := Util.box(Vector3((w - 2) * t, 0.36, 0.3), Mats.dark_wood())
		_mesh(beam, Vector3((w - 1) * t * 0.5, height - 0.18, r * t))
	for c in w:
		for r in h:
			if at(c, r) == "o":
				_skylight(tile_pos(c, r))


func _skylight(p: Vector3) -> void:
	var t := Util.TILE
	for s in [-1.0, 1.0]:
		_mesh(Util.box(Vector3(t, 3.0, 0.2), Mats.wall()), p + Vector3(0, height + 1.5, s * (t * 0.5 + 0.1)))
		_mesh(Util.box(Vector3(0.2, 3.0, t), Mats.wall()), p + Vector3(s * (t * 0.5 + 0.1), height + 1.5, 0))
	_mesh(Util.box(Vector3(t, 0.1, t), Util.mat(Mats.MOON, 1.2, 1.0, 1.0)), p + Vector3(0, height + 3.05, 0))
	for i in 5:
		var bar := Util.box(Vector3(0.05, 0.05, t), Mats.iron())
		_mesh(bar, p + Vector3((i - 2) * 0.3, height + 0.05, 0))
		var bar2 := Util.box(Vector3(t, 0.05, 0.05), Mats.iron())
		_mesh(bar2, p + Vector3(0, height + 0.05, (i - 2) * 0.3))
	var spot := SpotLight3D.new()
	spot.light_color = Mats.MOON
	spot.light_energy = 6.0
	spot.spot_range = height + 6.0
	spot.spot_angle = 24.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 3.0
	spot.position = p + Vector3(0.6, height + 2.8, 0.3)
	spot.rotation = Vector3(-PI * 0.5 + 0.12, 0, 0.1)
	spot.add_to_group("key_light")
	spot.set_meta("shadows", true)
	add_child(spot)


# --- Set pieces --------------------------------------------------------------------

func _pillar(p: Vector3) -> void:
	var t := Util.TILE
	var b := Util.solid(Vector3(t * 0.75, height, t * 0.75), null, Util.L_WORLD)
	b.position = p + Vector3(0, height * 0.5, 0)
	add_child(b)
	_mesh(Util.box(Vector3(t * 0.82, 0.45, t * 0.82), Mats.trim()), p + Vector3(0, 0.225, 0))
	_mesh(Util.box(Vector3(t * 0.7, 0.15, t * 0.7), Mats.trim()), p + Vector3(0, 0.52, 0))
	var shaft := Util.cylinder(0.42, height - 1.2, Mats.wall(), 16)
	_mesh(shaft, p + Vector3(0, 0.6 + (height - 1.2) * 0.5, 0))
	_mesh(Util.box(Vector3(t * 0.7, 0.2, t * 0.7), Mats.trim()), p + Vector3(0, height - 0.5, 0))
	_mesh(Util.box(Vector3(t * 0.85, 0.35, t * 0.85), Mats.trim()), p + Vector3(0, height - 0.22, 0))
	if _rng.randf() < 0.55:
		var to_center := Util.flat(Vector3((w - 1) * t * 0.5, 0, (h - 1) * t * 0.5) - p)
		var d := Vector3(signf(to_center.x), 0, 0) if absf(to_center.x) > absf(to_center.z) else Vector3(0, 0, signf(to_center.z))
		_torch_at(p + d * 0.44 + Vector3(0, 2.6, 0), d)


func _crates(p: Vector3) -> void:
	var t := Util.TILE
	var b := Util.solid(Vector3(t * 0.9, 2.1, t * 0.9), null, Util.L_WORLD)
	b.position = p + Vector3(0, 1.05, 0)
	add_child(b)
	var sizes := [1.15, 0.9]
	var y := 0.0
	for i in 2:
		var s: float = sizes[i]
		var crate := Node3D.new()
		crate.position = p + Vector3(_rng.randf_range(-0.06, 0.06), y + s * 0.5, _rng.randf_range(-0.06, 0.06))
		crate.rotation.y = _rng.randf_range(-0.2, 0.2)
		add_child(crate)
		crate.add_child(Util.box(Vector3(s, s, s), Mats.wood()))
		for e in 4:
			var a := e * PI * 0.5
			var edge := Util.box(Vector3(0.06, s + 0.01, 0.06), Mats.iron())
			edge.position = Vector3(cos(a) + sin(a), 0, cos(a) - sin(a)) * (s * 0.5 - 0.02)
			crate.add_child(edge)
		y += s


func _barrels(p: Vector3) -> void:
	var b := Util.solid(Vector3(Util.TILE * 0.85, 1.6, Util.TILE * 0.85), null, Util.L_WORLD)
	b.position = p + Vector3(0, 0.8, 0)
	add_child(b)
	var spots := [Vector3(-0.3, 0, -0.25), Vector3(0.32, 0, -0.1), Vector3(-0.05, 0, 0.32)]
	for i in 3:
		_barrel(p + spots[i], 0.0)
	if _rng.randf() < 0.6:
		_barrel(p + Vector3(0.05, 0.8, 0.0), 0.0)


func _barrel(at_pos: Vector3, tilt: float) -> void:
	var n := Node3D.new()
	n.position = at_pos
	n.rotation = Vector3(tilt, _rng.randf() * TAU, 0)
	add_child(n)
	var body := Util.cylinder(0.29, 0.8, Mats.wood(), 14)
	(body.mesh as CylinderMesh).rings = 2
	body.position.y = 0.4
	body.scale = Vector3(1.05, 1, 1.05)
	n.add_child(body)
	for y in [0.12, 0.68]:
		var band := Util.cylinder(0.31, 0.05, Mats.iron(), 14)
		band.position.y = y
		n.add_child(band)
	var top := Util.cylinder(0.27, 0.02, Mats.dark_wood(), 14)
	top.position.y = 0.8
	n.add_child(top)


func _table(p: Vector3) -> void:
	var b := Util.solid(Vector3(1.4, 0.9, 0.85), null, Util.L_WORLD)
	b.position = p + Vector3(0, 0.45, 0)
	add_child(b)
	_mesh(Util.box(Vector3(1.4, 0.08, 0.85), Mats.wood()), p + Vector3(0, 0.84, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(Util.box(Vector3(0.08, 0.8, 0.08), Mats.dark_wood()), p + Vector3(sx * 0.6, 0.4, sz * 0.34))
	var c := Mats.candles(_rng, 3, _candle_lights < 10)
	_candle_lights += 1
	c.position = p + Vector3(-0.35, 0.88, 0.1)
	add_child(c)
	var book := Util.box(Vector3(0.3, 0.06, 0.22), Util.mat(Color(0.3, 0.08, 0.06), 0.0, 1.0, 0.8))
	_mesh(book, p + Vector3(0.3, 0.91, -0.05), Vector3(0, 0.3, 0))
	var goblet := Util.cylinder(0.05, 0.16, Mats.gold(), 10)
	_mesh(goblet, p + Vector3(0.05, 0.96, 0.2))
	var skull := Util.sphere(0.09, Mats.bone())
	_mesh(skull, p + Vector3(0.45, 0.96, 0.2))


func _statue(p: Vector3, r: int) -> void:
	var b := Util.solid(Vector3(Util.TILE * 0.8, 3.2, Util.TILE * 0.8), null, Util.L_WORLD)
	b.position = p + Vector3(0, 1.6, 0)
	add_child(b)
	_mesh(Util.box(Vector3(1.15, 0.9, 1.15), Mats.trim()), p + Vector3(0, 0.45, 0))
	_mesh(Util.box(Vector3(1.25, 0.12, 1.25), Mats.trim()), p + Vector3(0, 0.96, 0))
	var s := Humanoid.new(Humanoid.Style.STATUE)
	s.position = p + Vector3(0, 1.02, 0)
	s.scale = Vector3.ONE * 1.25
	s.rotation.y = 0.0 if r > h * 0.5 else PI
	add_child(s)
	s.pose(Vector3(PI * 0.75, 0, -0.5), Vector3(PI * 0.75, 0, 0.5))
	# Hands clasp a stone sword pointing down.
	var sword := Util.box(Vector3(0.06, 1.3, 0.12), Mats.marble())
	sword.position = Vector3(0, 0.55, -0.42)
	s.add_child(sword)
	var guard := Util.box(Vector3(0.4, 0.06, 0.1), Mats.marble())
	guard.position = Vector3(0, 1.15, -0.42)
	s.add_child(guard)
	var c := Mats.candles(_rng, 5, _candle_lights < 10)
	_candle_lights += 1
	c.position = p + Vector3(0.0, 0.0, 0.8 if r < h * 0.5 else -0.8)
	add_child(c)


## A wall bricked up to a low gap at the floor: only a slide or a crouch gets through.
func _crawlway(p: Vector3) -> void:
	var t := Util.TILE
	_slab(p + Vector3(0, (CRAWL_GAP + height) * 0.5, 0), Vector3(t, height - CRAWL_GAP, t), Mats.wall())
	_mesh(Util.box(Vector3(t + 0.1, 0.2, t + 0.1), Mats.trim()), p + Vector3(0, CRAWL_GAP + 0.1, 0))


func _decor_brazier(p: Vector3) -> void:
	var b := Util.solid(Vector3(0.8, 1.15, 0.8), null, Util.L_WORLD)
	b.position = p + Vector3(0, 0.575, 0)
	add_child(b)
	var parts := Mats.brazier(true)
	(parts[0] as Node3D).position = p
	add_child(parts[0])


func _chandelier(p: Vector3) -> void:
	var y := height - 1.8
	var root := Node3D.new()
	root.position = p + Vector3(0, y, 0)
	add_child(root)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.72
	tm.outer_radius = 0.8
	tm.rings = 32
	ring.mesh = tm
	ring.material_override = Mats.iron()
	root.add_child(ring)
	var inner := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 0.32
	tm2.outer_radius = 0.37
	inner.mesh = tm2
	inner.material_override = Mats.iron()
	inner.position.y = 0.25
	root.add_child(inner)
	for i in 4:
		var a := TAU * i / 4.0
		var chain := Util.cylinder(0.012, 1.9, Mats.iron(), 4)
		chain.position = Vector3(cos(a) * 0.4, 0.95, sin(a) * 0.4)
		chain.rotation = Vector3(sin(a) * 0.2, 0, -cos(a) * 0.2)
		root.add_child(chain)
	for i in 10:
		var a := TAU * i / 10.0
		var cup := Util.cylinder(0.04, 0.03, Mats.iron(), 6)
		cup.position = Vector3(cos(a) * 0.76, 0.03, sin(a) * 0.76)
		root.add_child(cup)
		var candle := Util.cylinder(0.025, 0.18, Mats.wax(), 6)
		candle.position = cup.position + Vector3(0, 0.1, 0)
		root.add_child(candle)
		var f := Mats.flame(0.1, Mats.CANDLE, 2.6)
		f.position = cup.position + Vector3(0, 0.19, 0)
		root.add_child(f)
	var l := Mats.fire_light(3.6, 15.0, true, true)
	l.light_color = Mats.CANDLE
	l.position.y = -0.1
	root.add_child(l)


# --- Exit -------------------------------------------------------------------

func _build_lift() -> void:
	var cols: Array[int] = []
	for c in w:
		if at(c, h - 1) == "D":
			cols.append(c)
	if cols.is_empty():
		return
	var t := Util.TILE
	var c0: int = cols.min()
	var c1: int = cols.max()
	var r := h - 1
	var x0 := c0 * t - t * 0.5
	var x1 := c1 * t + t * 0.5
	var width := x1 - x0
	var cx := (x0 + x1) * 0.5
	var door_h := 3.4
	# Alcove floor, walls, back wall and ceiling.
	_slab(Vector3(cx, -0.25, (r + 1) * t), Vector3(width + 2 * t, 0.5, 3 * t), Mats.floor_stone())
	for side in [c0 - 1, c1 + 1]:
		_slab(tile_pos(side, r + 1) + Vector3(0, height * 0.5, t * 0.5), Vector3(t, height, 2 * t), Mats.wall())
	_slab(Vector3(cx, height * 0.5, (r + 3) * t), Vector3(width + 2 * t, height, t), Mats.wall())
	_slab(Vector3(cx, height + 0.25, (r + 1.5) * t), Vector3(width + 2 * t, 0.5, 3 * t), Mats.ceiling())
	_slab(Vector3(cx, (door_h + height) * 0.5, r * t), Vector3(width, height - door_h, t), Mats.wall())
	# Carved frame.
	for s in [-1.0, 1.0]:
		_mesh(Util.box(Vector3(0.4, door_h + 0.4, 0.3), Mats.trim()), Vector3(cx + s * (width * 0.5 + 0.1), (door_h + 0.4) * 0.5, r * t - t * 0.5 - 0.05))
		_torch_at(Vector3(cx + s * (width * 0.5 + 0.7), 2.5, r * t - t * 0.5), Vector3(0, 0, -1), true)
	_mesh(Util.box(Vector3(width + 1.0, 0.5, 0.3), Mats.trim()), Vector3(cx, door_h + 0.2, r * t - t * 0.5 - 0.05))
	_mesh(Util.box(Vector3(0.5, 0.6, 0.35), Mats.trim()), Vector3(cx, door_h + 0.3, r * t - t * 0.5 - 0.08), Vector3(0, 0, PI * 0.25))

	# Two heavy doors on hinges.
	_door_body = Util.solid(Vector3(width, door_h, 0.25), null, Util.L_WORLD)
	_door_body.position = Vector3(cx, door_h * 0.5, r * t)
	add_child(_door_body)
	_door_l = Node3D.new()
	_door_l.position = Vector3(x0, 0, r * t)
	add_child(_door_l)
	_door_r = Node3D.new()
	_door_r.position = Vector3(x1, 0, r * t)
	add_child(_door_r)
	for i in 2:
		var hinge: Node3D = _door_l if i == 0 else _door_r
		var s := 1.0 if i == 0 else -1.0
		var leaf := Node3D.new()
		leaf.position = Vector3(s * width * 0.25, door_h * 0.5, 0)
		hinge.add_child(leaf)
		leaf.add_child(Util.box(Vector3(width * 0.5 - 0.02, door_h, 0.18), Mats.dark_wood()))
		for y in [-1.1, 0.0, 1.1]:
			var strap := Util.box(Vector3(width * 0.5 - 0.1, 0.12, 0.22), Mats.iron())
			strap.position.y = y
			leaf.add_child(strap)
		var knocker := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.09
		tm.outer_radius = 0.12
		knocker.mesh = tm
		knocker.material_override = Mats.gold()
		knocker.rotation.x = PI * 0.5
		knocker.position = Vector3(-s * (width * 0.25 - 0.3), 0.0, -0.13)
		leaf.add_child(knocker)

	# Behind the doors: the portal on the back wall, and a rune circle on the floor.
	_portal_mat = ShaderMaterial.new()
	_portal_mat.shader = Mats.PORTAL
	var portal := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width + 0.6, width + 0.6)
	portal.mesh = q
	portal.material_override = _portal_mat
	portal.position = Vector3(cx, 2.3, (r + 2.5) * t - 0.02)
	portal.rotation.y = PI
	add_child(portal)
	_portal_light = OmniLight3D.new()
	_portal_light.light_color = Util.RED
	_portal_light.light_energy = 1.2
	_portal_light.omni_range = 7.0
	_portal_light.position = Vector3(cx, 2.0, (r + 1.6) * t)
	add_child(_portal_light)
	_pad_mat = Util.glow(Util.RED, 1.5, 0.6)
	var pad := MeshInstance3D.new()
	var tm3 := TorusMesh.new()
	tm3.inner_radius = 1.3
	tm3.outer_radius = 1.4
	tm3.rings = 48
	pad.mesh = tm3
	pad.material_override = _pad_mat
	pad.position = Vector3(cx, 0.02, (r + 1.5) * t)
	pad.scale = Vector3(1, 0.1, 1)
	add_child(pad)
	var sign := Label3D.new()
	sign.text = "DESCEND"
	sign.font = load("res://assets/fonts/Anton-Regular.ttf")
	sign.font_size = 72
	sign.outline_size = 0
	sign.modulate = Color(1.0, 0.75, 0.35) * 1.2
	sign.position = Vector3(cx, door_h + 0.75, r * t - t * 0.5 - 0.25)
	sign.rotation.y = PI
	add_child(sign)
	lift_rect = Rect2(x0, r * t + 0.3, width, t * 2.2)


func open_door(open: bool) -> void:
	if _door_body == null:
		return
	_door_body.collision_layer = 0 if open else Util.L_WORLD
	var tw := create_tween().set_parallel()
	tw.tween_property(_door_l, "rotation:y", -1.75 if open else 0.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_door_r, "rotation:y", 1.75 if open else 0.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _portal_mat.set_shader_parameter("open", v), 0.0 if open else 1.0, 1.0 if open else 0.0, 1.2)
	_pad_mat.albedo_color = Color(Color(0.3, 1.0, 0.5) * 2.0, 0.7) if open else Color(Util.RED * 1.5, 0.6)
	_portal_light.light_color = Color(0.6, 0.8, 1.0) if open else Util.RED
	_portal_light.light_energy = 4.0 if open else 1.2


func in_lift(p: Vector3) -> bool:
	return lift_rect.has_point(Vector2(p.x, p.z))


# --- Dressing --------------------------------------------------------------------

## Wall faces that look onto floor, grouped into straight runs: [[tiles...], normal].
func _face_runs() -> Array:
	var out := []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var faces := {}
		for r in h:
			for c in w:
				if at(c, r) != "#":
					continue
				var n := Vector2i(c, r) + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				if _is_floor(n.x, n.y):
					faces[Vector2i(c, r)] = true
		var along := Vector2i(1, 0) if d.y != 0 else Vector2i(0, 1)
		var done := {}
		for f: Vector2i in faces:
			if done.has(f) or faces.has(f - along):
				continue
			var run: Array[Vector2i] = []
			var cur := f
			while faces.has(cur):
				run.append(cur)
				done[cur] = true
				cur += along
			out.append([run, d])
	return out


func _torch_at(pos: Vector3, facing: Vector3, force_shadow := false) -> void:
	var tch := Mats.torch(true)
	tch.position = pos
	tch.rotation.y = Util.yaw_of(facing)
	if not force_shadow:
		_torch_count += 1
	add_child(tch)


func _dress() -> void:
	var t := Util.TILE
	for fr: Array in _face_runs():
		var run: Array = fr[0]
		var d: Vector2i = fr[1]
		var dv := Vector3(d.x, 0, d.y)
		var n := run.size()
		# Skirting and cornice along the whole run.
		var a: Vector2i = run[0]
		var b: Vector2i = run[n - 1]
		var mid := (tile_pos(a.x, a.y) + tile_pos(b.x, b.y)) * 0.5 + dv * (t * 0.5)
		var length := n * t
		var along := Vector3(1, 0, 0) if d.y != 0 else Vector3(0, 0, 1)
		var skirt := Util.box(along * length + Vector3(0.24, 0.32, 0.24) - along * 0.24, Mats.trim())
		_mesh(skirt, mid + Vector3(0, 0.16, 0))
		var cornice := Util.box(along * length + Vector3(0.3, 0.3, 0.3) - along * 0.3, Mats.trim())
		_mesh(cornice, mid + Vector3(0, height - 0.6, 0))
		var string_course := Util.box(along * length + Vector3(0.14, 0.12, 0.14) - along * 0.14, Mats.trim())
		_mesh(string_course, mid + Vector3(0, 3.3, 0))
		for i in n:
			var tl: Vector2i = run[i]
			var face := tile_pos(tl.x, tl.y) + dv * (t * 0.5)
			var edge := i == 0 or i == n - 1
			if n >= 3 and i % 4 == 2 and i < n - 1:
				# Pilaster with a torch.
				_mesh(Util.box(Vector3(0.6, height, 0.6) - Vector3(along.x, 0, along.z) * 0.0 - Vector3(dv.x, 0, dv.z).abs() * 0.3, Mats.trim()),
					face + dv * 0.15 + Vector3(0, height * 0.5, 0))
				_torch_at(face + dv * 0.3 + Vector3(0, 2.55, 0), dv)
			elif n >= 3 and i % 4 == 0 and not edge and _rng.randf() < 0.7:
				_banner(face + dv * 0.04, dv)
			elif _rng.randf() < 0.25:
				_wall_clutter(tile_pos(tl.x, tl.y) + Vector3(d.x, 0, d.y) * t, dv)
	_lintels()
	_floor_clutter()
	_dust()


## A stone header over every one-tile gap in a wall, so doorways and gates read as arches.
func _lintels() -> void:
	var t := Util.TILE
	var y0 := 3.4
	for r in h:
		for c in w:
			# Blade doorways stay open to the vault so the pendulum arm has room to swing;
			# crawlways are already walled down to their gap.
			if _is_wall(c, r) or at(c, r) in ["h", "v", "n"]:
				continue
			var ew := _is_wall(c - 1, r) and _is_wall(c + 1, r)
			var ns := _is_wall(c, r - 1) and _is_wall(c, r + 1)
			if ew == ns:
				continue
			var p := tile_pos(c, r)
			_slab(p + Vector3(0, (y0 + height) * 0.5, 0), Vector3(t, height - y0, t), Mats.wall())
			var across := Vector3(0, 0, 1) if ew else Vector3(1, 0, 0)
			for s in [-1.0, 1.0]:
				var arch := Util.box(Vector3(t + 0.3, 0.35, 0.22) if ew else Vector3(0.22, 0.35, t + 0.3), Mats.trim())
				_mesh(arch, p + across * s * (t * 0.5 + 0.05) + Vector3(0, y0 + 0.1, 0))
				var key := Util.box(Vector3(0.36, 0.5, 0.26) if ew else Vector3(0.26, 0.5, 0.36), Mats.trim())
				_mesh(key, p + across * s * (t * 0.5 + 0.06) + Vector3(0, y0 + 0.3, 0))


func _banner(pos: Vector3, facing: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = Util.yaw_of(-facing)
	add_child(root)
	var rod := Util.cylinder(0.025, 1.2, Mats.iron(), 6)
	rod.rotation.z = PI * 0.5
	rod.position = Vector3(0, 4.6, -0.08)
	root.add_child(rod)
	var cloth := Util.box(Vector3(1.0, 2.6, 0.02), Mats.cloth(Color(0.32, 0.03, 0.04)))
	cloth.position = Vector3(0, 3.28, -0.1)
	root.add_child(cloth)
	var tail := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.0, 0.45, 0.02)
	tail.mesh = pm
	tail.material_override = cloth.material_override
	tail.rotation.z = PI
	tail.position = Vector3(0, 1.76, -0.1)
	root.add_child(tail)
	var gold := Util.mat(Color(0.9, 0.65, 0.25), 0.15, 1.0, 0.4, 0.8)
	for s in [-1.0, 1.0]:
		var hem := Util.box(Vector3(0.04, 2.6, 0.025), gold)
		hem.position = Vector3(0.46 * s, 3.28, -0.11)
		root.add_child(hem)
	# The order's sigil: an hourglass.
	for s in [-1.0, 1.0]:
		var tri := MeshInstance3D.new()
		var tp := PrismMesh.new()
		tp.size = Vector3(0.5, 0.42, 0.01)
		tri.mesh = tp
		tri.material_override = gold
		tri.rotation.z = 0.0 if s > 0 else PI
		tri.position = Vector3(0, 3.45 - 0.22 * s, -0.115)
		root.add_child(tri)


func _wall_clutter(floor_pos: Vector3, facing: Vector3) -> void:
	var roll := _rng.randf()
	var p := floor_pos - facing * 0.35
	if roll < 0.35:
		_bones(p)
	elif roll < 0.6:
		_rubble(p)
	elif roll < 0.8 and _candle_lights < 10:
		var c := Mats.candles(_rng, _rng.randi_range(3, 6), true)
		_candle_lights += 1
		c.position = p
		add_child(c)
	else:
		# Chains hanging on the wall.
		for i in 2:
			var ch := Util.cylinder(0.015, 1.4, Mats.iron(), 4)
			ch.position = floor_pos - facing * (Util.TILE * 0.5 - 0.06) + Vector3(0, 3.0, 0) \
				+ Vector3(facing.z, 0, facing.x) * (i - 0.5) * 0.5
			add_child(ch)
			var cuff := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.05
			tm.outer_radius = 0.075
			cuff.mesh = tm
			cuff.material_override = Mats.iron()
			cuff.position = ch.position - Vector3(0, 0.75, 0)
			cuff.rotation.x = PI * 0.5
			add_child(cuff)


func _bones(p: Vector3) -> void:
	for i in _rng.randi_range(3, 6):
		var bone := Util.cylinder(0.02, _rng.randf_range(0.2, 0.42), Mats.bone(), 5)
		bone.position = p + Vector3(_rng.randf_range(-0.3, 0.3), 0.025, _rng.randf_range(-0.3, 0.3))
		bone.rotation = Vector3(PI * 0.5, _rng.randf() * TAU, 0)
		bone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bone)
	if _rng.randf() < 0.7:
		var skull := Util.sphere(0.1, Mats.bone())
		skull.scale = Vector3(0.9, 0.85, 1.1)
		skull.position = p + Vector3(_rng.randf_range(-0.2, 0.2), 0.085, _rng.randf_range(-0.2, 0.2))
		add_child(skull)
		var jaw := Util.box(Vector3(0.1, 0.04, 0.08), Mats.bone())
		jaw.position = skull.position + Vector3(0, -0.07, -0.05)
		add_child(jaw)


func _rubble(p: Vector3) -> void:
	for i in _rng.randi_range(4, 9):
		var s := _rng.randf_range(0.06, 0.22)
		var rock := Util.box(Vector3(s, s * 0.7, s * 1.2), Mats.trim())
		rock.position = p + Vector3(_rng.randf_range(-0.45, 0.45), s * 0.3, _rng.randf_range(-0.45, 0.45))
		rock.rotation = Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())
		add_child(rock)


func _floor_clutter() -> void:
	for r in h:
		for c in w:
			var ch := at(c, r)
			var p := tile_pos(c, r)
			if ch == ",":
				if _rng.randf() < 0.6:
					_bones(p)
				else:
					_rubble(p)
			elif ch == "=":
				pass
	# Carpets: runs of '='.
	_runs(func(c: int, r: int) -> bool: return at(c, r) == "=",
		func(r: int, c0: int, c1: int) -> void:
			var n := c1 - c0 + 1
			var size := Vector3(n * Util.TILE - (0.0 if n > 1 else 0.3), 0.025, Util.TILE * 0.8)
			_mesh(Util.box(size, Mats.cloth(Color(0.36, 0.03, 0.04))), _run_center(r, c0, c1, 0.012))
			for s in [-1.0, 1.0]:
				_mesh(Util.box(Vector3(size.x, 0.03, 0.05), Util.mat(Color(0.8, 0.55, 0.2), 0.1, 1.0, 0.5, 0.6)),
					_run_center(r, c0, c1, 0.014) + Vector3(0, 0, s * Util.TILE * 0.36)))


## Dust motes drifting through the torchlight.
func _dust() -> void:
	var t := Util.TILE
	var p := GPUParticles3D.new()
	p.amount = 500
	p.lifetime = 14.0
	p.preprocess = 14.0
	var size := Vector3(w * t, height, h * t)
	p.position = Vector3((w - 1) * t * 0.5, height * 0.5, (h - 1) * t * 0.5)
	p.visibility_aabb = AABB(-size * 0.5, size)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.gravity = Vector3(0, -0.01, 0)
	pm.direction = Vector3(1, 0.2, 0.4)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.3
	pm.turbulence_noise_speed_random = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.85, 0.75, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.15, 0.1)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


# --- Channel wiring ------------------------------------------------------------------

## Glowing lines along the floor from each trigger to what it powers.
func _build_lines() -> void:
	for d in devices:
		if not d.is_trigger():
			continue
		var targets: Array[Vector2i] = []
		for g in devices:
			if g.kind == Device.GATE and g.channel == d.channel:
				targets.append(g.tile)
		if d.channel == exit_channel:
			for c in w:
				if at(c, h - 1) == "D":
					targets.append(Vector2i(c, h - 2))
					break
		var best := Vector2i(-1, -1)
		var best_d := INF
		for tg in targets:
			var dd := Vector2(tg - d.tile).length()
			if dd < best_d:
				best_d = dd
				best = tg
		if best.x < 0:
			continue
		if not _lines.has(d.channel):
			_lines[d.channel] = Util.glow(d.ch_color(), 0.5)
		var m: StandardMaterial3D = _lines[d.channel]
		var a := tile_pos(d.tile.x, d.tile.y)
		var b := tile_pos(best.x, best.y)
		var corner := Vector3(b.x, 0, a.z)
		for seg: Array in [[a, corner], [corner, b]]:
			var from: Vector3 = seg[0]
			var to: Vector3 = seg[1]
			var length := from.distance_to(to)
			if length < 0.05:
				continue
			var line := Util.box(Vector3(length + 0.06, 0.012, 0.06) if absf(to.x - from.x) > 0.01 else Vector3(0.06, 0.012, length + 0.06), m)
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mesh(line, (from + to) * 0.5 + Vector3(0, 0.008, 0))


func set_channel_lit(ch: int, lit: bool) -> void:
	if _lines.has(ch):
		var col: Color = Device.CH_COLORS[ch % Device.CH_COLORS.size()]
		(_lines[ch] as StandardMaterial3D).albedo_color = col * (3.0 if lit else 0.5)


# --- Quality and per-frame -------------------------------------------------------------

## High: every light that wants shadows gets them. Low: only key lights cast shadows.
func apply_quality() -> void:
	var high := Game.high_quality()
	_flicker.clear()
	for n in get_tree().get_nodes_in_group("flicker"):
		if is_ancestor_of(n):
			_flicker.append(n)
	for n in find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l.has_meta("shadows"):
			var wants: bool = l.get_meta("shadows")
			l.shadow_enabled = wants and (high or l.is_in_group("key_light"))
			if l is OmniLight3D:
				l.light_size = 0.06 if high else 0.0
	for n in find_children("*", "GPUParticles3D", true, false):
		var p := n as GPUParticles3D
		p.amount_ratio = 1.0 if high else 0.35


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var i := 0
	for l in _flicker:
		var base: float = l.get_meta("base_energy")
		var k := float(i) * 1.7
		l.light_energy = base * (0.86 + 0.08 * sin(now * 9.0 + k) + 0.06 * sin(now * 23.0 + k * 2.3) + 0.04 * sin(now * 3.1 + k))
		i += 1


# --- Queries -----------------------------------------------------------------------

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := tile_of(from)
	var b := tile_of(to)
	var ids := astar.get_id_path(a, b, true)
	var out := PackedVector3Array()
	for id in ids:
		out.append(tile_pos(id.x, id.y))
	return out


## True if a point is on open, walkable floor inside the room (or in the lift).
func walkable(p: Vector3) -> bool:
	if in_lift(p):
		return true
	var tl := Vector2i(roundi(p.x / Util.TILE), roundi(p.z / Util.TILE))
	if tl.x < 0 or tl.y < 0 or tl.x >= w or tl.y >= h:
		return false
	return not astar.is_point_solid(tl)


func alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


func gates(ch: int) -> Array[Device]:
	var out: Array[Device] = []
	for d in devices:
		if d.kind == Device.GATE and d.channel == ch:
			out.append(d)
	return out
