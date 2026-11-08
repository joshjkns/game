class_name Level
extends Node3D
## Builds one greybox room from an ASCII map (see Levels) and tracks its win state.

signal completed

var data: Dictionary
var players: Array[Player] = []
var enemies: Array[Enemy] = []
var gun: Gun
var center := Vector3.ZERO
var size := Vector2.ZERO

var _door: StaticBody3D
var _door_open := false
var _exit_z := 0.0
var _done := false

var _wall_mat := Util.mat(Color(0.55, 0.57, 0.62))
var _floor_mat := Util.mat(Color(0.22, 0.23, 0.26))
var _glass_mat := Util.mat(Color(0.5, 0.85, 1.0), 0.3, 0.3)
var _door_mat := Util.mat(Color(0.9, 0.25, 0.3), 0.5)


func _ready() -> void:
	var rows: Array = data.map
	var h := rows.size()
	var w := 0
	for r: String in rows:
		w = maxi(w, r.length())
	var t := Util.TILE
	center = Vector3((w - 1) * t * 0.5, 0, (h - 1) * t * 0.5)
	size = Vector2(w * t, h * t)

	# Floor covers the room plus the exit alcove below it.
	var fl := Util.solid(Vector3(w * t, 0.2, (h + 3) * t), _floor_mat, Util.LAYER_WORLD)
	fl.position = Vector3(center.x, -0.1, (h + 1) * t * 0.5)
	add_child(fl)

	var starts := {}
	for r in h:
		var row: String = rows[r]
		for c in row.length():
			var ch := row[c]
			var p := Vector3(c * t, 0, r * t)
			match ch:
				"#":
					_wall(p)
				"w":
					var g := Util.solid(Vector3(t, Util.WALL_H, 0.3), _glass_mat, Util.LAYER_GLASS)
					g.position = p + Vector3(0, Util.WALL_H * 0.5, 0)
					add_child(g)
				"D":
					_build_exit(c, r)
				"E":
					_enemy(p, false, Vector3.BACK)
				"^":
					_enemy(p, true, Vector3.FORWARD)
				"v":
					_enemy(p, true, Vector3.BACK)
				"<":
					_enemy(p, true, Vector3.LEFT)
				">":
					_enemy(p, true, Vector3.RIGHT)
				"A", "B", "G":
					starts[ch] = p

	gun = Gun.new()
	gun.level = self
	gun.position = starts.G
	add_child(gun)

	for role in [Player.Role.FORWARD, Player.Role.INVERTED]:
		var pl := Player.new()
		pl.role = role
		pl.gun = gun
		pl.position = (starts.A if role == Player.Role.FORWARD else starts.B) + Vector3(0, 0.05, 0)
		add_child(pl)
		players.append(pl)


func _wall(p: Vector3) -> void:
	var wall := Util.solid(Vector3(Util.TILE, Util.WALL_H, Util.TILE), _wall_mat, Util.LAYER_WORLD)
	wall.position = p + Vector3(0, Util.WALL_H * 0.5, 0)
	add_child(wall)


func _enemy(p: Vector3, shielded: bool, facing: Vector3) -> void:
	var e := Enemy.new()
	e.shielded = shielded
	e.facing = facing
	e.position = p
	add_child(e)
	enemies.append(e)


func _build_exit(c: int, r: int) -> void:
	var t := Util.TILE
	_door = Util.solid(Vector3(t, Util.WALL_H, t * 0.4), _door_mat, Util.LAYER_WORLD)
	_door.position = Vector3(c * t, Util.WALL_H * 0.5, r * t)
	add_child(_door)
	# Alcove behind the door: interior is columns c-1..c+1, rows r+1..r+2.
	for dr in [1, 2]:
		_wall(Vector3((c - 2) * t, 0, (r + dr) * t))
		_wall(Vector3((c + 2) * t, 0, (r + dr) * t))
	for dc in range(-2, 3):
		_wall(Vector3((c + dc) * t, 0, (r + 3) * t))
	_exit_z = r * t + t * 0.5
	var marker := Util.box(Vector3(t * 3, 0.02, t * 2), Util.unshaded(Color(0.3, 1.0, 0.5), 0.25))
	marker.position = Vector3(c * t, 0.02, (r + 1.5) * t)
	add_child(marker)


func enemies_left() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func _process(_delta: float) -> void:
	if not _door_open and enemies_left() == 0:
		_door_open = true
		_door.get_child(0).set_deferred("disabled", true)
		create_tween().tween_property(_door, "position:y", -Util.WALL_H * 0.5, 0.6)
	if _door_open and not _done:
		for p in players:
			if p.global_position.z < _exit_z:
				return
		_done = true
		for p in players:
			p.frozen = true
		completed.emit()


func is_door_open() -> bool:
	return _door_open
