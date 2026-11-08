class_name TitleScene
extends Node3D
## The title backdrop: each biome's arena in turn, filmed by a slow drifting camera and
## cross-faded into the next. Hero select parks the camera on a keeper standing in the map.

signal map_shown(title: String)

const BIOMES := ["tundra", "dunes", "tomb"]
const HOLD := 9.0
const FADE := 1.8
## Where a previewed keeper stands, and the camera that frames them (menu sits on the left).
const HERO_SPOT := Vector3(1.7, 0, 14.5)
const HERO_CAM := Vector3(0, 2.1, 22.0)
const HERO_LOOK := Vector3(0.1, 1.15, 11.6)
## Where the weapon-select gun floats, in camera space (right of the menu column).
const GUN_AT := Vector3(0.62, -0.02, -1.6)
const GUN_SCALE := 1.7

var hero: Heroes
## The floating gun on weapon select, parented to the camera.
var _gun: Node3D
var cam: Camera3D
var arena: Arena
var map_title := ""
var _t := 0.0
var _shot_t := 0.0
var _index := 0
var _yaw := 0.0
var _spin := 1.0
var _look := Vector3.ZERO
var _fading := false
var _overlay: TextureRect
var _fade_tween: Tween
## Era select pins the backdrop: no auto-cycling, and hovering an era cross-fades to it.
var _hold := false
var _want := -1


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.make_current()
	# Above the menus: it holds a frame grab of the whole screen, so the menu fades into itself.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_overlay = TextureRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	layer.add_child(_overlay)
	_index = randi() % BIOMES.size()
	_show_map(BIOMES[_index])


func _show_map(biome: String) -> void:
	if arena:
		remove_child(arena)
		arena.queue_free()
	arena = Arena.new()
	add_child(arena)
	arena.build("title", biome)
	map_title = Run.biome_name(biome)
	map_shown.emit(map_title)
	_shot_t = 0.0
	_yaw = randf() * TAU
	_spin = 1.0 if randf() < 0.5 else -1.0
	if not hero:
		_place_camera(0.0, true)


func _process(delta: float) -> void:
	_t += delta
	# Weapon select holds the whole shot still: no orbit, no map changes, no mouse drift.
	if _gun:
		return
	if hero:
		_place_camera(delta, false)
		return
	_shot_t += delta
	_yaw += _spin * 0.035 * delta
	if _shot_t > HOLD and not _fading and not _hold:
		_next_map()
	_place_camera(delta, false)


func _place_camera(delta: float, snap: bool) -> void:
	var vp := get_viewport()
	var m := Vector2(0.5, 0.5)
	if vp:
		m = vp.get_mouse_position() / Vector2(vp.get_visible_rect().size)
	var off := Vector3((m.x - 0.5) * 0.35, (0.5 - m.y) * 0.2, 0)
	var pos: Vector3
	var look: Vector3
	if hero:
		pos = HERO_CAM + off + Vector3(sin(_t * 0.3) * 0.05, sin(_t * 0.4) * 0.04, 0)
		look = HERO_LOOK + off * 0.3
	else:
		# A slow orbit with a gentle push-in over the shot.
		var push := clampf(_shot_t / HOLD, 0.0, 1.2)
		var r := 21.0 - push * 3.0
		pos = Vector3(sin(_yaw) * r, 6.5 - push * 0.8, cos(_yaw) * r) + Basis(Vector3.UP, _yaw) * off * 2.0
		look = Vector3(0, 2.4, 0)
	if snap:
		cam.position = pos
		_look = look
	else:
		var k := 1.0 - exp(-2.5 * delta)
		cam.position = cam.position.lerp(pos, k)
		_look = _look.lerp(look, k)
	cam.look_at(_look)


## Freeze the current frame over everything, swap the map underneath, then dissolve the freeze.
func _next_map(target := -1, fade := FADE) -> void:
	_fading = true
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or hero or _gun:
		_fading = false
		return
	var img := get_viewport().get_texture().get_image()
	_overlay.texture = ImageTexture.create_from_image(img)
	_overlay.modulate.a = 1.0
	_overlay.visible = true
	_index = target if target >= 0 else (_index + 1) % BIOMES.size()
	_show_map(BIOMES[_index])
	_fade_tween = create_tween()
	_fade_tween.tween_interval(0.05 if target >= 0 else 0.1)
	_fade_tween.tween_property(_overlay, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_callback(_end_fade)


func _end_fade() -> void:
	_fading = false
	_overlay.visible = false
	_overlay.texture = null
	if _want >= 0 and _want != _index and not hero:
		_next_map(_want, 0.45)


## Era select: hold on one biome, cross-fading to it if another is showing.
func show_biome(biome: String) -> void:
	_hold = true
	_want = BIOMES.find(biome)
	if _want >= 0 and _want != _index and not _fading and not hero:
		_next_map(_want, 0.45)


func release_hold() -> void:
	_hold = false
	_want = -1
	_shot_t = 0.0


## Weapon select: the loadout's gun hangs still on the right of the frame, side on,
## while the camera holds its shot.
func set_weapon(id: String) -> void:
	clear_weapon()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
		_end_fade()
	_gun = Node3D.new()
	_gun.position = GUN_AT
	_gun.rotation = Vector3(0.04, -PI * 0.5 + 0.35, 0.0)
	_gun.scale = Vector3.ONE * GUN_SCALE
	cam.add_child(_gun)
	var model := Gun.build_model({"id": id, "tier": 0, "element": ""})
	model.position.z = 0.2
	_gun.add_child(model)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-0.3, 0.6, 0.7)
	lamp.omni_range = 3.0
	lamp.light_energy = 1.4
	lamp.light_volumetric_fog_energy = 0.0
	lamp.light_bake_mode = Light3D.BAKE_DISABLED
	_gun.add_child(lamp)


func clear_weapon() -> void:
	if _gun:
		_gun.queue_free()
		_gun = null
		_shot_t = 0.0
