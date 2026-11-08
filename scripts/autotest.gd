class_name Autotest
extends Node
## Headless smoke test of a whole run: shooting, Stasis on a falling rock, wave clears,
## shop, time-power pick, boss, and level advance. Run with:
##   godot --headless -- --autotest

var main: Node
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	_check_hero_kits()
	main.screens.show_title()
	var title_buttons: Array = main.screens._root.find_children("*", "Button", true, false).map(func(b): return String(b.text).to_upper())
	check("PLAY" in title_buttons and "QUIT" in title_buttons, "title presents Play and Quit")
	main.screens.show_hero_select("pip")
	check(main.screens._root.find_children("*", "Button", true, false).size() == 6, "hero select presents four roster cards, Play and Back")
	check(main.screens._hero_abilities.get_child_count() == 3, "selected loadout lists Shift, E and Q abilities")
	for id in Heroes.ORDER:
		main.screens._select_hero(id)
		await frames(3)
		var screen: Rect2 = main.screens.get_viewport_rect()
		var info: Rect2 = main.screens._hero_info.get_global_rect()
		var roster: Rect2 = main.screens._hero_cards[Heroes.ORDER[0]].get_global_rect()
		check(info.end.y <= screen.size.y and info.end.x < roster.position.x, "%s hero details fit beside the roster" % id)
	main.screens.show_how_to_play()
	check(main.screens._root.find_children("*", "Button", true, false).size() == 1, "How to Play screen opens")
	main.screens.close()
	main.screens._select_hero("mochi")
	check(main.screens._hero_abilities.get_child_count() == 3, "loadout selection updates ability details")
	main.screens._hero_play.emit_signal("pressed")
	check(Run.hero == "mochi", "Play as starts the selected hero")
	check(main.screens._difficulty_open and main.screens._difficulty_rows.size() == 4, "difficulty picker follows hero pick")
	main.screens._difficulty_rows["extreme"].emit_signal("pressed")
	await frames(2)
	check(Run.difficulty == "extreme" and main.screens._era_open, "era select follows difficulty pick")
	main.screens.era_chosen.emit("tundra", false)
	await frames(5)
	check(Run.act == 1 and main.arena != null, "picking the first era starts the run")
	var hard_enemy := Enemy.new()
	hard_enemy.setup("scrapper", false)
	main.arena.add_child(hard_enemy)
	var hard_hp := hard_enemy.max_hp
	hard_enemy.queue_free()
	Run.difficulty = "medium"
	Run.start("pip")
	main.start_run()
	await frames(5)
	var p: Player = main.player
	check(p != null and p.is_inside_tree(), "player spawned in combat room")
	check(main.arena.kind == "combat", "first room is combat")

	# Shooting: a scrapper straight ahead takes damage from the revolver.
	var e := Enemy.new()
	e.setup("scrapper", false)
	main.arena.add_child(e)
	e.global_position = p.global_position + Vector3(0, 0, -6)
	p.rotation.y = 0.0
	p.pitch = -0.08
	p.head.rotation.x = p.pitch
	await frames(40)
	var before := e.hp
	p.gun._cd = 0.0
	p.gun.trigger()
	await frames(2)
	check(e.hp < before or e.dead, "revolver shot damages enemy (%.0f -> %.0f)" % [before, e.hp])

	# Stasis freezes a falling rock mid-air; it drops when the freeze ends.
	var f := Faller.new()
	main.arena.add_child(f)
	f.drop_at(p.global_position + Vector3(0, 0, -8))
	await frames(100)
	f.freeze(0.5)
	var y := f.global_position.y
	await frames(15)
	check(is_equal_approx(f.global_position.y, y), "frozen rock holds in the air")
	await frames(120)
	check(f.state == Faller.State.LANDED, "released rock lands")

	# Slow Field scales time inside it.
	main.player.cooldowns.field = 0.0
	check(main.player.cast_field(), "slow field cast")
	await frames(2)
	var fpos: Vector3 = get_tree().get_nodes_in_group("slow_fields")[0].global_position
	check(SlowField.scale_at(get_tree(), fpos) < 1.0, "slow field slows time inside")

	# Timed events and the room clock.
	var arena: Arena = main.arena
	check(arena.par > 0.0 and arena.par_t <= arena.par, "combat room runs a clock")
	var probe := Enemy.new()
	probe.setup("scrapper", false)
	arena.add_child(probe)
	check(hard_hp > probe.max_hp * 1.5, "Extreme enemies are much tougher (%.0f vs %.0f)" % [hard_hp, probe.max_hp])
	arena.trigger_event("surge")
	await frames(2)
	check(Run.enemy_clock > 1.0 and SlowField.scale_at(get_tree(), probe.global_position) > 1.0, "time surge speeds the Unwound")
	arena.trigger_event("frozen")
	check(probe.frozen > 0.0, "frozen second freezes enemies")
	arena._on_enemy_died(probe)
	arena._on_enemy_died(probe)
	var before_spawning := arena.spawning
	arena.trigger_event("echoes")
	check(arena.spawning > before_spawning, "echoes rewind fallen enemies back")
	for id in ["rift", "gearfall", "golden", "stillness"]:
		arena.trigger_event(id)
	await frames(2)
	check(Run.enemy_clock < 1.0 and arena.golden_t > 0.0, "stillness slows the Unwound and golden hour runs")
	arena.par_t = 0.01
	arena.event_t = 0.0
	await frames(3)
	check(arena.overtime and is_equal_approx(Run.enemy_clock, Arena.OVERTIME_CLOCK), "running out the clock starts overtime")

	# Clear the three combat rooms.
	for r in Run.COMBAT_ROOMS:
		var ok := await _clear_room()
		check(ok, "combat room %d cleared" % (r + 1))
		if r == Run.COMBAT_ROOMS - 1:
			var relic := _find_prop("relic")
			check(relic != null, "relic appears after last fight")
			var choices := Run.power_choices()
			check(choices.size() == 3, "three time powers offered")
			Run.take_power(choices[0])
		main.advance()
		await frames(30)

	check(main.arena.kind == "shop", "shop room after fights")
	Run.coins = 500
	Run.refresh_shop()
	var coins := Run.coins
	check(Run.buy(0), "can buy from shop")
	check(Run.coins < coins, "buying costs coins")
	check(Run.reroll(), "reroll works")
	main.screens.show_shop()
	await frames(2)
	main.screens.close()

	# The boss comes straight after the shop.
	main.advance()
	await frames(200)
	check(main.arena.kind == "boss", "boss room follows the shop")
	var bosses := get_tree().get_nodes_in_group("boss")
	check(bosses.size() == 1, "boss spawns in boss room")
	if bosses.size() == 1:
		await frames(240)
		bosses[0].take_hit(99999.0, false, "", bosses[0].aim_point(), Vector3.ZERO)
		await frames(5)
		check(main.arena.done, "boss room clears on boss death")
	main.advance()
	await frames(30)
	check(Run.act == 2 and Run.level == 1, "act 2 begins after boss")

	print("AUTOTEST %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check_hero_kits() -> void:
	var supported_shift := ["blink", "rewind", "slide", "flutter"]
	var supported_e := ["stasis", "field", "haste", "decay"]
	var supported_q := ["stopclock", "loop", "overclock", "collapse"]
	for id in Heroes.ORDER:
		Run.start(id)
		var d: Dictionary = Heroes.DEFS[id]
		var weapon: Dictionary = Run.current_weapon()
		var complete: bool = weapon.id == d.weapon \
			and Run.WEAPONS.has(weapon.id) \
			and Run.max_hp() == d.hp \
			and Run.max_shield() == d.shield \
			and d.shift.id in supported_shift \
			and d.e.id in supported_e \
			and d.q.id in supported_q
		check(complete, "%s kit loads %s with Shift, E and Q abilities" % [d.weapon, Run.WEAPONS[d.weapon].name])
	Run.start("pip")


func _clear_room() -> bool:
	for i in 900:
		await get_tree().physics_frame
		for en in get_tree().get_nodes_in_group("enemies"):
			en.die()
		if main.arena.done:
			return true
	return false


func _find_prop(k: String) -> Prop:
	for n in get_tree().get_nodes_in_group("interact"):
		if n.kind == k:
			return n
	return null
