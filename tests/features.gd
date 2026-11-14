extends Node
## Audio, difficulty, afterburner, checkpoints, automap, ranks and combat feedback.
## godot --headless --path . res://tests/features.tscn

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
	Saves.dir = "user://test_feature_saves"
	Settings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(Progress.path)
	_check_sound_files()
	await _check_music()
	await _check_wall_parts()
	await _check_level_features()
	_check_ranks()
	DirAccess.remove_absolute(Progress.path)
	DirAccess.remove_absolute(Settings.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _script_sources() -> Array:
	var out: Array = []
	for file in DirAccess.get_files_at("res://scripts"):
		if file.ends_with(".gd"):
			out.append(FileAccess.get_file_as_string("res://scripts/" + file))
	return out


## A typo in a sound name only shows up as silence, so check every name in the code.
func _check_sound_files() -> void:
	var names := {}
	var pattern := RegEx.create_from_string("Sfx\\.(?:play|loop|positional_loop)\\(\"([a-z0-9_]+)\"")
	var literals := RegEx.create_from_string("\"((?:mine|robot|explode|enemy_shot|pickup|hit|laser|ui|map)_[a-z0-9_]+|shield_absorb|missile|prism|arc|flare|heal)\"")
	for source: String in _script_sources():
		for m in pattern.search_all(source):
			names[m.get_string(1)] = true
		for m in literals.search_all(source):
			var candidate := m.get_string(1)
			if FileAccess.file_exists("res://assets/audio/%s.wav" % candidate):
				names[candidate] = true
	var missing: Array = names.keys().filter(func(n): return load("res://assets/audio/%s.wav" % n) == null)
	check(names.size() > 25 and missing.is_empty(), "all %d sounds used in code exist %s" % [names.size(), missing])
	for level: int in [1, 2, 3, 4]:
		check(load("res://assets/audio/laser_%d.wav" % level) != null, "laser tier %d has its own sound" % level)
	for tier: String in ["tiny", "small", "medium", "big", "boss"]:
		check(load("res://assets/audio/explode_%s.wav" % tier) != null, "explosion size %s has a sound" % tier)


func _check_music() -> void:
	for song: String in ["shift", "smelter", "glass", "core"]:
		var calm: AudioStream = load("res://assets/music/%s_calm.ogg" % song)
		var combat: AudioStream = load("res://assets/music/%s_combat.ogg" % song)
		check(calm != null and combat != null, song + " has both stems")
		check(absf(calm.get_length() - combat.get_length()) < 0.05, "%s stems match in length (%.2f / %.2f)" % [song, calm.get_length(), combat.get_length()])
	for track: String in ["menu", "boss", "escape", "sting_win", "sting_lose"]:
		check(load("res://assets/music/%s.ogg" % track) != null, track + " music exists")
	for level: Dictionary in Game.levels:
		check(level.has("music") and FileAccess.file_exists("res://assets/music/%s_calm.ogg" % level["music"]), level["name"] + " has a song")
		check(FileAccess.file_exists("res://assets/audio/%s.wav" % level.get("ambience", "")), level["name"] + " has an ambience bed")
	Music.play_song("shift")
	check(Music.current == "shift", "a mine song starts")
	await get_tree().create_timer(0.2).timeout
	Music.play_song("shift")
	check(Music.current == "shift", "asking for the same song doesn't restart it")
	Music.report_combat()
	await get_tree().create_timer(0.5).timeout
	check(Music.combat_level > 0.2, "combat raises the fight stem (%.2f)" % Music.combat_level)
	Music._hold = 0.0
	var peak := Music.combat_level
	await get_tree().create_timer(0.5).timeout
	check(Music.combat_level < peak, "it fades when the fight ends")
	Music.play_track("boss")
	check(Music.current == "boss", "tracks replace songs")
	Music.sting("sting_win")
	check(Music.current == "", "a sting stops the current track")
	# The voice limiter: firing one sound many times can't pile up without bound.
	var start: int = Sfx.played_total
	for i in 50:
		Sfx.play("hit_confirm", null, -60.0)
	check(Sfx.played_total - start <= Sfx.MAX_VOICES, "same-frame repeats are limited (%d played)" % (Sfx.played_total - start))
	for bus: String in ["Effects", "Interface", "Ambience", "Music"]:
		check(AudioServer.get_bus_index(bus) >= 0, bus + " bus exists")
	check(Settings.KEYS.has("music_volume"), "music volume is saved")


## Every level's details come from the shared library, in whole transforms.
func _check_wall_parts() -> void:
	var library: Dictionary = WallParts._library()
	check(library.size() >= 20, "the wall part library loaded (%d parts)" % library.size())
	for level: Dictionary in Game.levels:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(level["data"]))
		var chunks: Dictionary = data.get("wall_parts", {})
		var known := true
		var whole := true
		for chunk: String in chunks:
			for part: String in chunks[chunk]:
				known = known and library.has(part)
				whole = whole and int(chunks[chunk][part].size()) % 12 == 0
		check(not chunks.is_empty() and known, level["name"] + " only uses parts that exist")
		check(whole, level["name"] + " stores complete transforms")
	var holder := Node3D.new()
	add_child(holder)
	var placed := WallParts.populate(holder, {"wall_parts": {"0_0_0": {"vent": [1, 0, 0, 5, 0, 1, 0, 6, 0, 0, 1, 7]}}})
	await get_tree().process_frame
	var batch: MultiMeshInstance3D = holder.get_child(0)
	check(placed == 1, "placing reports its count")
	# The headless renderer discards instance data, so this needs a real one.
	if DisplayServer.get_name() != "headless":
		check(batch.multimesh.get_instance_transform(0).origin == Vector3(5, 6, 7), "an instance lands where the level says")
	for i in batch.multimesh.mesh.get_surface_count():
		var mat: Material = batch.multimesh.mesh.surface_get_material(i)
		check(mat is StandardMaterial3D and mat.albedo_color != Color(1, 0, 1), "part surfaces use the real materials")
	holder.free()


func _load_level(index: int) -> Node:
	Game.reset_run()
	Game.level_index = index
	Game.level_start = Game._make_snapshot()
	var node: Node = load("res://scenes/level.tscn").instantiate()
	add_child(node)
	await frames(10)
	return node


func _check_level_features() -> void:
	# ---- Difficulty
	Game.difficulty = 0
	var node: Node = await _load_level(1)
	var p: Player = Game.player
	check(Game.lives == 5, "Recruit gets 5 lives")
	var robot: Robot = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot and e.kind == "tick")[0]
	check(is_equal_approx(robot.hp, 34.0 * 0.8), "Recruit robots have less armour (%.1f)" % robot.hp)
	check(is_equal_approx(robot.hp_ratio(), 1.0), "hit points still read as 100%")
	var before := p.shield
	p._invuln = 0.0
	p.take_damage(10.0, p.global_position, robot)
	check(is_equal_approx(before - p.shield, 6.0), "Recruit takes reduced damage (%.1f)" % (before - p.shield))
	before = p.shield
	p.take_damage(10.0, p.global_position, null)
	check(is_equal_approx(before - p.shield, 10.0), "wall scrapes ignore difficulty")
	node.free()
	await frames(4)
	Game.difficulty = 3
	node = await _load_level(1)
	p = Game.player
	check(Game.lives == 2, "Nightmare gets 2 lives")
	robot = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot and e.kind == "tick")[0]
	check(is_equal_approx(robot.hp, 34.0 * 1.5), "Nightmare robots are tougher (%.1f)" % robot.hp)
	var snap: Dictionary = Game._make_snapshot()
	check(int(snap["difficulty"]) == 3, "difficulty is stored in saves")
	Game.difficulty = 1
	Game._apply_snapshot(snap)
	check(Game.difficulty == 3, "difficulty is restored from saves")
	Game._apply_snapshot({"level_index": 0, "score": 0, "lives": 3, "kills": 0, "run_time": 0.0, "shield": 100.0, "energy": 100.0, "missiles": 6})
	check(Game.difficulty == Game.DEFAULT_DIFFICULTY, "older saves load as Pilot")
	node.free()
	await frames(4)

	# ---- Afterburner, combat feedback, checkpoints
	Game.difficulty = 1
	node = await _load_level(2)
	p = Game.player
	var level: Node3D = Game.level
	Game.autopilot = true
	for e in get_tree().get_nodes_in_group("enemy"):
		e.set_physics_process(false)
		e.set_process(false)
	p.energy = 100.0
	p._invuln = 1e6
	Input.action_press("afterburner")
	await frames(30)
	check(p.afterburning, "holding the key lights the afterburner")
	check(p.energy < 100.0, "the afterburner burns energy (%.1f)" % p.energy)
	p.energy = 0.0
	await frames(3)
	check(not p.afterburning, "it cuts out with an empty bank")
	Input.action_release("afterburner")
	await frames(3)

	var hits := [0, 0]
	var on_hit := func(killed: bool): hits[1 if killed else 0] += 1
	Game.enemy_hit.connect(on_hit)
	var target: Robot = get_tree().get_nodes_in_group("enemy").filter(func(e): return e is Robot)[0]
	target.take_damage(1.0, target.global_position, p)
	target.take_damage(1e6, target.global_position, p)
	check(hits[0] == 1 and hits[1] == 1, "hits and kills are reported to the HUD")
	Game.enemy_hit.disconnect(on_hit)
	var directions := [0]
	var on_dir := func(_at: Vector3): directions[0] += 1
	Game.player_hit.connect(on_dir)
	p._invuln = 0.0
	p.take_damage(1.0, p.global_position + Vector3.RIGHT * 5.0, target)
	check(directions[0] == 1, "enemy hits report a direction")
	p.take_damage(1.0, p.global_position, null)
	check(directions[0] == 1, "wall scrapes don't")
	Game.player_hit.disconnect(on_dir)
	p._invuln = 1e6

	var first_spawn := p._spawn_transform
	p.global_position = first_spawn.origin + Vector3(40.0, 0.0, 0.0)
	Game.collect_key("blue")
	check(p._spawn_transform.origin.distance_to(first_spawn.origin) > 30.0, "picking up a key sets a checkpoint")
	var marked := p._spawn_transform.origin
	var lives_before := Game.lives
	p._invuln = 0.0
	p.take_damage(1e6, p.global_position, target)
	check(p.dead and Game.deaths == 1 and Game.lives == lives_before - 1, "dying costs a life and counts")
	await get_tree().create_timer(2.6).timeout
	check(not p.dead and p.global_position.distance_to(marked) < 2.0, "respawn happens at the checkpoint")
	p._invuln = 1e6

	# ---- Automap
	var map: Automap = level.automap
	await get_tree().create_timer(0.4).timeout
	var seen_at_start: int = map.explored.size()
	check(seen_at_start > 0 and seen_at_start < level.cell_ids.size(), "the map starts mostly blank (%d cells)" % seen_at_start)
	var far_cell: Vector3 = level.astar.get_point_position(level.astar.get_point_ids()[level.astar.get_point_count() / 2])
	map.reveal_around(far_cell)
	check(map.explored.size() > seen_at_start, "flying somewhere reveals it")
	map.open()
	await get_tree().process_frame
	check(map.is_open and get_tree().paused, "opening the map pauses")
	check(map._lines.mesh != null and map._lines.mesh.get_surface_count() == 1, "the map draws what's been explored")
	map.close()
	check(not map.is_open and not get_tree().paused, "closing resumes")
	Game.player.dead = true
	map.open()
	check(not map.is_open, "no map while dead")
	Game.player.dead = false
	Game.autopilot = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	node.free()
	await frames(4)


func _check_ranks() -> void:
	Game.reset_run()
	Game.level_start = Game._make_snapshot()
	Game.robots_total = 10
	Game.kills = 10
	Game.secrets_total = 2
	Game.secrets_found = 2
	Game.astronauts_total = 1
	Game.astronauts_rescued = 1
	Game.deaths = 0
	check(Game.level_rank() == "S", "a perfect clear is S")
	Game.deaths = 3
	check(Game.level_rank() == "B", "dying costs rank (%s)" % Game.level_rank())
	Game.deaths = 0
	Game.kills = 0
	Game.secrets_found = 0
	Game.astronauts_rescued = 0
	check(Game.level_rank() == "C" or Game.level_rank() == "D", "a bare run ranks low (%s)" % Game.level_rank())
	Progress.record_result(2, 1, 5000, "A")
	Progress.record_result(2, 1, 100, "D")
	check(int(Progress.best(2, 1)["score"]) == 5000 and Progress.best(2, 1)["rank"] == "A", "a worse run keeps the best score")
	check(Progress.best(2, 2).is_empty(), "scores are per difficulty")
