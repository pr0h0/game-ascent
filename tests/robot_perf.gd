extends Node
## CPU cost of a busy level: every robot alerted at once, the ship parked and untouchable.
## godot --headless --path . --fixed-fps 60 res://tests/robot_perf.tscn -- level=10 frames=900
## The bench drives the robots, sentries, HUD, cockpit screens and player itself and times
## each one per frame; medians keep other processes on the machine out of the numbers.

var args := {"level": "10", "frames": "900", "warm": "60", "alert": "1"}
var _times := {}
var _hud: CanvasLayer
var _mfds: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	seed(1234)
	Progress.path = "user://test_progress.cfg"
	AudioServer.set_bus_mute(0, true)
	Game.reset_run()
	Game.autopilot = true
	Game.level_index = int(args["level"]) - 1
	add_child(load("res://scenes/level.tscn").instantiate())
	for i in 10:
		await get_tree().physics_frame
	var p: Player = Game.player
	p.shield = 1e9
	p._invuln = 1e9
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()
	var robots := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot)
	if args["alert"] == "1":
		# Everyone is brought within hunting range first, or the far ones would just go home.
		var astar: AStar3D = Game.level.astar
		var near: Array = Array(astar.get_point_ids()).filter(func(id): return astar.get_point_position(id).distance_to(p.global_position) < 170.0 and astar.get_point_position(id).distance_to(p.global_position) > 30.0)
		for r in robots:
			if not r is Boss and not near.is_empty():
				r.global_position = astar.get_point_position(near[randi() % near.size()])
			r.alert()
	_hud = Game.level.get_children().filter(func(n): return n is CanvasLayer and n.has_method("_paint"))[0]
	_hud._draw_layer.draw.disconnect(_hud._paint)
	_hud._draw_layer.draw.connect(func(): _timed("hud", _hud._paint))
	for mfd in p.find_children("*", "CockpitMfd", true, false):
		mfd._canvas.draw.disconnect(mfd._paint)
		mfd._canvas.draw.connect(func(): _timed("mfd", mfd._paint))
		mfd.set_process(false)
		_mfds.append(mfd)
	_hud.set_process(false)
	p.set_physics_process(false)
	p.set_process(false)
	for i in int(args["warm"]):
		await _drive(false)
	print("PERF level=%d robots=%d alerted=%d nodes=%d" % [int(args["level"]), robots.size(), robots.filter(func(r): return is_instance_valid(r) and r.alerted).size(), get_tree().get_node_count()])
	_times.clear()
	var walls: Array = []
	var last := Time.get_ticks_usec()
	for i in int(args["frames"]):
		await _drive(true)
		var now := Time.get_ticks_usec()
		walls.append((now - last) / 1000.0)
		last = now
	var total := 0.0
	var total_mean := 0.0
	for key: String in ["robots", "sentries", "player", "hud", "hud_proc", "mfd"]:
		var list: Array = _times.get(key, [0.0])
		total += _median(list)
		# Screens redraw a few times a second, so their cost is spread over every frame.
		total_mean += _mean(list) * list.size() / float(int(args["frames"]))
		print("PERF %-9s median=%.3f ms  mean=%.3f ms  p95=%.3f ms" % [key, _median(list), _mean(list), _pct(list, 0.95)])
	var live := get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot)
	var near := live.filter(func(r): return r.global_position.distance_to(Game.player.global_position) < 50.0).size()
	print("PERF at end: robots=%d with_los=%d within_50m=%d alerted=%d" % [live.size(), live.filter(func(r): return r.has_los).size(), near, live.filter(func(r): return r.alerted).size()])
	var modes := {}
	for r in live:
		var key: String = "%s/%s/%s" % [r.mode, "path" if r._path_i < r._path.size() else "nopath", "hit" if r.get_slide_collision_count() > 0 else "free"]
		modes[key] = modes.get(key, 0) + 1
	print("PERF modes ", modes)
	print("PERF scripts  median_sum=%.3f ms  mean_per_frame=%.3f ms  frame wall median=%.3f ms" % [total, total_mean, _median(walls)])
	print("PERF_DONE")
	get_tree().quit()


func _timed(key: String, f: Callable) -> void:
	var t := Time.get_ticks_usec()
	f.call()
	_add(key, (Time.get_ticks_usec() - t) / 1000.0)


func _add(key: String, ms: float) -> void:
	if not _times.has(key):
		_times[key] = []
	_times[key].append(ms)


## One frame: physics for the robots, sentries and ship, then the HUD and screens' process.
func _drive(record: bool) -> void:
	await get_tree().physics_frame
	var dt := 1.0 / Engine.physics_ticks_per_second
	var robots: Array = []
	var sentries: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Robot:
			robots.append(e)
		elif e is Sentry:
			sentries.append(e)
		if (e is Robot or e is Sentry) and e.is_physics_processing():
			e.set_physics_process(false)
	var t := Time.get_ticks_usec()
	for r in robots:
		if is_instance_valid(r) and r.is_inside_tree():
			r._physics_process(dt)
	var t2 := Time.get_ticks_usec()
	for s in sentries:
		if is_instance_valid(s) and s.is_inside_tree():
			s._physics_process(dt)
	var t3 := Time.get_ticks_usec()
	var p: Player = Game.player
	p._physics_process(dt)
	p._process(dt)
	var t4 := Time.get_ticks_usec()
	_hud._process(dt)
	for mfd in _mfds:
		mfd._process(dt)
	var t5 := Time.get_ticks_usec()
	if record:
		_add("robots", (t2 - t) / 1000.0)
		_add("sentries", (t3 - t2) / 1000.0)
		_add("player", (t4 - t3) / 1000.0)
		_add("hud_proc", (t5 - t4) / 1000.0)
	await get_tree().process_frame


func _median(list: Array) -> float:
	return _pct(list, 0.5)


func _pct(list: Array, q: float) -> float:
	if list.is_empty():
		return 0.0
	var sorted := list.duplicate()
	sorted.sort()
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]


func _mean(list: Array) -> float:
	var s := 0.0
	for v: float in list:
		s += v
	return s / maxf(list.size(), 1.0)
