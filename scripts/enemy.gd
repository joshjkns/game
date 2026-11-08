class_name Enemy
extends CharacterBody3D
## The Unwound: little masked clockwork raiders. One script, several behaviours by type.
## Every enemy is time-aware: Slow Fields scale its clock and Stasis freezes it solid.

signal died(enemy: Enemy)

const TYPES := {
	"scrapper": {"hp": 70.0, "speed": 6.4, "dmg": 12.0, "coins": 2, "size": 1.0, "color": "c9643a", "reach": 1.9},
	"slinger": {"hp": 55.0, "speed": 4.8, "dmg": 10.0, "coins": 2, "size": 0.95, "color": "3f8c6a", "reach": 30.0},
	"warden": {"hp": 230.0, "speed": 3.6, "dmg": 22.0, "coins": 5, "size": 1.5, "color": "5b5f8c", "reach": 2.8},
	"hexer": {"hp": 50.0, "speed": 5.0, "dmg": 9.0, "coins": 3, "size": 0.9, "color": "8c3f7a", "reach": 30.0},
	"bomber": {"hp": 32.0, "speed": 8.6, "dmg": 28.0, "coins": 1, "size": 0.8, "color": "d4a02a", "reach": 2.0},
}
## Same five behaviours in every act, dressed for the era: names, colours, mask, eyes,
## metal (blades, guns, shield) and trim (charms, crests).
const ERA_LOOKS := {
	"tundra": {"mask": "e8dcc0", "eye": Color(0.45, 0.95, 1.0), "magic": Color(0.6, 0.55, 1.0),
		"metal": "d8cba8", "trim": "efe9dc", "types": {
		"scrapper": ["Rime Raider", "8a5a3c"], "slinger": ["Frost Slinger", "6b7f99"],
		"warden": ["Mammoth Guard", "6e4a32"], "hexer": ["Frost Shaman", "5f86b0"], "bomber": ["Ice Bomb", "9fd6f0"]}},
	"dunes": {"mask": "e0b04a", "eye": Color(1.0, 0.45, 0.2), "magic": Color(1.0, 0.85, 0.3),
		"metal": "c99a4a", "trim": "e0b04a", "types": {
		"scrapper": ["Sand Raider", "b5653a"], "slinger": ["Lapis Slinger", "2f5f9c"],
		"warden": ["Jackal Guard", "2e2b3a"], "hexer": ["Sun Priest", "e6dcc4"], "bomber": ["Scarab Bomb", "2f8f7a"]}},
	"tomb": {"mask": "1c1f2a", "eye": Color(0.3, 1.0, 0.9), "magic": Color(0.9, 0.4, 1.0),
		"metal": "9aa3b8", "trim": "6ff0e0", "types": {
		"scrapper": ["Scrap Bot", "7d8399"], "slinger": ["Rail Gunner", "4b6a8c"],
		"warden": ["Sentinel", "3f3a5c"], "hexer": ["Oracle", "7a4fa0"], "bomber": ["Pulse Mine", "c8a040"]}},
}
const INK := Color(0.07, 0.04, 0.09)
const GRAVITY := 20.0

var type := "scrapper"
var elite := false
## A rewound copy of a fallen enemy: spectral, frailer, and drops nothing.
var echo := false
var hp := 70.0
var max_hp := 70.0
var speed := 5.0
var dmg := 10.0
var size := 1.0
var frozen := 0.0
var burn_t := 0.0
var burn_dps := 0.0
var rust_t := 0.0
var atk_cd := 1.5
var windup := 0.0
var spawn_t := 0.4
## False when a cutscene brings this enemy in instead of the usual pop-in.
var rise_in := true
var dead := false
## Seconds since this enemy was last hit; the HUD shows a health bar while it's recent.
var since_hit := 99.0
var decay_t := 0.0
var head: Node3D
var model: Node3D
var _parts: Array[MeshInstance3D] = []
var _outline: ShaderMaterial
var _ice: MeshInstance3D
var _tick_acc := 0.0
var _tick_color := Color.WHITE
var _tick_show := 0.0
var _strafe := 1.0
var _think_t := 0.0
var _anim := 0.0
var _flash_t := 0.0
var _overlay: StandardMaterial3D
var era := "tundra"
var _look: Dictionary
var _color := Color.WHITE


func setup(t: String, is_elite: bool, is_echo := false) -> void:
	type = t
	elite = is_elite
	echo = is_echo


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("chrono")
	collision_layer = Kit.L_ENEMY
	collision_mask = Kit.L_WORLD
	var d: Dictionary = TYPES.get(type, {})
	era = Run.biome()
	_look = ERA_LOOKS[era]
	_color = Color(_look.types[type][1]) if _look.types.has(type) else Color(d.get("color", "ffffff"))
	var depth_k := 1.0 + 0.45 * (Run.depth() - 1)
	if not d.is_empty():
		max_hp = d.hp * depth_k * Run.diff("hp")
		speed = d.speed * Run.diff("speed")
		dmg = d.dmg * (1.0 + 0.22 * (Run.depth() - 1)) * Run.diff("dmg")
		size = d.size
	if elite:
		max_hp *= 2.6
		size *= 1.25
		dmg *= 1.3
	if echo:
		max_hp *= 0.5
	hp = max_hp
	_strafe = [-1.0, 1.0].pick_random()
	_overlay = Kit.glow(Color.WHITE, 2.0, 0.85)
	_outline = Kit.own_outline(0.035 * size, _base_ink())
	model = Node3D.new()
	add_child(model)
	_build_model()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * size
	# Tall enough to cover the head, so headshots can't sail over the top of the capsule.
	cap.height = maxf(maxf(1.7 * size, head.position.y + 0.38 * size), cap.radius * 2.0 + 0.1)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	if not rise_in:
		return
	model.scale = Vector3.ONE * 0.01
	create_tween().tween_property(model, "scale", Vector3.ONE, spawn_t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## --- Look ---------------------------------------------------------------------

func _base_ink() -> Color:
	if echo:
		return Run.TIME_COLOR
	return Color("ffc23a") if elite else INK


func _mat(c: Color) -> StandardMaterial3D:
	if echo:
		# Echoes are ghosts of the last few seconds: translucent and tinted with time.
		var g := Kit.glow(c.lerp(Run.TIME_COLOR, 0.6), 0.6, 0.55)
		g.next_pass = _outline
		return g
	var m := Kit.toon(c)
	m.next_pass = _outline
	return m


func _p(mesh: Mesh, c: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, glow := false) -> MeshInstance3D:
	var mi := Kit.part(model, mesh, Kit.glow(c, 3.0) if glow else _mat(c), pos * size, scl * size, rot)
	_parts.append(mi)
	return mi


func _build_model() -> void:
	var c := _color
	var dark := c.darkened(0.45)
	var mask := Color(_look.mask)
	var eye: Color = _look.magic if type == "hexer" else _look.eye
	var metal := Color(_look.metal)
	var trim := Color(_look.trim)
	var box := Kit.box_mesh()
	match type:
		"hexer":
			_p(Kit.cyl(0.12, 0.5, 1.0, 6), c, Vector3(0, 0.9, 0))
			_p(Kit.cyl(0.0, 0.3, 0.45, 6), dark, Vector3(0, 1.85, 0))
			for i in 3:
				var a := TAU * i / 3.0
				_p(Kit.cyl(0.14, 0.14, 0.04, 8), trim, Vector3(cos(a) * 0.6, 1.2, sin(a) * 0.6), Vector3.ONE, Vector3(PI / 2, a, 0), era == "tomb")
		"warden":
			_p(Kit.rock_mesh(Vector3(1.0, 1.0, 0.8), 3, 0.15), c, Vector3(0, 0.95, 0))
			_p(box, dark, Vector3(-0.22, 0.25, 0), Vector3(0.22, 0.5, 0.25))
			_p(box, dark, Vector3(0.22, 0.25, 0), Vector3(0.22, 0.5, 0.25))
			_p(box, metal, Vector3(0, 0.95, -0.62), Vector3(1.15, 1.25, 0.12))
			_p(box, trim, Vector3(0, 0.95, -0.7), Vector3(0.3, 0.3, 0.05), Vector3(0, 0, PI / 4), era == "tomb")
		"bomber":
			_p(Kit.sphere(0.45, 8, 6), c, Vector3(0, 0.6, 0))
			_p(Kit.cyl(0.04, 0.06, 0.3, 6), dark, Vector3(0, 1.15, 0))
			_p(Kit.sphere(0.09, 6, 4), Color(1.0, 0.6, 0.2), Vector3(0, 1.32, 0), Vector3.ONE, Vector3.ZERO, true)
			_p(box, dark, Vector3(-0.18, 0.12, 0), Vector3(0.14, 0.25, 0.18))
			_p(box, dark, Vector3(0.18, 0.12, 0), Vector3(0.14, 0.25, 0.18))
		_:
			_p(Kit.rock_mesh(Vector3(0.75, 0.85, 0.6), 7, 0.15), c, Vector3(0, 0.85, 0))
			_p(box, dark, Vector3(-0.17, 0.25, 0), Vector3(0.18, 0.5, 0.2))
			_p(box, dark, Vector3(0.17, 0.25, 0), Vector3(0.18, 0.5, 0.2))
			if type == "slinger":
				_p(Kit.cyl(0.09, 0.12, 0.6, 8), metal.darkened(0.4), Vector3(0.42, 0.95, -0.25), Vector3.ONE, Vector3(PI / 2, 0, 0))
				_p(Kit.sphere(0.07, 6, 4), eye, Vector3(0.42, 0.95, -0.56), Vector3.ONE, Vector3.ZERO, true)
			else:
				_p(box, metal, Vector3(0.42, 0.85, -0.3), Vector3(0.08, 0.08, 0.7), Vector3(0.3, 0, 0))
	# Every Unwound wears a mask with glowing eye slits; the era decides what it's made of.
	var head_y: float = {"hexer": 1.55, "warden": 1.75, "bomber": 0.95}.get(type, 1.5)
	head = Node3D.new()
	head.position = Vector3(0, head_y * size, 0)
	model.add_child(head)
	if type != "bomber":
		_p(Kit.sphere(0.3, 8, 5), dark, Vector3(0, head_y, 0.02))
	_p(box, mask, Vector3(0, head_y, -0.22 if type != "bomber" else -0.4), Vector3(0.42, 0.34, 0.1))
	for sx in [-1.0, 1.0]:
		_p(box, eye, Vector3(0.09 * sx, head_y + 0.03, -0.28 if type != "bomber" else -0.46), Vector3(0.1, 0.04, 0.04), Vector3.ZERO, true)
	_dress(head_y, trim, eye)
	if type == "hexer":
		var l := OmniLight3D.new()
		l.light_color = eye
		l.light_energy = 1.0
		l.omni_range = 3.0
		l.position.y = 1.2
		model.add_child(l)


## Era costume on top of the shared body.
func _dress(head_y: float, trim: Color, eye: Color) -> void:
	var box := Kit.box_mesh()
	match era:
		"tundra":
			if type == "bomber":
				for i in 5:
					var a := TAU * i / 5.0
					_p(Kit.cyl(0.0, 0.1, 0.4, 4), Color("dff6ff"), Vector3(cos(a) * 0.4, 0.75, sin(a) * 0.4), Vector3.ONE, Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9))
				return
			# Fur ruff round the shoulders.
			_p(Kit.sphere(0.3, 8, 5), Color("efe9dc"), Vector3(0, head_y - 0.3, 0), Vector3(1.6, 0.55, 1.4))
			if type == "warden":
				for sx in [-1.0, 1.0]:
					_p(Kit.cyl(0.02, 0.08, 0.8, 6), trim, Vector3(0.24 * sx, head_y - 0.2, -0.45), Vector3.ONE, Vector3(-1.1, 0, -0.25 * sx))
			elif type == "hexer":
				for sx in [-1.0, 1.0]:
					_p(Kit.cyl(0.02, 0.04, 0.5, 4), trim, Vector3(0.2 * sx, head_y + 0.35, 0), Vector3.ONE, Vector3(0, 0, -0.6 * sx))
					_p(Kit.cyl(0.015, 0.03, 0.25, 4), trim, Vector3(0.3 * sx, head_y + 0.45, -0.05), Vector3.ONE, Vector3(0, 0, -1.2 * sx))
		"dunes":
			if type == "bomber":
				_p(box, trim, Vector3(0, 0.6, 0), Vector3(0.06, 0.93, 0.93))
				return
			_p(Kit.cyl(0.36, 0.42, 0.1, 10), trim, Vector3(0, head_y - 0.32, 0))
			if type == "warden":
				for sx in [-1.0, 1.0]:
					_p(Kit.cyl(0.0, 0.1, 0.5, 4), _color, Vector3(0.16 * sx, head_y + 0.42, 0.05))
			else:
				# Striped headdress: a gold cap with blue lappets either side of the mask.
				_p(box, trim, Vector3(0, head_y + 0.08, 0.06), Vector3(0.66, 0.42, 0.5))
				for sx in [-1.0, 1.0]:
					_p(box, Color("2a4a9c"), Vector3(0.29 * sx, head_y - 0.2, -0.04), Vector3(0.12, 0.45, 0.2))
			if type == "hexer":
				_p(Kit.cyl(0.24, 0.24, 0.04, 14), eye, Vector3(0, head_y + 0.55, 0.05), Vector3.ONE, Vector3(PI / 2, 0, 0), true)
		"tomb":
			if type == "bomber":
				_p(Kit.cyl(0.47, 0.47, 0.08, 12), eye, Vector3(0, 0.6, 0), Vector3.ONE, Vector3.ZERO, true)
				return
			# Visor band and a little antenna.
			_p(box, eye, Vector3(0, head_y + 0.03, -0.28), Vector3(0.36, 0.03, 0.03), Vector3.ZERO, true)
			_p(Kit.cyl(0.015, 0.015, 0.4, 4), Color(_look.metal), Vector3(0.15, head_y + 0.4, 0.05))
			_p(Kit.sphere(0.05, 6, 4), eye, Vector3(0.15, head_y + 0.62, 0.05), Vector3.ONE, Vector3.ZERO, true)
			if type == "warden":
				for sx in [-1.0, 1.0]:
					_p(box, Color(_look.metal), Vector3(0.6 * sx, 1.45, 0), Vector3(0.35, 0.3, 0.45))
					_p(box, eye, Vector3(0.6 * sx, 1.45, -0.23), Vector3(0.25, 0.05, 0.02), Vector3.ZERO, true)


func aim_point() -> Vector3:
	return global_position + Vector3.UP * (head.position.y * 0.7 if head else size)


func aim_radius() -> float:
	return 0.9 * size


func is_head(p: Vector3) -> bool:
	return head != null and p.distance_to(head.global_position) < 0.5 * size


func can_freeze() -> bool:
	return not dead


func freeze(t: float) -> void:
	frozen = maxf(frozen, t)
	windup = 0.0
	if _ice == null:
		_ice = Kit.part(self, Kit.rock_mesh(Vector3(1.3, 2.1, 1.3) * size, randi(), 0.2), Kit.glow(Color(0.55, 0.9, 1.0), 1.0, 0.35))
		_ice.position.y = size
	_refresh_outline()


func _refresh_outline() -> void:
	var c := _base_ink()
	if frozen > 0.0:
		c = Color(0.45, 0.9, 1.0)
	elif burn_t > 0.0:
		c = Color(1.0, 0.4, 0.15)
	elif rust_t > 0.0:
		c = Color(0.5, 1.0, 0.25)
	elif windup > 0.0:
		c = Color(1.0, 0.15, 0.2)
	_outline.set_shader_parameter("color", c)


## --- Damage -------------------------------------------------------------------

func take_hit(amount: float, crit: bool, element: String, point: Vector3, dir: Vector3) -> void:
	if dead:
		return
	if type == "warden" and frozen <= 0.0 and dir.dot(-global_basis.z) < -0.35 and not is_head(point):
		amount *= 0.15
		Kit.number(get_parent(), point, amount, Color(0.7, 0.72, 0.8))
		Kit.burst(get_parent(), point, Color(0.9, 0.9, 1.0), 4, 3.0, 0.05, 0.2)
		_apply(amount)
		return
	if frozen > 0.0:
		amount *= 1.3
	if rust_t > 0.0:
		amount *= 1.25
	if crit:
		amount *= Run.crit_mult()
	since_hit = 0.0
	Run.add_ult(amount)
	var col: Color = Color("ffd23a") if crit else (Run.ELEMENTS[element].color if element != "" else Color.WHITE)
	Kit.number(get_parent(), point, amount, col, crit)
	if element != "" and randf() < 0.3 + Run.stat("elem"):
		_proc(element, amount)
	if type != "warden" and frozen <= 0.0:
		velocity += dir * 1.2
	_flash_t = 0.06
	for p in _parts:
		p.material_overlay = _overlay
	_apply(amount)


## Damage over time (burn, heavy field): numbers are batched so they stay readable.
func take_tick(amount: float, color: Color) -> void:
	if dead:
		return
	_tick_acc += amount
	_tick_color = color
	_apply(amount)


## Dusk's Decay: corrodes and rots (damage over time) for t seconds.
func decay(t: float, dps: float) -> void:
	decay_t = t
	rust_t = maxf(rust_t, t)
	burn_t = maxf(burn_t, t)
	burn_dps = maxf(burn_dps, dps)
	_refresh_outline()


func display_name() -> String:
	return ("Echo " if echo else ("Elite " if elite else "")) + (_look.types[type][0] if _look.types.has(type) else type.capitalize())


func _apply(amount: float) -> void:
	hp -= amount
	if hp <= 0.0:
		die()


func _proc(element: String, base: float) -> void:
	match element:
		"fire":
			burn_t = 4.0
			burn_dps = maxf(burn_dps, base * 0.25)
		"rust":
			rust_t = 5.0
		"shock":
			var hits := 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if e == self or e.dead or e.global_position.distance_to(global_position) > 7.0:
					continue
				Kit.tracer(get_parent(), aim_point(), e.aim_point(), Color(0.45, 0.85, 1.0), 0.2, 0.05)
				e.take_hit(base * 0.5, false, "", e.aim_point(), Vector3.ZERO)
				hits += 1
				if hits >= 2:
					break
	_refresh_outline()


func die() -> void:
	if dead:
		return
	dead = true
	remove_from_group("enemies")
	remove_from_group("chrono")
	var world := get_parent()
	var at := aim_point()
	Kit.burst(world, at, _color.lightened(0.3), 16, 6.0, 0.12, 0.55)
	Kit.burst(world, at, Color(1.0, 0.85, 0.5), 8, 4.0, 0.05, 0.4)
	Kit.sfx(world, "enemy_die", at, -2.0)
	var coins: int = TYPES.get(type, {"coins": 20}).coins * (3 if elite else 1)
	var arena := world as Arena
	if arena and arena.golden_t > 0.0:
		coins *= 2
	coins = roundi(coins * Run.diff("coins"))
	if not echo:
		Pickup.drop_coins(world, at, coins)
	if not echo and randf() < 0.1:
		Pickup.drop(world, at, "health")
	if frozen > 0.0 and Run.has("shatter"):
		Kit.shockwave(world, at, Color(0.55, 0.9, 1.0), 4.0)
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(global_position) < 4.0:
				e.take_hit(40.0 * (1.0 + 0.3 * (Run.depth() - 1)), false, "", e.aim_point(), Vector3.ZERO)
				if not e.dead:
					e.freeze(1.5)
	if decay_t > 0.0 and Run.has("rot"):
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(global_position) < 5.0:
				e.decay(4.0, burn_dps)
				Kit.tracer(world, at, e.aim_point(), Color(0.55, 1.0, 0.4), 0.3, 0.06)
	Run.kills += 1
	for p in get_tree().get_nodes_in_group("player"):
		p.on_kill()
	died.emit(self)
	queue_free()


## --- Behaviour ----------------------------------------------------------------

func target() -> Node3D:
	var decoys := get_tree().get_nodes_in_group("decoys")
	if not decoys.is_empty():
		return decoys[0]
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty() or not ps[0].alive:
		return null
	return ps[0]


func _physics_process(delta: float) -> void:
	if dead:
		return
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for p in _parts:
				p.material_overlay = null
	since_hit += delta
	decay_t = maxf(0.0, decay_t - delta)
	_status(delta)
	if frozen > 0.0:
		return
	if spawn_t > 0.0:
		spawn_t -= delta
		return
	var ts := SlowField.scale_at(get_tree(), global_position)
	var dt := delta * ts
	_anim += dt
	var t := target()
	if t == null:
		velocity.x = 0
		velocity.z = 0
	else:
		_think(dt, t)
	if type != "hexer":
		velocity.y -= GRAVITY * dt
	# Movement is scaled by local time: velocity stays "real", the step is scaled.
	velocity *= ts
	move_and_slide()
	velocity /= ts
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	if global_position.y < -20.0:
		die()


func _status(delta: float) -> void:
	if frozen > 0.0:
		frozen -= delta
		if frozen <= 0.0:
			if _ice:
				_ice.queue_free()
				_ice = null
			_refresh_outline()
	if burn_t > 0.0:
		burn_t -= delta
		take_tick(burn_dps * delta, Color(1.0, 0.45, 0.2))
		if burn_t <= 0.0:
			burn_dps = 0.0
			_refresh_outline()
	if rust_t > 0.0:
		rust_t -= delta
		if rust_t <= 0.0:
			_refresh_outline()
	_tick_show -= delta
	if _tick_show <= 0.0 and _tick_acc >= 1.0:
		Kit.number(get_parent(), aim_point(), _tick_acc, _tick_color)
		_tick_acc = 0.0
		_tick_show = 0.45


func _face(at: Vector3, dt: float, rate := 8.0) -> void:
	var d := at - global_position
	d.y = 0
	if d.length() < 0.01:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-rate * dt))


func _steer(dir: Vector3, spd: float, dt: float) -> void:
	dir.y = 0
	dir = dir.normalized()
	# Push apart from nearby allies so groups spread into a crowd instead of a single file.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self:
			continue
		var off: Vector3 = global_position - e.global_position
		off.y = 0
		var l := off.length()
		if l < 1.6 * size and l > 0.01:
			dir += off / l * (1.6 * size - l)
	if is_on_wall():
		dir += get_wall_normal().cross(Vector3.UP) * _strafe
	dir = dir.normalized()
	var want := dir * spd
	velocity.x = move_toward(velocity.x, want.x, 30.0 * dt)
	velocity.z = move_toward(velocity.z, want.z, 30.0 * dt)
	model.rotation.z = sin(_anim * spd * 2.2) * 0.12 * minf(spd, 1.0)
	model.position.y = absf(sin(_anim * spd * 2.2)) * 0.06


func _think(dt: float, t: Node3D) -> void:
	var to := t.global_position - global_position
	var dist := Vector2(to.x, to.z).length()
	atk_cd -= dt
	# Wardens turn their shields slowly, so you can get round the back of them.
	_face(t.global_position, dt, 1.6 if type == "warden" else 8.0)
	if windup > 0.0:
		windup -= dt
		model.rotation.x = lerpf(model.rotation.x, 0.35, 1.0 - exp(-10.0 * dt))
		velocity.x = move_toward(velocity.x, 0, 40.0 * dt)
		velocity.z = move_toward(velocity.z, 0, 40.0 * dt)
		if windup <= 0.0:
			model.rotation.x = 0.0
			_attack(t)
			_refresh_outline()
		return
	match type:
		"slinger":
			var want := to.normalized() * (1.0 if dist > 15.0 else (-1.0 if dist < 9.0 else 0.0))
			_steer(want + to.normalized().cross(Vector3.UP) * _strafe * 0.8, speed, dt)
			if atk_cd <= 0.0 and dist < 30.0:
				_begin(0.4, 1.9)
		"hexer":
			var hover := 2.6 + sin(_anim * 2.0) * 0.4
			var ground := _ground_y()
			velocity.y = (ground + hover - global_position.y) * 3.0
			var want := to.normalized() * (1.0 if dist > 14.0 else -0.5)
			_steer(want + to.normalized().cross(Vector3.UP) * _strafe, speed, dt)
			_think_t -= dt
			if _think_t <= 0.0:
				_think_t = randf_range(2.5, 4.0)
				_strafe = -_strafe
			if atk_cd <= 0.0 and dist < 30.0:
				_begin(0.45, 2.4)
		"bomber":
			_steer(to, speed, dt)
			if dist < TYPES.bomber.reach:
				_begin(0.45, 99.0)
		_:
			var reach: float = TYPES[type].reach
			if dist > reach * 0.85:
				_steer(to, speed, dt)
			else:
				_steer(Vector3.ZERO, 0.0, dt)
			if dist < reach and atk_cd <= 0.0:
				_begin(0.45 if type == "scrapper" else 0.75, 1.1 if type == "scrapper" else 2.1)


func _ground_y() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.DOWN * 30.0, Kit.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _begin(wind: float, cooldown: float) -> void:
	windup = wind
	atk_cd = cooldown + randf_range(0.0, 0.6)
	_refresh_outline()


func _attack(t: Node3D) -> void:
	var world := get_parent()
	var dist := global_position.distance_to(t.global_position)
	match type:
		"slinger":
			_fire(t, 0.0)
		"hexer":
			for a in [-0.25, 0.0, 0.25]:
				_fire(t, a)
		"bomber":
			Kit.shockwave(world, global_position, Color(1.0, 0.55, 0.2), 3.5)
			Kit.flash(world, global_position + Vector3.UP, Color(1.0, 0.6, 0.2), 6.0, 8.0, 0.2)
			if dist < 3.5 and t is Player:
				t.hurt(dmg, global_position)
			die()
		"warden":
			Kit.shockwave(world, global_position - global_basis.z * 1.2, Color(1.0, 0.4, 0.3), 3.4)
			Kit.sfx(world, "punch", global_position, 0.0, 0.6)
			if dist < 3.6 and t is Player:
				t.hurt(dmg, global_position)
		_:
			Kit.sfx(world, "punch", global_position, -4.0, 1.2)
			if dist < TYPES.scrapper.reach + 0.6 and t is Player:
				t.hurt(dmg, global_position)
			velocity += -global_basis.z * 6.0


func _fire(t: Node3D, angle: float) -> void:
	var p := Projectile.new()
	p.damage = dmg
	p.color = Color(1.0, 0.45, 0.2) if type == "slinger" else Color(0.9, 0.35, 1.0)
	var from := aim_point() - global_basis.z * 0.6 * size
	var aim: Vector3 = (t.global_position + Vector3.UP * 1.1 - from).normalized()
	p.velocity = aim.rotated(Vector3.UP, angle) * (21.0 if type == "slinger" else 15.0)
	get_parent().add_child(p)
	p.global_position = from
	Kit.sfx(get_parent(), "enemy_shot", from, -6.0)
