class_name Faller
extends AnimatableBody3D
## A falling structure (boulder, icicle, broken masonry). A shadow ring warns where it lands.
## Stasis freezes it mid-air: it becomes a platform you can stand on. When the freeze ends
## it drops, and a released rock crushes enemies below. Landed rocks stay as cover.

enum State { WARN, FALL, FROZEN, LANDED }

const WARN_TIME := 1.3
const DROP_HEIGHT := 16.0
const HIT_RADIUS := 2.6

var size := 2.2
var color := Color("6b6f86")
var state := State.WARN
var fall_speed := 0.0
var released := false
var _t := 0.0
var _ground := Vector3.ZERO
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _ice: MeshInstance3D


## Call after adding to the tree: drops onto ground point `at`.
func drop_at(at: Vector3) -> void:
	_ground = at
	global_position = at + Vector3.UP * DROP_HEIGHT


func _ready() -> void:
	add_to_group("chrono")
	add_to_group("fallers")
	sync_to_physics = false
	collision_layer = Kit.L_WORLD
	collision_mask = 0
	var m := Kit.rock_mesh(Vector3(size, size * 1.1, size), randi())
	_mesh = Kit.part(self, m, Kit.toon(color, 0.04))
	_shape = CollisionShape3D.new()
	_shape.shape = m.create_convex_shape()
	_shape.disabled = true
	add_child(_shape)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 28
	tm.ring_segments = 3
	_ring_mat = Kit.glow(Color(1.0, 0.25, 0.2), 3.0, 0.8)
	_ring = MeshInstance3D.new()
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(_ring)
	_ring.ready.connect(func():
		_ring.global_position = _ground + Vector3.UP * 0.08
		_ring.scale = Vector3(HIT_RADIUS, 0.4, HIT_RADIUS) * 0.2)


func can_freeze() -> bool:
	return state == State.FALL or state == State.WARN or state == State.FROZEN


func aim_point() -> Vector3:
	return global_position


func aim_radius() -> float:
	return size * 0.8


func freeze(t: float) -> void:
	state = State.FROZEN
	_t = t
	_shape.disabled = false
	fall_speed = 0.0
	if _ice == null:
		_ice = Kit.part(self, Kit.sphere(size * 0.75, 10, 6), Kit.glow(Color(0.55, 0.9, 1.0), 1.2, 0.3))
	_ring_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.8)
	_ring_mat.emission = Color(0.55, 0.9, 1.0)


func _physics_process(delta: float) -> void:
	var ts := SlowField.scale_at(get_tree(), global_position)
	match state:
		State.WARN:
			_t += delta * ts
			if is_instance_valid(_ring):
				var k := clampf(_t / WARN_TIME, 0.0, 1.0)
				_ring.scale = Vector3(HIT_RADIUS * (0.2 + 0.8 * k), 0.4, HIT_RADIUS * (0.2 + 0.8 * k))
			if _t >= WARN_TIME:
				state = State.FALL
		State.FALL:
			var g := 30.0 * (3.0 if released and Run.has("gravity") else 1.0)
			fall_speed += g * delta * ts
			global_position.y -= fall_speed * delta * ts
			rotation.x += delta * ts * 0.8
			if global_position.y <= _ground.y + size * 0.4:
				global_position.y = _ground.y + size * 0.4
				_land()
		State.FROZEN:
			_t -= delta
			if _t <= 0.0:
				state = State.FALL
				released = true
				_shape.disabled = true
				if _ice:
					_ice.queue_free()
					_ice = null
				if is_instance_valid(_ring):
					_ring.global_position = Vector3(global_position.x, _ground.y + 0.08, global_position.z)
					_ring_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
					_ring_mat.emission = Color(1.0, 0.6, 0.2)


func _land() -> void:
	state = State.LANDED
	remove_from_group("chrono")
	_shape.disabled = false
	if is_instance_valid(_ring):
		_ring.queue_free()
	var world := get_parent()
	var at := Vector3(global_position.x, _ground.y, global_position.z)
	Kit.shockwave(world, at, Color(1.0, 0.75, 0.45), HIT_RADIUS * 1.3, 0.4)
	Kit.burst(world, at + Vector3.UP * 0.3, color.lightened(0.3), 14, 6.0, 0.18, 0.6)
	Kit.sfx(world, "glass", at, 2.0, 0.4)
	var mult := (3.0 if Run.has("gravity") else 1.0) if released else 1.0
	for p in get_tree().get_nodes_in_group("player"):
		if not released and p.global_position.distance_to(at) < HIT_RADIUS:
			p.hurt(30.0, at)
			p.velocity += (p.global_position - at).normalized() * 8.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(at) < HIT_RADIUS + e.size * 0.5:
			e.take_hit((140.0 if released else 45.0) * mult, released, "", e.aim_point(), Vector3.DOWN)
	# Landed rocks become cover for a while, then crumble away.
	var tw := create_tween()
	tw.tween_interval(25.0)
	tw.tween_property(self, "position:y", position.y - size, 2.0)
	tw.tween_callback(queue_free)


func _exit_tree() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
