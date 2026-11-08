class_name Revolver
extends Node3D
## The one revolver and its one round.
## LEON (A) can only fire. NOEL (B) can only recall: the lodged round flies back into the
## cylinder along the line to NOEL's muzzle, hitting everything on the way.
## Pattern: request_X goes to the host, which validates and broadcasts _on_X to everyone.

enum { IN_GUN, FLYING, LODGED }

const SPEED := 45.0
const THROW_SPEED := 15.0
const CATCH_RADIUS := 1.5
const PICKUP_RADIUS := 1.25
const STUCK_TIME := 5.0
const MAX_RANGE := 80.0

var world: World
var holder := ""
var last_holder := "A"
var bullet := IN_GUN
var lodged_pos := Vector3.ZERO
var lodged_normal := Vector3.UP

var body: RigidBody3D
var net_xf := Transform3D.IDENTITY

var _flight := {}
var _thrower := ""
var _throw_t := 0.0
## Host: a throw is in the air and has not been caught yet.
var _throw_live := false
var _steer_eye := Vector3.ZERO
var _steer_dir := Vector3.FORWARD
var _steer_held := false
var _stuck_t := 0.0
var _body_hit_ids := {}

var _body_model: GunModel
var _floor_ring: MeshInstance3D
var _floor_ring_mat: StandardMaterial3D
var _round: MeshInstance3D
var _round_light: OmniLight3D
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _lodged: MeshInstance3D
var _crack: MeshInstance3D
var _crack_mat: StandardMaterial3D
var _beacon: Node3D
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _dot: MeshInstance3D
var _dot_mat: StandardMaterial3D


func _ready() -> void:
	body = RigidBody3D.new()
	body.name = "Body"
	body.collision_layer = Util.L_GUN
	body.collision_mask = Util.L_WORLD | Util.L_GLASS | Util.L_ENEMY
	body.mass = 1.2
	# Fast, flat arc.
	body.gravity_scale = 0.45
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.body_entered.connect(_on_body_hit)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 0.25, 0.6)
	cs.shape = shape
	body.add_child(cs)
	_body_model = GunModel.new()
	_body_model.scale = Vector3.ONE * 1.3
	body.add_child(_body_model)
	if not Net.is_host():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	add_child(body)

	_floor_ring_mat = Util.glow(Util.AMBER, 2.0, 0.5)
	_floor_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.52
	ring_mesh.outer_radius = 0.58
	ring_mesh.rings = 40
	_floor_ring.mesh = ring_mesh
	_floor_ring.material_override = _floor_ring_mat
	_floor_ring.scale = Vector3(1, 0.15, 1)
	_floor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor_ring.top_level = true
	add_child(_floor_ring)

	_round = Util.sphere(0.06, Util.glow(Util.WHITE_HOT, 8.0))
	_round.top_level = true
	_round.visible = false
	_round_light = OmniLight3D.new()
	_round_light.omni_range = 4.0
	_round_light.light_energy = 3.0
	_round.add_child(_round_light)
	add_child(_round)
	_trail_mat = Util.glow(Util.AMBER, 4.0, 0.8)
	_trail = Util.box(Vector3.ONE, _trail_mat)
	_trail.top_level = true
	_trail.visible = false
	add_child(_trail)

	_lodged = Util.sphere(0.05, Util.glow(Util.WHITE_HOT, 6.0))
	_lodged.top_level = true
	_lodged.visible = false
	add_child(_lodged)
	_crack_mat = Util.glow(Util.AMBER, 3.0, 0.9)
	_crack = Util.cylinder(0.2, 0.01, _crack_mat, 7)
	_crack.top_level = true
	_crack.visible = false
	add_child(_crack)
	_beacon = Node3D.new()
	_beacon.top_level = true
	_beacon.visible = false
	add_child(_beacon)
	var beam := Util.cylinder(0.025, 2.2, Util.xray(Util.WHITE_HOT, 0.35), 6)
	beam.position.y = 1.1
	_beacon.add_child(beam)
	var diamond := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.3, 0.05)
	diamond.mesh = pm
	diamond.material_override = Util.xray(Util.WHITE_HOT, 0.95)
	diamond.position.y = 2.35
	diamond.rotation.z = PI
	_beacon.add_child(diamond)

	_line_mat = Util.glow(Util.AMBER, 3.0, 0.55)
	_line = Util.box(Vector3.ONE, _line_mat)
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_dot_mat = Util.glow(Util.AMBER, 4.0, 0.9)
	_dot = Util.sphere(0.06, _dot_mat)
	_dot.top_level = true
	add_child(_dot)


func is_loaded() -> bool:
	return bullet == IN_GUN


## Called on every PC when a room (re)starts.
func reset_to(pos: Vector3) -> void:
	holder = ""
	last_holder = Util.A
	bullet = IN_GUN
	_flight = {}
	_stuck_t = 0.0
	_throw_live = false
	_round.visible = false
	_trail.visible = false
	_lodged.visible = false
	_crack.visible = false
	_beacon.visible = false
	var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), pos + Vector3(0, 0.1, 0))
	body.global_transform = xf
	net_xf = xf
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	if Net.is_host():
		body.freeze = false
	_refresh_body()


# --- Tracing ------------------------------------------------------------------

## Follow a straight bullet line. Returns {end, normal, hits} where hits are
## [distance, 0 (enemy) / 1 (glass) / 2 (rune), id], sorted by distance.
## Breakables and runes never stop the round. pad widens the enemy hit radius (chain tiers).
func trace(from: Vector3, to: Vector3, stop_at_world: bool, pad := 0.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var end := to
	var normal := (from - to).normalized()
	if stop_at_world:
		var q := PhysicsRayQueryParameters3D.create(from, to, Util.L_WORLD)
		var hit := space.intersect_ray(q)
		if hit:
			end = hit.position
			normal = hit.normal
	var hits := []
	var exclude: Array[RID] = []
	for i in 8:
		var gq := PhysicsRayQueryParameters3D.create(from, end, Util.L_GLASS, exclude)
		var gh := space.intersect_ray(gq)
		if gh.is_empty():
			break
		exclude.append(gh.rid)
		if gh.collider is Glass:
			hits.append([from.distance_to(gh.position), 1, (gh.collider as Glass).id])
	if world.room:
		for e in world.room.enemies:
			if not e.alive:
				continue
			var cap := e.hit_capsule()
			var res := Util.segment_vs_capsule(from, end, e.global_position, cap[0], cap[1])
			if res[0] < cap[2] + pad:
				hits.append([res[1], 0, e.id])
		for d in world.room.devices:
			if not d.is_rune():
				continue
			var c := d.rune_center()
			var res := Util.segment_vs_capsule(from, end, c - Vector3(0, 0.3, 0), 0.0, 0.6)
			if res[0] < Device.RUNE_RADIUS:
				hits.append([res[1], 2, d.id])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return {"end": end, "normal": normal, "hits": hits}


func recall_blocked(to: Vector3) -> bool:
	var from := lodged_pos + lodged_normal * 0.08
	var q := PhysicsRayQueryParameters3D.create(from, to, Util.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.position.distance_to(to) > 0.3


# --- Requests (any peer -> host) -----------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_fire(role: String, origin: Vector3, dir: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not world.playing():
		return
	if role != Util.A or holder != role or bullet != IN_GUN or not world.get_player(role).alive:
		return
	dir = dir.normalized()
	var level := world.chain.host_release()
	var tr := trace(origin, origin + dir * MAX_RANGE, true, Chain.hit_pad(level))
	world.host_new_cycle()
	_on_fire.rpc(origin, tr.end, tr.normal, tr.hits, level)


@rpc("any_peer", "call_local", "reliable")
func request_recall(role: String, muzzle: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not world.playing():
		return
	if role != Util.B or holder != role or bullet != LODGED or not world.get_player(role).alive:
		return
	if recall_blocked(muzzle):
		world.toast_to(role, "No line to the round")
		return
	var level := world.chain.host_release()
	# A steered round finds its hits as it flies.
	var hits: Array = [] if level >= Chain.STEER else trace(lodged_pos, muzzle, false, Chain.hit_pad(level)).hits
	_on_recall.rpc(lodged_pos, muzzle, hits, level)


## NOEL's aim while a steerable recall is in flight.
@rpc("any_peer", "call_local", "unreliable_ordered")
func request_steer(role: String, eye: Vector3, dir: Vector3, held: bool) -> void:
	if not Net.is_host() or not Net.sender_is(role) or role != Util.B:
		return
	_steer_eye = eye
	_steer_dir = dir.normalized()
	_steer_held = held


@rpc("any_peer", "call_local", "reliable")
func request_throw(role: String, origin: Vector3, dir: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or world.frozen:
		return
	if holder != role or bullet == FLYING or not world.get_player(role).alive:
		return
	_on_throw.rpc(role, origin, dir.normalized() * THROW_SPEED + Vector3.UP * 1.5)


# --- Broadcasts (host -> everyone) -----------------------------------------------

@rpc("authority", "call_local", "reliable")
func _on_fire(origin: Vector3, end: Vector3, normal: Vector3, hits: Array, level: int) -> void:
	bullet = FLYING
	var shooter := world.get_player(Util.A)
	var vis_from := shooter.muzzle()
	if shooter.controlled:
		shooter.vm.anim_fire()
		shooter.vm.set_loaded(false)
		world.shake(0.25)
	_start_flight(origin, end, normal, hits, false, vis_from, level)
	Fx.flash(world.fx, vis_from, Util.AMBER, 6.0, 6.0, 0.12)
	Game.sfx("fire", false, vis_from)
	if level >= Chain.STEER:
		world.chain.slow_mo()


@rpc("authority", "call_local", "reliable")
func _on_recall(from: Vector3, to: Vector3, hits: Array, level: int) -> void:
	bullet = FLYING
	_lodged.visible = false
	_beacon.visible = false
	# The hole un-cracks: debris gathers back into the wall.
	Fx.burst(world.fx, from, Util.CYAN, 14, 3.0, 0.05, 0.35, true)
	Fx.ring(world.fx, from, Util.CYAN, 0.6, 0.35, true, lodged_normal)
	var tw := _crack.create_tween()
	tw.tween_property(_crack, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(func() -> void:
		_crack.visible = false
		_crack.scale = Vector3.ONE)
	var p := world.get_player(Util.B)
	if p.controlled:
		p.vm.anim_recall_start()
	_start_flight(from, to, Vector3.ZERO, hits, true, from, level)
	Game.sfx("fire", true, from)


func _start_flight(from: Vector3, to: Vector3, normal: Vector3, hits: Array, recall: bool, vis_from: Vector3,
		level: int) -> void:
	var length := maxf(from.distance_to(to), 0.01)
	_flight = {
		"from": from, "to": to, "normal": normal, "dir": (to - from) / length, "length": length,
		"d": 0.0, "hits": hits, "next_hit": 0, "recall": recall, "vis_from": vis_from,
		"level": level, "kills": 0, "steer": recall and level >= Chain.STEER,
		"pos": from, "tail": from, "t": 0.0, "hit": {},
	}
	_steer_held = false
	_round.visible = true
	_round.global_position = vis_from
	var c := Util.CYAN if recall else Util.AMBER
	_round_light.light_color = c
	_trail_mat.albedo_color = Color(c * 4.0, 0.8)
	_trail.visible = true


@rpc("authority", "call_local", "reliable")
func _on_throw(role: String, origin: Vector3, vel: Vector3) -> void:
	last_holder = role
	holder = ""
	_thrower = role
	_throw_t = Net.now()
	_throw_live = true
	_stuck_t = 0.0
	_body_hit_ids.clear()
	var xf := Transform3D(Basis.looking_at(vel.normalized()), origin)
	body.global_transform = xf
	net_xf = xf
	if Net.is_host():
		body.freeze = false
		body.linear_velocity = vel
		# NOEL's throw spins the other way.
		body.angular_velocity = body.global_basis.x * (-18.0 if role == Util.A else 18.0)
	var p := world.get_player(role)
	if p.controlled:
		p.vm.anim_throw()
	Game.sfx("throw", role == Util.B, origin)
	_refresh_body()


@rpc("authority", "call_local", "reliable")
func _on_catch(role: String, how: String) -> void:
	var from := body.global_position
	holder = role
	last_holder = role
	_throw_live = false
	if Net.is_host():
		body.freeze = true
	var p := world.get_player(role)
	if how == "rewind":
		Fx.tracer(world.fx, from, p.chest(), Util.CYAN, 0.6, 0.05)
		Fx.burst(world.fx, from, Util.CYAN, 10, 2.0, 0.05, 0.4, true)
		Game.sfx("rewind", false, p.chest())
	if p.controlled:
		p.vm.anim_catch()
	Game.sfx("catch", role == Util.B, p.chest())
	_refresh_body()


@rpc("authority", "call_local", "reliable")
func _on_drop(pos: Vector3) -> void:
	if holder != "":
		last_holder = holder
	holder = ""
	_thrower = ""
	var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), pos)
	body.global_transform = xf
	net_xf = xf
	if Net.is_host():
		body.freeze = false
		body.linear_velocity = Vector3.ZERO
	_refresh_body()


## Put the gun straight into an agent's hand (start of the run). Runs on every peer.
func give(role: String) -> void:
	holder = role
	last_holder = role
	if Net.is_host():
		body.freeze = true
	_refresh_body()


func host_drop(pos: Vector3) -> void:
	if holder != "":
		_on_drop.rpc(pos)


func apply_net(xf: Transform3D) -> void:
	net_xf = xf


func _refresh_body() -> void:
	body.visible = holder == ""
	for p: Player in world.players.values():
		p.show_gun(holder == p.role)


# --- Per frame ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if world == null or world.room == null:
		return
	if not _flight.is_empty() and not world.frozen:
		if _flight.steer:
			_send_steer()
			if Net.is_host():
				_host_steer(delta)
		else:
			_advance(delta)
	if Net.is_host() and holder == "" and world.playing():
		_host_loose(delta)


func _advance(delta: float) -> void:
	var f := _flight
	f.d = minf(f.d + SPEED * Chain.speed_scale(f.level, f.recall) * delta, f.length)
	var d: float = f.d
	var length: float = f.length
	if Net.is_host():
		var hits: Array = f.hits
		while f.next_hit < hits.size() and hits[f.next_hit][0] <= d:
			f.next_hit += 1
			_host_hit(f, hits[f.next_hit - 1])
	# Visual position. A recalled round homes onto NOEL's actual muzzle.
	var vis_to: Vector3 = f.to
	if f.recall:
		vis_to = world.get_player(Util.B).muzzle()
	var pos: Vector3 = (f.vis_from as Vector3).lerp(vis_to, d / length)
	_round.global_position = pos
	var tail: Vector3 = (f.vis_from as Vector3).lerp(vis_to, maxf(d - 5.0, 0.0) / length)
	Util.place_beam(_trail, tail, pos, 0.03)
	if d >= length:
		_land(vis_to)


## Host: the round reached something on its line. Kills feed the chain.
func _host_hit(f: Dictionary, h: Array) -> void:
	var actor := Util.B if f.recall else Util.A
	if h[1] == 0:
		if world.host_bullet_hit(h[2], f.dir, f.recall):
			f.kills += 1
			world.chain.host_add()
	elif h[1] == 1:
		world.host_set_glass(h[2], false, actor)
	elif h[1] == 2:
		world.host_rune_hit(h[2], f.recall)


func _land(vis_to: Vector3) -> void:
	var f := _flight
	_flight = {}
	_round.visible = false
	_trail.visible = false
	if f.recall:
		if not f.steer:
			Fx.tracer(world.fx, f.vis_from, vis_to, Util.CYAN, 0.6, 0.03)
		bullet = IN_GUN
		var p := world.get_player(Util.B)
		if p.controlled:
			p.vm.anim_recall_end()
			p.vm.set_loaded(true)
			world.shake(0.15)
		Game.sfx("lodge", true, vis_to)
	else:
		Fx.tracer(world.fx, f.vis_from, f.to, Util.AMBER, 0.6, 0.03)
		bullet = LODGED
		lodged_normal = f.normal
		lodged_pos = (f.to as Vector3) + lodged_normal * 0.02
		_lodged.global_position = lodged_pos
		_lodged.visible = true
		_crack.visible = true
		_crack.scale = Vector3.ONE
		_crack.global_position = lodged_pos
		var up := Vector3.UP if absf(lodged_normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		_crack.global_basis = Basis.looking_at(lodged_normal, up) * Basis(Vector3.RIGHT, PI * 0.5)
		_beacon.visible = true
		_beacon.global_position = lodged_pos
		Fx.burst(world.fx, lodged_pos, Util.AMBER, 12, 3.0, 0.05, 0.35, false)
		Game.sfx("lodge", false, lodged_pos)
	if Net.is_host():
		_host_settle(f)


## Host: a high chain blasts where the flight ends; a flight that killed nothing breaks the chain.
func _host_settle(f: Dictionary) -> void:
	if f.level >= Chain.BLAST:
		var at := world.get_player(Util.B).global_position + Vector3(0, 0.5, 0) if f.recall \
			else lodged_pos + lodged_normal * 0.3
		f.kills += world.chain.host_blast(at, f.recall)
	if f.kills == 0:
		world.chain.host_break()


## NOEL's PC streams their aim to the host while a steerable recall flies.
func _send_steer() -> void:
	var lp := world.local_player()
	if lp == null or lp.role != Util.B:
		return
	var held := Input.is_action_pressed("primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	request_steer.rpc_id(1, Util.B, lp.eye(), lp.aim_dir(), held)


## Host: while NOEL holds LMB the round slows and bends towards NOEL's aim line, then it rips home.
func _host_steer(delta: float) -> void:
	var f := _flight
	f.t += delta
	var muzzle := world.get_player(Util.B).muzzle()
	var pos: Vector3 = f.pos
	var dir: Vector3 = f.dir
	var steering: bool = _steer_held and f.t < Chain.STEER_TIME and pos.distance_to(muzzle) > Chain.STEER_LEAD
	var step := (Chain.STEER_SPEED if steering else SPEED * Chain.speed_scale(f.level, true)) * delta
	if steering:
		var goal := _steer_eye + _steer_dir * maxf(_steer_eye.distance_to(pos) - Chain.STEER_LEAD, 0.0)
		var want := (goal - pos).normalized()
		var angle := dir.angle_to(want)
		if angle > 0.001:
			dir = dir.slerp(want, minf(Chain.STEER_TURN * delta / angle, 1.0)).normalized()
	else:
		dir = (muzzle - pos).normalized()
	var home := not steering and pos.distance_to(muzzle) <= step
	var next := muzzle if home else pos + dir * step
	for h: Array in trace(pos, next, false, Chain.hit_pad(f.level)).hits:
		var key := "%d:%d" % [h[1], h[2]]
		if not f.hit.has(key):
			f.hit[key] = true
			_host_hit(f, h)
	f.pos = next
	f.dir = dir
	_show_round(next)
	if home:
		_on_steer_home.rpc()
	elif not Game.solo:
		_on_round_at.rpc(next)


func _show_round(pos: Vector3) -> void:
	var f := _flight
	f.tail = pos + ((f.tail as Vector3) - pos).limit_length(3.0)
	_round.global_position = pos
	Util.place_beam(_trail, f.tail, pos, 0.03)


@rpc("authority", "unreliable_ordered")
func _on_round_at(pos: Vector3) -> void:
	if not _flight.is_empty() and _flight.steer:
		_show_round(pos)


@rpc("authority", "call_local", "reliable")
func _on_steer_home() -> void:
	if not _flight.is_empty():
		_land(world.get_player(Util.B).muzzle())


func _host_loose(delta: float) -> void:
	var pos := body.global_position
	var since := Net.now() - _throw_t
	var in_air := body.linear_velocity.length() > 3.0 and _thrower != ""
	# The throw touched the floor before anyone caught it: a dropped catch.
	if _throw_live and (not in_air or _floor_below(pos, 0.35)):
		_throw_live = false
		world.chain.host_drop()
	for p: Player in world.players.values():
		if not p.alive or not p.present or world.held_prop(p.role) != null:
			continue
		var may := p.role != _thrower or since > 0.6
		var body_d := Util.segment_vs_capsule(pos, pos, p.global_position, 0.1, 1.9)[0] as float
		if in_air and may and body_d < CATCH_RADIUS:
			_on_catch.rpc(p.role, "catch")
			# A flair catch (airborne, sliding, dashing, vaulting, wall-running) feeds the chain.
			if p.in_flair():
				world.chain.host_add()
			return
		if not in_air and Util.flat(pos - p.global_position).length() < PICKUP_RADIUS \
				and absf(pos.y - p.global_position.y) < 1.6:
			_on_catch.rpc(p.role, "pickup")
			return
	# Fail-safe: the gun rewinds to its last holder if it ends up somewhere unreachable.
	if pos.y < -3.0:
		_stuck_t += delta * 4.0  # down a chasm: rewind quickly
	elif pos.y > 2.6 or not world.room.walkable(pos):
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t > STUCK_TIME:
		_stuck_t = 0.0
		var to := last_holder if world.get_player(last_holder).alive else Util.other(last_holder)
		if world.get_player(to).alive:
			_on_catch.rpc(to, "rewind")


func _floor_below(pos: Vector3, reach: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * reach, Util.L_WORLD | Util.L_GLASS)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _on_body_hit(other: Node) -> void:
	if not Net.is_host() or holder != "" or body.linear_velocity.length() < 4.0:
		return
	if other is Enemy and not _body_hit_ids.has((other as Enemy).id):
		_body_hit_ids[(other as Enemy).id] = true
		world.host_hit_enemy(other, "gun", body.linear_velocity.normalized(), _thrower)
	elif other is Glass and (other as Glass).intact and (other as Glass).fragile():
		world.host_set_glass((other as Glass).id, false, _thrower)


func _process(delta: float) -> void:
	if world == null or world.room == null:
		return
	if not Net.is_host() and holder == "":
		body.global_transform = body.global_transform.interpolate_with(net_xf, 1.0 - exp(-20.0 * delta))
	_floor_ring.visible = holder == ""
	if holder == "":
		_floor_ring.global_position = Vector3(body.global_position.x, 0.02, body.global_position.z)
		var c := Util.AMBER if is_loaded() else Util.CYAN
		_floor_ring_mat.albedo_color = Color(c * 1.6, 0.35 + 0.25 * sin(Time.get_ticks_msec() / 150.0))
	_body_model.set_loaded(is_loaded(), Util.role_color(last_holder))
	if _beacon.visible:
		_beacon.rotation.y += delta * 2.0
	_update_preview()


## Aim line for LEON (local only) and the recall preview (shown to both players).
func _update_preview() -> void:
	var marked := {}
	_preview(marked)
	if world.room:
		for e in world.room.enemies:
			e.set_targeted(marked.has(e.id), marked.get(e.id, Util.AMBER))


func _preview(marked: Dictionary) -> void:
	_line.visible = false
	_dot.visible = false
	if not _flight.is_empty():
		return
	var lp := world.local_player()
	var from: Vector3
	var to: Vector3
	var color: Color
	var hits: Array = []
	if holder == Util.A and bullet == IN_GUN and lp != null and lp.role == Util.A and lp.alive:
		var tr := trace(lp.eye(), lp.eye() + lp.aim_dir() * MAX_RANGE, true, Chain.hit_pad(world.chain.count))
		from = lp.muzzle()
		to = tr.end
		hits = tr.hits
		color = Util.AMBER
	elif holder == Util.B and bullet == LODGED:
		var bp := world.get_player(Util.B)
		if not bp.alive:
			return
		from = lodged_pos
		to = bp.muzzle()
		if recall_blocked(bp.eye()):
			color = Util.RED
		else:
			color = Util.CYAN
			hits = trace(from, bp.eye(), false, Chain.hit_pad(world.chain.count)).hits
	else:
		return
	_line.visible = true
	Util.place_beam(_line, from, to, 0.012)
	_line_mat.albedo_color = Color(color * 3.0, 0.55)
	_dot.visible = true
	_dot.global_position = to if color != Util.CYAN else from
	_dot_mat.albedo_color = Color(color * 4.0, 0.9)
	for h: Array in hits:
		if h[1] == 0:
			marked[h[2]] = color
