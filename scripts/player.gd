class_name Player
extends CharacterBody3D
## First-person hero: fast movement (double jump), shield + health, the hero's kit
## (Shift move, E skill, Q ultimate; see Heroes.DEFS) and the gun, which lives in gun.gd.

signal died

const SPEED := 10.0
const ACCEL := 90.0
const AIR_ACCEL := 28.0
const JUMP := 6.8
const GRAVITY := 19.0
const DASH_SPEED := 26.0
const DASH_TIME := 0.15
const SENS := 0.0024
const SHIELD_DELAY := 3.0
const SHIELD_RATE := 30.0
const STASIS_TIME := 4.0
const ULT_TIME := 8.0
const REWIND_SECONDS := 3.0
const REWIND_PLAY := 0.6

var head: Node3D
var cam: Camera3D
var vm_cam: Camera3D
var gun: Gun
var pitch := 0.0
var alive := true
var air_jumps := 1
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var cooldowns := {"shift": 0.0, "e": 0.0}
## The running ultimate ("" when none) and how long it has left.
var ult_kind := ""
var ult_t := 0.0
var glide_t := 0.0
var shield_wait := 0.0
var hurt_flash := 0.0
var shake := 0.0
var haste_t := 0.0
var prompt := ""
var input_enabled := true
## Holds the gun overlay; cutscenes hide it.
var view_layer: CanvasLayer
## Autotest drives the player through this instead of the keyboard.
var bot_move := Vector2.ZERO
var _history: Array = []
## Recall playback: a smoothed copy of the recorded path, newest first, with the distance
## along it at each point, run backwards over REWIND_PLAY seconds.
var _replay: PackedVector3Array = []
var _replay_len: PackedFloat32Array = []
var _replay_t := 0.0
var _trail_at := Vector3.ZERO
var _replay_done: Callable
var _history_t := 0.0
var _bob := 0.0
var _land_dip := 0.0
var _was_floor := true


func _ready() -> void:
	add_to_group("player")
	collision_layer = Kit.L_PLAYER
	collision_mask = Kit.L_WORLD
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)
	cam = Camera3D.new()
	cam.fov = Preferences.field_of_view
	cam.near = 0.05
	cam.far = 400.0
	cam.cull_mask = 0xFFFFF & ~Kit.VIEW_LAYER
	head.add_child(cam)
	cam.make_current()
	_build_view_camera()
	gun = Gun.new()
	gun.player = self
	cam.add_child(gun)


## The viewmodel draws through its own camera into a transparent overlay so it never
## clips into walls and keeps a fixed FOV.
func _build_view_camera() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	view_layer = layer
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	box.add_child(sv)
	vm_cam = Camera3D.new()
	vm_cam.fov = 62.0
	vm_cam.near = 0.01
	vm_cam.far = 10.0
	vm_cam.cull_mask = Kit.VIEW_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vm_cam.environment = env
	sv.add_child(vm_cam)


func _unhandled_input(event: InputEvent) -> void:
	if not alive or not input_enabled or is_rewinding():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := SENS * Preferences.mouse_sensitivity * (lerpf(1.0, 0.75, gun.ads) / gun.zoom())
		rotate_y(-event.relative.x * s)
		pitch = clampf(pitch - event.relative.y * s, -1.5, 1.5)
		head.rotation.x = pitch
		gun.sway += Vector2(event.relative.x, event.relative.y) * 0.0006
	elif event.is_action_pressed("mobility"):
		use_shift()
	elif event.is_action_pressed("skill"):
		use_e()
	elif event.is_action_pressed("ult"):
		use_ult()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("weapon_1"):
		gun.swap(0)
	elif event.is_action_pressed("weapon_2"):
		gun.swap(1)
	elif event.is_action_pressed("reload"):
		gun.start_reload()


func eye() -> Vector3:
	return cam.global_position


func aim_dir() -> Vector3:
	return -cam.global_basis.z


func chest() -> Vector3:
	return global_position + Vector3.UP * 1.2


func cd_total(slot: String) -> float:
	return Run.hero_def()[slot].cd * Run.cd_mult()


func ready_frac(slot: String) -> float:
	return 1.0 - clampf(cooldowns[slot] / maxf(0.01, cd_total(slot)), 0.0, 1.0)


func ult_active(kind: String) -> bool:
	return ult_kind == kind and ult_t > 0.0


func _physics_process(delta: float) -> void:
	for k in cooldowns:
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	haste_t = maxf(0.0, haste_t - delta)
	glide_t = maxf(0.0, glide_t - delta)
	Run.ult_lock = maxf(0.0, Run.ult_lock - delta)
	if ult_t > 0.0:
		ult_t -= delta
		if ult_t <= 0.0:
			ult_kind = ""
	elif Run.ult_lock <= 0.0 and not get_tree().get_nodes_in_group("enemies").is_empty():
		Run.ult = minf(100.0, Run.ult + 0.5 * delta)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.0)
	shake = maxf(0.0, shake - delta * 3.0)
	if not alive:
		return
	if is_rewinding():
		return
	_regen(delta)
	_record(delta)
	var input := bot_move
	if input_enabled and bot_move == Vector2.ZERO:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := SPEED * (1.0 + Run.stat("speed") + (0.5 if haste_t > 0.0 else 0.0)) * (0.7 if gun.aiming else 1.0)
	if is_on_floor():
		air_jumps = 1
	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * DASH_SPEED
		velocity.y = 0.0
	else:
		var a := ACCEL if is_on_floor() else AIR_ACCEL
		var target := wish * speed
		var horiz := Vector3(velocity.x, 0, velocity.z).move_toward(target, a * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
		var g := GRAVITY * (0.25 if glide_t > 0.0 and velocity.y < 0.0 else 1.0)
		velocity.y -= g * delta
		if glide_t > 0.0 and velocity.y < -2.5:
			velocity.y = -2.5
		if input_enabled and Input.is_action_just_pressed("jump"):
			jump()
	move_and_slide()
	if is_on_floor() and not _was_floor:
		_land_dip = 0.12
	_was_floor = is_on_floor()
	if global_position.y < -30.0:
		hurt(25.0, global_position)
		global_position = Vector3(0, 3, 0)
		velocity = Vector3.ZERO
	_find_prompt()


func jump() -> void:
	if is_on_floor():
		velocity.y = JUMP
	elif air_jumps > 0:
		air_jumps -= 1
		velocity.y = JUMP * 0.9
		Kit.burst(get_parent(), global_position, Color(0.7, 0.8, 1.0), 6, 3.0, 0.06, 0.3)


func _wish() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if bot_move == Vector2.ZERO else bot_move
	var w := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	return w if w.length() > 0.1 else -global_basis.z


## --- Hero kit -------------------------------------------------------------------

func use_shift() -> bool:
	if cooldowns.shift > 0.0 or not alive:
		return false
	var id: String = Run.hero_def().shift.id
	var ok := true
	match id:
		"blink": _blink()
		"rewind": ok = _rewind_kit()
		"slide":
			dash_t = DASH_TIME * (2.0 if Run.has("runaway") else 1.4)
			dash_dir = _wish()
			Kit.sfx(self, "throw", null, -8.0, 1.4)
		"flutter":
			velocity.y = 10.0
			var f := _wish() * 7.0
			velocity.x = f.x
			velocity.z = f.z
			glide_t = 2.2
			Kit.burst(get_parent(), global_position, Run.hero_def().accent, 10, 4.0, 0.06, 0.4)
			Kit.sfx(self, "throw", null, -8.0, 0.8)
	if not ok:
		return false
	cooldowns.shift = cd_total("shift")
	if Run.has("afterimage"):
		var d := Decoy.new()
		get_parent().add_child(d)
		d.global_position = global_position
		d.rotation.y = rotation.y
	return true


func use_e() -> bool:
	if cooldowns.e > 0.0 or not alive:
		return false
	var id: String = Run.hero_def().e.id
	var ok := true
	match id:
		"stasis": ok = cast_stasis()
		"field": cast_field()
		"haste":
			haste_t = 4.0 + (3.0 if Run.has("runaway") else 0.0)
			gun.instant_reload()
			Kit.shockwave(get_parent(), global_position, Run.hero_def().accent, 3.0)
			Kit.sfx(self, "reverse", null, -4.0, 1.5)
		"decay": _throw_decay()
	if not ok:
		return false
	cooldowns.e = cd_total("e")
	gun.cast_hand()
	return true


func use_ult() -> bool:
	if Run.ult < 100.0 or not alive or ult_t > 0.0:
		return false
	Run.ult = 0.0
	Run.ult_lock = ULT_TIME
	var id: String = Run.hero_def().q.id
	var world := get_parent()
	Kit.shockwave(world, global_position, Run.hero_def().accent, 8.0, 0.6)
	Kit.sfx(self, "rewind", null, 0.0, 0.7)
	gun.cast_hand()
	match id:
		"stopclock":
			for n in get_tree().get_nodes_in_group("chrono"):
				if n.global_position.distance_to(global_position) < 40.0 and n.can_freeze():
					n.freeze(5.0)
		"loop", "overclock":
			ult_kind = id
			ult_t = ULT_TIME
			if id == "overclock":
				gun.instant_reload()
		"collapse":
			var targets := get_tree().get_nodes_in_group("enemies").filter(
				func(e): return e.global_position.distance_to(global_position) < 40.0)
			targets.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
			for i in mini(targets.size(), 10):
				var f := Faller.new()
				f.size = 2.4 if targets[i] is Boss else 1.8
				f.released = true
				f.state = Faller.State.FALL
				f.color = Run.hero_def().fur.darkened(0.3)
				world.add_child(f)
				f.drop_at(targets[i].global_position)
				f.global_position.y -= 6.0
	return true


func _blink() -> void:
	var dir := _wish()
	var from := global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 9.0, Kit.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var to: Vector3 = (hit.position - dir * 0.7) if hit else from + dir * 9.0
	Kit.burst(get_parent(), from, Run.hero_def().accent, 10, 3.0, 0.07, 0.35)
	global_position = to - Vector3.UP * 0.9
	Kit.burst(get_parent(), to, Run.hero_def().accent, 10, 3.0, 0.07, 0.35)
	Kit.tracer(get_parent(), from, to, Run.hero_def().accent, 0.25, 0.3)
	Kit.sfx(self, "reverse", null, -6.0, 1.6)


func _rewind_kit() -> bool:
	if _history.is_empty():
		return false
	var snap: Dictionary = _history[0]
	Kit.burst(get_parent(), global_position + Vector3.UP, Run.hero_def().accent, 16, 5.0)
	Kit.sfx(self, "reverse", null, -2.0, 0.9)
	_rewind_through(func():
		Run.hp = maxf(Run.hp, snap.hp)
		Run.shield = maxf(Run.shield, snap.shield)
		if Run.has("deeploop"):
			gun.instant_reload()
			cooldowns.e = 0.0
		Kit.sfx(self, "rewind", null, -4.0, 1.3))
	return true


## Runs the recorded path backwards so a recall reads as time reversing, not a teleport.
## The samples are joined with a Catmull-Rom curve and walked at an eased, even speed.
func _rewind_through(done: Callable) -> void:
	var pts: Array[Vector3] = [global_position]
	for i in range(_history.size() - 1, -1, -1):
		pts.append(_history[i].pos)
	_history.clear()
	_replay = PackedVector3Array()
	_replay_len = PackedFloat32Array()
	var total := 0.0
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		for j in 6:
			var q: Vector3 = pts[i].cubic_interpolate(pts[i + 1], p0, p3, j / 6.0)
			if not _replay.is_empty():
				total += q.distance_to(_replay[-1])
			_replay.append(q)
			_replay_len.append(total)
	_replay.append(pts[-1])
	_replay_len.append(total + (pts[-1].distance_to(_replay[-2]) if _replay.size() > 1 else 0.0))
	_replay_t = 0.0
	_replay_done = done
	_trail_at = global_position
	velocity = Vector3.ZERO


## Driven per rendered frame, so the camera glides instead of stepping at the physics rate.
func _play_back(delta: float) -> void:
	_replay_t += delta
	var k := clampf(_replay_t / REWIND_PLAY, 0.0, 1.0)
	var want := ease(k, -2.0) * _replay_len[-1]
	var i := _replay_len.bsearch(want)
	if i <= 0:
		global_position = _replay[0]
	elif i >= _replay.size():
		global_position = _replay[-1]
	else:
		var span := maxf(_replay_len[i] - _replay_len[i - 1], 0.0001)
		global_position = _replay[i - 1].lerp(_replay[i], (want - _replay_len[i - 1]) / span)
	if _trail_at.distance_to(global_position) > 0.6:
		Kit.tracer(get_parent(), _trail_at + Vector3.UP, global_position + Vector3.UP, Run.hero_def().accent.lightened(0.3), 0.4, 0.06)
		_trail_at = global_position
	velocity = Vector3.ZERO
	if k >= 1.0:
		_replay.clear()
		_replay_done.call()


func is_rewinding() -> bool:
	return not _replay.is_empty()


func _throw_decay() -> void:
	var p := Projectile.new()
	p.from_player = true
	p.damage = 30.0 * (1.0 + 0.3 * (Run.depth() - 1)) * Run.dmg_mult()
	p.splash = 4.5
	p.decay = true
	p.color = Run.hero_def().accent
	p.velocity = aim_dir() * 22.0 + Vector3.UP * 3.0
	p.gravity = 14.0
	p.radius = 0.3
	get_parent().add_child(p)
	p.global_position = gun.hand_tip()


func _process(delta: float) -> void:
	if is_rewinding():
		_play_back(delta)
	var flat := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and flat > 1.0:
		_bob += delta * flat * 1.25
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.6)
	var base_fov := Preferences.field_of_view + (6.0 if dash_t > 0.0 and gun.ads == 0.0 else 0.0) + (14.0 if is_rewinding() else 0.0)
	# Zoom divides the view's tangent, so 4x really is four times closer.
	var target_fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / gun.zoom()))
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - exp(-20.0 * delta))
	var shake_amount := shake if Preferences.camera_shake else 0.0
	cam.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake_amount * 0.08
	cam.position.y += sin(_bob * 2.0) * 0.035 * minf(flat / SPEED, 1.0) - _land_dip
	if vm_cam:
		vm_cam.global_transform = cam.global_transform


func _regen(delta: float) -> void:
	shield_wait -= delta
	if shield_wait <= 0.0 and Run.shield < Run.max_shield():
		Run.shield = minf(Run.max_shield(), Run.shield + SHIELD_RATE * delta)
	if Run.has("heart"):
		Run.hp = minf(Run.max_hp(), Run.hp + 2.0 * delta)


func _record(delta: float) -> void:
	_history_t -= delta
	if _history_t > 0.0:
		return
	_history_t = 0.05
	_history.append({"pos": global_position, "hp": Run.hp, "shield": Run.shield})
	if _history.size() > int(REWIND_SECONDS * 20):
		_history.pop_front()


func hurt(amount: float, _from: Vector3) -> void:
	if not alive or amount <= 0.0 or is_rewinding():
		return
	shield_wait = SHIELD_DELAY
	var absorbed := minf(Run.shield, amount)
	Run.shield -= absorbed
	Run.hp -= amount - absorbed
	hurt_flash = 1.0 if absorbed < amount else 0.5
	shake = clampf(shake + amount * 0.02, 0.0, 0.6)
	Kit.sfx(self, "punch", null, -6.0, 0.8 if absorbed < amount else 1.4)
	if Run.hp <= 0.0:
		if Run.has("secondwind") and not Run.second_wind_used and not _history.is_empty():
			_rewind()
		else:
			Run.hp = 0.0
			alive = false
			Kit.sfx(self, "player_die")
			died.emit()
	Run.changed.emit()


## Second Wind: snap back to where (and how healthy) you were a few seconds ago.
func _rewind() -> void:
	Run.second_wind_used = true
	var snap: Dictionary = _history[0]
	Kit.burst(get_parent(), global_position + Vector3.UP, Color(0.6, 0.5, 1.0), 24, 6.0)
	Run.hp = maxf(snap.hp, Run.max_hp() * 0.35)
	Run.shield = snap.shield
	Kit.sfx(self, "reverse")
	_rewind_through(func():
		Kit.sfx(self, "rewind")
		Kit.shockwave(get_parent(), global_position, Color(0.6, 0.5, 1.0), 4.0))


func heal(amount: float) -> void:
	Run.hp = minf(Run.max_hp(), Run.hp + amount)
	Run.changed.emit()


func on_kill() -> void:
	if Run.has("haste"):
		haste_t = maxf(haste_t, 3.0)


## --- Time abilities ---------------------------------------------------------

## Q: freeze whatever the crosshair is on (enemy, enemy shot, or a falling structure).
func cast_stasis() -> bool:
	var target := _aimed_chrono(70.0)
	if target == null:
		Kit.sfx(self, "ui", null, -10.0, 0.6)
		return false
	var t := STASIS_TIME + (3.0 if Run.has("longstasis") else 0.0)
	var targets := [target]
	if Run.has("longstasis"):
		for n in get_tree().get_nodes_in_group("chrono"):
			if n != target and n.global_position.distance_to(target.global_position) < 4.5:
				targets.append(n)
	for n in targets:
		n.freeze(t)
	Kit.tracer(get_parent(), gun.hand_tip(), target.global_position, Color(0.55, 0.9, 1.0), 0.3, 0.08)
	Kit.shockwave(get_parent(), target.global_position, Color(0.55, 0.9, 1.0), 2.5, 0.4)
	Kit.sfx(self, "reverse", null, -4.0)
	return true


## F: drop a bubble where you aim; everything inside runs at a fraction of normal speed.
func cast_field() -> bool:
	var q := PhysicsRayQueryParameters3D.create(eye(), eye() + aim_dir() * 16.0, Kit.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var pos: Vector3 = hit.position if hit else eye() + aim_dir() * 14.0
	var f := SlowField.new()
	f.radius = 6.0 * (1.4 if Run.has("heavyfield") else 1.0)
	f.burns = Run.has("heavyfield")
	get_parent().add_child(f)
	f.global_position = pos
	Kit.sfx(self, "pull", null, -4.0)
	return true


## The chrono object (anything with freeze()) closest to the aim line, in sight.
func _aimed_chrono(reach: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var o := eye()
	var d := aim_dir()
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("chrono"):
		if not n.can_freeze():
			continue
		var p: Vector3 = n.aim_point()
		var along := (p - o).dot(d)
		if along < 0.5 or along > reach:
			continue
		var off := (o + d * along).distance_to(p)
		var allowed: float = n.aim_radius() + along * 0.035
		if off > allowed:
			continue
		var q := PhysicsRayQueryParameters3D.create(o, p, Kit.L_WORLD)
		q.exclude = [n.get_rid()] if n is CollisionObject3D else []
		if space.intersect_ray(q):
			continue
		var score := along + off * 6.0
		if score < best_score:
			best_score = score
			best = n
	return best


## --- Interaction --------------------------------------------------------------

func _find_prompt() -> void:
	var n := _nearest_interactable()
	prompt = n.prompt() if n else ""


func _nearest_interactable() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interact"):
		var d: float = n.global_position.distance_to(global_position)
		if d < n.reach and d < best_d and n.prompt() != "":
			best = n
			best_d = d
	return best


func _interact() -> void:
	var n := _nearest_interactable()
	if n:
		n.interact(self)
