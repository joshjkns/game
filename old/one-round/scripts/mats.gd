class_name Mats
## Cached dungeon materials (procedural, no textures) and small builders for the light
## sources every room shares: torches, braziers, candles and flames.

const STONE := preload("res://shaders/stone.gdshader")
const FLAME := preload("res://shaders/flame.gdshader")
const WATER := preload("res://shaders/water.gdshader")
const SHELL := preload("res://shaders/shell.gdshader")
const RIM := preload("res://shaders/rim.gdshader")
const PORTAL := preload("res://shaders/portal.gdshader")

const FIRE := Color(1.0, 0.6, 0.34)
const CANDLE := Color(1.0, 0.68, 0.36)
const MOON := Color(0.55, 0.68, 1.0)

static var _cache := {}


static func _stone(key: String, params: Dictionary) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = STONE
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


static func wall() -> ShaderMaterial:
	return _stone("wall", {"color_a": Color(0.4, 0.38, 0.36), "color_b": Color(0.22, 0.21, 0.21),
		"mortar_color": Color(0.06, 0.06, 0.06), "pattern": 0, "cell": Vector2(0.46, 0.22), "gap": 0.016,
		"grime": 0.6, "moss": 0.6, "bump": 0.8})


static func floor_stone() -> ShaderMaterial:
	return _stone("floor", {"color_a": Color(0.34, 0.33, 0.32), "color_b": Color(0.17, 0.17, 0.18),
		"pattern": 1, "cell": Vector2(0.72, 0.58), "gap": 0.024, "grime": 0.5, "wet": 0.9,
		"roughness_base": 0.8, "bump": 1.0})


static func ceiling() -> ShaderMaterial:
	return _stone("ceiling", {"color_a": Color(0.2, 0.19, 0.19), "color_b": Color(0.1, 0.1, 0.1),
		"pattern": 0, "cell": Vector2(0.9, 0.45), "grime": 0.2, "bump": 1.0})


static func trim() -> ShaderMaterial:
	return _stone("trim", {"color_a": Color(0.46, 0.44, 0.41), "color_b": Color(0.3, 0.29, 0.28),
		"pattern": 3, "grime": 0.4, "roughness_base": 0.7, "bump": 0.8})


static func marble() -> ShaderMaterial:
	return _stone("marble", {"color_a": Color(0.78, 0.76, 0.72), "color_b": Color(0.55, 0.53, 0.5),
		"pattern": 3, "grime": 0.35, "roughness_base": 0.35, "bump": 0.4})


static func pit_wall() -> ShaderMaterial:
	return _stone("pit", {"color_a": Color(0.2, 0.18, 0.16), "color_b": Color(0.08, 0.07, 0.07),
		"pattern": 0, "cell": Vector2(0.7, 0.35), "grime": 0.0, "moss": 0.3})


static func wood() -> ShaderMaterial:
	return _stone("wood", {"color_a": Color(0.36, 0.22, 0.12), "color_b": Color(0.2, 0.12, 0.07),
		"mortar_color": Color(0.05, 0.03, 0.02), "pattern": 2, "cell": Vector2(2.2, 0.21), "gap": 0.012,
		"grime": 0.25, "roughness_base": 0.75, "bump": 0.9})


static func dark_wood() -> ShaderMaterial:
	return _stone("dark_wood", {"color_a": Color(0.2, 0.12, 0.07), "color_b": Color(0.1, 0.06, 0.04),
		"mortar_color": Color(0.03, 0.02, 0.01), "pattern": 2, "cell": Vector2(3.0, 0.28), "gap": 0.01,
		"grime": 0.1, "roughness_base": 0.7, "bump": 0.7})


static func iron() -> StandardMaterial3D:
	return _std("iron", Color(0.13, 0.12, 0.12), 0.45, 0.85)


static func gold() -> StandardMaterial3D:
	return _std("gold", Color(0.95, 0.68, 0.3), 0.28, 1.0)


static func clay() -> StandardMaterial3D:
	return _std("clay", Color(0.42, 0.22, 0.13), 0.8, 0.0)


static func bone() -> StandardMaterial3D:
	return _std("bone", Color(0.72, 0.66, 0.55), 0.7, 0.0)


static func cloth(color: Color) -> StandardMaterial3D:
	var key := "cloth" + color.to_html()
	if not _cache.has(key):
		var m := Util.mat(color, 0.0, 1.0, 0.95)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


static func wax() -> StandardMaterial3D:
	if not _cache.has("wax"):
		var m := Util.mat(Color(0.9, 0.84, 0.7), 0.0, 1.0, 0.6)
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.6
		_cache["wax"] = m
	return _cache["wax"]


static func _std(key: String, color: Color, rough: float, metal: float) -> StandardMaterial3D:
	if not _cache.has(key):
		_cache[key] = Util.mat(color, 0.0, 1.0, rough, metal)
	return _cache[key]


static func flame_mat(tint := FIRE, intensity := 3.0) -> ShaderMaterial:
	var key := "flame" + tint.to_html() + str(intensity)
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAME
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("intensity", intensity)
		_cache[key] = m
	return _cache[key]


static func water(glow: Color) -> ShaderMaterial:
	var key := "water" + glow.to_html()
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = WATER
		m.set_shader_parameter("glow", glow)
		_cache[key] = m
	return _cache[key]


static func rim(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RIM
	m.set_shader_parameter("tint", color)
	return m


static func shell(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHELL
	m.set_shader_parameter("tint", color)
	return m


# --- Flames and light sources -------------------------------------------------

## A billboarded flame quad (unit height `size`). Returns the mesh so callers can set `fuel`.
static func flame(size: float, tint := FIRE, intensity := 3.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size * 0.6, size)
	q.center_offset = Vector3(0, size * 0.5, 0)
	mi.mesh = q
	mi.material_override = flame_mat(tint, intensity)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_instance_shader_parameter("seed", randf() * 10.0)
	return mi


## A flickering warm light. `key` lights keep their shadows on the low preset too.
static func fire_light(energy: float, light_range: float, shadows := true, key := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = FIRE
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	l.shadow_bias = 0.06
	l.shadow_normal_bias = 1.5
	l.light_size = 0.06
	l.light_volumetric_fog_energy = 1.4
	l.set_meta("base_energy", energy)
	l.set_meta("shadows", shadows)
	l.add_to_group("flicker")
	l.add_to_group("key_light" if key else "fill_light")
	return l


## Wall torch: iron bracket, wrapped handle, flame and a shadowed flickering light.
static func torch(shadows := true) -> Node3D:
	var root := Node3D.new()
	var plate := Util.box(Vector3(0.16, 0.34, 0.05), iron())
	plate.position = Vector3(0, -0.1, 0.025)
	root.add_child(plate)
	var arm := Util.box(Vector3(0.05, 0.05, 0.3), iron())
	arm.position = Vector3(0, -0.2, -0.14)
	arm.rotation.x = 0.5
	root.add_child(arm)
	var stick := Util.cylinder(0.035, 0.5, dark_wood(), 8)
	stick.position = Vector3(0, -0.02, -0.3)
	stick.rotation.x = -0.35
	root.add_child(stick)
	var cup := Util.cylinder(0.07, 0.12, iron(), 8)
	(cup.mesh as CylinderMesh).bottom_radius = 0.04
	cup.position = Vector3(0, 0.2, -0.38)
	root.add_child(cup)
	var f := flame(0.46, FIRE, 2.2)
	f.position = Vector3(0, 0.24, -0.38)
	root.add_child(f)
	var l := fire_light(2.4, 10.0, shadows)
	l.position = Vector3(0, 0.45, -0.6)
	root.add_child(l)
	return root


## A cluster of candles on the floor or a table, with one small unshadowed light.
static func candles(rng: RandomNumberGenerator, count := 4, with_light := true) -> Node3D:
	var root := Node3D.new()
	for i in count:
		var h := rng.randf_range(0.08, 0.3)
		var r := rng.randf_range(0.022, 0.04)
		var c := Util.cylinder(r, h, wax(), 8)
		var off := Vector3(rng.randf_range(-0.16, 0.16), h * 0.5, rng.randf_range(-0.16, 0.16))
		c.position = off
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(c)
		var f := flame(0.09, CANDLE, 2.5)
		f.position = off + Vector3(0, h * 0.5 + 0.005, 0)
		root.add_child(f)
	if with_light:
		var l := fire_light(0.9, 4.0, false)
		l.light_color = CANDLE
		l.omni_attenuation = 1.8
		l.position = Vector3(0, 0.45, 0)
		root.add_child(l)
	return root


## A standing iron brazier: bowl on a tripod, coals and a big flame. Returns [root, flame, light].
static func brazier(shadows := true) -> Array:
	var root := Node3D.new()
	for i in 3:
		var a := TAU * i / 3.0
		var leg := Util.box(Vector3(0.05, 1.0, 0.05), iron())
		leg.position = Vector3(cos(a) * 0.2, 0.48, sin(a) * 0.2)
		leg.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
		root.add_child(leg)
	var bowl := Util.cylinder(0.36, 0.22, iron(), 12)
	(bowl.mesh as CylinderMesh).bottom_radius = 0.18
	bowl.position.y = 1.0
	root.add_child(bowl)
	var rim_ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.33
	tm.outer_radius = 0.39
	rim_ring.mesh = tm
	rim_ring.material_override = iron()
	rim_ring.position.y = 1.11
	root.add_child(rim_ring)
	var coals := Util.cylinder(0.31, 0.04, Util.mat(Color(1.0, 0.3, 0.05), 2.5, 1.0, 0.9), 12)
	coals.position.y = 1.1
	root.add_child(coals)
	var f := flame(1.0, FIRE, 2.4)
	f.position.y = 1.08
	root.add_child(f)
	var l := fire_light(3.2, 12.0, shadows, true)
	l.position.y = 1.7
	root.add_child(l)
	var embers := Mats.embers()
	embers.position.y = 1.2
	root.add_child(embers)
	return [root, f, l, coals]


## Sparks drifting up from a fire.
static func embers(amount := 24) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3, 4, 3))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, 0.6, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 0.7, 0.3, 1))
	fade.set_color(1, Color(1, 0.2, 0.0, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(3.0, 1.6, 0.6)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
