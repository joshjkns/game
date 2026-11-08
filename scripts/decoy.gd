class_name Decoy
extends Node3D
## Afterimage power: a glowing copy of the player that enemies chase for a moment.

var life := 2.0


func _ready() -> void:
	add_to_group("decoys")
	var m := Kit.glow(Color(0.55, 0.5, 1.0), 2.0, 0.5)
	var body := CapsuleMesh.new()
	body.radius = 0.4
	body.height = 1.8
	Kit.part(self, body, m, Vector3(0, 0.9, 0))


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
