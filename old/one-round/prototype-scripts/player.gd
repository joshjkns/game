class_name Player
extends CharacterBody3D
## A co-op player. FORWARD (A) can only fire the gun, INVERTED (B) can only recall.

enum Role { FORWARD, INVERTED }

const SPEED := 6.0
const GRAVITY := 20.0

var role: Role = Role.FORWARD
var gun: Gun
var hand: Marker3D
var aim_dir := Vector3(0, 0, -1)
var frozen := false

var _p := "a_"
var _mouse_aim := false


func _ready() -> void:
	_p = "a_" if role == Role.FORWARD else "b_"
	collision_layer = Util.LAYER_PLAYER
	collision_mask = Util.LAYER_WORLD | Util.LAYER_PLAYER | Util.LAYER_ENEMY | Util.LAYER_GLASS

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	mi.material_override = Util.mat(color(), 0.25)
	add_child(mi)

	var visor := Util.box(Vector3(0.45, 0.15, 0.12), Util.mat(Color(0.1, 0.1, 0.12)))
	visor.position = Vector3(0, 1.4, -0.32)
	add_child(visor)

	hand = Marker3D.new()
	hand.position = Vector3(0.0, Util.BULLET_Y, -0.45)
	add_child(hand)

	var label := Label3D.new()
	label.text = "A" if role == Role.FORWARD else "B"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96
	label.outline_size = 24
	label.modulate = color()
	label.position.y = 2.3
	add_child(label)


func color() -> Color:
	return Util.COLOR_A if role == Role.FORWARD else Util.COLOR_B


func chest() -> Vector3:
	return global_position + Vector3(0, Util.BULLET_Y, 0)


func _unhandled_input(event: InputEvent) -> void:
	if role == Role.FORWARD and event is InputEventMouseMotion:
		_mouse_aim = true


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	velocity.y -= GRAVITY * delta

	var move := Vector3.ZERO
	if not frozen:
		var v := Input.get_vector(_p + "left", _p + "right", _p + "up", _p + "down")
		move = Vector3(v.x, 0, v.y)
	velocity.x = move.x * SPEED
	velocity.z = move.z * SPEED
	move_and_slide()

	if frozen:
		return
	_update_aim(move)
	if Input.is_action_just_pressed(_p + "grab"):
		gun.try_grab(self)
	if Input.is_action_just_pressed(_p + "use"):
		gun.try_use(self)


func _update_aim(move: Vector3) -> void:
	var a := Vector3.ZERO
	if role == Role.FORWARD:
		var stick := Input.get_vector("a_aim_left", "a_aim_right", "a_aim_up", "a_aim_down")
		if stick.length() > 0.3:
			a = Vector3(stick.x, 0, stick.y)
			_mouse_aim = false
		elif _mouse_aim:
			a = Util.flat(_mouse_point() - global_position)
		else:
			a = move
	else:
		# Inverted player snaps their aim to the lodged bullet.
		if gun.holder == self and gun.bullet_state == Gun.Bullet.LODGED:
			a = Util.flat(gun.lodged_pos - global_position)
		else:
			a = move
	if a.length() > 0.05:
		aim_dir = a.normalized()
		rotation.y = atan2(-aim_dir.x, -aim_dir.z)


func _mouse_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position + aim_dir
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var n := cam.project_ray_normal(mp)
	if absf(n.y) < 0.001:
		return global_position + aim_dir
	var t := (Util.BULLET_Y - o.y) / n.y
	return o + n * t
