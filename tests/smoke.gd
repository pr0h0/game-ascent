extends Node
## Headless end-to-end check of the run: godot --headless --path . res://tests/smoke.tscn

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var game = Game
	game.reset_run()
	game.level_index = 1  # The Vein: this test walks its specific rooms and doors.
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	var level = game.level
	var p = game.player
	check(level != null and p != null, "level and player spawned")
	check(get_tree().get_nodes_in_group("enemy").size() >= 30, "robots, sentries and core registered (%d)" % get_tree().get_nodes_in_group("enemy").size())
	p.shield = 1e9

	# Navigation: every cell reachable from the start when doors are open.
	var door_cells := []
	for d in level.data["doors"]:
		door_cells.append(Vector3i(int(d["cell"][0]), int(d["cell"][1]), int(d["cell"][2])))
	for c in door_cells:
		level.set_cell_blocked(c, false)
	var start_id: int = level.astar.get_closest_point(p.global_position)
	var unreachable := 0
	for id in level.astar.get_point_ids():
		if id != start_id and level.astar.get_id_path(start_id, id).is_empty():
			unreachable += 1
	check(unreachable == 0, "all %d cells connected" % level.cell_ids.size())
	for c in door_cells:
		level.set_cell_blocked(c, true)

	# Flight: thrust moves the ship forward and it stops at walls.
	var z0: float = p.global_position.z
	Input.action_press("thrust_forward")
	await frames(120)
	Input.action_release("thrust_forward")
	check(p.global_position.z < z0 - 12.0, "forward thrust moves along -Z (moved %.1f m)" % (z0 - p.global_position.z))
	Input.action_press("thrust_back")
	await frames(600)
	Input.action_release("thrust_back")
	# Behind the spawn room is the sealed entry door the ship arrived through, at z = 50.
	check(p.global_position.z > 38.0 and p.global_position.z < 49.0, "the sealed entry door stops the ship (z=%.1f)" % p.global_position.z)

	# Settings feed the flight controls.
	var f0: Basis = p.global_basis
	Settings.invert_y = true
	p._mouse = Vector2(0, 60)
	await frames(2)
	Settings.invert_y = false
	check((-p.global_basis.z).y > (-f0.z).y, "inverted Y pitches up on mouse down")
	p.global_basis = Basis.IDENTITY

	# Rear view turns the camera around, but the guns still point forward.
	p.view_mode = Player.View.COCKPIT
	p.global_position = level.v3(level.data["start"])
	p.global_basis = Basis.IDENTITY
	p.set_rear_view(true)
	await frames(3)
	check(p.cam.global_basis.z.dot(p.global_basis.z) < -0.9, "rear view looks backward")
	check(not p.cockpit.visible and p.ship.visible, "cockpit rear view swaps the cabin for the ship's tail")
	check((p.cam.global_position - p.global_position).y > 1.0, "rear viewpoint sits above the hull")
	check((p.aim_point() - p.global_position).dot(-p.global_basis.z) > 0.0, "guns keep aiming forward in rear view")
	p.set_rear_view(false)
	await frames(3)
	check(p.cam.global_basis.z.dot(p.global_basis.z) > 0.9 and p.cockpit.visible and not p.ship.visible, "rear view switches back")
	p.view_mode = Player.View.CLEAN
	p.set_rear_view(true)
	check(not p.ship.visible, "clean rear view stays free of the ship")
	p.set_rear_view(false)
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()

	# Wall hits: a full-speed crash is a scratch, a light bump costs nothing.
	var crash := func(speed: float, start_shield := 100.0) -> float:
		p.global_position = Vector3(0, 10, 41.5)
		p.global_basis = Basis.IDENTITY
		p.velocity = Vector3(0, 0, speed)
		p.shield = start_shield
		await frames(30)
		return start_shield - p.shield
	var hard: float = await crash.call(40.0)
	check(hard > 0.0 and hard <= 2.0, "full-speed wall crash costs under 2 shield (lost %.2f)" % hard)
	var soft: float = await crash.call(16.0)
	check(soft == 0.0, "light wall bump costs no shield")
	var weak: float = await crash.call(40.0, 8.0)
	check(weak == 0.0, "walls cannot damage a ship below 10 shield")
	p.shield = 1e9

	# Roll keys rotate about the view axis.
	var basis0: Basis = p.global_basis
	Input.action_press("roll_left")
	await frames(60)
	Input.action_release("roll_left")
	check(basis0.x.dot(p.global_basis.x) < 0.95 and absf(basis0.z.dot(p.global_basis.z)) > 0.99, "roll keeps heading")
	p.global_basis = Basis.IDENTITY

	# Weapons: an aimed volley damages a robot, the missile homes and kills.
	var target
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Robot and e.kind == "tick":
			target = e
			break
	var kills0: int = game.kills
	# Held still so this measures weapon damage, not whether its dodge happened to work.
	target.set_physics_process(false)
	# Levels are generated: shoot from whichever side has open space.
	var aim_from := func(pos: Vector3, dist: float) -> Vector3:
		for d: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
			var ok := true
			for step in range(1, int(dist / 5.0) + 1):
				if not level.cell_ids.has(Vector3i(((pos + d * step * 5.0) / level.cell_size).round())):
					ok = false
			if ok:
				return pos + d * dist
		return pos + Vector3(0, 0, dist)
	p.global_position = aim_from.call(target.global_position, 18.0)
	p.global_basis = Basis.looking_at((target.global_position - p.global_position).normalized(), Vector3.UP if absf((target.global_position - p.global_position).normalized().y) < 0.9 else Vector3.BACK)
	await frames(4)
	var hp0: float = target.hp
	p.fire_primary()
	await frames(40)
	check(not is_instance_valid(target) or target.hp < hp0, "cannon bolt damages robot")
	if is_instance_valid(target):
		p.global_position = aim_from.call(target.global_position, 25.0)
		p.lock_target = target
		p._missile_cd = 0.0
		var ammo0: int = p.missiles
		p.fire_missile()
		check(p.missiles == ammo0 - 1, "missile consumes ammo")
		await frames(120)
	check(game.kills > kills0, "robot destroyed by weapons")

	# Robots hold fire for a moment after spotting the player, then open up.
	p.global_position = level.v3(level.data["start"])
	p.velocity = Vector3.ZERO
	var spotter = level.spawn_robot("tick", p.global_position + Vector3(10, 4, -20))
	var count_shots := func() -> int:
		return level.get_children().filter(func(n): return n is Bolt and n.shooter == spotter).size()
	await frames(50)
	check(count_shots.call() == 0, "robot holds fire just after spotting the player")
	var fired := false
	for i in 300:
		await frames(1)
		fired = fired or count_shots.call() > 0
	check(fired, "robot opens fire after its reaction delay")
	var enemy_shots: Array = level.get_children().filter(func(n): return n is Bolt and n.shooter == spotter)
	check(enemy_shots.is_empty() or enemy_shots[0].color == Player.LASER_COLORS[0], "a 10-damage robot fires green")
	spotter.queue_free()

	# After dying, hunters forget the player and head back instead of camping the respawn.
	var hunter
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Robot and e.kind == "lancer" and e.global_position.distance_to(p.global_position) > 150.0:
			hunter = e
			break
	var post: Vector3 = hunter.home
	hunter.global_position = level.astar.get_point_position(level.astar.get_closest_point(post + Vector3(0, 0, 40)))
	var start_away: float = hunter.global_position.distance_to(post)
	hunter.alert()
	p._die()
	await frames(4)
	check(not hunter.alerted and hunter._returning, "hunters stand down when the player dies")
	await get_tree().create_timer(2.8).timeout
	check(not p.dead, "player respawned")
	check(not hunter.alerted, "hunters do not re-target the respawned player across the map")
	check(hunter.global_position.distance_to(post) < start_away, "hunter moved back toward its post")
	p.shield = 1e9

	# Astronauts: fly close to rescue them for points, once each.
	var survivors: Array = get_tree().get_nodes_in_group("astronaut")
	check(survivors.size() == 5 and game.astronauts_total == 5, "five astronauts wait in the shelter")
	var survivor = survivors[0]
	var score_before: int = game.score
	p.global_position = survivor.global_position + Vector3(0, 0, 3)
	await frames(6)
	check(game.astronauts_rescued == 1 and game.score == score_before + Astronaut.SCORE, "flying close rescues an astronaut for points")
	await frames(90)
	check(game.astronauts_rescued == 1 and not is_instance_valid(survivor), "each astronaut only counts once")
	check(game.level.get("cell_ids").has(Vector3i((survivors[1].global_position / level.cell_size).round())), "shelter is part of the level")

	# Both stats start at 100 and can be boosted to 200, as in Descent.
	var collect := func(kind: String) -> void:
		var pk := Pickup.new()
		pk.kind = kind
		level.add_child(pk)
		pk._collect(p)
	check(Player.START_SHIELD == 100.0 and Player.START_ENERGY == 100.0, "ship starts at 100 shield and 100 energy")
	p.shield = 100.0
	collect.call("shield")
	check(p.shield == 130.0, "shield pickup goes past 100")
	p.shield = 190.0
	collect.call("shield")
	check(p.shield == 200.0, "shield caps at 200")
	p.energy = 100.0
	collect.call("energy")
	check(p.energy == 140.0, "energy pickup goes past 100")
	p.energy = 190.0
	collect.call("energy")
	check(p.energy == 200.0, "energy caps at 200")
	p.energy = 99.9
	await frames(60)
	check(p.energy == 100.0, "passive recharge stops at 100")
	p.energy = 150.0
	await frames(30)
	check(p.energy == 150.0, "energy above 100 neither recharges nor decays")
	p.shield = 1e9

	# A bolt still lands after whoever fired it has been destroyed.
	var doomed := Node3D.new()
	add_child(doomed)
	p._invuln = 0.0
	var shield0: float = p.shield
	Bolt.launch(p.global_position + Vector3(0, 0, 8), Vector3.FORWARD, 100.0, 1234.0, Color.RED, game.PLAYER, 1.0, doomed)
	doomed.free()
	await frames(30)
	check(shield0 - p.shield >= 1234.0, "bolt from a destroyed shooter still damages the player")

	# View modes cycle chase -> cockpit -> clean.
	p.view_mode = Player.View.CHASE
	p._apply_view_mode()
	check(p.ship.visible and not p.cockpit.visible, "chase view shows the ship only")
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()
	check(p.cockpit.visible and not p.ship.visible, "cockpit view shows the cabin only")
	p.view_mode = Player.View.CLEAN
	p._apply_view_mode()
	check(not p.cockpit.visible and not p.ship.visible, "clean view shows neither")

	# Each colour gates the next, and doors stay shut without their key.
	var doors := {}
	for n in level.get_children():
		if n is Door:
			doors[n.lock] = doors.get(n.lock, []) + [n]
	var upgrade_in_level: bool = get_tree().get_nodes_in_group("pickup").any(func(n): return n.kind == "upgrade_dual_fire")
	check(upgrade_in_level, "Cannon Sync is found on level 2")
	check(doors["blue"].size() >= 1 and doors["yellow"].size() >= 1 and doors["red"].size() >= 1, "three key colours of doors")
	var pickups := {}
	for n in get_tree().get_nodes_in_group("pickup"):
		pickups[n.kind] = n
	var far_door = doors["blue"][-1]
	var shoot_door := func(source: Object) -> void:
		Bolt.launch(far_door.global_position + far_door.global_basis.z * 4.0, -far_door.global_basis.z, 200.0, 13.0, Color.WHITE, game.WORLD, 1.0, source)
		await frames(8)
	await shoot_door.call(p)
	check(not far_door._is_open, "shooting a locked door without its key does nothing")
	Flare.launch(far_door.global_position + far_door.global_basis.z * 4.0, -far_door.global_basis.z)
	await frames(10)
	check(not far_door._is_open, "a flare does not open a door without its key")
	for color in ["blue", "yellow", "red"]:
		var door = doors[color][0]
		# Approach from the side already reachable: the generated doors face every way.
		var offset: Vector3 = door.global_basis.z * 14.0
		var from_start: int = level.astar.get_closest_point(level.v3(level.data["start"]))
		if level.astar.get_id_path(from_start, level.astar.get_closest_point(door.global_position + offset)).is_empty():
			offset = -offset
		p.global_position = door.global_position + offset
		p.velocity = Vector3.ZERO
		await frames(30)
		check(not door._is_open, color + " door stays shut without its key")
		check(door._mat.emission == game.KEY_COLORS[color], color + " door shows its key colour")
		var into: Vector3 = -offset.normalized() * 40.0
		p.velocity = into
		await frames(70)
		check(signf((p.global_position - door.global_position).dot(offset)) > 0.0, color + " door is solid")
		p.global_position = pickups["key_" + color].global_position
		await frames(6)
		check(game.has_key(color), color + " key collected")
		p.global_position = door.global_position + offset
		p.velocity = Vector3.ZERO
		await frames(240)
		check(door._is_open and door._shape.disabled, color + " door opens with its key")

	# With the key, a shot opens the door from any distance, but only the player's shots.
	var bystander := Node3D.new()
	add_child(bystander)
	check(p.global_position.distance_to(far_door.global_position) > Door.TRIGGER_RANGE, "shot test is out of proximity range")
	await shoot_door.call(bystander)
	check(not far_door._is_open, "enemy fire does not open doors")
	await shoot_door.call(p)
	check(far_door._is_open, "player's shot opens an unlocked door from range")
	bystander.queue_free()

	# The reactor can't be seen, or shot, from anywhere at the red door.
	var reactor
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Reactor:
			reactor = n
	var red_door = doors["red"][0]
	var space = p.get_world_3d().direct_space_state
	var clear_shots := 0
	for dx in [-16.0, -8.0, 0.0, 6.0, 12.0]:
		for dy in [-3.5, 0.0, 3.5]:
			for dz in [-3.5, 0.0, 3.5]:
				var from: Vector3 = red_door.global_position + red_door.global_basis * Vector3(dz, dy, dx)
				var q := PhysicsRayQueryParameters3D.create(from, reactor.global_position, game.WORLD)
				q.exclude = [reactor.get_rid()]
				if space.intersect_ray(q).is_empty():
					clear_shots += 1
	check(clear_shots == 0, "reactor is out of sight from the red door (%d clear lines)" % clear_shots)

	p.global_position = reactor.global_position + Vector3(-40, 0, 0)
	await frames(2)
	check(p.has_line_of_sight(reactor), "core is targetable from inside the chamber")
	var core_hp: float = reactor.hp
	var flare := Flare.launch(reactor.global_position + Vector3(-12, 0, 0), Vector3.RIGHT)
	await frames(20)
	check(flare.stuck and reactor.hp == core_hp, "a flare sticks where it lands and deals no damage")
	for i in 10:
		Flare.launch(p.global_position, Vector3.UP)
	await frames(2)
	check(Flare.active_count() <= Flare.MAX_ACTIVE, "old flares burn out to cap the light count")
	reactor.take_damage(1e6, reactor.global_position, null)
	await frames(10)
	check(game.reactor_down and game.escape_left > 55.0, "core destroyed starts escape timer")
	var escape_door = doors["reactor"][0]
	check(p.global_position.distance_to(escape_door.global_position) > Door.TRIGGER_RANGE, "flare test is out of proximity range")
	Flare.launch(escape_door.global_position + Vector3(-4, 0, 0), Vector3.RIGHT)
	await frames(10)
	check(escape_door._is_open, "a flare opens an unlocked door from range")
	await frames(240)

	# Entering the tunnel hands over to the cinematic, which plays out to a win.
	p.global_position = level.v3(level.data["escape_trigger"])
	await frames(8)
	check(game.cinematic and p.cinematic, "tunnel entry starts the autopilot")
	var timer_at_start: float = game.escape_left
	var shield_at_start: float = p.shield
	var before: Vector3 = p.global_position
	await frames(240)
	check(p.global_position.distance_to(before) > 60.0, "autopilot flies the ship down the tunnel")
	check(is_equal_approx(game.escape_left, timer_at_start), "escape timer freezes during the cinematic")
	p.take_damage(50.0, p.global_position, null)
	check(p.shield == shield_at_start, "ship is untouchable during the cinematic")
	Engine.time_scale = 6.0
	var safety := 0
	while not game.finished and safety < 6000:
		safety += 1
		await get_tree().process_frame
	Engine.time_scale = 1.0
	check(game.finished and game.score > 0, "cinematic ends the run in a win")
	var run: EscapeRun = level.get_children().filter(func(n): return n is EscapeRun)[0]
	check(run._in_space and level._env.background_mode == Environment.BG_SKY, "the ship flies out into space")
	check(run._t >= 5.5 and run._t <= 6.5, "tunnel flight lasts about six seconds (%.1f s)" % run._t)
	check(run._space_t >= 2.0 and run.elapsed() <= 9.0, "the explosion plays after the flight (%.1f s total)" % run.elapsed())
	# Saves: every level-start snapshot is its own file, and bad files are skipped.
	Saves.dir = "user://test_saves"
	DirAccess.make_dir_recursive_absolute(Saves.dir)
	for stale in DirAccess.get_files_at(Saves.dir):
		DirAccess.remove_absolute(Saves.dir.path_join(stale))
	var extra_level: Dictionary = game.levels[0].duplicate()
	game.levels.append(extra_level)
	game.level_index = 0
	game.player.shield = 150.0
	game.player.energy = 40.0
	for i in 3:
		game.level_index = 0
		game.prepare_next_level()
	var saved: Array = Saves.list()
	check(saved.size() == 3, "completing the same level repeatedly keeps every save (%d)" % saved.size())
	check(int(saved[0]["level_index"]) == 1, "snapshot records the new level")
	check(saved[0]["shield"] == 150.0 and saved[0]["energy"] == 100.0, "next level keeps a boosted shield and refills low energy")
	var old_file := FileAccess.open(Saves.dir.path_join("old.json"), FileAccess.WRITE)
	old_file.store_string(JSON.stringify({"version": 1, "id": "old", "created_unix": 1.0, "level_index": 0, "score": 5, "lives": 3, "kills": 0, "run_time": 0.0, "shield": 100.0, "energy": 100.0, "missiles": 6}))
	old_file.close()
	var migrated: Array = Saves.list().filter(func(s): return s["id"] == "old")
	check(migrated.size() == 1 and int(migrated[0]["level_index"]) == 1, "saves from before the new level still load The Vein")
	Saves.delete("old")
	var f := FileAccess.open(Saves.dir.path_join("broken.json"), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	check(Saves.list().size() == 3, "corrupt save files are ignored")
	Saves.delete(saved[0]["id"])
	check(Saves.list().size() == 2, "deleting removes only that save")
	game.score = 999
	game.lives = 1
	game._apply_snapshot(saved[1])
	check(game.score == int(saved[1]["score"]) and game.lives == int(saved[1]["lives"]) and game.keys.is_empty() and not game.finished, "loading restores the snapshot and clears level progress")
	game.levels.pop_back()
	for file_name in DirAccess.get_files_at(Saves.dir):
		DirAccess.remove_absolute(Saves.dir.path_join(file_name))

	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)
