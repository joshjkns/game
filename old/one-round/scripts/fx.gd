class_name Fx
## Cheap tween-driven effects. Every effect can run in reverse, which is how NOEL's
## actions look: debris gathers in, sparks fly into the impact point.

static var _shard_mesh: BoxMesh


static func _mesh() -> BoxMesh:
	if _shard_mesh == null:
		_shard_mesh = BoxMesh.new()
		_shard_mesh.size = Vector3.ONE
	return _shard_mesh


## A burst of small glowing shards. reversed = shards fly inwards and vanish at pos.
static func burst(parent: Node, pos: Vector3, color: Color, count := 12, speed := 4.0,
		size := 0.07, life := 0.5, reversed := false, spread := Vector3.ONE) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := Util.glow(color, 3.0)
	for i in count:
		var s := MeshInstance3D.new()
		s.mesh = _mesh()
		s.material_override = m
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(s)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized() * spread
		var out := pos + dir * speed * life * randf_range(0.5, 1.0)
		var sc := Vector3.ONE * size * randf_range(0.6, 1.4)
		s.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var tw := s.create_tween().set_parallel()
		if reversed:
			s.global_position = out
			s.scale = Vector3.ONE * 0.01
			tw.tween_property(s, "global_position", pos, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(s, "scale", sc, life * 0.6)
		else:
			s.global_position = pos
			s.scale = sc
			tw.tween_property(s, "global_position", out, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "scale", Vector3.ONE * 0.01, life).set_delay(life * 0.3)
		tw.chain().tween_callback(s.queue_free)


## A fading straight trail between two points.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, life := 0.5, thickness := 0.04) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var m := Util.glow(color, 3.0, 0.9)
	var t := Util.box(Vector3.ONE, m)
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(t)
	Util.place_beam(t, from, to, thickness)
	var tw := t.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.tween_callback(t.queue_free)


static func flash(parent: Node, pos: Vector3, color: Color, energy := 5.0, light_range := 6.0, life := 0.18) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(l.queue_free)


## A flat ring that expands (or contracts, if reversed) on the floor or a wall.
static func ring(parent: Node, pos: Vector3, color: Color, radius := 1.2, life := 0.4, reversed := false,
		normal := Vector3.UP) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	mi.mesh = tm
	var m := Util.glow(color, 3.0, 0.9)
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos
	if absf(normal.dot(Vector3.UP)) < 0.99:
		mi.global_basis = Basis.looking_at(normal, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	var small := Vector3(0.05, 1.0, 0.05)
	var big := Vector3(radius, 1.0, radius)
	mi.scale = big if reversed else small
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", small if reversed else big, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)
