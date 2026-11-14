extends Node
## Same scripted barrage of explosions and hit sparks every run, for comparing frame rates.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 800x450 res://tests/fx_perf.tscn -- <quality 0-2> [new|old] [shot dir]
## "old" runs the effects as they were before the effects pass (tests/fx_perf_old.gd), for an A/B.

var fx: Variant = Fx

const IDLE_SECONDS := 3.0
const BARRAGE_SECONDS := 8.0


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func(): print("FXPERF timeout"); get_tree().quit(1))
	Progress.path = "user://test_progress.cfg"
	var args := OS.get_cmdline_user_args()
	Settings.quality = int(args[0]) if args.size() > 0 else Settings.Quality.HIGH
	if args.size() > 1 and args[1] == "old":
		fx = load("res://tests/fx_perf_old.gd")
	Settings.vsync = false
	Settings.apply()
	Game.reset_run()
	Game.level_index = 0
	Game.level_start = Game._make_snapshot()
	add_child(load("res://scenes/level.tscn").instantiate())
	for i in 90:
		await get_tree().process_frame
	var p: Player = Game.player
	p.shield = 1e9
	p._invuln = 1e9
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Robot:
			n.queue_free()
	await get_tree().process_frame
	# Face the nearest wall a sensible distance away, so the sparks land in view.
	var from := p.global_position
	var space := p.get_world_3d().direct_space_state
	var best := {}
	for dir: Vector3 in [-p.global_basis.z, p.global_basis.x, -p.global_basis.x, p.global_basis.z, Vector3.UP, Vector3.DOWN]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, Game.WORLD))
		if hit.is_empty():
			continue
		var d := from.distance_to(hit.position)
		if d > 12.0 and (best.is_empty() or absf(d - 22.0) < absf(float(best["d"]) - 22.0)):
			best = {"d": d, "pos": hit.position, "normal": hit.normal, "dir": dir}
	var forward: Vector3 = best.get("dir", -p.global_basis.z)
	if absf(forward.dot(Vector3.UP)) < 0.95:
		p.look_at(from + forward, Vector3.UP)
	var wall: Vector3 = best.get("pos", from + forward * 30.0)
	var normal: Vector3 = best.get("normal", -forward)
	var dist := from.distance_to(wall)
	var blast_at := from + forward * clampf(dist * 0.6, 8.0, 24.0)
	var idle := await _measure(IDLE_SECONDS, func(_t: float) -> void: pass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var state := {"boom": 0.0, "spark": 0.0, "shot": false}
	var barrage := await _measure(BARRAGE_SECONDS, func(dt: float) -> void:
		state["boom"] -= dt
		state["spark"] -= dt
		if state["boom"] <= 0.0:
			state["boom"] = 0.4
			var size: float = [3.0, 5.0, 9.0, 3.5, 11.0][rng.randi() % 5]
			fx.explosion(blast_at + Vector3(rng.randf_range(-6, 6), rng.randf_range(-3, 3), rng.randf_range(-4, 4)), size, size > 7.0)
		if state["spark"] <= 0.0:
			state["spark"] = 0.06
			fx.sparks(wall + Vector3(rng.randf_range(-3, 3), rng.randf_range(-2, 2), 0), normal, [Color(1, 0.7, 0.3), Color(0.3, 0.8, 1.0), Color(1, 0.3, 0.2)][rng.randi() % 3]))
	print("FXPERF fx=%s quality=%d idle_fps=%.1f barrage_fps=%.1f barrage_low1=%.1f worst_ms=%.1f idle_draws=%d barrage_draws=%d idle_prims=%d barrage_prims=%d" % [
		"old" if fx != Fx else "new", Settings.quality, idle[0], barrage[0], barrage[1], barrage[2], idle[3], barrage[3], idle[4], barrage[4]])
	if args.size() > 2:
		await _shots(args[2], blast_at, wall, normal)
	get_tree().quit()


## Average fps, 1% low fps and the worst frame in ms while `tick` runs every frame.
func _measure(seconds: float, tick: Callable) -> Array:
	var times: Array[float] = []
	var elapsed := 0.0
	var last := Time.get_ticks_usec()
	var draws := 0
	var prims := 0
	while elapsed < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1e6
		last = now
		elapsed += dt
		times.append(dt)
		tick.call(dt)
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var sorted := times.duplicate()
	sorted.sort()
	var slowest := sorted.slice(int(sorted.size() * 0.99))
	var low := 0.0
	for t in slowest:
		low += t
	return [times.size() / elapsed, slowest.size() / maxf(low, 1e-6), sorted[-1] * 1000.0, draws / times.size(), prims / times.size()]


func _shots(dir: String, blast_at: Vector3, wall: Vector3, normal: Vector3) -> void:
	for i in 60:
		await get_tree().process_frame
	fx.explosion(blast_at, 9.0, true)
	for frame in 60:
		await get_tree().process_frame
		if frame in [2, 7, 14, 30, 55]:
			await _shot(dir + "/explosion_%02d.png" % frame)
	await get_tree().create_timer(3.0).timeout
	for i in 3:
		fx.sparks(wall + Vector3(i * 2.0 - 2.0, 0, 0), normal, [Color(1, 0.7, 0.3), Color(0.3, 0.8, 1.0), Color(1, 0.3, 0.2)][i])
	for i in 3:
		await get_tree().process_frame
	await _shot(dir + "/sparks_wall.png")
	var robot: Node3D = Game.level.spawn_robot("lancer", blast_at, false)
	for i in 20:
		await get_tree().process_frame
	var cam := get_viewport().get_camera_3d().global_position
	var face := (cam - robot.global_position).normalized()
	for i in 3:
		var side := face.cross(Vector3.UP).normalized() * (i - 1) * 1.2
		fx.sparks(robot.global_position + face * 2.4 + side, face, [Color(1, 0.7, 0.3), Color(0.3, 0.8, 1.0), Color(1, 0.3, 0.2)][i])
	for i in 3:
		await get_tree().process_frame
	await _shot(dir + "/sparks_robot.png")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
