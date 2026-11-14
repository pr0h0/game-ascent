extends Node
## Screenshots of the effects pass: per-level lighting, the reactor heat haze (with and
## without) and the low-shield warning.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1280x720 --fixed-fps 30 res://tests/fx_shots.tscn -- <dir> [level indices...]


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func(): print("FXSHOTS timeout"); get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var picks: Array = [0, 3, 7, 8]
	if args.size() > 1:
		picks = []
		for a in args.slice(1):
			picks.append(int(a))
	Progress.path = "user://test_progress.cfg"
	Settings.quality = Settings.Quality.HIGH
	Game.autopilot = true
	for index: int in picks:
		Game.reset_run()
		Game.level_index = index
		Game.level_start = Game._make_snapshot()
		var level: Node3D = load("res://scenes/level.tscn").instantiate()
		add_child(level)
		# Past the title card.
		for i in 150:
			await get_tree().process_frame
		var p: Player = Game.player
		p.shield = 1e9
		p._invuln = 1e9
		var tag := str(Game.current_level()["name"]).to_snake_case().replace("'", "")
		await _shot(dir + "/mood_%d_%s.png" % [index, tag])
		if index == picks[0]:
			await _reactor_shots(dir, level, p)
			p.shield = 9.0
			for i in 10:
				await get_tree().process_frame
			await _shot(dir + "/low_shield.png")
			p.shield = 1e9
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()


func _reactor_shots(dir: String, level: Node3D, p: Player) -> void:
	var reactor: Node3D = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Reactor:
			reactor = e
	if reactor == null:
		return
	reactor.fires_novas = false
	var space := p.get_world_3d().direct_space_state
	var spot := Vector3.INF
	for id in level.astar.get_point_ids():
		var at: Vector3 = level.astar.get_point_position(id)
		var d := at.distance_to(reactor.global_position)
		if d < 40.0 or d > 60.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(at, reactor.global_position, Game.WORLD)
		q.exclude = [reactor.get_rid()]
		if space.intersect_ray(q).is_empty():
			spot = at
			break
	if spot == Vector3.INF:
		return
	p.global_position = spot
	p.look_at(reactor.global_position, Vector3.UP)
	for i in 20:
		await get_tree().process_frame
	await _shot(dir + "/reactor_haze.png")
	reactor._haze.visible = false
	reactor.set_process(false)
	await get_tree().process_frame
	await _shot(dir + "/reactor_no_haze.png")
	reactor.set_process(true)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
