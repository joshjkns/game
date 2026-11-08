class_name Logo
extends Control
## The UNWOUND typemark: a clock badge whose mainspring uncoils out through a gap in the rim,
## set over a slanted Lilita One wordmark in cream with an ink outline. Drawn in code so it
## stays crisp at any size. The gold second hand ticks in real time.

const CREAM := Color("fff4e0")
const GOLD := Color("ffe08b")
const INK := Color(0.012, 0.025, 0.03)
const WORD := "UNWOUND"
const TAGLINE := "A TIME-BENDING ROGUELITE"
const SLANT := 0.16
const GAP_FROM := -0.95  # the rim is open between these angles (upper right)
const GAP_TO := -0.15

var word_size := 92
var show_tagline := true
var _font: Font
var _tag_font: Font
var _second := -1


func _init(fsize := 92, tagline := true) -> void:
	word_size = fsize
	show_tagline = tagline


func _ready() -> void:
	_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_tag_font = load("res://assets/fonts/Rajdhani-Bold.ttf")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(word_size * 5.0, word_size * (2.45 if show_tagline else 2.15))


func _process(_delta: float) -> void:
	var s := int(Time.get_unix_time_from_system()) % 60
	if s != _second:
		_second = s
		queue_redraw()


func _draw() -> void:
	var r := word_size * 0.4
	var c := Vector2(size.x * 0.5, r * 1.25)
	_badge(c, r)
	var baseline := c.y + r * 1.2 + word_size * 0.86
	_wordmark(baseline)
	if show_tagline:
		_tagline(baseline + word_size * 0.36)


func _badge(c: Vector2, r: float) -> void:
	var w := r * 0.15
	var rim := w + r * 0.13
	# Ink backing plate, then the rim with its gap, outlined in ink.
	draw_circle(c, r * 1.12, INK)
	draw_arc(c, r, GAP_TO, TAU + GAP_FROM, 64, INK, rim, true)
	draw_arc(c, r, GAP_TO, TAU + GAP_FROM, 64, CREAM, w, true)
	# The mainspring peels off the rim's end and sweeps out through the gap, tapering.
	var pts := PackedVector2Array()
	var steps := 40
	for i in steps + 1:
		var t := float(i) / steps
		var a := lerpf(GAP_FROM, 0.6, t)
		pts.append(c + Vector2.from_angle(a) * r * (1.0 + 0.62 * t * t))
	for pass_i in 2:
		for i in steps:
			var t := float(i) / steps
			var ww := lerpf(w, w * 0.35, t)
			if pass_i == 0:
				draw_line(pts[i], pts[i + 1], INK, ww + r * 0.13, true)
			else:
				draw_line(pts[i], pts[i + 1], CREAM, ww, true)
		var tip := pts[steps]
		draw_circle(tip, (w * 0.75 + r * 0.07) if pass_i == 0 else w * 0.75, INK if pass_i == 0 else GOLD)
	# Hour ticks, the quarters longer.
	for i in 12:
		var a := TAU * i / 12.0 - PI * 0.5
		var d := Vector2.from_angle(a)
		var inner := 0.66 if i % 3 == 0 else 0.74
		draw_line(c + d * r * inner, c + d * r * 0.84, CREAM, w * (0.8 if i % 3 == 0 else 0.5), true)
	# Hands at ten past ten, and a live second hand.
	_hand(c, -PI / 3.0, r * 0.46, w * 1.0, CREAM)
	_hand(c, PI / 3.0, r * 0.66, w * 0.8, CREAM)
	var sec := TAU * maxi(_second, 0) / 60.0
	_hand(c, sec, r * 0.78, w * 0.38, GOLD, r * 0.2)
	draw_circle(c, w * 0.7, GOLD)
	draw_circle(c, w * 0.28, INK)


## Clock angle: 0 is twelve o'clock, increasing clockwise.
func _hand(c: Vector2, clock_angle: float, length: float, width: float, col: Color, tail := 0.0) -> void:
	var d := Vector2.from_angle(clock_angle - PI * 0.5)
	draw_line(c - d * tail, c + d * length, col, width, true)


func _wordmark(baseline: float) -> void:
	var fsize := word_size
	var spacing := fsize * 0.02
	var widths: Array[float] = []
	var total := 0.0
	for ch in WORD:
		var cw := _font.get_char_size(ch.unicode_at(0), fsize).x
		widths.append(cw)
		total += cw + spacing
	total -= spacing
	var x0 := (size.x - total) * 0.5 + fsize * SLANT * 0.3
	var outline := int(fsize * 0.16)
	# Slant the whole word about its baseline.
	draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-SLANT, 1), Vector2(0, baseline)))
	for pass_i in 3:
		var x := x0
		for i in WORD.length():
			var ch := WORD[i]
			match pass_i:
				0:
					draw_string_outline(_font, Vector2(x + fsize * 0.05, fsize * 0.07), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, INK)
				1:
					draw_string_outline(_font, Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, outline, INK)
				2:
					draw_string(_font, Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, CREAM)
			x += widths[i] + spacing
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _tagline(y: float) -> void:
	var fsize := int(word_size * 0.2)
	var spaced := " ".join(TAGLINE.split(""))
	var tw := _tag_font.get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := (size.x - tw) * 0.5
	draw_string_outline(_tag_font, Vector2(x, y), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, INK)
	draw_string(_tag_font, Vector2(x, y), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, GOLD)
	var mid := y - fsize * 0.32
	var rule := word_size * 0.55
	for side: float in [-1.0, 1.0]:
		var inner := size.x * 0.5 + side * (tw * 0.5 + fsize * 0.6)
		draw_line(Vector2(inner, mid), Vector2(inner + side * rule, mid), INK, 4.0, true)
		draw_line(Vector2(inner, mid), Vector2(inner + side * rule, mid), GOLD, 2.0, true)
