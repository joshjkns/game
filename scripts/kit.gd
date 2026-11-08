class_name Kit
## Shared look and helpers: toon materials with ink outlines, faceted low-poly meshes,
## one-shot effects (bursts, tracers, damage numbers) and sound.

const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_PICKUP := 8
## Visual layer only the viewmodel camera renders.
const VIEW_LAYER := 1 << 19

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
uniform vec4 color : source_color = vec4(0.05, 0.04, 0.08, 1.0);
uniform float width = 0.03;
// Push each vertex outward in view space so the ink line is `width` metres thick
// regardless of how the part is scaled.
void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 dir = normalize(mat3(MODELVIEW_MATRIX) * normalize(VERTEX + vec3(0.0001)));
	v.xyz += dir * width;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	ALBEDO = color.rgb;
}
"""

const FIELD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec4 color : source_color = vec4(0.5, 0.4, 1.0, 1.0);
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float bands = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 60.0);
	ALBEDO = color.rgb * (rim * 1.6 + 0.04 + bands * 0.05 * rim);
}
"""

static var _outline_shader: Shader
static var _field_shader: Shader
static var _outlines := {}
static var _sounds := {}
static var _font: Font
static var _box: BoxMesh


## Flat toon-shaded material. outline > 0 adds an inverted-hull ink line of that width.
static func toon(c: Color, outline := 0.0, ink := Color(0.05, 0.04, 0.08)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.85
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.7
	if outline > 0.0:
		m.next_pass = outline_mat(outline, ink)
	return m


static func outline_mat(width: float, ink := Color(0.05, 0.04, 0.08)) -> ShaderMaterial:
	var key := "%s|%s" % [width, ink.to_html()]
	if _outlines.has(key):
		return _outlines[key]
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", ink)
	_outlines[key] = m
	return m


## A unique outline material (for enemies whose outline colour changes with status).
static func own_outline(width: float, ink: Color) -> ShaderMaterial:
	var m := outline_mat(width, ink).duplicate() as ShaderMaterial
	return m


static func glow(c: Color, energy := 3.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func field_mat(c: Color) -> ShaderMaterial:
	if _field_shader == null:
		_field_shader = Shader.new()
		_field_shader.code = FIELD_SHADER
	var m := ShaderMaterial.new()
	m.shader = _field_shader
	m.set_shader_parameter("color", c)
	return m


static func box_mesh() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
	return _box


## A mesh instance from a primitive, positioned and coloured. Handy for building models.
static func part(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		scale := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cube(parent: Node3D, mat: Material, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return part(parent, box_mesh(), mat, pos, size, rot)


static func sphere(radius: float, segs := 8, rings := 5) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func cyl(top: float, bottom: float, height: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


## A faceted, flat-shaded rock: a coarse sphere with every vertex nudged by a seeded hash.
static func rock_mesh(size: Vector3, seed_value: int, roughness := 0.28) -> ArrayMesh:
	var base := sphere(0.5, 7, 4).get_mesh_arrays()
	var verts: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = base[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	var moved := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in idx:
		var v := verts[i]
		var key := v.snapped(Vector3.ONE * 0.001)
		if not moved.has(key):
			rng.seed = hash(key) ^ seed_value
			var j := 1.0 + rng.randf_range(-roughness, roughness)
			var top := 0.82 if v.y > 0.3 else 1.0
			moved[key] = Vector3(v.x * j, v.y * j * top, v.z * j) * size
		st.add_vertex(moved[key])
	st.generate_normals()
	return st.commit()


## A static collidable body with a mesh and matching convex shape.
static func solid(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	body.transform = xf
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape() if not mesh is BoxMesh else _box_shape(mesh)
	body.add_child(cs)
	return body


static func _box_shape(m: BoxMesh) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = m.size
	return b


static func block(parent: Node3D, mat: Material, pos: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var bm := BoxMesh.new()
	bm.size = size
	return solid(parent, bm, mat, Transform3D(Basis(Vector3.UP, yaw), pos))


## --- Effects ---------------------------------------------------------------

static func burst(parent: Node, pos: Vector3, color: Color, count := 10, speed := 5.0,
		size := 0.09, life := 0.45) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := glow(color, 3.0)
	for i in count:
		var s := MeshInstance3D.new()
		s.mesh = box_mesh()
		s.material_override = m
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(s)
		s.global_position = pos
		s.scale = Vector3.ONE * size * randf_range(0.6, 1.4)
		s.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.2), randf_range(-1, 1)).normalized()
		var tw := s.create_tween().set_parallel()
		tw.tween_property(s, "global_position", pos + dir * speed * life * randf_range(0.4, 1.0), life) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "scale", Vector3.ONE * 0.01, life).set_delay(life * 0.35)
		tw.chain().tween_callback(s.queue_free)


static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, life := 0.12, thick := 0.035) -> void:
	if parent == null or not parent.is_inside_tree() or from.distance_to(to) < 0.05:
		return
	var m := glow(color, 4.0, 0.95)
	var t := MeshInstance3D.new()
	t.mesh = box_mesh()
	t.material_override = m
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(t)
	var mid := (from + to) * 0.5
	t.global_position = mid
	t.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	t.scale = Vector3(thick, thick, from.distance_to(to))
	var tw := t.create_tween().set_parallel()
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.tween_property(t, "scale:x", 0.0, life)
	tw.tween_property(t, "scale:y", 0.0, life)
	tw.chain().tween_callback(t.queue_free)


static func flash(parent: Node, pos: Vector3, color: Color, energy := 4.0, light_range := 6.0, life := 0.12) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(l.queue_free)


## An expanding glowing ring on the ground (explosions, slams).
static func shockwave(parent: Node, pos: Vector3, color: Color, radius: float, life := 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 4
	var m := glow(color, 3.0, 0.9)
	var r := MeshInstance3D.new()
	r.mesh = tm
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(r)
	r.global_position = pos + Vector3.UP * 0.1
	r.scale = Vector3(0.2, 0.3, 0.2)
	var tw := r.create_tween().set_parallel()
	tw.tween_property(r, "scale", Vector3(radius, 0.6, radius), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(r.queue_free)
	var orb := MeshInstance3D.new()
	orb.mesh = sphere(1.0, 12, 6)
	var om := glow(color, 5.0, 0.7)
	orb.material_override = om
	parent.add_child(orb)
	orb.global_position = pos
	orb.scale = Vector3.ONE * radius * 0.3
	var tw2 := orb.create_tween().set_parallel()
	tw2.tween_property(orb, "scale", Vector3.ONE * radius * 0.8, life * 0.7)
	tw2.tween_property(om, "albedo_color:a", 0.0, life * 0.7)
	tw2.chain().tween_callback(orb.queue_free)


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _font


## A floating damage number. Crits are larger and gold; elements tint the number.
static func number(parent: Node, pos: Vector3, amount: float, color: Color, crit := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font = font()
	l.font_size = 96 if crit else 64
	l.pixel_size = 0.0021
	l.modulate = color
	l.outline_size = 16
	l.outline_modulate = Color(0.08, 0.04, 0.1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.render_priority = 10
	l.outline_render_priority = 9
	parent.add_child(l)
	var off := Vector3(randf_range(-0.3, 0.3), randf_range(0.15, 0.45), randf_range(-0.3, 0.3))
	l.global_position = pos + off
	l.scale = Vector3.ONE * (1.4 if crit else 1.0)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 0.9, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


## --- Sound ------------------------------------------------------------------

static func sfx(parent: Node, name: String, pos = null, volume := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if not _sounds.has(name):
		var path := "res://assets/audio/forward/%s.wav" % name
		_sounds[name] = load(path) if ResourceLoader.exists(path) else null
	if _sounds[name] == null:
		return
	var p: Node
	if pos is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 8.0
		p3.bus = "Master"
		p3.volume_db = volume
		p3.pitch_scale = pitch * randf_range(0.93, 1.07)
		p3.stream = _sounds[name]
		parent.add_child(p3)
		p3.global_position = pos
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "Master"
		p2.volume_db = volume
		p2.pitch_scale = pitch * randf_range(0.95, 1.05)
		p2.stream = _sounds[name]
		parent.add_child(p2)
		p2.play()
		p = p2
	p.connect("finished", p.queue_free)
