class_name Projectile
extends Node3D
## A visible, dodgeable shot. Enemy shots can be slowed by fields and frozen by Stasis;
## player shells explode on impact.

var from_player := false
var velocity := Vector3.ZERO
var gravity := 0.0
var damage := 10.0
var splash := 0.0
var element := ""
## Dusk's Decay orb: everything in the burst rots (corrodes and takes damage over time).
var decay := false
var color := Color(1.0, 0.5, 0.2)
var radius := 0.22
var life := 6.0
var frozen := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	if not from_player:
		add_to_group("chrono")
	_mesh = Kit.part(self, Kit.sphere(radius, 8, 5), Kit.glow(color, 4.0))
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := Kit.part(self, Kit.sphere(radius * 1.8, 8, 5), Kit.glow(color, 1.5, 0.35))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 1.2
	l.omni_range = 3.0
	add_child(l)


func can_freeze() -> bool:
	return frozen <= 0.0


func aim_point() -> Vector3:
	return global_position


func aim_radius() -> float:
	return 0.8


func freeze(t: float) -> void:
	frozen = t
	_mesh.material_override = Kit.glow(Color(0.55, 0.9, 1.0), 3.0)


func _physics_process(delta: float) -> void:
	if frozen > 0.0:
		frozen -= delta
		if frozen <= 0.0:
			# A frozen shot dissolves instead of resuming: Stasis is a reliable answer to a volley.
			Kit.burst(get_parent(), global_position, Color(0.55, 0.9, 1.0), 6, 2.0, 0.05, 0.3)
			queue_free()
		return
	var dt := delta * (1.0 if from_player else SlowField.scale_at(get_tree(), global_position))
	life -= dt
	if life <= 0.0:
		_explode(global_position)
		return
	velocity.y -= gravity * dt
	var from := global_position
	var to := from + velocity * dt
	var mask := Kit.L_WORLD | (Kit.L_ENEMY if from_player else Kit.L_PLAYER)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		if not from_player and hit.collider is Player:
			hit.collider.hurt(damage, from)
		elif from_player and hit.collider is Enemy and splash <= 0.0:
			hit.collider.take_hit(damage, false, element, hit.position, velocity.normalized())
		_explode(hit.position)
		return
	global_position = to
	if not from_player:
		for d in get_tree().get_nodes_in_group("decoys"):
			if d.global_position.distance_to(to + Vector3.DOWN) < 1.0:
				_explode(to)
				return


func _explode(at: Vector3) -> void:
	if splash > 0.0:
		Kit.shockwave(get_parent(), at, color, splash, 0.35)
		Kit.flash(get_parent(), at, color, 6.0, splash * 3.0, 0.2)
		Kit.sfx(get_parent(), "glass", at, 0.0, 0.5)
		for e in get_tree().get_nodes_in_group("enemies"):
			var d: float = e.aim_point().distance_to(at)
			if d < splash:
				e.take_hit(damage * (1.0 - 0.5 * d / splash), false, element, e.aim_point(), (e.global_position - at).normalized())
				if decay and not e.dead:
					e.decay(4.0, damage * 0.6)
	else:
		Kit.burst(get_parent(), at, color, 5, 3.0, 0.06, 0.25)
	queue_free()
