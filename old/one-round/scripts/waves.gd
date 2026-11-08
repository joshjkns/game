class_name Waves
extends Node
## Wave director for the current room (child of World, at /root/World/Waves on both PCs).
## The host decides when each wave lands and where every enemy stands. Both PCs then create
## them through one reliable RPC, in the same order, so the new enemies take the same ids
## everywhere (Room.add_enemy). The next wave lands once the current one is mostly down or
## after a timeout; the final wave when someone steps into the open lift.

const KINDS := {"E": Enemy.GRUNT, "T": Enemy.TURRET, "X": Enemy.ANCHOR, "R": Enemy.RUSHER}
## The next wave lands once at most this share of the current one is still standing.
const NEXT_AT := 0.25
const TIMEOUT := 25.0
## Portals gather this long before a wave steps out of them.
const TELEGRAPH := 1.0
## Spacing between enemies of one group.
const GAP := 1.3

var world: World
## Waves landed so far: count + 1 once the final wave is in.
var wave := 0
var count := 0
## Test-only: no further waves land.
var paused := false

var _data: Dictionary
var _current: Array[Enemy] = []
var _landed_at := 0.0
var _incoming := false


func reset(data: Dictionary) -> void:
	_data = data
	count = data.waves.size()
	wave = 0
	paused = false
	_current.clear()
	_incoming = false


func in_final() -> bool:
	return wave > count


## Every regular wave has landed and nothing is left standing.
func cleared() -> bool:
	return wave >= count and not _incoming and world.room.alive_enemies() == 0


## HUD line: the wave count, then the exit hold.
func status() -> String:
	if in_final():
		return "HOLD THE LIFT"
	if world.door_open:
		return "TO THE LIFT"
	if wave == 0:
		return ""
	return "WAVE %d/%d" % [wave, count]


func host_tick() -> void:
	if _incoming or paused:
		return
	if wave < count:
		if wave == 0 or _mostly_down() or world.room_time - _landed_at > TIMEOUT:
			_host_launch(_data.waves[wave])
	elif world.door_open and not in_final() and _lift_entered():
		_host_launch(_data.final)


func _mostly_down() -> bool:
	var up := 0
	for e in _current:
		if e.alive:
			up += 1
	return up <= int(_current.size() * NEXT_AT)


func _lift_entered() -> bool:
	for p: Player in world.players.values():
		if p.alive and p.present and world.room.in_lift(p.global_position):
			return true
	return false


func _host_launch(groups: Array) -> void:
	_incoming = true
	var kinds := PackedInt32Array()
	var spots := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for g: Array in groups:
		var line := _line(world.room.spawns[g[1]], g[2] if g.size() > 2 else 1)
		for p in line:
			var target := world.nearest_player(p)
			kinds.append(KINDS[g[0]])
			spots.append(p)
			yaws.append(Util.yaw_of(Util.flat(target.global_position - p)) if target else 0.0)
	var ep := world.epoch
	var n := wave + 1
	_on_warn.rpc(ep, n, spots)
	await get_tree().create_timer(TELEGRAPH).timeout
	if ep == world.epoch:
		_on_spawn.rpc(ep, n, kinds, spots, yaws)


## A group stands in single file behind its marker, away from the nearest player, so a charging
## line is one clean pierce. Falls back to standing abreast, then to bunching on the marker.
func _line(at: Vector3, n: int) -> PackedVector3Array:
	var p := world.nearest_player(at)
	var back := Util.flat(at - p.global_position).normalized() if p else Vector3.BACK
	for axis: Vector3 in [back, Vector3(-back.z, 0, back.x)]:
		var line := PackedVector3Array()
		for i in n:
			var s := at + axis * GAP * i
			if not world.room.walkable(s):
				break
			line.append(s)
		if line.size() == n:
			return line
	var bunch := PackedVector3Array()
	for i in n:
		bunch.append(at)
	return bunch


@rpc("authority", "call_local", "reliable")
func _on_warn(ep: int, n: int, spots: PackedVector3Array) -> void:
	if ep != world.epoch:
		return
	for p in spots:
		Fx.ring(world.fx, p + Vector3(0, 0.05, 0), Util.RED, 1.0, TELEGRAPH, true)
		Fx.burst(world.fx, p + Vector3(0, 1.0, 0), Util.RED, 10, 2.5, 0.06, TELEGRAPH, true)
	Game.sfx("rewind", false, spots[0], -2.0, 0.6)
	world.toast("Final wave — hold the lift" if n > count else "Wave %d" % n, Util.RED)


@rpc("authority", "call_local", "reliable")
func _on_spawn(ep: int, n: int, kinds: PackedInt32Array, spots: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	if ep != world.epoch:
		return
	wave = n
	_current.clear()
	for i in kinds.size():
		var e := world.room.add_enemy(kinds[i], spots[i], yaws[i])
		_current.append(e)
		Fx.flash(world.fx, e.chest(), Util.RED, 6.0, 6.0, 0.3)
		Fx.burst(world.fx, e.chest(), Util.RED, 10, 3.0, 0.06, 0.4, false)
	_landed_at = world.room_time
	_incoming = false
