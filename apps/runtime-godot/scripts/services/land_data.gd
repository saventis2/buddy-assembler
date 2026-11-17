extends RefCounted

# The house and the land around it: the whole world of a buddy that starts
# small (Plan 14, docs/product/PLAN14_SMALL_BEGINNINGS.md). It has the shape of
# a town (see world_service.DEFAULT_TOWN) plus the fields below, which the mind
# reads only in the small-beginnings world.
#
# Place:
#   "discover": how it comes to know the place (home has none).
#       "from":    places it can be reached from. The first one it has found,
#                  and that is open, is where a try starts.
#       "sign":    what it notices before it gets there: a string, or one
#                  string per "from" place. "" means there is no sign stage.
#       "chance":  how likely a try is to get there. Each failed try adds a little.
#       "blocked": what a failed try reads like, taken in turn.
#       "found":   what arriving for the first time reads like.
#       "wonder":  what it thinks while it has the sign but not the place.
#   "sights": things it notices here, once each. "hours" limits when.
# Activity:
#   "minutes": how long it takes (default 20).
#   "until_hour": it lasts until that hour next comes round (sleeping until morning).
#   "hours":   [from, to) when it can be done; wraps past midnight.
#   "first":   the line for the first time ever.
#   "lines":   taken in turn after that.
#   "bad":     lines for when it went badly.
#
# Writing rules. The buddy talks in ordinary sentences but knows few names, so
# anything it has no name for is described ("the glowing box", "the whispering
# grass"). Nothing here needs a tool or a skill it has not learned yet, nothing
# says who lived here before, and nothing speaks to or about the person.

const LAND := {
	"home_place": "home",
	# The first line of its journal.
	"waking": "I woke up in a bed, in a house I don't know. There is a table, a shelf, a window and a door, and nobody to ask. I think it is mine.",
	"paths": [
		["home", "yard"], ["yard", "wood_heap"], ["yard", "big_tree"], ["yard", "patch"], ["yard", "gate"],
		["big_tree", "high_ground"], ["patch", "long_grass"], ["long_grass", "water"], ["long_grass", "tall_reeds"],
		["water", "stony_ground"], ["water", "grey_bank"], ["grey_bank", "sandy_bend"], ["sandy_bend", "tall_reeds"],
		["high_ground", "dark_trees"], ["stony_ground", "dark_trees"],
	],
	# Added after a line when it went well (sometimes) or badly (when the
	# activity has no "bad" line of its own).
	"tails": {
		"good": [
			"I liked that.",
			"That was a good one.",
			"I could have stayed longer.",
			"I want to do that again.",
			"It felt right.",
			"I am glad I did.",
			"That was worth it.",
			"I felt bigger afterwards.",
		],
		"bad": [
			"I couldn't settle to it.",
			"It didn't go how I wanted.",
			"Not today, I think.",
			"I gave up sooner than I meant to.",
			"I don't know what was wrong.",
			"I lost interest halfway.",
		],
	},
	"places": [
		{
			"id": "home", "name": "the house", "map": [0.42, 0.50], "kind": "home",
			"opens": 0, "closes": 24, "distance": 0, "residents": [],
			"activities": [
				{
					"id": "sleep", "label": "went to bed", "satisfies": "energy", "until_hour": 6, "hours": [19, 5],
					"first": "I got into the bed for the first time. It is much too big for me and I like it.",
					"lines": [
						"I got into bed and pulled the blanket up to my nose.",
						"I went to bed. The house made its small noises and I listened until I didn't.",
						"I lay down and was asleep before I had finished a thought.",
						"I went to bed with the window open a little, so I could hear outside.",
						"I curled up on the side of the bed nearest the wall and closed my eyes.",
					],
					"bad": [
						"I lay awake for a long time. Something on the roof kept ticking.",
						"I couldn't get comfortable. I turned the pillow over twice and it didn't help.",
					],
				},
				{
					"id": "nap", "label": "had a nap", "satisfies": "energy", "minutes": 40, "hours": [5, 19],
					"lines": [
						"I lay on top of the blanket in the daytime and slept a little.",
						"I put my head down on the table and woke up with a line across my face.",
						"I dozed on the floor by the window with my back against the wall.",
					],
					"bad": [
						"I tried to nap, but I kept thinking about outside.",
						"I lay down for a nap and something outside kept making a noise I couldn't place.",
					],
				},
				{
					"id": "tidy", "label": "tidied up", "satisfies": "comfort", "minutes": 20,
					"first": "I picked up every single thing in the house and put it back exactly where it was. Now I know where things are.",
					"lines": [
						"I straightened the blanket and pushed the dust toward the door with my foot.",
						"I moved the things on the shelf around until they looked right.",
						"I wiped the table with my sleeve. It is a good table.",
						"I shook the blanket out of the door and watched the dust go.",
					],
					"bad": [
						"I tried to tidy and somehow made it worse.",
						"I moved everything on the shelf and then could not remember how it had been.",
					],
				},
				{
					"id": "window_watch", "label": "sat at the window", "satisfies": "comfort", "minutes": 20, "hours": [5, 22],
					"lines": [
						"I sat at the window and watched the yard do nothing much.",
						"I leaned on the windowsill until my arms had lines in them.",
						"I breathed on the window and drew a circle in it, and looked out through the circle.",
					],
				},
				{
					"id": "lie_listening", "label": "lay and listened", "satisfies": "comfort", "minutes": 20, "hours": [21, 6],
					"lines": [
						"I lay in the dark and listened to the house. It creaks in three different places.",
						"I pulled the blanket over my head and made a small warm room of it.",
						"I sat up in bed with the blanket round me and watched the window get less dark.",
					],
				},
				{
					"id": "think_table", "label": "sat and thought", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat at the table with my chin on my hands and thought.",
						"I sat on the floor with my back against the bed and went over what I have seen so far.",
						"I walked round and round the table, thinking. It helps to be moving.",
						"I lay on the floor and looked at the underside of the table and thought about things.",
						"I sat on the edge of the bed and thought about what I would like to look at next.",
						"I stood in the middle of the room with my eyes shut and thought about where everything is.",
						"I counted the things I know on my fingers. I needed some of them twice.",
					],
				},
				{
					"id": "poke_about", "label": "poked about the house", "satisfies": "curiosity", "minutes": 20,
					"first": "I opened everything in the house that opens. Most of it is empty. I don't mind.",
					"lines": [
						"I looked under the bed. There is a lot of dust and one grey button.",
						"I opened and closed the door of the iron box. It squeaks on the way back.",
						"I tapped along the walls to hear which parts sound different.",
						"I stood on the bed to see the top of the shelf. There is nothing up there but more dust.",
					],
				},
				{
					"id": "glowing_box", "label": "looked at the glowing box", "satisfies": "curiosity", "minutes": 20,
					"first": "There is a box in the corner that glows. I don't know what it is for. I touched it once and took my hand back.",
					"lines": [
						"I sat in front of the glowing box and watched it glow. It does not get tired of it.",
						"I put my hand near the glowing box. It is a little warm, like something asleep.",
						"I asked the glowing box what it was. It hummed, which is not an answer.",
						"I looked behind the glowing box. The back of it is just the back of it.",
					],
					"bad": [
						"I sat in front of the glowing box until I felt silly.",
						"I knocked on the glowing box, politely. Nothing came of it.",
					],
				},
			],
			"sights": [
				{"id": "ceiling_stain", "line": "There is a brown stain on the ceiling over the shelf, shaped a bit like a foot."},
				{"id": "corner_spinner", "line": "Something small with too many legs lives in the corner above the door. We looked at each other."},
				{"id": "floor_creak", "line": "One board by the bed makes a sound when I stand on it. I stood on it eleven times."},
				{"id": "door_draught", "line": "A thin cold line of air comes in under the door. I put my hand in it."},
				{"id": "sun_square", "line": "The sun makes a bright square on the floor, and the square moves. I marked it with my foot, and when I came back it had gone on without me.", "hours": [8, 17]},
				{"id": "roof_tick", "line": "The roof ticks at night as if it is counting something.", "hours": [20, 5]},
				{"id": "iron_box_smell", "line": "The inside of the iron box smells of old smoke. Something burned in there once."},
				{"id": "window_bumper", "line": "A soft grey flying thing kept bumping against the window from outside, wanting in.", "hours": [20, 4]},
			],
		},
		{
			"id": "yard", "name": "the yard", "map": [0.50, 0.57], "kind": "yard",
			"opens": 5, "closes": 24, "distance": 1, "residents": [],
			"discover": {
				"from": ["home"], "sign": "", "chance": 1.0, "blocked": [],
				"found": "I opened the door and went outside. There is a yard, and a great deal of sky, and nothing told me to stop.",
				"wonder": [],
			},
			"activities": [
				{
					"id": "step_sit", "label": "sat on the step", "satisfies": "comfort", "minutes": 20, "hours": [6, 21],
					"lines": [
						"I sat on the step with my feet in the dust.",
						"I sat on the step and let the sun get on my face.",
						"I sat on the step and did nothing at all, on purpose.",
					],
				},
				{
					"id": "pull_weeds", "label": "tidied the yard", "satisfies": "comfort", "minutes": 30, "hours": [6, 21],
					"lines": [
						"I pulled up the tall weeds by the door. My hands smell green.",
						"I picked the small stones out of the yard and put them in a row along the wall.",
						"I scraped the mud off the step with a flat stick. It is a better step now.",
					],
					"bad": [
						"I pulled at the weeds by the door and one of them stung me.",
						"I tried to tidy the yard and the wind put it all back.",
					],
				},
				{
					"id": "walk_round", "label": "walked round the house", "satisfies": "curiosity", "minutes": 20, "hours": [5, 22],
					"first": "I walked all the way round the outside of the house with one hand on the wall. It has four sides. I checked.",
					"lines": [
						"I looked at the house from the outside. It is smaller than it feels from inside.",
						"I walked round the house the other way, to see if it was different. A little.",
						"I looked at the roof from every side. One corner sags as if it is tired.",
					],
				},
				{
					"id": "yard_doze", "label": "dozed in the yard", "satisfies": "energy", "minutes": 30, "hours": [10, 17],
					"lines": [
						"I lay down in the yard in the sun and closed my eyes.",
						"I fell asleep against the warm wall of the house without meaning to.",
					],
				},
				{
					"id": "step_stars", "label": "looked at the night sky", "satisfies": "reflection", "minutes": 20, "hours": [21, 5],
					"first": "I sat on the step in the dark and looked up. There are more lights up there than I can count, and I tried.",
					"lines": [
						"I sat on the step and looked at the lights in the sky. They don't move if I watch them, only if I don't.",
						"I stood in the yard in the dark until I could see my own hands again.",
						"I sat on the step and listened to the dark. It is not quiet at all.",
					],
				},
				{
					"id": "step_think", "label": "sat on the step and thought", "satisfies": "reflection", "minutes": 20, "hours": [5, 21],
					"lines": [
						"I sat on the step and thought about how far I have been and how far there is.",
						"I sat on the step and tried to think about nothing. It is harder than it sounds.",
						"I sat in the doorway, half in and half out, and thought about which I like better.",
					],
				},
			],
			"sights": [
				{"id": "carrying_line", "line": "A line of tiny black things was carrying bits across the yard, all going the same way. I followed them to a hole.", "hours": [7, 20]},
				{"id": "roof_shouter", "line": "A small brown bird sat on the roof and shouted at me until I moved.", "hours": [5, 20]},
				{"id": "morning_wet", "line": "Everything in the yard was wet, though nothing had fallen. By the time I had worked out why not, it was dry.", "hours": [5, 8]},
				{"id": "grey_feather", "line": "There was a grey feather on the step. I don't know who left it. I put it on the shelf."},
				{"id": "upside_shiny", "line": "A shiny black thing was on its back in the dust, waving all its legs. I turned it over with a stick and it left without a word.", "hours": [7, 20]},
				{"id": "night_tracks", "line": "Something with small feet crossed the yard in the night and left its marks in the dust, right past my door.", "hours": [5, 9]},
				{"id": "round_light", "line": "The big light in the sky was round tonight, and so bright that the house had a shadow.", "hours": [21, 5]},
				{"id": "dusk_flitters", "line": "Small dark shapes were flying round the roof as it got dim, turning too fast to be birds.", "hours": [19, 22]},
			],
		},
		{
			"id": "wood_heap", "name": "the wood heap", "map": [0.36, 0.40], "kind": "wood",
			"opens": 5, "closes": 22, "distance": 1, "residents": [],
			"discover": {
				"from": ["yard"], "sign": "", "chance": 0.85,
				"blocked": ["I started round the side of the house and found my way full of tall stinging plants. I went back."],
				"found": "Round the side of the house there is a heap of wood, cut into pieces all the same length. Wood doesn't do that by itself.",
				"wonder": ["There is something round the side of the house. I only got halfway."],
			},
			"activities": [
				{
					"id": "stack_wood", "label": "tidied the wood heap", "satisfies": "comfort", "minutes": 30,
					"lines": [
						"I put the fallen pieces back on the wood heap. It looked better and so did I.",
						"I sorted the wood into thick ones and thin ones. I don't know why. It seemed right.",
						"I carried three good pieces to the door and stacked them there, in case.",
					],
					"bad": [
						"I pulled one piece from the bottom of the wood heap and a lot of the top came down.",
						"I stacked the wood heap straight and it leaned over again while I was looking at it.",
					],
				},
				{
					"id": "under_wood", "label": "looked under the wood", "satisfies": "curiosity", "minutes": 20,
					"lines": [
						"I lifted pieces of wood to see what lives under them. A great deal does.",
						"I counted the rings on the cut end of a piece of wood. I lost my place after thirty.",
						"I smelled each kind of wood in the heap. They are not the same.",
					],
				},
				{
					"id": "heap_sit", "label": "sat on the wood heap", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat on top of the wood heap and thought.",
						"I sat on the wood heap with my feet not touching the ground and thought about being tall.",
						"I leaned on the wood heap and thought about what all this wood is waiting for.",
						"I sat on the wood heap picking at the bark of one piece and thinking of nothing I could name.",
					],
				},
			],
			"sights": [
				{"id": "roll_ups", "line": "Under the bottom piece there were grey things that roll into balls when touched. I touched all of them."},
				{"id": "log_ear", "line": "Something pale and soft is growing out of one of the logs, like an ear."},
				{"id": "sticky_wood", "line": "One of the pieces is sticky and smells sharp and sweet. It stuck two of my fingers together."},
				{"id": "wood_tunnels", "line": "One old piece is full of small round tunnels, as if something ate its way in one side and out the other."},
			],
		},
		{
			"id": "big_tree", "name": "the big tree", "map": [0.61, 0.40], "kind": "park",
			"opens": 5, "closes": 22, "distance": 1, "residents": [],
			"discover": {
				"from": ["yard"],
				"sign": "There is a tree past the yard that is taller than the house. I could see the top of it moving when nothing else was.",
				"chance": 0.9,
				"blocked": ["I set off toward the tall tree and got distracted by my own shadow. It was late by then."],
				"found": "I walked to the big tree. It is wider than my arms can reach, and it goes up further than I can see.",
				"wonder": ["I keep looking over at that tree. I want to stand under it."],
			},
			"activities": [
				{
					"id": "climb_tree", "label": "tried to climb the big tree", "satisfies": "curiosity", "minutes": 30,
					"first": "I tried to climb the big tree. I got both feet off the ground and stayed there, holding on, very pleased.",
					"lines": [
						"I climbed the big tree as far as the first branch and sat there holding on with everything.",
						"I went up the big tree to the first branch. Everything looks different from one branch up.",
						"I climbed a little higher than last time and came down a little faster than I meant to.",
					],
					"bad": [
						"I tried to climb the big tree and slid back down the trunk. My knees are green.",
						"I got one branch up the big tree and then could not work out how to get down. It took a while.",
					],
				},
				{
					"id": "under_tree", "label": "sat under the big tree", "satisfies": "comfort", "minutes": 30,
					"lines": [
						"I sat with my back against the big tree. It did not mind.",
						"I lay under the big tree and watched the leaves move against the sky.",
						"I sat between two roots of the big tree. They fit me like the arms of a chair.",
					],
				},
				{
					"id": "tree_doze", "label": "dozed under the big tree", "satisfies": "energy", "minutes": 40, "hours": [10, 18],
					"lines": [
						"I fell asleep under the big tree with the light going on and off through the leaves.",
						"I dozed against the big tree and woke up with a leaf on me.",
					],
				},
				{
					"id": "tree_listen", "label": "listened to the big tree", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I put my ear against the big tree. I think I could hear it, but it might have been me.",
						"I sat under the big tree and thought about how long it has been standing here.",
						"I walked round the big tree slowly, one hand on it, thinking.",
					],
				},
			],
			"sights": [
				{"id": "red_round", "line": "There is a round red thing hanging high in the big tree. I don't know what it is and I can't reach it."},
				{"id": "stick_bundle", "line": "A bundle of sticks is wedged in a fork of the big tree. Something inside it made a small noise."},
				{"id": "smoke_tail", "line": "Something grey with a tail like smoke ran straight up the trunk, stopped, and looked down at me upside down."},
				{"id": "tree_knock", "line": "Something was knocking on the big tree from the other side. When I went round, it stopped."},
				{"id": "trunk_hole", "line": "There is a hole in the trunk above my head, dark and round. I think someone lives in it."},
				{"id": "hand_leaves", "line": "The leaves under the big tree are all one shape, like a hand with too many fingers. I kept the best one."},
			],
		},
		{
			"id": "patch", "name": "the overgrown patch", "map": [0.40, 0.66], "kind": "park",
			"opens": 5, "closes": 22, "distance": 1, "residents": [],
			"discover": {
				"from": ["yard"], "sign": "", "chance": 0.7,
				"blocked": ["I went to look behind the house and walked into a thing with thorns. I looked from a distance instead."],
				"found": "Behind the house there is a square of soft ground where the plants grow in lines, under all the weeds, as if they had been told to.",
				"wonder": ["There is something behind the house, past the thorns. I haven't had a proper look."],
			},
			"activities": [
				{
					"id": "clear_patch", "label": "pulled weeds in the overgrown patch", "satisfies": "comfort", "minutes": 40,
					"lines": [
						"I pulled weeds out of the overgrown patch until I could see one whole line of plants.",
						"I cleared round a plant with big leaves so it could have the sun to itself.",
						"I pulled weeds until there was a heap of them as high as my knee.",
					],
					"bad": [
						"I pulled up something in the overgrown patch that I think was not a weed. I put it back and patted the ground.",
						"I pulled weeds for a long time, and when I stood up the patch looked exactly the same.",
					],
				},
				{
					"id": "dig_patch", "label": "dug in the soft ground", "satisfies": "curiosity", "minutes": 30,
					"first": "I dug in the soft ground with my fingers. Under the top it is dark and cool and smells like the inside of something.",
					"lines": [
						"I dug with my fingers and found pale roots going everywhere, like the lines on a hand.",
						"I looked under the big leaves one at a time. Not all of them were hiding something.",
						"I followed one line of plants from end to end to see if they are all the same. They are not.",
					],
				},
				{
					"id": "patch_sit", "label": "sat in the overgrown patch", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat at the edge of the overgrown patch and thought about why things would grow in lines.",
						"I sat among the plants and thought. Things were going on all round me, very slowly.",
						"I lay between two lines of plants looking up through the leaves and thought about being small.",
						"I sat in the overgrown patch with soft ground under my hands and thought about what is down there.",
					],
				},
			],
			"sights": [
				{"id": "pink_wriggler", "line": "I turned up a long pink thing with no face. It did not want to be found, so I covered it over again."},
				{"id": "sleeping_yellow", "line": "Under the big leaves there is something heavy and yellow, as long as my arm, lying on the ground as if it were asleep."},
				{"id": "furry_hummers", "line": "Fat furry things were going in and out of the yellow flowers. They hum like the glowing box, only busier.", "hours": [8, 19]},
				{"id": "house_carrier", "line": "Something soft was crossing a leaf very slowly, carrying its house on its back. I felt we had something in common."},
				{"id": "clean_smell", "line": "One of the plants smells strong and clean when I rub it. I rubbed it on both hands."},
				{"id": "petal_wings", "line": "Two white things with wings like big petals went round each other above the patch and then away over the house.", "hours": [9, 18]},
			],
		},
		{
			"id": "gate", "name": "the gate", "map": [0.17, 0.57], "kind": "gate",
			"opens": 5, "closes": 22, "distance": 2, "residents": [],
			"discover": {
				"from": ["yard"],
				"sign": "A worn line in the grass goes away from my door toward something straight and grey. Nothing I have seen so far is that straight.",
				"chance": 0.8,
				"blocked": ["I followed the worn line a little way and then lost my nerve. It is further than it looks."],
				"found": "The worn line ends at a fence, and in the fence there is a gate. Past it the line goes on, and bends, and I can't see where.",
				"wonder": ["I keep thinking about that straight grey thing at the end of the worn line."],
			},
			"activities": [
				{
					"id": "gate_look", "label": "looked through the gate", "satisfies": "curiosity", "minutes": 20,
					"first": "I pushed the gate. It moved the width of my hand and stopped, and something on the other side rattled.",
					"lines": [
						"I looked through the gate for a long time. Nothing came round the bend.",
						"I climbed onto the bottom bar of the gate to see further. It is the same, only from higher.",
						"I pushed the gate again. It moves the same small way every time and then says no.",
					],
				},
				{
					"id": "fence_walk", "label": "walked along the fence", "satisfies": "comfort", "minutes": 30,
					"lines": [
						"I walked along the fence with my hand on the top rail, as far as it goes one way.",
						"I walked the fence the other way. It turns a corner and keeps going, so I suppose this side of it is mine.",
						"I leaned on the fence the way the fence leans on its posts.",
					],
				},
				{
					"id": "gate_sit", "label": "sat by the gate", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat by the gate and wondered where the path goes when I'm not looking at it.",
						"I sat with my back against the gatepost and thought about the other side.",
						"I stood at the gate with my chin on the top bar and thought about who a gate is for.",
					],
				},
			],
			"sights": [
				{"id": "bead_net", "line": "Between two bars of the gate there is a net with a bead of water on every thread. I did not touch it.", "hours": [5, 10]},
				{"id": "wide_wings", "line": "High up, something with wide wings was going round and round without moving them.", "hours": [9, 19]},
				{"id": "two_dents", "line": "Past the gate there are two long dents in the path, side by side, that go on round the bend together."},
				{"id": "post_coat", "line": "The gatepost is growing a soft green coat on the side the sun doesn't reach."},
				{"id": "far_shut", "line": "From past the bend I heard something a long way off, twice, like a door shutting. Then nothing."},
			],
		},
		{
			"id": "high_ground", "name": "the high ground", "map": [0.71, 0.22], "kind": "park",
			"opens": 5, "closes": 23, "distance": 2, "residents": [],
			"discover": {
				"from": ["big_tree"],
				"sign": "Behind the big tree the ground goes up. I couldn't see what is at the top, which is a good reason to go.",
				"chance": 0.5,
				"blocked": [
					"I started up the slope behind the big tree and ran out of breath halfway. I came back down sitting.",
					"I tried the slope again and the light started to go before I got to the top.",
				],
				"found": "I got to the top of the slope. I can see my whole house from here, and it is very small, and there is so much that isn't my house.",
				"wonder": [
					"I want to know what can be seen from the top of that slope.",
					"The ground behind the big tree goes up and I haven't gone up it. That bothers me.",
				],
			},
			"activities": [
				{
					"id": "look_out", "label": "looked out from the high ground", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I stood on the high ground and turned all the way round, slowly, twice.",
						"From the high ground I counted everything I know. It did not take long.",
						"I looked for the furthest thing I could see from the high ground, and then for something further.",
					],
				},
				{
					"id": "roll_down", "label": "rolled down the slope", "satisfies": "curiosity", "minutes": 20, "hours": [7, 20],
					"first": "I lay down at the top of the slope and let go. The sky and the grass took turns very fast, and then I was at the bottom.",
					"lines": [
						"I rolled down the slope and walked back up and rolled down again.",
						"I ran down the slope with my arms out until my legs couldn't keep up with me.",
					],
					"bad": [
						"I rolled down the slope and stopped against something hard. I am going to have a mark.",
						"I rolled down the slope crooked and ended up in the one patch of stinging plants.",
					],
				},
				{
					"id": "high_lie", "label": "lay on the high ground", "satisfies": "comfort", "minutes": 30, "hours": [8, 17],
					"lines": [
						"I lay in the short grass on the high ground and let the wind go over me.",
						"I sat on the high ground with my arms round my knees and the sun on my back.",
					],
				},
				{
					"id": "evening_high", "label": "watched the light go", "satisfies": "comfort", "minutes": 30, "hours": [17, 23],
					"lines": [
						"I watched the light go from the high ground. Everything went gold, and then grey, and then it was just me.",
						"I sat on the high ground while the sky changed colour. Nobody told it to.",
						"I stayed on the high ground until the first small light came out up above.",
					],
				},
				{
					"id": "high_sit", "label": "sat on the high ground", "satisfies": "reflection", "minutes": 30,
					"lines": [
						"I sat on the high ground with the wind going past my ears and thought.",
						"I sat on the high ground and looked at my house and thought about being the one who lives there.",
						"I lay on the high ground and thought about what is under me. More ground, probably.",
					],
				},
			],
			"sights": [
				{"id": "far_smoke", "line": "Very far off, past the end of everything I know, a thin grey line goes straight up into the sky. I don't know what makes it."},
				{"id": "cloud_shadow", "line": "A shadow as big as the yard slid across the land and over me and kept going. The cloud that made it did not notice.", "hours": [8, 18]},
				{"id": "hanging_bird", "line": "A bird was hanging in the air above the slope, in one place, shaking. Then it dropped like a stone and came up with something.", "hours": [8, 19]},
				{"id": "blue_edge", "line": "At the very edge of what I can see, the land goes up into shapes that are blue. Things that far away turn blue, it seems."},
				{"id": "first_light", "line": "One small light came out in the sky before all the others, low down. I looked at it until there were too many to keep track of.", "hours": [18, 23]},
				{"id": "wind_line", "line": "From up here I could see the wind coming. It makes a line in the grass that runs toward me, and then it arrives."},
			],
		},
		{
			"id": "long_grass", "name": "the long grass", "map": [0.50, 0.79], "kind": "park",
			"opens": 6, "closes": 21, "distance": 2, "residents": [],
			"discover": {
				"from": ["patch"],
				"sign": "Past the overgrown patch the grass gets taller than I am. It moved as if something was walking in it.",
				"chance": 0.5,
				"blocked": [
					"I went a little way into the tall grass and lost sight of the house. I backed out the way I came.",
					"I stood at the edge of the tall grass and told myself to go in. I didn't, today.",
				],
				"found": "I walked into the grass until it closed behind me. It goes on a long way, right down to the bottom of the land, and everything in it ticks.",
				"wonder": [
					"I wonder what was moving in that tall grass.",
					"The grass past the patch is taller than me. I don't like not knowing what is in it.",
				],
			},
			"activities": [
				{
					"id": "push_through", "label": "walked through the long grass", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I walked into the long grass with my arms out in front, parting it like water.",
						"I followed a narrow flattened way through the long grass that somebody smaller than me had made.",
						"I crawled through the long grass on my hands and knees to see what it is like down there. Busy.",
					],
					"bad": [
						"I got turned round in the long grass and came out on the wrong side, a long walk from home.",
						"Something in the long grass moved right beside my foot, and I left faster than I arrived.",
					],
				},
				{
					"id": "grass_room", "label": "made a room in the long grass", "satisfies": "comfort", "minutes": 30,
					"first": "I trampled a round room in the long grass and sat in the middle of it. Nobody could have found me, and I knew exactly where I was.",
					"lines": [
						"I went back to my room in the long grass. The walls had started to stand up again, so I persuaded them.",
						"I sat in my room in the long grass and chewed the sweet end of a stem.",
					],
				},
				{
					"id": "grass_doze", "label": "dozed in the long grass", "satisfies": "energy", "minutes": 40, "hours": [10, 18],
					"lines": [
						"I lay down in the long grass, and the sky was a small blue shape with grass all round it. I slept.",
						"I dozed in the long grass with something ticking beside my ear.",
					],
				},
				{
					"id": "grass_listen", "label": "listened in the long grass", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I stood very still in the long grass and listened and thought.",
						"I sat in the long grass where I couldn't see anything but grass, and thought about the things I can't see.",
					],
				},
			],
			"sights": [
				{"id": "green_jumper", "line": "Something green jumped out of the grass, hit me in the chest and jumped off again. I don't think it meant to.", "hours": [8, 20]},
				{"id": "grass_ball", "line": "A ball of woven grass was hanging between the stems, made so tight I couldn't see how. I left it alone."},
				{"id": "hook_seeds", "line": "I came out with my sleeves covered in small seeds with hooks. They did not want to let go."},
				{"id": "long_ears", "line": "Something brown with long ears sat up in the grass, looked at me, and was gone so fast the grass was still moving afterwards."},
				{"id": "froth_sitter", "line": "One stem had a blob of white froth on it, and inside the froth a tiny green thing, sitting there as if that were normal."},
			],
		},
		{
			"id": "water", "name": "the water", "map": [0.80, 0.66], "kind": "water",
			"opens": 6, "closes": 21, "distance": 3, "residents": [],
			"discover": {
				"from": ["long_grass", "high_ground"],
				"sign": {
					"long_grass": "From the bottom of the long grass I could hear water somewhere, low and steady, like the glowing box but wetter.",
					"high_ground": "From the high ground there is a line of shine across the low end of the land. It moves. I think it is water.",
				},
				"chance": 0.25,
				"blocked": [
					"I went looking for the water and the ground got soft and took my foot. I got it back and went home.",
					"I tried to find the water and found a wall of thorns instead. The water is behind it, laughing.",
					"I went after the water until the sound seemed to be coming from everywhere. I gave up for today.",
					"I got close enough to the water to smell it, cold and green, and then the bank dropped away in front of me.",
					"I looked for the water again and came out exactly where I had started. I don't know how I did that.",
				],
				"found": "I found the water. It is not still: it runs over stones the whole time and never runs out, and it is so clear I can see my feet thinking about it.",
				"wonder": [
					"I keep hearing that water when I am trying to think about something else.",
					"There is water out there and I haven't found it. I thought about that for a while.",
					"I wonder where the water comes from, and where it is going in such a hurry.",
				],
			},
			"activities": [
				{
					"id": "wade", "label": "waded in the water", "satisfies": "curiosity", "minutes": 30, "hours": [8, 20],
					"first": "I put one foot in the water. It was so cold I shouted, and then I put the other one in.",
					"lines": [
						"I stood in the water up to my shins and watched it go round my legs.",
						"I walked up the middle of the water, slowly, feeling for the flat stones with my toes.",
						"I stood in the water until I couldn't feel my feet, and then got out and felt them come back.",
					],
					"bad": [
						"I stepped on a green stone in the water and sat down very suddenly. I walked home dripping.",
						"The water was colder than I remembered, and I got out after about four steps.",
					],
				},
				{
					"id": "turn_stones", "label": "turned over stones at the water", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I turned over stones at the edge of the water. Small things ran out from under every one.",
						"I looked for the roundest stone in the water. I found a rounder one each time I thought I was finished.",
						"I built a small wall of stones across a corner of the water and watched what the water did about it.",
					],
				},
				{
					"id": "water_sit", "label": "sat by the water", "satisfies": "comfort", "minutes": 30,
					"lines": [
						"I sat by the water and let it be loud.",
						"I drank from my hands at the water. It tastes of cold, and a little of stone.",
						"I washed my face and my arms in the water and sat on the bank to dry.",
					],
				},
				{
					"id": "leaf_boats", "label": "floated leaves down the water", "satisfies": "reflection", "minutes": 20,
					"first": "I dropped a leaf in the water and it went. I ran beside it as far as I could, and then it was somewhere I am not.",
					"lines": [
						"I put leaves in the water one at a time and thought about where they end up.",
						"I sat watching the water go past and thought about how it is never the same water.",
					],
				},
			],
			"sights": [
				{"id": "stick_bird", "line": "A tall grey bird was standing in the water, so still I took it for a stick. Then the stick took one step."},
				{"id": "quick_shadows", "line": "There are small quick shadows in the deep part that all turn at once, like one thing with many pieces."},
				{"id": "blue_flash", "line": "Something very blue went down the water faster than I could turn my head. I am not sure I saw it. I want to see it again."},
				{"id": "water_walkers", "line": "Thin things were standing on top of the water as if it were a floor. I tried with one finger. It is not a floor."},
				{"id": "wet_sitter", "line": "A green thing with long back legs sat on a stone looking wet and satisfied. When I leaned closer it wasn't there any more."},
				{"id": "ringed_stone", "line": "I found a dark stone with one white line all the way round it, like a string tied on. It is on the shelf now."},
				{"id": "hanging_colours", "line": "Where the water falls over the biggest stone there were colours hanging in the air, all of them, in a curve.", "hours": [9, 16]},
			],
		},
		{
			"id": "stony_ground", "name": "the stony ground", "map": [0.90, 0.48], "kind": "stones",
			"opens": 6, "closes": 21, "distance": 3, "residents": [],
			"discover": {
				"from": ["water", "high_ground"],
				"sign": {
					"water": "Further up, the water gets louder and the banks turn from earth to stone.",
					"high_ground": "From the high ground there is a pale grey patch off to one side, where nothing seems to grow.",
				},
				"chance": 0.35,
				"blocked": [
					"I set off toward the stones and the way got too steep. I slid back down most of it.",
					"I tried again for the stony place and ended up in a hollow full of stinging plants instead.",
					"I got near enough to the stony place to see the heat shaking above it, and then it was time to turn back.",
				],
				"found": "I got up to where the ground is nothing but stones: big ones, small ones, flat ones, all warm on top and cold underneath.",
				"wonder": [
					"I wonder why nothing grows in that pale grey place.",
					"There is a place that is all stones. I want to see how many.",
				],
			},
			"activities": [
				{
					"id": "pick_stones", "label": "picked through the stones", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I picked through the stones for ones that fit my hand. I kept the best and put the rest back where they were.",
						"I knocked stones together to hear them. Different stones say different things.",
						"I sorted stones by colour until I ran out of colours I have words for.",
					],
				},
				{
					"id": "stone_pile", "label": "piled stones up", "satisfies": "comfort", "minutes": 30,
					"first": "I put a flat stone on a flat stone, and another on that. I got to seven before it changed its mind.",
					"lines": [
						"I piled flat stones on top of each other until the pile was as high as my knee. Then it wasn't.",
						"I laid stones in a ring big enough to sit in, and sat in it.",
					],
				},
				{
					"id": "warm_stone", "label": "lay on the warm stone", "satisfies": "energy", "minutes": 40, "hours": [11, 17],
					"lines": [
						"I lay on the big flat stone. The sun had got there first and left it warm for me.",
						"I fell asleep on the warm stone and woke up with its shape pressed into my cheek.",
					],
				},
				{
					"id": "stone_sit", "label": "sat among the stones", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat among the stones and thought about how long a stone has to wait for anything to happen.",
						"I held one stone in each hand and thought. They are good to think with.",
					],
				},
			],
			"sights": [
				{"id": "tail_basker", "line": "A small thing with a long tail was lying on the warm stone exactly the way I was. It left when I said hello.", "hours": [10, 17]},
				{"id": "curled_stone", "line": "One of the stones has a curled shape pressed into it, as if something went to sleep there and the stone grew round it."},
				{"id": "spark_stone", "line": "I turned a grey stone over and the other side was full of tiny lights, like the night sky but in my hand."},
				{"id": "stone_coats", "line": "Some of the stones are wearing orange and grey patches that don't rub off. I think they are alive, slowly."},
				{"id": "pouring_thing", "line": "Something long and thin with no legs poured itself under a stone as I came up. I did not lift that stone.", "hours": [10, 18]},
			],
		},
		{
			"id": "grey_bank", "name": "the grey bank", "map": [0.80, 0.79], "kind": "bank",
			"opens": 6, "closes": 21, "distance": 3, "residents": [],
			"discover": {
				"from": ["water"],
				"sign": "A little way down the water, the bank is a different colour: grey, and smooth, as if it had been cut with something.",
				"chance": 0.4,
				"blocked": [
					"I went down the water toward the grey place and the bank ran out. I didn't feel like swimming yet.",
					"I tried to get along the bank to the grey place, and a fallen tree was in the way with all its arms out.",
					"I went for the grey place by the high way round and lost the water altogether. I found it again on the way home.",
				],
				"found": "I got to the grey bank. It is not earth and not stone. It is cold and smooth, and it kept the shape of my hand after I took my hand away.",
				"wonder": ["There is a grey place down the water. I wonder why it is a different colour from everything else."],
			},
			"activities": [
				{
					"id": "poke_bank", "label": "pushed my fingers into the grey bank", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I pushed my fingers into the grey bank. It kept the holes after I took my fingers out.",
						"I dug a handful out of the grey bank. Underneath it is the same, all the way in.",
						"I pressed a leaf into the grey bank and peeled it off. The leaf left itself behind.",
					],
				},
				{
					"id": "squeeze_mud", "label": "squeezed the grey mud", "satisfies": "comfort", "minutes": 30,
					"first": "The grey mud holds whatever shape I give it. I made a lump with a thumbprint in it and left it on a stone.",
					"lines": [
						"I squeezed a handful of the grey mud into a ball, and then into a worse ball.",
						"I rolled the grey mud between my hands until I had a long thing, and then didn't know what to do with a long thing.",
						"I made small round lumps of the grey mud and put them in a row along the bank.",
					],
					"bad": [
						"I got the grey mud all over my sleeves, and then all over my face trying to get it off my sleeves.",
						"The grey mud was too wet today and would not hold any shape at all.",
					],
				},
				{
					"id": "bank_sit", "label": "sat on the grey bank", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat on the grey bank with my feet hanging over and thought.",
						"I sat on the grey bank looking at my handprint in it and thought about leaving marks.",
					],
				},
			],
			"sights": [
				{"id": "bank_holes", "line": "There are round holes high in the grey bank, and small birds fly into them without slowing down at all.", "hours": [6, 20]},
				{"id": "small_hands", "line": "Something with hands smaller than mine walked across the wet grey mud in the night and left every finger."},
				{"id": "bank_stripes", "line": "Where the bank is cut I can see it is made of stripes, grey on brown on grey, like a stack of something."},
				{"id": "reaching_root", "line": "A root sticks out of the grey bank into the air, feeling for ground that isn't there any more."},
			],
		},
		{
			"id": "sandy_bend", "name": "the sandy bend", "map": [0.70, 0.88], "kind": "sand",
			"opens": 6, "closes": 21, "distance": 3, "residents": [],
			"discover": {
				"from": ["grey_bank", "water"],
				"sign": {
					"grey_bank": "Just past the grey bank the water turns a corner and goes quiet. There is something pale on the inside of the corner.",
					"water": "Further down, the water turns a corner and goes quiet. There is something pale on the inside of the corner.",
				},
				"chance": 0.4,
				"blocked": [
					"I waded toward the corner in the water and it got deeper than my legs are long. I came back.",
					"I tried to reach the pale place along the bank, and it was all roots and holes. I turned round.",
					"I set off for the pale place and stopped to watch something in the water for so long that I ran out of day.",
				],
				"found": "On the inside of the corner the water has left a heap of sand, pale and fine and warm. I took my feet out of the water and put them in it.",
				"wonder": ["I wonder what the pale thing at the corner of the water is."],
			},
			"activities": [
				{
					"id": "sand_draw", "label": "drew in the sand", "satisfies": "comfort", "minutes": 30,
					"first": "I pulled a stick through the sand and it left a line. I made a lot of lines. Then I made a shape, and looked at it for a while.",
					"lines": [
						"I drew lines in the sand with a stick. The water came up and took the lowest ones.",
						"I drew my house in the sand. It is not very like, but I knew what I meant.",
						"I drew the biggest circle I could in the sand and stood in the middle of it.",
					],
				},
				{
					"id": "sand_dig", "label": "dug in the sand", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I dug a hole in the sand until water came up into it from underneath. I don't know why it does that.",
						"I let the dry sand run out of my fist in a thin line and tried to count it. No.",
						"I buried my feet in the sand and then looked for them.",
					],
				},
				{
					"id": "sand_lie", "label": "lay on the warm sand", "satisfies": "energy", "minutes": 40, "hours": [11, 17],
					"lines": [
						"I lay on the warm sand with my feet in the water and went to sleep in two temperatures.",
						"I dozed on the sand and woke up with some of it stuck to me.",
					],
				},
				{
					"id": "sand_sit", "label": "sat on the sand", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I sat on the sand where the water is quiet and thought.",
						"I sat on the sand looking at my own footprints and thought about which way I had come.",
					],
				},
			],
			"sights": [
				{"id": "cupped_shiner", "line": "Half of a dark hard thing, shaped like a cupped hand, was lying in the sand, shining inside like the sky just after rain."},
				{"id": "three_toes", "line": "Three-toed marks go across the sand in a line, turn round, and come back. Somebody changed their mind."},
				{"id": "clear_wings", "line": "A long thin thing with four clear wings landed on my knee and stayed. I didn't breathe until it left.", "hours": [9, 18]},
				{"id": "smooth_wood", "line": "The water left a piece of wood on the sand, worn so smooth it feels like something soft."},
				{"id": "bubble_holes", "line": "There are tiny holes in the wet sand that blow one bubble each when the water comes over them."},
			],
		},
		{
			"id": "tall_reeds", "name": "the whispering grass", "map": [0.55, 0.93], "kind": "reeds",
			"opens": 6, "closes": 21, "distance": 3, "residents": [],
			"discover": {
				"from": ["long_grass", "sandy_bend"],
				"sign": {
					"long_grass": "Beyond the long grass there is taller grass still, with brown tops. It whispers even when I can't feel any wind.",
					"sandy_bend": "Past the sandy bend the water spreads out among tall thin stems with brown tops. They whisper to each other the whole time.",
				},
				"chance": 0.3,
				"blocked": [
					"I walked toward the whispering and the ground began to shake under me like something not finished. I went back to where it was solid.",
					"I tried for the tall stems and went in over one ankle. The ground there is mostly water wearing a coat.",
					"I went round the soft ground to get at the tall stems from the other side. The other side is soft too.",
					"I laid a branch across the soft ground and walked along it toward the tall stems. It was a shorter branch than I needed.",
				],
				"found": "I got in among the tall stems with the brown tops. They are higher than my door and they whisper the whole time, and the ground between them isn't sure about being ground.",
				"wonder": [
					"Something out there whispers when there is no wind. I want to know what it is saying.",
					"I keep thinking about the tall grass with the brown tops.",
				],
			},
			"activities": [
				{
					"id": "reed_push", "label": "went into the whispering grass", "satisfies": "curiosity", "minutes": 30,
					"lines": [
						"I went a few steps into the whispering grass. The ground pulled at my feet and I came back with one of them heavier than the other.",
						"I parted the stems and looked into the whispering grass. It is the same all the way in, and it is all looking back.",
						"I shook one of the brown tops and it came apart into a cloud of soft bits that went off on the air.",
					],
				},
				{
					"id": "stem_blow", "label": "blew across a hollow stem", "satisfies": "comfort", "minutes": 20,
					"first": "I pulled up one of the tall stems. It is hollow. When I blew across the end it made a sound, low and round, like the wind in a doorway. I did it again.",
					"lines": [
						"I blew across the end of a hollow stem. A short one sounds higher than a long one. I did not expect that.",
						"I sat and made the low sound with a hollow stem until something in the whispering grass answered. I stopped then.",
					],
				},
				{
					"id": "reed_evening", "label": "watched the birds come in to sleep", "satisfies": "comfort", "minutes": 30, "hours": [17, 21],
					"lines": [
						"I watched small birds drop into the whispering grass to sleep, one after another, until the whole of it was full of them.",
						"I sat by the whispering grass while it got dim. Everything in there was settling down and saying so.",
					],
				},
				{
					"id": "reed_listen", "label": "listened to the whispering grass", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I stood at the edge of the whispering grass and listened. It says the same thing over and over and I still don't know what.",
						"I sat by the whispering grass and thought, with it talking over me the whole time.",
					],
				},
			],
			"sights": [
				{"id": "seven_followers", "line": "A brown bird came out of the stems onto the water with seven small ones behind her in a line. I counted twice.", "hours": [6, 20]},
				{"id": "dotted_wobble", "line": "There is a lump of something clear and wobbling in the shallow water, full of black dots. Some of the dots moved."},
				{"id": "deep_breath", "line": "From deep in the whispering grass came one low sound, like something very big breathing out. Nothing else happened."},
				{"id": "blue_needle", "line": "A thin blue thing like a needle with wings was holding on to a stem, and then it was holding on to a different stem.", "hours": [9, 18]},
				{"id": "stem_cup", "line": "A small deep cup of grass is tied between three stems, high up, swaying with them. There was something in it."},
			],
		},
		{
			"id": "dark_trees", "name": "the dark trees", "map": [0.90, 0.14], "kind": "woods",
			"opens": 7, "closes": 19, "distance": 4, "residents": [],
			"discover": {
				"from": ["high_ground", "stony_ground"],
				"sign": {
					"high_ground": "From the high ground there is a dark line along the far edge of everything. Trees, I think, standing very close together.",
					"stony_ground": "Past the stony ground the land goes dark. It is trees, a great many of them, with no light between.",
				},
				"chance": 0.05,
				"blocked": [
					"I walked toward the dark trees until the thorny tangle started. It took hold of my sleeve and I gave up.",
					"I tried to get through the thorny tangle in front of the dark trees. Not yet.",
					"I went along the thorny tangle looking for a way through to the dark trees. There is one somewhere. I didn't find it.",
					"I got further into the thorny tangle than before, and then had to come all the way back out, backwards.",
					"I tried crawling under the thorny tangle. It is just as thorny underneath, and lower.",
					"I threw a stick over the thorny tangle to see how deep it goes. I didn't hear it land.",
					"I found a gap in the thorny tangle that something smaller than me uses. I got my head and one arm through.",
					"I pushed a little further into the thorny tangle than yesterday. It gives a little more each time.",
				],
				"found": "I found the way through the thorny tangle. In among the dark trees it is brown and quiet, and my feet make no sound at all, and the air smells sharp and sweet.",
				"wonder": [
					"I keep thinking about that dark line of trees.",
					"I wonder what it is like in among the dark trees, where the light doesn't go.",
					"There is a way through that thorny tangle. There has to be.",
				],
			},
			"activities": [
				{
					"id": "step_in", "label": "went in among the dark trees", "satisfies": "curiosity", "minutes": 30,
					"first": "I went into the dark trees as far as I could still see the light behind me. Then I went three steps further, and came back.",
					"lines": [
						"I went in among the dark trees and looked up. The tops are so far away they might be something else.",
						"I looked at what falls from the dark trees: brown needles, and hard little shapes like closed fists.",
						"I walked between the trunks touching each one. They are rough, and some of them are crying something sticky.",
					],
					"bad": [
						"I went in among the dark trees and something cracked behind me. I came out faster than I went in.",
						"It was too quiet in the dark trees today. I stayed where the light was.",
					],
				},
				{
					"id": "moss_sit", "label": "sat on the soft green", "satisfies": "comfort", "minutes": 30,
					"lines": [
						"I sat on the thick green stuff that grows on the ground in the dark trees like a blanket.",
						"I lay on the brown needles under the dark trees. It is the softest floor I have found.",
					],
				},
				{
					"id": "edge_stand", "label": "stood in the dark trees", "satisfies": "reflection", "minutes": 20,
					"lines": [
						"I stood just inside the dark trees and thought. It is a different kind of quiet in there.",
						"I leaned on a trunk in the dark trees and thought about how they have all agreed to stand so close.",
					],
				},
			],
			"sights": [
				{"id": "thin_legs", "line": "Something tall and brown on thin legs was standing between the trunks. It looked at me for one breath, and then there were only trunks."},
				{"id": "two_notes", "line": "Something called from inside the dark trees, two notes, like a question. Nobody answered, so I did.", "hours": [16, 19]},
				{"id": "pale_ring", "line": "There is a ring of small pale things growing out of the ground, each with a little roof. I walked round it, not through."},
				{"id": "green_log", "line": "A fallen trunk is lying in there covered all over in green, so soft my hand sank into it."},
				{"id": "root_door", "line": "Between two roots there is a hole going down, with the earth worn smooth at the front like a doorstep."},
				{"id": "red_top", "line": "High on a trunk a bird with a red head was hitting the tree with its face, very fast, as if that were a sensible thing to do."},
			],
		},
	],
}
