class_name Enemy
extends StaticBody3D
## Static target that dies in one hit. A shielded enemy ignores bullets
## travelling into its face and only dies when hit from the side or behind.

var alive := true
var shielded := false
var facing := Vector3.BACK

var _mat: StandardMaterial3D
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = Util.LAYER_ENEMY
	collision_mask = 0
	rotation.y = atan2(-facing.x, -facing.z)

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_shape.shape = cap
	_shape.position.y = 0.9
	add_child(_shape)

	_mat = Util.mat(Util.COLOR_ENEMY, 0.3)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	body.mesh = cm
	body.position.y = 0.9
	body.material_override = _mat
	add_child(body)

	var eye := Util.box(Vector3(0.5, 0.12, 0.1), Util.mat(Color.WHITE, 2.0))
	eye.position = Vector3(0, 1.45, -0.36)
	add_child(eye)

	if shielded:
		var shield := Util.box(Vector3(1.3, 1.7, 0.15), Util.mat(Color(0.75, 0.8, 0.9), 0.2))
		shield.position = Vector3(0, 0.9, -0.62)
		add_child(shield)


## True when a bullet travelling along dir would hit the shield.
func blocks(dir: Vector3) -> bool:
	return shielded and dir.dot(facing) < -0.1


func set_targeted(on: bool) -> void:
	if not alive:
		return
	_mat.emission = Color(1.0, 0.9, 0.2) if on else Util.COLOR_ENEMY
	_mat.emission_energy_multiplier = 1.5 if on else 0.3


func die() -> void:
	if not alive:
		return
	alive = false
	_shape.set_deferred("disabled", true)
	_mat.emission = Color.WHITE
	_mat.emission_energy_multiplier = 4.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.6, 0.05, 1.6), 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
