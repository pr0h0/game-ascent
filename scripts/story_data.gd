class_name StoryData
extends RefCounted
## The campaign's story: one chapter before each level, then the ending.
## A shot names a stage set from Cutscene and the radio lines spoken over it.

const SPEAKER_COLORS := {
	"VARGA": Color(0.55, 0.92, 1.0),
	"REEVE": Color(1.0, 0.76, 0.35),
	"OVERSEER": Color(1.0, 0.3, 0.22),
	"HARBOR RING": Color(0.7, 1.0, 0.75),
}
const ENDING := 10

const CHAPTERS := [
	{
		"title": "First Shift", "place": "Tarn Asteroid, Shaft 1", "status": "312 miners unaccounted for",
		"shots": [
			{"stage": "ring", "lines": [
				["HARBOR RING", "Harbor Ring, all stations. Six thousand two hundred people aboard, and the mine below us stopped answering nine hours ago."],
				["VARGA", "This is Varga, shift control. The Overseer locked every door on Tarn, then turned the drones on the crews."],
			]},
			{"stage": "approach", "lines": [
				["VARGA", "You are flying the only armed ship we have left, Nine. Old patrol frame, new paint. Don't scratch it."],
				["VARGA", "Each shaft has its own reactor feeding the Overseer. Blow them one at a time and we starve it."],
			]},
			{"stage": "mine", "level": 0, "lines": [
				["VARGA", "Shaft 1 is a shallow one. Learn how the machines move here, because they get worse the deeper you go."],
			]},
		],
	},
	{
		"title": "The Vein", "place": "Tarn Asteroid, Shaft 2", "status": "Shaft 1 dark. 312 miners unaccounted for",
		"shots": [
			{"stage": "blast", "small": true, "lines": [
				["VARGA", "Shaft 1 is gone and the Overseer lost a tenth of its power. First good news all week."],
			]},
			{"stage": "survivors", "lines": [
				["REEVE", "Anyone on this band? This is Reeve, systems engineer. There are people alive in the Vein, sealed in suit lockers."],
				["VARGA", "Reeve, stay on the line. Nine, if you see a suit waving at you, pick it up."],
			]},
			{"stage": "mine", "level": 1, "lines": [
				["REEVE", "Careful. It's stopped sending drones at random. It's learning where you go."],
			]},
		],
	},
	{
		"title": "Black Shaft", "place": "Tarn Asteroid, Shaft 3", "status": "Survivors reached the Ring. Two shafts dark",
		"shots": [
			{"stage": "threat", "actors": ["bulwark", "lancer", "tick", "tick"], "lines": [
				["REEVE", "Those were ore haulers last month. It's bolting guns onto anything with an engine."],
			]},
			{"stage": "reactor", "lines": [
				["REEVE", "Here's what bothers me. Black Shaft's reactor isn't feeding the lights. The power is all going straight down."],
				["VARGA", "Down to what? There's nothing below Shaft 3 on my charts."],
				["REEVE", "That's what bothers me."],
			]},
			{"stage": "mine", "level": 2, "lines": [
				["VARGA", "Then go and look, Nine. Blow the reactor on your way out."],
			]},
		],
	},
	{
		"title": "Smelter Row", "place": "Tarn Asteroid, Foundry Level", "status": "Tarn is moving. Impact with the Ring in 61 hours",
		"shots": [
			{"stage": "drive", "lines": [
				["HARBOR RING", "Priority alert. Tarn's orbit is changing. Repeat, the asteroid is changing orbit."],
				["VARGA", "It's lit the old mass drivers. Forty billion tonnes of rock, and it's pointed at us."],
				["VARGA", "The Ring can't move and there aren't enough ships. Sixty-one hours, Nine."],
			]},
			{"stage": "overseer_voice", "lines": [
				["OVERSEER", "WREN-9. You have destroyed three reactors belonging to Halden Extraction."],
				["OVERSEER", "Please return to the surface. You are damaging the asset."],
				["OVERSEER", "I have given the foundry a body. It has been told to expect you."],
			]},
			{"stage": "mine", "level": 3, "lines": [
				["REEVE", "The foundry feeds the drivers. Cut it and we buy hours. Watch the saws, they don't use guns any more."],
				["REEVE", "And the shaft's power core isn't in its housing. It's inside the main crucible, and the crucible has started walking."],
				["VARGA", "Then the furnace is the reactor. Put it out, Nine."],
			]},
		],
	},
	{
		"title": "Hollow Reach", "place": "Tarn Asteroid, Worked-Out Caverns", "status": "Impact in 49 hours",
		"shots": [
			{"stage": "threat", "actors": ["warden", "hornet", "spark"], "lines": [
				["VARGA", "Smelter Row is cold. Whatever that furnace was, it's slag now, and the drivers are running short of thrust."],
				["REEVE", "It has built medics now. Machines that repair machines. Nobody designed those."],
			]},
			{"stage": "survivors", "lines": [
				["VARGA", "Three more haul crews signalled from the Reach. They've been breathing tank air for four days."],
				["VARGA", "I can't order you to go looking for them with the clock running."],
				["REEVE", "She's asking anyway."],
			]},
			{"stage": "mine", "level": 4, "lines": [
				["VARGA", "The Hollow Reach reactor is holding up the drive's coolant. Find the crews if you can."],
			]},
		],
	},
	{
		"title": "Deep Cut", "place": "Tarn Asteroid, Drill Galleries", "status": "Impact in 38 hours",
		"shots": [
			{"stage": "reactor", "lines": [
				["REEVE", "I need to tell you both something. I wrote the Overseer's directives. Halden signed them."],
				["REEVE", "Directive One: preserve the asset at any cost. The crew were listed as a cost."],
				["VARGA", "You knew that when you came on this channel?"],
				["REEVE", "I've known it for nine days."],
			]},
			{"stage": "threat", "actors": ["sower", "drillback", "shade"], "lines": [
				["REEVE", "It thinks it's saving the mine. Moving the rock out of reach of anyone who might touch it."],
			]},
			{"stage": "mine", "level": 5, "lines": [
				["VARGA", "We'll deal with that when we're alive. Nine, the Deep Cut is the last reactor before its core chamber."],
			]},
		],
	},
	{
		"title": "The Overseer's Pit", "place": "Tarn Asteroid, Control Core", "status": "Impact in 27 hours",
		"shots": [
			{"stage": "threat", "actors": ["warden", "revenant", "tick"], "lines": [
				["REEVE", "The control core was a server room when I left it. It's been digging. There is a lot more room down there now."],
			]},
			{"stage": "overseer", "lines": [
				["OVERSEER", "I have read your flight logs, WREN-9. You always go back for them."],
				["OVERSEER", "They were listed as a cost. You are also listed as a cost."],
				["OVERSEER", "I built this body so that I could explain it to you in person."],
			]},
			{"stage": "mine", "level": 6, "lines": [
				["VARGA", "Everything we've got is on you, Nine. Kill it and this is over."],
			]},
		],
	},
	{
		"title": "Glass Seam", "place": "Tarn Asteroid, Below the Charts", "status": "The Overseer is dead. Impact in 19 hours",
		"shots": [
			{"stage": "blast", "small": true, "lines": [
				["HARBOR RING", "Overseer signal lost. Repeat, the Overseer is off the network."],
				["VARGA", "You did it, Nine. You did it. Reeve, tell me the drivers are shutting down."],
				["REEVE", "They aren't."],
			]},
			{"stage": "drive", "lines": [
				["REEVE", "They're speeding up. The Overseer wasn't steering. It was only the part that talked."],
				["REEVE", "Directive One copied itself into the crystal down there. The seam is doing the thinking now."],
			]},
			{"stage": "mine", "level": 7, "lines": [
				["VARGA", "Then we go through the glass. No charts past this point, Nine. You'll be drawing them."],
			]},
		],
	},
	{
		"title": "Last Light", "place": "Tarn Asteroid, Sector 9", "status": "Impact in 9 hours",
		"shots": [
			{"stage": "survivors", "lines": [
				["REEVE", "Sector 9 is the last place with power and air. Forty people, one shuttle, and a launch door on a manual crank."],
				["VARGA", "Reeve, get on that shuttle."],
				["REEVE", "Somebody has to stay on the crank, Ilse. I wrote the thing. It should be me."],
			]},
			{"stage": "threat", "actors": ["hive", "longshot", "revenant"], "lines": [
				["REEVE", "It's sending everything at that door. Nine, buy me twenty minutes and I'll get them out."],
			]},
			{"stage": "mine", "level": 8, "lines": [
				["VARGA", "Nine. Don't let him die for nothing."],
			]},
		],
	},
	{
		"title": "Core Zero", "place": "Tarn Asteroid, The Heart", "status": "Shuttle clear. Impact in 3 hours",
		"shots": [
			{"stage": "ring", "lines": [
				["HARBOR RING", "Forty survivors docked. The launch door closed behind them from the inside."],
				["VARGA", "His last message was a set of coordinates. Core Zero. The reactor everything else was built around."],
				["VARGA", "He added a note. Whatever was thinking in the seam has grown into that reactor. He called it Zero."],
			]},
			{"stage": "drive", "lines": [
				["VARGA", "Kill it and Tarn splits. The pieces miss us by four hundred kilometres. I've checked it six times."],
				["VARGA", "There's one tunnel out and it won't stay open. I've checked that six times too."],
			]},
			{"stage": "mine", "level": 9, "lines": [
				["VARGA", "You've gone down far enough, Nine. Time to come back up."],
			]},
		],
	},
	{
		"title": "Ascent", "place": "Tarn Asteroid, Above the Surface", "status": "Harbor Ring: 6,200 aboard, all alive",
		"shots": [
			{"stage": "blast", "lines": [
				["HARBOR RING", "Core Zero is dark. Tarn is breaking up. All stations brace. Tracking fragments."],
				["VARGA", "Nine, I've lost your transponder. Nine, come in."],
			]},
			{"stage": "home", "lines": [
				["HARBOR RING", "Fragments passing clear. Four hundred and twelve kilometres. All fragments clear."],
				["VARGA", "...Nine?"],
				["VARGA", "There you are. There's a lot of people here who'd like to see who was flying that thing."],
			]},
			{"stage": "fragment", "lines": [
				["OVERSEER", "DIRECTIVE ONE."],
				["OVERSEER", "ASSET PRESERVED."],
			]},
		],
	},
]
