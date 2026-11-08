class_name Stage
extends SubViewportContainer
## A small self-contained 3D scene shown inside the 2D UI: the title backdrop, character
## portraits, the opening cinematic. Owns its own World3D so it never touches the game world.

var viewport: SubViewport
var root: Node3D
var camera: Camera3D
var env: Environment


func _init(transparent := false) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = transparent
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	root = Node3D.new()
	viewport.add_child(root)
	env = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = not transparent
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	camera = Camera3D.new()
	camera.current = true
	root.add_child(camera)


func light(pos: Vector3, color: Color, energy: float, rng := 8.0, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	root.add_child(l)
	return l


func spot(pos: Vector3, target: Vector3, color: Color, energy: float, angle := 30.0, rng := 12.0) -> SpotLight3D:
	var s := SpotLight3D.new()
	root.add_child(s)
	s.transform = _looking(pos, target)
	s.light_color = color
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_range = rng
	s.shadow_enabled = true
	return s


func aim(from: Vector3, at: Vector3, fov := 40.0) -> void:
	camera.transform = _looking(from, at)
	camera.fov = fov


static func _looking(pos: Vector3, target: Vector3) -> Transform3D:
	var d := (target - pos).normalized()
	return Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD), pos)


## Slow drifting dust motes.
func dust(center: Vector3, extents: Vector3, color := Color(1, 0.9, 0.75, 0.5), amount := 120) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = center
	p.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3(0, -0.02, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.direction = Vector3(0.3, 0.2, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color * Color(2, 2, 2, 1)
	q.material = m
	p.draw_pass_1 = q
	root.add_child(p)
	return p


## One revolver cartridge standing on its base, about 4 cm tall. Origin at the base.
static func cartridge() -> Node3D:
	var n := Node3D.new()
	var brass := Util.mat(Color(0.78, 0.55, 0.22), 0.0, 1.0, 0.25, 1.0)
	var lead := Util.mat(Color(0.42, 0.4, 0.4), 0.0, 1.0, 0.45, 0.6)
	var rim := Util.cylinder(0.0108, 0.0015, brass, 24)
	rim.position.y = 0.00075
	n.add_child(rim)
	var case := Util.cylinder(0.0095, 0.03, brass, 24)
	case.position.y = 0.0165
	n.add_child(case)
	var tip := Util.cylinder(0.009, 0.006, lead, 24)
	tip.position.y = 0.034
	n.add_child(tip)
	var nose := Util.sphere(0.009, lead)
	nose.position.y = 0.037
	nose.scale = Vector3(1, 0.9, 1)
	n.add_child(nose)
	var primer := Util.cylinder(0.003, 0.0006, Util.mat(Color(0.85, 0.7, 0.45), 0.0, 1.0, 0.3, 1.0), 16)
	primer.position.y = -0.0002
	n.add_child(primer)
	return n


# --- Title backdrop -----------------------------------------------------------------

## The title screen: the revolver turning slowly in the dark, LEON's amber on one side and
## NOEL's cyan on the other, one round standing upright on the stone.
static func backdrop() -> Stage:
	var s := Stage.new(false)
	s.env.fog_enabled = true
	s.env.fog_light_color = Color(0.05, 0.055, 0.07)
	s.env.fog_density = 0.04
	s.aim(Vector3(-0.55, 0.42, 1.55), Vector3(-0.2, 0.18, 0), 34.0)

	var stone := Util.mat(Color(0.07, 0.07, 0.075), 0.0, 1.0, 0.55, 0.0)
	var floor_mi := Util.box(Vector3(12, 0.1, 12), stone)
	floor_mi.position.y = -0.05
	s.root.add_child(floor_mi)

	var pivot := Node3D.new()
	pivot.name = "Gun"
	pivot.position = Vector3(0.1, 0.32, -0.15)
	s.root.add_child(pivot)
	var gun := GunModel.new()
	gun.scale = Vector3.ONE * 1.6
	gun.set_loaded(true, Util.AMBER)
	pivot.add_child(gun)

	var shell := Stage.cartridge()
	shell.scale = Vector3.ONE * 2.2
	shell.position = Vector3(-0.38, 0.0, 0.18)
	s.root.add_child(shell)

	s.spot(Vector3(-0.2, 2.4, 0.6), Vector3(-0.1, 0.1, 0), Color(1.0, 0.92, 0.82), 3.0, 22.0, 6.0)
	s.light(Vector3(-1.4, 0.6, 0.4), Util.AMBER, 2.2, 3.0)
	s.light(Vector3(1.4, 0.7, -0.6), Util.CYAN, 2.4, 3.2)
	s.dust(Vector3(0, 0.6, 0), Vector3(1.6, 0.7, 1.0))

	s.set_meta("spin", pivot)
	return s


## Character portrait: the agent standing in a pool of their colour on a transparent background.
static func portrait(role: String) -> Stage:
	var s := Stage.new(true)
	var c := Util.role_color(role)
	var body := Humanoid.new(Humanoid.Style.LEON if role == Util.A else Humanoid.Style.NOEL, c)
	body.two_handed = false
	body.name = "Body"
	body.rotation.y = PI + (0.35 if role == Util.A else -0.35)
	s.root.add_child(body)
	var gun := GunModel.new()
	gun.name = "Gun"
	gun.position = Vector3(0, -0.02, 0.06)
	gun.scale = Vector3.ONE * 1.25
	gun.set_loaded(true, c)
	gun.visible = false
	s.set_meta("gun", gun)
	s.set_meta("body", body)
	body.ready.connect(func() -> void: body.weapon_socket.add_child(gun))
	s.aim(Vector3(0, 1.25, 3.3), Vector3(0, 1.0, 0), 34.0)
	s.env.ambient_light_energy = 0.5
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.5, -0.5 if role == Util.A else 0.5, 0)
	key.light_energy = 1.2
	key.light_color = Color(1, 0.95, 0.9)
	s.root.add_child(key)
	s.light(Vector3(0, 1.6, -1.2), c, 5.0, 4.0)
	s.light(Vector3(-1.2 if role == Util.A else 1.2, 0.4, 0.6), c, 1.5, 3.0)
	return s


func _process(delta: float) -> void:
	if has_meta("spin"):
		var p: Node3D = get_meta("spin")
		p.rotation.y += delta * 0.18
		p.position.y = 0.32 + sin(Time.get_ticks_msec() / 1400.0) * 0.012
