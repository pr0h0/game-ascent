extends Node
## First Shift, start to finish: godot --headless --path . res://tests/level1.tscn

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
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	var level = Game.level
	var p: Player = Game.player
	p.shield = 1e9
	var robots := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot)
	var kinds := robots.filter(func(r): return r.kind == "bulwark")
	check(level.cell_ids.size() < 1500, "much smaller than The Vein (%d cells)" % level.cell_ids.size())
	check(robots.size() <= 12 and kinds.is_empty(), "few robots and no heavies (%d)" % robots.size())
	var keys := get_tree().get_nodes_in_group("pickup").filter(func(n): return n.kind.begins_with("key_"))
	check(keys.size() == 1 and keys[0].kind == "key_blue", "blue is the only key")
	check(Game.astronauts_total == 0, "no astronauts here")

	var door_cells := []
	var door: Door
	var escape: Door
	for n in level.get_children():
		if n is Door:
			door_cells.append(n.cell)
			level.set_cell_blocked(n.cell, false)
			if n.lock == "blue":
				door = n
			elif n.lock == "reactor":
				escape = n
	var start_id: int = level.astar.get_closest_point(p.global_position)
	var cut_off := 0
	for id in level.astar.get_point_ids():
		if id != start_id and level.astar.get_id_path(start_id, id).is_empty():
			cut_off += 1
	check(cut_off == 0, "every cell is reachable")
	for c in door_cells:
		level.set_cell_blocked(c, true)
	# The key must be reachable without passing the door it opens.
	var key_id: int = level.astar.get_closest_point(keys[0].global_position)
	check(not level.astar.get_id_path(start_id, key_id).is_empty(), "key can be reached before the blue door")

	# The side of the door the key is on, whichever way the door faces.
	var near := door.global_basis.z * 14.0
	if level.astar.get_id_path(start_id, level.astar.get_closest_point(door.global_position + near)).is_empty():
		near = -near
	p.global_position = door.global_position + near
	p.velocity = Vector3.ZERO
	await frames(40)
	check(not door._is_open, "blue door stays shut without the key")
	p.global_position = keys[0].global_position
	await frames(6)
	check(Game.has_key("blue"), "blue key collected")
	p.global_position = door.global_position + near
	await frames(240)
	check(door._is_open, "blue door opens")

	var reactor: Reactor = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Reactor)[0]
	check(reactor.hp < 600.0 and not reactor.fires_novas, "the reactor is weaker and doesn't shoot back")
	var space := p.get_world_3d().direct_space_state
	var clear := 0
	for dz in [-16.0, -8.0, 0.0, 6.0, 12.0]:
		for dx in [-3.5, 0.0, 3.5]:
			for dy in [-3.5, 0.0, 3.5]:
				var q := PhysicsRayQueryParameters3D.create(door.global_position + door.global_basis * Vector3(dx, dy, dz), reactor.global_position, Game.WORLD)
				q.exclude = [reactor.get_rid()]
				if space.intersect_ray(q).is_empty():
					clear += 1
	check(clear == 0, "reactor is out of sight from the door (%d clear lines)" % clear)
	var inside := PhysicsRayQueryParameters3D.create(reactor.global_position + Vector3(0, 0, 30), reactor.global_position, Game.WORLD)
	inside.exclude = [reactor.get_rid()]
	check(space.intersect_ray(inside).is_empty(), "reactor is visible from inside its chamber")

	reactor.take_damage(1e6, reactor.global_position, null)
	await frames(10)
	check(Game.reactor_down, "reactor destroyed")
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
	check(Game.finished and Game.won, "level one can be won")
	check(run._t >= 5.5 and run._t <= 6.5, "tunnel flight lasts about six seconds (%.1f s)" % run._t)
	check(run._space_t >= 2.0 and run.elapsed() <= 9.0, "the explosion plays after the flight (%.1f s total)" % run.elapsed())
	check(Game.has_next_level(), "The Vein follows it")
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)
