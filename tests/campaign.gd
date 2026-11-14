extends Node
## All ten levels: can each be solved in order, and can it be won?
## godot --headless --path . res://tests/campaign.tscn

var failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL  " + what)
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	for index in Game.levels.size():
		await _run_level(index)
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _run_level(index: int) -> void:
	Game.reset_run()
	Game.level_index = index
	var node: Node = load("res://scenes/level.tscn").instantiate()
	add_child(node)
	await frames(10)
	var level = Game.level
	var p: Player = Game.player
	var name_text: String = Game.level_title(index)
	p.shield = 1e9
	var robots: Array = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot)
	var doors: Array = level.get_children().filter(func(n): return n is Door)
	var pickups: Array = get_tree().get_nodes_in_group("pickup")
	check(not robots.is_empty(), name_text + ": has robots")
	check(Game.earlier_upgrades(index).size() <= Game.MAX_CATCH_UP, name_text + ": catch-up limited")

	# Walk the key chain: keep collecting whatever is reachable and opening its doors.
	var start: int = level.astar.get_closest_point(p.global_position)
	var held := {}
	for d in doors:
		if d.lock == "secret":
			level.set_cell_blocked(d.cell, false)
	var reach := func(pos: Vector3) -> bool:
		return not level.astar.get_id_path(start, level.astar.get_closest_point(pos)).is_empty()
	var keys: Array = pickups.filter(func(n): return n.kind.begins_with("key_"))
	var progressed := true
	while progressed:
		progressed = false
		for k in keys:
			var color: String = k.kind.trim_prefix("key_")
			if not held.has(color) and reach.call(k.global_position):
				held[color] = true
				progressed = true
				for d in doors:
					if d.lock == color:
						level.set_cell_blocked(d.cell, false)
	check(held.size() == keys.size(), "%s: all keys obtainable (%d/%d)" % [name_text, held.size(), keys.size()])

	var escape: Door = doors.filter(func(d): return d.lock == "reactor")[0]
	var goal_pos: Vector3 = level.v3(level.data["reactor"]) if level.data["reactor"] != null else robots.filter(func(r): return r is Boss)[0].global_position
	check(reach.call(goal_pos + Vector3(0, 0, 25)), name_text + ": objective reachable")
	level.set_cell_blocked(escape.cell, false)
	# The airlock behind the sealed entry door is part of the map too.
	for d in doors.filter(func(d): return d.lock == "entry"):
		level.set_cell_blocked(d.cell, false)
	var cut := 0
	for id in level.astar.get_point_ids():
		if id != start and level.astar.get_id_path(start, id).is_empty():
			cut += 1
	check(cut == 0, "%s: %d cells unreachable" % [name_text, cut])
	level.set_cell_blocked(escape.cell, true)

	# From each key door, the objective must stay out of sight.
	var goal: Node3D = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Reactor or e is Boss)[0]
	var space := p.get_world_3d().direct_space_state
	for d in doors:
		if d.lock in ["blue", "yellow", "red"]:
			var q := PhysicsRayQueryParameters3D.create(d.global_position, goal.global_position, Game.WORLD)
			q.exclude = [goal.get_rid()]
			for other in doors:
				q.exclude.append(other.get_rid())
			check(not space.intersect_ray(q).is_empty(), name_text + ": objective visible from a door")

	# Secrets exist on every level and only open to a shot.
	var secret: Array = doors.filter(func(d): return d.hidden_door)
	check(not secret.is_empty() and Game.secrets_total == secret.size(), name_text + ": has secret doors")
	p.global_position = secret[0].global_position + Vector3(1, 0, 1)
	await frames(10)
	check(not secret[0]._is_open, name_text + ": secret door ignores proximity")
	secret[0].take_damage(1.0, secret[0].global_position, p)
	check(secret[0]._is_open and Game.secrets_found == 1, name_text + ": a shot opens the secret door")

	# Destroy the objective, then let the ending play out.
	goal.take_damage(1e7, goal.global_position, null)
	await frames(10)
	check(Game.reactor_down, name_text + ": objective destroyed")
	p.global_position = level.v3(level.data["escape_trigger"])
	await frames(8)
	check(Game.cinematic, name_text + ": finale starts")
	Engine.time_scale = 8.0
	for i in 8000:
		if Game.finished:
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	check(Game.finished and Game.won, name_text + ": level can be won")
	var run: EscapeRun = level.get_children().filter(func(n): return n is EscapeRun)[0]
	check(run._t >= 5.0 and run._t <= 7.0, "%s: flight %.1f s" % [name_text, run._t])
	print("LEVEL %d ok-so-far failures=%d cells=%d robots=%d mines=%d secrets=%d" % [index + 1, failures, level.cell_ids.size(), robots.size(), level.data["mines"].size(), secret.size()])
	node.free()
	await frames(4)
