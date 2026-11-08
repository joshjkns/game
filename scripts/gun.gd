class_name Gun
extends Node3D
## The held weapon: builds a chunky toon viewmodel for each gun, handles firing, reloading,
## swapping, aiming and the casting hand. Rendered only by the player's viewmodel camera.

const HIP := Vector3(0.24, -0.25, -0.5)
const BRASS := Color("d9a441")
const IRON := Color("3a3f52")

var player: Player
var aiming := false
## 0..1, how far into aim-down-sights the gun has come.
var ads := 0.0
var sway := Vector2.ZERO
var hit_marker := 0.0
var crit_marker := false
var reload_t := 0.0
var swap_t := 0.0
var _cd := 0.0
var _kick := 0.0
var _cast_t := 0.0
var _shots := 0
var _idle := 9.0
var _rig: Node3D
var _model: Node3D
var _hand: Node3D
var _flash: MeshInstance3D
var _built_for := {}


func _ready() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	_build_hand()
	rebuild()
	Run.changed.connect(_on_run_changed)


func _on_run_changed() -> void:
	if _built_for != weapon():
		rebuild()


func weapon() -> Dictionary:
	return Run.current_weapon()


func data() -> Dictionary:
	return Run.WEAPONS[weapon().id]


func ammo() -> int:
	var w := weapon()
	if not w.has("ammo"):
		w["ammo"] = data().mag
	return w.ammo


func sight_def() -> Dictionary:
	return SIGHTS.get(weapon().id, {"at": Vector3(0, 0.08, 0), "zoom": 1.25})


## Aim zoom for the world camera, eased in with the sights.
func zoom() -> float:
	return lerpf(1.0, sight_def().zoom, ease(ads, -1.6))


## Fully behind a scope: the HUD draws the scope view and the gun model hides.
func scoped() -> bool:
	return sight_def().get("scope", false) and ads > 0.9


func elem_color() -> Color:
	return Run.ELEMENTS[weapon().element].color


func reloading() -> bool:
	return reload_t > 0.0


func reload_total() -> float:
	return data().reload / (1.0 + Run.stat("reload"))


func swap(slot: int) -> void:
	if slot >= Run.weapons.size() or slot == Run.held or swap_t > 0.0:
		return
	Run.held = slot
	reload_t = 0.0
	swap_t = 0.35
	rebuild()
	Kit.sfx(self, "card", null, -6.0)


func start_reload() -> void:
	if reloading() or ammo() >= data().mag:
		return
	reload_t = reload_total()
	Kit.sfx(self, "door", null, -10.0, 1.6)


func instant_reload() -> void:
	reload_t = 0.0
	weapon().ammo = data().mag


func cast_hand() -> void:
	_cast_t = 0.35


## World-space point near the casting hand, for ability beams.
func hand_tip() -> Vector3:
	return player.cam.global_transform * Vector3(-0.25, -0.2, -0.6)


func muzzle() -> Vector3:
	return player.cam.global_transform * Vector3(0.2, -0.16, -0.9)


func _process(delta: float) -> void:
	if player == null:
		return
	_cd -= delta
	_idle += delta
	hit_marker = maxf(0.0, hit_marker - delta)
	_kick = move_toward(_kick, 0.0, delta * 1.8)
	_cast_t = maxf(0.0, _cast_t - delta)
	swap_t = maxf(0.0, swap_t - delta)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			weapon().ammo = data().mag
	var can := player.alive and player.input_enabled and not player.is_rewinding()
	aiming = can and Input.is_action_pressed("aim") and not reloading()
	if can:
		var held: bool = Input.is_action_pressed("fire") if data().auto else Input.is_action_just_pressed("fire")
		if held:
			trigger()
	_animate(delta)


## Pull the trigger once (respecting fire rate). Returns true if a shot went out.
func trigger() -> bool:
	if _cd > 0.0 or swap_t > 0.0:
		return false
	if reloading():
		if ammo() > 0:
			reload_t = 0.0
		else:
			return false
	if ammo() <= 0:
		start_reload()
		return false
	var haste := 1.5 if player.haste_t > 0.0 else 1.0
	if player.ult_active("overclock"):
		haste *= 2.0
	_cd = 1.0 / (data().rate * Run.rate_mult() * haste)
	if not player.ult_active("overclock"):
		weapon().ammo -= 1
	var bonus := 1.0
	if Run.has("stopwatch") and _idle >= 1.5:
		bonus += 1.2
	if Run.has("borrowed") and Run.shield <= 0.0:
		bonus += 0.35
	if player.ult_active("overclock"):
		bonus += 0.3
	_idle = 0.0
	_shoot(bonus)
	_shots += 1
	if player.ult_active("loop") or (Run.has("echo") and _shots % 5 == 0):
		get_tree().create_timer(0.22).timeout.connect(func():
			if is_instance_valid(self) and player.alive:
				_shoot(bonus, true))
	if weapon().ammo <= 0:
		if Run.has("refill") and randf() < 0.35:
			weapon().ammo = data().mag
			Kit.burst(player.get_parent(), muzzle(), Color(0.6, 0.5, 1.0), 8, 2.0, 0.05, 0.3)
			Kit.sfx(self, "rewind", null, -10.0, 1.6)
		else:
			start_reload()
	return true


func _shoot(bonus: float, echo := false) -> void:
	var d := data()
	var w := weapon()
	var dmg := Run.weapon_dmg(w) * Run.dmg_mult() * bonus
	var col := elem_color() if not echo else Color(0.7, 0.55, 1.0)
	var space := player.get_world_3d().direct_space_state
	var world := player.get_parent()
	var o := player.eye()
	var fwd := player.aim_dir()
	var spread: float = deg_to_rad(d.spread) * (0.4 if aiming else 1.0)
	_kick = minf(_kick + d.kick, 0.4)
	player.pitch = clampf(player.pitch + d.kick * 0.12, -1.5, 1.5)
	player.head.rotation.x = player.pitch
	_flash.visible = true
	get_tree().create_timer(0.04).timeout.connect(func(): if is_instance_valid(_flash): _flash.visible = false)
	if d.kind != "beam" or _shots % 3 == 0:
		Kit.sfx(self, "fire", null, -4.0 if d.kind != "beam" else -12.0, _pitch_for(w.id))
	Kit.flash(world, muzzle(), col, 2.0, 5.0, 0.06)
	if d.kind == "shell":
		var p := Projectile.new()
		p.from_player = true
		p.damage = dmg
		p.splash = d.splash
		p.element = w.element
		p.color = col
		p.velocity = fwd * d.speed + Vector3.UP * 2.0
		p.gravity = 9.0
		p.radius = 0.25
		world.add_child(p)
		p.global_position = muzzle()
		return
	for i in d.pellets:
		var dir := fwd
		if spread > 0.0:
			var b := player.cam.global_basis
			dir = (fwd + b.x * randfn(0.0, spread * 0.5) + b.y * randfn(0.0, spread * 0.5)).normalized()
		var exclude: Array[RID] = [player.get_rid()]
		var start := o
		var end := o + dir * 200.0
		var pierce: int = d.get("pierce", 0)
		var last := end
		while true:
			var q := PhysicsRayQueryParameters3D.create(start, end, Kit.L_WORLD | Kit.L_ENEMY)
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			last = hit.position
			var c: Object = hit.collider
			if c is Enemy:
				var crit: bool = c.is_head(hit.position) or randf() < Run.crit_chance()
				c.take_hit(dmg, crit, w.element, hit.position, dir)
				if player.ult_active("loop"):
					player.heal(dmg * 0.12)
				hit_marker = 0.12
				crit_marker = crit
				if pierce > 0:
					pierce -= 1
					exclude.append(c.get_rid())
					start = hit.position
					continue
			else:
				Kit.burst(world, hit.position + hit.normal * 0.05, col, 4, 3.0, 0.05, 0.25)
			break
		if d.kind == "beam":
			Kit.tracer(world, muzzle(), last, col, 0.09, 0.07)
		else:
			Kit.tracer(world, muzzle(), last, col, 0.1, 0.03 if d.pellets > 1 else 0.045)


func _pitch_for(id: String) -> float:
	return {"tick": 1.0, "chatter": 1.35, "bellow": 0.7, "mortar": 0.55, "lancet": 1.8, "pike": 0.8}.get(id, 1.0)


func _animate(delta: float) -> void:
	sway = sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var flat := Vector2(player.velocity.x, player.velocity.z).length()
	var t := Time.get_ticks_msec() / 1000.0
	var bob := Vector3(sin(t * 9.0) * 0.012, absf(cos(t * 9.0)) * -0.014, 0) * minf(flat / Player.SPEED, 1.0)
	if not player.is_on_floor():
		bob.y += clampf(player.velocity.y * -0.004, -0.04, 0.04)
	ads = move_toward(ads, 1.0 if aiming else 0.0, delta * 7.0)
	var sight: Vector3 = sight_def().at
	var base := HIP.lerp(Vector3(-sight.x, -sight.y, -EYE_RELIEF - sight.z), ease(ads, -1.6))
	if _model:
		_model.visible = not scoped()
	var steady := 1.0 - 0.75 * ads
	var target := base + (bob + Vector3(-sway.x, sway.y, 0) * 0.6) * steady + Vector3(0, 0, _kick * 0.6)
	var rot := Vector3(_kick * 1.4, -sway.x * 1.2, sway.x * 0.8) * steady
	if reloading():
		var k := sin(clampf(1.0 - reload_t / reload_total(), 0.0, 1.0) * PI)
		target += Vector3(0, -0.12, 0.05) * k
		rot += Vector3(-0.5, 0.2, 0.7) * k
	if swap_t > 0.0:
		target.y -= swap_t * 0.9
		rot.x -= swap_t * 2.0
	if player.dash_t > 0.0:
		target.z += 0.06
	_rig.position = _rig.position.lerp(target, 1.0 - exp(-18.0 * delta))
	_rig.rotation = _rig.rotation.lerp(rot, 1.0 - exp(-16.0 * delta))
	var hand_target := Vector3(-0.3, -0.26, -0.48) if _cast_t > 0.0 else Vector3(-0.42, -0.55, -0.42)
	_hand.position = _hand.position.lerp(hand_target, 1.0 - exp(-20.0 * delta))
	_hand.rotation = _hand.rotation.lerp(Vector3(0.6, 0.3, 0.3) if _cast_t > 0.0 else Vector3(0.2, 0.5, 0.6), 1.0 - exp(-14.0 * delta))


## --- Models -------------------------------------------------------------------

func rebuild() -> void:
	_built_for = weapon().duplicate()
	if _model:
		_model.queue_free()
	var w := weapon()
	_model = build_model(w)
	_rig.add_child(_model)
	# Right hand on the grip.
	var hd := Run.hero_def()
	var glove := Kit.toon(hd.fur, 0.005)
	Kit.cube(_model, Kit.toon(IRON.darkened(0.3), 0.005), Vector3(0, -0.07, 0.03), Vector3(0.05, 0.12, 0.05), Vector3(0.35, 0, 0))
	Kit.cube(_model, glove, Vector3(0.0, -0.1, 0.06), Vector3(0.09, 0.08, 0.1), Vector3(0.35, 0, 0))
	Kit.cube(_model, Kit.toon(hd.fur.darkened(0.15), 0.005), Vector3(0.0, -0.17, 0.16), Vector3(0.08, 0.08, 0.18), Vector3(0.6, 0, 0))
	_flash = Kit.part(_model, Kit.sphere(0.07, 6, 4), Kit.glow(elem_color(), 6.0, 0.9), _muzzle_local(w.id))
	_flash.visible = false
	_set_view_layer(_model)


## Where each gun's sight sits in model space (the point the eye lines up behind), how far
## aiming zooms the view, and whether it's a full scope that takes over the screen.
const SIGHTS := {
	"tick": {"at": Vector3(0, 0.097, 0.0), "zoom": 1.35},
	"chatter": {"at": Vector3(0, 0.105, -0.06), "zoom": 1.3},
	"bellow": {"at": Vector3(0, 0.088, 0.0), "zoom": 1.15},
	"mortar": {"at": Vector3(-0.115, 0.12, 0.04), "zoom": 1.2},
	"lancet": {"at": Vector3(0, 0.112, -0.06), "zoom": 1.3},
	"pike": {"at": Vector3(0, 0.105, 0.04), "zoom": 4.0, "scope": true},
}
## How far in front of the eye the sight sits when aiming.
const EYE_RELIEF := 0.26
const WOOD := Color("6b4428")
const LEATHER := Color("4a3324")


## The gun itself (no hands), facing -Z. Shared by the viewmodel and the rendered HUD/shop icons.
static func build_model(w: Dictionary) -> Node3D:
	var m := Node3D.new()
	var body := Kit.toon(body_color(w.id), 0.007)
	var brass := Kit.toon(BRASS, 0.005)
	var iron := Kit.toon(IRON, 0.005)
	var dark := Kit.toon(IRON.darkened(0.45), 0.004)
	var wood := Kit.toon(WOOD, 0.006)
	var stripe := Kit.glow(Run.TIER_COLORS[w.tier], 1.6)
	var core := Kit.glow(Run.ELEMENTS[w.element].color, 3.5)
	var lens := Kit.glow(Color(0.45, 0.95, 0.9), 0.8, 0.35)
	match w.id:
		"tick":
			# Revolver: top strap, fat brass cylinder, underlugged barrel, wooden grip.
			Kit.cube(m, body, Vector3(0, 0.02, -0.06), Vector3(0.06, 0.1, 0.2))
			Kit.cube(m, body, Vector3(0, 0.077, -0.2), Vector3(0.05, 0.022, 0.42))
			Kit.part(m, Kit.cyl(0.052, 0.052, 0.11, 6), brass, Vector3(0, 0.025, -0.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				Kit.part(m, Kit.cyl(0.012, 0.012, 0.112, 6), dark, Vector3(cos(a) * 0.04, 0.025 + sin(a) * 0.04, -0.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.022, 0.024, 0.3, 8), iron, Vector3(0, 0.05, -0.31), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, body, Vector3(0, 0.022, -0.31), Vector3(0.03, 0.032, 0.26))
			Kit.cube(m, iron, Vector3(0, 0.085, 0.05), Vector3(0.02, 0.035, 0.03), Vector3(-0.6, 0, 0))
			Kit.cube(m, wood, Vector3(0, -0.07, 0.05), Vector3(0.05, 0.14, 0.07), Vector3(0.35, 0, 0))
			Kit.cube(m, brass, Vector3(0, -0.14, 0.075), Vector3(0.052, 0.02, 0.072), Vector3(0.35, 0, 0))
			Kit.cube(m, iron, Vector3(0, -0.055, -0.03), Vector3(0.012, 0.012, 0.08))
			Kit.cube(m, iron, Vector3(0, -0.035, -0.07), Vector3(0.012, 0.04, 0.012))
			_iron_sights(m, iron, brass, 0.097, 0.0, -0.44)
			Kit.cube(m, stripe, Vector3(0.026, 0.077, -0.25), Vector3(0.004, 0.012, 0.26))
			Kit.part(m, Kit.sphere(0.022, 6, 4), core, Vector3(0.03, 0.03, -0.03))
		"chatter":
			# SMG: boxy receiver, vented shroud, drum mag, foregrip, folded stock, red dot.
			Kit.cube(m, body, Vector3(0, 0.02, -0.12), Vector3(0.08, 0.1, 0.34))
			Kit.cube(m, iron, Vector3(0, 0.076, -0.12), Vector3(0.03, 0.012, 0.3))
			Kit.part(m, Kit.cyl(0.038, 0.038, 0.18, 8), iron, Vector3(0, 0.03, -0.38), Vector3.ONE, Vector3(PI / 2, 0, 0))
			for i in 3:
				Kit.cube(m, dark, Vector3(0.036, 0.03, -0.32 - i * 0.045), Vector3(0.01, 0.018, 0.025))
			Kit.part(m, Kit.cyl(0.044, 0.044, 0.035, 8), brass, Vector3(0, 0.03, -0.48), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.075, 0.075, 0.06, 12), brass, Vector3(0, -0.08, -0.14), Vector3.ONE, Vector3(0, 0, PI / 2))
			Kit.part(m, Kit.cyl(0.03, 0.03, 0.065, 8), iron, Vector3(0, -0.08, -0.14), Vector3.ONE, Vector3(0, 0, PI / 2))
			Kit.cube(m, wood, Vector3(0, -0.06, 0.04), Vector3(0.05, 0.12, 0.06), Vector3(0.3, 0, 0))
			Kit.cube(m, wood, Vector3(0, -0.04, -0.27), Vector3(0.04, 0.08, 0.04), Vector3(-0.15, 0, 0))
			for sx in [-1.0, 1.0]:
				Kit.cube(m, iron, Vector3(0.032 * sx, 0.0, 0.14), Vector3(0.012, 0.012, 0.2))
			Kit.cube(m, iron, Vector3(0, 0.0, 0.24), Vector3(0.076, 0.05, 0.014))
			_red_dot(m, iron, lens, 0.105, -0.06)
			Kit.cube(m, stripe, Vector3(0.041, 0.02, -0.12), Vector3(0.004, 0.014, 0.22))
			Kit.part(m, Kit.sphere(0.025, 6, 4), core, Vector3(0.04, -0.08, -0.14))
		"bellow":
			# Double-barrel with a leather bellows pump, sighting rib and brass bead.
			Kit.cube(m, body, Vector3(0, 0.0, -0.03), Vector3(0.11, 0.1, 0.2))
			for sx in [-1.0, 1.0]:
				Kit.part(m, Kit.cyl(0.034, 0.036, 0.42, 8), iron, Vector3(0.033 * sx, 0.035, -0.34), Vector3.ONE, Vector3(PI / 2, 0, 0))
				Kit.part(m, Kit.cyl(0.022, 0.022, 0.43, 8), dark, Vector3(0.033 * sx, 0.035, -0.34), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, iron, Vector3(0, 0.072, -0.32), Vector3(0.018, 0.012, 0.44))
			Kit.part(m, Kit.sphere(0.011, 6, 4), Kit.glow(BRASS, 1.2), Vector3(0, 0.088, -0.53))
			for sx in [-1.0, 1.0]:
				Kit.cube(m, iron, Vector3(0.011 * sx, 0.085, 0.0), Vector3(0.008, 0.028, 0.01))
			var leather := Kit.toon(LEATHER, 0.005)
			for i in 5:
				Kit.cube(m, leather if i % 2 == 0 else brass, Vector3(0, -0.035, -0.16 - i * 0.04), Vector3(0.09 - (i % 2) * 0.015, 0.06 - (i % 2) * 0.012, 0.035))
			Kit.cube(m, wood, Vector3(0, -0.03, 0.14), Vector3(0.07, 0.1, 0.18), Vector3(0.15, 0, 0))
			Kit.cube(m, Kit.toon(LEATHER.darkened(0.3)), Vector3(0, -0.04, 0.235), Vector3(0.075, 0.115, 0.02), Vector3(0.15, 0, 0))
			Kit.cube(m, stripe, Vector3(0.056, 0.0, -0.03), Vector3(0.004, 0.016, 0.16))
			Kit.part(m, Kit.sphere(0.03, 6, 4), core, Vector3(0, -0.035, -0.08))
		"mortar":
			# A cuckoo clock with a tube on it: the house, its little door, a dial, a ladder sight.
			Kit.part(m, Kit.cyl(0.085, 0.07, 0.42, 10), iron, Vector3(0, 0.04, -0.22), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.06, 0.06, 0.43, 10), dark, Vector3(0, 0.04, -0.22), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.1, 0.1, 0.06, 10), brass, Vector3(0, 0.04, -0.44), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.095, 0.095, 0.04, 10), brass, Vector3(0, 0.04, -0.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, wood, Vector3(0, 0.06, 0.04), Vector3(0.16, 0.15, 0.14))
			Kit.part(m, Kit.cyl(0.0, 0.13, 0.08, 4), body, Vector3(0, 0.175, 0.04), Vector3.ONE, Vector3(0, PI / 4, 0))
			Kit.part(m, Kit.cyl(0.045, 0.045, 0.01, 12), Kit.toon(Color("efe6d2")), Vector3(0.082, 0.07, 0.04), Vector3.ONE, Vector3(0, 0, PI / 2))
			Kit.cube(m, dark, Vector3(0.088, 0.085, 0.04), Vector3(0.004, 0.032, 0.006))
			Kit.cube(m, dark, Vector3(0.088, 0.07, 0.05), Vector3(0.004, 0.006, 0.022))
			Kit.cube(m, wood, Vector3(0, -0.07, 0.06), Vector3(0.05, 0.12, 0.06), Vector3(0.3, 0, 0))
			for i in 3:
				Kit.part(m, Kit.cyl(0.014, 0.014, 0.06, 6), brass, Vector3(0.09, -0.01, -0.02 - i * 0.03))
			# Ladder sight on the left, clear of the barrel.
			Kit.cube(m, iron, Vector3(-0.1, 0.06, -0.15), Vector3(0.012, 0.012, 0.42))
			for sx in [-1.0, 1.0]:
				Kit.cube(m, iron, Vector3(-0.115 + 0.012 * sx, 0.1, 0.04), Vector3(0.006, 0.07, 0.006))
			Kit.cube(m, iron, Vector3(-0.115, 0.135, 0.04), Vector3(0.03, 0.006, 0.006))
			Kit.cube(m, iron, Vector3(-0.115, 0.098, -0.33), Vector3(0.007, 0.07, 0.007))
			Kit.part(m, Kit.sphere(0.008, 6, 4), Kit.glow(BRASS, 1.5), Vector3(-0.115, 0.122, -0.33))
			Kit.part(m, Kit.sphere(0.035, 6, 4), core, Vector3(0, 0.07, -0.032))
			Kit.cube(m, stripe, Vector3(0.081, 0.02, 0.04), Vector3(0.004, 0.012, 0.12))
		"lancet":
			# Beam caster: brass prongs, glowing coils, an energy cell and a holo ring sight.
			Kit.cube(m, body, Vector3(0, 0.01, -0.06), Vector3(0.07, 0.09, 0.26))
			Kit.cube(m, body, Vector3(0, 0.05, -0.2), Vector3(0.05, 0.03, 0.14))
			for sx in [-1.0, 1.0]:
				Kit.cube(m, brass, Vector3(0.03 * sx, 0.03, -0.34), Vector3(0.016, 0.022, 0.36))
			for i in 3:
				Kit.part(m, Kit.cyl(0.052, 0.052, 0.018, 12), core, Vector3(0, 0.03, -0.24 - i * 0.09), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.0, 0.025, 0.06, 6), Kit.glow(Run.ELEMENTS[w.element].color.lightened(0.4), 4.0), Vector3(0, 0.03, -0.5), Vector3.ONE, Vector3(-PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.024, 0.024, 0.12, 8), core, Vector3(0, -0.035, 0.07), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.part(m, Kit.cyl(0.03, 0.03, 0.02, 8), iron, Vector3(0, -0.035, 0.135), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, Kit.toon(IRON.darkened(0.2)), Vector3(0, -0.07, 0.0), Vector3(0.045, 0.12, 0.055), Vector3(0.3, 0, 0))
			Kit.cube(m, iron, Vector3(0, 0.07, -0.06), Vector3(0.012, 0.03, 0.02))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.02
			ring.outer_radius = 0.026
			ring.rings = 20
			ring.ring_segments = 4
			Kit.part(m, ring, Kit.glow(Run.ELEMENTS[w.element].color.lightened(0.3), 2.5, 0.9), Vector3(0, 0.112, -0.06), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, stripe, Vector3(0.036, 0.01, -0.06), Vector3(0.004, 0.014, 0.18))
		"pike":
			# Bolt rifle: long fluted barrel, muzzle brake, cheek-rest stock, bolt, scope.
			Kit.cube(m, body, Vector3(0, 0.01, -0.1), Vector3(0.07, 0.1, 0.36))
			Kit.part(m, Kit.cyl(0.02, 0.026, 0.52, 8), iron, Vector3(0, 0.035, -0.53), Vector3.ONE, Vector3(PI / 2, 0, 0))
			Kit.cube(m, iron, Vector3(0, 0.035, -0.8), Vector3(0.05, 0.03, 0.06))
			for sx in [-1.0, 1.0]:
				Kit.cube(m, dark, Vector3(0.026 * sx, 0.035, -0.8), Vector3(0.004, 0.02, 0.04))
			Kit.cube(m, wood, Vector3(0, -0.01, -0.36), Vector3(0.06, 0.05, 0.3))
			Kit.cube(m, wood, Vector3(0, -0.02, 0.17), Vector3(0.06, 0.11, 0.22))
			Kit.cube(m, wood, Vector3(0, 0.045, 0.14), Vector3(0.05, 0.03, 0.12))
			Kit.cube(m, Kit.toon(LEATHER.darkened(0.3)), Vector3(0, -0.02, 0.285), Vector3(0.065, 0.12, 0.02))
			Kit.cube(m, iron, Vector3(0, -0.065, -0.12), Vector3(0.045, 0.07, 0.06))
			Kit.part(m, Kit.cyl(0.008, 0.008, 0.06, 6), iron, Vector3(0.05, 0.04, -0.01), Vector3.ONE, Vector3(0, 0, PI / 2))
			Kit.part(m, Kit.sphere(0.014, 6, 4), brass, Vector3(0.08, 0.04, -0.01))
			_scope(m, iron, brass, lens, 0.105)
			Kit.cube(m, stripe, Vector3(0.036, 0.01, -0.16), Vector3(0.004, 0.014, 0.26))
			Kit.part(m, Kit.sphere(0.026, 6, 4), core, Vector3(-0.036, 0.02, -0.05))
	return m


## Rear notch and front post, both topping out at the sight line.
static func _iron_sights(m: Node3D, iron: Material, front: Material, y: float, rear_z: float, front_z: float) -> void:
	for sx in [-1.0, 1.0]:
		Kit.cube(m, iron, Vector3(0.012 * sx, y - 0.008, rear_z), Vector3(0.01, 0.024, 0.012))
	Kit.cube(m, front, Vector3(0, y - 0.01, front_z), Vector3(0.008, 0.03, 0.012))


## A small boxy red-dot: an open frame round tinted glass, with the dot floating in it.
static func _red_dot(m: Node3D, iron: Material, glass: Material, y: float, z: float) -> void:
	Kit.cube(m, iron, Vector3(0, y - 0.03, z), Vector3(0.05, 0.012, 0.07))
	for sx in [-1.0, 1.0]:
		Kit.cube(m, iron, Vector3(0.024 * sx, y, z), Vector3(0.006, 0.05, 0.05))
	Kit.cube(m, iron, Vector3(0, y + 0.024, z), Vector3(0.054, 0.006, 0.05))
	Kit.cube(m, glass, Vector3(0, y, z - 0.02), Vector3(0.042, 0.042, 0.002))
	Kit.part(m, Kit.sphere(0.004, 6, 4), Kit.glow(Color(1.0, 0.2, 0.15), 6.0), Vector3(0, y, z - 0.021))


## Long scope on two rings: bells at each end with tinted lenses.
static func _scope(m: Node3D, iron: Material, brass: Material, glass: Material, y: float) -> void:
	Kit.part(m, Kit.cyl(0.024, 0.024, 0.24, 10), iron, Vector3(0, y, -0.1), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(m, Kit.cyl(0.036, 0.026, 0.07, 10), iron, Vector3(0, y, -0.25), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(m, Kit.cyl(0.026, 0.032, 0.05, 10), iron, Vector3(0, y, 0.04), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(m, Kit.cyl(0.032, 0.032, 0.004, 12), glass, Vector3(0, y, -0.287), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(m, Kit.cyl(0.03, 0.03, 0.004, 12), glass, Vector3(0, y, 0.066), Vector3.ONE, Vector3(PI / 2, 0, 0))
	Kit.part(m, Kit.cyl(0.012, 0.012, 0.03, 8), brass, Vector3(0, y + 0.03, -0.1))
	Kit.part(m, Kit.cyl(0.012, 0.012, 0.03, 8), brass, Vector3(0.03, y, -0.1), Vector3.ONE, Vector3(0, 0, PI / 2))
	for z in [-0.17, -0.02]:
		Kit.part(m, Kit.cyl(0.028, 0.028, 0.02, 10), brass, Vector3(0, y, z), Vector3.ONE, Vector3(PI / 2, 0, 0))
		Kit.cube(m, iron, Vector3(0, y - 0.04, z), Vector3(0.02, 0.05, 0.016))


func _muzzle_local(id: String) -> Vector3:
	return {"tick": Vector3(0, 0.05, -0.47), "chatter": Vector3(0, 0.03, -0.5),
		"bellow": Vector3(0, 0.035, -0.56), "mortar": Vector3(0, 0.04, -0.48),
		"lancet": Vector3(0, 0.03, -0.54), "pike": Vector3(0, 0.035, -0.84)}.get(id, Vector3(0, 0, -0.4))


static func body_color(id: String) -> Color:
	return {"tick": Color("8c2f39"), "chatter": Color("2f6f8c"), "bellow": Color("6b4a2f"),
		"mortar": Color("3f6b3a"), "lancet": Color("5a3f8c"), "pike": Color("2b2f45")}.get(id, Color.GRAY)


## The left paw: the hero's fur, a brass bracer and a glowing clock face that casts the kit.
func _build_hand() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	_hand.position = Vector3(-0.42, -0.55, -0.42)
	var brass := Kit.toon(BRASS, 0.005)
	var hd := Run.hero_def()
	Kit.cube(_hand, Kit.toon(hd.fur, 0.007), Vector3(0, -0.04, 0.12), Vector3(0.09, 0.09, 0.24))
	Kit.part(_hand, Kit.sphere(0.065, 10, 6), Kit.toon(hd.fur, 0.006), Vector3(0, -0.01, -0.08), Vector3(1, 0.8, 1.1))
	Kit.cube(_hand, brass, Vector3(0, 0, 0), Vector3(0.11, 0.1, 0.12))
	for i in 4:
		Kit.part(_hand, Kit.sphere(0.022, 8, 5), Kit.toon(hd.fur, 0.004), Vector3(-0.04 + i * 0.027, 0.0, -0.13))
	Kit.part(_hand, Kit.cyl(0.045, 0.045, 0.012, 12), Kit.glow(hd.accent, 3.0), Vector3(0, 0.056, 0.02))
	Kit.cube(_hand, Kit.glow(Color(1, 0.9, 0.6), 2.0), Vector3(0, 0.064, 0.0), Vector3(0.006, 0.004, 0.035))
	_set_view_layer(_hand)


func _set_view_layer(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers = Kit.VIEW_LAYER
		if n is GeometryInstance3D:
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_view_layer(c)
