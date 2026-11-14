extends Node
## Renders the same viewpoints of one mine at one graphics quality and reports the
## average draw calls, primitives, objects and frame rate, for comparing presets.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1280x720 res://tests/quality_perf.tscn -- <quality 0-2> [level index] [nolod] [shots=<absolute dir>]
## Add --rendering-method gl_compatibility before res:// to see what the web build draws.

const VIEWPOINTS := 10
const FRAMES_PER_VIEW := 24


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func(): print("QPERF timeout"); get_tree().quit(1))
	Progress.path = "user://test_progress.cfg"
	Settings.path = "user://test_quality_settings.cfg"
	var args := OS.get_cmdline_user_args()
	Settings.quality = int(args[0]) if args.size() > 0 else Settings.Quality.HIGH
	var level_index := int(args[1]) if args.size() > 1 else 0
	Settings.vsync = false
	Settings.apply()
	Game.reset_run()
	Game.level_index = level_index
	Game.level_start = Game._make_snapshot()
	add_child(load("res://scenes/level.tscn").instantiate())
	if "nolod" in args:
		get_viewport().mesh_lod_threshold = 0.0
	for i in 60:
		await get_tree().process_frame
	var p: Player = Game.player
	p.shield = 1e9
	p._invuln = 1e9
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Robot:
			n.queue_free()
	await get_tree().process_frame
	var shot_dir := ""
	for a in args:
		if a.begins_with("shots="):
			shot_dir = a.substr(6)
	var cells: Array = Game.level.data["cells"]
	var space := p.get_world_3d().direct_space_state
	var cell_size: float = Game.level.cell_size
	var totals := [0.0, 0.0, 0.0, 0.0]
	var frames := 0
	var elapsed := 0.0
	for v in VIEWPOINTS:
		var c: Array = cells[int(float(v) / VIEWPOINTS * cells.size())]
		var at := Vector3(c[0], c[1], c[2]) * cell_size
		# Look down the longest open line from here, where the most mine is in view.
		var best_dir := Vector3.FORWARD
		var best_len := -1.0
		for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + dir * 400.0, Game.WORLD))
			var d := 400.0 if hit.is_empty() else at.distance_to(hit.position)
			if d > best_len:
				best_len = d
				best_dir = dir
		var last := Time.get_ticks_usec()
		for f in FRAMES_PER_VIEW:
			p.global_position = at
			p.look_at(at + best_dir, Vector3.UP if absf(best_dir.y) < 0.9 else Vector3.FORWARD)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if f == FRAMES_PER_VIEW - 1 and shot_dir != "":
				get_viewport().get_texture().get_image().save_png("%s/q%d_l%d_v%d.png" % [shot_dir, Settings.quality, level_index, v])
			if f < 4:  # let the new view settle before counting
				last = now
				continue
			elapsed += (now - last) / 1e6
			last = now
			frames += 1
			totals[0] += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			totals[1] += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			totals[2] += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	totals[3] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	print("QPERF level=%d quality=%d renderer=%s lod=%s fps=%.1f draws=%d prims=%d objects=%d vram_mb=%.0f adapter=%s" % [
		level_index, Settings.quality, RenderingServer.get_current_rendering_method(), "off" if "nolod" in args else "on",
		frames / maxf(elapsed, 1e-6), totals[0] / frames, totals[1] / frames, totals[2] / frames, totals[3],
		RenderingServer.get_video_adapter_name()])
	DirAccess.remove_absolute(Settings.path)
	get_tree().quit()
