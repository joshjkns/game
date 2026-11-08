class_name Rooms
## Room layouts. One character = one Util.TILE (1.5 m) square.
##
## Structure       #  wall (full height)     .  floor        ,  floor strewn with bones/rubble
##                 _  chasm                  w  glowing water (walkable)   =  red carpet
##                 o  skylight (a moonbeam through a ceiling grate)
##                 n  crawlway: wall with a 1 m gap at the floor (slide or crouch through)
## Agents          A  LEON start   B  NOEL start   G  the revolver (loaded)
## Spawn markers   !  ?  $  %  &  where wave groups appear (plain floor otherwise)
## Cover / decor   O  pillar   c  crates   r  barrels   t  table   S  statue   i  brazier
##                 L  chandelier overhead
## Break / restore |  -  crystal ward (N-S / E-W)    b  bridge   z  broken bridge
##                 k  crumbling floor over a chasm
##                 u  loot urn (LEON smashes it)     U  shattered relic (NOEL restores it)
## Traps           s  spikes   f  fire grate   h  blade swinging E-W   v  blade swinging N-S
## Puzzles         1-9  portcullis on that channel
##                 per-room "keys" map a letter to a trigger: [type, channel, seconds]
##                   plate    held while someone (or a prop) stands on it
##                   rune_f   lit by LEON's shot    rune_r  lit by NOEL's recall
##                   rune_p   needs both in one cycle (a pincer)
##                   brazier  NOEL rewinds it to full fire; it burns down
##                 "exit": N  the exit door also needs channel N on
##                 D  exit (in the bottom wall row; 3 wide)
## Waves           "waves": 2-4 waves, each a list of groups [kind, marker, count = 1]
##                 "final": one more wave, triggered by stepping into the open lift
##                   kinds: E  cultist   T  gargoyle sentry (static)   X  Anchor (dies only to a
##                   pincer; at most one per room)   R  rusher (groups spawn in single file)
## Every row must be the same length. Story lines: [speaker, text], speaker "" / "A" / "B".

## A run plays the first RUN_LENGTH rooms. The movement test arena comes after them.
const RUN_LENGTH := 5

const ALL := [
	{
		"name": "THE UNDERCROFT",
		"floor": "I",
		"par": 45.0,
		"fire_interval": 3.0,
		"height": 6.0,
		"accent": Color(0.25, 1.0, 0.6),
		"keys": {"F": ["rune_f", 1], "Q": ["rune_r", 2]},
		"waves": [
			[["E", "!"], ["E", "?"]],
			[["R", "$", 3]],
		],
		"final": [["R", "$", 3], ["E", "!"]],
		"map": [
			"#########################",
			"#u.u.#.......L.......#.U#",
			"#....#...............#..#",
			"#.u..1.......!.......2..#",
			"#i...#...............#.i#",
			"######O.............O####",
			"#O.....................O#",
			"#............=.......$..#",
			"#..A.G.......=..........#",
			"#............=.....?....#",
			"#..B.........=..........#",
			"#.......F....=...Q..p...#",
			"#O.r..t......=.....i...O#",
			"############DDD##########",
		],
	},
	{
		"name": "THE CISTERN",
		"floor": "II",
		"par": 55.0,
		"fire_interval": 2.2,
		"height": 6.0,
		"accent": Color(0.15, 0.95, 0.75),
		"keys": {"P": ["plate", 1]},
		"exit": 1,
		"waves": [
			[["T", "!"], ["E", "?"], ["E", "$"]],
			[["R", "%", 3], ["E", "?"]],
		],
		"final": [["R", "%", 3], ["R", "?", 2]],
		"map": [
			"###########################",
			"#!........w___w.........?.#",
			"#.........w___w...........#",
			"#..p......wzzzw....|......#",
			"#.........w___w....|......#",
			"#...O.....w___w....|..$...#",
			"#.........w___w....|......#",
			"#..A......wbbbw....|...p..#",
			"#..G...B..w___w...........#",
			"#.p.......w___w....O...%..#",
			"#....u....w___w...........#",
			"#i..u.....w___w..P..u...i.#",
			"##################DDD######",
		],
	},
	{
		"name": "THE OSSUARY",
		"floor": "III",
		"par": 70.0,
		"fire_interval": 2.0,
		"height": 6.5,
		"accent": Color(1.0, 0.35, 0.15),
		"keys": {"Y": ["brazier", 1, 35.0]},
		"exit": 1,
		"waves": [
			[["X", "!"], ["E", "?"], ["E", "$"]],
			[["R", "%", 3], ["E", "?"]],
			[["R", "?", 2], ["R", "$", 2]],
		],
		"final": [["R", "%", 4]],
		"map": [
			"###########################",
			"#,,,,S.........!......S,,,#",
			"#,...........%...........,#",
			"#..O.....O...L...O.....O..#",
			"#.........................#",
			"#.....?...............$...#",
			"#..O.....O.......O.....O..#",
			"#.........sssssss.........#",
			"#_____..............._____#",
			"#Y.kkk...............kkk.Y#",
			"#..___..A.G.....B....___..#",
			"#_____...i.......i..._____#",
			"############DDD############",
		],
	},
	{
		"name": "THE CLOCKWORK GALLERY",
		"floor": "IV",
		"par": 60.0,
		"fire_interval": 2.0,
		"height": 6.5,
		"accent": Color(0.7, 0.45, 1.0),
		"keys": {"P": ["plate", 1], "Q": ["plate", 2]},
		"waves": [
			[["E", "!"], ["T", "?"], ["E", "$"]],
			[["R", "%", 3], ["E", "$"]],
		],
		"final": [["R", "%", 3], ["R", "!", 3]],
		"map": [
			"#############################",
			"#.........#.....!....o....?.#",
			"#..r......#.................#",
			"#.........#...O.......O.....#",
			"#..P......1.......f.f.......#",
			"#.........#.................#",
			"#.....O...#.....$.......c...#",
			"#.........#####h#####h#######",
			"#..t......#.................#",
			"#..A.G....#....s.s.s.s......#",
			"#..B......#.......%.........#",
			"#...p.....2.......Q.........#",
			"#.i.......#....s.s.s.s...i..#",
			"#.U.......#.................#",
			"##################DDD########",
		],
	},
	{
		"name": "THE THRONE OF HOURS",
		"floor": "V",
		"par": 80.0,
		"fire_interval": 1.8,
		"height": 7.5,
		"accent": Color(0.3, 0.75, 1.0),
		"keys": {"Z": ["rune_p", 1]},
		"exit": 1,
		"waves": [
			[["T", "!"], ["E", "%"], ["E", "&"]],
			[["X", "?"], ["R", "$", 3]],
			[["R", "%", 3], ["R", "&", 3]],
		],
		"final": [["R", "$", 3], ["R", "?", 3]],
		"map": [
			"#############################",
			"#www..S...i...!...i...S..www#",
			"#www...?......Z......$...www#",
			"#www......o.......o......www#",
			"#www--O.......L.......O--www#",
			"#www.....................www#",
			"#.....O.....%.=.&.....O.....#",
			"#..p..........=...........p.#",
			"#.....O.......=.......O.....#",
			"#....c...f....=....f...c....#",
			"#.............=.............#",
			"#..o..O.......=.......O..o..#",
			"#...A.G.......=.......B.....#",
			"#.i....t......=......t....i.#",
			"#############DDD#############",
		],
	},
	{
		"name": "THE PROVING HALL",
		"floor": "0",
		"par": 30.0,
		"fire_interval": 2.5,
		"height": 6.0,
		"accent": Color(1.0, 0.75, 0.3),
		"waves": [[["E", "!"]]],
		"final": [["E", "!"]],
		"map": [
			"#################",
			"#...........#...#",
			"#.A.B.G.r...#...#",
			"#...........#...#",
			"#..t........n.!.#",
			"#...........#...#",
			"#...........#...#",
			"#####...#####...#",
			"#####___#####...#",
			"#####___#####...#",
			"#####___#####...#",
			"#####___#####...#",
			"#####...#####...#",
			"#...............#",
			"########DDD######",
		],
	},
]
