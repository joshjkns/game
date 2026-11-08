class_name Player
extends CharacterBody3D
## One agent. Each PC is authoritative over its own player's movement and camera.
## LEON (A) runs forward; NOEL (B) is inverted: same controls, but everything NOEL does
## plays backwards on both screens.

const RADIUS := 0.35
const HEIGHT := 1.8
const SPEED := 5.5
const ACCEL := 45.0
const JUMP := 5.2
const GRAVITY := 16.0
const SENS := 0.0022
const SEND_RATE := 30.0
const PUNCH_RANGE := 2.6
const PUNCH_COOLDOWN := 0.45
const PULL_COOLDOWN := 2.0
const REVERSE_COOLDOWN := 3.0
const REVERSE_RANGE := 6.0
const UNTHROW_RANGE := 16.0
const REVIVE_TIME := 1.5
const REVIVE_RANGE := 2.6
# Movement kit. Every move keeps its momentum: speed above the walking target bleeds off slowly.
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 3.0
const AIR_ACCEL := 14.0
const MOMENTUM_DRAG := 6.0
## Capsule height and eye height while sliding or crouched (fits under a 1 m gap).
const LOW_HEIGHT := 0.9
const LOW_EYE := 0.7
const SLIDE_MIN_SPEED := 6.5
const SLIDE_SPEED := 10.5
const SLIDE_FRICTION := 7.0
const SLIDE_STEER := 2.0
const KICK_RANGE := 1.2
const KICK_STUN := 1.6
const KICK_FORCE := 9.0
const KICK_COOLDOWN := 0.5
## Ledges from VAULT_MIN up to MANTLE_MAX above the feet are climbed automatically when moved into.
const VAULT_MIN := 0.4
const MANTLE_MAX := 1.7
const VAULT_REACH := 0.6
const VAULT_TIME := 0.28
const WALL_RUN_TIME := 1.2
const WALL_RUN_MIN_SPEED := 5.0
const WALL_RUN_SPEED := 8.5
const WALL_RUN_LIFT := 2.0
const WALL_RUN_GRAVITY := 3.0
const WALL_REACH := 0.5
const WALL_JUMP_OUT := 6.0
const WALL_LEAN := 0.25
const DASH_SPEED := 20.0
const DASH_TIME := 0.16
const DASH_COOLDOWN := 3.0
## What movement rays and headroom checks collide with.
const SOLID := Util.L_WORLD | Util.L_GLASS | Util.L_GATE

enum Move { WALK, AIR, CROUCH, SLIDE, DASH, WALL_RUN, VAULT }


## What the agent wants this physics frame: read from the keyboard on the controlling PC,
## or set directly by the autotest. All buttons are "held"; presses are edges between frames.
class Intent:
	var move := Vector2.ZERO
	var sprint := false
	var crouch := false
	var jump := false
	var dash := false


var role := "A"
## Whether this PC drives this player (and looks through its camera).
var controlled := false
var present := true
var alive := true
var echo := false
var pitch := 0.0
var cam: Camera3D
var vm: Viewmodel
var revive_progress := 0.0
## True while the opening plays: the camera is scripted, mouse look is ignored.
var cinematic := false
var cooldowns := {}
var movement_state := Move.WALK
## Test-only: drives this player instead of the keyboard (set by the autotest).
var bot: Intent

var _rig: Node3D
var _body: Humanoid
var _label: Label3D
var _xray: MeshInstance3D
var _hand_gun: GunModel
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_vel := Vector3.ZERO
var _net_age := 0.0
var _send_t := 0.0
var _look := Vector2.ZERO
var _cam_rest := Vector3(0, Util.EYE_H, 0)
var _death_tw: Tween
var _vm_layer: CanvasLayer
var _capsule: CapsuleShape3D
var _collider: CollisionShape3D
var _probe := CapsuleShape3D.new()
var _low := false
var _was := Intent.new()
var _move_t := 0.0
var _wall_n := Vector3.ZERO
## The wall last run on: it cannot be run again until the agent touches the floor.
var _last_wall := Vector3.ZERO
var _lean := 0.0
var _dash_dir := Vector3.ZERO
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _vault_vel := Vector3.ZERO


func _ready() -> void:
	collision_layer = Util.L_PLAYER
	collision_mask = Util.L_WORLD | Util.L_GLASS | Util.L_ENEMY | Util.L_PLAYER | Util.L_GATE
	_collider = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = HEIGHT
	_collider.shape = _capsule
	_collider.position.y = HEIGHT * 0.5
	add_child(_collider)
	_probe.radius = RADIUS - 0.02

	var c := Util.role_color(role)
	_rig = Node3D.new()
	add_child(_rig)
	_body = Humanoid.new(Humanoid.Style.LEON if role == Util.A else Humanoid.Style.NOEL, c)
	_body.two_handed = false
	_rig.add_child(_body)
	# Rim visible through walls so partners can always find each other.
	_xray = Util.capsule(RADIUS + 0.02, HEIGHT, _xray_material(c))
	_xray.position.y = HEIGHT * 0.5
	_xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(_xray)
	_hand_gun = GunModel.new()
	_hand_gun.position = Vector3(0, -0.02, 0.06)
	_hand_gun.scale = Vector3.ONE * 1.25
	_body.weapon_socket.add_child(_hand_gun)
	_label = label_node()
	_rig.add_child(_label)

	cam = Camera3D.new()
	cam.position = _cam_rest
	cam.fov = 85.0
	cam.near = 0.03
	add_child(cam)
	_build_viewmodel()
	show_gun(false)
	set_controlled(controlled)
	_net_pos = global_position


## The viewmodel renders in its own transparent viewport on top of the world, so it never
## clips into walls and never shows up in the wet floor's screen-space reflections.
func _build_viewmodel() -> void:
	_vm_layer = CanvasLayer.new()
	_vm_layer.layer = 1
	add_child(_vm_layer)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vm_layer.add_child(svc)
	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	sv.audio_listener_enable_3d = false
	svc.add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.42, 0.36)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.5, 0.9, 0)
	key.light_energy = 1.1
	key.light_color = Color(1.0, 0.68, 0.42)
	sv.add_child(key)
	var rim_light := DirectionalLight3D.new()
	rim_light.rotation = Vector3(-0.2, PI - 0.6, 0)
	rim_light.light_energy = 0.5
	rim_light.light_color = Color(0.55, 0.65, 1.0)
	sv.add_child(rim_light)
	var vm_cam := Camera3D.new()
	vm_cam.fov = cam.fov
	vm_cam.near = 0.01
	vm_cam.current = true
	sv.add_child(vm_cam)
	vm = Viewmodel.new()
	vm.role = role
	vm_cam.add_child(vm)


func label_node() -> Label3D:
	var label := Label3D.new()
	label.text = Util.role_name(role)
	label.font = load("res://assets/fonts/Anton-Regular.ttf")
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Util.role_color(role) * 1.5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0008
	label.position.y = 2.25
	return label


static func _xray_material(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, blend_add, cull_back, shadows_disabled;
uniform vec4 tint : source_color;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb * (0.015 + rim * 0.55);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", c)
	m.render_priority = 5
	return m


func set_controlled(on: bool) -> void:
	controlled = on
	if cam == null:
		return
	cam.current = on
	# You never see your own body, only its shadow on the floor.
	_body.set_shadow_only(on)
	_hand_gun.cast_shadow_only(on)
	_xray.visible = not on
	_label.visible = not on
	_vm_layer.visible = on


func is_local() -> bool:
	return is_multiplayer_authority()


func eye() -> Vector3:
	return cam.global_position if cam else global_position + _cam_rest


func chest() -> Vector3:
	return global_position + Vector3(0, Util.CHEST_H, 0)


func aim_dir() -> Vector3:
	return -cam.global_basis.z


func muzzle() -> Vector3:
	if controlled:
		# The viewmodel camera sits at its world's origin, so this maps it into the real world.
		return cam.global_transform * vm.muzzle_global()
	return _hand_gun.muzzle.global_position


## Scripted look pitch (opening cinematic).
func set_look(p: float) -> void:
	pitch = p
	cam.rotation.x = p


func show_gun(on: bool) -> void:
	if vm == null:
		return
	vm.show_gun(on)
	_hand_gun.visible = on


func respawn(pos: Vector3, face: Vector3) -> void:
	if _death_tw and _death_tw.is_valid():
		_death_tw.kill()
	global_position = pos
	rotation = Vector3(0, Util.yaw_of(face), 0)
	pitch = 0.0
	velocity = Vector3.ZERO
	alive = true
	echo = false
	revive_progress = 0.0
	cooldowns.clear()
	_set_move(Move.WALK)
	_set_low(false)
	_last_wall = Vector3.ZERO
	_lean = 0.0
	_net_pos = pos
	_net_vel = Vector3.ZERO
	_net_yaw = rotation.y
	_net_pitch = 0.0
	cam.position = _cam_rest
	cam.rotation = Vector3.ZERO
	_rig.rotation = Vector3.ZERO
	_rig.position = Vector3.ZERO
	_body.set_ghost(false)
	_body.set_shadow_only(controlled)
	collision_layer = Util.L_PLAYER


# --- Death and un-death -------------------------------------------------------

func on_died(as_echo: bool) -> void:
	alive = false
	echo = as_echo
	collision_layer = 0
	velocity = Vector3.ZERO
	Fx.burst(get_parent(), chest(), Util.role_color(role), 18, 3.0, 0.08, 0.6, false)
	if _death_tw and _death_tw.is_valid():
		_death_tw.kill()
	_death_tw = create_tween().set_parallel()
	_death_tw.tween_property(cam, "position", Vector3(0, 0.35, 0), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_death_tw.tween_property(cam, "rotation:z", 1.2, 0.6)
	_death_tw.tween_property(_rig, "rotation:x", -PI * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tw.tween_property(_rig, "position:y", 0.3, 0.5)
	if as_echo:
		_body.set_ghost(true, Util.role_color(role))


## The death plays backwards and the agent stands up where they fell.
func on_revived() -> void:
	if _death_tw and _death_tw.is_valid():
		_death_tw.kill()
	alive = true
	echo = false
	collision_layer = Util.L_PLAYER
	Fx.burst(get_parent(), chest(), Util.CYAN, 18, 3.0, 0.08, 0.6, true)
	_death_tw = create_tween().set_parallel()
	_death_tw.tween_property(cam, "position", _cam_rest, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_IN)
	_death_tw.tween_property(cam, "rotation:z", 0.0, 0.6)
	_death_tw.tween_property(_rig, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_death_tw.tween_property(_rig, "position:y", 0.0, 0.5)
	_body.set_ghost(false)
	_body.set_shadow_only(controlled)


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not controlled:
		return
	var world := Game.world as World
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_look += mm.relative
		if alive and not cinematic:
			var k := SENS * Game.sensitivity
			rotation.y -= mm.relative.x * k
			pitch = clampf(pitch - mm.relative.y * k, -1.5, 1.5)
			cam.rotation.x = pitch
		return
	if event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if (event as InputEventMouseButton).pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("release_mouse"):
		# Esc toggles the in-game menu (the HUD shows it whenever the mouse is free).
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("restart"):
		world.request_restart.rpc_id(1)
	elif not alive or world.frozen:
		return
	elif event.is_action_pressed("primary"):
		_primary(world)
	elif event.is_action_pressed("throw"):
		_throw(world)
	elif event.is_action_pressed("interact"):
		_interact(world)
	elif event.is_action_pressed("ping"):
		_ping(world)


func _ready_at(key: String) -> bool:
	return Time.get_ticks_msec() / 1000.0 >= float(cooldowns.get(key, 0.0))


func _use(key: String, cooldown: float) -> void:
	cooldowns[key] = Time.get_ticks_msec() / 1000.0 + cooldown


## 0..1 for the HUD (1 = ready).
func cooldown_frac(key: String, total: float) -> float:
	var left := float(cooldowns.get(key, 0.0)) - Time.get_ticks_msec() / 1000.0
	return clampf(1.0 - left / total, 0.0, 1.0)


func _primary(world: World) -> void:
	var rv := world.revolver
	if rv.holder == role:
		if role == Util.A:
			if rv.bullet == Revolver.IN_GUN:
				rv.request_fire.rpc_id(1, role, eye(), aim_dir())
			elif rv.bullet == Revolver.LODGED:
				world.toast("Only NOEL recalls — throw it [RMB]")
		else:
			if rv.bullet == Revolver.LODGED:
				rv.request_recall.rpc_id(1, role, eye())
			elif rv.bullet == Revolver.IN_GUN:
				world.toast("Only LEON fires — throw it [RMB]")
		return
	if world.held_prop(role) != null:
		world.request_throw_prop.rpc_id(1, role, eye(), aim_dir(), false)
		return
	if role == Util.A:
		if _ready_at("punch"):
			_use("punch", PUNCH_COOLDOWN)
			vm.anim_punch()
			world.request_punch.rpc_id(1, role, eye(), aim_dir())
	else:
		if _ready_at("pull"):
			_use("pull", PULL_COOLDOWN)
			vm.anim_pull()
			world.request_pull.rpc_id(1, role, eye(), aim_dir())
		else:
			world.toast("Recharging")


func _throw(world: World) -> void:
	if world.revolver.holder == role:
		world.revolver.request_throw.rpc_id(1, role, eye() + aim_dir() * 0.4, aim_dir())
	elif world.held_prop(role) != null:
		world.request_throw_prop.rpc_id(1, role, eye(), aim_dir(), false)


func _interact(world: World) -> void:
	if world.revolver.holder == role:
		world.toast("Hands full")
		return
	if role == Util.B and _near_echo(world):
		return  # Held: handled in _physics_process as a revive.
	var held := world.held_prop(role)
	if held != null:
		world.request_throw_prop.rpc_id(1, role, eye(), aim_dir(), true)
		return
	if role == Util.A:
		var p := world.find_prop(eye(), aim_dir(), 3.5)
		if p:
			world.request_grab.rpc_id(1, role, p.id)
		return
	# NOEL: reverse a bullet > rewind a brazier > un-throw a prop > un-break.
	var b := world.find_enemy_bullet(eye(), aim_dir(), REVERSE_RANGE)
	if b:
		if _ready_at("reverse"):
			_use("reverse", REVERSE_COOLDOWN)
			vm.anim_reverse_bullet()
			world.request_reverse.rpc_id(1, role, b.id)
		else:
			world.toast("Recharging")
		return
	var br := world.find_brazier(eye(), aim_dir())
	if br:
		vm.anim_reverse_bullet()
		world.request_relight.rpc_id(1, role, br.id)
		return
	var pr := world.find_prop(eye(), aim_dir(), UNTHROW_RANGE)
	if pr:
		vm.anim_pull()
		world.request_unthrow.rpc_id(1, role, pr.id)
		return
	var q := PhysicsRayQueryParameters3D.create(eye(), eye() + aim_dir() * UNTHROW_RANGE,
		Util.L_WORLD | Util.L_GHOST | Util.L_GLASS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider is Glass and not (hit.collider as Glass).intact and (hit.collider as Glass).restorable():
		vm.anim_pull()
		world.request_unbreak.rpc_id(1, role, (hit.collider as Glass).id)


func _ping(world: World) -> void:
	var q := PhysicsRayQueryParameters3D.create(eye(), eye() + aim_dir() * 80.0,
		Util.L_WORLD | Util.L_GLASS | Util.L_ENEMY | Util.L_PROP)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var eid: int = (hit.collider as Enemy).id if hit.collider is Enemy else -1
		world.request_ping.rpc_id(1, role, hit.position, eid)


func _near_echo(world: World) -> bool:
	var a := world.get_player(Util.A)
	return a.echo and not a.alive and global_position.distance_to(a.global_position) < REVIVE_RANGE


# --- Movement kit: slide, vault / mantle, wall-run, dash -----------------------------

## True while airborne, vaulting, sliding, dashing or wall-running (flair catches, chain bonuses).
func in_flair() -> bool:
	return movement_state != Move.WALK and movement_state != Move.CROUCH


func body_height() -> float:
	return _capsule.height


func _intent() -> Intent:
	if bot:
		return bot
	var it := Intent.new()
	if controlled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		it.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		it.sprint = Input.is_action_pressed("sprint")
		it.crouch = Input.is_action_pressed("crouch")
		it.jump = Input.is_action_pressed("jump")
		it.dash = Input.is_action_pressed("dash")
	return it


func _move(delta: float, it: Intent) -> void:
	var wish := (global_basis * Vector3(it.move.x, 0, it.move.y)).normalized()
	var jump := it.jump and not _was.jump
	var crouch := it.crouch and not _was.crouch
	var dash := it.dash and not _was.dash
	_was.jump = it.jump
	_was.crouch = it.crouch
	_was.dash = it.dash
	_move_t += delta
	if dash and movement_state != Move.VAULT and _ready_at("dash"):
		_start_dash(wish)
	match movement_state:
		Move.VAULT:
			_vault_step()
			return
		Move.DASH:
			_dash_step()
		Move.WALL_RUN:
			_wall_run_step(delta, jump)
		Move.SLIDE:
			_slide_step(delta, wish, it.crouch, jump)
		_:
			_run_step(delta, wish, it.sprint, jump, crouch)
	if movement_state == Move.VAULT:
		return
	move_and_slide()
	_settle(it.crouch)
	_lean = -WALL_LEAN * _wall_n.dot(global_basis.x) if movement_state == Move.WALL_RUN else 0.0


func _set_move(m: Move) -> void:
	if movement_state == Move.WALL_RUN:
		_last_wall = _wall_n
	movement_state = m
	_move_t = 0.0
	if m == Move.SLIDE or m == Move.CROUCH:
		_set_low(true)


func _set_low(on: bool) -> void:
	_low = on
	_capsule.height = LOW_HEIGHT if on else HEIGHT
	_collider.position.y = _capsule.height * 0.5


## After moving: walk, crouch or fall depending on the floor and headroom; stand up once there is room.
func _settle(crouch_held: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_last_wall = Vector3.ZERO
	if movement_state == Move.WALK or movement_state == Move.AIR or movement_state == Move.CROUCH:
		var want := Move.AIR
		if on_floor:
			want = Move.CROUCH if crouch_held or (_low and not _can_stand()) else Move.WALK
		if want != movement_state:
			_set_move(want)
	if _low and movement_state != Move.SLIDE and movement_state != Move.CROUCH and _can_stand():
		_set_low(false)


## Ground and air control. Speed above `speed` bleeds off at MOMENTUM_DRAG instead of snapping back.
func _steer(delta: float, wish: Vector3, speed: float) -> void:
	var on_floor := is_on_floor()
	if wish == Vector3.ZERO and not on_floor:
		return
	var hv := Util.flat(velocity)
	var target := wish * maxf(speed, hv.length() - MOMENTUM_DRAG * delta)
	hv = hv.move_toward(target, (ACCEL if on_floor else AIR_ACCEL) * delta)
	velocity.x = hv.x
	velocity.z = hv.z


func _run_step(delta: float, wish: Vector3, sprint: bool, jump: bool, crouch: bool) -> void:
	var on_floor := is_on_floor()
	if on_floor and crouch and Util.flat(velocity).length() >= SLIDE_MIN_SPEED:
		_start_slide()
		return
	if movement_state == Move.AIR and _try_wall_run():
		return
	if wish != Vector3.ZERO and movement_state != Move.CROUCH and _try_vault(wish):
		return
	var speed := SPEED
	if movement_state == Move.CROUCH:
		speed = CROUCH_SPEED
	elif sprint:
		speed = SPRINT_SPEED
	_steer(delta, wish, speed)
	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif jump and (not _low or _can_stand()):
		velocity.y = JUMP


func _start_slide() -> void:
	var hv := Util.flat(velocity)
	hv = hv.normalized() * maxf(hv.length(), SLIDE_SPEED)
	velocity.x = hv.x
	velocity.z = hv.z
	_set_move(Move.SLIDE)


func _slide_step(delta: float, wish: Vector3, crouch_held: bool, jump: bool) -> void:
	var hv := Util.flat(velocity)
	var speed := hv.length() - SLIDE_FRICTION * delta
	var dir := (hv.normalized() + wish * SLIDE_STEER * delta).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_kick()
	if jump and _can_stand():
		velocity.y = JUMP
		_set_move(Move.AIR)
	elif speed < CROUCH_SPEED or not crouch_held or not is_on_floor():
		_set_move(Move.WALK)


## A slide into an enemy kicks it; the host stuns it and knocks it back.
func _kick() -> void:
	if not _ready_at("kick"):
		return
	var world := Game.world as World
	var dir := Util.flat(velocity).normalized()
	for e in world.room.enemies:
		var to := Util.flat(e.global_position - global_position)
		if e.alive and to.length() < KICK_RANGE and to.dot(dir) > 0.0 \
				and absf(e.global_position.y - global_position.y) < 1.0:
			_use("kick", KICK_COOLDOWN)
			world.request_slide_kick.rpc_id(1, role, e.id, dir)
			return


## Input direction on the ground, view direction in the air (or with no input).
func _start_dash(wish: Vector3) -> void:
	_use("dash", DASH_COOLDOWN)
	_dash_dir = wish if wish != Vector3.ZERO and is_on_floor() else -global_basis.z
	_set_move(Move.DASH)
	Game.sfx("throw", role == Util.B, null, -8.0, 1.6)


func _dash_step() -> void:
	if _move_t >= DASH_TIME:
		velocity = _dash_dir * SPRINT_SPEED
		_set_move(Move.AIR)
	else:
		velocity = _dash_dir * DASH_SPEED


## Airborne and fast beside a wall (not the last one run on): start running along it.
func _try_wall_run() -> bool:
	var hv := Util.flat(velocity)
	if hv.length() < WALL_RUN_MIN_SPEED:
		return false
	for side: Vector3 in [global_basis.x, -global_basis.x]:
		var hit := _ray(global_position + Vector3(0, 1.0, 0), side * (RADIUS + WALL_REACH))
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) > 0.3 or n.dot(_last_wall) > 0.9 or absf(hv.normalized().dot(n)) > 0.7:
			continue
		_wall_n = n
		_set_move(Move.WALL_RUN)
		velocity.y = WALL_RUN_LIFT
		return true
	return false


func _wall_run_step(delta: float, jump: bool) -> void:
	var along := Util.flat(velocity).slide(_wall_n)
	if jump:
		velocity = along + _wall_n * WALL_JUMP_OUT
		velocity.y = JUMP
		_set_move(Move.AIR)
		return
	var hit := _ray(global_position + Vector3(0, 1.0, 0), -_wall_n * (RADIUS + WALL_REACH))
	if hit.is_empty() or is_on_floor() or _move_t > WALL_RUN_TIME or along.length() < WALL_RUN_MIN_SPEED * 0.5:
		_set_move(Move.AIR)
		return
	_wall_n = hit.normal
	along = along.normalized() * maxf(along.length(), WALL_RUN_SPEED)
	# A slight push into the wall keeps the body against it.
	velocity = along - Util.flat(_wall_n) * 0.5 + Vector3(0, velocity.y - WALL_RUN_GRAVITY * delta, 0)


## Moving into low cover or a ledge (VAULT_MIN..MANTLE_MAX high, with room on top): climb onto it.
## Momentum carries the agent on over low cover.
func _try_vault(wish: Vector3) -> bool:
	var feet := global_position
	var reach := RADIUS + VAULT_REACH
	var face := _ray(feet + Vector3(0, VAULT_MIN, 0), wish * reach)
	if face.is_empty() or (face.normal as Vector3).dot(wish) > -0.5:
		return false
	if not _ray(feet + Vector3(0, MANTLE_MAX + 0.2, 0), wish * (reach + RADIUS)).is_empty():
		return false
	var over: Vector3 = face.position + wish * (RADIUS + 0.1)
	over.y = feet.y + MANTLE_MAX + 0.1
	var top := _ray(over, Vector3.DOWN * (MANTLE_MAX + 0.1 - VAULT_MIN))
	if top.is_empty() or (top.normal as Vector3).y < 0.7 or not _fits(top.position, HEIGHT):
		return false
	_vault_from = feet
	_vault_to = top.position
	_vault_vel = wish * maxf(Util.flat(velocity).length(), SPEED)
	velocity = Vector3.ZERO
	_set_move(Move.VAULT)
	return true


## Up first, then over the lip.
func _vault_step() -> void:
	var t := minf(_move_t / VAULT_TIME, 1.0)
	var p := _vault_from.lerp(_vault_to, smoothstep(0.25, 1.0, t))
	p.y = lerpf(_vault_from.y, _vault_to.y, smoothstep(0.0, 0.6, t))
	global_position = p
	if t >= 1.0:
		velocity = _vault_vel
		_set_move(Move.WALK)


func _ray(from: Vector3, along: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + along, SOLID)
	return get_world_3d().direct_space_state.intersect_ray(q)


## Whether a capsule of this height standing at `feet` is clear of walls and bodies.
func _fits(feet: Vector3, height: float) -> bool:
	_probe.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, height * 0.5 + 0.05, 0))
	q.collision_mask = SOLID | Util.L_ENEMY | Util.L_PLAYER
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _can_stand() -> bool:
	return _fits(global_position, HEIGHT)


# --- Movement and sync -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_local():
		return
	var world := Game.world as World
	if world == null:
		return
	if alive:
		_move(delta, _intent() if not world.frozen else Intent.new())
	if global_position.y < -3.0 and alive:
		world.local_player_hit(self, Vector3.DOWN)
	if not controlled:
		return

	# NOEL holds interact over LEON's echo to un-die them.
	if role == Util.B and alive and Input.is_action_pressed("interact") and _near_echo(world) \
			and world.revolver.holder != role:
		revive_progress += delta
		if revive_progress >= REVIVE_TIME:
			revive_progress = 0.0
			world.request_revive.rpc_id(1, role)
	else:
		revive_progress = 0.0

	vm.tick(delta, Vector2(velocity.x, velocity.z).length(), _look)
	_look = Vector2.ZERO
	vm.show_prop(world.held_prop(role).kind if world.held_prop(role) != null else -1)
	vm.set_loaded(world.revolver.is_loaded())

	_send_t -= delta
	if _send_t <= 0.0 and world.room_ready and not Game.solo and Net.is_connected_peer():
		_send_t = 1.0 / SEND_RATE
		_state.rpc(global_position, velocity, rotation.y, pitch, movement_state, _lean)


@rpc("authority", "unreliable_ordered")
func _state(pos: Vector3, vel: Vector3, yaw: float, p: float, move: int, lean: float) -> void:
	_net_pos = pos
	_net_vel = vel
	_net_age = 0.0
	_net_yaw = yaw
	_net_pitch = p
	_lean = lean
	if move != movement_state:
		movement_state = move as Move
		_set_low(movement_state == Move.SLIDE or movement_state == Move.CROUCH)


func _process(delta: float) -> void:
	# Third-person pose: gun arm up and following the look pitch while holding the revolver.
	var holding := _hand_gun.visible
	var k := 1.0 - exp(-10.0 * delta)
	_body.aim = lerpf(_body.aim, 1.0 if holding and alive else 0.0, k)
	_body.aim_pitch = pitch
	_body.crouch = lerpf(_body.crouch, 1.0 if _low else 0.0, k)
	_body.rotation.z = lerpf(_body.rotation.z, _lean, k)
	if alive:
		cam.position.y = lerpf(cam.position.y, LOW_EYE if _low else _cam_rest.y, k)
		cam.rotation.z = lerpf(cam.rotation.z, _lean * 0.5, k)
	# The through-wall rim only shows when the partner is actually hidden from this PC's view.
	if not controlled and _xray and Game.world:
		var lp: Player = (Game.world as World).local_player()
		if lp and lp != self:
			_xray.visible = not (Game.world as World).has_los(lp.eye(), chest() + Vector3(0, 0.3, 0))
	if is_local():
		return
	# Extrapolate along the last known velocity so a sliding or dashing partner does not trail.
	_net_age += delta
	var at := _net_pos + _net_vel * minf(_net_age, 2.0 / SEND_RATE)
	var kn := 1.0 - exp(-18.0 * delta)
	global_position = global_position.lerp(at, kn)
	rotation.y = lerp_angle(rotation.y, _net_yaw, kn)
	pitch = lerpf(pitch, _net_pitch, kn)
	cam.rotation.x = pitch
