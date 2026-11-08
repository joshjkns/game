class_name World
extends Node3D
## Root of game.tscn (always at /root/World on both PCs). Owns the room flow and every
## gameplay RPC except the revolver's. The host is authoritative for enemies, props, glass,
## deaths and room flow. Each PC is authoritative for its own player's movement.
## Pattern: request_X (any peer -> host) validates, then _on_X (host -> everyone) applies.

enum State { LOADING, INTRO, PLAY, DEAD, CLEAR }

const SNAP_RATE := 20.0
const ENEMY_BULLET_SPEED := 8.0
const REVERSED_BULLET_SPEED := 13.0
const PROP_THROW_SPEED := 18.0
const UNTHROW_SPEED := 22.0
const PAR_BONUS := [Pickup.GEM, Pickup.GEM, Pickup.COIN, Pickup.COIN, Pickup.COIN]

var room: Room
var room_index := 0
var epoch := 0
var players := {}
var revolver: Revolver
var chain: Chain
var fx: Node3D
var hud: Hud
var cards: Cards
var waves: Waves
var local_role := "A"
var state := State.LOADING
var frozen := true
var room_ready := false
var room_time := 0.0
var room_deaths := 0
var room_pincers := 0
var undie_used := false
var door_open := false
var room_loot := 0
## The waves were cleared within the room's par time.
var par_beaten := false
## Host time until which enemies and their rounds crawl (hourglass pickup).
var slow_until := 0.0
## Test-only: enemy bullets do not kill (set by the autotest).
var invulnerable := false

var _bullets := {}
var _next_bullet_id := 0
var _ready_peers := {}
var _snap_t := 0.0
var _reported := {}
var _host_cd := {}
var _shake := 0.0
var _env: Environment
var _grade: CanvasLayer
var _pickups := {}
var _next_pickup := 0
var _channels := {}
var _crumble_t := {}
var _seal_warned := false


func _ready() -> void:
	Game.world = self
	local_role = Net.my_role if not Game.solo else Util.A
	_build_environment()
	fx = Node3D.new()
	fx.name = "Fx"
	add_child(fx)
	var holder := Node3D.new()
	holder.name = "Players"
	add_child(holder)
	for role: String in [Util.A, Util.B]:
		var p := Player.new()
		p.name = role
		p.role = role
		p.set_multiplayer_authority(1 if Game.solo else Net.peer_for(role))
		p.controlled = role == local_role
		players[role] = p
		holder.add_child(p)
	revolver = Revolver.new()
	revolver.name = "Revolver"
	revolver.world = self
	add_child(revolver)
	chain = Chain.new()
	chain.name = "Chain"
	chain.world = self
	add_child(chain)
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	cards = Cards.new()
	add_child(cards)
	waves = Waves.new()
	waves.name = "Waves"
	waves.world = self
	add_child(waves)
	_apply_grade()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Net.cli.has("autotest"):
		var t: Node = load("res://scripts/autotest.gd").new()
		add_child(t)
	_client_ready.rpc_id(1)


func _exit_tree() -> void:
	if Game.world == self:
		Game.world = null


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.006, 0.005, 0.005)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Cool fill so the shadows read blue against warm torch pools.
	_env.ambient_light_color = Color(0.32, 0.4, 0.6)
	_env.ambient_light_energy = 0.3
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.25
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for i in 7:
		_env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4, 5] else 0.0)
	_env.ssao_enabled = true
	_env.ssao_radius = 1.4
	_env.ssao_intensity = 2.2
	_env.ssao_light_affect = 0.15
	_env.ssr_enabled = true
	_env.ssr_max_steps = 72
	_env.ssr_fade_in = 0.1
	_env.ssr_depth_tolerance = 0.3
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_read_sky_light = false
	_env.sdfgi_bounce_feedback = 0.55
	_env.sdfgi_energy = 1.25
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.15
	_env.ssil_radius = 4.0
	_env.ssil_intensity = 1.0
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_albedo = Color(0.72, 0.74, 0.8)
	_env.volumetric_fog_anisotropy = 0.55
	_env.volumetric_fog_length = 56.0
	_env.volumetric_fog_detail_spread = 0.8
	_env.volumetric_fog_ambient_inject = 0.04
	_env.volumetric_fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	apply_quality()
	Game.quality_changed.connect(_on_quality_changed)
	get_viewport().size_changed.connect(_apply_scaling)


func _on_quality_changed() -> void:
	apply_quality()
	if room:
		room.apply_quality()
	toast("Graphics " + Game.quality, Color.WHITE)


## High: SDFGI bounce light, SSIL, dense volumetric fog lit by GI. Low: none of the GI.
func apply_quality() -> void:
	var high := Game.high_quality()
	_env.sdfgi_enabled = high
	_env.ssil_enabled = high
	_env.volumetric_fog_density = 0.026 if high else 0.018
	_env.volumetric_fog_gi_inject = 0.5 if high else 0.0
	_env.ambient_light_energy = 0.22 if high else 0.4
	_env.ssr_enabled = high
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	_apply_scaling()


## Render 3D at a sane resolution on big (retina) fullscreen windows and upscale with FSR.
func _apply_scaling() -> void:
	var vp := get_viewport()
	var px := float(DisplayServer.window_get_size().y) if DisplayServer.get_name() != "headless" else 720.0
	var target := 1440.0 if Game.high_quality() else 900.0
	var sc := clampf(target / maxf(px, 1.0), 0.5, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc


## NOEL's screen is colder, less saturated, with a faint chromatic edge.
func _apply_grade() -> void:
	var inverted := local_role == Util.B
	_env.adjustment_enabled = inverted
	_env.adjustment_saturation = 0.72
	_env.adjustment_contrast = 1.08
	_env.adjustment_brightness = 0.96
	if _grade == null:
		_grade = CanvasLayer.new()
		_grade.layer = 0
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float e = dot(d, d) * 4.0;
	vec3 c;
	c.r = texture(screen_tex, uv + d * 0.006 * e).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - d * 0.006 * e).b;
	c *= mix(vec3(1.0), vec3(0.86, 1.0, 1.14), 0.7);
	COLOR = vec4(c, 1.0);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		rect.material = m
		_grade.add_child(rect)
		add_child(_grade)
	_grade.visible = inverted


# --- Lookups ------------------------------------------------------------------

func get_player(role: String) -> Player:
	return players[role]


func local_player() -> Player:
	return players.get(local_role)


func playing() -> bool:
	return state == State.PLAY and not frozen


func held_prop(role: String) -> Prop:
	if room == null:
		return null
	for p in room.props:
		if p.holder == role:
			return p
	return null


func nearest_player(pos: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in players.values():
		if not p.alive or not p.present:
			continue
		var d := pos.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Util.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The loose prop closest to the crosshair line, within range and in sight.
func find_prop(eye: Vector3, dir: Vector3, max_range: float) -> Prop:
	if room == null:
		return null
	var best: Prop = null
	var best_off := INF
	for p in room.props:
		if p.holder != "" or p.unthrow_to != "":
			continue
		var to := p.global_position - eye
		var along := to.dot(dir)
		if along <= 0.0 or along > max_range:
			continue
		var off := (to - dir * along).length()
		if off > maxf(0.45, along * 0.09) or off >= best_off:
			continue
		if not has_los(eye, p.global_position):
			continue
		best = p
		best_off = off
	return best


func find_enemy_bullet(eye: Vector3, dir: Vector3, max_range: float) -> EnemyBullet:
	var best: EnemyBullet = null
	var best_off := INF
	for b: EnemyBullet in _bullets.values():
		if b.reversed:
			continue
		var to := b.global_position - eye
		var along := to.dot(dir)
		if along <= 0.0 or to.length() > max_range:
			continue
		var off := (to - dir * along).length()
		if off > maxf(0.6, along * 0.16) or off >= best_off:
			continue
		best = b
		best_off = off
	return best


# --- Room flow ------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _client_ready() -> void:
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_ready_peers[id if id != 0 else 1] = true
	var needed := 1 if Game.solo else 2
	if _ready_peers.size() >= needed and state == State.LOADING:
		_load_room.rpc(Game.room_index, true)


@rpc("authority", "call_local", "reliable")
func _load_room(index: int, intro: bool) -> void:
	epoch += 1
	room_index = index
	Game.room_index = index
	if room:
		room.queue_free()
		remove_child(room)
	for b: EnemyBullet in _bullets.values():
		b.queue_free()
	_bullets.clear()
	for c in fx.get_children():
		c.queue_free()
	room = Room.new()
	room.name = "Room"
	add_child(room)
	room.build(Rooms.ALL[index])
	waves.reset(Rooms.ALL[index])
	for role: String in players:
		var p: Player = players[role]
		var start: Vector3 = room.starts.get(role, room.gun_start)
		p.respawn(start + Vector3(0, 0.05, 0), Vector3(0, 0, -1))
	revolver.reset_to(room.gun_start)
	chain.reset()
	_reported.clear()
	_host_cd.clear()
	_pickups.clear()
	_channels.clear()
	_crumble_t.clear()
	_seal_warned = false
	undie_used = false
	door_open = false
	room_loot = 0
	par_beaten = false
	slow_until = 0.0
	room_time = 0.0
	frozen = true
	room_ready = true
	if intro:
		room_deaths = 0
		room_pincers = 0
	state = State.INTRO
	_end_opening()
	hud.on_room_loaded()
	var ep := epoch
	var wait := 0.7
	if intro and not Game.opening_seen:
		Game.opening_seen = true
		wait = _opening(index)
	elif intro:
		wait = cards.room_intro(index, Rooms.ALL[index])
	else:
		cards.rewind()
	if Net.is_host():
		await get_tree().create_timer(wait).timeout
		if ep == epoch:
			_begin.rpc(ep)


const OPENING := 4.6

## First room of a run: eyes open looking down at your hands. LEON holds the revolver with
## its cylinder open on the one round; it snaps shut and you look up into the room.
func _opening(index: int) -> float:
	revolver.give(Util.A)
	var lp := local_player()
	hud.visible = false
	lp.cinematic = true
	lp.set_look(-1.05)
	lp.vm.anim_opening(OPENING - 1.4)
	cards.eyes_open(OPENING)
	var ep := epoch
	var tw := create_tween()
	tw.tween_interval(OPENING - 1.3)
	tw.tween_method(func(v: float) -> void: if ep == epoch: lp.set_look(v), -1.05, 0.0, 1.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		if ep == epoch:
			_end_opening()
			cards.room_intro(index, Rooms.ALL[index], true))
	return OPENING + 0.6


func _end_opening() -> void:
	hud.visible = true
	cards.close_lids()
	for p: Player in players.values():
		p.cinematic = false


@rpc("authority", "call_local", "reliable")
func _begin(ep: int) -> void:
	if ep != epoch:
		return
	state = State.PLAY
	frozen = false


@rpc("any_peer", "call_local", "reliable")
func request_restart() -> void:
	if not Net.is_host() or state == State.CLEAR or state == State.LOADING:
		return
	_load_room.rpc(room_index, false)


@rpc("authority", "call_local", "reliable")
func _set_frozen(on: bool) -> void:
	frozen = on


# --- Per frame ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if room == null:
		return
	if state == State.PLAY and not frozen:
		room_time += delta
	var ts := time_scale()
	if not frozen:
		for id: int in _bullets.keys():
			var b: EnemyBullet = _bullets.get(id)
			if b and not b.step(delta * ts, self):
				_remove_bullet(id)
	if playing():
		_local_hazards()
		_local_rushers()
	if not Net.is_host():
		return
	if playing():
		for e in room.enemies:
			e.host_tick(delta * ts, self)
		_host_traps_and_falls()
		_host_crumble(delta)
		_host_pickups()
	if state == State.PLAY:
		_host_devices()
	_host_props(delta)
	_host_check_progress()
	_snap_t -= delta
	if _snap_t <= 0.0 and not Game.solo and Net.partner_connected():
		_snap_t = 1.0 / SNAP_RATE
		_send_snapshot()


func _process(delta: float) -> void:
	var lp := local_player()
	if lp and lp.cam:
		_shake = maxf(_shake - delta * 1.5, 0.0)
		lp.cam.h_offset = randf_range(-1, 1) * _shake * 0.08
		lp.cam.v_offset = randf_range(-1, 1) * _shake * 0.08


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _host_check_progress() -> void:
	if state != State.PLAY:
		return
	waves.host_tick()
	if not door_open and waves.cleared():
		if room.exit_channel == 0 or _channels.get(room.exit_channel, false):
			_on_door.rpc(true)
			_host_par_bonus()
		elif not _seal_warned:
			_seal_warned = true
			_toast_all.rpc("Exit sealed — find the trigger", Device.CH_COLORS[room.exit_channel % Device.CH_COLORS.size()])
	if door_open and waves.in_final() and room.alive_enemies() == 0:
		for p: Player in players.values():
			if p.present and (not p.alive or not room.in_lift(p.global_position)):
				return
		var rank := _rank()
		_on_room_clear.rpc(room_time, room_deaths, room_pincers, rank, room_loot)
		var ep := epoch
		await get_tree().create_timer(5.0).timeout
		if ep != epoch:
			return
		if room_index + 1 < Rooms.RUN_LENGTH:
			_load_room.rpc(room_index + 1, true)
		else:
			_on_run_complete.rpc()


func _rank() -> String:
	var par: float = Rooms.ALL[room_index].par
	if room_deaths == 0 and par_beaten:
		return "S"
	if room_deaths <= 1 and room_time <= par * 1.5:
		return "A"
	if room_deaths <= 3:
		return "B"
	return "C"


## Beating par spills gems at the foot of the lift.
func _host_par_bonus() -> void:
	if room_time > Rooms.ALL[room_index].par:
		return
	_on_par_beaten.rpc()
	var mouth := room.lift_rect.get_center()
	host_spawn_pickups(PAR_BONUS, Vector3(mouth.x, 1.0, (room.h - 2) * Util.TILE))


@rpc("authority", "call_local", "reliable")
func _on_par_beaten() -> void:
	par_beaten = true
	hud.toast("Par beaten — bonus loot", Pickup.color_of(Pickup.GEM))


@rpc("authority", "call_local", "reliable")
func _on_door(open: bool) -> void:
	door_open = open
	room.open_door(open)
	Game.sfx("door")
	hud.toast("Exit open", Color(0.3, 1.0, 0.5))


@rpc("authority", "call_local", "reliable")
func _on_room_clear(time: float, deaths: int, pincers: int, rank: String, loot: int) -> void:
	state = State.CLEAR
	frozen = true
	Game.total_time += time
	Game.total_pincers += pincers
	Game.total_loot += loot
	cards.results(Rooms.ALL[room_index], time, deaths, pincers, rank, loot)


@rpc("authority", "call_local", "reliable")
func _on_run_complete() -> void:
	state = State.CLEAR
	frozen = true
	cards.final(Game.total_time, Game.total_deaths, Game.total_pincers, Game.total_loot)
	await get_tree().create_timer(7.0 if Net.is_host() else 6.5).timeout
	Game.quit_to_title("RUN COMPLETE. %d DEATHS, %d PINCERS." % [Game.total_deaths, Game.total_pincers])


# --- Snapshots (host -> client) -------------------------------------------------

func _send_snapshot() -> void:
	var e := PackedFloat32Array()
	for en in room.enemies:
		var p := en.global_position
		e.append_array([p.x, p.y, p.z, en.yaw, float(en.flags())])
	var pr := PackedFloat32Array()
	for p in room.props:
		var o := p.global_position
		var q := p.global_basis.get_rotation_quaternion()
		var hcode := 0.0 if p.holder == "" else (1.0 if p.holder == Util.A else 2.0)
		pr.append_array([o.x, o.y, o.z, q.x, q.y, q.z, q.w, hcode])
	var g := revolver.body.global_transform
	var gq := g.basis.get_rotation_quaternion()
	var gun := PackedFloat32Array([g.origin.x, g.origin.y, g.origin.z, gq.x, gq.y, gq.z, gq.w])
	_snap.rpc(epoch, e, pr, gun)


@rpc("authority", "unreliable_ordered")
func _snap(ep: int, e: PackedFloat32Array, pr: PackedFloat32Array, gun: PackedFloat32Array) -> void:
	if ep != epoch or room == null:
		return
	var n := mini(room.enemies.size(), e.size() / 5)
	for i in n:
		var k := i * 5
		room.enemies[i].apply_net(Vector3(e[k], e[k + 1], e[k + 2]), e[k + 3], int(e[k + 4]))
	var m := mini(room.props.size(), pr.size() / 8)
	for i in m:
		var k := i * 8
		var p := room.props[i]
		p.net_xf = Transform3D(Basis(Quaternion(pr[k + 3], pr[k + 4], pr[k + 5], pr[k + 6])), Vector3(pr[k], pr[k + 1], pr[k + 2]))
		var hc := int(pr[k + 7])
		p.holder = "" if hc == 0 else (Util.A if hc == 1 else Util.B)
	if gun.size() == 7:
		revolver.apply_net(Transform3D(Basis(Quaternion(gun[3], gun[4], gun[5], gun[6])), Vector3(gun[0], gun[1], gun[2])))


# --- Enemy bullets --------------------------------------------------------------

func host_enemy_fire(e: Enemy, origin: Vector3, dir: Vector3) -> void:
	_next_bullet_id += 1
	_on_bullet_spawn.rpc(_next_bullet_id, origin, dir, ENEMY_BULLET_SPEED, e.id, Net.now())


@rpc("authority", "call_local", "reliable")
func _on_bullet_spawn(id: int, origin: Vector3, dir: Vector3, speed: float, shooter: int, t0: float) -> void:
	if room == null:
		return
	var b := EnemyBullet.new()
	b.id = id
	b.dir = dir
	b.speed = speed
	b.shooter = shooter
	fx.add_child(b)
	b.global_position = origin + dir * speed * clampf(Net.now() - t0, 0.0, 0.3)
	_bullets[id] = b
	Fx.flash(fx, origin, Util.RED, 3.0, 4.0, 0.1)
	Game.sfx("enemy_shot", false, origin, -4.0)


func _remove_bullet(id: int) -> void:
	var b: EnemyBullet = _bullets.get(id)
	if b:
		b.queue_free()
		_bullets.erase(id)


@rpc("authority", "call_local", "reliable")
func _on_bullet_gone(id: int) -> void:
	_remove_bullet(id)


@rpc("any_peer", "call_local", "reliable")
func request_reverse(role: String, id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B:
		return
	var p := get_player(role)
	var b: EnemyBullet = _bullets.get(id)
	if b == null or b.reversed or not p.alive or revolver.holder == role:
		return
	if b.global_position.distance_to(p.eye()) > Player.REVERSE_RANGE + 1.5 or not _host_ready(role, "reverse", 2.7):
		return
	var dir := -b.dir
	if b.shooter >= 0 and b.shooter < room.enemies.size():
		var s := room.enemies[b.shooter]
		if s.alive:
			dir = (s.chest() - b.global_position).normalized()
	_on_bullet_reversed.rpc(id, b.global_position, dir, REVERSED_BULLET_SPEED)


@rpc("authority", "call_local", "reliable")
func _on_bullet_reversed(id: int, pos: Vector3, dir: Vector3, speed: float) -> void:
	var b: EnemyBullet = _bullets.get(id)
	if b == null:
		return
	b.reverse(pos, dir, speed)
	Fx.ring(fx, pos, Util.CYAN, 0.8, 0.35, true, dir)
	Fx.burst(fx, pos, Util.CYAN, 10, 2.5, 0.04, 0.3, true)
	Game.sfx("reverse", true, pos)


func host_reversed_hit(b: EnemyBullet, e: Enemy) -> void:
	_on_bullet_gone.rpc(b.id)
	if e.kind == Enemy.ANCHOR:
		_on_deflect.rpc(e.id)
	else:
		host_kill(e, b.dir, "reversed")


## Victim decides: called on the PC that owns the player.
func local_player_hit(p: Player, _dir: Vector3, force := false) -> void:
	if invulnerable and not force:
		return
	if not p.alive or state != State.PLAY or _reported.has(p.role):
		return
	_reported[p.role] = true
	shake(0.6)
	report_death.rpc_id(1, p.role)


# --- Death and un-death ---------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func report_death(role: String) -> void:
	if not Net.is_host() or not Net.sender_is(role) or state != State.PLAY:
		return
	var p := get_player(role)
	if not p.alive:
		return
	var partner := get_player(Util.other(role))
	var as_echo := role == Util.A and not undie_used and partner.alive
	if revolver.holder == role:
		revolver.host_drop(p.global_position + Vector3(0, 0.4, 0))
	var held := held_prop(role)
	if held:
		_host_release_prop(held, Vector3.ZERO, false)
	_on_player_died.rpc(role, as_echo)
	if not as_echo:
		var ep := epoch
		_on_room_failed.rpc()
		await get_tree().create_timer(1.6).timeout
		if ep == epoch:
			_load_room.rpc(room_index, false)


@rpc("authority", "call_local", "reliable")
func _on_player_died(role: String, as_echo: bool) -> void:
	var p := get_player(role)
	p.on_died(as_echo)
	Game.sfx("player_die", role == Util.B, p.chest())
	if as_echo:
		hud.toast("LEON is an echo — NOEL, hold E on them", Util.CYAN)


@rpc("authority", "call_local", "reliable")
func _on_room_failed() -> void:
	state = State.DEAD
	frozen = true
	room_deaths += 1
	Game.total_deaths += 1
	cards.death()


@rpc("any_peer", "call_local", "reliable")
func request_revive(role: String) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B:
		return
	var b := get_player(Util.B)
	var a := get_player(Util.A)
	if undie_used or not b.alive or a.alive or not a.echo:
		return
	if b.global_position.distance_to(a.global_position) > Player.REVIVE_RANGE + 1.0:
		return
	_on_revived.rpc(Util.A)


@rpc("authority", "call_local", "reliable")
func _on_revived(role: String) -> void:
	undie_used = true
	_reported.erase(role)
	var p := get_player(role)
	p.on_revived()
	Game.sfx("player_die", true, p.chest())
	hud.toast("Revived", Util.CYAN)


# --- Enemies ------------------------------------------------------------------

## The revolver round reached an enemy. True if the hit kills it (a pincer kills a moment later).
func host_bullet_hit(id: int, dir: Vector3, recall: bool) -> bool:
	var e := room.enemies[id]
	if not e.alive:
		return false
	if e.kind != Enemy.ANCHOR:
		host_kill(e, dir, "recall" if recall else "fire")
		return true
	if not recall:
		if not e.cracked:
			e.cracked = true
			_on_cracked.rpc(id)
	elif e.cracked:
		host_pincer(e, dir)
		return true
	else:
		_on_deflect.rpc(id)
	return false


## A new forward shot starts a new cycle: uncracked armour heals.
func host_new_cycle() -> void:
	for e in room.enemies:
		if e.cracked:
			e.cracked = false
	for d in room.devices:
		if d.primed:
			_on_primed.rpc(d.id, false)


func host_kill(e: Enemy, dir: Vector3, cause: String) -> void:
	if not e.alive:
		return
	var at := e.global_position
	# call_local runs immediately, so the enemy is dead on the host before this returns.
	_on_enemy_killed.rpc(e.id, dir, cause)
	if at.y > -1.5:
		var drops := [Pickup.COIN, Pickup.COIN]
		if randf() < 0.5:
			drops.append(Pickup.COIN)
		if e.kind == Enemy.ANCHOR:
			drops.append_array([Pickup.GEM, Pickup.ECHO])
		else:
			var roll := randf()
			if roll < 0.22:
				drops.append(Pickup.HOURGLASS)
			elif roll < 0.4 and undie_used:
				drops.append(Pickup.ECHO)
		drops.append_array(chain.bonus_drops(cause))
		host_spawn_pickups(drops, at + Vector3(0, 1.0, 0))


@rpc("authority", "call_local", "reliable")
func _on_enemy_killed(id: int, dir: Vector3, cause: String) -> void:
	if room == null or id >= room.enemies.size():
		return
	room.enemies[id].on_killed(dir, cause)
	hud.enemy_killed()


## Punch, thrown prop, thrown gun or un-thrown prop. First hit disarms, the next one kills.
func host_hit_enemy(e: Enemy, cause: String, dir: Vector3, _actor: String) -> void:
	if not e.alive:
		return
	if e.kind == Enemy.TURRET:
		e.stunned = 2.0
		_on_action.rpc("", "stun", e.chest())
	elif e.armed:
		e.armed = false
		e.stunned = 1.5
		_on_disarmed.rpc(e.id, false)
	elif e.kind == Enemy.ANCHOR:
		e.stunned = 1.5
		_on_action.rpc("", "stun", e.chest())
	else:
		host_kill(e, dir, cause)


@rpc("authority", "call_local", "reliable")
func _on_disarmed(id: int, by_pull: bool) -> void:
	var e := room.enemies[id]
	e.on_disarmed(by_pull)
	if by_pull:
		Fx.tracer(fx, e.chest(), get_player(Util.B).chest(), Util.CYAN, 0.4, 0.03)
	Game.sfx("punch", by_pull, e.chest())


@rpc("authority", "call_local", "reliable")
func _on_cracked(id: int) -> void:
	var e := room.enemies[id]
	e.cracked = true
	Fx.burst(fx, e.chest(), Util.AMBER, 20, 4.0, 0.07, 0.5, false)
	Fx.flash(fx, e.chest(), Util.AMBER, 6.0, 6.0, 0.25)
	Game.sfx("glass", false, e.chest(), -4.0, 0.6)
	hud.toast("Anchor cracked — recall through it", Util.AMBER)


@rpc("authority", "call_local", "reliable")
func _on_deflect(id: int) -> void:
	var e := room.enemies[id]
	Fx.burst(fx, e.chest(), Color.WHITE, 10, 3.0, 0.04, 0.3, false)
	Game.sfx("lodge", false, e.chest(), 0.0, 1.6)
	if e.kind == Enemy.ANCHOR and not e.cracked:
		hud.toast("Anchor holds — LEON shoots first", Color.WHITE)


func host_pincer(e: Enemy, dir: Vector3) -> void:
	room_pincers += 1
	var ep := epoch
	_on_pincer.rpc(e.id)
	await get_tree().create_timer(1.15).timeout
	if ep != epoch:
		return
	host_kill(e, dir, "pincer")
	_set_frozen.rpc(false)


## The co-op finisher: the world freezes and the cut-in slams across both screens.
@rpc("authority", "call_local", "reliable")
func _on_pincer(_id: int) -> void:
	frozen = true
	cards.cutin()
	Game.sfx("pincer")
	shake(0.5)


# --- Hands-free kit ---------------------------------------------------------------

func _host_ready(role: String, key: String, cd: float) -> bool:
	var k := role + key
	var now := Net.now()
	if now < float(_host_cd.get(k, 0.0)):
		return false
	_host_cd[k] = now + cd
	return true


func _hands_free(role: String) -> bool:
	return revolver.holder != role and held_prop(role) == null and get_player(role).alive


@rpc("any_peer", "call_local", "reliable")
func request_punch(role: String, origin: Vector3, dir: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.A or not _hands_free(role):
		return
	var best: Enemy = null
	var best_d := INF
	for e in room.enemies:
		if not e.alive:
			continue
		var to := e.chest() - origin
		var d := to.length()
		if d > Player.PUNCH_RANGE + 0.5 or to.normalized().dot(dir) < 0.55:
			continue
		if d < best_d:
			best_d = d
			best = e
	if best:
		host_hit_enemy(best, "punch", dir, role)
		_on_action.rpc(role, "punch_hit", best.chest())
		return
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * Player.PUNCH_RANGE, Util.L_WORLD | Util.L_GLASS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Glass:
		host_set_glass((hit.collider as Glass).id, false, role)
	else:
		_on_action.rpc(role, "punch", origin + dir)


## A slide into an enemy kicks it off its feet: stunned and knocked back, still armed.
@rpc("any_peer", "call_local", "reliable")
func request_slide_kick(role: String, id: int, dir: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or id < 0 or id >= room.enemies.size():
		return
	var p := get_player(role)
	var e := room.enemies[id]
	if not p.alive or not e.alive or e.global_position.distance_to(p.global_position) > Player.KICK_RANGE + 1.5:
		return
	if not _host_ready(role, "kick%d" % id, Player.KICK_COOLDOWN):
		return
	e.stunned = maxf(e.stunned, Player.KICK_STUN)
	if e.kind != Enemy.TURRET:
		e.knock = Util.flat(dir).normalized() * Player.KICK_FORCE
	_on_action.rpc(role, "kick", e.chest())


## NOEL's pull is a punch played backwards: it yanks the weapon out of an enemy's hands.
@rpc("any_peer", "call_local", "reliable")
func request_pull(role: String, origin: Vector3, dir: Vector3) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B or not _hands_free(role):
		return
	if not _host_ready(role, "pull", Player.PULL_COOLDOWN - 0.3):
		return
	var best: Enemy = null
	var best_off := INF
	for e in room.enemies:
		if not e.alive or e.kind == Enemy.TURRET:
			continue
		var to := e.chest() - origin
		var along := to.dot(dir)
		if along <= 0.0 or along > 14.0:
			continue
		var off := (to - dir * along).length()
		if off > 1.2 or off >= best_off or not has_los(origin, e.chest()):
			continue
		best = e
		best_off = off
	if best == null:
		_on_action.rpc(role, "pull", origin + dir)
		return
	if best.armed:
		best.armed = false
		best.stunned = 1.0
		_on_disarmed.rpc(best.id, true)
	else:
		best.stunned = 1.2
		_on_action.rpc(role, "pull_hit", best.chest())


@rpc("any_peer", "call_local", "reliable")
func request_grab(role: String, id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or not _hands_free(role):
		return
	var p := room.props[id]
	if p.holder != "" or p.unthrow_to != "" or p.global_position.distance_to(get_player(role).eye()) > 4.5:
		return
	p.holder = role
	p.lethal = false
	p.freeze = true
	_on_action.rpc(role, "grab", p.global_position)


@rpc("any_peer", "call_local", "reliable")
func request_throw_prop(role: String, origin: Vector3, dir: Vector3, soft: bool) -> void:
	if not Net.is_host() or not Net.sender_is(role) or frozen:
		return
	var p := held_prop(role)
	if p == null:
		return
	_host_release_prop(p, dir * (3.0 if soft else PROP_THROW_SPEED) + Vector3.UP * 1.2, not soft, origin + dir * 0.7)
	_on_action.rpc(role, "throw_soft" if soft else "throw", origin)


func _host_release_prop(p: Prop, vel: Vector3, lethal: bool, at: Variant = null) -> void:
	var role := p.holder
	p.holder = ""
	p.unthrow_to = ""
	p.thrower = role
	p.lethal = lethal
	p.hit_ids.clear()
	p.freeze = false
	if at != null:
		p.global_position = at
	p.linear_velocity = vel
	p.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)) if lethal else Vector3.ZERO


## NOEL's un-throw: the prop flies from where it is into NOEL's hand, hitting anything in the way.
@rpc("any_peer", "call_local", "reliable")
func request_unthrow(role: String, id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B or not _hands_free(role):
		return
	var p := room.props[id]
	var b := get_player(role)
	if p.holder != "" or p.unthrow_to != "" or p.global_position.distance_to(b.eye()) > Player.UNTHROW_RANGE + 1.0:
		return
	if not has_los(p.global_position, b.eye()):
		return
	p.unthrow_to = role
	p.thrower = role
	p.freeze = true
	p.hit_ids.clear()
	_on_action.rpc(role, "unthrow", p.global_position)


func _host_props(delta: float) -> void:
	for p in room.props:
		if p.holder != "":
			var pl := get_player(p.holder)
			var aim := pl.aim_dir()
			var right := pl.global_basis.x
			p.global_position = pl.eye() + aim * 0.7 + right * 0.25 + Vector3(0, -0.3, 0)
			p.global_basis = pl.global_basis
		elif p.unthrow_to != "":
			var pl := get_player(p.unthrow_to)
			if not pl.alive:
				_host_release_prop(p, Vector3.ZERO, false)
				continue
			var target := pl.eye() + pl.aim_dir() * 0.6
			var to := target - p.global_position
			var step := UNTHROW_SPEED * delta
			var dir := to.normalized()
			var next := p.global_position + dir * minf(step, to.length())
			var q := PhysicsRayQueryParameters3D.create(p.global_position, next, Util.L_GLASS)
			var gh := get_world_3d().direct_space_state.intersect_ray(q)
			if gh and gh.collider is Glass and (gh.collider as Glass).fragile():
				host_set_glass((gh.collider as Glass).id, false, Util.B)
			for e in room.enemies:
				if e.alive and not p.hit_ids.has(e.id):
					var res := Util.segment_vs_capsule(p.global_position, next, e.global_position, 0.3, 1.7)
					if res[0] < 0.6:
						p.hit_ids[e.id] = true
						host_hit_enemy(e, "unthrow", dir, Util.B)
			p.global_position = next
			p.rotate(Vector3.UP, -delta * 12.0)
			if to.length() < 0.6:
				p.unthrow_to = ""
				p.holder = pl.role
				_on_action.rpc(pl.role, "unthrow_catch", target)


# --- Glass --------------------------------------------------------------------

func host_set_glass(id: int, intact: bool, actor: String) -> void:
	var g := room.glass[id]
	if g.intact == intact:
		return
	_crumble_t.erase(id)
	_on_glass.rpc(id, intact, actor)
	if g.kind == Glass.POT and not intact:
		var drops := [Pickup.COIN, Pickup.COIN, Pickup.COIN]
		for i in randi_range(0, 2):
			drops.append(Pickup.COIN)
		if randf() < 0.18:
			drops.append(Pickup.HOURGLASS)
		host_spawn_pickups(drops, g.center())
	elif g.kind == Glass.RELIC and intact and not g.rewarded:
		g.rewarded = true
		host_spawn_pickups([Pickup.GEM], g.center() + Vector3(0, 0.6, 0))


@rpc("authority", "call_local", "reliable")
func _on_glass(id: int, intact: bool, actor: String) -> void:
	if room == null or id >= room.glass.size():
		return
	room.glass[id].set_intact(intact, actor)


@rpc("any_peer", "call_local", "reliable")
func request_unbreak(role: String, id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B or not _hands_free(role):
		return
	var g := room.glass[id]
	if g.intact or not g.restorable():
		return
	if g.kind in [Glass.BRIDGE, Glass.CRUMBLE, Glass.RELIC]:
		host_set_glass(id, true, role)
		return
	var bodies: Array[Node3D] = []
	for p: Player in players.values():
		if p.alive:
			bodies.append(p)
	for e in room.enemies:
		if e.alive:
			bodies.append(e)
	for n in bodies:
		var off := n.global_position - g.global_position
		var across := absf(off.x) if g.vertical else absf(off.z)
		var along := absf(off.z) if g.vertical else absf(off.x)
		if across < 0.55 and along < Util.TILE * 0.5 + 0.3:
			toast_to(role, "Something is in the way")
			return
	host_set_glass(id, true, role)


# --- Feedback --------------------------------------------------------------------

## Sounds and small effects for actions that the other PC should see and hear.
@rpc("authority", "call_local", "reliable")
func _on_action(role: String, action: String, pos: Vector3) -> void:
	var rev := role == Util.B
	match action:
		"punch", "pull":
			Game.sfx("pull" if action == "pull" else "punch", rev, pos, -6.0)
		"punch_hit", "pull_hit", "stun", "kick":
			Fx.burst(fx, pos, Util.role_color(role) if role != "" else Color.WHITE, 8, 2.5, 0.05, 0.3, rev)
			Game.sfx("punch", rev, pos)
		"grab":
			Game.sfx("catch", false, pos, -6.0, 1.4)
		"throw", "throw_soft":
			Game.sfx("throw", rev, pos, -3.0 if action == "throw" else -10.0)
		"unthrow":
			Fx.burst(fx, pos, Util.CYAN, 8, 2.0, 0.04, 0.3, true)
			Game.sfx("pull", true, pos)
		"unthrow_catch":
			Game.sfx("catch", true, pos, -6.0, 1.4)
		"relight":
			Fx.burst(fx, pos, Util.CYAN, 18, 2.5, 0.05, 0.5, true)
			Fx.flash(fx, pos, Mats.FIRE, 6.0, 8.0, 0.4)
			Game.sfx("rewind", true, pos, -2.0)


@rpc("any_peer", "call_local", "reliable")
func request_ping(role: String, pos: Vector3, enemy_id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role):
		return
	if not _host_ready(role, "ping", 0.25):
		return
	_on_ping.rpc(role, pos, enemy_id)


@rpc("authority", "call_local", "reliable")
func _on_ping(role: String, pos: Vector3, enemy_id: int) -> void:
	hud.add_ping(role, pos, enemy_id)
	Fx.ring(fx, pos + Vector3(0, 0.05, 0), Util.role_color(role), 0.8, 0.5, role == Util.B)
	Game.sfx("ping", role == Util.B)


func toast(msg: String, color := Color.WHITE) -> void:
	hud.toast(msg, color)


func toast_to(role: String, msg: String) -> void:
	if Game.solo:
		toast(msg)
	else:
		_toast.rpc_id(Net.peer_for(role), msg)


@rpc("authority", "call_local", "reliable")
func _toast(msg: String) -> void:
	toast(msg, Util.RED)


# --- Solo testing ---------------------------------------------------------------

## Tab is caught here, before the GUI, so focus navigation can never swallow it.
func _input(event: InputEvent) -> void:
	if Game.solo and event.is_action_pressed("swap_role") and not event.is_echo():
		get_viewport().set_input_as_handled()
		solo_swap()


## One-PC test mode: Tab swaps which agent you control.
func solo_swap() -> void:
	local_role = Util.other(local_role)
	Net.my_role = local_role
	for p: Player in players.values():
		p.set_controlled(p.role == local_role)
	_apply_grade()
	hud.on_role_changed()
	toast(Util.role_name(local_role), Util.role_color(local_role))


# --- Time, traps and falls -----------------------------------------------------------

## Enemies and their rounds crawl while an hourglass is running.
func time_scale() -> float:
	return 0.3 if Net.now() < slow_until else 1.0


## Victim decides: each PC checks the traps against its own player.
func _local_hazards() -> void:
	for p: Player in players.values():
		if not p.is_local() or not p.alive:
			continue
		for hz in room.hazards:
			if hz.lethal_for(p.global_position, Player.RADIUS):
				Fx.burst(fx, p.chest(), Util.RED, 14, 3.0, 0.06, 0.4, false)
				local_player_hit(p, Vector3.UP)
				break


## Victim decides: a rusher that reaches this PC's player cuts them down.
func _local_rushers() -> void:
	for p: Player in players.values():
		if not p.is_local() or not p.alive:
			continue
		for e in room.enemies:
			if e.touches(p.global_position):
				Fx.burst(fx, p.chest(), Util.RED, 14, 3.0, 0.06, 0.4, false)
				local_player_hit(p, e.facing())
				break


func _host_traps_and_falls() -> void:
	for e in room.enemies:
		if not e.alive or e.kind == Enemy.TURRET:
			continue
		if e.global_position.y < -2.5:
			host_kill(e, Vector3.DOWN, "fall")
			continue
		for hz in room.hazards:
			if hz.lethal_for(e.global_position, 0.32):
				host_kill(e, Vector3.UP, "trap")
				break


func _standing_on(g: Glass) -> bool:
	var bodies: Array[Node3D] = []
	for p: Player in players.values():
		if p.alive and p.present:
			bodies.append(p)
	for e in room.enemies:
		if e.alive:
			bodies.append(e)
	for b in bodies:
		var d := b.global_position - g.global_position
		if absf(d.x) < Util.TILE * 0.5 + 0.2 and absf(d.z) < Util.TILE * 0.5 + 0.2 and d.y > -0.6 and d.y < 0.7:
			return true
	return false


## Crumbling floors: a moment after anyone steps on one, it gives way.
func _host_crumble(delta: float) -> void:
	for g in room.glass:
		if g.kind != Glass.CRUMBLE or not g.intact:
			continue
		if _crumble_t.has(g.id):
			_crumble_t[g.id] -= delta
			if _crumble_t[g.id] <= 0.0:
				host_set_glass(g.id, false, "")
		elif _standing_on(g):
			_crumble_t[g.id] = 0.85
			_on_crumble_warn.rpc(g.id)


@rpc("authority", "call_local", "reliable")
func _on_crumble_warn(id: int) -> void:
	if room and id < room.glass.size():
		room.glass[id].warn()


# --- Pickups --------------------------------------------------------------------

func host_spawn_pickups(kinds: Array, origin: Vector3) -> void:
	for k: int in kinds:
		_next_pickup += 1
		var pos := Util.flat(origin)
		for i in 8:
			var a := randf() * TAU
			var c := Util.flat(origin) + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 1.6)
			if room.walkable(c) and has_los(origin, c + Vector3(0, 0.3, 0)):
				pos = c
				break
		_on_pickup.rpc(epoch, _next_pickup, k, origin, pos)


@rpc("authority", "call_local", "reliable")
func _on_pickup(ep: int, id: int, kind: int, origin: Vector3, pos: Vector3) -> void:
	if ep != epoch or room == null:
		return
	var pk := Pickup.new()
	pk.id = id
	pk.kind = kind
	fx.add_child(pk)
	pk.global_position = pos
	pk.spill_from(origin)
	_pickups[id] = pk


func _host_pickups() -> void:
	for id: int in _pickups.keys():
		var pk: Pickup = _pickups[id]
		if pk.taken:
			continue
		for p: Player in players.values():
			if not p.alive or not p.present:
				continue
			var d := pk.global_position - p.global_position
			if Util.flat(d).length() < Pickup.RADIUS and absf(d.y) < 1.6:
				pk.taken = true
				_on_pickup_taken.rpc(epoch, id, p.role)
				break


@rpc("authority", "call_local", "reliable")
func _on_pickup_taken(ep: int, id: int, role: String) -> void:
	if ep != epoch or not _pickups.has(id):
		return
	var pk: Pickup = _pickups[id]
	_pickups.erase(id)
	match pk.kind:
		Pickup.COIN:
			room_loot += 1
		Pickup.GEM:
			room_loot += 5
			hud.toast("Gem +5", Pickup.color_of(Pickup.GEM))
		Pickup.HOURGLASS:
			slow_until = Net.now() + 6.0
			hud.toast("Time slowed", Pickup.color_of(Pickup.HOURGLASS))
			Game.sfx("rewind", false, null, -4.0, 0.6)
		Pickup.ECHO:
			undie_used = false
			hud.toast("Revive restored", Util.CYAN)
	hud.loot_flash()
	pk.collect(role)


# --- Devices and channels ---------------------------------------------------------

func _host_devices() -> void:
	var now := Net.now()
	for d in room.devices:
		if d.kind == Device.PLATE:
			var pressed := false
			for p: Player in players.values():
				if p.alive and p.present and d.plate_has(p.global_position):
					pressed = true
			for e in room.enemies:
				if e.alive and e.kind != Enemy.TURRET and d.plate_has(e.global_position):
					pressed = true
			for pr in room.props:
				if pr.holder == "" and pr.unthrow_to == "" and d.plate_has(pr.global_position):
					pressed = true
			if pressed != d.on:
				_on_device.rpc(d.id, pressed, 0.0)
		elif d.is_trigger() and d.on and d.until > 0.0 and now >= d.until:
			_on_device.rpc(d.id, false, 0.0)
	var chans := {}
	for d in room.devices:
		if d.is_trigger():
			chans[d.channel] = bool(chans.get(d.channel, true)) and d.active(now)
	for ch: int in chans:
		var want: bool = chans[ch]
		if want == bool(_channels.get(ch, false)):
			continue
		# Never drop a portcullis on someone standing under it.
		if not want and _gate_occupied(ch):
			continue
		_on_channel.rpc(ch, want)


func _gate_occupied(ch: int) -> bool:
	for g in room.gates(ch):
		var bodies: Array[Node3D] = []
		for p: Player in players.values():
			if p.alive:
				bodies.append(p)
		for e in room.enemies:
			if e.alive:
				bodies.append(e)
		for b in bodies:
			var d := b.global_position - g.global_position
			if absf(d.x) < Util.TILE * 0.5 + 0.4 and absf(d.z) < Util.TILE * 0.5 + 0.4:
				return true
	return false


@rpc("authority", "call_local", "reliable")
func _on_device(id: int, on: bool, until: float) -> void:
	if room == null or id >= room.devices.size():
		return
	room.devices[id].set_state(on, until)


@rpc("authority", "call_local", "reliable")
func _on_primed(id: int, primed: bool) -> void:
	if room == null or id >= room.devices.size():
		return
	room.devices[id].set_primed(primed)
	if primed:
		Fx.burst(fx, room.devices[id].rune_center(), Util.AMBER, 12, 2.5, 0.05, 0.4, false)
		hud.toast("Crystal primed — recall through it", Util.AMBER)


@rpc("authority", "call_local", "reliable")
func _on_channel(ch: int, on: bool) -> void:
	if room == null:
		return
	_channels[ch] = on
	for g in room.gates(ch):
		g.set_state(on, 0.0)
		room.set_gate_solid(g)
	room.set_channel_lit(ch, on)
	if ch == room.exit_channel and on:
		hud.toast("Seal lit", Device.CH_COLORS[ch % Device.CH_COLORS.size()])


func channel_on(ch: int) -> bool:
	return _channels.get(ch, false)


## The revolver round passed through a rune crystal.
func host_rune_hit(id: int, recall: bool) -> void:
	var d := room.devices[id]
	if d.active(Net.now()) and d.until <= 0.0:
		return
	match d.kind:
		Device.RUNE_F:
			if not recall:
				_host_light(d)
		Device.RUNE_R:
			if recall:
				_host_light(d)
		Device.RUNE_P:
			if not recall:
				if not d.primed:
					_on_primed.rpc(id, true)
			elif d.primed:
				_on_primed.rpc(id, false)
				_host_light(d)


func _host_light(d: Device) -> void:
	_on_device.rpc(d.id, true, Net.now() + d.hold if d.hold > 0.0 else 0.0)


## NOEL rewinds a brazier back to full fire.
@rpc("any_peer", "call_local", "reliable")
func request_relight(role: String, id: int) -> void:
	if not Net.is_host() or not Net.sender_is(role) or not playing() or role != Util.B or not _hands_free(role):
		return
	var d := room.devices[id]
	if d.kind != Device.BRAZIER:
		return
	if d.global_position.distance_to(get_player(role).global_position) > Device.BRAZIER_RANGE + 1.0:
		return
	_on_device.rpc(id, true, Net.now() + d.hold)
	_on_action.rpc(role, "relight", d.global_position + Vector3(0, 1.2, 0))


## The brazier under the crosshair within reach, or null.
func find_brazier(eye: Vector3, dir: Vector3) -> Device:
	if room == null:
		return null
	for d in room.devices:
		if d.kind != Device.BRAZIER:
			continue
		var c := d.global_position + Vector3(0, 1.1, 0)
		var to := c - eye
		if to.length() > Device.BRAZIER_RANGE + 0.5:
			continue
		if to.normalized().dot(dir) > 0.8:
			return d
	return null


@rpc("authority", "call_local", "reliable")
func _toast_all(msg: String, color: Color) -> void:
	toast(msg, color)
