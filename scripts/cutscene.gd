class_name Cutscene
extends Node
## Short, skippable cutscenes about time. The world is paused while they play (time stands
## still around the camera); this node runs through the pause and drives the camera and
## the HUD overlay by progress. Fire, jump, interact or Esc skips.

const INTRO_LEN := 3.6

var main: Node
## The cutscene running ("boss") or "" when none.
var playing := ""
var _t := 0.0
var _len := 1.0
var _cam: Camera3D
var _boss: Boss
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _look := Vector3.ZERO


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## The era's boss rises out of the ground while the camera looks up at it.
func boss_intro(boss: Boss) -> void:
	_boss = boss
	_begin("boss", INTRO_LEN, {"name": "BOSS", "line": "", "era": ""})
	var at := boss.global_position
	_look = at + Vector3.UP * 5.5
	_from = at + Vector3(9.0, 1.2, 15.0)
	_to = at + Vector3(3.5, 1.4, 9.5)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.far = 400.0
	_cam.cull_mask = main.player.cam.cull_mask
	boss.get_parent().add_child(_cam)
	_cam.make_current()
	main.player.view_layer.visible = false
	boss.model.position.y = -9.0
	Kit.sfx(main, "door", null, 6.0, 0.3)


## The boss falls: a few seconds of slow motion.
func boss_outro() -> void:
	main.hud.show_banner("BOSS DEFEATED", Arena.PALETTES[Run.biome()].accent)
	Engine.time_scale = 0.2
	var tw := create_tween().set_ignore_time_scale()
	tw.tween_interval(0.5)
	tw.tween_property(Engine, "time_scale", 1.0, 1.4).set_ease(Tween.EASE_IN)


func skip() -> void:
	if playing != "" and _t > 0.25:
		_t = _len


## Ends any cutscene at once, e.g. when the room is torn down.
func stop() -> void:
	Engine.time_scale = 1.0
	if playing != "":
		_end()


func _begin(kind: String, length: float, info: Dictionary) -> void:
	playing = kind
	_t = 0.0
	_len = length
	info.kind = kind
	main.hud.cine = info
	main.hud.cine_p = 0.0
	main.get_tree().paused = true


func _process(delta: float) -> void:
	if playing == "":
		return
	_t = minf(_t + delta, _len)
	var p := _t / _len
	main.hud.cine_p = p
	if playing == "boss" and is_instance_valid(_cam) and is_instance_valid(_boss):
		var k := ease(p, -1.8)
		_cam.global_position = _from.lerp(_to, k)
		_cam.look_at(_look.lerp(_boss.global_position + Vector3.UP * 4.5, k))
		var rise := clampf(p / 0.45, 0.0, 1.0)
		_boss.model.position.y = lerpf(-9.0, 0.0, ease(rise, 0.4))
		_boss.model.rotation.z = sin(p * 40.0) * 0.02 * (1.0 - rise)
	if _t >= _len:
		_end()


func _end() -> void:
	playing = ""
	main.hud.cine = {}
	main.get_tree().paused = false
	if is_instance_valid(_boss):
		_boss.model.position.y = 0.0
		_boss.model.rotation.z = 0.0
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	_boss = null
	var player: Player = main.player
	if player != null and is_instance_valid(player):
		player.cam.make_current()
		player.view_layer.visible = true
