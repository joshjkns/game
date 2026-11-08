class_name SlowField
extends Node3D
## A bubble of slowed time. Enemies, shots and falling rocks inside it run at FACTOR speed.
## Anything time-aware asks SlowField.scale_at(position) each frame.

const FACTOR := 0.2
const LIFE := 6.0

var radius := 6.0
var burns := false
var _t := 0.0
var _mesh: MeshInstance3D


## Local time scale for enemy-side things: the global enemy clock, times any field here.
static func scale_at(tree: SceneTree, pos: Vector3) -> float:
	var s := 1.0
	for f in tree.get_nodes_in_group("slow_fields"):
		if f.global_position.distance_to(pos) < f.radius:
			s = minf(s, FACTOR)
	return s * Run.enemy_clock


func _ready() -> void:
	add_to_group("slow_fields")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = Kit.sphere(1.0, 32, 16)
	_mesh.material_override = Kit.field_mat(Color(0.95, 0.55, 0.25) if burns else Color(0.5, 0.45, 1.0))
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * 0.1
	add_child(_mesh)
	create_tween().tween_property(_mesh, "scale", Vector3.ONE * radius, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Kit.shockwave(get_parent(), global_position, Color(0.6, 0.5, 1.0), radius, 0.4)
	var l := OmniLight3D.new()
	l.light_color = Color(0.55, 0.45, 1.0)
	l.light_energy = 1.5
	l.omni_range = radius * 1.3
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	if burns:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(global_position) < radius:
				e.take_tick(15.0 * delta, Color(1.0, 0.6, 0.3))
	if _t > LIFE:
		remove_from_group("slow_fields")
		var tw := create_tween()
		tw.tween_property(_mesh, "scale", Vector3.ONE * 0.05, 0.25)
		tw.tween_callback(queue_free)
		set_process(false)
