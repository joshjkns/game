class_name Humanoid
extends Node3D
## A jointed, low-poly person built from primitives: hips, spine, chest, head, two-part arms
## and legs, plus costume pieces per style. Animated procedurally: walk cycle from how fast
## it is actually moving, aim pose, hands-up (disarmed), stagger (stunned) and breathing.
## Faces -Z like everything else. Total height about 1.8 m.

enum Style { LEON, NOEL, CULTIST, KNIGHT, STATUE }

var style := Style.CULTIST
var accent := Util.RED
## 0..1 blend into the aim pose (right arm forward).
var aim := 0.0
var aim_pitch := 0.0
## Two-handed weapon (left hand supports the stock).
var two_handed := true
## 0..1 blend into hands-up.
var hands_up := 0.0
var stagger := 0.0
## 0..1 blend into a low crouch (sliding or crouched under a gap).
var crouch := 0.0
## Set false for statues: no animation.
var animated := true

var hips: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var cape: Node3D
var flap_l: Node3D
var flap_r: Node3D
## Attach the held weapon here: its -Z points where the arm points.
var weapon_socket: Node3D
var eye_mat: StandardMaterial3D

var _speed := 0.0
var _phase := 0.0
var _t := 0.0
var _last := Vector3.ZERO
var _meshes: Array[MeshInstance3D] = []
var _saved := {}
var _hips_y := 0.98

var _body: Material
var _cloth: Material
var _skin: Material
var _boot: Material
var _trim: StandardMaterial3D


func _init(s := Style.CULTIST, accent_color := Util.RED) -> void:
	style = s
	accent = accent_color


func _ready() -> void:
	_pick_materials()
	_build()
	_last = global_position
	_t = randf() * 10.0
	_phase = randf() * TAU


func _pick_materials() -> void:
	_trim = Util.glow(accent, 2.6)
	eye_mat = Util.glow(accent, 5.0)
	_skin = Util.mat(Color(0.55, 0.4, 0.32), 0.0, 1.0, 0.7)
	_boot = Util.mat(Color(0.07, 0.05, 0.04), 0.0, 1.0, 0.55)
	match style:
		Style.LEON:
			_body = Util.mat(Color(0.2, 0.13, 0.08), 0.0, 1.0, 0.55)  # oiled leather coat
			_cloth = Util.mat(Color(0.12, 0.1, 0.09), 0.0, 1.0, 0.85)
		Style.NOEL:
			_body = Util.mat(Color(0.07, 0.1, 0.13), 0.0, 1.0, 0.85)  # dark teal cloak
			_cloth = Util.mat(Color(0.13, 0.15, 0.17), 0.0, 1.0, 0.9)
		Style.CULTIST:
			_body = Util.mat(Color(0.2, 0.05, 0.05), 0.0, 1.0, 0.92)  # oxblood robe
			_cloth = Util.mat(Color(0.08, 0.06, 0.06), 0.0, 1.0, 0.9)
			_skin = Util.mat(Color(0.32, 0.27, 0.25), 0.0, 1.0, 0.7)
		Style.KNIGHT:
			_body = Util.mat(Color(0.32, 0.31, 0.3), 0.0, 1.0, 0.32, 0.9)  # plate
			_cloth = Util.mat(Color(0.25, 0.04, 0.04), 0.0, 1.0, 0.9)
			_skin = _body
		Style.STATUE:
			_body = Mats.marble()
			_cloth = _body
			_skin = _body
			_boot = _body
			_trim = null


func _add(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _taper(top: float, bottom: float, h: float, m: Material, sides := 10) -> MeshInstance3D:
	var mi := Util.cylinder(top, h, m, sides)
	(mi.mesh as CylinderMesh).bottom_radius = bottom
	return mi


func _build() -> void:
	var big := style == Style.KNIGHT
	var robe := style == Style.CULTIST
	hips = _pivot(self, Vector3(0, _hips_y, 0))
	_add(hips, Util.box(Vector3(0.32, 0.16, 0.2), _cloth), Vector3(0, 0, 0))

	# Legs.
	for side in [-1, 1]:
		var leg := _pivot(hips, Vector3(0.1 * side, -0.04, 0))
		_add(leg, Util.capsule(0.085, 0.5, _cloth), Vector3(0, -0.22, 0))
		var knee := _pivot(leg, Vector3(0, -0.45, 0))
		_add(knee, Util.capsule(0.07, 0.48, _boot if style != Style.STATUE else _cloth), Vector3(0, -0.22, 0))
		_add(knee, Util.box(Vector3(0.11, 0.08, 0.24), _boot), Vector3(0, -0.46, -0.05))
		if big:
			_add(knee, Util.box(Vector3(0.13, 0.16, 0.1), _body), Vector3(0, -0.02, -0.06))
		if side < 0:
			leg_l = leg
			knee_l = knee
		else:
			leg_r = leg
			knee_r = knee

	# Torso.
	spine = _pivot(hips, Vector3(0, 0.08, 0))
	_add(spine, _taper(0.15, 0.15, 0.24, _body), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.72))
	chest = _pivot(spine, Vector3(0, 0.2, 0))
	_add(chest, _taper(0.205, 0.155, 0.34, _body), Vector3(0, 0.16, 0), Vector3.ZERO, Vector3(1.12, 1, 0.7))
	_add(chest, Util.sphere(0.12, _body), Vector3(-0.17, 0.3, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
	_add(chest, Util.sphere(0.12, _body), Vector3(0.17, 0.3, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
	_add(chest, Util.cylinder(0.05, 0.12, _skin, 8), Vector3(0, 0.38, 0))
	# Belt.
	_add(spine, Util.box(Vector3(0.33, 0.06, 0.23), _boot), Vector3(0, 0.0, 0))
	if _trim and style != Style.KNIGHT:
		_add(spine, Util.box(Vector3(0.06, 0.05, 0.02), _trim), Vector3(0, 0.0, -0.12))

	head = _pivot(chest, Vector3(0, 0.44, 0))
	_add(head, Util.sphere(0.115, _skin), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(0.92, 1.08, 1.0))

	# Arms.
	for side in [-1, 1]:
		var arm := _pivot(chest, Vector3(0.235 * side, 0.29, 0))
		_add(arm, Util.capsule(0.062, 0.34, _body if style != Style.CULTIST else _body), Vector3(0, -0.14, 0))
		var elbow := _pivot(arm, Vector3(0, -0.29, 0))
		_add(elbow, Util.capsule(0.052, 0.3, _body), Vector3(0, -0.12, 0))
		var hand := _pivot(elbow, Vector3(0, -0.27, 0))
		_add(hand, Util.box(Vector3(0.075, 0.1, 0.045), _skin if style != Style.KNIGHT else _body), Vector3(0, -0.04, 0))
		if style in [Style.LEON, Style.NOEL] and _trim:
			_add(elbow, Util.box(Vector3(0.11, 0.025, 0.11), _trim), Vector3(0, -0.24, 0))
		if big:
			_add(arm, Util.sphere(0.13, _body), Vector3(0.03 * side, 0.0, 0), Vector3.ZERO, Vector3(1.2, 0.8, 1.1))
		if side < 0:
			arm_l = arm
			elbow_l = elbow
			hand_l = hand
		else:
			arm_r = arm
			elbow_r = elbow
			hand_r = hand
	weapon_socket = _pivot(hand_r, Vector3(0, -0.06, 0))
	weapon_socket.rotation.x = -PI * 0.5

	match style:
		Style.LEON: _costume_leon()
		Style.NOEL: _costume_noel()
		Style.CULTIST: _costume_cultist()
		Style.KNIGHT: _costume_knight()
		Style.STATUE: _costume_cultist()
	if robe:
		pass


## Gunslinger: long coat with tails, wide-brim hat, amber eyes under the brim.
func _costume_leon() -> void:
	flap_l = _pivot(hips, Vector3(-0.1, 0.02, 0))
	flap_r = _pivot(hips, Vector3(0.1, 0.02, 0))
	for f: Node3D in [flap_l, flap_r]:
		var s := signf(f.position.x)
		_add(f, Util.box(Vector3(0.2, 0.72, 0.27), _body), Vector3(0.02 * s, -0.36, 0.03), Vector3(0, 0, 0.05 * s))
		_add(f, Util.box(Vector3(0.02, 0.7, 0.02), _trim), Vector3(0.12 * s, -0.36, -0.1))
	_add(chest, Util.box(Vector3(0.3, 0.12, 0.05), _trim), Vector3(0, 0.36, -0.11), Vector3(0.2, 0, 0))  # collar glow
	var brim := _add(head, Util.cylinder(0.26, 0.02, _boot, 20), Vector3(0, 0.2, 0.0), Vector3(-0.08, 0, 0))
	brim.scale = Vector3(1, 1, 1.1)
	_add(head, _taper(0.1, 0.13, 0.15, _boot, 14), Vector3(0, 0.28, 0.01))
	_add(head, Util.cylinder(0.131, 0.03, _trim, 14), Vector3(0, 0.22, 0.01))
	_add(head, Util.box(Vector3(0.17, 0.025, 0.03), eye_mat), Vector3(0, 0.12, -0.105))
	_add(head, Util.box(Vector3(0.2, 0.08, 0.15), _cloth), Vector3(0, 0.02, -0.04))  # scarf over mouth


## Hooded wanderer: cloak cape, deep hood, cyan eyes in the shadow.
func _costume_noel() -> void:
	cape = _pivot(chest, Vector3(0, 0.36, 0.12))
	_add(cape, Util.box(Vector3(0.5, 1.15, 0.04), _body), Vector3(0, -0.58, 0.02))
	_add(cape, Util.box(Vector3(0.5, 0.03, 0.05), _trim), Vector3(0, -1.15, 0.02))
	_add(head, Util.sphere(0.16, _body), Vector3(0, 0.12, 0.03), Vector3.ZERO, Vector3(1, 1.08, 1.12))
	_add(head, _taper(0.0, 0.08, 0.2, _body, 8), Vector3(0, 0.2, 0.14), Vector3(-1.1, 0, 0))
	_add(head, Util.box(Vector3(0.2, 0.2, 0.05), Util.mat(Color(0.01, 0.01, 0.015), 0.0, 1.0, 1.0)), Vector3(0, 0.1, -0.11))
	_add(head, Util.box(Vector3(0.04, 0.02, 0.02), eye_mat), Vector3(-0.045, 0.12, -0.14))
	_add(head, Util.box(Vector3(0.04, 0.02, 0.02), eye_mat), Vector3(0.045, 0.12, -0.14))
	_add(chest, Util.box(Vector3(0.36, 0.03, 0.27), _trim), Vector3(0, 0.33, 0))
	flap_l = _pivot(hips, Vector3(-0.1, 0.02, 0))
	flap_r = _pivot(hips, Vector3(0.1, 0.02, 0))
	for f: Node3D in [flap_l, flap_r]:
		_add(f, Util.box(Vector3(0.19, 0.5, 0.24), _cloth), Vector3(0, -0.24, 0.02))


## Hooded cultist: floor-length robe, pointed hood, red eyes, sash.
func _costume_cultist() -> void:
	flap_l = _pivot(hips, Vector3(-0.09, 0.02, 0))
	flap_r = _pivot(hips, Vector3(0.09, 0.02, 0))
	for f: Node3D in [flap_l, flap_r]:
		var s := signf(f.position.x)
		_add(f, _taper(0.13, 0.2, 0.95, _body, 10), Vector3(0.02 * s, -0.47, 0), Vector3(0, 0, 0.06 * s), Vector3(1, 1, 1.1))
	_add(head, Util.sphere(0.155, _body), Vector3(0, 0.13, 0.03), Vector3.ZERO, Vector3(1, 1.1, 1.12))
	_add(head, _taper(0.0, 0.11, 0.28, _body, 8), Vector3(0, 0.32, 0.07), Vector3(0.35, 0, 0))
	_add(head, Util.box(Vector3(0.19, 0.18, 0.05), Util.mat(Color(0.01, 0.005, 0.005), 0.0, 1.0, 1.0)), Vector3(0, 0.1, -0.11))
	if style != Style.STATUE:
		_add(head, Util.box(Vector3(0.035, 0.018, 0.02), eye_mat), Vector3(-0.042, 0.12, -0.14))
		_add(head, Util.box(Vector3(0.035, 0.018, 0.02), eye_mat), Vector3(0.042, 0.12, -0.14))
		_add(chest, Util.box(Vector3(0.06, 0.55, 0.02), _trim), Vector3(0.0, 0.08, -0.13), Vector3(0, 0, 0.5))
	_add(chest, Util.box(Vector3(0.44, 0.08, 0.3), _body), Vector3(0, 0.33, 0.01))


## Armoured Anchor: great helm with a burning slit, pauldrons, tabard and cape.
func _costume_knight() -> void:
	_add(head, Util.cylinder(0.14, 0.3, _body, 12), Vector3(0, 0.12, 0))
	_add(head, Util.sphere(0.14, _body), Vector3(0, 0.27, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	_add(head, Util.box(Vector3(0.2, 0.025, 0.03), eye_mat), Vector3(0, 0.15, -0.135))
	_add(head, Util.box(Vector3(0.02, 0.14, 0.03), eye_mat), Vector3(0, 0.07, -0.135))
	_add(chest, Util.box(Vector3(0.3, 0.42, 0.06), _cloth), Vector3(0, 0.0, -0.15))
	_add(chest, Util.box(Vector3(0.12, 0.12, 0.01), eye_mat), Vector3(0, 0.12, -0.185), Vector3(0, 0, PI * 0.25))
	cape = _pivot(chest, Vector3(0, 0.36, 0.14))
	_add(cape, Util.box(Vector3(0.56, 1.3, 0.04), _cloth), Vector3(0, -0.66, 0.02))
	flap_l = _pivot(hips, Vector3(-0.1, 0.0, 0))
	flap_r = _pivot(hips, Vector3(0.1, 0.0, 0))
	for f: Node3D in [flap_l, flap_r]:
		_add(f, Util.box(Vector3(0.2, 0.34, 0.26), _body), Vector3(0, -0.15, 0))


# --- Animation ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not animated or delta <= 0.0 or not is_visible_in_tree():
		return
	var p := global_position
	var v := Util.flat(p - _last).length() / delta
	_last = p
	_speed = lerpf(_speed, minf(v, 8.0), 1.0 - exp(-10.0 * delta))
	_t += delta
	var moving := clampf(_speed / 4.0, 0.0, 1.0)
	_phase += delta * (1.5 + _speed * 1.75)
	var s := sin(_phase)
	var swing := s * 0.6 * moving

	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	knee_l.rotation.x = -maxf(0.0, sin(_phase + 1.3)) * 1.0 * moving - 0.05
	knee_r.rotation.x = -maxf(0.0, sin(_phase + 1.3 + PI)) * 1.0 * moving - 0.05
	hips.position.y = _hips_y - absf(cos(_phase)) * 0.035 * moving
	hips.rotation.y = s * 0.08 * moving
	spine.rotation.x = -0.1 * moving
	spine.rotation.y = -s * 0.1 * moving
	chest.scale = Vector3.ONE * (1.0 + 0.012 * sin(_t * 2.1))
	if flap_l:
		flap_l.rotation.x = maxf(swing, -0.1) * 0.8
		flap_r.rotation.x = maxf(-swing, -0.1) * 0.8
	if cape:
		cape.rotation.x = 0.12 + 0.35 * moving + sin(_t * 1.7) * 0.03

	# Arms: walk swing, blended into aim or hands-up.
	var rest_l := Vector3(-swing * 0.8, 0, -0.08)
	var rest_r := Vector3(swing * 0.8, 0, 0.08)
	var elbow_rest := 0.25 + 0.2 * moving
	var aim_r := Vector3(PI * 0.5 + aim_pitch, 0.0, 0.05)
	var aim_l := Vector3(PI * 0.5 + aim_pitch - 0.15, 0.0, -0.55) if two_handed else rest_l
	var up_r := Vector3(PI * 0.92, 0, -0.35)
	var up_l := Vector3(PI * 0.92, 0, 0.35)
	var r := rest_r.lerp(aim_r, aim).lerp(up_r, hands_up)
	var l := rest_l.lerp(aim_l, aim if two_handed else 0.0).lerp(up_l, hands_up)
	arm_r.rotation = r
	arm_l.rotation = l
	elbow_r.rotation.x = lerpf(lerpf(elbow_rest, 0.05, aim), 0.7, hands_up)
	elbow_l.rotation.x = lerpf(lerpf(elbow_rest, 0.6 if two_handed else elbow_rest, aim), 0.7, hands_up)
	head.rotation.x = -aim_pitch * 0.6 * aim

	leg_l.rotation.x = lerpf(leg_l.rotation.x, 1.3, crouch)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, 1.0, crouch)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, -2.0, crouch)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, -1.6, crouch)
	hips.position.y -= 0.45 * crouch
	spine.rotation.x -= 0.5 * crouch

	if stagger > 0.0:
		spine.rotation.z = sin(_t * 15.0) * 0.18 * stagger
		head.rotation.z = sin(_t * 11.0 + 1.0) * 0.3 * stagger
	else:
		spine.rotation.z = 0.0
		head.rotation.z = 0.0


## Freeze a pose (statues).
func pose(arm_l_rot: Vector3, arm_r_rot: Vector3) -> void:
	animated = false
	arm_l.rotation = arm_l_rot
	arm_r.rotation = arm_r_rot
	elbow_l.rotation.x = 0.4
	elbow_r.rotation.x = 0.4


# --- Look helpers ------------------------------------------------------------------

## Rim the whole figure in a colour (aim/recall line highlight). Pass a transparent colour to clear.
func set_highlight(on: bool, color := Util.AMBER) -> void:
	var m: Material = Mats.rim(Color(color, 0.8)) if on else null
	for mi in _meshes:
		mi.material_overlay = m


## Swap every mesh to one translucent material (an echo), or back.
func set_ghost(on: bool, color := Color.WHITE) -> void:
	if on:
		var gm := Util.mat(color, 0.6, 0.35, 0.5)
		gm.cull_mode = BaseMaterial3D.CULL_BACK
		for mi in _meshes:
			if not _saved.has(mi):
				_saved[mi] = mi.material_override
			mi.material_override = gm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		for mi: MeshInstance3D in _saved:
			mi.material_override = _saved[mi]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_saved.clear()


## The local player only sees their own shadow, never their body.
func set_shadow_only(on: bool) -> void:
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func set_eyes(energy: float) -> void:
	eye_mat.albedo_color = accent * energy
