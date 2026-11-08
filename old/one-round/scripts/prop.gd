class_name Prop
extends RigidBody3D
## A throwable prop: wine bottle, stool or pewter platter. The host simulates it; clients follow snapshots.
## A thrown prop disarms an armed enemy, or kills one that is already disarmed.

enum { BOTTLE, STOOL, TRAY }

var id := 0
var kind := BOTTLE
## Role holding it ("" = loose in the world).
var holder := ""
## Role that threw it last.
var thrower := ""
## True while flying from a throw and able to hit something.
var lethal := false
## Host only: homing towards NOEL's hand during an un-throw.
var unthrow_to := ""
var hit_ids := {}

var net_xf := Transform3D.IDENTITY
var start_xf := Transform3D.IDENTITY


func _ready() -> void:
	collision_layer = Util.L_PROP
	collision_mask = Util.L_WORLD | Util.L_GLASS | Util.L_ENEMY | Util.L_PROP | Util.L_GATE
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	start_xf = global_transform
	net_xf = global_transform

	var cs := CollisionShape3D.new()
	match kind:
		BOTTLE:
			mass = 0.6
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.08
			cyl.height = 0.34
			cs.shape = cyl
			var gm := Util.mat(Color(0.08, 0.22, 0.1), 0.0, 0.92, 0.08, 0.2)
			var glass := Util.cylinder(0.08, 0.24, gm, 12)
			glass.position.y = -0.05
			add_child(glass)
			var shoulder := Util.sphere(0.08, gm)
			shoulder.scale = Vector3(1, 0.5, 1)
			shoulder.position.y = 0.07
			add_child(shoulder)
			var neck := Util.cylinder(0.028, 0.1, gm, 8)
			neck.position.y = 0.13
			add_child(neck)
			var cork := Util.cylinder(0.025, 0.04, Util.mat(Color(0.5, 0.35, 0.2), 0.0, 1.0, 0.9), 8)
			cork.position.y = 0.19
			add_child(cork)
			var label := Util.cylinder(0.082, 0.09, Util.mat(Color(0.7, 0.62, 0.45), 0.0, 1.0, 0.9), 12)
			label.position.y = -0.06
			add_child(label)
		STOOL:
			mass = 2.5
			var c2 := CylinderShape3D.new()
			c2.radius = 0.22
			c2.height = 0.6
			cs.shape = c2
			var seat := Util.cylinder(0.22, 0.06, Mats.wood(), 14)
			seat.position.y = 0.27
			add_child(seat)
			for i in 3:
				var a := TAU * i / 3.0
				var leg := Util.cylinder(0.025, 0.58, Mats.dark_wood(), 6)
				leg.position = Vector3(cos(a) * 0.13, -0.02, sin(a) * 0.13)
				leg.rotation = Vector3(sin(a) * 0.18, 0, -cos(a) * 0.18)
				add_child(leg)
		TRAY:
			mass = 1.0
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.5, 0.04, 0.34)
			cs.shape = bx
			var plate := Util.cylinder(0.24, 0.03, Util.mat(Color(0.45, 0.45, 0.47), 0.0, 1.0, 0.3, 0.9), 18)
			plate.scale = Vector3(1, 1, 0.72)
			add_child(plate)
			var rim := Util.cylinder(0.25, 0.02, Mats.gold(), 18)
			rim.scale = Vector3(1, 1, 0.72)
			rim.position.y = 0.015
			add_child(rim)
	add_child(cs)
	if not Net.is_host():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


func reset() -> void:
	holder = ""
	thrower = ""
	lethal = false
	unthrow_to = ""
	hit_ids.clear()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = start_xf
	net_xf = start_xf


func _process(delta: float) -> void:
	# Hide the world copy for whoever holds it: their viewmodel shows it instead.
	visible = not (holder != "" and Game.world and holder == Game.world.local_role)
	if Net.is_host():
		return
	global_transform = global_transform.interpolate_with(net_xf, 1.0 - exp(-20.0 * delta))


func _on_body_entered(body: Node) -> void:
	if not Net.is_host() or not lethal or Game.world == null:
		return
	if linear_velocity.length() < 3.0:
		return
	if body is Enemy and not hit_ids.has((body as Enemy).id):
		hit_ids[(body as Enemy).id] = true
		Game.world.host_hit_enemy(body, "prop", linear_velocity.normalized(), thrower)
		lethal = false
	elif body is Glass and (body as Glass).intact and (body as Glass).fragile():
		Game.world.host_set_glass((body as Glass).id, false, thrower)
