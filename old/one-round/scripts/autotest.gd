extends Node
## Scripted smoke test of the core loop, run with:
##   godot --headless --path . -- --solo --autotest
## Drives both agents through the real request RPCs and prints PASS/FAIL lines, then quits.

var world: World
var _fails := 0


func _ready() -> void:
	world = get_parent() as World
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	return cond.call()


func _put(p: Player, pos: Vector3, look_at: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var d := Util.flat(look_at - pos)
	p.rotation.y = Util.yaw_of(d)
	var to := look_at - p.eye()
	p.pitch = atan2(to.y, Util.flat(to).length())
	p.cam.rotation.x = p.pitch


## A walkable spot about dist metres from target with a clear line between them.
func _clear_spot_near(target: Vector3, dist: float) -> Vector3:
	for i in 16:
		var p := target + Util.dir_of(TAU * i / 16.0) * dist
		if world.room.walkable(p) and world.has_los(p + Vector3(0, 1.6, 0), target + Vector3(0, 1.3, 0)):
			return Util.flat(p)
	return Util.flat(target) + Vector3(2, 0, 0)


func _give_gun(role: String) -> bool:
	var p := world.get_player(role)
	var rv := world.revolver
	if rv.holder == role:
		return true
	_put(p, Util.flat(rv.body.global_position), Vector3.ZERO)
	return await _wait_until(func() -> bool: return rv.holder == role, 3.0)


func _lift() -> Vector3:
	var c := world.room.lift_rect.get_center()
	return Vector3(c.x, 0.1, c.y)


## Waits for wave 1, then pins it and holds back later waves so a test can work the room.
func _first_wave() -> bool:
	var ok := await _wait_until(func() -> bool: return world.waves.wave >= 1, 5.0)
	world.waves.paused = true
	for e in world.room.enemies:
		e.moves = false
	return ok


## Lets the waves run again and cuts each one down as it lands, until the exit opens.
func _clear_waves() -> bool:
	world.waves.paused = false
	return await _wait_until(func() -> bool:
		for e in world.room.enemies:
			world.host_kill(e, Vector3.FORWARD, "test")
		return world.door_open, 15.0)


## Both agents step into the lift, the final wave lands and is cut down, and the room clears.
func _hold_lift() -> bool:
	var lift := _lift()
	_put(world.get_player(Util.A), lift + Vector3(-0.5, 0, 0), lift)
	_put(world.get_player(Util.B), lift + Vector3(0.5, 0, 0), lift)
	if not await _wait_until(func() -> bool: return world.waves.in_final(), 3.0):
		return false
	for e in world.room.enemies:
		world.host_kill(e, Vector3.FORWARD, "test")
	return await _wait_until(func() -> bool: return world.state == World.State.CLEAR, 2.0)


func _shot(name: String) -> void:
	var dir := OS.get_environment("SHOTS_DIR")
	if dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _run() -> void:
	if Net.cli.has("tour"):
		await _run_tour()
		get_tree().quit()
		return
	if Net.cli.has("shots"):
		await _run_shots()
		get_tree().quit()
		return
	if not Game.solo:
		if Net.is_host():
			await _run_net_host()
		else:
			await _run_net_client()
		print("AUTOTEST %s %s (%d failures)" % ["HOST" if Net.is_host() else "CLIENT", "PASSED" if _fails == 0 else "FAILED", _fails])
		await _wait(1.0)
		get_tree().quit(1 if _fails > 0 else 0)
		return
	world.invulnerable = true
	var rv := world.revolver
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)

	# --- Room 1: fire, throw, catch, recall ---
	_check(await _wait_until(func() -> bool: return world.state == World.State.PLAY, 15.0), "room 1 starts")
	_check(await _first_wave() and world.room.enemies.size() == 2, "room 1's first wave is two grunts")
	_check(await _give_gun(Util.A), "LEON picks up the gun from the floor")
	var e0 := world.room.enemies[0]
	var e1 := world.room.enemies[1]
	_put(a, world.room.starts.A, e0.chest())
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (e0.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0), "fired round lodges in a wall")
	_check(not e0.alive, "forward shot kills grunt 0")

	# Place NOEL so the recall line passes through grunt 1.
	var line := Util.flat(e1.chest() - rv.lodged_pos).normalized()
	var spot := Util.flat(e1.global_position) + line * 3.0
	_put(b, spot, rv.lodged_pos)
	_check(world.room.walkable(spot), "recall spot is on the floor")
	_put(a, _clear_spot_near(b.global_position, 5.0), b.chest())
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.holder == Util.B, 4.0), "NOEL catches the thrown gun")
	rv.request_fire.rpc_id(1, Util.B, b.eye(), b.aim_dir())
	await _wait(0.2)
	_check(rv.bullet == Revolver.LODGED, "NOEL cannot fire")
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.IN_GUN, 3.0), "recall returns the round to the cylinder")
	_check(not e1.alive, "recall kills grunt 1")
	_check(await _clear_waves(), "lift door opens once every wave is down")
	_check(await _hold_lift(), "holding the lift through the final wave clears the room")
	_check(await _wait_until(func() -> bool: return world.room_index == 1 and world.state == World.State.PLAY, 20.0), "room 2 loads after results")
	_check(await _first_wave(), "room 2's first wave lands")

	# --- Room 2: glass, props, bullet reversal ---
	var g: Glass = null
	for gg in world.room.glass:
		if gg.kind == Glass.WARD:
			g = gg
			break
	world.host_set_glass(g.id, false, Util.A)
	_check(not g.intact and g.collision_layer == Util.L_GHOST, "glass breaks")
	_put(b, g.global_position + Vector3(-4, 0, 0), g.center())
	world.request_unbreak.rpc_id(1, Util.B, g.id)
	_check(g.intact, "NOEL un-breaks glass")

	var pr := world.room.props[0]
	_put(a, Util.flat(pr.global_position) + Vector3(1.0, 0, 0), pr.global_position)
	world.request_grab.rpc_id(1, Util.A, pr.id)
	_check(world.held_prop(Util.A) == pr, "LEON grabs a prop")
	world.request_throw_prop.rpc_id(1, Util.A, a.eye(), a.aim_dir(), false)
	_check(world.held_prop(Util.A) == null and pr.lethal, "LEON throws the prop")
	await _wait(1.0)
	_put(b, Util.flat(pr.global_position) + Vector3(0, 0, 5.0), pr.global_position)
	if not world.room.walkable(b.global_position):
		_put(b, Util.flat(pr.global_position) + Vector3(0, 0, -5.0), pr.global_position)
	world.request_unthrow.rpc_id(1, Util.B, pr.id)
	_check(await _wait_until(func() -> bool: return pr.holder == Util.B, 3.0), "NOEL un-throws the prop into their hand")
	world.request_throw_prop.rpc_id(1, Util.B, b.eye(), b.aim_dir(), true)

	var turret: Enemy = null
	for e in world.room.enemies:
		if e.kind == Enemy.TURRET:
			turret = e
	_check(turret != null, "room 2 has a turret")
	_check(await _wait_until(func() -> bool: return not world._bullets.is_empty(), 6.0), "turret fires slow bullets")
	var bl: EnemyBullet = world._bullets.values()[0]
	_put(b, bl.global_position + bl.dir * 3.0, bl.global_position)
	world.request_reverse.rpc_id(1, Util.B, bl.id)
	_check(bl.reversed, "NOEL reverses an enemy bullet")

	# --- Death and un-death ---
	world.local_player_hit(a, Vector3.FORWARD, true)
	_check(await _wait_until(func() -> bool: return a.echo and not a.alive, 1.0), "LEON's first death leaves an echo")
	_put(b, a.global_position + Vector3(1.0, 0, 0), a.global_position)
	world.request_revive.rpc_id(1, Util.B)
	_check(await _wait_until(func() -> bool: return a.alive, 1.0), "NOEL un-dies LEON")
	world.local_player_hit(b, Vector3.FORWARD, true)
	_check(await _wait_until(func() -> bool: return world.state == World.State.DEAD, 1.0), "NOEL dying fractures time")
	_check(await _wait_until(func() -> bool: return world.state == World.State.PLAY and world.room_deaths == 1, 5.0), "room restarts")

	# --- Room 3: Anchor and the temporal pincer ---
	world._load_room.rpc(2, false)
	_check(await _wait_until(func() -> bool: return world.room_index == 2 and world.state == World.State.PLAY, 5.0), "room 3 loads")
	_check(await _first_wave(), "room 3's first wave lands")
	var anchor: Enemy = null
	for e in world.room.enemies:
		if e.kind == Enemy.ANCHOR:
			anchor = e
	_check(anchor != null, "room 3 has an Anchor")
	_check(await _give_gun(Util.A), "LEON has the gun")
	var row1 := anchor.global_position.z
	_put(a, Vector3(anchor.global_position.x - 6.0, 0, row1), anchor.chest())
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (anchor.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0), "shot through the Anchor lodges")
	_check(anchor.alive and anchor.cracked, "forward shot cracks the Anchor, does not kill it")
	_put(b, Vector3(anchor.global_position.x - 4.0, 0, row1 + 0.01), rv.lodged_pos)
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	if not await _wait_until(func() -> bool: return rv.holder == Util.B, 3.0):
		await _give_gun(Util.B)
		_put(b, Vector3(anchor.global_position.x - 4.0, 0, row1 + 0.01), rv.lodged_pos)
	_check(rv.holder == Util.B, "NOEL has the gun for the recall")
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	_check(await _wait_until(func() -> bool: return world.frozen, 3.0), "pincer freezes the world for the cut-in")
	_check(await _wait_until(func() -> bool: return not anchor.alive and not world.frozen, 3.0), "pincer kills the Anchor and resumes")
	_check(world.room_pincers == 1, "pincer counted")
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.IN_GUN, 3.0), "round returns after the pincer")

	await _run_puzzles()
	await _run_waves()
	await _run_chain()
	await _run_movement()

	print("AUTOTEST %s (%d failures)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# --- Two-process network test: host drives LEON, client drives NOEL -------------

func _recall_spot() -> Vector3:
	var rv := world.revolver
	var e1 := world.room.enemies[1]
	var line := Util.flat(e1.chest() - rv.lodged_pos).normalized()
	return Util.flat(e1.global_position) + line * 3.0


func _run_net_host() -> void:
	world.invulnerable = true
	var rv := world.revolver
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)
	_check(await _wait_until(func() -> bool: return world.state == World.State.PLAY, 20.0), "[host] room 1 starts")
	var b_start := b.global_position
	_check(await _wait_until(func() -> bool: return b.global_position.distance_to(b_start) > 1.0, 5.0), "[host] sees NOEL move (player sync)")
	_check(await _first_wave(), "[host] wave 1 lands")
	_check(await _give_gun(Util.A), "[host] LEON picks up the gun")
	var e0 := world.room.enemies[0]
	_put(a, world.room.starts.A, e0.chest())
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (e0.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0), "[host] round lodges")
	_check(not e0.alive, "[host] grunt 0 dead")
	_check(world.chain.count == 1, "[host] the kill adds to the chain")
	var spot := _recall_spot()
	_check(await _wait_until(func() -> bool: return Util.flat(b.global_position).distance_to(spot) < 0.3, 12.0), "[host] NOEL reaches the recall spot")
	await _wait(0.3)
	_put(a, _clear_spot_near(b.global_position, 5.0), b.chest())
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.holder == Util.B, 4.0), "[host] NOEL catches the gun")
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.IN_GUN, 6.0), "[host] NOEL's recall returns the round")
	_check(not world.room.enemies[1].alive, "[host] recall kills grunt 1")
	world.waves.paused = false
	_check(await _wait_until(func() -> bool: return world.waves.wave == 2, 3.0), "[host] clearing wave 1 brings wave 2")
	world.host_kill(world.room.enemies[2], Vector3.FORWARD, "test")
	await _wait(1.5)
	_check(await _clear_waves(), "[host] door opens once every wave is down")


func _run_net_client() -> void:
	world.invulnerable = true
	var rv := world.revolver
	var b := world.get_player(Util.B)
	_check(Net.my_role == Util.B and b.controlled and b.is_local(), "[client] controls NOEL")
	_check(await _wait_until(func() -> bool: return world.state == World.State.PLAY, 20.0), "[client] room 1 starts")
	_put(b, b.global_position + Vector3(2, 0, 0), Vector3.ZERO)
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 8.0), "[client] sees the round lodge")
	_check(not world.room.enemies[0].alive, "[client] sees grunt 0 die")
	_check(await _wait_until(func() -> bool: return world.chain.count == 1, 2.0), "[client] chain matches the host after the kill")
	var spot := _recall_spot()
	_put(b, spot, rv.lodged_pos)
	_check(await _wait_until(func() -> bool: return rv.holder == Util.B, 12.0), "[client] catches the gun")
	# The host threw from within 5 m of NOEL, well away from LEON's start.
	var a := world.get_player(Util.A)
	_check(Util.flat(a.global_position).distance_to(Util.flat(b.global_position)) < 6.0, "[client] sees LEON move (player sync)")
	_put(b, spot, rv.lodged_pos)
	await _wait(0.2)
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	_check(await _wait_until(func() -> bool: return rv.bullet == Revolver.IN_GUN, 3.0), "[client] round back in the cylinder")
	_check(not world.room.enemies[1].alive, "[client] sees grunt 1 die")
	_check(await _wait_until(func() -> bool: return world.waves.wave == 2, 4.0), "[client] sees wave 2 land")
	var ids_match := world.room.enemies.size() == 5
	for i in world.room.enemies.size():
		ids_match = ids_match and world.room.enemies[i].id == i and (i < 2 or world.room.enemies[i].kind == Enemy.RUSHER)
	_check(ids_match, "[client] wave 2's rushers exist with the host's ids")
	_check(await _wait_until(func() -> bool: return not world.room.enemies[2].alive, 2.0) and world.room.enemies[3].alive,
		"[client] the host's kill by id lands on the same rusher")
	_check(await _wait_until(func() -> bool: return world.door_open, 15.0), "[client] sees the door open")
	_check(Net._best_rtt < 0.1, "[client] clock synced (rtt %.1f ms)" % (Net._best_rtt * 1000.0))


# --- Screenshots for a visual check (SHOTS_DIR=... godot --path . -- --solo --autotest --shots) ---

func _run_shots() -> void:
	world.invulnerable = true
	var rv := world.revolver
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)
	await _wait(1.2)
	await _shot("01_intro_card")
	await _wait_until(func() -> bool: return world.state == World.State.PLAY, 15.0)
	await _first_wave()
	await _shot("02_room1_start")
	await _give_gun(Util.A)
	var e0 := world.room.enemies[0]
	_put(a, world.room.starts.A, e0.chest())
	await _wait(0.4)
	await _shot("03_aim_line")
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (e0.chest() - a.eye()).normalized())
	await _wait(0.12)
	await _shot("04_round_in_flight")
	await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0)
	await _wait(0.8)
	_put(b, _recall_spot(), rv.lodged_pos)
	_put(a, _clear_spot_near(b.global_position, 5.0), b.chest())
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	await _wait(0.15)
	await _shot("05_throw")
	await _wait_until(func() -> bool: return rv.holder == Util.B, 4.0)
	world.solo_swap()
	_put(b, _recall_spot(), rv.lodged_pos)
	await _wait(0.6)
	await _shot("06_noel_recall_preview")
	_put(a, a.global_position, b.chest())
	world.solo_swap()
	await _wait(0.3)
	await _shot("07_leon_sees_noel")
	world.solo_swap()
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	await _wait(0.1)
	await _shot("08_recall_flight")
	await _clear_waves()
	await _hold_lift()
	await _wait(1.6)
	await _shot("09_results")
	await _wait_until(func() -> bool: return world.room_index == 1 and world.state == World.State.PLAY, 20.0)
	world.solo_swap()
	await _wait(1.0)
	await _shot("10_noodle_bar")
	await _load(2)
	var anchor: Enemy = null
	for e in world.room.enemies:
		if e.kind == Enemy.ANCHOR:
			anchor = e
	await _give_gun(Util.A)
	if world.local_role != Util.A:
		world.solo_swap()
	_put(a, Vector3(anchor.global_position.x - 6.0, 0, anchor.global_position.z), anchor.chest())
	await _wait(0.3)
	await _shot("11_server_floor_anchor")
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (anchor.chest() - a.eye()).normalized())
	await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0)
	var bspot := Vector3(anchor.global_position.x - 4.0, 0, anchor.global_position.z + 0.01)
	_put(b, bspot, rv.lodged_pos)
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	await _wait_until(func() -> bool: return rv.holder == Util.B, 3.0)
	_put(b, bspot, rv.lodged_pos)
	world.solo_swap()
	await _wait(0.3)
	await _shot("11b_anchor_recall_preview")
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	await _wait_until(func() -> bool: return world.frozen, 3.0)
	await _wait(0.45)
	await _shot("12_pincer_cutin")
	world.local_player_hit(b, Vector3.FORWARD, true)
	await _wait(0.5)
	await _shot("13_death_card")


# --- Room tour: wide shots of every room for a visual check (--tour, with SHOTS_DIR) -----

func _run_tour() -> void:
	world.invulnerable = true
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)
	var only := OS.get_environment("TOUR_ROOMS")
	for i in Rooms.ALL.size():
		if only != "" and not only.split(",").has(str(i)):
			continue
		await _load(i)
		var r := world.room
		var center := Vector3((r.w - 1) * Util.TILE * 0.5, 1.4, (r.h - 1) * Util.TILE * 0.5)
		_put(a, r.starts.A, center)
		_put(b, r.starts.B + Vector3(0, 0, -2.5), center)
		await _wait(2.5)
		await _shot("tour_%d_a_start" % i)
		var far := Vector3(center.x + (r.w * 0.3), 0, Util.TILE * 1.5)
		if not r.walkable(far):
			far = _clear_spot_near(Vector3(center.x, 0, Util.TILE * 2.0), 2.0)
		_put(a, far, Vector3(center.x - r.w * 0.2, 1.0, (r.h - 1) * Util.TILE))
		await _wait(1.5)
		await _shot("tour_%d_b_back" % i)
		var e0: Enemy = r.enemies[0]
		var spot := _clear_spot_near(e0.global_position, 3.2)
		_put(a, spot, e0.chest())
		_put(b, e0.global_position + (spot - e0.global_position).normalized().rotated(Vector3.UP, 0.9) * 1.8, e0.chest())
		await _wait(1.0)
		await _shot("tour_%d_c_enemy" % i)


# --- Puzzles, traps and pickups ---------------------------------------------------

func _load(i: int) -> void:
	world._load_room.rpc(i, false)
	await _wait_until(func() -> bool: return world.room_index == i and world.state == World.State.PLAY, 8.0)
	await _first_wave()
	for e in world.room.enemies:
		e.fire_interval = 999.0


func _device(kind: int) -> Device:
	for d in world.room.devices:
		if d.kind == kind:
			return d
	return null


func _glass_of(kind: int, intact: Variant = null) -> Glass:
	for g in world.room.glass:
		if g.kind == kind and (intact == null or g.intact == intact):
			return g
	return null


func _run_puzzles() -> void:
	var rv := world.revolver
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)

	# Undercroft: LEON's shot lights the amber rune, which raises gate 1.
	await _load(0)
	var rune := _device(Device.RUNE_F)
	var gate1: Device = world.room.gates(rune.channel)[0]
	_check(not gate1.on and gate1._body.collision_layer == Util.L_GATE, "gate starts closed")
	_check(await _give_gun(Util.A), "[puzzle] LEON has the gun")
	_put(a, rune.global_position + Vector3(4.5, 0, 0), rune.rune_center())
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (rune.rune_center() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rune.on, 3.0), "forward shot lights the amber rune")
	_check(await _wait_until(func() -> bool: return gate1.on and gate1._body.collision_layer == 0, 2.0), "lit rune opens its gate")
	_check(not world.room.astar.is_point_solid(gate1.tile), "open gate is walkable for enemies")
	# A recall rune ignores the forward shot.
	var rr := _device(Device.RUNE_R)
	_check(not rr.on, "cyan rune ignores LEON's shot")

	# Loot: a smashed urn spills coins; walking over them adds to the loot.
	# LEON punches with empty hands, so NOEL takes the gun.
	await _drop_to(Util.B)
	var pot := _glass_of(Glass.POT, true)
	_put(a, Util.flat(pot.global_position) + Vector3(0, 0, 1.6), pot.center())
	world.request_punch.rpc_id(1, Util.A, a.eye(), (pot.center() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return not pot.intact, 1.0), "LEON smashes a loot urn")
	_check(await _wait_until(func() -> bool: return not world._pickups.is_empty(), 1.0), "coins spill out")
	var before := world.room_loot
	var spots: Array[Vector3] = []
	for pk: Pickup in world._pickups.values():
		spots.append(pk.global_position)
	for sp in spots:
		_put(a, Util.flat(sp), sp)
		await _wait(0.15)
	_check(world.room_loot > before, "walking over coins adds loot (%d)" % world.room_loot)
	# Relic: NOEL restores it and a gem drops.
	await _drop_to(Util.A)
	var relic := _glass_of(Glass.RELIC)
	_check(relic != null and not relic.intact, "relic starts shattered")
	world.request_unbreak.rpc_id(1, Util.B, relic.id)
	_check(relic.intact, "NOEL restores the relic")
	var gem := false
	for pk: Pickup in world._pickups.values():
		gem = gem or pk.kind == Pickup.GEM
	_check(gem, "restored relic drops a gem")

	# Cistern: bridges, plates, the exit seal, falling to death.
	await _load(1)
	var broken := _glass_of(Glass.BRIDGE, false)
	var whole := _glass_of(Glass.BRIDGE, true)
	_check(broken != null and whole != null, "cistern has a broken and an intact bridge")
	_check(world.room.astar.is_point_solid(broken.tiles[0]), "broken bridge is not walkable")
	world.request_unbreak.rpc_id(1, Util.B, broken.id)
	_check(broken.intact and not world.room.astar.is_point_solid(broken.tiles[0]), "NOEL restores the bridge")
	await _drop_to(Util.B)
	var e0: Enemy = world.room.enemies[1]
	e0.global_position = whole.global_position + Vector3(1.5, 0.1, 0)
	await _wait(0.3)
	var near_end := whole.global_position + Vector3(-1.8, 0, 0)
	_put(a, whole.global_position + Vector3(-3.0, 0, 0), near_end)
	world.request_punch.rpc_id(1, Util.A, a.eye(), (near_end - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return not whole.intact, 1.0), "LEON punches the bridge down")
	_check(await _wait_until(func() -> bool: return not e0.alive, 3.0), "the cultist on it falls to its death")
	var plate := _device(Device.PLATE)
	_check(not world.channel_on(plate.channel), "exit seal starts unlit")
	var prop: Prop = world.room.props[0]
	prop.global_position = plate.global_position + Vector3(0, 0.4, 0)
	prop.linear_velocity = Vector3.ZERO
	_check(await _wait_until(func() -> bool: return world.channel_on(plate.channel), 3.0), "a prop on the plate lights the seal")
	_check(await _clear_waves(), "door opens once the waves are down and the seal is lit")

	# Ossuary: braziers, crumbling floor.
	await _load(2)
	var braziers: Array[Device] = []
	for d in world.room.devices:
		if d.kind == Device.BRAZIER:
			braziers.append(d)
	_check(braziers.size() == 2 and not braziers[0].on, "two dead braziers")
	for br in braziers:
		_put(b, br.global_position + Vector3(1.6 if br.global_position.x < 10.0 else -1.6, 0, 0), br.global_position + Vector3(0, 1.1, 0))
		world.request_relight.rpc_id(1, Util.B, br.id)
	_check(braziers[0].on and braziers[1].on, "NOEL rewinds both braziers")
	_check(await _wait_until(func() -> bool: return world.channel_on(1), 1.0), "both fires light the exit seal")
	var cr := _glass_of(Glass.CRUMBLE, true)
	_put(a, cr.global_position + Vector3(0, 0.05, 0), cr.global_position + Vector3(0, 0, -3))
	_check(await _wait_until(func() -> bool: return not cr.intact, 2.5), "crumbling floor gives way under LEON")
	_check(await _wait_until(func() -> bool: return world.state != World.State.PLAY or a.global_position.y < -1.0, 2.0), "LEON falls")
	await _wait_until(func() -> bool: return world.state == World.State.PLAY, 6.0)
	cr = world.room.glass[cr.id]
	if cr.intact:
		world.host_set_glass(cr.id, false, "")
	world.request_unbreak.rpc_id(1, Util.B, cr.id)
	_check(cr.intact, "NOEL restores the crumbled floor")

	# Gallery: plates hold gates; traps kill cultists.
	await _load(3)
	var p1: Device = null
	for d in world.room.devices:
		if d.kind == Device.PLATE and d.channel == 1:
			p1 = d
	var g1: Device = world.room.gates(1)[0]
	_put(b, p1.global_position, p1.global_position + Vector3(0, 0, -3))
	_check(await _wait_until(func() -> bool: return g1.on, 1.0), "standing on the plate opens its gate")
	_put(b, p1.global_position + Vector3(0, 0, 3.0), p1.global_position)
	_check(await _wait_until(func() -> bool: return not g1.on, 1.0), "stepping off closes it again")
	var spikes: Hazard = null
	for hz in world.room.hazards:
		if hz.kind == Hazard.SPIKES:
			spikes = hz
	var victim: Enemy = world.room.enemies[world.room.enemies.size() - 1]
	victim.global_position = spikes.global_position + Vector3(0, 0.05, 0)
	_check(await _wait_until(func() -> bool: return not victim.alive, Hazard.SPIKE_PERIOD + 1.0), "spikes kill a cultist")
	var blade: Hazard = null
	for hz in world.room.hazards:
		if hz.kind == Hazard.BLADE_X:
			blade = hz
	var hit_any := false
	for i in 40:
		hit_any = hit_any or blade.lethal_for(blade.global_position, 0.35)
		await _wait(0.07)
	_check(hit_any, "the pendulum blade sweeps its doorway")
	_check(not blade.lethal_for(blade.global_position + Vector3(0, 0, 3.0), 0.35), "the blade misses someone well clear of it")

	# Throne: the pincer seal crystal.
	await _load(4)
	var seal := _device(Device.RUNE_P)
	_check(await _give_gun(Util.A), "[seal] LEON has the gun")
	var from := seal.global_position + Vector3(-5.0, 0, 3.0)
	_put(a, from, seal.rune_center())
	rv.request_fire.rpc_id(1, Util.A, a.eye(), (seal.rune_center() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return seal.primed, 3.0), "forward shot primes the seal crystal")
	_check(not world.channel_on(1), "primed is not lit")
	await _wait_until(func() -> bool: return rv.bullet == Revolver.LODGED, 3.0)
	var back := rv.lodged_pos + (seal.rune_center() - rv.lodged_pos) * 1.6
	_put(b, Util.flat(back), seal.rune_center())
	await _drop_to(Util.B)
	_put(b, Util.flat(back), rv.lodged_pos)
	await _wait(0.1)
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	_check(await _wait_until(func() -> bool: return world.channel_on(1), 3.0), "recall through the primed crystal lights the seal")

	# Hourglass pickup slows enemy time.
	world.host_spawn_pickups([Pickup.HOURGLASS], a.global_position + Vector3(0, 1, 0))
	await _wait(0.6)
	for pk: Pickup in world._pickups.values().duplicate():
		if is_instance_valid(pk):
			_put(a, Util.flat(pk.global_position), pk.global_position)
			await _wait(0.1)
	_check(await _wait_until(func() -> bool: return world.time_scale() < 1.0, 1.0), "hourglass slows enemy time")


## Put the gun in one agent's hands (dropping it from the other's) so the other's hands are free.
func _drop_to(role: String) -> void:
	var rv := world.revolver
	var p := world.get_player(role)
	await _wait_until(func() -> bool: return rv.bullet != Revolver.FLYING, 3.0)
	if rv.holder == role:
		return
	if rv.holder != "":
		rv.host_drop(p.global_position + Vector3(0, 0.5, 0))
		_check(await _wait_until(func() -> bool: return rv.holder == role, 3.0), "%s takes the dropped gun" % role)
	else:
		_check(await _give_gun(role), "%s picks up the gun" % role)


# --- Waves, rushers, par and the exit hold ---------------------------------------------

func _run_waves() -> void:
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)
	var w := world.waves
	world._load_room.rpc(0, false)
	_check(await _wait_until(func() -> bool: return world.state == World.State.PLAY, 8.0), "[waves] undercroft reloads")
	_check(world.room.enemies.is_empty(), "[waves] the room starts empty")
	_check(await _wait_until(func() -> bool: return w.wave == 1, 3.0) and world.room.enemies.size() == 2, "[waves] wave 1 lands")
	for e in world.room.enemies:
		world.host_kill(e, Vector3.FORWARD, "test")
	_check(await _wait_until(func() -> bool: return w.wave == 2, 3.0), "[waves] clearing wave 1 brings wave 2")
	var rushers := world.room.enemies.filter(func(e: Enemy) -> bool: return e.kind == Enemy.RUSHER)
	_check(rushers.size() == 3, "[waves] wave 2 is three rushers")
	var lead: Enemy = rushers[0]
	var tail: Enemy = rushers[2]
	_check(Util.flat(tail.global_position - lead.global_position).length() > Waves.GAP * 1.5, "[waves] rushers land in a line")

	_put(b, world.room.starts.B, lead.chest())
	world.invulnerable = false
	_put(a, lead.global_position + Util.flat(a.global_position - lead.global_position).normalized() * 3.0, lead.chest())
	_check(await _wait_until(func() -> bool: return not a.alive, 3.0), "[waves] a rusher that reaches LEON cuts him down")
	world.invulnerable = true
	_put(b, a.global_position + Vector3(1.0, 0, 0), a.global_position)
	world.request_revive.rpc_id(1, Util.B)
	_check(await _wait_until(func() -> bool: return a.alive, 1.0), "[waves] NOEL revives LEON")

	_check(await _clear_waves(), "[waves] the exit opens once every wave is down")
	var gems := 0
	for pk: Pickup in world._pickups.values():
		if pk.kind == Pickup.GEM:
			gems += 1
	_check(world.par_beaten and gems == 2, "[waves] beating par spills bonus gems")
	_check(w.status() == "TO THE LIFT", "[waves] HUD points to the lift")

	var lift := _lift()
	_put(a, lift, lift + Vector3(0, 0, -3))
	_check(await _wait_until(func() -> bool: return w.in_final(), 3.0), "[waves] stepping into the lift brings the final wave")
	_check(w.status() == "HOLD THE LIFT", "[waves] HUD says hold the lift")
	await _wait(0.5)
	_check(world.state == World.State.PLAY and world.room.alive_enemies() > 0, "[waves] the room holds while the final wave stands")
	for e in world.room.enemies:
		world.host_kill(e, Vector3.FORWARD, "test")
	await _wait(0.5)
	_check(world.state == World.State.PLAY, "[waves] one agent in the lift does not clear the room")
	_put(b, lift + Vector3(0.6, 0, 0), lift)
	_check(await _wait_until(func() -> bool: return world.state == World.State.CLEAR, 2.0), "[waves] final wave down with both agents in the lift clears the room")


# --- Chain: kills feed it, whiffs, drops and time break it, tiers buff the next release ------

## LEON fires at target; true once the round lodges.
func _fire_at(target: Vector3) -> bool:
	var a := world.get_player(Util.A)
	world.revolver.request_fire.rpc_id(1, Util.A, a.eye(), (target - a.eye()).normalized())
	return await _wait_until(func() -> bool: return world.revolver.bullet == Revolver.LODGED, 3.0)


## NOEL recalls from spot; true once the round is back in the cylinder.
func _recall_from(spot: Vector3, steer_at: Variant = null) -> bool:
	var rv := world.revolver
	var b := world.get_player(Util.B)
	_put(b, spot, rv.lodged_pos)
	rv.request_recall.rpc_id(1, Util.B, b.eye())
	if steer_at != null:
		rv.request_steer.rpc_id(1, Util.B, b.eye(), ((steer_at as Vector3) - b.eye()).normalized(), true)
	return await _wait_until(func() -> bool: return rv.bullet == Revolver.IN_GUN, 4.0)


## Every test here runs along one open row of the Undercroft hall: LEON at its west end shoots
## east into the far wall, and NOEL recalls back along it.
func _run_chain() -> void:
	var rv := world.revolver
	var ch := world.chain
	var a := world.get_player(Util.A)
	var b := world.get_player(Util.B)
	var west := Vector3(6, 0, 13.5)
	var east_wall := Vector3(35, 1.25, 13.5)
	# The hall's own cultist stands on the row: park enemies clear of it until they are needed.
	var aside := Vector3(4.5, 0, 9)

	await _load(0)
	var e0 := world.room.enemies[0]
	var e1 := world.room.enemies[1]
	_check(ch.count == 0, "chain starts at 0")
	_check(await _give_gun(Util.A), "[chain] LEON has the gun")
	e0.global_position = Vector3(15, 0, 13.5)
	e1.global_position = aside
	_put(a, west, e0.chest())
	_check(await _fire_at(e0.chest()) and not e0.alive, "[chain] forward shot kills")
	_check(ch.count == 1, "a forward-shot kill adds 1 to the chain")
	e1.global_position = Vector3(21, 0, 13.5)
	await _drop_to(Util.B)
	_check(await _recall_from(Vector3(9, 0, 13.5)) and not e1.alive, "[chain] recall kills")
	_check(ch.count == 2, "a recall kill adds 1 to the chain")
	await _drop_to(Util.A)
	_put(a, west, east_wall)
	await _fire_at(east_wall)
	_check(ch.count == 0, "a shot that kills nothing resets the chain")

	await _load(0)
	_check(await _give_gun(Util.A), "[chain] LEON has the gun again")
	ch.host_add(3)
	rv.request_throw.rpc_id(1, Util.A, a.eye(), Vector3(1, -0.3, 0).normalized())
	_check(await _wait_until(func() -> bool: return ch.count == 0, 3.0), "a dropped gun resets the chain")
	await _wait_until(func() -> bool: return rv.body.linear_velocity.length() < 0.3, 8.0)
	_check(await _give_gun(Util.A), "[chain] LEON picks the dropped gun up")
	ch.host_add(2)
	await _wait(2.0)
	_check(ch.count == 2, "the chain holds within the decay window")
	_check(await _wait_until(func() -> bool: return ch.count == 0, Chain.DECAY), "the chain decays without kills or catches")
	_put(a, Vector3(7, 0, 13.5), Vector3(12, 1.25, 13.5))
	_put(b, Vector3(12, 0, 13.5), a.chest())
	rv.request_throw.rpc_id(1, Util.A, a.eye(), (b.chest() - a.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.holder == Util.B, 3.0) and ch.count == 0, "a catch on the ground adds nothing")
	_put(a, Vector3(9.5, 2.2, 13.5), b.chest())
	rv.request_throw.rpc_id(1, Util.B, b.eye(), (a.chest() - b.eye()).normalized())
	_check(await _wait_until(func() -> bool: return rv.holder == Util.A, 3.0) and ch.count == 1, "an airborne catch adds 1")

	# Tier 2: the shot's hit radius widens enough to take an enemy just off the line.
	await _load(0)
	e0 = world.room.enemies[0]
	e1 = world.room.enemies[1]
	_check(await _give_gun(Util.A), "[chain] LEON has the gun for the tiers")
	e0.global_position = Vector3(15, 0, 14.25)
	e1.global_position = aside
	_put(a, west, east_wall)
	var aim := a.eye() + (east_wall - a.eye()).normalized() * Revolver.MAX_RANGE
	_check(rv.trace(a.eye(), aim, true).hits.is_empty(), "the enemy is just off the shot line")
	ch.host_add(Chain.WIDE)
	_check(await _fire_at(east_wall) and not e0.alive, "chain %d widens the shot onto it" % Chain.WIDE)

	# Tier 5: the shot lodges with a blast that takes an enemy well off the line.
	await _load(0)
	e0 = world.room.enemies[0]
	e1 = world.room.enemies[1]
	_check(await _give_gun(Util.A), "[chain] LEON has the gun for the blast")
	e1.global_position = Vector3(33, 0, 15.75)
	_put(a, west, east_wall)
	ch.host_add(Chain.BLAST)
	_check(rv.trace(a.eye(), aim, true, Chain.hit_pad(Chain.BLAST)).hits.is_empty(), "the enemy is well off the shot line")
	_check(await _fire_at(east_wall), "[chain] the blast shot lodges")
	_check(await _wait_until(func() -> bool: return not e1.alive, 1.0), "chain %d: the explosive lodge kills it" % Chain.BLAST)
	_check(ch.count == Chain.BLAST + 1, "the blast kill adds to the chain")

	# Tier 4+: NOEL steers the recall into an enemy far off the straight line home.
	e0.global_position = Vector3(21, 0, 16.5)
	await _drop_to(Util.B)
	_check(await _recall_from(Vector3(9, 0, 13.5), e0.chest()), "[chain] the steered round comes home")
	_check(not e0.alive, "chain %d: the steered recall bends into the enemy" % (Chain.BLAST + 1))

# --- Movement kit (the proving hall, after the run's rooms) --------------------------

## Hold one of the bot's buttons for exactly one physics frame.
func _tap(bot: Player.Intent, button: String) -> void:
	bot.set(button, true)
	for i in 2:
		await get_tree().physics_frame
	bot.set(button, false)


func _run_movement() -> void:
	await _load(Rooms.RUN_LENGTH)
	var a := world.get_player(Util.A)
	var bot := Player.Intent.new()
	a.bot = bot
	await _wait(0.2)
	_check(a.movement_state == Player.Move.WALK and not a.in_flair(), "an agent standing on the floor is not in flair")

	# Slide: standing, the crawlway blocks; sliding passes under it and kicks the cultist beyond.
	var gap := Room.tile_pos(12, 4)
	var cultist := world.room.enemies[0]
	var cultist_x := cultist.global_position.x
	_put(a, gap + Vector3(-6.0, 0, 0), gap + Vector3(0, 1.6, 0))
	bot.move = Vector2(0, -1)
	_check(not await _wait_until(func() -> bool: return a.global_position.x > gap.x, 1.2), "a standing agent cannot pass the crawlway")
	_put(a, gap + Vector3(-6.0, 0, 0), gap + Vector3(0, 1.6, 0))
	bot.sprint = true
	await _wait_until(func() -> bool: return a.global_position.x > gap.x - 3.0, 2.0)
	bot.crouch = true
	for i in 2:
		await get_tree().physics_frame
	_check(a.movement_state == Player.Move.SLIDE and a.in_flair(), "sprint + crouch slides")
	_check(a.body_height() < Room.CRAWL_GAP, "sliding lowers the capsule under the crawlway gap")
	_check(await _wait_until(func() -> bool: return a.global_position.x > gap.x + Util.TILE * 0.5, 2.0), "the slide passes under the crawlway")
	_check(await _wait_until(func() -> bool: return cultist.stunned > 0.0, 1.5), "a slide into the cultist kicks it (stunned)")
	_check(await _wait_until(func() -> bool: return cultist.global_position.x > cultist_x + 0.5, 1.0), "the slide kick knocks it back")
	bot.crouch = false
	bot.sprint = false
	bot.move = Vector2.ZERO

	# Dash: a burst along the view, then a cooldown.
	var lane := Room.tile_pos(10, 5)
	_put(a, lane, lane + Vector3(-10.0, 1.6, 0))
	await _wait(0.3)
	await _tap(bot, "dash")
	_check(a.movement_state == Player.Move.DASH and a.in_flair(), "dash starts")
	await _wait(0.4)
	var dashed := a.global_position.distance_to(lane)
	_check(dashed > 2.5, "the dash covers ground (%.1f m)" % dashed)
	var here := a.global_position
	await _tap(bot, "dash")
	await _wait(0.3)
	_check(a.cooldown_frac("dash", Player.DASH_COOLDOWN) < 1.0 and a.global_position.distance_to(here) < 0.5, "a second dash waits for the cooldown")

	# Vault: running into low cover (a table) carries the agent over it.
	var table := Room.tile_pos(3, 4)
	_put(a, table + Vector3(3.0, 0, 0), table + Vector3(-5.0, 1.6, 0))
	bot.move = Vector2(0, -1)
	_check(await _wait_until(func() -> bool: return a.movement_state == Player.Move.VAULT, 1.5), "running into low cover vaults")
	_check(await _wait_until(func() -> bool: return a.global_position.x < table.x - 1.2 and a.is_on_floor() and a.global_position.y < 0.1, 2.5), "the vault clears the cover")

	# Mantle: running into a 1.6 m ledge (barrels) climbs onto it.
	var ledge := Room.tile_pos(8, 2)
	_put(a, ledge + Vector3(3.0, 0, 0), ledge + Vector3(-5.0, 1.6, 0))
	_check(await _wait_until(func() -> bool: return a.movement_state == Player.Move.VAULT, 1.5), "running into a ledge mantles")
	bot.move = Vector2.ZERO
	await _wait_until(func() -> bool: return a.movement_state != Player.Move.VAULT, 1.0)
	_check(a.global_position.y > 1.5, "the mantle ends on top of the ledge")

	# Wall-run: sprint, jump at the chasm and run its west wall across.
	var x := Room.tile_pos(5, 0).x - Util.TILE * 0.5 + Player.RADIUS + 0.1
	var edge := Room.tile_pos(0, 8).z - Util.TILE * 0.5
	var far := Room.tile_pos(0, 11).z + Util.TILE * 0.5
	_put(a, Vector3(x, 0, Room.tile_pos(0, 5).z), Vector3(x, 1.6, far + 10.0))
	bot.move = Vector2(0, -1)
	bot.sprint = true
	await _wait_until(func() -> bool: return a.global_position.z > edge - 0.6, 2.0)
	await _tap(bot, "jump")
	_check(await _wait_until(func() -> bool: return a.movement_state == Player.Move.WALL_RUN, 0.5), "jumping beside a wall at speed starts a wall-run")
	await _wait_until(func() -> bool: return a.global_position.z > (edge + far) * 0.5, 1.0)
	_check(a.movement_state == Player.Move.WALL_RUN and a.global_position.y > 0.0, "the wall-run holds the agent up over the chasm")
	_check(await _wait_until(func() -> bool: return a.global_position.z > far + 0.5, 1.5), "the wall-run crosses the chasm")
	_check(await _wait_until(func() -> bool: return a.is_on_floor(), 1.5), "the agent lands on the far side")
	a.bot = null
