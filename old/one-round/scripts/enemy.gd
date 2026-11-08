class_name Enemy
extends CharacterBody3D
## Grunt, turret, Anchor or rusher. The host runs the AI; clients follow snapshots.
## Hit rules (punch, thrown prop, thrown gun): the first hit disarms and stuns, the next one kills.
## Rushers carry no weapon, so any hit kills them. Bullets (revolver either way, reversed enemy
## bullets) kill outright, except Anchors, which only die to a temporal pincer.

const GRUNT := 0
const TURRET := 1
const ANCHOR := 2
const RUSHER := 3

const MOVE_SPEED := 3.0
const STOP_RANGE := 11.0
const FIRE_RANGE := 22.0
const CHARGE_TIME := 0.45
const STRAFE_SPEED := 2.2
const RUSH_SPEED := 6.2
## Rushers stop pathing and run straight at a visible target inside this range.
const LUNGE_RANGE := 7.0
## A rusher this close to a player (centre to centre) cuts them down.
const CONTACT := 1.0
const KNOCK_DRAG := 14.0

const F_ARMED := 1
const F_STUNNED := 2
const F_CRACKED := 4
const F_CHARGING := 8

var id := 0
var kind := GRUNT
var fire_interval := 2.0
var moves := true
var room: Room
var home_yaw := 0.0

var alive := true
var armed := true
var stunned := 0.0
var cracked := false
var charging := false
var yaw := 0.0
var start_pos := Vector3.ZERO
## Host: knockback velocity while stunned (a slide kick).
var knock := Vector3.ZERO

var _next_fire := 1.5
var _path := PackedVector3Array()
var _path_i := 0
var _repath := 0.0
var _strafe_dir := 1.0
var _strafe_t := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _targeted := false
var _target_color := Util.AMBER

var _rig: Node3D
var _visor_mat: StandardMaterial3D
var _body: Humanoid
var _gun: Node3D
var _armour: MeshInstance3D
var _armour_mat: ShaderMaterial
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = Util.L_ENEMY
	collision_mask = Util.L_WORLD | Util.L_GLASS | Util.L_ENEMY | Util.L_PLAYER | Util.L_GATE
	start_pos = global_position
	yaw = home_yaw
	_net_pos = global_position
	_net_yaw = yaw
	_rig = Node3D.new()
	add_child(_rig)
	var cs := CollisionShape3D.new()
	if kind == TURRET:
		_build_turret(cs)
	else:
		_build_humanoid(cs)
	add_child(cs)
	_rig.rotation.y = yaw
	reset()


## Bolt-caster: a bound crossbow that fires slow red rounds. Points down -Z.
func _build_caster() -> Node3D:
	var g := Node3D.new()
	var wood := Mats.dark_wood()
	var stock := Util.box(Vector3(0.07, 0.09, 0.62), wood)
	stock.position = Vector3(0, -0.02, -0.12)
	g.add_child(stock)
	var grip := Util.box(Vector3(0.05, 0.14, 0.07), wood)
	grip.position = Vector3(0, -0.1, 0.06)
	grip.rotation.x = 0.3
	g.add_child(grip)
	for s in [-1.0, 1.0]:
		var limb := Util.box(Vector3(0.36, 0.035, 0.05), Mats.iron())
		limb.position = Vector3(0.17 * s, 0.0, -0.4)
		limb.rotation.y = 0.35 * s
		g.add_child(limb)
	var gem := Util.sphere(0.045, _visor_mat)
	gem.position = Vector3(0, 0.05, -0.36)
	g.add_child(gem)
	var rail := Util.box(Vector3(0.02, 0.02, 0.5), _visor_mat)
	rail.position = Vector3(0, 0.035, -0.18)
	g.add_child(rail)
	return g


func _build_humanoid(cs: CollisionShape3D) -> void:
	var big := kind == ANCHOR
	var r := 0.42 if big else 0.32
	var hgt := 2.0 if big else 1.75
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = hgt
	cs.shape = cap
	cs.position.y = hgt * 0.5
	_body = Humanoid.new(Humanoid.Style.KNIGHT if big else Humanoid.Style.CULTIST, Util.AMBER if kind == RUSHER else Util.RED)
	if big:
		_body.scale = Vector3.ONE * 1.14
	elif kind == RUSHER:
		_body.scale = Vector3(0.9, 0.95, 0.9)
	_rig.add_child(_body)
	_visor_mat = _body.eye_mat
	if kind == RUSHER:
		return
	_gun = _build_caster()
	_body.weapon_socket.add_child(_gun)
	if big:
		_gun.scale = Vector3.ONE * 1.2
		_armour_mat = Mats.shell(Color(0.55, 0.65, 0.85))
		_armour = Util.capsule(r + 0.12, hgt + 0.2, null)
		_armour.material_override = _armour_mat
		_armour.position.y = hgt * 0.5
		_armour.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rig.add_child(_armour)
		_marker_mat = Util.xray(Color.WHITE, 0.9)
		_marker = MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.3, 0.3, 0.05)
		_marker.mesh = pm
		_marker.material_override = _marker_mat
		_marker.position.y = hgt + 0.55
		_marker.rotation.z = PI
		add_child(_marker)


## A stone gargoyle crouched on a pedestal; its head tracks and spits rounds.
func _build_turret(cs: CollisionShape3D) -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 1.6
	cs.shape = cyl
	cs.position.y = 0.8
	_visor_mat = Util.glow(Util.RED, 3.0)
	var stone := Mats.marble()
	var ped := Util.box(Vector3(0.9, 0.8, 0.9), Mats.trim())
	ped.position.y = 0.4
	add_child(ped)
	var top := Util.box(Vector3(1.0, 0.1, 1.0), Mats.trim())
	top.position.y = 0.85
	add_child(top)
	var dark := Util.mat(Color(0.2, 0.2, 0.22), 0.0, 1.0, 0.6)
	var body := Util.sphere(0.32, dark)
	body.scale = Vector3(1, 0.85, 1.2)
	body.position = Vector3(0, 1.1, 0.05)
	_rig.add_child(body)
	for s in [-1.0, 1.0]:
		var wing := Util.box(Vector3(0.05, 0.55, 0.5), dark)
		wing.position = Vector3(0.3 * s, 1.35, 0.2)
		wing.rotation = Vector3(-0.4, 0, 0.5 * s)
		_rig.add_child(wing)
		var claw := Util.box(Vector3(0.1, 0.25, 0.12), dark)
		claw.position = Vector3(0.18 * s, 0.98, -0.3)
		_rig.add_child(claw)
		var horn := Util.cylinder(0.04, 0.22, stone, 5)
		(horn.mesh as CylinderMesh).top_radius = 0.0
		horn.position = Vector3(0.12 * s, 1.58, -0.18)
		horn.rotation = Vector3(-0.6, 0, 0.4 * s)
		_rig.add_child(horn)
	var head := Util.sphere(0.2, dark)
	head.scale = Vector3(1, 0.9, 1.15)
	head.position = Vector3(0, 1.38, -0.28)
	_rig.add_child(head)
	var jaw := Util.box(Vector3(0.24, 0.08, 0.2), dark)
	jaw.position = Vector3(0, 1.24, -0.42)
	_rig.add_child(jaw)
	for s in [-1.0, 1.0]:
		var eye := Util.box(Vector3(0.07, 0.03, 0.03), _visor_mat)
		eye.position = Vector3(0.07 * s, 1.42, -0.48)
		_rig.add_child(eye)
	var maw := Util.sphere(0.05, _visor_mat)
	maw.position = Vector3(0, 1.28, -0.5)
	_rig.add_child(maw)
	_gun = Node3D.new()
	_rig.add_child(_gun)


func reset() -> void:
	alive = true
	armed = kind != RUSHER
	stunned = 0.0
	knock = Vector3.ZERO
	cracked = false
	charging = false
	yaw = home_yaw
	visible = true
	collision_layer = Util.L_ENEMY
	global_position = start_pos
	_net_pos = start_pos
	_net_yaw = yaw
	velocity = Vector3.ZERO
	_next_fire = randf_range(1.2, fire_interval + 0.6)
	_rig.rotation = Vector3(0, yaw, 0)
	_rig.scale = Vector3.ONE
	_rig.position = Vector3.ZERO
	if _body:
		_body.set_highlight(false)
		_targeted = false
	if _gun:
		_gun.visible = true
	_refresh_look()


func eye() -> Vector3:
	return global_position + Vector3(0, 1.25 if kind == TURRET else 1.5, 0)


func chest() -> Vector3:
	return global_position + Vector3(0, 1.2, 0)


func facing() -> Vector3:
	return Util.dir_of(yaw)


func muzzle() -> Vector3:
	return global_position + Vector3(0, 1.22, 0) + facing() * 0.75


## Capsule used for bullet hit tests: [y0, y1, radius].
func hit_capsule() -> Array:
	if kind == TURRET:
		return [0.3, 1.5, 0.5]
	if kind == ANCHOR:
		return [0.3, 1.8, 0.55]
	return [0.3, 1.6, 0.45]


# --- Host AI --------------------------------------------------------------------

func host_tick(delta: float, world: Node) -> void:
	if not alive:
		return
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if stunned > 0.0:
		stunned -= delta
		charging = false
		if kind != TURRET:
			velocity.x = knock.x
			velocity.z = knock.z
			knock = knock.move_toward(Vector3.ZERO, KNOCK_DRAG * delta)
			move_and_slide()
		return
	if kind == TURRET:
		yaw = home_yaw + sin(Net.now() * 0.7 + id) * 1.1
		_tick_fire(delta, world, null)
		return

	var target: Node3D = world.nearest_player(global_position)
	if target == null:
		charging = false
		move_and_slide()
		return
	var to := Util.flat(target.global_position - global_position)
	var dist := to.length()
	var los: bool = world.has_los(eye(), target.global_position + Vector3(0, Util.CHEST_H, 0))
	if kind == RUSHER:
		_rush(delta, target, to, dist, los)
	elif armed:
		if los:
			yaw = lerp_angle(yaw, Util.yaw_of(to), 1.0 - exp(-8.0 * delta))
		if moves and (not los or dist > STOP_RANGE):
			_follow(delta, target.global_position, not los, MOVE_SPEED)
		elif moves and dist > 0.01:
			_strafe(delta, to / dist)
		_tick_fire(delta, world, target if los and dist < FIRE_RANGE else null)
	else:
		# Disarmed: back away from the nearest player with hands up.
		charging = false
		if moves and dist < 4.0 and dist > 0.01:
			var away := -to / dist
			if room.walkable(global_position + away * 0.8):
				velocity.x = away.x * MOVE_SPEED * 0.6
				velocity.z = away.z * MOVE_SPEED * 0.6
		yaw = lerp_angle(yaw, Util.yaw_of(to), 1.0 - exp(-6.0 * delta))
	move_and_slide()


## Rusher: path in, then sprint straight at the target once it is close, in sight and the
## floor ahead holds (so a lunge never carries it into a chasm).
func _rush(delta: float, target: Node3D, to: Vector3, dist: float, los: bool) -> void:
	charging = los and dist < LUNGE_RANGE
	if not moves:
		return
	var d := to / maxf(dist, 0.01)
	if charging and room.walkable(global_position + d * Util.TILE):
		velocity.x = d.x * RUSH_SPEED
		velocity.z = d.z * RUSH_SPEED
		yaw = lerp_angle(yaw, Util.yaw_of(d), 1.0 - exp(-12.0 * delta))
	else:
		_follow(delta, target.global_position, true, RUSH_SPEED)


## Cultists in range keep sidestepping, flipping direction now and then or at an obstacle.
func _strafe(delta: float, toward: Vector3) -> void:
	_strafe_t -= delta
	var side := Vector3(-toward.z, 0, toward.x) * _strafe_dir
	if _strafe_t <= 0.0 or not room.walkable(global_position + side * Util.TILE * 0.6):
		_strafe_dir = -_strafe_dir
		_strafe_t = randf_range(0.8, 2.2)
		return
	velocity.x = side.x * STRAFE_SPEED
	velocity.z = side.z * STRAFE_SPEED


func touches(pos: Vector3) -> bool:
	if not alive or kind != RUSHER or stunned > 0.0:
		return false
	var d := pos - global_position
	return Util.flat(d).length() < CONTACT and absf(d.y) < 1.2


func _follow(delta: float, goal: Vector3, face_path: bool, speed: float) -> void:
	_repath -= delta
	if _repath <= 0.0 or _path_i >= _path.size():
		_repath = 0.4
		_path = room.path(global_position, goal)
		_path_i = 1
	if _path_i >= _path.size():
		return
	var to := Util.flat(_path[_path_i] - global_position)
	if to.length() < 0.25:
		_path_i += 1
		return
	var d := to.normalized()
	velocity.x = d.x * speed
	velocity.z = d.z * speed
	if face_path:
		yaw = lerp_angle(yaw, Util.yaw_of(d), 1.0 - exp(-8.0 * delta))


func _tick_fire(delta: float, world: Node, target: Node3D) -> void:
	if kind != TURRET and target == null:
		charging = false
		_next_fire = maxf(_next_fire, 0.7)
		return
	_next_fire -= delta
	charging = _next_fire < CHARGE_TIME
	if _next_fire > 0.0:
		return
	_next_fire = fire_interval if kind != TURRET else 1.3
	charging = false
	var dir := facing()
	if target:
		dir = (target.global_position + Vector3(0, Util.CHEST_H, 0) - muzzle()).normalized()
	world.host_enemy_fire(self, muzzle(), dir)


func flags() -> int:
	return (F_ARMED if armed else 0) | (F_STUNNED if stunned > 0.0 else 0) \
		| (F_CRACKED if cracked else 0) | (F_CHARGING if charging else 0)


# --- Client sync and visuals ---------------------------------------------------

func apply_net(pos: Vector3, net_yaw: float, f: int) -> void:
	_net_pos = pos
	_net_yaw = net_yaw
	armed = (f & F_ARMED) != 0
	stunned = 0.2 if (f & F_STUNNED) != 0 else 0.0
	cracked = (f & F_CRACKED) != 0
	charging = (f & F_CHARGING) != 0


func _process(delta: float) -> void:
	if not alive:
		return
	if not Net.is_host():
		global_position = global_position.lerp(_net_pos, 1.0 - exp(-15.0 * delta))
		yaw = lerp_angle(yaw, _net_yaw, 1.0 - exp(-15.0 * delta))
	_rig.rotation.y = yaw
	if _body:
		var k := 1.0 - exp(-8.0 * delta)
		_body.aim = lerpf(_body.aim, 1.0 if (armed or charging) and stunned <= 0.0 else 0.0, k)
		_body.hands_up = lerpf(_body.hands_up, 1.0 if _disarmed() and stunned <= 0.0 else 0.0, k)
		_body.stagger = 1.0 if stunned > 0.0 else 0.0
	else:
		_rig.rotation.z = sin(Time.get_ticks_msec() / 60.0) * 0.12 if stunned > 0.0 else 0.0
	_refresh_look()


func _disarmed() -> bool:
	return not armed and kind != RUSHER


func _refresh_look() -> void:
	if _gun:
		_gun.visible = armed or kind == TURRET
	var v := 3.0
	if charging:
		v = 6.0 + 4.0 * sin(Time.get_ticks_msec() / 30.0)
	elif stunned > 0.0:
		v = 0.5 + randf() * 2.0
	elif _disarmed():
		v = 1.0
	_visor_mat.albedo_color = (Util.AMBER if kind == RUSHER else Util.RED) * v
	if _armour_mat:
		_armour.visible = alive
		if cracked:
			_armour_mat.set_shader_parameter("tint", Util.AMBER)
			_armour_mat.set_shader_parameter("energy", 2.0 + sin(Time.get_ticks_msec() / 80.0))
			_marker_mat.albedo_color = Color(Util.AMBER, 0.95)
		else:
			_armour_mat.set_shader_parameter("tint", Color(0.55, 0.65, 0.85))
			_armour_mat.set_shader_parameter("energy", 0.8)
			_marker_mat.albedo_color = Color(1, 1, 1, 0.9)
		_marker.rotation.y += 0.03


## Local-only highlight when this enemy sits on the aim or recall line.
func set_targeted(on: bool, color := Util.AMBER) -> void:
	var t := on and alive
	if t == _targeted and color == _target_color:
		return
	_targeted = t
	_target_color = color
	if _body:
		_body.set_highlight(t, color)


func on_disarmed(by_pull: bool) -> void:
	armed = false
	if _gun and kind != TURRET:
		_gun.visible = false
		Fx.burst(get_parent(), _gun.global_position, Util.CYAN if by_pull else Util.RED, 8, 2.0, 0.06, 0.4, false)


func on_killed(dir: Vector3, cause: String) -> void:
	if not alive:
		return
	alive = false
	collision_layer = 0
	charging = false
	set_targeted(false)
	_refresh_look()
	var pos := chest()
	if cause == "pincer":
		_shatter_pincer(dir)
		return
	Fx.burst(get_parent(), pos, Util.RED, 16, 4.0, 0.08, 0.5, false)
	Fx.flash(get_parent(), pos, Util.RED)
	Game.sfx("enemy_die", false, pos)
	var fall := Util.flat(dir).normalized()
	if fall.length() < 0.1:
		fall = -facing()
	var axis := Vector3.UP.cross(fall).normalized()
	var tw := create_tween()
	tw.tween_property(_rig, "global_basis", Basis(axis, PI * 0.5) * _rig.global_basis, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.6)
	tw.tween_property(_rig, "scale", Vector3(1, 0.05, 1), 0.3)
	tw.tween_callback(func() -> void: visible = false)


func _shatter_pincer(dir: Vector3) -> void:
	var pos := chest()
	var side := Vector3.UP.cross(Util.flat(dir).normalized())
	if side.length() < 0.1:
		side = Vector3.RIGHT
	for i in 2:
		var c := Util.AMBER if i == 0 else Util.CYAN
		var half := Util.box(Vector3(0.5, 2.0, 0.6), Util.glow(c, 3.0))
		get_parent().add_child(half)
		half.global_position = global_position + Vector3(0, 1.0, 0)
		var s := side * (1.0 if i == 0 else -1.0)
		var tw := half.create_tween().set_parallel()
		tw.tween_property(half, "global_position", half.global_position + s * 2.5 + Vector3(0, 0.5, 0), 0.6) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(half, "rotation", Vector3(randf(), randf(), randf()) * 2.0, 0.6)
		tw.tween_property(half, "scale", Vector3.ONE * 0.01, 0.4).set_delay(0.5)
		tw.chain().tween_callback(half.queue_free)
		Fx.burst(get_parent(), pos, c, 20, 6.0, 0.1, 0.7, false)
	Fx.flash(get_parent(), pos, Color.WHITE, 10.0, 10.0, 0.4)
	visible = false
