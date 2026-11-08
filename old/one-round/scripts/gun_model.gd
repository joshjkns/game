class_name GunModel
extends Node3D
## The hero revolver, kitbashed from primitives. Points down -Z.
## Six-chamber cylinder with only one chamber lit, and a strip that shows the loaded state.

var cyl: Node3D
var muzzle: Marker3D
var _chamber_mat: StandardMaterial3D
var _strip_mat: StandardMaterial3D
## Brass base of the one round, seen at the back of its chamber when the cylinder is open.
var cartridge: Node3D


func _init() -> void:
	var metal := Util.mat(Color(0.11, 0.11, 0.13), 0.0, 1.0, 0.28, 0.9)
	var dark := Util.mat(Color(0.05, 0.05, 0.06), 0.0, 1.0, 0.5, 0.6)
	var grip_mat := Util.mat(Color(0.16, 0.07, 0.05), 0.0, 1.0, 0.6)
	_chamber_mat = Util.glow(Util.WHITE_HOT, 4.0)
	_strip_mat = Util.glow(Util.AMBER, 3.0)

	var barrel := Util.cylinder(0.034, 0.34, metal, 12)
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.035, -0.25)
	add_child(barrel)
	var rib := Util.box(Vector3(0.03, 0.025, 0.34), metal)
	rib.position = Vector3(0, 0.07, -0.25)
	add_child(rib)
	var sight := Util.box(Vector3(0.01, 0.025, 0.02), _strip_mat)
	sight.position = Vector3(0, 0.09, -0.4)
	add_child(sight)
	var frame := Util.box(Vector3(0.07, 0.12, 0.17), metal)
	frame.position = Vector3(0, 0.02, -0.01)
	add_child(frame)
	var under := Util.box(Vector3(0.05, 0.035, 0.22), dark)
	under.position = Vector3(0, -0.015, -0.2)
	add_child(under)

	cyl = Node3D.new()
	cyl.position = Vector3(0, 0.025, -0.02)
	cyl.rotation.x = PI * 0.5
	add_child(cyl)
	var drum := Util.cylinder(0.062, 0.13, dark, 6)
	cyl.add_child(drum)
	for i in 6:
		var a := TAU * i / 6.0
		var ch := Util.cylinder(0.014, 0.134, _chamber_mat if i == 0 else metal, 8)
		ch.position = Vector3(cos(a) * 0.04, 0, sin(a) * 0.04)
		cyl.add_child(ch)
	cartridge = Node3D.new()
	cartridge.position = Vector3(0.04, 0.066, 0)
	cyl.add_child(cartridge)
	var brass := Util.mat(Color(0.85, 0.6, 0.24), 0.4, 1.0, 0.22, 1.0)
	cartridge.add_child(Util.cylinder(0.017, 0.006, brass, 20))
	var primer := Util.cylinder(0.006, 0.0075, Util.mat(Color(0.95, 0.8, 0.55), 0.8, 1.0, 0.2, 1.0), 14)
	cartridge.add_child(primer)

	var grip := Util.box(Vector3(0.055, 0.17, 0.075), grip_mat)
	grip.position = Vector3(0, -0.1, 0.09)
	grip.rotation.x = -0.35
	add_child(grip)
	var hammer := Util.box(Vector3(0.02, 0.05, 0.04), metal)
	hammer.position = Vector3(0, 0.085, 0.08)
	hammer.rotation.x = 0.5
	add_child(hammer)
	var guard := Util.box(Vector3(0.015, 0.06, 0.07), metal)
	guard.position = Vector3(0, -0.07, -0.02)
	add_child(guard)
	var strip := Util.box(Vector3(0.074, 0.012, 0.2), _strip_mat)
	strip.position = Vector3(0, -0.035, -0.08)
	add_child(strip)

	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0.035, -0.43)
	add_child(muzzle)


func set_loaded(loaded: bool, color: Color) -> void:
	_chamber_mat.albedo_color = Util.WHITE_HOT * 4.0 if loaded else Color(0.15, 0.15, 0.17)
	_strip_mat.albedo_color = color * 3.0 if loaded else color * 0.6
	cartridge.visible = loaded


func cast_shadow_only(on: bool) -> void:
	for c in find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
