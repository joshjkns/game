class_name Levels
## Level layouts. One character = one tile (Util.TILE metres).
##   #  wall              .  floor
##   A  player A start    B  player B start
##   G  gun               E  enemy
##   D  exit door (must be in the bottom row)
##   w  glass railing: bullets pass, players don't
##   ^ v < >  shielded enemy facing up / down / left / right (blocks shots from the front)

const ALL := [
	{
		"name": "Fire and Return",
		"hint": "A fires through the top target. Drop the gun for B, who recalls the bullet through the other one.",
		"map": [
			"###############",
			"#.............#",
			"#..A.G........#",
			"#.........E...#",
			"#.............#",
			"#..B......E...#",
			"#.............#",
			"#######D#######",
		],
	},
	{
		"name": "Two for One",
		"hint": "Four targets, one bullet. Aim each shot so B gets a clean return line through another target.",
		"map": [
			"###############",
			"#.............#",
			"#..E.......E..#",
			"#.............#",
			"#.....###.....#",
			"#.A.G.###...B.#",
			"#.............#",
			"#..E.......E..#",
			"#######D#######",
		],
	},
	{
		"name": "Around the Shield",
		"hint": "The shielded target blocks shots from the front. Shoot past it, then recall through its back.",
		"map": [
			"###############",
			"#.............#",
			"#.....v.......#",
			"#.............#",
			"#wwwwwwwwwwwww#",
			"#.............#",
			"#..A.G.....E..#",
			"#..B..........#",
			"#######D#######",
		],
	},
]
