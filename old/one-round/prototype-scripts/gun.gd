class_name Gun
extends Node3D
## The one gun and its one bullet. A fires it forward; B recalls it backwards.
## Shots are straight lines on the horizontal plane at Util.BULLET_Y.

signal message(text: String)

enum Bullet { IN_GUN, FLYING, LODGED }

const SPEED := 40.0
const HIT_RADIUS := 0.5
const GRAB_RANGE := 1.8
const MAX_RANGE := 60.0

var level: Level
var holder: Player = null
var bullet_state := Bullet.IN_GUN
var lodged_pos := Vector3.ZERO

var _visual: Node3D
var _stripe_mat: StandardMaterial3D
var _fx: Node3D
var _bullet: MeshInstance3D
var _beacon: MeshInstance3D
var _aim: MeshInstance3D
var _aim_mat: StandardMaterial3D
var _aim_dot: MeshInstance3D
var _aim_dot_mat: StandardMaterial3D
var _flight := {}
var _floor_marker: MeshInstance3D


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var barrel := Util.box(Vector3(0.12, 0.16, 0.6), Util.mat(Color(0.2, 0.2, 0.22)))
	barrel.position.z = -0.15
	_visual.add_child(barrel)
	var grip := Util.box(Vector3(0.1, 0.25, 0.12), Util.mat(Color(0.15, 0.15, 0.17)))
	grip.position = Vector3(0, -0.15, 0.05)
	_visual.add_child(grip)
	_stripe_mat = Util.mat(Util.COLOR_A, 2.0)
	var stripe := Util.box(Vector3(0.14, 0.05, 0.45), _stripe_mat)
	stripe.position = Vector3(0, 0.09, -0.15)
	_visual.add_child(stripe)

	_floor_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.02
	_floor_marker.mesh = disc
	_floor_marker.material_override = Util.unshaded(Color(1, 1, 1), 0.35)
	_floor_marker.position.y = 0.02
	add_child(_floor_marker)

	# World-space effects: not affected by the gun moving between hands.
	_fx = Node3D.new()
	_fx.top_level = true
	add_child(_fx)

	_bullet = Util.sphere(0.13, Util.mat(Color(1.0, 0.95, 0.7), 4.0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.omni_range = 3.0
	light.light_energy = 2.0
	_bullet.add_child(light)
	_bullet.visible = false
	_fx.add_child(_bullet)

	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 3.0
	_beacon.mesh = cyl
	_beacon.material_override = Util.unshaded(Color(1.0, 0.9, 0.5), 0.35)
	_beacon.visible = false
	_fx.add_child(_beacon)

	_aim_mat = Util.unshaded(Util.COLOR_A, 0.6)
	_aim = Util.box(Vector3(0.06, 0.06, 1.0), _aim_mat)
	_aim.visible = false
	_fx.add_child(_aim)
	_aim_dot_mat = Util.unshaded(Util.COLOR_A, 0.8)
	_aim_dot = Util.sphere(0.15, _aim_dot_mat)
	_aim_dot.visible = false
	_fx.add_child(_aim_dot)

	_lie_on_floor()


func is_loaded() -> bool:
	return bullet_state == Bullet.IN_GUN


func try_grab(p: Player) -> void:
	if holder == p:
		_drop()
		return
	if holder != null:
		return
	if Util.flat(global_position - p.global_position).length() <= GRAB_RANGE:
		holder = p
		reparent(p.hand, false)
		transform = Transform3D.IDENTITY
		_visual.position = Vector3.ZERO
		_visual.rotation = Vector3.ZERO


func try_use(p: Player) -> void:
	if holder != p or bullet_state == Bullet.FLYING:
		return
	var forward := p.role == Player.Role.FORWARD
	if bullet_state == Bullet.IN_GUN:
		if forward:
			var from := p.chest()
			_launch(from, trace(from, from + p.aim_dir * MAX_RANGE), false)
		else:
			message.emit("B is inverted and can't fire. Pass the gun to A.")
	else:
		if not forward:
			var res := trace(lodged_pos, p.chest())
			if res.blocked:
				message.emit("Recall blocked. B needs a clear line to the bullet.")
			else:
				_launch(lodged_pos, res, true)
		else:
			message.emit("A can't recall. Pass the gun to B.")


## Follow a straight bullet path. Stops at walls and at shields hit from the front.
## Returns end point, direction, length, enemies hit (in order) and whether it was blocked.
func trace(from: Vector3, to: Vector3) -> Dictionary:
	var dir := Util.flat(to - from)
	var length := dir.length()
	dir = dir.normalized()
	var end := from + dir * length
	var blocked := false

	var q := PhysicsRayQueryParameters3D.create(from, end, Util.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		end = hit.position
		length = from.distance_to(end)
		blocked = true

	var candidates := []
	for e: Enemy in level.enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var rel := Util.flat(e.global_position - from)
		var t := rel.dot(dir)
		if t <= 0.05 or t >= length:
			continue
		if (rel - dir * t).length() > HIT_RADIUS:
			continue
		candidates.append({"enemy": e, "t": t})
	candidates.sort_custom(func(a, b): return a.t < b.t)

	var kills := []
	for c in candidates:
		if c.enemy.blocks(dir):
			length = maxf(c.t - 0.7, 0.0)
			end = from + dir * length
			blocked = true
			break
		kills.append(c)
	return {"end": end, "dir": dir, "length": length, "kills": kills, "blocked": blocked}


func _launch(from: Vector3, res: Dictionary, recall: bool) -> void:
	bullet_state = Bullet.FLYING
	_beacon.visible = false
	_bullet.visible = true
	_bullet.global_position = from
	_flight = {"from": from, "res": res, "d": 0.0, "recall": recall}
	_spawn_tracer(from, res.end, Util.COLOR_B if recall else Util.COLOR_A)


func _process(delta: float) -> void:
	if bullet_state == Bullet.FLYING:
		_advance(delta)
	_floor_marker.visible = holder == null
	if holder == null:
		_visual.rotate_y(delta * 1.5)
		_floor_marker.material_override.albedo_color = Color(Util.COLOR_A if is_loaded() else Util.COLOR_B, 0.3 + 0.15 * sin(Time.get_ticks_msec() / 200.0))
	_stripe_mat.emission = Util.COLOR_A if is_loaded() else Color(0.3, 0.3, 0.3)
	_stripe_mat.albedo_color = _stripe_mat.emission
	_update_aim()
	if _beacon.visible:
		var pulse := 0.25 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
		_beacon.material_override.albedo_color.a = pulse


func _advance(delta: float) -> void:
	var res: Dictionary = _flight.res
	var d: float = minf(_flight.d + SPEED * delta, res.length)
	_flight.d = d
	_bullet.global_position = _flight.from + res.dir * d
	for k in res.kills:
		if k.t <= d and is_instance_valid(k.enemy):
			k.enemy.die()
	if d < res.length:
		return
	if _flight.recall:
		bullet_state = Bullet.IN_GUN
		_bullet.visible = false
	else:
		bullet_state = Bullet.LODGED
		lodged_pos = res.end - res.dir * 0.12
		_bullet.global_position = lodged_pos
		_beacon.global_position = lodged_pos + Vector3(0, 1.5, 0)
		_beacon.visible = true
	_flight = {}


func _update_aim() -> void:
	for e: Enemy in level.enemies:
		if is_instance_valid(e):
			e.set_targeted(false)
	_aim.visible = false
	_aim_dot.visible = false
	if holder == null or bullet_state == Bullet.FLYING:
		return

	var from: Vector3
	var res: Dictionary
	var color: Color
	if holder.role == Player.Role.FORWARD and bullet_state == Bullet.IN_GUN:
		from = holder.chest()
		res = trace(from, from + holder.aim_dir * MAX_RANGE)
		color = Util.COLOR_A
	elif holder.role == Player.Role.INVERTED and bullet_state == Bullet.LODGED:
		from = lodged_pos
		res = trace(from, holder.chest())
		color = Util.COLOR_BLOCKED if res.blocked else Util.COLOR_B
	else:
		return

	_aim.visible = true
	Util.place_beam(_aim, from, res.end)
	_aim_mat.albedo_color = Color(color, 0.6)
	_aim_dot_mat.albedo_color = Color(color, 0.9)
	_aim_dot.global_position = res.end
	_aim_dot.visible = true
	if color != Util.COLOR_BLOCKED:
		for k in res.kills:
			k.enemy.set_targeted(true)


func _drop() -> void:
	var p := holder
	holder = null
	var pos := p.global_position + p.aim_dir * 0.5
	reparent(level, false)
	transform = Transform3D.IDENTITY
	global_position = Vector3(pos.x, 0.0, pos.z)
	_lie_on_floor()


func _lie_on_floor() -> void:
	_visual.position = Vector3(0, 0.12, 0)
	_visual.rotation = Vector3(0, 0, PI / 2)


func _spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var mat := Util.unshaded(color, 0.9)
	var tracer := Util.box(Vector3(0.1, 0.1, 1.0), mat)
	_fx.add_child(tracer)
	Util.place_beam(tracer, from, to)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(tracer.queue_free)
