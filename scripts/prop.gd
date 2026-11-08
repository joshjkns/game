class_name Prop
extends Node3D
## Things you press E on: the exit portal, chests, weapon loot, the hourglass relic (time-power
## pick) and the clockmaker's stall (shop). Main listens to `used` for the ones that open UI.

signal used(prop: Prop)

var kind := "chest"
var reach := 3.0
var active := true
var weapon := {}
var _spin: Node3D
var _t := 0.0


func _ready() -> void:
	add_to_group("interact")
	_spin = Node3D.new()
	add_child(_spin)
	match kind:
		"portal": _build_portal()
		"chest": _build_chest()
		"loot": _build_loot()
		"relic": _build_relic()
		"vendor": _build_vendor()


func prompt() -> String:
	if not active:
		return ""
	match kind:
		"portal": return "[F]  Step through"
		"chest": return "[F]  Open chest"
		"loot": return "[F]  Take %s (%s)" % [Run.weapon_name(weapon), Run.TIER_NAMES[weapon.tier]]
		"relic": return "[F]  Pick a power"
		"vendor": return "[F]  Shop"
	return ""


func interact(p: Player) -> void:
	if not active:
		return
	match kind:
		"chest":
			active = false
			Kit.sfx(self, "door", global_position, 0.0, 1.2)
			var lid: Node3D = _spin.get_child(1)
			create_tween().tween_property(lid, "rotation:x", -1.9, 0.3).set_trans(Tween.TRANS_BACK)
			Pickup.drop_coins(get_parent(), global_position + Vector3.UP, 8 + Run.depth() * 3)
			if randf() < 0.45:
				var o := Run.roll_offer()
				if o.kind == "weapon":
					spawn_loot(get_parent(), global_position + global_basis.z * 1.6, o.weapon)
			return
		"loot":
			var old: Dictionary = Run.current_weapon() if Run.weapons.size() >= 2 else {}
			Run.give_weapon(weapon.duplicate())
			Kit.sfx(p, "catch")
			if not old.is_empty():
				old.erase("ammo")
				spawn_loot(get_parent(), global_position, old)
			queue_free()
			return
		"relic":
			active = false
			Kit.sfx(p, "rewind")
			var tw := create_tween()
			tw.tween_property(_spin, "scale", Vector3.ONE * 0.01, 0.4)
	used.emit(self)


static func spawn_loot(world: Node, at: Vector3, w: Dictionary) -> Prop:
	var p := Prop.new()
	p.kind = "loot"
	p.weapon = w
	world.add_child(p)
	p.global_position = at
	return p


func _process(delta: float) -> void:
	_t += delta
	match kind:
		"portal":
			_spin.rotation.z += delta * (1.5 if active else 0.2)
		"loot", "relic":
			_spin.rotation.y += delta * 1.5
			_spin.position.y = 1.0 + sin(_t * 2.0) * 0.12


func _build_portal() -> void:
	reach = 3.5
	var stone := Kit.toon(Color("4a4560"), 0.05)
	for sx in [-1.0, 1.0]:
		Kit.cube(self, stone, Vector3(1.9 * sx, 1.9, 0), Vector3(0.6, 3.8, 0.8))
	Kit.cube(self, stone, Vector3(0, 4.0, 0), Vector3(4.6, 0.7, 0.9))
	Kit.cube(self, Kit.toon(Color("d9a441"), 0.03), Vector3(0, 4.0, -0.47), Vector3(0.8, 0.8, 0.1), Vector3(0, 0, PI / 4))
	_spin.position.y = 2.0
	var disc := Kit.part(_spin, Kit.cyl(1.55, 1.55, 0.05, 32), Kit.field_mat(Color(0.35, 0.6, 1.0)), Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner := Kit.part(_spin, Kit.cyl(1.5, 1.5, 0.02, 32), Kit.glow(Color(0.1, 0.12, 0.35), 1.0, 0.85), Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0))
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 6:
		var a := TAU * i / 6.0
		Kit.cube(_spin, Kit.glow(Color(0.5, 0.75, 1.0), 3.0), Vector3(cos(a), sin(a), 0) * 1.6, Vector3(0.12, 0.35, 0.08), Vector3(0, 0, a))
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.6, 1.0)
	l.light_energy = 3.0
	l.omni_range = 9.0
	l.position = Vector3(0, 2, 1)
	add_child(l)


func _build_chest() -> void:
	var wood := Kit.toon(Color("7a4a2a"), 0.03)
	var trim := Kit.toon(Color("ffc93a"), 0.02)
	Kit.cube(_spin, wood, Vector3(0, 0.35, 0), Vector3(1.2, 0.7, 0.8))
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.7, 0.4)
	_spin.add_child(lid)
	Kit.cube(lid, wood, Vector3(0, 0.15, -0.4), Vector3(1.24, 0.3, 0.84))
	Kit.cube(lid, trim, Vector3(0, 0.15, -0.4), Vector3(0.2, 0.34, 0.88))
	Kit.cube(_spin, trim, Vector3(0, 0.45, 0.42), Vector3(0.2, 0.25, 0.06))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.4)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.position.y = 1.2
	add_child(l)


func _build_loot() -> void:
	reach = 2.6
	var tier: Color = Run.TIER_COLORS[weapon.tier]
	var el: Color = Run.ELEMENTS[weapon.element].color
	_spin.position.y = 1.0
	Kit.cube(_spin, Kit.toon(tier.darkened(0.3), 0.03), Vector3(0, 0, 0), Vector3(0.18, 0.22, 0.8))
	Kit.cube(_spin, Kit.toon(Color("3a3f52"), 0.02), Vector3(0, 0.05, -0.55), Vector3(0.08, 0.08, 0.4))
	Kit.cube(_spin, Kit.glow(el, 3.0), Vector3(0, 0.13, 0), Vector3(0.1, 0.04, 0.5))
	# The loot beam: a tall soft pillar of the tier's colour, readable from across the arena.
	var beam := Kit.part(self, Kit.cyl(0.25, 0.4, 14.0, 12), Kit.glow(tier, 2.0, 0.28), Vector3(0, 7.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = tier
	l.light_energy = 2.0
	l.omni_range = 4.0
	l.position.y = 1.0
	add_child(l)


func _build_relic() -> void:
	reach = 3.0
	var brass := Kit.toon(Color("d9a441"), 0.03)
	_spin.position.y = 1.0
	Kit.part(_spin, Kit.cyl(0.4, 0.4, 0.1, 8), brass, Vector3(0, 0.6, 0))
	Kit.part(_spin, Kit.cyl(0.4, 0.4, 0.1, 8), brass, Vector3(0, -0.6, 0))
	Kit.part(_spin, Kit.cyl(0.05, 0.32, 0.55, 10), Kit.glow(Color(0.6, 0.5, 1.0), 1.5, 0.6), Vector3(0, -0.28, 0))
	Kit.part(_spin, Kit.cyl(0.32, 0.05, 0.55, 10), Kit.glow(Color(0.6, 0.5, 1.0), 1.5, 0.6), Vector3(0, 0.28, 0))
	for i in 3:
		var a := TAU * i / 3.0
		Kit.cube(_spin, brass, Vector3(cos(a) * 0.36, 0, sin(a) * 0.36), Vector3(0.06, 1.2, 0.06))
	var beam := Kit.part(self, Kit.cyl(0.3, 0.5, 16.0, 12), Kit.glow(Color(0.6, 0.5, 1.0), 2.0, 0.25), Vector3(0, 8.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.5, 1.0)
	l.light_energy = 3.0
	l.omni_range = 7.0
	l.position.y = 1.0
	add_child(l)


func _build_vendor() -> void:
	reach = 4.0
	var wood := Kit.toon(Color("6b3f2a"), 0.04)
	var cloth := Kit.toon(Color("b23a48"), 0.03)
	var brass := Kit.toon(Color("d9a441"), 0.03)
	Kit.block(self, wood, Vector3(0, 0.55, 0), Vector3(3.2, 1.1, 1.2))
	for sx in [-1.0, 1.0]:
		Kit.cube(self, wood, Vector3(1.5 * sx, 1.9, -0.4), Vector3(0.2, 2.6, 0.2))
	Kit.cube(self, cloth, Vector3(0, 3.25, -0.1), Vector3(3.6, 0.15, 1.8), Vector3(-0.25, 0, 0))
	# A big clock face on a post behind the counter.
	Kit.cube(self, wood, Vector3(0, 2.0, -0.8), Vector3(0.3, 4.0, 0.3))
	Kit.part(self, Kit.cyl(0.8, 0.8, 0.12, 16), brass, Vector3(0, 3.7, -0.65), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(self, Kit.cyl(0.65, 0.65, 0.05, 16), Kit.glow(Color("fff1cc"), 1.2), Vector3(0, 3.7, -0.57), Vector3.ONE, Vector3(PI / 2, 0, 0))
	_spin.position = Vector3(0, 3.7, -0.52)
	Kit.cube(_spin, Kit.toon(Color("2b2235")), Vector3(0, 0.22, 0), Vector3(0.05, 0.45, 0.03))
	Kit.cube(_spin, Kit.toon(Color("2b2235")), Vector3(0.15, 0, 0), Vector3(0.3, 0.05, 0.03))
	# The Clockmaker: a squat robed figure with a lantern eye.
	var robe := Kit.toon(Color("3d4a7a"), 0.04)
	Kit.part(self, Kit.cyl(0.25, 0.55, 1.4, 8), robe, Vector3(0, 1.8, -0.6))
	Kit.part(self, Kit.sphere(0.35, 8, 5), Kit.toon(Color("e8d2b0"), 0.03), Vector3(0, 2.7, -0.6))
	Kit.part(self, Kit.cyl(0.0, 0.45, 0.6, 8), robe, Vector3(0, 3.1, -0.6))
	Kit.part(self, Kit.sphere(0.1, 6, 4), Kit.glow(Color(1.0, 0.75, 0.3), 4.0), Vector3(0.12, 2.75, -0.3))
	for i in 3:
		Kit.cube(self, brass, Vector3(-1.0 + i * 1.0, 1.25, 0.1), Vector3(0.35, 0.3, 0.35), Vector3(0, i, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 2.5
	l.omni_range = 8.0
	l.position = Vector3(0, 2.6, 1.0)
	add_child(l)
	_spin.set_meta("clock", true)


func _physics_process(delta: float) -> void:
	if kind == "vendor":
		_spin.rotation.z -= delta * 0.6
