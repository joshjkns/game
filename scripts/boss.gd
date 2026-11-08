class_name Boss
extends Enemy
## The act guardian, built for its era: a woolly titan in the Ice Age, a sun pharaoh's statue
## in Egypt, a clockwork keeper at the end of time. All cycle slams that erupt the ground,
## fire volleys and rockfalls. Freeze its falling rocks and release them onto its head.

## Per-era colour of the boss's rocks.
const ERA_BOSSES := {
	"tundra": {"rock": Color("a8d0e8")},
	"dunes": {"rock": Color("c98a52")},
	"tomb": {"rock": Color("5b5f8c")},
}

var title := ""
var phase := 1
var _next := "rockfall"
var _orbit: Node3D
var _eyes: Array[MeshInstance3D] = []
## Keeper only: its clock hands and pendulum, animated in _think.
var _hands: Array[Node3D] = []
var _pendulum: Node3D
var _life := 0.0


func _ready() -> void:
	type = "boss"
	add_to_group("boss")
	title = "Boss"
	super._ready()
	max_hp = 2600.0 * (1.0 + 0.6 * (Run.act - 1)) * Run.diff("hp")
	hp = max_hp
	speed = 3.6 * Run.diff("speed")
	dmg = 26.0 * (1.0 + 0.3 * (Run.act - 1)) * Run.diff("dmg")
	atk_cd = 2.0
	spawn_t = 1.5
	# The body capsule stops at the chest; the head gets its own hit sphere.
	var cs := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 1.6
	cs.shape = ball
	cs.position = head.position
	add_child(cs)


func _build_model() -> void:
	size = 3.2
	_outline.set_shader_parameter("width", 0.06)
	head = Node3D.new()
	model.add_child(head)
	var piece: Callable
	match Run.biome():
		"tundra":
			_build_titan()
			piece = func(r: float): return Kit.rock_mesh(Vector3.ONE * r, randi())
		"dunes":
			_build_pharaoh()
			piece = func(r: float): return _block_mesh(r)
		_:
			_build_keeper()
			piece = func(r: float): return Kit.cyl(r, r, 0.15, 10)
	var glow: Color = _eyes[0].material_override.albedo_color
	# Debris orbits the body, like time caught swirling around it.
	_orbit = Node3D.new()
	_orbit.position.y = 1.4 * size
	model.add_child(_orbit)
	for i in 7:
		var a := TAU * i / 7.0
		var r := Kit.part(_orbit, piece.call(randf_range(0.4, 0.8)), Kit.toon(ERA_BOSSES[Run.biome()].rock, 0.03), Vector3(cos(a) * 4.2, randf_range(-1.5, 2.0), sin(a) * 4.2))
		r.rotation = Vector3(randf(), randf(), randf()) * TAU
	var l := OmniLight3D.new()
	l.light_color = glow
	l.light_energy = 3.0
	l.omni_range = 10.0
	l.position = Vector3(0, 2.4 * size, -2.0)
	model.add_child(l)


func _block_mesh(r: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(r * 1.4, r * 0.8, r)
	return b


func _eye_pair(c: Color, at: Vector3) -> void:
	for sx in [-1.0, 1.0]:
		_eyes.append(_p(Kit.sphere(0.08, 6, 4), c, Vector3(at.x * sx, at.y, at.z), Vector3(1.4, 0.8, 1), Vector3.ZERO, true))


## A mammoth the size of a house, tusks first, ice growing out of its back.
func _build_titan() -> void:
	var fur := Color("6e4a32")
	var ivory := Color("efe6d2")
	_p(Kit.rock_mesh(Vector3(1.5, 1.25, 1.9), 11, 0.2), fur, Vector3(0, 1.55, 0.25))
	_p(Kit.rock_mesh(Vector3(1.1, 0.5, 1.5), 12, 0.25), fur.darkened(0.2), Vector3(0, 1.05, 0.25))
	for sx in [-1.0, 1.0]:
		for z in [-0.35, 0.85]:
			_p(Kit.cyl(0.26, 0.3, 1.0, 7), fur.darkened(0.25), Vector3(0.48 * sx, 0.5, z))
		_p(Kit.rock_mesh(Vector3(0.5, 0.7, 0.2), 14 + int(sx), 0.2), fur.darkened(0.15), Vector3(0.55 * sx, 2.0, -0.55))
		_p(Kit.cyl(0.08, 0.13, 1.0, 7), ivory, Vector3(0.32 * sx, 1.35, -1.43), Vector3.ONE, Vector3(-2.09, 0, 0.15 * sx))
		_p(Kit.cyl(0.03, 0.08, 0.8, 7), ivory, Vector3(0.36 * sx, 1.34, -2.19), Vector3.ONE, Vector3(-0.93, 0, 0.2 * sx))
	_p(Kit.rock_mesh(Vector3(0.95, 0.95, 0.85), 13, 0.15), fur.lightened(0.08), Vector3(0, 2.05, -0.75))
	_p(Kit.cyl(0.13, 0.2, 0.9, 7), fur.darkened(0.1), Vector3(0, 1.4, -1.12), Vector3.ONE, Vector3(0.25, 0, 0))
	_p(Kit.cyl(0.09, 0.13, 0.6, 7), fur.darkened(0.1), Vector3(0, 0.8, -1.05), Vector3.ONE, Vector3(-0.35, 0, 0))
	for i in 4:
		_p(Kit.cyl(0.0, 0.14, 0.6 + 0.2 * (i % 2), 5), Color(0.7, 0.92, 1.0), Vector3(-0.3 + 0.2 * i, 2.35, 0.25 * i),
			Vector3.ONE, Vector3(0.2, 0, 0.3 - 0.2 * i), true)
	_eye_pair(Color(0.45, 0.95, 1.0), Vector3(0.3, 2.2, -1.15))
	head.position = Vector3(0, 2.05, -0.75) * size


## A sandstone colossus in a striped headdress, a sun disc blazing behind its head.
func _build_pharaoh() -> void:
	var sand := Color("c98a52")
	var gold := Color("e0b04a")
	var lapis := Color("2a4a9c")
	var box := Kit.box_mesh()
	for sx in [-1.0, 1.0]:
		_p(box, sand.darkened(0.1), Vector3(0.3 * sx, 0.45, 0), Vector3(0.35, 0.9, 0.4))
		_p(box, sand, Vector3(0.8 * sx, 1.6, 0), Vector3(0.3, 1.0, 0.35))
		_p(box, sand, Vector3(0.3 * sx, 1.75, -0.4), Vector3(0.28, 0.28, 0.9), Vector3(0, 0.6 * sx, 0))
		_p(box, lapis, Vector3(0.42 * sx, 2.15, -0.05), Vector3(0.22, 0.7, 0.3))
		for j in 3:
			_p(box, gold, Vector3(0.42 * sx, 1.92 + j * 0.2, -0.05), Vector3(0.24, 0.05, 0.32))
	_p(Kit.cyl(0.55, 0.75, 0.6, 4), Color("efe6d2"), Vector3(0, 0.95, 0), Vector3.ONE, Vector3(0, PI / 4, 0))
	_p(box, gold, Vector3(0, 1.25, 0), Vector3(1.1, 0.12, 0.8))
	_p(box, sand, Vector3(0, 1.7, 0), Vector3(1.2, 0.9, 0.7))
	_p(Kit.cyl(0.62, 0.66, 0.12, 12), gold, Vector3(0, 2.12, 0))
	_p(Kit.cyl(0.05, 0.05, 1.2, 6), gold, Vector3(0.15, 1.95, -0.65), Vector3.ONE, Vector3(0, 0, 0.5))
	_p(box, sand, Vector3(0, 2.45, 0), Vector3(0.6, 0.6, 0.55))
	_p(box, gold, Vector3(0, 2.62, 0.08), Vector3(0.85, 0.5, 0.75))
	_p(box, lapis, Vector3(0, 2.05, -0.25), Vector3(0.12, 0.35, 0.12))
	_p(Kit.cyl(0.04, 0.07, 0.25, 6), gold, Vector3(0, 2.92, -0.3))
	_p(Kit.cyl(0.75, 0.75, 0.06, 24), Color(1.0, 0.75, 0.25), Vector3(0, 2.7, 0.55), Vector3.ONE, Vector3(PI / 2, 0, 0), true)
	_eye_pair(Color(1.0, 0.8, 0.3), Vector3(0.13, 2.5, -0.28))
	head.position = Vector3(0, 2.45, 0) * size


## A walking clock case: hands racing on its face, a pendulum swinging in its chest.
func _build_keeper() -> void:
	var metal := Color("3f3a5c")
	var brass := Color("c9a050")
	var box := Kit.box_mesh()
	for sx in [-1.0, 1.0]:
		_p(box, metal.darkened(0.2), Vector3(0.35 * sx, 0.3, 0), Vector3(0.3, 0.6, 0.4))
		_p(box, metal, Vector3(0.78 * sx, 1.4, 0), Vector3(0.28, 1.1, 0.3))
		_p(Kit.cyl(0.22, 0.22, 0.12, 10), brass, Vector3(0.78 * sx, 1.98, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
	_p(box, metal, Vector3(0, 1.35, 0), Vector3(1.1, 1.7, 0.7))
	_p(box, Color("15131f"), Vector3(0, 0.95, -0.36), Vector3(0.6, 0.7, 0.02))
	_p(Kit.cyl(0.68, 0.68, 0.05, 24), brass, Vector3(0, 1.8, -0.36), Vector3.ONE, Vector3(PI / 2, 0, 0))
	_p(Kit.cyl(0.62, 0.62, 0.06, 24), Color("efe6d2"), Vector3(0, 1.8, -0.38), Vector3.ONE, Vector3(PI / 2, 0, 0))
	_p(Kit.cyl(0.0, 0.75, 0.45, 4), metal.darkened(0.2), Vector3(0, 2.45, 0), Vector3.ONE, Vector3(0, PI / 4, 0))
	_p(Kit.sphere(0.38, 8, 5), metal, Vector3(0, 2.4, -0.1))
	var glow := Color(0.9, 0.4, 1.0)
	for i in 2:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 1.8, -0.43) * size
		model.add_child(pivot)
		var length := 0.5 if i == 0 else 0.32
		_parts.append(Kit.part(pivot, box, Kit.glow(glow if i == 0 else Color("2a2438"), 2.0 if i == 0 else 0.0),
			Vector3(0, length * 0.5, 0) * size, Vector3(0.05, length, 0.03) * size))
		_hands.append(pivot)
	_pendulum = Node3D.new()
	_pendulum.position = Vector3(0, 1.25, -0.38) * size
	model.add_child(_pendulum)
	_parts.append(Kit.part(_pendulum, box, _mat(brass), Vector3(0, -0.25, 0) * size, Vector3(0.03, 0.5, 0.02) * size))
	_parts.append(Kit.part(_pendulum, Kit.cyl(0.12, 0.12, 0.04, 14), Kit.glow(brass, 1.5), Vector3(0, -0.55, 0) * size,
		Vector3.ONE * size, Vector3(PI / 2, 0, 0)))
	_eye_pair(glow, Vector3(0.13, 2.42, -0.43))
	head.position = Vector3(0, 2.4, 0) * size


func is_head(p: Vector3) -> bool:
	return head != null and p.distance_to(head.global_position) < 1.3


func aim_radius() -> float:
	return 3.0


func freeze(t: float) -> void:
	# Bosses resist Stasis: a short stagger rather than a full freeze.
	super.freeze(minf(t, 1.2))


func _think(dt: float, t: Node3D) -> void:
	_orbit.rotation.y += dt * (0.6 if phase == 1 else 1.4)
	_life += dt
	for i in _hands.size():
		_hands[i].rotation.z -= dt * (4.0 if i == 0 else 0.33) * phase
	if _pendulum:
		_pendulum.rotation.z = sin(_life * 2.2 * phase) * 0.45
	if phase == 1 and hp < max_hp * 0.5:
		phase = 2
		speed = 4.6 * Run.diff("speed")
		Kit.shockwave(get_parent(), global_position, Color(1.0, 0.3, 0.2), 10.0, 0.6)
		Kit.sfx(get_parent(), "player_die", global_position, 0.0, 0.5)
	var to := t.global_position - global_position
	var dist := Vector2(to.x, to.z).length()
	_face(t.global_position, dt, 3.0)
	atk_cd -= dt
	if windup > 0.0:
		windup -= dt
		model.position.y = sin(windup * 30.0) * 0.05
		velocity.x = move_toward(velocity.x, 0, 30.0 * dt)
		velocity.z = move_toward(velocity.z, 0, 30.0 * dt)
		if windup <= 0.0:
			_attack(t)
			_refresh_outline()
		return
	_steer(to if dist > 9.0 else Vector3.ZERO, speed, dt)
	if atk_cd <= 0.0:
		_begin(1.0 if _next != "volley" else 0.7, 2.6 if phase == 1 else 1.7)


func _attack(t: Node3D) -> void:
	var world := get_parent()
	match _next:
		"slam":
			Kit.shockwave(world, global_position, Color(1.0, 0.45, 0.25), 7.0, 0.5)
			Kit.sfx(world, "punch", global_position, 4.0, 0.4)
			var count := 6 if phase == 1 else 10
			for i in count:
				var at: Vector3 = t.global_position + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7))
				if i == 0:
					at = t.global_position
				_eruption(Vector3(at.x, t.global_position.y, at.z), 0.9 + i * 0.08)
			_next = "volley"
		"volley":
			for wave in (2 if phase == 1 else 3):
				get_tree().create_timer(wave * 0.45).timeout.connect(func():
					if dead or not is_instance_valid(t):
						return
					for a in range(-3, 4):
						_fire_orb(t, a * 0.12))
			_next = "rockfall"
		"rockfall":
			for i in (4 if phase == 1 else 6):
				var f := Faller.new()
				f.size = randf_range(2.0, 3.0)
				f.color = ERA_BOSSES[Run.biome()].rock
				world.add_child(f)
				var spot: Vector3 = t.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				if i == 0:
					spot = t.global_position
				f.drop_at(Vector3(spot.x, t.global_position.y, spot.z))
			_next = "slam"
			if phase == 2:
				for i in 2:
					var e := Enemy.new()
					e.setup(["scrapper", "bomber"].pick_random(), false)
					world.add_child(e)
					e.global_position = global_position + Vector3(randf_range(-5, 5), 0.5, randf_range(-5, 5))


func _fire_orb(t: Node3D, angle: float) -> void:
	var p := Projectile.new()
	p.damage = dmg * 0.6
	p.color = _eyes[0].material_override.albedo_color if not _eyes.is_empty() else Color.ORANGE
	p.radius = 0.4
	var from := global_position + Vector3.UP * 4.8 - global_basis.z * 2.0
	var aim: Vector3 = (t.global_position + Vector3.UP - from).normalized()
	p.velocity = aim.rotated(Vector3.UP, angle) * 18.0
	get_parent().add_child(p)
	p.global_position = from
	Kit.sfx(get_parent(), "enemy_shot", from, 0.0, 0.6)


## A red ring on the ground that erupts after a delay.
func _eruption(at: Vector3, delay: float) -> void:
	var world := get_parent()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 3
	var ring := MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = Kit.glow(Color(1.0, 0.2, 0.15), 3.0, 0.9)
	world.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.1
	ring.scale = Vector3(2.4, 0.5, 2.4)
	var core := Kit.part(ring, Kit.cyl(0.95, 0.95, 0.02, 20), Kit.glow(Color(0.8, 0.1, 0.1), 1.5, 0.4))
	core.scale = Vector3(0.1, 1, 0.1)
	var tw := ring.create_tween()
	tw.tween_property(core, "scale", Vector3(1, 1, 1), delay)
	tw.tween_callback(func():
		Kit.shockwave(world, at, Color(1.0, 0.45, 0.2), 2.6, 0.4)
		Kit.burst(world, at, Color(1.0, 0.5, 0.2), 10, 9.0, 0.15, 0.5)
		for p in get_tree().get_nodes_in_group("player"):
			if Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < 2.4 and p.global_position.y - at.y < 2.0:
				p.hurt(dmg, at)
				p.velocity.y = 8.0
		ring.queue_free())


func die() -> void:
	if dead:
		return
	Pickup.drop_coins(get_parent(), aim_point(), 40)
	super.die()
