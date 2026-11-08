class_name EnemyBullet
extends Node3D
## A slow, visible enemy round. The host spawns it. Its motion is deterministic, so each PC
## simulates it locally, and each PC decides whether it hit its own player (victim decides).
## NOEL can reverse one: it turns cyan and flies back at its shooter, lethal only to enemies.

const RADIUS := 0.12
const LIFETIME := 15.0

var id := 0
var dir := Vector3.FORWARD
var speed := 8.0
var reversed := false
var shooter := -1
var age := 0.0

var _core_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
var _light: OmniLight3D
var _visual: Node3D


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_core_mat = Util.glow(Util.RED, 6.0)
	var core := Util.capsule(0.07, 0.4, _core_mat)
	core.rotation.x = PI * 0.5
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(core)
	_trail_mat = Util.glow(Util.RED, 3.0, 0.35)
	var trail := Util.box(Vector3(0.05, 0.05, 1.4), _trail_mat)
	trail.position.z = 0.85
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(trail)
	_light = OmniLight3D.new()
	_light.light_color = Util.RED
	_light.light_energy = 1.5
	_light.omni_range = 2.5
	add_child(_light)
	_orient()


func _orient() -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_visual.global_basis = Basis.looking_at(dir, up)


func reverse(pos: Vector3, new_dir: Vector3, new_speed: float) -> void:
	global_position = pos
	dir = new_dir
	speed = new_speed
	reversed = true
	age = 0.0
	_core_mat.albedo_color = Util.CYAN * 6.0
	_trail_mat.albedo_color = Color(Util.CYAN * 3.0, 0.35)
	_light.light_color = Util.CYAN
	_orient()


## Advance one step. Returns false when the bullet is spent.
func step(delta: float, world: World) -> bool:
	var prev := global_position
	var next := prev + dir * speed * delta
	age += delta
	if age > LIFETIME:
		return false
	var q := PhysicsRayQueryParameters3D.create(prev, next + dir * RADIUS, Util.L_WORLD | Util.L_GLASS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		Fx.burst(world.fx, hit.position, Util.CYAN if reversed else Util.RED, 6, 2.0, 0.04, 0.25, false)
		return false
	if reversed:
		if Net.is_host():
			for e in world.room.enemies:
				if not e.alive:
					continue
				var cap := e.hit_capsule()
				var res := Util.segment_vs_capsule(prev, next, e.global_position, cap[0], cap[1])
				if res[0] < cap[2] + RADIUS:
					world.host_reversed_hit(self, e)
					return false
	else:
		for p: Player in world.players.values():
			if not p.alive or not p.is_local():
				continue
			var res := Util.segment_vs_capsule(prev, next, p.global_position, 0.2, p.body_height() - 0.1)
			if res[0] < Player.RADIUS + RADIUS:
				world.local_player_hit(p, dir)
				return false
	global_position = next
	return true
