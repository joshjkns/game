class_name Heroes
extends Node3D
## The playable heroes: their kits (data) and their cute toon models. A Heroes node *is* a
## hero model; build one with Heroes.make(id). Models idle-bob and blink on their own.

## Each hero: signature gun, a quick Shift move, an E skill, and a Q ultimate that charges
## from damage dealt.
const DEFS := {
	"pip": {
		"name": "Pip", "weapon": "tick", "hp": 100.0, "shield": 50.0,
		"fur": Color("f0a35e"), "belly": Color("fff0d8"), "accent": Color("7fe0ff"),
		"shift": {"id": "blink", "name": "Blink", "short": "Short teleport", "cd": 5.0, "text": "Teleport a short way in the direction you're moving."},
		"e": {"id": "stasis", "name": "Stasis", "short": "Freeze one target", "cd": 7.0, "text": "Freeze what you aim at: an enemy (+30% damage taken), a shot, or a falling rock you can stand on."},
		"q": {"id": "stopclock", "name": "Stop the Clock", "short": "Freeze everything, 5s", "text": "Freeze every enemy, shot and falling rock nearby for 5 seconds."},
	},
	"mochi": {
		"name": "Mochi", "weapon": "chatter", "hp": 125.0, "shield": 40.0,
		"fur": Color("ffa3c7"), "belly": Color("ffd9e8"), "accent": Color("83d4c2"),
		"shift": {"id": "rewind", "name": "Rewind", "short": "Undo the last 3s", "cd": 9.0, "text": "Snap back to where you were 3 seconds ago, with the health you had then (if it was higher)."},
		"e": {"id": "field", "name": "Slow Field", "short": "Bubble of slow time", "cd": 12.0, "text": "Drop a bubble where enemies, shots and rocks run at 20% speed."},
		"q": {"id": "loop", "name": "Time Loop", "short": "Double shots that heal", "text": "For 8 seconds every shot fires twice and hits heal you."},
	},
	"nib": {
		"name": "Nib", "weapon": "bellow", "hp": 90.0, "shield": 70.0,
		"fur": Color("2e3b6e"), "belly": Color("f4f6ff"), "accent": Color("ffb43a"),
		"shift": {"id": "slide", "name": "Slide", "short": "Fast belly-slide", "cd": 2.5, "text": "Belly-slide forward at high speed."},
		"e": {"id": "haste", "name": "Haste", "short": "Reload and speed up", "cd": 10.0, "text": "Instantly reload. +50% move and fire rate for 4 seconds."},
		"q": {"id": "overclock", "name": "Overclock", "short": "Free ammo frenzy", "text": "For 8 seconds: double fire rate, +30% damage, no ammo used."},
	},
	"dusk": {
		"name": "Dusk", "weapon": "mortar", "hp": 100.0, "shield": 50.0,
		"fur": Color("b7a3ea"), "belly": Color("fff4e0"), "accent": Color("8cff6a"),
		"shift": {"id": "flutter", "name": "Flutter", "short": "Leap high and glide", "cd": 4.0, "text": "Leap high and glide down slowly."},
		"e": {"id": "decay", "name": "Decay", "short": "Orb that rots foes", "cd": 8.0, "text": "Throw an orb that ages everything it bursts on: corrodes and rots them for 4s."},
		"q": {"id": "collapse", "name": "Collapse", "short": "Boulders on every foe", "text": "Age the sky: a boulder crashes onto every enemy nearby."},
	},
}
const ORDER := ["pip", "mochi", "nib", "dusk"]
const INK := Color(0.08, 0.05, 0.1)

var id := "pip"
var sitting := false
var _eyes: Array[Node3D] = []
var _body: Node3D
var _t := 0.0
var _blink := 2.0
var _wings: Array[Node3D] = []


static func make(hero: String, sit := false) -> Heroes:
	var h := Heroes.new()
	h.id = hero
	h.sitting = sit
	return h


## A live portrait: the hero's head rendered in its own little world.
static func portrait(host: Node, hero: String, px := 256) -> Texture2D:
	var sv := SubViewport.new()
	sv.size = Vector2i(px, px)
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	host.add_child(sv)
	var m := make(hero)
	sv.add_child(m)
	m.rotation.y = 0.35
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 0.95, 2.4)
	sv.add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0))
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.85)
	env.ambient_light_energy = 0.9
	cam.environment = env
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.6, 0)
	sun.light_energy = 1.2
	sv.add_child(sun)
	return sv.get_texture()


func def() -> Dictionary:
	return DEFS[id]


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var d := def()
	var fur := Kit.toon(d.fur, 0.02, INK)
	var belly := Kit.toon(d.belly, 0.015, INK)
	match id:
		"pip": _pip(fur, belly)
		"mochi": _mochi(fur, belly)
		"nib": _nib(fur, belly)
		"dusk": _dusk(fur, belly)


## Big shiny eyes and rosy cheeks: shared by every hero.
func _face(y: float, spread: float, z: float, eye_r := 0.075) -> void:
	var black := Kit.toon(Color("1a1222"))
	var shine := Kit.glow(Color.WHITE, 1.5)
	for sx in [-1.0, 1.0]:
		var e := Node3D.new()
		e.position = Vector3(spread * sx, y, z)
		_body.add_child(e)
		Kit.part(e, Kit.sphere(eye_r, 10, 6), black, Vector3.ZERO, Vector3(1, 1.2, 0.6))
		Kit.part(e, Kit.sphere(eye_r * 0.35, 6, 4), shine, Vector3(eye_r * 0.3 * -sx, eye_r * 0.45, eye_r * 0.45))
		_eyes.append(e)
		Kit.part(_body, Kit.sphere(0.06, 8, 5), Kit.toon(Color("ff7fa0")), Vector3((spread + 0.07) * sx, y - 0.11, z - 0.03), Vector3(1, 0.5, 0.4))


func _pip(fur: Material, belly: Material) -> void:
	Kit.part(_body, Kit.sphere(0.42, 14, 8), fur, Vector3(0, 0.42, 0), Vector3(1, 0.92, 0.9))
	Kit.part(_body, Kit.sphere(0.3, 12, 8), belly, Vector3(0, 0.38, 0.17), Vector3(1, 1, 0.7))
	Kit.part(_body, Kit.sphere(0.4, 14, 8), fur, Vector3(0, 0.88, 0), Vector3(1.08, 0.92, 0.95))
	for sx in [-1.0, 1.0]:
		Kit.part(_body, Kit.sphere(0.17, 10, 6), belly, Vector3(0.24 * sx, 0.78, 0.2))
		Kit.part(_body, Kit.sphere(0.12, 8, 6), fur, Vector3(0.27 * sx, 1.2, -0.02), Vector3(1, 1, 0.5))
		Kit.part(_body, Kit.sphere(0.07, 8, 6), Kit.toon(Color("ff9fb5")), Vector3(0.27 * sx, 1.2, 0.03), Vector3(1, 1, 0.4))
		Kit.part(_body, Kit.sphere(0.09, 8, 6), fur, Vector3(0.36 * sx, 0.45, 0.22))
		Kit.part(_body, Kit.sphere(0.1, 8, 6), fur, Vector3(0.17 * sx, 0.05, 0.12), Vector3(1, 0.6, 1.3))
	_face(0.92, 0.15, 0.33)
	Kit.part(_body, Kit.sphere(0.035, 6, 4), Kit.toon(Color("ff7f9f")), Vector3(0, 0.84, 0.39))
	# A brass pocket watch hanging on the belly, and goggles pushed up on the head.
	var brass := Kit.toon(Color("e0aa45"), 0.012, INK)
	Kit.part(_body, Kit.cyl(0.1, 0.1, 0.04, 14), brass, Vector3(0, 0.36, 0.38), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(_body, Kit.cyl(0.08, 0.08, 0.01, 14), Kit.glow(DEFS.pip.accent, 1.8), Vector3(0, 0.36, 0.405), Vector3.ONE, Vector3(PI / 2, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.part(_body, Kit.cyl(0.08, 0.08, 0.06, 12), brass, Vector3(0.1 * sx, 1.15, 0.27), Vector3.ONE, Vector3(PI / 2 - 0.5, 0, 0))
		Kit.part(_body, Kit.cyl(0.06, 0.06, 0.01, 12), Kit.glow(DEFS.pip.accent, 1.0, 0.8), Vector3(0.1 * sx, 1.165, 0.3), Vector3.ONE, Vector3(PI / 2 - 0.5, 0, 0))


func _mochi(fur: Material, belly: Material) -> void:
	Kit.part(_body, Kit.sphere(0.38, 14, 8), fur, Vector3(0, 0.4, 0), Vector3(1, 1, 0.95))
	Kit.part(_body, Kit.sphere(0.28, 12, 8), belly, Vector3(0, 0.36, 0.15), Vector3(1, 1, 0.7))
	Kit.part(_body, Kit.sphere(0.42, 14, 8), fur, Vector3(0, 0.85, 0.02), Vector3(1.3, 0.85, 1.0))
	var gill := Kit.toon(Color("e24f8f"), 0.012, INK)
	for sx in [-1.0, 1.0]:
		for i in 3:
			var a := -0.7 + i * 0.6
			var g := Node3D.new()
			g.position = Vector3(0.48 * sx, 0.9, -0.05)
			g.rotation = Vector3(0, 0, a * sx * -1.0 + (0.0 if sx > 0 else PI))
			_body.add_child(g)
			Kit.part(g, Kit.cyl(0.03, 0.04, 0.3, 6), gill, Vector3(0.15, 0, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
			Kit.part(g, Kit.sphere(0.07, 8, 5), gill, Vector3(0.3, 0, 0))
		Kit.part(_body, Kit.sphere(0.09, 8, 6), fur, Vector3(0.33 * sx, 0.42, 0.2))
		Kit.part(_body, Kit.sphere(0.1, 8, 6), fur, Vector3(0.17 * sx, 0.05, 0.12), Vector3(1, 0.6, 1.3))
	_face(0.9, 0.22, 0.38, 0.065)
	Kit.part(_body, Kit.box_mesh(), Kit.toon(Color("6a1f45")), Vector3(0, 0.8, 0.41), Vector3(0.16, 0.02, 0.02))
	var tail := Kit.part(_body, Kit.cyl(0.02, 0.2, 0.6, 8), fur, Vector3(0, 0.25, -0.45), Vector3(0.5, 1, 1), Vector3(-1.2, 0, 0))
	tail.name = "Tail"
	# A floating time-bubble that follows her around.
	Kit.part(_body, Kit.sphere(0.13, 12, 8), Kit.field_mat(DEFS.mochi.accent), Vector3(0.5, 1.25, 0.1))


func _nib(fur: Material, belly: Material) -> void:
	Kit.part(_body, Kit.sphere(0.42, 14, 8), fur, Vector3(0, 0.5, 0), Vector3(0.95, 1.2, 0.9))
	Kit.part(_body, Kit.sphere(0.33, 12, 8), belly, Vector3(0, 0.5, 0.15), Vector3(0.9, 1.15, 0.75))
	Kit.part(_body, Kit.sphere(0.24, 12, 8), belly, Vector3(0, 0.92, 0.2), Vector3(1.2, 0.9, 0.7))
	var orange := Kit.toon(Color("ffa53a"), 0.012, INK)
	Kit.part(_body, Kit.cyl(0.0, 0.07, 0.16, 8), orange, Vector3(0, 0.86, 0.43), Vector3(1, 1, 0.7), Vector3(PI / 2, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.part(_body, Kit.sphere(0.1, 8, 6), orange, Vector3(0.15 * sx, 0.03, 0.15), Vector3(1, 0.35, 1.5))
		Kit.part(_body, Kit.sphere(0.12, 8, 6), fur, Vector3(0.4 * sx, 0.5, 0.0), Vector3(0.4, 1.2, 0.8), Vector3(0, 0, 0.3 * sx))
	_face(0.98, 0.13, 0.33, 0.065)
	# A long red scarf and courier goggles.
	var scarf := Kit.toon(Color("e8434f"), 0.015, INK)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.24
	tm.outer_radius = 0.34
	tm.rings = 16
	tm.ring_segments = 8
	Kit.part(_body, tm, scarf, Vector3(0, 0.75, 0.0), Vector3(1.05, 0.8, 1.0))
	Kit.part(_body, Kit.box_mesh(), scarf, Vector3(-0.2, 0.55, -0.3), Vector3(0.12, 0.4, 0.05), Vector3(0.3, 0, 0.2))
	var brass := Kit.toon(Color("e0aa45"), 0.012, INK)
	for sx in [-1.0, 1.0]:
		Kit.part(_body, Kit.cyl(0.08, 0.08, 0.05, 12), brass, Vector3(0.1 * sx, 1.18, 0.27), Vector3.ONE, Vector3(PI / 2 - 0.6, 0, 0))
		Kit.part(_body, Kit.cyl(0.06, 0.06, 0.01, 12), Kit.glow(DEFS.nib.accent, 1.0, 0.8), Vector3(0.1 * sx, 1.195, 0.29), Vector3.ONE, Vector3(PI / 2 - 0.6, 0, 0))


func _dusk(fur: Material, belly: Material) -> void:
	Kit.part(_body, Kit.sphere(0.36, 14, 8), fur, Vector3(0, 0.42, 0), Vector3(1, 1.05, 0.9))
	Kit.part(_body, Kit.sphere(0.4, 14, 8), fur, Vector3(0, 0.86, 0.02), Vector3(1.05, 0.95, 0.95))
	# A fluffy white collar of puffs.
	for i in 8:
		var a := TAU * i / 8.0
		Kit.part(_body, Kit.sphere(0.13, 8, 6), belly, Vector3(cos(a) * 0.3, 0.6, sin(a) * 0.26 + 0.04))
	var wing := Kit.toon(Color("e9c4ff"), 0.015, INK)
	var spot := Kit.glow(DEFS.dusk.accent, 1.5)
	for sx in [-1.0, 1.0]:
		for upper in [true, false]:
			var w := Node3D.new()
			w.position = Vector3(0.15 * sx, 0.6 if upper else 0.4, -0.3)
			_body.add_child(w)
			var s := Vector3(0.38, 0.32, 0.04) if upper else Vector3(0.28, 0.22, 0.04)
			Kit.part(w, Kit.sphere(1.0, 12, 6), wing, Vector3(0.32 * sx, 0.15 if upper else -0.05, 0), s, Vector3(0, 0, (0.5 if upper else -0.4) * sx))
			if upper:
				Kit.part(w, Kit.sphere(0.07, 8, 5), spot, Vector3(0.42 * sx, 0.22, 0.03), Vector3(1, 1, 0.3))
			_wings.append(w)
		# Feathery antennae.
		var ant := Node3D.new()
		ant.position = Vector3(0.12 * sx, 1.18, 0.1)
		ant.rotation = Vector3(-0.3, 0, -0.45 * sx)
		_body.add_child(ant)
		Kit.part(ant, Kit.cyl(0.012, 0.012, 0.4, 5), Kit.toon(Color("5a4878")), Vector3(0, 0.2, 0))
		for k in 4:
			Kit.part(ant, Kit.box_mesh(), Kit.toon(Color("5a4878")), Vector3(0, 0.12 + k * 0.08, 0), Vector3(0.14 - k * 0.025, 0.012, 0.012))
		Kit.part(_body, Kit.sphere(0.09, 8, 6), fur, Vector3(0.3 * sx, 0.42, 0.2))
		Kit.part(_body, Kit.sphere(0.09, 8, 6), fur, Vector3(0.15 * sx, 0.05, 0.12), Vector3(1, 0.6, 1.3))
	_face(0.88, 0.17, 0.32, 0.1)


func _process(delta: float) -> void:
	_t += delta
	_body.position.y = absf(sin(_t * 2.2)) * 0.03 if not sitting else sin(_t * 1.6) * 0.01
	_body.scale = Vector3(1.0 + sin(_t * 2.2) * 0.012, 1.0 - sin(_t * 2.2) * 0.012, 1.0)
	_blink -= delta
	var closed := _blink < 0.12
	if _blink <= 0.0:
		_blink = randf_range(2.0, 4.5)
	for e in _eyes:
		e.scale.y = 0.12 if closed else 1.0
	for i in _wings.size():
		_wings[i].rotation.y = sin(_t * 3.0 + i) * 0.25
