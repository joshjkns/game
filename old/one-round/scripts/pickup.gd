class_name Pickup
extends Node3D
## Things that spill on the floor. The host spawns them and decides who collects them.
##   COIN       loot (+1)
##   GEM        loot (+5), from relics and Anchors
##   HOURGLASS  slows every enemy and enemy round to a crawl for a few seconds
##   ECHO       gives NOEL's un-die back for this room

enum { COIN, GEM, HOURGLASS, ECHO }

const RADIUS := 1.1
const NAMES := ["COIN", "GEM", "HOURGLASS", "ECHO"]

var id := 0
var kind := COIN
var taken := false
var _model: Node3D
var _t := 0.0


static func color_of(k: int) -> Color:
	match k:
		GEM: return Color(0.3, 1.0, 0.5)
		HOURGLASS: return Color(1.0, 0.8, 0.35)
		ECHO: return Color(0.8, 0.95, 1.0)
	return Color(1.0, 0.75, 0.3)


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	_t = randf() * 5.0
	match kind:
		COIN:
			var c := Util.cylinder(0.11, 0.025, Mats.gold(), 14)
			c.rotation.x = PI * 0.5
			_model.add_child(c)
			_model.position.y = 0.25
		GEM:
			var g := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radial_segments = 6
			sm.rings = 2
			sm.radius = 0.14
			sm.height = 0.36
			g.mesh = sm
			g.material_override = Util.mat(color_of(GEM), 2.0, 1.0, 0.05, 0.3)
			_model.add_child(g)
			_model.position.y = 0.45
			_light(color_of(GEM), 1.0)
		HOURGLASS:
			for s in [-1.0, 1.0]:
				var cap := Util.cylinder(0.13, 0.03, Mats.gold(), 12)
				cap.position.y = 0.17 * s
				_model.add_child(cap)
				var bulb := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.1 if s > 0 else 0.01
				cm.bottom_radius = 0.01 if s > 0 else 0.1
				cm.height = 0.16
				bulb.mesh = cm
				bulb.material_override = Util.mat(Color(1.0, 0.85, 0.5), 2.5, 0.8, 0.1)
				bulb.position.y = 0.085 * s
				_model.add_child(bulb)
			for i in 3:
				var post := Util.cylinder(0.012, 0.34, Mats.gold(), 4)
				var a := TAU * i / 3.0
				post.position = Vector3(cos(a) * 0.11, 0, sin(a) * 0.11)
				_model.add_child(post)
			_model.position.y = 0.55
			_light(color_of(HOURGLASS), 1.6)
		ECHO:
			var core := Util.sphere(0.12, Util.glow(Util.CYAN, 4.0))
			_model.add_child(core)
			var halo := Util.sphere(0.24, Util.glow(Color(0.8, 0.95, 1.0), 1.0, 0.25))
			_model.add_child(halo)
			_model.position.y = 0.7
			_light(Util.CYAN, 1.6)
	if kind != COIN:
		var ring := Util.cylinder(0.35, 0.01, Util.glow(color_of(kind), 1.5, 0.35), 20)
		ring.position.y = 0.02
		add_child(ring)


func _light(c: Color, e: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = e
	l.omni_range = 2.5
	l.position.y = 0.6
	add_child(l)


## Arc from where it spilled to where it rests.
func spill_from(from: Vector3) -> void:
	var to := global_position
	global_position = from
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 1.0, 0), 0.0, 1.0, 0.5)


func _process(delta: float) -> void:
	_t += delta
	_model.rotation.y += delta * (5.0 if kind == COIN else 1.8)
	if kind != COIN:
		_model.position.y += sin(_t * 2.5) * delta * 0.08


func collect(role: String) -> void:
	taken = true
	var c := color_of(kind)
	Fx.burst(get_parent(), global_position + Vector3(0, 0.4, 0), c, 8 if kind == COIN else 16, 2.0, 0.04, 0.3, role == Util.B)
	Game.sfx("catch", role == Util.B, global_position, -8.0 if kind == COIN else -2.0, 1.8 if kind == COIN else 1.2)
	queue_free()
