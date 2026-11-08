class_name Arena
extends Node3D
## One room of a level, built at runtime in the act's biome: lighting, sky and fog, a faceted
## low-poly arena, cover, waves of enemies, falling structures, and the props that lead on.
## Combat rooms run on a clock: beat par for a bonus, run over and the Unwound speed up.
## Timed events (EVENTS) bend time mid-fight, for better or worse.

signal cleared
signal prop_used(prop: Prop)
signal boss_spawned(boss: Boss)

const RADIUS := 30.0
const START := Vector3(0, 0.2, 22)
const EXIT := Vector3(0, 0, -22)
const OVERTIME_CLOCK := 1.3
const GEAR_COLOR := Color("c9a050")

## Timed room events. `len` 0 means instant; `good` events get rarer on harder clocks.
const EVENTS := {
	"surge": {"name": "TIME SURGE", "text": "The Unwound run fast", "len": 7.0, "color": Color("ff9d59"), "good": false},
	"rift": {"name": "RIFT TEAR", "text": "Reinforcements from another hour", "len": 0.0, "color": Color("c08cff"), "good": false},
	"echoes": {"name": "ECHOES", "text": "The fallen rewind back", "len": 0.0, "color": Color("83d4c2"), "good": false},
	"gearfall": {"name": "GEARFALL", "text": "The clockwork above gives way", "len": 4.0, "color": Color("ffd24a"), "good": false},
	"stillness": {"name": "STILLNESS", "text": "Time drags for everyone but you", "len": 5.0, "color": Color("6fd8ff"), "good": true},
	"frozen": {"name": "FROZEN SECOND", "text": "Everything stops", "len": 2.5, "color": Color("a8eaff"), "good": true},
	"golden": {"name": "GOLDEN HOUR", "text": "Kills drop double coins", "len": 10.0, "color": Color("ffe08b"), "good": true},
}

const PALETTES := {
	"tundra": {"sky": Color("141a45"), "horizon": Color("6c63b0"), "ground": Color("dfe6f5"),
		"ground2": Color("b9c3e3"), "rock": Color("4e5a86"), "rock2": Color("6f7cab"), "fog": Color("5b5fa8"),
		"sun": Color("b9c8ff"), "sun_e": 1.1, "ambient": Color("7a80c8"), "accent": Color("7fe8ff"), "fog_d": 0.016},
	"dunes": {"sky": Color("d9773f"), "horizon": Color("f7cf98"), "ground": Color("e0a066"),
		"ground2": Color("c98352"), "rock": Color("a85f3a"), "rock2": Color("c57a4c"), "fog": Color("e9a86e"),
		"sun": Color("ffd9a0"), "sun_e": 1.5, "ambient": Color("d08c62"), "accent": Color("ffcf5a"), "fog_d": 0.02},
	"tomb": {"sky": Color("0b0816"), "horizon": Color("2c2042"), "ground": Color("4a3f5c"),
		"ground2": Color("3a3049"), "rock": Color("3b3350"), "rock2": Color("54476e"), "fog": Color("2a2040"),
		"sun": Color("9d8cff"), "sun_e": 0.45, "ambient": Color("4b3d6e"), "accent": Color("ff9a3a"), "fog_d": 0.024},
}

var kind := "combat"
## Set by Main when cutscenes play: the boss arrives sooner and rises in its intro instead.
var cinematic := false
var biome := "tundra"
var pal: Dictionary
var waves_left := 0
var wave_timer := 0.0
var spawning := 0
var fall_timer := 6.0
var done := false
var boss: Boss
## Room clock: seconds left to beat par, and whether we've run into overtime.
var par := 0.0
var par_t := 0.0
var overtime := false
## The running timed event ("" when none), its time left and full length.
var event := ""
var event_t := 0.0
var event_len := 0.0
var golden_t := 0.0
var _event_wait := 0.0
var _last_event := ""
var _gears_left := 0
var _gear_wait := 0.0
## Where and what recently died, for ECHOES to rewind.
var _fallen: Array = []


func build(room_kind: String, biome_override := "") -> void:
	kind = room_kind
	biome = biome_override if biome_override != "" else Run.biome()
	pal = PALETTES[biome]
	seed(hash("%d-%d-%d-%d" % [Run.act, Run.level, Run.room, Time.get_ticks_usec()]))
	_environment()
	_ground()
	_perimeter()
	_skyline()
	_particles()
	match kind:
		"combat":
			_cover(12)
			_platforms(2)
			waves_left = 2 + (1 if Run.depth() >= 3 else 0)
			wave_timer = 0.8
			par = (24.0 + 9.0 * waves_left) * Run.diff("par")
			par_t = par
			_event_wait = randf_range(9.0, 13.0) / Run.diff("events")
		"shop":
			_cover(5, 12.0)
			var v := _prop("vendor", Vector3(-6, 0, -6))
			v.rotation.y = 0.5
			_prop("portal", EXIT)
			if randf() < 0.5:
				_prop("chest", Vector3(7, 0, -4))
			done = true
		"boss":
			_cover(6, 18.0)
			wave_timer = 0.8 if cinematic else 2.0
		"title":
			_cover(12)
			_platforms(2)
			done = true


func _exit_tree() -> void:
	Run.enemy_clock = 1.0


func _physics_process(delta: float) -> void:
	if done:
		return
	if kind == "boss":
		if boss == null and wave_timer > 0.0:
			wave_timer -= delta
			if wave_timer <= 0.0:
				_spawn_boss()
		elif boss != null and is_instance_valid(boss) and not boss.dead:
			_tick_fallers(delta, 12.0)
		return
	_tick_clock(delta)
	_tick_events(delta)
	_tick_fallers(delta, 4.0 if overtime else 7.0)
	var alive := get_tree().get_nodes_in_group("enemies").size()
	wave_timer -= delta
	var rush := overtime or alive <= 2 or wave_timer <= -12.0
	if waves_left > 0 and spawning == 0 and rush and wave_timer <= 0.0:
		_spawn_wave()
	elif waves_left == 0 and spawning == 0 and alive == 0:
		_clear()


## --- Time ----------------------------------------------------------------------

func _tick_clock(delta: float) -> void:
	if overtime:
		return
	par_t -= delta
	if par_t <= 0.0:
		par_t = 0.0
		overtime = true
		_announce("OVERTIME", Color("ff5a5e"))
		Kit.sfx(self, "rewind", null, 0.0, 0.5)
		for f in get_tree().get_nodes_in_group("enemies"):
			Kit.burst(self, f.aim_point(), Color("ff5a5e"), 6, 3.0, 0.06, 0.3)


func _tick_events(delta: float) -> void:
	golden_t = maxf(0.0, golden_t - delta)
	if event != "":
		event_t -= delta
		if event_t <= 0.0:
			event = ""
	if _gears_left > 0:
		_gear_wait -= delta
		if _gear_wait <= 0.0:
			_gear_wait = 0.4
			_gears_left -= 1
			_drop_faller(5.0, randf_range(1.4, 2.2), GEAR_COLOR)
	var clock := OVERTIME_CLOCK if overtime else 1.0
	if event == "surge":
		clock *= 1.6
	elif event == "stillness":
		clock *= 0.4
	Run.enemy_clock = clock
	if waves_left == 0 and get_tree().get_nodes_in_group("enemies").size() <= 1:
		return
	_event_wait -= delta
	if _event_wait <= 0.0 and event == "":
		_event_wait = randf_range(13.0, 19.0) / Run.diff("events")
		trigger_event(_pick_event())


func _pick_event() -> String:
	var weights := {}
	for id in EVENTS:
		if id == _last_event or (id == "echoes" and _fallen.size() < 2):
			continue
		weights[id] = 1.0 / Run.diff("events") if EVENTS[id].good else 1.0
	var total := 0.0
	for id in weights:
		total += weights[id]
	var roll := randf() * total
	for id in weights:
		roll -= weights[id]
		if roll <= 0.0:
			return id
	return weights.keys().back()


func trigger_event(id: String) -> void:
	var def: Dictionary = EVENTS[id]
	_last_event = id
	event_len = def.len
	event_t = def.len
	if def.len > 0.0:
		event = id
	_announce(def.name, def.color)
	Kit.sfx(self, "rewind", null, -2.0, 1.6 if def.good else 0.7)
	var ps := get_tree().get_nodes_in_group("player")
	if not ps.is_empty():
		Kit.shockwave(self, ps[0].global_position, def.color, 14.0, 0.6)
	match id:
		"rift":
			_spawn_group(maxi(3, roundi((2 + Run.depth()) * Run.diff("count"))))
		"echoes":
			var n := mini(_fallen.size(), 3 + Run.depth() / 2)
			for i in n:
				var f: Dictionary = _fallen.pop_back()
				_telegraph_spawn(f.at, f.type, false, i * 0.1, true)
			_fallen.clear()
		"gearfall":
			_gears_left = 6 + Run.depth()
			_gear_wait = 0.0
		"frozen":
			for c in get_tree().get_nodes_in_group("chrono"):
				if c.can_freeze():
					c.freeze(def.len)
		"golden":
			golden_t = def.len


func _announce(text: String, col: Color, sub := "") -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_banner(text, col, sub)


## Unstable ground: structures keep crashing down near the player during a fight.
func _tick_fallers(delta: float, every: float) -> void:
	fall_timer -= delta
	if fall_timer > 0.0:
		return
	fall_timer = randf_range(every * 0.7, every * 1.2)
	_drop_faller(6.0, randf_range(1.8, 2.8), pal.rock2)


func _drop_faller(spread: float, size: float, color: Color) -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return
	var p: Vector3 = ps[0].global_position
	var at := _floor_at(p + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread)))
	var f := Faller.new()
	f.size = size
	f.color = color
	add_child(f)
	f.drop_at(at)


func _floor_at(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30, p.z), Vector3(p.x, -5, p.z), Kit.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else Vector3(p.x, 0, p.z)


func _spawn_wave() -> void:
	waves_left -= 1
	wave_timer = 0.8
	_spawn_group(roundi((5 + Run.depth() + Run.room) * Run.diff("count")))


func _spawn_group(count: int) -> void:
	var pool := ["scrapper", "scrapper", "scrapper", "slinger", "slinger", "bomber"]
	if Run.depth() >= 2:
		pool += ["hexer", "hexer", "warden"]
	if Run.depth() >= 4:
		pool += ["warden", "bomber", "hexer"]
	var ps := get_tree().get_nodes_in_group("player")
	var ppos: Vector3 = ps[0].global_position if not ps.is_empty() else START
	for i in count:
		var at := Vector3.ZERO
		for attempt in 12:
			var a := randf() * TAU
			var r := randf_range(6.0, RADIUS - 6.0)
			at = Vector3(cos(a) * r, 0, sin(a) * r)
			if at.distance_to(ppos) > 11.0:
				break
		var elite_chance := 0.06 + 0.025 * Run.depth() + Run.diff("elite")
		_telegraph_spawn(_floor_at(at), pool.pick_random(), randf() < elite_chance, i * 0.08)


## Enemies arrive through a swirling purple rift: a ring warns you where, then they step out.
func _telegraph_spawn(at: Vector3, t: String, elite: bool, delay: float, echo := false) -> void:
	spawning += 1
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 1.0
	tm.rings = 18
	tm.ring_segments = 3
	ring.mesh = tm
	var rift_color := Run.TIME_COLOR if echo else Color(0.75, 0.35, 1.0)
	ring.material_override = Kit.glow(rift_color, 3.0, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.1
	ring.scale = Vector3.ONE * 0.01
	var tw := ring.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(ring, "scale", Vector3(1.3, 1, 1.3), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		var e := Enemy.new()
		e.setup(t, elite, echo)
		if not echo:
			e.died.connect(_on_enemy_died)
		add_child(e)
		e.global_position = at + Vector3.UP * 0.2
		Kit.burst(self, at + Vector3.UP, rift_color, 10, 4.0, 0.08, 0.4)
		spawning -= 1)
	tw.tween_property(ring, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(ring.queue_free)


func _on_enemy_died(e: Enemy) -> void:
	_fallen.append({"type": e.type, "at": _floor_at(e.global_position)})
	if _fallen.size() > 8:
		_fallen.pop_front()


func _spawn_boss() -> void:
	boss = Boss.new()
	boss.rise_in = not cinematic
	add_child(boss)
	boss.global_position = Vector3(0, 0.3, -12)
	boss.rotation.y = 0.0
	boss.died.connect(func(_e): _clear())
	Kit.shockwave(self, boss.global_position, Color(1.0, 0.3, 0.2), 12.0, 0.8)
	Kit.sfx(self, "door", null, 4.0, 0.4)
	boss_spawned.emit(boss)


func _clear() -> void:
	if done:
		return
	done = true
	event = ""
	Run.enemy_clock = 1.0
	var last_fight := Run.room >= Run.COMBAT_ROOMS - 1
	if kind == "combat":
		var swift := ""
		if not overtime:
			var bonus := roundi((3 + 2 * Run.depth()) * (0.5 + par_t / par) * Run.diff("coins"))
			Run.add_coins(bonus)
			swift = "Swift clear  +%d coins" % bonus
		_announce("AREA CLEAR" if last_fight else "ROOM CLEAR", Color("8fe46c"), swift)
		Kit.sfx(self, "clear", null, -2.0)
	for f in get_tree().get_nodes_in_group("fallers"):
		if f.state != Faller.State.LANDED:
			f.queue_free()
	Kit.sfx(self, "rewind", null, -4.0, 0.8)
	if kind == "combat":
		_prop("relic", Vector3(0, 0, -8))
	if kind == "combat" and randf() < 0.45:
		_prop("chest", Vector3(randf_range(-8, 8), 0, randf_range(-6, 4)))
	if kind == "boss":
		var tier := clampi(Run.act, 1, 3)
		Prop.spawn_loot(self, Vector3(4, 0, -6), Run.make_weapon(Run.WEAPONS.keys().filter(func(k): return k != "tick").pick_random(), tier, ["fire", "shock", "rust"].pick_random()))
		_prop("relic", Vector3(-4, 0, -6))
	_prop("portal", EXIT)
	cleared.emit()


func _prop(k: String, at: Vector3) -> Prop:
	var p := Prop.new()
	p.kind = k
	add_child(p)
	p.global_position = _floor_at(at)
	p.used.connect(func(pp): prop_used.emit(pp))
	return p


## --- World building -------------------------------------------------------------

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = pal.sky
	sky_mat.sky_horizon_color = pal.horizon
	sky_mat.ground_bottom_color = pal.fog
	sky_mat.ground_horizon_color = pal.horizon
	sky_mat.sun_angle_max = 8.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal.ambient
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = pal.fog
	env.fog_density = pal.fog_d
	env.fog_sky_affect = 0.55
	env.fog_aerial_perspective = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal.sun
	sun.light_energy = pal.sun_e
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(randf_range(20, 160)), 0)
	add_child(sun)


func _ground() -> void:
	var g := Kit.block(self, Kit.toon(pal.ground), Vector3(0, -1, 0), Vector3(140, 2, 140))
	g.get_child(0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Low faceted mounds and colour patches break up the floor like painted terrain.
	for i in 18:
		var a := randf() * TAU
		var r := randf_range(4.0, RADIUS - 2.0)
		var s := randf_range(3.0, 7.0)
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.rock_mesh(Vector3(s, 0.35, s * randf_range(0.6, 1.2)), i, 0.35)
		mi.material_override = Kit.toon(pal.ground2 if i % 2 == 0 else pal.ground.lightened(0.06))
		mi.position = Vector3(cos(a) * r, -0.06, sin(a) * r)
		mi.rotation.y = randf() * TAU
		add_child(mi)


func _perimeter() -> void:
	var n := 26
	for i in n:
		var a := TAU * i / n + randf_range(-0.05, 0.05)
		var r := RADIUS + randf_range(1.0, 4.0)
		var s := Vector3(randf_range(7, 11), randf_range(8, 16), randf_range(6, 10))
		var xf := Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(cos(a) * r, s.y * 0.3, sin(a) * r))
		Kit.solid(self, Kit.rock_mesh(s, i * 7 + 1, 0.3), Kit.toon(pal.rock if i % 3 else pal.rock2, 0.06), xf)


## Far-off silhouettes that fade into the fog and give the sky depth.
func _skyline() -> void:
	for i in 14:
		var a := TAU * i / 14.0 + randf() * 0.3
		var r := randf_range(70, 110)
		var s := Vector3(randf_range(25, 45), randf_range(20, 50), randf_range(20, 40))
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.rock_mesh(s, 100 + i, 0.35)
		mi.material_override = Kit.toon(pal.rock.lerp(pal.fog, 0.4))
		mi.position = Vector3(cos(a) * r, s.y * 0.25, sin(a) * r)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	if biome == "tundra":
		var moon := Kit.part(self, Kit.sphere(9.0, 24, 12), Kit.glow(Color("eef2ff"), 2.2), Vector3(-80, 70, -150))
		moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in 3:
			var ribbon := Kit.part(self, Kit.box_mesh(), Kit.glow(Color(0.35, 1.0, 0.75) if i != 1 else Color(0.6, 0.45, 1.0), 1.5, 0.18),
				Vector3(-30 + i * 30, 55 + i * 6, -120), Vector3(90, 14, 0.5), Vector3(0.3, 0.2 * i, 0.15 * (i - 1)))
			ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif biome == "dunes":
		var sun := Kit.part(self, Kit.sphere(12.0, 24, 12), Kit.glow(Color("fff0c8"), 2.5), Vector3(60, 45, -160))
		sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Pyramids on the horizon say "Egypt" before anything else does.
		for i in 3:
			var h := 34.0 - i * 9.0
			var pyr := Kit.part(self, Kit.cyl(0.0, h * 1.1, h, 4), Kit.toon(pal.rock2.lerp(pal.fog, 0.35)),
				Vector3(-50 + i * 38, h * 0.5 - 2.0, -130 + i * 12), Vector3.ONE, Vector3(0, PI / 4 + i * 0.2, 0))
			pyr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cover(count: int, min_r := 7.0) -> void:
	for i in count:
		var a := randf() * TAU
		var r := randf_range(min_r, RADIUS - 5.0)
		var at := Vector3(cos(a) * r, 0, sin(a) * r)
		if at.distance_to(START) < 6.0 or at.distance_to(EXIT) < 6.0 or _title_stage(at, 6.0):
			continue
		match biome:
			"tundra":
				if i % 3 == 0:
					_crystal(at)
				else:
					_rock(at)
			"dunes":
				if i % 2 == 0:
					_hut(at)
				else:
					_rock(at)
			"tomb":
				if i % 2 == 0:
					_pillar(at)
				else:
					_rock(at)


## The title's hero-select spot stays clear of cover.
func _title_stage(at: Vector3, clearance: float) -> bool:
	return kind == "title" and at.distance_to(TitleScene.HERO_SPOT) < clearance


func _rock(at: Vector3) -> void:
	var s := Vector3(randf_range(2.5, 5), randf_range(1.6, 3.6), randf_range(2.5, 5))
	var xf := Transform3D(Basis(Vector3.UP, randf() * TAU), at + Vector3.UP * s.y * 0.3)
	Kit.solid(self, Kit.rock_mesh(s, randi(), 0.3), Kit.toon(pal.rock2, 0.04), xf)


func _crystal(at: Vector3) -> void:
	_rock(at)
	var c: Color = [Color(0.6, 0.4, 1.0), Color(0.4, 0.9, 1.0)].pick_random()
	for i in randi_range(2, 4):
		var h := randf_range(2.0, 5.0)
		var mi := Kit.part(self, Kit.cyl(0.0, 0.5, h, 5), Kit.glow(c, 1.6, 0.85),
			at + Vector3(randf_range(-1, 1), h * 0.5 + 0.5, randf_range(-1, 1)), Vector3.ONE,
			Vector3(randf_range(-0.4, 0.4), randf(), randf_range(-0.4, 0.4)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.5
	l.omni_range = 7.0
	l.position = at + Vector3.UP * 2.5
	add_child(l)


## A sun-baked adobe hut with dark windows and a flat roof.
func _hut(at: Vector3) -> void:
	var w := randf_range(4, 6)
	var h := randf_range(3, 5)
	var yaw := randf() * TAU
	var wall := Kit.toon(pal.rock2.lightened(0.15), 0.05)
	var body := Kit.block(self, wall, at + Vector3.UP * h * 0.5, Vector3(w, h, w * 0.8), yaw)
	Kit.cube(body, Kit.toon(pal.rock.darkened(0.2)), Vector3(0, h * 0.5 + 0.15, 0), Vector3(w + 0.4, 0.3, w * 0.8 + 0.4))
	Kit.cube(body, Kit.toon(Color("2a1a14")), Vector3(w * 0.2, 0.3, w * 0.4 + 0.01), Vector3(0.9, 1.0, 0.05))
	Kit.cube(body, Kit.toon(Color("2a1a14")), Vector3(-w * 0.25, -0.6, w * 0.4 + 0.01), Vector3(1.0, 1.8, 0.05))


func _pillar(at: Vector3) -> void:
	var h := randf_range(5, 8)
	var stone := Kit.toon(pal.rock2, 0.05)
	var p := Kit.block(self, stone, at + Vector3.UP * h * 0.5, Vector3(1.6, h, 1.6), randf() * TAU)
	Kit.cube(p, Kit.toon(pal.rock.darkened(0.1)), Vector3(0, -h * 0.5 + 0.3, 0), Vector3(2.2, 0.6, 2.2))
	Kit.cube(p, Kit.toon(pal.rock.darkened(0.1)), Vector3(0, h * 0.5 - 0.2, 0), Vector3(2.0, 0.4, 2.0))
	# A torch on each pillar: the warm light pools are what make the tomb read.
	var flame := Kit.part(p, Kit.cyl(0.0, 0.18, 0.5, 6), Kit.glow(pal.accent, 4.0), Vector3(0, 0.6, 0.95))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.cube(p, Kit.toon(Color("3a2a1a")), Vector3(0, 0.25, 0.9), Vector3(0.15, 0.4, 0.15))
	var l := OmniLight3D.new()
	l.light_color = pal.accent
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.position = Vector3(0, 0.8, 1.4)
	p.add_child(l)


func _platforms(count: int) -> void:
	for i in count:
		var a := randf() * TAU
		var r := randf_range(12, 20)
		var at := Vector3(cos(a) * r, 0, sin(a) * r)
		if at.distance_to(START) < 8.0 or at.distance_to(EXIT) < 8.0 or _title_stage(at, 8.0):
			continue
		var h := randf_range(2.0, 3.2)
		var yaw := randf() * TAU
		var top := Kit.toon(pal.ground.darkened(0.04), 0.0)
		var side := Kit.toon(pal.rock2, 0.05)
		var plat := Kit.block(self, side, at + Vector3.UP * h * 0.5, Vector3(7, h, 7), yaw)
		Kit.cube(plat, top, Vector3(0, h * 0.5 + 0.02, 0), Vector3(7.1, 0.06, 7.1))
		# A ramp up one side.
		var b := Basis(Vector3.UP, yaw)
		var ramp_len := h / sin(0.42)
		var ramp_pos := at + b * Vector3(0, h * 0.5 - 0.1, 3.5 + cos(0.42) * ramp_len * 0.5)
		var rb := BoxMesh.new()
		rb.size = Vector3(3, 0.4, ramp_len)
		Kit.solid(self, rb, side, Transform3D(b * Basis(Vector3.RIGHT, 0.42), ramp_pos))


func _particles() -> void:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(35, 10, 35)
	m.gravity = Vector3(0.6, -1.2, 0.2) if biome == "tundra" else Vector3(1.5, -0.1, 0.4)
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.6
	m.direction = Vector3(1, 0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.2
	p.process_material = m
	p.amount = 500
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_aabb = AABB(Vector3(-40, -12, -40), Vector3(80, 30, 80))
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var col: Color = {"tundra": Color(1, 1, 1), "dunes": Color(1.0, 0.85, 0.6), "tomb": Color(1.0, 0.6, 0.25)}[biome]
	var qm := Kit.glow(col, 1.5 if biome == "tomb" else 0.6, 0.8)
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	p.draw_pass_1 = q
	p.position = Vector3(0, 9, 0)
	add_child(p)
