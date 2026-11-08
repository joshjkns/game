class_name Icons
extends Control
## Vector ability icons drawn in code, so every ability has a readable glyph without image
## assets. Use Icons.paint() from any _draw(), or add an Icons control to show one.

var icon := "stasis"
var color := Color.WHITE


func _draw() -> void:
	if icon.begins_with("weapon_"):
		paint_weapon(self, icon, size * 0.5, minf(size.x * 0.25, size.y * 0.5), Color(1, 1, 1, color.a))
	else:
		paint(self, icon, size * 0.5, minf(size.x, size.y) * 0.42, color)


static func _arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, w: float) -> void:
	ci.draw_line(from, to, col, w, true)
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([to + d * w * 1.2, to - d * w * 1.6 + n * w * 1.5, to - d * w * 1.6 - n * w * 1.5]), col)


## Weapon icon ids carry the variant so the rendered gun matches tier and element.
static func for_weapon(id: String, tier := 0, element := "") -> String:
	return "weapon_%s|%d|%s" % [id, tier, element]


static func for_item(id: String) -> String:
	return Run.item_icon(id)


static func for_power(id: String) -> String:
	return {
		"echo": "rewind", "secondwind": "rewind", "shatter": "stasis", "longstasis": "stasis",
		"heavyfield": "field", "deeploop": "loop", "runaway": "haste", "rot": "decay",
		"haste": "overclock", "gravity": "collapse", "stopwatch": "stopclock", "refill": "reload",
		"heart": "heart", "afterimage": "blink", "charged": "overclock", "borrowed": "shield",
	}.get(id, "hourglass")


const INK := Color("0b1214")
static var _guns := {}


## A gun rendered from its real model (side view, transparent), cached per variant.
## Each variant keeps a tiny SubViewport that renders once.
static func weapon_texture(id: String, tier := 0, element := "") -> Texture2D:
	var key := "%s|%d|%s" % [id, tier, element]
	if _guns.has(key):
		return _guns[key]
	var tree := Engine.get_main_loop() as SceneTree
	var sv := SubViewport.new()
	sv.size = Vector2i(320, 160)
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	tree.root.add_child.call_deferred(sv)
	var pivot := Node3D.new()
	sv.add_child(pivot)
	var model := Gun.build_model({"id": id, "tier": tier, "element": element})
	model.rotation = Vector3(0.12, -0.32, 0.0)
	pivot.add_child(model)
	var box := AABB()
	var first := true
	for mi in model.get_children():
		if mi is MeshInstance3D:
			var part_box: AABB = model.transform * (mi.transform * mi.get_aabb())
			box = part_box if first else box.merge(part_box)
			first = false
	model.position = -box.get_center()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.y, maxf(box.size.z, box.size.x) * 0.5) * 1.18
	cam.position = Vector3(2.0, 0, 0)
	cam.rotation.y = PI * 0.5
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.78, 0.86)
	env.ambient_light_energy = 0.8
	cam.environment = env
	sv.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 1.1, 0)
	sun.light_energy = 1.3
	sv.add_child(sun)
	_guns[key] = sv.get_texture()
	return _guns[key]


## Draws a weapon icon id (from for_weapon) into the box centred on c, 2:1, r = half height.
static func paint_weapon(ci: CanvasItem, id: String, c: Vector2, r: float, tint := Color.WHITE) -> void:
	var parts := id.trim_prefix("weapon_").split("|")
	var tex := weapon_texture(parts[0], int(parts[1]) if parts.size() > 1 else 0, parts[2] if parts.size() > 2 else "")
	ci.draw_texture_rect(tex, Rect2(c - Vector2(r * 2.0, r), Vector2(r * 4.0, r * 2.0)), false, tint)


## Draws a glyph with a dark ink rim so it reads on any background.
static func paint(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color) -> void:
	if id.begins_with("weapon_"):
		paint_weapon(ci, id, c, r * 0.62, Color(1, 1, 1, col.a))
		return
	var w := maxf(2.0, r * 0.14)
	var ink := Color(INK, col.a * 0.9)
	var o := maxf(1.5, r * 0.11)
	for d in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o)]:
		_glyph(ci, id, c + d, r, ink, w + o)
	_glyph(ci, id, c, r, col, w)


static func _glyph(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color, w: float) -> void:
	match id:
		"blink":
			for i in 3:
				ci.draw_line(c + Vector2(-r + i * r * 0.35, -r * 0.5 + i * r * 0.5), c + Vector2(-r * 0.6 + i * r * 0.35, -r * 0.5 + i * r * 0.5), Color(col, 0.5), w)
			_arrow(ci, c + Vector2(-r * 0.2, 0), c + Vector2(r * 0.7, 0), col, w * 1.3)
		"stasis":
			for i in 3:
				var a := PI * i / 3.0
				var d := Vector2(cos(a), sin(a)) * r
				ci.draw_line(c - d, c + d, col, w, true)
				for s in [-1.0, 1.0]:
					ci.draw_line(c + d * 0.6 * s, c + d * 0.6 * s + d.rotated(0.8 * s) * 0.25, col, w * 0.7, true)
		"stopclock":
			ci.draw_arc(c, r * 0.85, 0, TAU, 32, col, w, true)
			ci.draw_line(c, c + Vector2(0, -r * 0.6), col, w, true)
			ci.draw_line(c, c + Vector2(r * 0.45, 0), col, w, true)
			ci.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color(1, 0.4, 0.4, col.a), w * 0.8, true)
		"rewind":
			ci.draw_arc(c, r * 0.7, -PI * 0.2, PI * 1.4, 28, col, w, true)
			var tip := c + Vector2(cos(-PI * 0.2), sin(-PI * 0.2)) * r * 0.7
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.35, -r * 0.1), tip + Vector2(r * 0.15, -r * 0.4), tip + Vector2(r * 0.2, r * 0.15)]), col)
		"field":
			ci.draw_arc(c, r * 0.85, 0, TAU, 32, col, w, true)
			ci.draw_arc(c, r * 0.45, 0, TAU, 24, Color(col, 0.6), w * 0.7, true)
			ci.draw_circle(c + Vector2(r * 0.3, -r * 0.35), r * 0.12, col)
		"loop":
			for s in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(r * 0.42 * s, 0), r * 0.42, 0, TAU, 24, col, w, true)
		"slide":
			for i in 3:
				var x := -r * 0.6 + i * r * 0.5
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, -r * 0.5), c + Vector2(x + r * 0.35, 0), c + Vector2(x, r * 0.5)]), Color(col, 0.4 + i * 0.3), w, true)
		"haste":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, -r), c + Vector2(-r * 0.5, r * 0.15), c + Vector2(-r * 0.02, r * 0.1),
				c + Vector2(-r * 0.2, r), c + Vector2(r * 0.5, -r * 0.15), c + Vector2(r * 0.02, -r * 0.1)]), col)
		"overclock":
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.55, c + Vector2(cos(a), sin(a)) * r * 0.95, col, w * 1.6)
			ci.draw_arc(c, r * 0.55, 0, TAU, 24, col, w * 1.4, true)
			ci.draw_circle(c, r * 0.2, col)
		"flutter":
			for s in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(r * 0.9 * s, -r * 0.8), c + Vector2(r * s, r * 0.1), c + Vector2(r * 0.4 * s, r * 0.6)]), Color(col, 0.85))
		"decay":
			ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.6, col)
			ci.draw_circle(c + Vector2(-r * 0.22, 0), r * 0.15, Color(0.1, 0.06, 0.12))
			ci.draw_circle(c + Vector2(r * 0.22, 0), r * 0.15, Color(0.1, 0.06, 0.12))
			for i in 3:
				ci.draw_line(c + Vector2(-r * 0.3 + i * r * 0.3, r * 0.5), c + Vector2(-r * 0.3 + i * r * 0.3, r * 0.95), col, w)
		"collapse":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.2), c + Vector2(-r * 0.2, -r * 0.8), c + Vector2(r * 0.5, -r * 0.6),
				c + Vector2(r * 0.7, 0.0), c + Vector2(r * 0.1, r * 0.35), c + Vector2(-r * 0.5, r * 0.25)]), col)
			for i in 3:
				ci.draw_line(c + Vector2(-r * 0.5 + i * r * 0.5, r * 0.5), c + Vector2(-r * 0.5 + i * r * 0.5, r * 0.95), Color(col, 0.6), w)
		"coin":
			if col.v < 0.2:
				ci.draw_circle(c, r, col)
				return
			ci.draw_circle(c, r, Color("ffc93a", col.a))
			ci.draw_circle(c, r * 0.6, Color("c2781a", col.a))
			ci.draw_circle(c, r * 0.3, Color("ffc93a", col.a))
		"skull":
			ci.draw_circle(c + Vector2(0, -r * 0.1), r * 0.75, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.4, r * 0.3), Vector2(r * 0.8, r * 0.5)), col)
			ci.draw_circle(c + Vector2(-r * 0.28, -r * 0.1), r * 0.2, Color(0.1, 0.06, 0.12))
			ci.draw_circle(c + Vector2(r * 0.28, -r * 0.1), r * 0.2, Color(0.1, 0.06, 0.12))
		"hourglass":
			# Two glass bulbs meeting at the waist, capped top and bottom, sand in the lower bulb.
			var x := r * 0.55
			ci.draw_polyline(PackedVector2Array([c + Vector2(-x, -r * 0.82), c + Vector2(x, -r * 0.82), c + Vector2(r * 0.08, 0),
				c + Vector2(x, r * 0.82), c + Vector2(-x, r * 0.82), c + Vector2(-r * 0.08, 0), c + Vector2(-x, -r * 0.82)]), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.75, -r), c + Vector2(r * 0.75, -r), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.75, r), c + Vector2(r * 0.75, r), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-x * 0.7, r * 0.78), c + Vector2(x * 0.7, r * 0.78), c + Vector2(0, r * 0.3)]), col)
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.62, c + Vector2(cos(a), sin(a)) * r, col, w * 1.5, true)
			ci.draw_arc(c, r * 0.62, 0, TAU, 24, col, w, true)
			ci.draw_circle(c, r * 0.22, col)
		"heart":
			var pts := PackedVector2Array([c + Vector2(0, r * 0.86), c + Vector2(-r * 0.9, -r * 0.05), c + Vector2(-r * 0.78, -r * 0.58), c + Vector2(-r * 0.35, -r * 0.68), c, c + Vector2(r * 0.35, -r * 0.68), c + Vector2(r * 0.78, -r * 0.58), c + Vector2(r * 0.9, -r * 0.05)])
			ci.draw_colored_polygon(pts, col)
		"shield":
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.6), c + Vector2(r * 0.62, r * 0.35), c, c + Vector2(-r * 0.62, r * 0.35), c + Vector2(-r * 0.8, -r * 0.6)])
			ci.draw_colored_polygon(pts, Color(col, 0.22))
			ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], pts[0]]), col, w, true)
		"eye":
			ci.draw_arc(c, r * 0.7, PI, TAU, 20, col, w, true)
			ci.draw_arc(c, r * 0.7, 0, PI, 20, col, w, true)
			ci.draw_circle(c, r * 0.25, col)
		"hammer":
			ci.draw_line(c + Vector2(-r * 0.1, r * 0.75), c + Vector2(r * 0.18, -r * 0.42), col, w * 1.7, true)
			ci.draw_line(c + Vector2(-r * 0.72, -r * 0.42), c + Vector2(r * 0.65, -r * 0.42), col, w * 1.7, true)
			ci.draw_line(c + Vector2(-r * 0.65, -r * 0.42), c + Vector2(-r * 0.65, -r * 0.05), col, w * 1.7, true)
			ci.draw_line(c + Vector2(r * 0.55, -r * 0.42), c + Vector2(r * 0.55, -r * 0.05), col, w * 1.7, true)
		"boot":
			var pts := PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.7), c + Vector2(r * 0.1, -r * 0.7), c + Vector2(r * 0.18, r * 0.1), c + Vector2(r * 0.75, r * 0.38), c + Vector2(r * 0.68, r * 0.7), c + Vector2(-r * 0.65, r * 0.7), c + Vector2(-r * 0.68, r * 0.42), c + Vector2(-r * 0.35, r * 0.2)])
			ci.draw_colored_polygon(pts, col)
		"flame":
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.28, -r * 0.25), c + Vector2(r * 0.67, -r * 0.48), c + Vector2(r * 0.54, r * 0.22), c + Vector2(0, r), c + Vector2(-r * 0.55, r * 0.3), c + Vector2(-r * 0.58, -r * 0.1), c + Vector2(-r * 0.18, r * 0.05)])
			ci.draw_colored_polygon(pts, col)
		"reload":
			ci.draw_arc(c, r * 0.65, -PI * 0.1, PI * 1.6, 24, col, w * 1.5, true)
			_arrow(ci, c + Vector2(-r * 0.2, -r * 0.72), c + Vector2(r * 0.35, -r * 0.65), col, w * 1.4)
		"spring":
			var pts := PackedVector2Array()
			for i in 41:
				var t := float(i) / 40.0
				pts.append(c + Vector2(cos(t * TAU * 3.0) * r * 0.55, -r * 0.85 + t * r * 1.7 + sin(t * TAU * 3.0) * r * 0.12))
			ci.draw_polyline(pts, col, w, true)
		"bullet":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.32, r * 0.9), c + Vector2(-r * 0.32, -r * 0.2), c + Vector2(-r * 0.2, -r * 0.65),
				c + Vector2(0, -r * 0.95), c + Vector2(r * 0.2, -r * 0.65), c + Vector2(r * 0.32, -r * 0.2), c + Vector2(r * 0.32, r * 0.9)]), col)
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.35), c + Vector2(r * 0.4, r * 0.35), Color(INK, col.a), w * 0.6)
		"potion":
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.62, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.85), Vector2(r * 0.4, r * 0.75)), col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.32, -r * 0.98), Vector2(r * 0.64, r * 0.22)), col)
			ci.draw_circle(c + Vector2(-r * 0.2, r * 0.15), r * 0.14, Color(1, 1, 1, col.a * 0.7) if col.v > 0.2 else col)
		"feather":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.9), c + Vector2(r * 0.35, r * 0.15), c + Vector2(-r * 0.45, r * 0.6),
				c + Vector2(-r * 0.3, -r * 0.1)]), col)
			ci.draw_line(c + Vector2(-r * 0.8, r * 0.95), c + Vector2(r * 0.55, -r * 0.6), Color(INK, col.a) if col.v > 0.2 else col, w * 0.7, true)
		"cracked":
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.62, c + Vector2(cos(a), sin(a)) * r, col, w * 1.5, true)
			ci.draw_arc(c, r * 0.62, 0, TAU, 24, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.6), c + Vector2(r * 0.1, -r * 0.15), c + Vector2(-r * 0.1, r * 0.15), c + Vector2(r * 0.15, r * 0.6)]), Color(1, 0.45, 0.4, col.a) if col.v > 0.2 else col, w, true)
		_:
			ci.draw_circle(c, r * 0.5, col)
