extends Node
## Black Shaft: key order, cannon upgrades and a full win.
## godot --headless --path . res://tests/level3.tscn

const LEVEL := 2

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func bolts() -> Array:
	return Game.level.get_children().filter(func(n): return n is Bolt and n.shooter == Game.player)


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Game.reset_run()
	Settings.unlock_all = false
	Game.level_index = LEVEL
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	var level = Game.level
	var p: Player = Game.player
	p.shield = 1e9
	check(Game.upgrades.is_empty() and Game.laser_level() == 1, "nothing is granted automatically at level start")

	var doors := {}
	for n in level.get_children():
		if n is Door:
			doors[n.lock] = n
	var pickups := {}
	for n in get_tree().get_nodes_in_group("pickup"):
		pickups[n.kind] = n
	var start: int = level.astar.get_closest_point(p.global_position)
	var reachable := func(pos: Vector3) -> bool:
		return not level.astar.get_id_path(start, level.astar.get_closest_point(pos)).is_empty()
	check(reachable.call(pickups["key_blue"].global_position), "blue key is reachable from the start")
	check(not reachable.call(pickups["key_yellow"].global_position), "yellow key is behind the blue door")
	check(not reachable.call(pickups["upgrade_laser_2"].global_position), "the upgrade is behind the blue door")
	check(not reachable.call(level.v3(level.data["reactor"]) + Vector3(0, 0, 30)), "reactor is behind the yellow door")
	level.set_cell_blocked(doors["blue"].cell, false)
	check(reachable.call(pickups["key_yellow"].global_position), "blue door leads to the yellow key")
	check(not reachable.call(level.v3(level.data["reactor"]) + Vector3(0, 0, 30)), "blue door alone doesn't reach the reactor")
	level.set_cell_blocked(doors["yellow"].cell, false)
	check(reachable.call(level.v3(level.data["reactor"]) + Vector3(0, 0, 30)), "yellow door leads to the reactor")
	level.set_cell_blocked(doors["reactor"].cell, false)
	level.set_cell_blocked(doors["secret"].cell, false)
	# The airlock behind the sealed entry door is part of the map too.
	level.set_cell_blocked(doors["entry"].cell, false)
	var cut_off := 0
	for id in level.astar.get_point_ids():
		if id != start and level.astar.get_id_path(start, id).is_empty():
			cut_off += 1
	check(cut_off == 0, "all %d cells are connected" % level.cell_ids.size())
	level.set_cell_blocked(doors["reactor"].cell, true)

	# Catch-up: Cannon Sync from level 2 waits near the start, for anyone who missed it.
	var sync_pickup = pickups.get("upgrade_dual_fire")
	check(sync_pickup != null and sync_pickup.global_position.distance_to(level.v3(level.data["start"])) < 120.0, "Cannon Sync reappears near the start of level 3")
	p.global_position = level.v3(level.data["start"])
	p.global_basis = Basis.IDENTITY
	await frames(3)
	var before: int = bolts().size()
	p._fire_cd = 0.0
	p.fire_primary()
	check(bolts().size() == before + 1, "without Cannon Sync the cannons alternate")
	var green: Bolt = bolts().back()
	check(green.damage == Player.LASER_DAMAGE[0] and green.color == Player.LASER_COLORS[0], "laser level 1 is green")
	p.global_position = sync_pickup.global_position
	await frames(6)
	check(Game.has_upgrade("dual_fire"), "picking it up installs it")
	p.global_position = level.v3(level.data["start"])
	await frames(3)
	before = bolts().size()
	p._fire_cd = 0.0
	p.fire_primary()
	check(bolts().size() == before + 2, "Cannon Sync fires both cannons together")

	# Laser levels: each step changes colour and damage.
	p.global_position = pickups["upgrade_laser_2"].global_position
	await frames(6)
	check(Game.laser_level() == 2, "laser upgrade can be collected")
	for tier in [2, 3, 4]:
		Game.upgrades = ["dual_fire", "laser_%d" % tier]
		p._fire_cd = 0.0
		p.fire_primary()
		var shot: Bolt = bolts().back()
		check(shot.damage == Player.LASER_DAMAGE[tier - 1] and shot.color == Player.LASER_COLORS[tier - 1], "laser level %d has its own damage and colour" % tier)

	# A duplicate becomes energy, and never downgrades or stacks.
	Game.upgrades = ["dual_fire", "laser_3"]
	p.energy = 50.0
	Game.collect_upgrade("laser_2", "x", Color.WHITE)
	check(Game.laser_level() == 3 and Game.upgrades.size() == 2 and p.energy == 50.0 + Pickup.ENERGY_BOOST, "an already-held laser upgrade gives energy instead")
	p.energy = 50.0
	Game.collect_upgrade("dual_fire", "x", Color.WHITE)
	check(Game.upgrades.size() == 2 and p.energy == 50.0 + Pickup.ENERGY_BOOST, "a duplicate Cannon Sync gives energy instead")

	var snap: Dictionary = Game._make_snapshot()
	Game.upgrades = []
	Game._apply_snapshot(snap)
	check(Game.laser_level() == 3 and Game.has_upgrade("dual_fire"), "upgrades survive in level snapshots")
	snap["upgrades"] = ["overcharge"]
	Game._apply_snapshot(snap)
	check(Game.laser_level() == 2, "saves with the old upgrade name still work")

	# LOS and the escape.
	var reactor: Reactor = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Reactor)[0]
	var space := p.get_world_3d().direct_space_state
	var clear := 0
	var door: Door = doors["yellow"]
	for dz in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		for dx in [-3.5, 0.0, 3.5]:
			for dy in [-3.5, 0.0, 3.5]:
				var q := PhysicsRayQueryParameters3D.create(door.global_position + door.global_basis * Vector3(dx, dy, dz), reactor.global_position, Game.WORLD)
				q.exclude = [reactor.get_rid()]
				if space.intersect_ray(q).is_empty():
					clear += 1
	check(clear == 0, "reactor is out of sight from the yellow door (%d clear lines)" % clear)
	check(reactor.hp >= 1600.0 and reactor.fires_novas, "the reactor is the toughest yet")
	reactor.take_damage(1e6, reactor.global_position, null)
	await frames(10)
	var escape: Door = doors["reactor"]
	p.global_position = escape.global_position + Vector3(-14, 0, 0)
	await frames(240)
	check(escape._is_open, "escape door opens")
	p.global_position = level.v3(level.data["escape_trigger"])
	await frames(8)
	check(Game.cinematic, "tunnel starts the finale")
	Engine.time_scale = 6.0
	for i in 6000:
		if Game.finished:
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var run: EscapeRun = level.get_children().filter(func(n): return n is EscapeRun)[0]
	check(Game.finished and Game.won, "level 3 can be won")
	check(run._t >= 5.5 and run._t <= 6.5, "tunnel flight lasts about six seconds (%.1f s)" % run._t)
	check(run._space_t >= 2.0 and run.elapsed() <= 9.0, "the explosion plays after the flight (%.1f s total)" % run.elapsed())
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)
