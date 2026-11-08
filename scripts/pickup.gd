class_name Pickup
extends Node3D
## Coins and health orbs: pop out of enemies, bounce, then fly to the player when near.

var kind := "coin"
var value := 1
var velocity := Vector3.ZERO
var _magnet := false
var _age := 0.0
var _mesh: MeshInstance3D
var _ground := 0.0


static func drop_coins(world: Node, at: Vector3, count: int) -> void:
	var total := int(round(count * (1.0 + Run.stat("coins"))))
	for i in total:
		drop(world, at, "coin")


static func drop(world: Node, at: Vector3, k: String) -> void:
	var p := Pickup.new()
	p.kind = k
	p.velocity = Vector3(randf_range(-3, 3), randf_range(5, 8), randf_range(-3, 3))
	world.add_child(p)
	p.global_position = at


func _ready() -> void:
	if kind == "coin":
		var m := Kit.toon(Color("ffc93a"), 0.012, Color("6b3d0a"))
		m.emission_enabled = true
		m.emission = Color("ff9a1a")
		m.emission_energy_multiplier = 0.5
		_mesh = Kit.part(self, Kit.cyl(0.16, 0.16, 0.04, 10), m, Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
		Kit.cube(_mesh, Kit.toon(Color("c2781a")), Vector3(0, 0.025, 0), Vector3(0.12, 0.01, 0.12), Vector3(0, PI / 4, 0))
	else:
		_mesh = Kit.part(self, Kit.sphere(0.2, 8, 5), Kit.glow(Color(0.35, 1.0, 0.45), 3.0))
		Kit.part(self, Kit.sphere(0.32, 8, 5), Kit.glow(Color(0.35, 1.0, 0.45), 1.0, 0.3))
	_ground = global_position.y - 2.0
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 30.0, Kit.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		_ground = hit.position.y + 0.25


func _process(delta: float) -> void:
	_age += delta
	_mesh.rotation.y += delta * 4.0
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return
	var p: Player = ps[0]
	var to := p.chest() - global_position
	if not _magnet and _age > 0.5 and to.length() < 6.0 and (kind == "coin" or Run.hp < Run.max_hp()):
		_magnet = true
	if _magnet:
		velocity = velocity.lerp(to.normalized() * (14.0 + _age * 6.0), 1.0 - exp(-10.0 * delta))
		global_position += velocity * delta
		if to.length() < 0.7:
			_collect(p)
		return
	velocity.y -= 20.0 * delta
	global_position += velocity * delta
	if global_position.y < _ground:
		global_position.y = _ground
		velocity *= Vector3(0.6, -0.35, 0.6)
	if _age > 40.0:
		queue_free()


func _collect(p: Player) -> void:
	if kind == "coin":
		Run.add_coins(1)
		Kit.sfx(p, "ping", null, -16.0, 1.8 + randf() * 0.3)
	else:
		p.heal(20.0)
		Kit.sfx(p, "catch", null, -8.0, 1.4)
	queue_free()
