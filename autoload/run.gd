extends Node
## Run state: everything that survives between rooms and levels, plus the content tables
## (weapons, shop items, time powers). Reset by start().

signal changed

const ACTS := 3
const LEVELS_PER_ACT := 1
## Difficulty steps per act, so scaling keeps its old curve with one level per act.
const DEPTH_PER_ACT := 2
const COMBAT_ROOMS := 2

const TIER_COLORS := [Color("d8dde6"), Color("55c9a0"), Color("4fa3ff"), Color("ffb02e")]
const TIER_NAMES := ["Common", "Uncommon", "Rare", "Legendary"]
const TIME_COLOR := Color("83d4c2")
const ELEMENTS := {
	"": {"name": "", "color": Color("ffd27a")},
	"fire": {"name": "Fire", "color": Color("ff6a2b")},
	"shock": {"name": "Shock", "color": Color("6fd8ff")},
	"rust": {"name": "Rust", "color": Color("8cff4a")},
}

## Named stat families share a colour and icon across the shop, HUD, and stat sheet.
const STAT_DEFS := {
	"dmg": {"name": "Damage", "group": "Offence", "icon": "bullet", "color": Color("ff806b"), "format": "percent"},
	"rate": {"name": "Fire rate", "group": "Offence", "icon": "overclock", "color": Color("ffd166"), "format": "percent"},
	"reload": {"name": "Reload speed", "group": "Offence", "icon": "reload", "color": Color("72d4c4"), "format": "percent"},
	"shield": {"name": "Max shield", "group": "Survival", "icon": "shield", "color": Color("70c9e8"), "format": "flat"},
	"hp": {"name": "Max health", "group": "Survival", "icon": "heart", "color": Color("ff7886"), "format": "flat"},
	"crit": {"name": "Crit chance", "group": "Offence", "icon": "eye", "color": Color("c3dc69"), "format": "percent"},
	"critdmg": {"name": "Crit damage", "group": "Offence", "icon": "hammer", "color": Color("ff9d59"), "format": "percent"},
	"speed": {"name": "Move speed", "group": "Mobility", "icon": "boot", "color": Color("8cdb82"), "format": "percent"},
	"cdr": {"name": "Ability cooldown", "group": "Utility", "icon": "stopclock", "color": Color("78bbd5"), "format": "percent", "inverse": true},
	"coins": {"name": "Coin drops", "group": "Utility", "icon": "coin", "color": Color("ffe08b"), "format": "percent"},
	"elem": {"name": "Element chance", "group": "Offence", "icon": "flame", "color": Color("ff985f"), "format": "percent"},
}

## Guns. rate = shots per second; spread in degrees; kind = hitscan | shell | beam.
const WEAPONS := {
	"tick": {"name": "Revolver", "dmg": 26.0, "rate": 3.6, "mag": 8, "reload": 1.1,
		"spread": 0.4, "pellets": 1, "auto": false, "kind": "hitscan", "kick": 0.09, "price": 0},
	"chatter": {"name": "SMG", "dmg": 9.0, "rate": 12.0, "mag": 40, "reload": 1.5,
		"spread": 2.4, "pellets": 1, "auto": true, "kind": "hitscan", "kick": 0.025, "price": 22},
	"bellow": {"name": "Shotgun", "dmg": 10.0, "rate": 1.3, "mag": 6, "reload": 1.7,
		"spread": 6.5, "pellets": 9, "auto": false, "kind": "hitscan", "kick": 0.22, "price": 24},
	"mortar": {"name": "Grenade Launcher", "dmg": 75.0, "rate": 1.1, "mag": 4, "reload": 1.9,
		"spread": 0.0, "pellets": 1, "auto": false, "kind": "shell", "kick": 0.2, "price": 30,
		"splash": 3.6, "speed": 34.0},
	"lancet": {"name": "Laser Rifle", "dmg": 14.0, "rate": 14.0, "mag": 70, "reload": 2.0,
		"spread": 0.0, "pellets": 1, "auto": true, "kind": "beam", "kick": 0.006, "price": 28},
	"pike": {"name": "Sniper Rifle", "dmg": 95.0, "rate": 0.95, "mag": 5, "reload": 1.8,
		"spread": 0.0, "pellets": 1, "auto": false, "kind": "hitscan", "kick": 0.25, "price": 30,
		"pierce": 3},
}

## Stackable stat items. Effects are shown as short, coloured stat lines in the shop.
const ITEMS := {
	"mainspring": {"name": "Mainspring", "price": 14, "icon": "spring", "stats": {"dmg": 0.12}},
	"escapement": {"name": "Escapement", "price": 14, "icon": "overclock", "stats": {"rate": 0.12}},
	"quickhands": {"name": "Second Hand", "price": 10, "icon": "reload", "stats": {"reload": 0.25}},
	"plating": {"name": "Time Capsule", "price": 12, "icon": "shield", "stats": {"shield": 25.0}},
	"heartwood": {"name": "Tree Rings", "price": 12, "icon": "heart", "stats": {"hp": 20.0}},
	"loupe": {"name": "Astrolabe", "price": 12, "icon": "eye", "stats": {"crit": 0.06}},
	"hammer": {"name": "Midnight Chime", "price": 12, "icon": "hammer", "stats": {"critdmg": 0.3}},
	"boots": {"name": "Leap Year Boots", "price": 10, "icon": "boot", "stats": {"speed": 0.08}},
	"watch": {"name": "Pocket Watch", "price": 14, "icon": "stopclock", "stats": {"cdr": 0.12}},
	"gilt": {"name": "Compound Interest", "price": 10, "icon": "coin", "stats": {"coins": 0.2}},
	"fuse": {"name": "Half-Life", "price": 12, "icon": "flame", "stats": {"elem": 0.12}},
	"tonic": {"name": "Rewind Tonic", "price": 8, "icon": "potion", "heal": 60.0},
	"featherweight": {"name": "Fast Forward", "price": 12, "icon": "feather", "stats": {"speed": 0.16, "dmg": -0.08}},
	"hard": {"name": "Overwound Spring", "price": 14, "icon": "cracked", "stats": {"rate": 0.2, "dmg": -0.1}},
}

## Difficulty, picked after the hero. Multipliers on enemy health, damage, numbers and
## speed; `events` scales how often timed room events fire, `par` the room clock, and
## `elite` adds to the elite chance. Coins pay a little more on harder clocks.
const DIFFICULTIES := {
	"easy": {"name": "Easy", "color": Color("8cdb82"), "hp": 0.75, "dmg": 0.6,
		"count": 0.8, "speed": 0.92, "events": 0.7, "par": 1.35, "elite": 0.0, "coins": 1.0},
	"medium": {"name": "Medium", "color": Color("ffe08b"), "hp": 1.0, "dmg": 1.0,
		"count": 1.0, "speed": 1.0, "events": 1.0, "par": 1.0, "elite": 0.0, "coins": 1.0},
	"hard": {"name": "Hard", "color": Color("ff9d59"), "hp": 1.35, "dmg": 1.35,
		"count": 1.3, "speed": 1.1, "events": 1.35, "par": 0.85, "elite": 0.05, "coins": 1.15},
	"extreme": {"name": "Extreme", "color": Color("ff5a5e"), "hp": 1.8, "dmg": 1.7,
		"count": 1.6, "speed": 1.2, "events": 1.7, "par": 0.7, "elite": 0.12, "coins": 1.3},
}
const DIFFICULTY_ORDER := ["easy", "medium", "hard", "extreme"]

## Each act drops you into a different time. One stamp per level: the year, then a few words.
const ERAS := {
	"tundra": {"name": "Ice Age", "stamps": [
		{"year": -20000, "text": "Ice sheets a mile thick"},
		{"year": -12000, "text": "The great thaw begins"}]},
	"dunes": {"name": "Ancient Egypt", "stamps": [
		{"year": -2560, "text": "The Great Pyramid is brand new"},
		{"year": -1323, "text": "A boy king is laid to rest"}]},
	"tomb": {"name": "The Far Future", "stamps": [
		{"year": 802701, "text": "The cities are long gone"},
		{"year": 30000000, "text": "The sun is going out"}]},
}

## Time powers: free pick of 1 from 3 after every fight.
const POWERS := {
	"echo": {"name": "Echo Rounds", "text": "Every 5th shot repeats itself a moment later."},
	"secondwind": {"name": "Second Wind", "text": "Once per level, lethal damage rewinds you 3 seconds instead."},
	"shatter": {"name": "Shatter", "text": "Frozen enemies explode on death, freezing those nearby.", "hero": "pip"},
	"longstasis": {"name": "Long Stasis", "text": "Stasis lasts 3s longer and catches everything near the target.", "hero": "pip"},
	"heavyfield": {"name": "Heavy Field", "text": "Slow Field is 40% bigger and burns 15 damage/s.", "hero": "mochi"},
	"deeploop": {"name": "Deep Loop", "text": "Rewind also reloads and resets Slow Field.", "hero": "mochi"},
	"runaway": {"name": "Runaway Clock", "text": "Haste lasts 3s longer. Slide has 2 charges' worth of speed.", "hero": "nib"},
	"rot": {"name": "Spreading Rot", "text": "Enemies that die while decaying spread Decay to those nearby.", "hero": "dusk"},
	"haste": {"name": "Haste", "text": "Kills give +30% move and fire rate for 3s."},
	"gravity": {"name": "Gravity Debt", "text": "Released frozen rocks fall 3x faster and deal 3x damage.", "hero": "pip"},
	"stopwatch": {"name": "Stopwatch", "text": "First shot after 1.5s without firing deals +120%."},
	"refill": {"name": "Rewound Magazine", "text": "Emptying a magazine has a 35% chance to refill it."},
	"heart": {"name": "Hourglass Heart", "text": "+40 max health. Regenerate 2 health/s."},
	"afterimage": {"name": "Afterimage", "text": "Your Shift move leaves a decoy that enemies chase for 2s."},
	"charged": {"name": "Wound Spring", "text": "Ultimate charges 40% faster."},
	"borrowed": {"name": "Borrowed Time", "text": "+35% damage while your shield is broken."},
}

var hero := "pip"
var difficulty := "medium"
## Global clock for the Unwound: room events and overtime speed enemies, their shots and
## falling rocks up. Arena sets it every frame during a fight.
var enemy_clock := 1.0
## Ultimate charge, 0..100.
var ult := 0.0
## Seconds left on the ultimate just used; no charge is earned until it runs out.
var ult_lock := 0.0
var act := 1
var level := 1
var room := 0
var coins := 0
var hp := 100.0
var shield := 50.0
var weapons: Array = []
var held := 0
var items := {}
var powers := {}
var kills := 0
var second_wind_used := false
var shop_offers: Array = []
var shop_locked: Array = [false, false, false, false]
var rerolls := 0


func _init() -> void:
	_bind("move_forward", [KEY_W]); _bind("move_back", [KEY_S])
	_bind("move_left", [KEY_A]); _bind("move_right", [KEY_D])
	_bind("jump", [KEY_SPACE]); _bind("mobility", [KEY_SHIFT])
	_bind("reload", [KEY_R]); _bind("interact", [KEY_F])
	_bind("skill", [KEY_E]); _bind("ult", [KEY_Q])
	_bind("weapon_1", [KEY_1]); _bind("weapon_2", [KEY_2]); _bind("stats", [KEY_TAB]); _bind("pause", [KEY_ESCAPE])
	_bind_mouse("fire", MOUSE_BUTTON_LEFT); _bind_mouse("aim", MOUSE_BUTTON_RIGHT)


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func start(hero_id := "pip") -> void:
	hero = hero_id
	# Start part-charged so the ultimate (and its tip) shows up within the first fight.
	ult = 60.0
	ult_lock = 0.0
	enemy_clock = 1.0
	act = 1; level = 1; room = 0; coins = 0; kills = 0
	items = {}; powers = {}
	weapons = [make_weapon(hero_def().weapon, 0, "")]
	held = 0
	hp = max_hp(); shield = max_shield()
	second_wind_used = false
	shop_offers = []; shop_locked = [false, false, false, false]; rerolls = 0
	changed.emit()


func hero_def() -> Dictionary:
	return Heroes.DEFS[hero]


func diff(key: String) -> float:
	return DIFFICULTIES[difficulty][key]


func add_ult(damage: float) -> void:
	if ult >= 100.0 or ult_lock > 0.0:
		return
	var per_point := 14.0 * (1.0 + 0.4 * (depth() - 1))
	ult = minf(100.0, ult + damage / per_point * (1.4 if has("charged") else 1.0))


func make_weapon(id: String, tier: int, element: String) -> Dictionary:
	return {"id": id, "tier": tier, "element": element}


func weapon_name(w: Dictionary) -> String:
	var e: String = ELEMENTS[w.element].name
	return ("%s %s" % [e, WEAPONS[w.id].name]).strip_edges()


func weapon_dmg(w: Dictionary) -> float:
	return WEAPONS[w.id].dmg * (1.0 + 0.3 * w.tier) * (1.0 + 0.15 * (depth() - 1))


func weapon_price(w: Dictionary) -> int:
	return int((WEAPONS[w.id].price + 18 * w.tier) * price_scale())


## How deep into the run we are, 1-based across acts.
func depth() -> int:
	return (act - 1) * DEPTH_PER_ACT + level


func price_scale() -> float:
	return 1.0 + 0.22 * (depth() - 1)


func is_boss_level() -> bool:
	return level == LEVELS_PER_ACT


func biome() -> String:
	return ["tundra", "dunes", "tomb"][clampi(act, 1, ACTS) - 1]


func biome_name(b := "") -> String:
	return ERAS[b if b != "" else biome()].name


## "20,000 BC", "2560 BC", "AD 802,701". Commas only once the number gets long.
static func format_year(y: int) -> String:
	var n := absi(y)
	var digits := str(n)
	if n >= 10000:
		var grouped := ""
		while digits.length() > 3:
			grouped = "," + digits.right(3) + grouped
			digits = digits.left(digits.length() - 3)
		digits += grouped
	return "%s BC" % digits if y < 0 else "AD %s" % digits


## The year and a few words for the current level, shown as you arrive.
func era_stamp() -> Dictionary:
	return ERAS[biome()].stamps[level - 1]


func stack(id: String) -> int:
	return items.get(id, 0)


func stat(s: String) -> float:
	var total := 0.0
	for id in items:
		var effects: Dictionary = ITEMS[id].get("stats", {})
		total += effects.get(s, 0.0) * items[id]
	return total


func stat_icon(s: String) -> String:
	return STAT_DEFS.get(s, {}).get("icon", "gear")


func stat_color(s: String) -> Color:
	return STAT_DEFS.get(s, {}).get("color", Color.WHITE)


func item_icon(id: String) -> String:
	return ITEMS.get(id, {}).get("icon", "gear")


func item_color(id: String) -> Color:
	var item: Dictionary = ITEMS.get(id, {})
	var effects: Dictionary = item.get("stats", {})
	if effects.is_empty():
		return stat_color("hp")
	return stat_color(String(effects.keys()[0]))


func item_groups(id: String) -> Array[String]:
	var groups: Array[String] = []
	var item: Dictionary = ITEMS.get(id, {})
	var effects: Dictionary = item.get("stats", {})
	for s in effects:
		var group: String = STAT_DEFS[s].group
		if not groups.has(group):
			groups.append(group)
	if item.has("heal"):
		groups.append("Recovery")
	return groups


func item_group_label(id: String) -> String:
	var groups := item_groups(id)
	if groups.size() > 1:
		return " / ".join(PackedStringArray(groups))
	return groups[0] if not groups.is_empty() else "Item"


func item_effect_text(id: String, stat_id: String) -> String:
	var item: Dictionary = ITEMS[id]
	if stat_id == "heal":
		return "Heal %d HP" % int(item.heal)
	var amount: float = item.stats[stat_id]
	var definition: Dictionary = STAT_DEFS[stat_id]
	if definition.format == "flat":
		var flat_sign := "+" if amount >= 0.0 else ""
		return "%s%d %s" % [flat_sign, roundi(amount), definition.name]
	var shown := -amount if definition.get("inverse", false) else amount
	var percent_sign := "+" if shown >= 0.0 else ""
	return "%s%d%% %s" % [percent_sign, roundi(shown * 100.0), definition.name]


func item_effect_ids(id: String) -> Array[String]:
	var result: Array[String] = []
	var effects: Dictionary = ITEMS[id].get("stats", {})
	for s in effects:
		result.append(String(s))
	if ITEMS[id].has("heal"):
		result.append("heal")
	return result


func has(power: String) -> bool:
	return powers.has(power)


func max_hp() -> float:
	return hero_def().hp + stat("hp") + (40.0 if has("heart") else 0.0)


func max_shield() -> float:
	return hero_def().shield + stat("shield")


func dmg_mult() -> float:
	return maxf(0.1, 1.0 + stat("dmg"))


func rate_mult() -> float:
	return 1.0 + stat("rate")


func crit_chance() -> float:
	return 0.05 + stat("crit")


func crit_mult() -> float:
	return 2.0 + stat("critdmg")


func cd_mult() -> float:
	return maxf(0.35, 1.0 - stat("cdr"))


func add_coins(n: int) -> void:
	coins += n
	changed.emit()


func current_weapon() -> Dictionary:
	return weapons[held]


## --- Shop -------------------------------------------------------------------

func roll_offer() -> Dictionary:
	if randf() < 0.35:
		var ids := WEAPONS.keys().filter(func(k): return k != hero_def().weapon)
		var tier := clampi(int(randf() * randf() * 4.0 + (depth() - 1) * 0.25), 0, 3)
		var el: String = ["", "", "fire", "shock", "rust"].pick_random()
		var w := make_weapon(ids.pick_random(), tier, el)
		return {"kind": "weapon", "weapon": w, "price": weapon_price(w)}
	var id: String = ITEMS.keys().pick_random()
	return {"kind": "item", "id": id, "price": int(ITEMS[id].price * price_scale())}


## Rerolls every unlocked (or empty) slot.
func refresh_shop() -> void:
	if shop_offers.size() != 4:
		shop_offers = [{}, {}, {}, {}]
		shop_locked = [false, false, false, false]
	for i in 4:
		if not shop_locked[i] or shop_offers[i].is_empty():
			shop_offers[i] = roll_offer()
	changed.emit()


func reroll_price() -> int:
	return 2 + depth() + rerolls * 2


func buy(i: int) -> bool:
	var o: Dictionary = shop_offers[i]
	if o.is_empty() or coins < o.price:
		return false
	coins -= o.price
	if o.kind == "item":
		if ITEMS[o.id].has("heal"):
			hp = minf(max_hp(), hp + ITEMS[o.id].heal)
		else:
			items[o.id] = stack(o.id) + 1
			var health_gain: float = ITEMS[o.id].get("stats", {}).get("hp", 0.0)
			if health_gain > 0.0:
				hp += health_gain
	else:
		give_weapon(o.weapon)
	shop_offers[i] = {}
	shop_locked[i] = false
	changed.emit()
	return true


func give_weapon(w: Dictionary) -> void:
	if weapons.size() < 2:
		weapons.append(w)
		held = weapons.size() - 1
	else:
		weapons[held] = w
	changed.emit()


func reroll() -> bool:
	var p := reroll_price()
	if coins < p:
		return false
	coins -= p
	rerolls += 1
	refresh_shop()
	return true


## --- Powers -----------------------------------------------------------------

func power_choices() -> Array:
	var pool := POWERS.keys().filter(func(k): return not powers.has(k) and POWERS[k].get("hero", hero) == hero)
	pool.shuffle()
	return pool.slice(0, 3)


func take_power(id: String) -> void:
	powers[id] = true
	if id == "heart":
		hp += 40.0
	changed.emit()


## --- Progression ------------------------------------------------------------

## Advance to the next level. Returns false when the run is won.
func next_level() -> bool:
	# The last act's boss ends the run: leave act/level as they are so the HUD and end
	# screen (still drawing behind the victory menu) never look up a fourth era.
	if level >= LEVELS_PER_ACT and act >= ACTS:
		return false
	room = 0
	rerolls = 0
	second_wind_used = false
	level += 1
	if level > LEVELS_PER_ACT:
		level = 1
		act += 1
	changed.emit()
	return true
