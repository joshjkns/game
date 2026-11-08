class_name Hazard
extends Node3D
## Dungeon traps on a fixed clock (host time), so every PC agrees on where they are without
## any network traffic. Each PC kills its own player; the host kills enemies.
##   SPIKES   floor spikes that punch up on a cycle
##   FIRE     a grate that vents a column of flame
##   BLADE_X / BLADE_Z  a pendulum blade swinging along that axis

enum { SPIKES, FIRE, BLADE_X, BLADE_Z }

const SPIKE_PERIOD := 3.2
const FIRE_PERIOD := 4.0
const BLADE_PERIOD := 2.6

var id := 0
var kind := SPIKES
var phase := 0.0
var room_height := 6.0

var _spikes: MultiMeshInstance3D
var _spike_mat: StandardMaterial3D
var _flames: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D
var _warn_mat: StandardMaterial3D
var _arm: Node3D
var _was_up := false


func _ready() -> void:
	match kind:
		SPIKES: _build_spikes()
		FIRE: _build_fire()
		_: _build_blade()


func _build_spikes() -> void:
	var plate := Util.box(Vector3(Util.TILE * 0.96, 0.04, Util.TILE * 0.96), Mats.iron())
	plate.position.y = 0.02
	add_child(plate)
	_warn_mat = Util.glow(Util.RED, 0.4)
	for i in 4:
		var e := Util.box(Vector3(Util.TILE * 0.96, 0.02, 0.04), _warn_mat)
		var a := i * PI * 0.5
		e.position = Vector3(sin(a), 0, cos(a)) * Util.TILE * 0.46 + Vector3(0, 0.045, 0)
		e.rotation.y = a
		add_child(e)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.05
	cm.height = 0.7
	cm.radial_segments = 6
	_spike_mat = Util.mat(Color(0.5, 0.48, 0.45), 0.0, 1.0, 0.3, 0.9)
	cm.material = _spike_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = 25
	for i in 25:
		var x := (i % 5 - 2) * 0.27
		var z := (i / 5 - 2) * 0.27
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0.35, z)))
	_spikes = MultiMeshInstance3D.new()
	_spikes.multimesh = mm
	_spikes.position.y = -0.72
	add_child(_spikes)


func _build_fire() -> void:
	var grate := Util.box(Vector3(Util.TILE * 0.8, 0.05, Util.TILE * 0.8), Mats.iron())
	grate.position.y = 0.025
	add_child(grate)
	for i in 5:
		var bar := Util.box(Vector3(0.04, 0.06, Util.TILE * 0.8), Util.mat(Color(0.05, 0.04, 0.04), 0.0, 1.0, 0.6, 0.8))
		bar.position = Vector3((i - 2) * 0.22, 0.05, 0)
		add_child(bar)
	_warn_mat = Util.glow(Color(1.0, 0.35, 0.05), 0.5)
	var glow := Util.box(Vector3(Util.TILE * 0.7, 0.01, Util.TILE * 0.7), _warn_mat)
	glow.position.y = 0.03
	add_child(glow)
	for i in 3:
		var f := Mats.flame(2.2, Color(1.0, 0.45, 0.16), 1.6)
		f.position = Vector3((i - 1) * 0.3, 0.0, (i % 2) * 0.2 - 0.1)
		f.visible = false
		add_child(f)
		_flames.append(f)
	_fire_light = Mats.fire_light(0.0, 9.0, false)
	_fire_light.remove_from_group("flicker")
	_fire_light.position.y = 1.4
	add_child(_fire_light)


func _build_blade() -> void:
	var pivot := Node3D.new()
	pivot.position.y = room_height - 0.1
	add_child(pivot)
	var mount := Util.box(Vector3(0.5, 0.2, 0.5), Mats.iron())
	pivot.add_child(mount)
	_arm = Node3D.new()
	pivot.add_child(_arm)
	var length := room_height - 1.0
	var rod := Util.cylinder(0.04, length, Mats.iron(), 6)
	rod.position.y = -length * 0.5
	_arm.add_child(rod)
	# A crescent from a squashed cylinder segment, edge down. Broad face in the swing plane.
	var blade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.75
	cm.bottom_radius = 0.75
	cm.height = 0.03
	cm.radial_segments = 24
	blade.mesh = cm
	blade.material_override = Util.mat(Color(0.65, 0.63, 0.6), 0.0, 1.0, 0.18, 1.0)
	blade.scale = Vector3(1.0, 1.0, 0.45)
	blade.position.y = -length - 0.05
	blade.rotation.x = PI * 0.5
	_arm.add_child(blade)
	var edge := Util.box(Vector3(1.3, 0.025, 0.035), Util.glow(Util.RED, 1.6))
	edge.position.y = -length - 0.36
	_arm.add_child(edge)
	if kind == BLADE_Z:
		pivot.rotation.y = PI * 0.5


func _cycle(period: float) -> float:
	return fmod(Net.now() + phase + 1000.0 * period, period)


## 0 = retracted, 1 = fully out. Spikes and fire only.
func extension() -> float:
	if kind == SPIKES:
		var t := _cycle(SPIKE_PERIOD)
		if t < 1.8:
			return 0.0
		if t < 2.3:
			return 0.18
		if t < 2.4:
			return 0.18 + (t - 2.3) * 8.2
		if t < 3.0:
			return 1.0
		return 1.0 - (t - 3.0) * 5.0
	if kind == FIRE:
		var t := _cycle(FIRE_PERIOD)
		if t < 2.6:
			return 0.0 if t < 2.0 else 0.15
		if t < 3.8:
			return 1.0
		return 0.0
	return 0.0


func blade_angle() -> float:
	return 0.95 * sin(TAU * _cycle(BLADE_PERIOD) / BLADE_PERIOD)


## Blade edge as a world-space segment.
func blade_segment() -> Array:
	var length := room_height - 1.0
	var a := blade_angle()
	var axis := Vector3.RIGHT if kind == BLADE_X else Vector3.BACK
	var pivot := global_position + Vector3(0, room_height - 0.1, 0)
	var radial := (axis * sin(a) + Vector3.DOWN * cos(a))
	var bob := pivot + radial * (length + 0.3)
	var tangent := axis * cos(a) + Vector3.UP * sin(a)
	return [bob - tangent * 0.65, bob + tangent * 0.65]


## Would a standing body (capsule axis at `base`, radius r) die here right now?
func lethal_for(base: Vector3, r: float) -> bool:
	match kind:
		SPIKES, FIRE:
			if extension() < 0.7:
				return false
			var d := base - global_position
			var half := Util.TILE * 0.5 - 0.1 + r * 0.5
			return absf(d.x) < half and absf(d.z) < half and d.y > -0.4 and d.y < 1.0
		_:
			var seg := blade_segment()
			return Util.segment_vs_capsule(seg[0], seg[1], base, 0.1, 1.8)[0] < r + 0.08


func _process(_delta: float) -> void:
	match kind:
		SPIKES:
			var e := extension()
			_spikes.position.y = -0.72 + e * 0.72
			_warn_mat.albedo_color = Util.RED * (0.4 + (2.5 if e > 0.0 else 0.0))
			var up := e > 0.7
			if up and not _was_up:
				Game.sfx("lodge", false, global_position, -10.0, 0.6)
			_was_up = up
		FIRE:
			var e := extension()
			for f in _flames:
				f.visible = e > 0.0
				f.scale = Vector3.ONE * (0.25 if e < 0.5 else 1.0)
			_fire_light.light_energy = 0.4 if e > 0.0 and e < 0.5 else (5.0 if e >= 0.5 else 0.0)
			_warn_mat.albedo_color = Color(1.0, 0.35, 0.05) * (0.5 + e * 3.0)
			var up := e >= 0.5
			if up and not _was_up:
				Game.sfx("enemy_shot", false, global_position, -6.0, 0.5)
			_was_up = up
		_:
			# Pivot is turned 90 degrees for BLADE_Z, so its local +X is world -Z.
			_arm.rotation.z = blade_angle() if kind == BLADE_X else -blade_angle()
