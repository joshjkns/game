class_name Util
## Shared constants and small helpers for building greybox geometry in code.

const TILE := 1.5
const WALL_H := 4.0
const EYE_H := 1.6
const CHEST_H := 1.25

# Physics layers.
const L_WORLD := 1    # floor, walls, crates, racks, lift door
const L_PLAYER := 2
const L_ENEMY := 4
const L_GLASS := 8    # intact glass: blocks bodies and bullets
const L_PROP := 16
const L_GUN := 32
const L_GHOST := 64   # broken glass frame: only NOEL's un-break ray hits it
const L_GATE := 128   # portcullis bars: block bodies, not bullets, sight or a thrown gun

# Colour language (see plan.md): amber = LEON/forward, cyan = NOEL/inverted, red = enemies.
const AMBER := Color(1.0, 0.6, 0.12)
const CYAN := Color(0.15, 0.85, 1.0)
const RED := Color(1.0, 0.1, 0.14)
const WHITE_HOT := Color(1.0, 0.96, 0.85)
const INK := Color(0.04, 0.04, 0.05)

const A := "A"
const B := "B"


static func role_color(role: String) -> Color:
	return AMBER if role == A else CYAN


static func role_name(role: String) -> String:
	return "LEON" if role == A else "NOEL"


static func other(role: String) -> String:
	return B if role == A else A


static func mat(color: Color, emission := 0.0, alpha := 1.0, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func glow(color: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color * energy, alpha) if energy > 1.0 else Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Unshaded, drawn through walls. Used for beacons and markers.
static func xray(color: Color, alpha := 0.8) -> StandardMaterial3D:
	var m := glow(color, 1.0, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 10
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
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = material
	return mi


static func cylinder(radius: float, height: float, material: Material, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = sides
	mi.mesh = cm
	mi.material_override = material
	return mi


static func capsule(radius: float, height: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
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
	if material:
		body.add_child(box(size, material))
	return body


## Stretch a unit-length (along local Z) mesh between two points.
static func place_beam(node: Node3D, from: Vector3, to: Vector3, thickness := 1.0) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.001:
		node.visible = false
		return
	node.global_position = (from + to) * 0.5
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	node.global_basis = Basis.looking_at(d / length, up) * Basis.from_scale(Vector3(thickness, thickness, length))


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Point on the segment [a, b] closest to p, as a 0..1 parameter.
static func segment_t(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return 0.0
	return clampf((p - a).dot(ab) / l2, 0.0, 1.0)


## Shortest distance between segment [a, b] and a vertical capsule axis at base, from y0 to y1.
## Returns [distance, t along a->b in metres].
static func segment_vs_capsule(a: Vector3, b: Vector3, base: Vector3, y0: float, y1: float) -> Array:
	var pts := Geometry3D.get_closest_points_between_segments(a, b, base + Vector3(0, y0, 0), base + Vector3(0, y1, 0))
	return [pts[0].distance_to(pts[1]), a.distance_to(pts[0])]


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of(yaw: float, pitch := 0.0) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
