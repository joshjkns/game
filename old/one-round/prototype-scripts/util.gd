class_name Util
## Shared constants and small helpers for building greybox geometry in code.

const TILE := 1.5
const WALL_H := 1.6
const BULLET_Y := 1.0

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_GLASS := 8

const COLOR_A := Color(1.0, 0.55, 0.15)
const COLOR_B := Color(0.25, 0.6, 1.0)
const COLOR_ENEMY := Color(0.85, 0.15, 0.2)
const COLOR_BLOCKED := Color(1.0, 0.15, 0.15)


static func mat(color: Color, emission := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func unshaded(color: Color, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func box(size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	return mi


static func sphere(radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = material
	return mi


static func solid(size: Vector3, material: Material, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(box(size, material))
	return body


## Stretch a unit-length (along Z) mesh so it spans from -> to.
static func place_beam(node: Node3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01 or absf(d.normalized().y) > 0.99:
		node.visible = false
		return
	var b := Basis.looking_at(d / length, Vector3.UP)
	node.global_transform = Transform3D(b * Basis.from_scale(Vector3(1, 1, length)), (from + to) * 0.5)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
