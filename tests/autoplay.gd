extends Node
## Plays levels start to finish with the autopilot and reports frame rates and anything odd.
##
## On the GPU:  godot --path . --resolution 1920x1080 res://tests/autoplay.tscn -- levels=1,10
## Logic only:  godot --headless --path . res://tests/autoplay.tscn -- levels=all speed=4
## Options:     levels=all|1,2,3  difficulty=0-3  speed=1  max=1500  immortal=1
##              audio=1  shots=<dir>  report=<file.json>  hunt=0  carry=0

var args := {"levels": "all", "difficulty": "1", "speed": "1", "max": "1500", "immortal": "0", "audio": "0", "shots": "", "report": "", "hunt": "1", "carry": "1", "shot_every": "25"}
var _report: Array = []
var _exit_failures := 0
var _carry_upgrades: Array = []
var _carry_ammo: Dictionary = {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			args[parts[0]] = parts[1]
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_autoplay_saves"
	Game.autopilot = true
	Game.difficulty = int(args["difficulty"])
	Settings.invert_y = false
	Settings.mouse_sensitivity = 1.0
	Settings.vsync = false
	if args["audio"] != "1":
		AudioServer.set_bus_mute(0, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var chosen: Array = []
	if args["levels"] == "all":
		chosen = range(Game.levels.size())
	else:
		for token in args["levels"].split(","):
			chosen.append(int(token) - 1)
	for index: int in chosen:
		await _play(index)
	_finish()


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var path: String = args["report"]
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(_report, "  "))
	print("AUTOPLAY_DONE problems=%d" % _exit_failures)
	DirAccess.remove_absolute(Progress.path)
	get_tree().quit(0)


func _pct(sorted_ms: Array, q: float) -> float:
	if sorted_ms.is_empty():
		return 0.0
	return sorted_ms[clampi(int(sorted_ms.size() * q), 0, sorted_ms.size() - 1)]


func _play(index: int) -> void:
	Engine.time_scale = 1.0
	Game.reset_run()
	Game.level_index = index
	Game.start_missiles = Game.levels[index]["base_missiles"]
	Game.start_ammo = Game.base_ammo(index)
	Game.level_start = Game._make_snapshot()
	if args["carry"] == "1":
		# Flown as a campaign: everything from earlier levels is already installed.
		Game.upgrades = _earlier_kit(index)
		Game.level_start["upgrades"] = Game.upgrades.duplicate()
	var load_start := Time.get_ticks_msec()
	var node: Node = load("res://scenes/level.tscn").instantiate()
	add_child(node)
	var load_ms := Time.get_ticks_msec() - load_start
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Player = Game.player
	# Screenshots should show a normal number of lives, not the bot's safety net.
	# Screenshots and recordings should show a normal number of lives, not the bot's safety net.
	var showing: bool = args["shots"] != "" or OS.has_feature("movie")
	Game.lives = 5 if showing else 99
	if OS.has_feature("movie"):
		Settings.show_fps = false
	if args["immortal"] == "1":
		p.invincible_left = 1e9
	var bot := Autopilot.new()
	bot.hunt_secrets = args["hunt"] == "1"
	add_child(bot)
	bot.max_seconds = float(args["max"])
	bot.begin(p, Game.level)
	var speed := float(args["speed"])
	# The first frames are spent compiling; they would drown out the real numbers.
	for i in 30:
		await get_tree().process_frame
	Engine.time_scale = speed
	var ms: Array = []
	var cpu_ms: Array = []
	var gpu_ms: Array = []
	var draw_calls := 0.0
	var prims := 0.0
	var objects := 0.0
	var peak_nodes := 0
	var peak_objects := 0
	var worst_frames: Array = []
	var last := Time.get_ticks_usec()
	var shots_dir: String = args["shots"]
	var next_shot := 3.0
	var shot_count := 0
	var vp := get_viewport().get_viewport_rid()
	# Balance numbers for tools/refresh.sh: damage, resources spent, deaths and pickups left behind.
	var tally := {"damage": 0.0, "energy": 0.0, "ammo": 0, "deaths": []}
	var on_hurt := func(amount: float) -> void: tally["damage"] += amount
	var on_died := func() -> void: tally["deaths"].append({"t": snappedf(bot.elapsed, 0.1), "pos": "%v" % p.global_position.snapped(Vector3.ONE), "by": p.last_attacker, "goal": bot.goal_kind})
	Game.player_hurt.connect(on_hurt)
	Game.player_died.connect(on_died)
	var placed: Array = get_tree().get_nodes_in_group("pickup")
	var last_energy: float = p.energy
	var last_ammo := _ammo_count(p)
	while not bot.done and bot.elapsed < bot.max_seconds:
		await get_tree().process_frame
		if is_instance_valid(p):
			tally["energy"] += maxf(0.0, last_energy - p.energy)
			last_energy = p.energy
			var ammo_now := _ammo_count(p)
			tally["ammo"] += maxi(0, last_ammo - ammo_now)
			last_ammo = ammo_now
		var now := Time.get_ticks_usec()
		var frame_ms := (now - last) / 1000.0
		last = now
		if Game.cinematic:
			continue
		ms.append(frame_ms)
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		draw_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		objects += obj
		peak_objects = maxi(peak_objects, obj)
		peak_nodes = maxi(peak_nodes, get_tree().get_node_count())
		if frame_ms > 40.0:
			worst_frames.append("%.0fms@%.0fs(%s) proc=%.0f phys=%.0f gpu=%.0f bolts+fx nodes=%d" % [frame_ms, bot.elapsed, bot.goal_kind, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, gpu_ms[-1], get_tree().get_node_count()])
		if shots_dir != "" and bot.elapsed > next_shot:
			next_shot += float(args["shot_every"])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/L%02d_%03d.png" % [shots_dir, index + 1, shot_count])
			shot_count += 1
			last = Time.get_ticks_usec()
	Game.player_hurt.disconnect(on_hurt)
	Game.player_died.disconnect(on_died)
	var missed: Array = []
	for item in placed:
		if is_instance_valid(item) and item.is_inside_tree():
			missed.append(item.kind)
	if not Game.finished:
		bot.note("TIMEOUT after %.0f s, last goal %s" % [bot.elapsed, bot.goal_kind])
		_exit_failures += 1
	var won: bool = Game.finished and Game.won
	var frames := ms.size()
	var total_ms := 0.0
	for v in ms:
		total_ms += v
	ms.sort()
	cpu_ms.sort()
	gpu_ms.sort()
	var entry := {
		"level": index + 1, "name": Game.levels[index]["name"], "won": won, "seconds": snappedf(bot.elapsed, 0.1),
		"load_ms": load_ms, "frames": frames,
		"fps_avg": snappedf(1000.0 * frames / maxf(total_ms, 1.0), 0.1),
		"ms_p50": snappedf(_pct(ms, 0.5), 0.1), "ms_p95": snappedf(_pct(ms, 0.95), 0.1), "ms_p99": snappedf(_pct(ms, 0.99), 0.1), "ms_max": snappedf(_pct(ms, 1.0), 0.1),
		"cpu_p50": snappedf(_pct(cpu_ms, 0.5), 0.1), "gpu_p50": snappedf(_pct(gpu_ms, 0.5), 0.1), "gpu_p95": snappedf(_pct(gpu_ms, 0.95), 0.1),
		"draw_calls": int(draw_calls / maxf(frames, 1.0)), "primitives": int(prims / maxf(frames, 1.0)), "objects": int(objects / maxf(frames, 1.0)), "peak_objects": peak_objects, "peak_nodes": peak_nodes,
		"deaths": Game.deaths, "kills": Game.kills, "robots": Game.robots_total, "secrets": "%d/%d" % [Game.secrets_found, Game.secrets_total],
		"astronauts": "%d/%d" % [Game.astronauts_rescued, Game.astronauts_total], "score": Game.score, "rank": Game.level_rank(), "escape_left": snappedf(Game.escape_left, 0.1),
		"difficulty": Game.difficulty, "damage_taken": snappedf(tally["damage"], 0.1), "energy_used": snappedf(tally["energy"], 0.1), "ammo_used": tally["ammo"],
		"pickups_total": placed.size(), "pickups_missed": missed, "death_spots": tally["deaths"],
		"stuck": bot.stuck_events, "teleports": bot.teleports, "weapons": bot.weapons_used.keys(), "missiles": bot.missiles_used.keys(), "spikes": worst_frames.slice(0, 12), "spike_count": worst_frames.size(), "log": bot.log_lines,
	}
	_report.append(entry)
	if not won or bot.stuck_events > 0:
		_exit_failures += 1
	print("LEVEL %d %s won=%s time=%.0fs fps=%.0f p50=%.1f p95=%.1f p99=%.1f max=%.0f gpu=%.1f cpu=%.1f draws=%d prims=%dk objs=%d load=%.1fs deaths=%d kills=%d/%d secrets=%s astro=%s rank=%s stuck=%d tp=%d weapons=%s missiles=%s spikes=%d nodes=%d" % [
		index + 1, Game.levels[index]["name"], won, bot.elapsed, entry["fps_avg"], entry["ms_p50"], entry["ms_p95"], entry["ms_p99"], entry["ms_max"], entry["gpu_p50"], entry["cpu_p50"],
		entry["draw_calls"], entry["primitives"] / 1000, entry["objects"], load_ms / 1000.0, Game.deaths, Game.kills, Game.robots_total, entry["secrets"], entry["astronauts"], entry["rank"], bot.stuck_events, bot.teleports, entry["weapons"], entry["missiles"], worst_frames.size(), peak_nodes])
	for line: String in bot.log_lines:
		print("   " + line)
	Engine.time_scale = 1.0
	bot.queue_free()
	node.queue_free()
	Sfx.stop_all_loops()
	await get_tree().process_frame
	await get_tree().process_frame


func _ammo_count(p: Player) -> int:
	var n := 0
	for v in p.ammo.values():
		n += int(v)
	return n


## What a player who collected everything would be carrying at this point.
func _earlier_kit(index: int) -> Array:
	var out: Array = []
	for i in index:
		for item in GalleryData.level_data(i)["pickups"]:
			var kind: String = item["type"]
			if kind.begins_with("upgrade_"):
				var name_text := kind.trim_prefix("upgrade_")
				if not out.has(name_text):
					out.append(name_text)
	return out
