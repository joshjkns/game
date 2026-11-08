class_name Viewmodel
extends Node3D
## First-person hands and revolver, driven by tweens. NOEL's animations are LEON's played
## backwards: recall is fire reversed, pull is punch reversed, and the cylinder spins anticlockwise.

const GUN_REST := Vector3(0.16, -0.16, -0.36)
const FIST_REST := Vector3(0.24, -0.33, -0.42)
const OFF_REST := Vector3(-0.26, -0.36, -0.44)
const PROP_REST := Vector3(0.22, -0.24, -0.5)
## Opening shot: the gun held low and close, tipped up toward the eye, cylinder swung out.
const INSPECT_POS := Vector3(0.03, -0.13, -0.3)
const INSPECT_ROT := Vector3(0.95, 0.2, 0.65)
const CYL_OUT := Vector3(0.105, -0.02, 0.0)

var role := "A"
var gun: GunModel
var gun_pivot: Node3D
var fist: MeshInstance3D
var off_hand: MeshInstance3D
var prop_pivot: Node3D

var _held_kind := -1
var _bob := 0.0
var _sway := Vector2.ZERO
var _anim: Tween
var _cyl_rest := Vector3.ZERO


func _ready() -> void:
	gun_pivot = Node3D.new()
	gun_pivot.position = GUN_REST
	add_child(gun_pivot)
	gun = GunModel.new()
	gun.scale = Vector3.ONE * 0.62
	gun_pivot.add_child(gun)
	_cyl_rest = gun.cyl.position
	var sleeve_col := Color(0.2, 0.13, 0.08) if role == Util.A else Color(0.07, 0.1, 0.13)
	var glove := Util.mat(Color(0.09, 0.065, 0.05), 0.0, 1.0, 0.55)
	var sleeve := Util.mat(sleeve_col, 0.0, 1.0, 0.7)
	var cuff_mat := Util.glow(Util.role_color(role), 2.5)
	# Gun hand: a gloved fist around the grip, sleeve running back out of frame.
	var gun_hand := _glove(glove, sleeve, cuff_mat, true)
	gun_hand.position = Vector3(0.0, -0.11, 0.1)
	gun_hand.rotation.x = -0.35
	gun_pivot.add_child(gun_hand)
	# A small fill light so the hero gun reads in dark rooms.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.8, 0.6)
	fill.light_energy = 0.5
	fill.omni_range = 1.4
	fill.position = Vector3(0.0, 0.15, -0.1)
	add_child(fill)

	fist = _glove(glove, sleeve, cuff_mat, false)
	fist.position = FIST_REST
	add_child(fist)
	off_hand = _glove(glove, sleeve, cuff_mat, false)
	off_hand.position = OFF_REST
	off_hand.scale = Vector3(-1, 1, 1)
	add_child(off_hand)

	prop_pivot = Node3D.new()
	prop_pivot.position = PROP_REST
	add_child(prop_pivot)
	_set_layers(self)


## A gloved fist with knuckles, thumb, a glowing cuff and the coat sleeve.
func _glove(glove: Material, sleeve: Material, cuff: Material, holding: bool) -> MeshInstance3D:
	var palm := Util.box(Vector3(0.085, 0.08, 0.1), glove)
	for i in 4:
		var f := Util.box(Vector3(0.019, 0.04, 0.05), glove)
		f.position = Vector3(-0.031 + i * 0.0207, 0.012 if holding else 0.0, -0.065)
		f.rotation.x = 0.9 if holding else 0.3
		palm.add_child(f)
		var k := Util.box(Vector3(0.018, 0.012, 0.012), glove)
		k.position = Vector3(-0.031 + i * 0.0207, 0.042, -0.05)
		palm.add_child(k)
	var thumb := Util.box(Vector3(0.022, 0.022, 0.06), glove)
	thumb.position = Vector3(-0.05, 0.01, -0.03)
	thumb.rotation.y = 0.5
	palm.add_child(thumb)
	var wrist := Util.cylinder(0.042, 0.06, glove, 10)
	wrist.rotation.x = PI * 0.5
	wrist.position.z = 0.07
	palm.add_child(wrist)
	var c := Util.cylinder(0.05, 0.025, cuff, 12)
	c.rotation.x = PI * 0.5
	c.position.z = 0.11
	palm.add_child(c)
	var arm := Util.cylinder(0.055, 0.42, sleeve, 12)
	(arm.mesh as CylinderMesh).top_radius = 0.048
	arm.rotation.x = PI * 0.5
	arm.position = Vector3(0, -0.01, 0.33)
	palm.add_child(arm)
	return palm


## Keep viewmodel meshes from casting shadows into the world.
func _set_layers(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_layers(c)


func show_gun(on: bool) -> void:
	gun_pivot.visible = on
	fist.visible = not on


func set_loaded(loaded: bool) -> void:
	gun.set_loaded(loaded, Util.role_color(role))


func show_prop(kind: int) -> void:
	if kind == _held_kind:
		return
	_held_kind = kind
	for c in prop_pivot.get_children():
		c.queue_free()
	if kind < 0:
		return
	var m: MeshInstance3D
	match kind:
		Prop.BOTTLE:
			m = Util.cylinder(0.06, 0.26, Util.mat(Color(0.08, 0.22, 0.1), 0.2, 0.92, 0.08, 0.2))
		Prop.STOOL:
			m = Util.cylinder(0.18, 0.06, Util.mat(Color(0.36, 0.22, 0.12), 0.0, 1.0, 0.7))
		_:
			m = Util.cylinder(0.2, 0.025, Util.mat(Color(0.45, 0.45, 0.47), 0.0, 1.0, 0.3, 0.9), 18)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop_pivot.add_child(m)
	prop_pivot.scale = Vector3.ONE * 0.01
	create_tween().tween_property(prop_pivot, "scale", Vector3.ONE, 0.15)


func muzzle_global() -> Vector3:
	return gun.muzzle.global_position


func _restart() -> Tween:
	if _anim and _anim.is_valid():
		_anim.kill()
	_anim = create_tween()
	return _anim


func anim_fire() -> void:
	var tw := _restart()
	gun_pivot.position = GUN_REST
	gun_pivot.rotation = Vector3.ZERO
	tw.set_parallel()
	tw.tween_property(gun_pivot, "rotation:x", 0.55, 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun_pivot, "position:z", GUN_REST.z + 0.12, 0.06)
	tw.tween_property(gun.cyl, "rotation:y", gun.cyl.rotation.y - TAU / 6.0, 0.12)
	tw.chain().tween_property(gun_pivot, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gun_pivot, "position:z", GUN_REST.z, 0.3)


## Fire played backwards: the gun drifts up into a kick, then snaps forward as the round arrives.
func anim_recall_start() -> void:
	var tw := _restart()
	tw.tween_property(gun_pivot, "rotation:x", 0.35, 0.25).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(gun_pivot, "position:z", GUN_REST.z + 0.08, 0.25)
	tw.parallel().tween_property(gun.cyl, "rotation:y", gun.cyl.rotation.y + TAU, 0.6)


func anim_recall_end() -> void:
	var tw := _restart()
	tw.tween_property(gun_pivot, "rotation:x", -0.2, 0.05)
	tw.parallel().tween_property(gun_pivot, "position:z", GUN_REST.z - 0.06, 0.05)
	tw.tween_property(gun_pivot, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gun_pivot, "position:z", GUN_REST.z, 0.3)


## Spin on the finger. NOEL's twirl runs the other way.
func anim_catch() -> void:
	var tw := _restart()
	var dir := -1.0 if role == Util.A else 1.0
	gun_pivot.rotation = Vector3.ZERO
	gun_pivot.position = GUN_REST + Vector3(0, -0.15, 0)
	tw.set_parallel()
	tw.tween_property(gun_pivot, "rotation:x", TAU * dir, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun_pivot, "position", GUN_REST, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun.cyl, "rotation:y", gun.cyl.rotation.y + TAU * dir, 0.5)
	tw.chain().tween_callback(func() -> void: gun_pivot.rotation = Vector3.ZERO)


func anim_throw() -> void:
	var tw := _restart()
	tw.tween_property(off_hand, "position", OFF_REST + Vector3(0.2, 0.1, -0.25), 0.08)
	tw.tween_property(off_hand, "position", OFF_REST, 0.2)


func anim_punch() -> void:
	var tw := _restart()
	fist.position = FIST_REST
	tw.tween_property(fist, "position", Vector3(0.05, -0.12, -0.75), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(fist, "position", FIST_REST, 0.18).set_trans(Tween.TRANS_QUAD)


## Punch reversed: the open hand starts extended and yanks back to the body.
func anim_pull() -> void:
	var tw := _restart()
	fist.position = Vector3(0.05, -0.12, -0.75)
	fist.scale = Vector3(1.3, 0.6, 1.0)
	tw.tween_property(fist, "position", FIST_REST, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(fist, "scale", Vector3.ONE, 0.18)


func anim_reverse_bullet() -> void:
	var tw := _restart()
	tw.tween_property(off_hand, "position", Vector3(-0.1, -0.15, -0.6), 0.08)
	tw.tween_property(off_hand, "rotation:z", TAU * 0.5, 0.15)
	tw.tween_property(off_hand, "position", OFF_REST, 0.15)
	tw.tween_callback(func() -> void: off_hand.rotation.z = 0.0)


## The opening: look down at what is in your hands. LEON holds the revolver with the cylinder
## swung out; it clicks round twice to the one round, flicks shut, and comes up to rest.
## NOEL looks at empty hands. Runs for about `dur` seconds.
func anim_opening(dur: float) -> void:
	var tw := _restart()
	if gun_pivot.visible:
		gun_pivot.position = INSPECT_POS
		gun_pivot.rotation = INSPECT_ROT
		gun.cyl.position = _cyl_rest + CYL_OUT
		gun.cyl.rotation.y = -TAU / 3.0
		off_hand.position = Vector3(-0.1, -0.24, -0.34)
		tw.tween_interval(dur * 0.45)
		for i in 2:
			tw.tween_callback(func() -> void: Game.sfx("ui", false, null, -4.0, 0.55 + i * 0.06))
			tw.tween_property(gun.cyl, "rotation:y", -TAU / 3.0 + (i + 1) * TAU / 6.0, 0.14) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.3)
		tw.tween_interval(0.25)
		# Flick it shut.
		tw.tween_callback(func() -> void: Game.sfx("catch", false, null, -2.0, 0.85))
		tw.tween_property(gun.cyl, "position", _cyl_rest, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(gun_pivot, "rotation:z", INSPECT_ROT.z - 0.5, 0.08)
		tw.tween_property(gun_pivot, "rotation:z", INSPECT_ROT.z, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.2)
		tw.tween_property(gun_pivot, "position", GUN_REST, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(gun_pivot, "rotation", Vector3.ZERO, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(off_hand, "position", OFF_REST, 0.7)
	else:
		fist.position = Vector3(0.1, -0.2, -0.32)
		fist.rotation = Vector3(0.9, 0, 0.4)
		off_hand.position = Vector3(-0.1, -0.21, -0.33)
		off_hand.rotation = Vector3(0.9, 0, -0.4)
		tw.tween_interval(dur * 0.7)
		tw.tween_property(fist, "position", FIST_REST, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(fist, "rotation", Vector3.ZERO, 0.7)
		tw.parallel().tween_property(off_hand, "position", OFF_REST, 0.7)
		tw.parallel().tween_property(off_hand, "rotation", Vector3.ZERO, 0.7)


func tick(delta: float, speed: float, look: Vector2) -> void:
	_bob += delta * speed * 1.8
	var bob := Vector3(cos(_bob) * 0.008, absf(sin(_bob)) * 0.012, 0) * clampf(speed / 5.0, 0.0, 1.0)
	_sway = _sway.lerp(look * 0.0008, 1.0 - exp(-10.0 * delta))
	position = Vector3(-_sway.x, _sway.y, 0) + bob
