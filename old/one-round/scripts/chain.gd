class_name Chain
extends Node
## The team chain: one shared counter fed by kills of the round and flair catches. The chain at
## the moment of release buffs LEON's next shot and NOEL's next recall (thresholds below).
## Host-authoritative: host_* functions change it and _on_chain broadcasts the new value.

## Seconds without a kill or a catch before the chain drops to 0.
const DECAY := 4.0
## Share of the chain kept when the thrown gun hits the floor (0 resets, 0.5 halves).
const DROP_KEEP := 0.0

# Tier thresholds. Each tier keeps the ones below it.
const WIDE := 2    # shot and recall: wider hit radius; recall: faster round
const STEER := 4   # shot: brief slow-mo on fire; recall: NOEL steers the round by holding LMB
const BLAST := 5   # shot: blast where the round lodges; recall: blast at NOEL's feet on the catch
const LOOT := 8    # kills by the round drop extra loot

const WIDE_PAD := 0.5
const RECALL_FAST := 1.6
const SLOWMO_SCALE := 0.3
const SLOWMO_TIME := 0.5
const STEER_SPEED := 22.0
## Radians per second the steered round can turn.
const STEER_TURN := 6.0
## The round bends towards a point this far closer to NOEL along NOEL's aim, so it keeps coming
## home; inside this range it stops steering and homes.
const STEER_LEAD := 4.0
const STEER_TIME := 2.0
const BLAST_RADIUS := 4.0
const ROUND_KILLS := ["fire", "recall", "pincer", "blast"]
const LOOT_DROPS := [Pickup.COIN, Pickup.COIN, Pickup.COIN]
## HUD names for what the next shot / recall gets: [threshold, shot, recall].
const PERKS := [[WIDE, "WIDE", "FAST"], [STEER, "SLOW-MO", "STEER"], [BLAST, "BLAST", "BLAST"], [LOOT, "LOOT", "LOOT"]]

var world: World
var count := 0
## Seconds since the chain last changed. Each PC counts it for the HUD; the host acts on it.
var idle := 0.0
## Host: the chain when the round was last released.
var release := 0


static func hit_pad(level: int) -> float:
	return WIDE_PAD if level >= WIDE else 0.0


static func speed_scale(level: int, recall: bool) -> float:
	return RECALL_FAST if recall and level >= WIDE else 1.0


static func perk(level: int, recall: bool) -> String:
	var name := ""
	for p: Array in PERKS:
		if level >= p[0]:
			name = p[2 if recall else 1]
	return name


## Called on every PC when a room (re)starts.
func reset() -> void:
	count = 0
	idle = 0.0
	release = 0


func _physics_process(delta: float) -> void:
	if count == 0 or not world.playing():
		return
	idle += delta
	if Net.is_host() and idle >= DECAY:
		host_break()


# --- Host ------------------------------------------------------------------------

## The round leaves the gun or the wall: returns the chain level that buffs this flight.
func host_release() -> int:
	release = count
	return count


func host_add(n := 1) -> void:
	_on_chain.rpc(count + n)


func host_break() -> void:
	if count > 0:
		_on_chain.rpc(0)


func host_drop() -> void:
	if count > 0:
		_on_chain.rpc(int(count * DROP_KEEP))


## Extra pickups for a kill while the released chain is high enough.
func bonus_drops(cause: String) -> Array:
	return LOOT_DROPS if release >= LOOT and cause in ROUND_KILLS else []


## Kills every enemy in reach of pos that it can see. Players are never hurt and Anchors still
## need a pincer. Returns the number of kills, each of which feeds the chain.
func host_blast(pos: Vector3, recall: bool) -> int:
	_on_blast.rpc(pos, recall)
	var kills := 0
	for e in world.room.enemies:
		if not e.alive or e.kind == Enemy.ANCHOR or e.chest().distance_to(pos) > BLAST_RADIUS:
			continue
		if world.has_los(pos, e.chest()):
			world.host_kill(e, (e.chest() - pos).normalized(), "blast")
			kills += 1
	if kills > 0:
		host_add(kills)
	return kills


# --- Broadcasts --------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _on_chain(value: int) -> void:
	var old := count
	count = value
	idle = 0.0
	Game.best_chain = maxi(Game.best_chain, value)
	world.hud.chain_changed(old, value)
	if value > old:
		Game.sfx("ui", false, null, -6.0, 1.0 + 0.08 * mini(value, 10))
	else:
		Game.sfx("glass", false, null, -8.0, 0.5)


@rpc("authority", "call_local", "reliable")
func _on_blast(pos: Vector3, recall: bool) -> void:
	var c := Util.CYAN if recall else Util.AMBER
	Fx.flash(world.fx, pos, c, 10.0, BLAST_RADIUS * 2.5, 0.35)
	Fx.burst(world.fx, pos, c, 28, 7.0, 0.09, 0.5, recall)
	Fx.ring(world.fx, pos, c, BLAST_RADIUS, 0.45, recall)
	Game.sfx("fire", recall, pos, 2.0, 0.5)
	world.shake(0.45)


## Brief slow-mo on every PC as a high-chain shot leaves the gun.
func slow_mo() -> void:
	Engine.time_scale = SLOWMO_SCALE
	get_tree().create_timer(SLOWMO_TIME, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)
