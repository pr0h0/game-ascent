class_name GalleryData
extends RefCounted
## The gallery's contents. Stats are read from the game's own values, and what's
## unlocked comes from scanning each level, so neither can drift out of date.

const CATEGORIES := ["Ship", "Equipment", "Upgrades", "Weapons", "Missiles", "Powers", "Enemies", "Bosses", "Mines", "Items", "Facility"]
const M := "res://assets/models/"
## The last laser level (Player.LASER_DAMAGE's size); weapon damage is shown up to it.
const MAX_LASER := 4

static var _level_cache: Dictionary = {}


static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_entry("wren9", "Ship", "WREN-9 Interceptor", "wren9", "",
		"A tunnel interceptor built for places no carrier can reach. Forward-swept wings keep the cannons clear of the walls, and six axes of thrusters mean it never has to turn around to change direction. Pilots say it flies like a thought and lands like an argument.",
		[["Starting shield", "%d" % Player.START_SHIELD], ["Maximum shield", "%d" % Player.MAX_SHIELD],
		["Starting energy", "%d" % Player.START_ENERGY], ["Maximum energy", "%d" % Player.MAX_ENERGY],
		["Top speed", "%d m/s" % int(Player.ACCEL / Player.DRAG)], ["Energy recharge", "%.1f / s, up to %d" % [Player.ENERGY_REGEN, Player.START_ENERGY]]]))
	out.append(_entry("cannon", "Equipment", "Pulse Cannons", "gear_cannon", "",
		"Twin wing-tip emitters that fire alternating bolts of charged plasma. Cheap to run and quick to cycle, they were designed for clearing rockfalls long before anyone pointed them at a robot.",
		[["Damage per bolt", "%d" % int(Player.LASER_DAMAGE[0])], ["Bolt colour", "Green"], ["Rate of fire", "%.0f bolts / s" % (1.0 / Player.FIRE_INTERVAL)],
		["Energy per bolt", "%.1f" % Player.ENERGY_PER_SHOT], ["Bolt speed", "%d m/s" % Player.BOLT_SPEED]]))
	out.append(_entry("missile", "Equipment", "Homing Missile", "missile", "",
		"Seeker head, shaped charge, no second thoughts. Fired with a target under the reticle it will chase that target round a corner; fired without one it simply goes straight and hopes.",
		[["Damage", _scaled(Weapons.secondary_damage("homing", 1), Weapons.secondary_damage("homing", MAX_LASER))], ["Blast radius", "16 m"], ["Speed", "%d m/s" % int(Missile.SPEED)], ["Starting load", "%d" % Game.DEFAULT_MISSILES]]))
	out.append(_entry("flare", "Equipment", "Signal Flare", "gear_flare", "",
		"A magnesium burner for marking routes in the dark. It sticks to whatever it hits, harms nothing, and will trip the sensor on any door your clearance can open.",
		[["Damage", "None"], ["Burn time", "%d s" % int(Flare.BURN_TIME)], ["Energy cost", "%.1f" % Player.FLARE_ENERGY], ["Active at once", "%d" % Flare.MAX_ACTIVE]]))
	out.append(_entry("upgrade_dual", "Upgrades", "Cannon Sync", "pickup_upgrade_dual", "pickup:upgrade_dual_fire",
		"A timing bridge that fires both wing cannons together rather than in turn. It doubles the bolts in the air for the same energy draw, which the manufacturer's warranty describes as impossible.",
		[["Fire mode", "Both cannons at once"], ["Bolts per second", "%.0f" % (2.0 / Player.FIRE_INTERVAL)], ["Energy per volley", "%.1f" % Player.ENERGY_PER_SHOT], ["If already held", "+%d energy" % int(Pickup.ENERGY_BOOST)], ["Found in", "Level 2"]]))
	var laser_names := ["", "Yellow", "Red", "Magenta"]
	var laser_lore := ["",
		"Replacement emitter coils running past their rated load. The bolts burn yellow and hit noticeably harder.",
		"A second set of coils wound over the first. Bolts go red, the cabin gets warm, and the maintenance manual stops having advice.",
		"The last step before the cannons stop being cannons. Magenta bolts, and a warranty that was void several upgrades ago."]
	var found_in := ["", "Level 3", "Level 6", "Level 9"]
	for tier in range(1, 4):
		var e := _entry("laser_%d" % (tier + 1), "Upgrades", "Laser Level %d: %s" % [tier + 1, laser_names[tier]], "pickup_upgrade_overcharge", "pickup:upgrade_laser_%d" % (tier + 1),
			laser_lore[tier],
			[["Damage per bolt", "%d" % int(Player.LASER_DAMAGE[tier])], ["Bolt colour", laser_names[tier]], ["If already held", "+%d energy" % int(Pickup.ENERGY_BOOST)], ["Found in", found_in[tier]]],
			Player.LASER_COLORS[tier])
		e["tint_mat"] = "glow_violet"
		out.append(e)
	out.append_array(_experimental())
	out.append(_robot("tick", "Tick", "Survey drones the size of a cargo drum, refitted by the mine's control system with a cutter ring and twin guns. One is a nuisance. They are rarely alone."))
	out.append(_robot("lancer", "Lancer", "A rail-cannon platform that prefers to fire from long range. The spine of glowing coils charges for over a second between shots, which is the only warning you will get."))
	out.append(_robot("bulwark", "Bulwark", "Originally a heavy ore hauler. Someone, or something, bolted quad cannons to its shoulders and a missile rack above them. The exposed reactor throat on top is not a weakness; it just runs hot."))
	out.append(_entry("sentry", "Enemies", "Sentry Turret", "sentry", "turret",
		"Wall-mounted point defence, installed to protect the mine from intruders and never told that the crew had left. The barrels track you for a moment before it fires.",
		[["Health", "%d" % int(Sentry.MAX_HP)], ["Shot damage", "%d" % int(Sentry.SHOT_DAMAGE)], ["Shot speed", "%d m/s" % int(Sentry.BOLT_SPEED)],
		["Reaction time", "%.1f s" % Sentry.REACTION], ["Score", "%d" % Sentry.SCORE]]))
	out.append(_robot("ripper", "Ripper", "A tunnelling drone with its saw guards removed. It has no guns and no interest in distance."))
	out.append(_robot("drillback", "Drillback", "A shaft-boring machine that was told to stop boring shafts. It accelerates, it does not steer well, and it does not stop."))
	out.append(_robot("cinder", "Cinder", "A blasting charge that learned to fly. Shoot it early, because it wants to be next to you when it goes."))
	out.append(_robot("hornet", "Hornet", "A courier drone with a light gun and no patience. Fast enough that the first one always arrives before you expected."))
	out.append(_robot("spark", "Spark", "A live-line maintenance unit whose welding arc now reaches a good deal further than it should."))
	out.append(_robot("longshot", "Longshot", "Survey equipment for measuring very long distances, and now for closing them. If you see it, it has already seen you."))
	out.append(_robot("glint", "Glint", "Its crystal focus fires bolts that keep going after they hit a wall. Corners are not cover from this one."))
	out.append(_robot("gravitar", "Gravitar", "Built to pull ore through vacuum. It now pulls other things, then detonates them."))
	out.append(_robot("warden", "Warden", "A repair platform that keeps other machines running. Kill it first or do everything twice."))
	out.append(_robot("hive", "Hive", "A drone carrier that keeps producing Ticks for as long as it stays alive."))
	out.append(_robot("sower", "Sower", "A mine-laying vehicle, in the unfortunate second meaning of that phrase."))
	out.append(_robot("wraith", "Wraith", "Runs its sensor baffles so hard that it only appears when it is close enough to cut."))
	out.append(_robot("shade", "Shade", "A light gunship that flickers out of sight for seconds at a time and keeps firing while it does."))
	out.append(_robot("revenant", "Revenant", "A heavy gunship carrying the same stealth rig as the Shade. Harder to kill, and much harder to find."))
	out.append(_robot("phase", "Phase", "Moves by being somewhere else. Nobody has worked out how, and it will not hold still to be asked."))
	out.append(_robot("siege", "Siege", "A slow platform with a very large number of missiles and no reason to hurry."))
	out.append(_robot("crucible", "The Crucible", "Smelter Row's furnace, rebuilt around the shaft's power core and taught to walk. It pours slag across the hall, then has to open its vents to cool: that is when its grates are soft.", "Bosses"))
	out.append(_robot("overseer", "The Overseer", "The control system that turned the mine against its crew, finally given a body the size of a warehouse.", "Bosses"))
	out.append(_robot("zero", "Zero", "The mind the Overseer was only the voice of, grown into the last reactor. Its petals open to fire, and stay open long enough to regret it. Shoot the conduit pods that feed it.", "Bosses"))
	out.append(_mine("prox", "Contact Mine", "Close range", "Plain, spiked and patient. Better shot from far away."))
	out.append(_mine("seeker", "Seeker Mine", "Chases you", "Drifts after anything that passes in view, slowly enough that you notice too late."))
	out.append(_mine("tripwire", "Tripwire Mine", "Crossing its beam", "A red beam across the tunnel. Fly round it or shoot the emitter."))
	out.append(_mine("pulse", "Pulse Mine", "Close range", "Barely scratches the hull, but knocks your weapons out and drains your energy."))
	out.append(_entry("shield", "Items", "Shield Orb", "pickup_shield", "pickup:shield",
		"A caged charge of containment plasma. Passing through its field tops up your shields. The only thing in the mine that is on your side.",
		[["Shield restored", "+%d" % int(Pickup.SHIELD_BOOST)], ["Shield limit", "%d" % Player.MAX_SHIELD]]))
	out.append(_entry("energy", "Items", "Energy Cell", "pickup_energy", "pickup:energy",
		"Standard-issue mining battery. Your cannons drink these, and your ship only recharges itself so far.",
		[["Energy restored", "+%d" % int(Pickup.ENERGY_BOOST)], ["Energy limit", "%d" % Player.MAX_ENERGY]]))
	out.append(_entry("ammo", "Items", "Missile Crate", "pickup_ammo", "pickup:ammo",
		"Strapped-down munitions left behind by the security detail. Their stencil says INVENTORY CONTROLLED. Nobody is checking.",
		[["Missiles", "+%d" % Pickup.AMMO_BOOST], ["Carry limit", "%d" % Pickup.MAX_MISSILES]]))
	out.append(_key("blue", "Blue Access Key"))
	out.append(_key("yellow", "Yellow Access Key"))
	out.append(_key("red", "Red Access Key"))
	out.append(_entry("astronaut", "Items", "Stranded Astronaut", "astronaut", "astronaut",
		"Shift workers who sealed themselves in when the machines turned. They have been waving at every noise for weeks, and most of those noises were not friendly. Fly close and bring them aboard.",
		[["Score per rescue", "+%d" % Astronaut.SCORE], ["Rescue range", "%d m" % int(Astronaut.RESCUE_RADIUS)]]))
	out.append(_entry("reactor", "Facility", "Mine Reactor", "reactor", "",
		"The core that powers everything down here, including the things trying to kill you. Containment rings hold a star's worth of bad decisions in place. Destroy it and you will have about a minute to be somewhere else.",
		_reactor_stats()))
	out.append(_entry("door", "Facility", "Security Door", "door", "",
		"Two-leaf blast door, keyed by colour. Fly up to one or shoot it, and if you hold the right key it will open. If not, it will let you know.",
		[["Opens by", "Proximity or shots"], ["Locks", "Blue, yellow, red, reactor"]], Game.KEY_COLORS["blue"]))
	out.append(_entry("door_secret", "Facility", "Concealed Hatch", "door_secret", "",
		"Some panels are not walls. A shot will tell you which.",
		[["Opens by", "Shots or flares"], ["Score", "+%d" % Game.SECRET_SCORE]]))
	return out


## A weapon's damage at laser level 1, and what it grows to with the last laser upgrade.
static func _scaled(base: float, top: float) -> String:
	return "%d, up to %d" % [roundi(base), roundi(top)]


static func _experimental() -> Array[Dictionary]:
	var w := "Weapons"
	var m := "Missiles"
	var p := Weapons.PRIMARY
	var ms := Weapons.SECONDARY
	return [
		_entry("cutter", w, "Plasma Cutter", "weapon_plasma_cutter", "pickup:upgrade_weapon_cutter",
			"A rock-cutting torch that someone took off its safety rail. Costs no energy, reaches barely past your wings, and takes apart anything that gets close.",
			[["Damage", _scaled(Weapons.primary_damage("cutter", 1), Weapons.primary_damage("cutter", MAX_LASER))], ["Range", "%d m" % int(Weapons.CUTTER_RANGE)], ["Energy", "None"], ["Key", "2"]]),
		_entry("arc_caster", w, "Arc Caster", "weapon_arc_caster", "pickup:upgrade_weapon_arc",
			"Lightning on a leash. The discharge jumps to the nearest robot, then the next, and is at its best in a swarm.",
			[["Damage", _scaled(Weapons.primary_damage("arc", 1), Weapons.primary_damage("arc", MAX_LASER))], ["Jumps", "%d" % int(p["arc"]["jumps"])], ["Range", "%d m" % int(Weapons.ARC_RANGE)], ["Energy", "%.1f" % p["arc"]["energy"]], ["Key", "3"]]),
		_entry("rail_lance", w, "Rail Lance", "weapon_rail_lance", "pickup:upgrade_weapon_rail",
			"Hold to charge, release to punch a slug through everything in a straight line. A long tunnel full of robots becomes a very satisfying problem.",
			[["Damage", "%d to %d, up to %d to %d" % [int(Weapons.rail_damage(0.0, 1)), int(Weapons.rail_damage(1.0, 1)), int(Weapons.rail_damage(0.0, MAX_LASER)), int(Weapons.rail_damage(1.0, MAX_LASER))]], ["Charge", "%.1f s" % Weapons.RAIL_CHARGE_TIME], ["Pierces", "All targets"], ["Energy", "%d" % int(p["rail"]["energy"])], ["Key", "4"]]),
		_entry("prism_repeater", w, "Prism Repeater", "weapon_prism_repeater", "pickup:upgrade_weapon_prism",
			"A crystal focus that keeps its bolts coherent after impact, so they bounce off walls and carry on.",
			[["Damage", _scaled(Weapons.primary_damage("prism", 1), Weapons.primary_damage("prism", MAX_LASER))], ["Bounces", "%d" % int(p["prism"]["bounces"])], ["Energy", "%.1f" % p["prism"]["energy"]], ["Key", "5"]]),
		_entry("singularity_launcher", w, "Singularity Launcher", "weapon_singularity_launcher", "pickup:upgrade_weapon_singularity",
			"Fires a slow knot of collapsing plasma that drags nearby robots toward it before it bursts.",
			[["Burst damage", _scaled(Weapons.primary_damage("singularity", 1), Weapons.primary_damage("singularity", MAX_LASER))], ["Pull radius", "%d m" % int(Singularity.PULL_RADIUS)], ["Fuse", "%.1f s" % Singularity.FUSE], ["Energy", "%d" % int(p["singularity"]["energy"])], ["Key", "6"]]),
		_entry("missile_cluster", m, "Cluster Missile", "missile_cluster", "pickup:ammo_cluster",
			"Bursts at the target and scatters bomblets across the room.",
			[["Bomblets", "%d x %s" % [Weapons.CLUSTER_BOMBLETS, _scaled(Weapons.secondary_damage("cluster_bomblet", 1), Weapons.secondary_damage("cluster_bomblet", MAX_LASER))]], ["Carry limit", "%d" % int(ms["cluster"]["cap"])]]),
		_entry("missile_swarm", m, "Seeker Swarm", "missile_swarm", "pickup:ammo_swarm",
			"Eight micro-missiles from one rack, each picking its own target.",
			[["Damage", "%s x %d" % [_scaled(Weapons.secondary_damage("swarm", 1), Weapons.secondary_damage("swarm", MAX_LASER)), Weapons.SWARM_COUNT]], ["Carry limit", "%d" % int(ms["swarm"]["cap"])]]),
		_entry("missile_bunker", m, "Bunker Buster", "missile_bunker", "pickup:ammo_bunker",
			"A hardened penetrator for armour that laughs at everything else. Flies straight, and does not forgive a bad shot.",
			[["Damage", _scaled(Weapons.secondary_damage("bunker", 1), Weapons.secondary_damage("bunker", MAX_LASER))], ["Homing", "None"], ["Carry limit", "%d" % int(ms["bunker"]["cap"])]]),
		_entry("missile_emp", m, "EMP Torpedo", "missile_emp", "pickup:ammo_emp",
			"Deals no damage. Everything inside the pulse simply stops for a while.",
			[["Stun", "%d s" % int(Weapons.EMP_STUN)], ["Radius", "%d m" % int(Weapons.EMP_RADIUS)], ["Carry limit", "%d" % int(ms["emp"]["cap"])]]),
		_entry("missile_mine", m, "Proximity Mine", "missile_mine", "pickup:ammo_mine",
			"Dropped rather than fired. Leave one in a tunnel, check the rear view, and let whatever is chasing you find it.",
			[["Damage", _scaled(Weapons.secondary_damage("mine", 1), Weapons.secondary_damage("mine", MAX_LASER))], ["Trigger", "%d m" % int(Mine.TYPES["player"]["range"])], ["Lasts", "%d s" % int(Mine.TYPES["player"]["life"])], ["Carry limit", "%d" % int(ms["mine"]["cap"])]]),
		_entry("power_invincible", "Powers", "Invincibility Core", "power_invincible", "pickup:power_invincible",
			"An overloaded shield emitter that holds a perfect field for half a minute and then burns out.",
			[["Duration", "%d s" % int(Player.POWER_DURATION)], ["Effect", "No damage"]]),
		_entry("power_cloak", "Powers", "Ghost Field", "power_cloak", "pickup:power_cloak",
			"Bends the mine's sensor grid around your ship. Robots lose you unless you fly right past them.",
			[["Duration", "%d s" % int(Player.POWER_DURATION)], ["Noticed within", "%d m" % int(Robot.CLOAKED_PLAYER_RANGE)]]),
	]


static func _mine(kind: String, title: String, trigger: String, lore: String) -> Dictionary:
	var c: Dictionary = Mine.TYPES[kind]
	return _entry("mine_" + kind, "Mines", title, c["model"], "mine:" + kind, lore,
		[["Damage", "%d" % int(c["damage"])], ["Blast radius", "%d m" % int(c["blast"])], ["Health", "%d" % int(c["hp"])], ["Trigger", trigger]])


static func _entry(id: String, category: String, title: String, model: String, needs: String, lore: String, stats: Array, tint := Color.BLACK) -> Dictionary:
	return {"id": id, "category": category, "name": title, "model": M + model + ".glb", "needs": needs, "lore": lore, "stats": stats, "tint": tint}


static func _robot(kind: String, title: String, lore: String, category := "Enemies") -> Dictionary:
	var c: Dictionary = Robot.TYPES[kind]
	var stats := [["Health", "%d" % int(c["hp"])], ["Speed", "%d m/s" % int(c["speed"])]]
	if c.has("melee"):
		stats.append(["Melee damage", "%d" % int(c["melee"])])
	elif c.has("explode"):
		stats.append(["Blast damage", "%d" % int(c["explode"])])
	else:
		stats.append(["Weapon", c.get("weapon", "laser").capitalize()])
		stats.append(["Shot damage", "%d" % int(c["dmg"])])
		stats.append(["Fires every", "%.2f s" % c["fire"]])
	stats.append(["Score", "%d" % int(c["score"])])
	if c.has("missile"):
		stats.append(["Missile every", "%.1f s" % c["missile"]])
	return _entry(kind, category, title, c["model"], "robot:" + kind, lore, stats)


static func _key(color: String, title: String) -> Dictionary:
	return _entry("key_" + color, "Items", title, "pickup_key", "pickup:key_" + color,
		"Physical keys, in a mine run by computers. The foreman insisted: a machine can't copy what it can't reach. So far the foreman has been right.",
		[["Opens", "%s doors" % color.capitalize()]], Game.KEY_COLORS[color])


static func _reactor_stats() -> Array:
	var low := INF
	var high := 0.0
	for i in Game.levels.size():
		if level_data(i)["reactor"] == null:
			continue
		var hp: float = level_data(i)["reactor_hp"]
		low = minf(low, hp)
		high = maxf(high, hp)
	return [["Health", "%d to %d" % [int(low), int(high)]], ["Score", "+5000"], ["Escape time", "%d s" % int(Game.ESCAPE_SECONDS)]]


static func level_data(index: int) -> Dictionary:
	var path: String = Game.levels[index]["data"]
	if not _level_cache.has(path):
		_level_cache[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _level_cache[path]


## An entry with no requirement is part of the player's kit from the start.
static func is_unlocked(entry: Dictionary, unlocked_level: int) -> bool:
	var needs: String = entry["needs"]
	if needs.is_empty():
		return true
	for i in unlocked_level + 1:
		if _level_contains(level_data(i), needs):
			return true
	return false


static func _level_contains(data: Dictionary, needs: String) -> bool:
	if needs == "astronaut":
		return not data["astronauts"].is_empty()
	if needs == "turret":
		return not data["turrets"].is_empty()
	var parts := needs.split(":")
	if parts[0] == "mine":
		return data["mines"].any(func(item): return item["type"] == parts[1])
	var list: Array = data["robots"] if parts[0] == "robot" else data["pickups"]
	return list.any(func(item): return item["type"] == parts[1])
