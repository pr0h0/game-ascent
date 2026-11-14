extends Node
## Regression checks for the code-review fixes (docs/review/code_review.md) in sounds,
## projectiles, saves, menus and effects.
## godot --headless --path . res://tests/review_fixes_a.tscn

const SHIP := Vector3(0, 10, 38)

var failures := 0
var p: Player


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find(root: Node, script_class: Variant) -> Node:
	for n in root.find_children("*", "", true, false):
		if is_instance_of(n, script_class):
			return n
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Progress.path = "user://test_review_progress.cfg"
	Saves.dir = "user://test_review_saves"
	Settings.path = "user://test_review_settings.cfg"
	Controls.path = "user://test_review_controls.cfg"
	await get_tree().process_frame
	_check_saves()
	_check_progress()
	_check_controls()
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	p = Game.player
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Robot:
			e.queue_free()
	await frames(2)
	p.global_position = SHIP
	p.shield = 1e6
	await _check_sfx_voices()
	await _check_launch_sounds()
	await _check_bolt_lights()
	_check_fx()
	await _check_pickups()
	_check_doors()
	await _check_automap_pause()
	await _check_settings_panel()
	await _check_bind_rows()
	_check_escape_bonus()
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


# H1: a positional sound freed mid-play (level change, cutscene set cleared) gives its voice back.
func _check_sfx_voices() -> void:
	var sound := "hit_wall"
	Sfx._voices.erase(sound)
	for i in Sfx.MAX_VOICES + 3:
		Sfx._last_played.erase(sound)
		Sfx.play(sound, p.global_position + Vector3(0, 0, -5))
		for child in Game.level.get_children():
			if child is AudioStreamPlayer3D and child.stream == Sfx._stream(sound):
				child.free()
	check(int(Sfx._voices.get(sound, 0)) == 0, "freed sound players release their voice (%d held)" % int(Sfx._voices.get(sound, 0)))
	var before := Sfx.played_total
	Sfx._last_played.erase(sound)
	Sfx.play(sound, p.global_position)
	check(Sfx.played_total == before + 1, "the sound still plays after many were freed mid-play")
	await frames(1)


func _newest_player(stream_name: String) -> AudioStreamPlayer3D:
	var found: AudioStreamPlayer3D = null
	for child in Game.level.get_children():
		if child is AudioStreamPlayer3D and child.stream == Sfx._stream(stream_name):
			found = child
	return found


# H2: launch sounds come from the launch point, not the world origin.
func _check_launch_sounds() -> void:
	var at := p.global_position + Vector3(6, 0, -10)
	for sound in ["missile", "flare", "singularity_fire", "mine_drop"]:
		Sfx._last_played.erase(sound)
	var m := Missile.launch(at, Vector3.FORWARD, null, Game.WORLD | Game.ENEMY, true, 82.0, 0.0)
	var heard := _newest_player("missile")
	check(heard != null and heard.global_position.distance_to(at) < 0.5, "missile launch sound plays where it launches")
	check(m.global_position.distance_to(at) < 0.01, "missile starts at its launch point")
	var f := Flare.launch(at, Vector3.FORWARD)
	heard = _newest_player("flare")
	check(heard != null and heard.global_position.distance_to(at) < 0.5, "flare launch sound plays where it launches")
	var s := Singularity.launch(at, Vector3.FORWARD, 0.0, true)
	heard = _newest_player("singularity_fire")
	check(heard != null and heard.global_position.distance_to(at) < 0.5, "singularity launch sound plays where it launches")
	var mine := Mine.spawn("player", at)
	heard = _newest_player("mine_drop")
	check(heard != null and heard.global_position.distance_to(at) < 0.5, "mine drop sound plays where it lands")
	var m2 := Missile.launch(at, Vector3.FORWARD, null, Game.WORLD | Game.ENEMY, true, 82.0, 0.0)
	check(m.get_child_count() > 0 and m2.get_child_count() > 0 and _trail(m).process_material == _trail(m2).process_material, "missiles share one trail material")
	for n in [m, m2, f, s, mine]:
		if is_instance_valid(n):
			n.queue_free()
	await frames(2)


func _trail(m: Node) -> GPUParticles3D:
	for c in m.get_children():
		if c is GPUParticles3D:
			return c
	return null


# M10: only every third bolt carries its own light.
func _check_bolt_lights() -> void:
	var lit := 0
	var bolts: Array = []
	for i in 9:
		bolts.append(Bolt.launch(SHIP + Vector3(0, 0, -4), Vector3.FORWARD, 1.0, 0.0, Color.WHITE, 0))
	for b: Node in bolts:
		for c in b.get_children():
			if c is OmniLight3D:
				lit += 1
	check(lit == 3, "9 bolts make 3 lights, not 9 (%d)" % lit)
	for b: Node in bolts:
		b.queue_free()
	await frames(1)


# L10, L11: quads are built at the size they're keyed by; shockwaves come from a pool.
func _check_fx() -> void:
	var mat := Fx._sprite("fx_glow")
	var a := Fx._quad(mat, 0.2)
	var b := Fx._quad(mat, 0.31)
	check(a.size.is_equal_approx(Vector2.ONE * 0.2) and b.size.is_equal_approx(Vector2.ONE * 0.3), "small quads keep their own size (%s, %s)" % [a.size, b.size])
	check(Fx._quad(mat, 0.2) == a, "the same size still shares one quad")
	for i in 10:
		Fx.pulse(SHIP + Vector3(0, 0, -6), 20.0, Weapons.ARC_COLOR)
	var spheres := 0
	for child in Game.level.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh and child.mesh == Fx._sphere:
			spheres += 1
	check(spheres > 0 and spheres <= Fx.SHOCKWAVE_POOL, "ten pulses reuse a pool of shockwaves (%d spheres)" % spheres)


# L4: missile pickups stay put when the ship is already full.
func _check_pickups() -> void:
	p.missiles = Pickup.MAX_MISSILES
	var full := Pickup.new()
	full.kind = "ammo"
	Game.level.add_child(full)
	full.global_position = p.global_position
	p.ammo["cluster"] = int(Weapons.SECONDARY["cluster"]["cap"])
	var full_cluster := Pickup.new()
	full_cluster.kind = "ammo_cluster"
	Game.level.add_child(full_cluster)
	full_cluster.global_position = p.global_position
	await frames(3)
	check(is_instance_valid(full) and not full.is_queued_for_deletion(), "a missile pickup is left when missiles are full")
	check(is_instance_valid(full_cluster) and not full_cluster.is_queued_for_deletion(), "a cluster pickup is left when clusters are full")
	p.missiles = Pickup.MAX_MISSILES - 1
	await frames(3)
	check(not is_instance_valid(full) or full.is_queued_for_deletion(), "it is collected once there is room")
	check(p.missiles == Pickup.MAX_MISSILES, "and tops up to the cap (%d)" % p.missiles)
	check(Pickup.MAX_MISSILES == int(Weapons.SECONDARY["homing"]["cap"]), "the missile cap comes from Weapons")
	if is_instance_valid(full_cluster):
		full_cluster.queue_free()


# L8: doors that can't open by proximity, and open ones, don't process.
func _check_doors() -> void:
	var hidden_ok := true
	var entry_ok := true
	var any_hidden := false
	for child in Game.level.get_children():
		if child is Door:
			if child.hidden_door:
				any_hidden = true
				hidden_ok = hidden_ok and not child.is_processing()
			elif child.lock == "entry":
				entry_ok = entry_ok and not child.is_processing()
			elif not child._is_open:
				check(child.is_processing(), "a shut %s door still watches for the ship" % child.lock)
	check(any_hidden and hidden_ok, "hidden doors don't process")
	check(entry_ok, "the entry door doesn't process")
	for child in Game.level.get_children():
		if child is Door and child.hidden_door:
			child._open()
			check(not child.is_processing(), "an opened door stops processing")
			break


func _action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


# M7, L20: Start while the map is up closes the map instead of pausing behind it.
func _check_automap_pause() -> void:
	var pause: PauseMenu = _find(get_tree().root, PauseMenu)
	var map: Automap = Game.level.automap
	map.open()
	check(map.is_open, "the automap opens")
	pause._unhandled_input(_action("pause_game"))
	check(not pause.visible, "Start doesn't open the pause menu over the map")
	map._unhandled_input(_action("pause_game"))
	check(not map.is_open and not get_tree().paused, "Start closes the map and resumes")
	Game.autopilot = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause.open()
	pause.close()
	check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "Resume leaves the mouse free on autopilot")
	Game.autopilot = false
	await frames(1)


# M8, M9: the gamepad page goes with its settings panel; sliders save once, not per tick.
func _check_settings_panel() -> void:
	var holder := Control.new()
	add_child(holder)
	var panel := SettingsPanel.new()
	holder.add_child(panel)
	await frames(2)
	panel._open_gamepad()
	check(panel._gamepad_page.visible, "the gamepad page opens")
	holder.visible = false
	await frames(1)
	check(not panel._gamepad_page.visible, "hiding the settings panel hides the gamepad page")
	holder.visible = true
	var changes := [0]
	var count := func(): changes[0] += 1
	Settings.settings_changed.connect(count)
	var slider: HSlider = null
	for s in panel.find_children("*", "HSlider", true, false):
		if is_equal_approx(s.max_value, 100.0) and is_equal_approx(s.min_value, 65.0):
			slider = s
	var fov0 := Settings.fov
	for v in [70.0, 71.0, 72.0, 73.0, 74.0]:
		slider.value = v
	check(changes[0] == 0 and is_equal_approx(Settings.fov, 74.0), "dragging previews without saving (%d saves)" % changes[0])
	slider.drag_ended.emit(true)
	check(changes[0] == 1, "the drag's end saves once (%d)" % changes[0])
	slider.value = 76.0
	await get_tree().create_timer(0.5).timeout
	check(changes[0] == 2, "a resting value is saved after a moment (%d)" % changes[0])
	Settings.settings_changed.disconnect(count)
	Settings.change("fov", fov0)
	holder.queue_free()
	await frames(1)


# L19: while one slot listens, a left click on another slot moves the listening there.
func _check_bind_rows() -> void:
	var rows := BindRows.new()
	rows.size = Vector2(900, 2000)
	add_child(rows)
	await frames(3)
	var actions := Controls.actions()
	var before: Array = Controls.bindings[Controls.KEYBOARD][actions[1]].duplicate()
	rows.listen(actions[1], 0)
	var other: Button = rows._slots[rows._slot_id(actions[2], 0)]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = other.get_global_rect().get_center()
	rows._input(click)
	check(Controls.bindings[Controls.KEYBOARD][actions[1]] == before, "clicking another slot doesn't bind Left mouse")
	rows.queue_free()


# M5: a progress file that doesn't parse is left alone rather than overwritten.
func _check_progress() -> void:
	var f := FileAccess.open(Progress.path, FileAccess.WRITE)
	f.store_string("[progress\nunlocked_level=== 4 (((")
	f.close()
	Progress.unlock(3)
	Progress.record_result(0, 0, 999, "S")
	check(FileAccess.get_file_as_string(Progress.path).begins_with("[progress\nunlocked_level==="), "a corrupt progress file isn't overwritten")
	DirAccess.remove_absolute(Progress.path)
	Progress.unlock(2)
	check(Progress.unlocked_level() == 2, "progress saves again once the file is gone")
	Progress.record_result(1, 0, 500, "B")
	check(int(Progress.best(1, 0).get("score", 0)) == 500, "a best score is read back from the cache")
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked_level", 4)
	cfg.save(Progress.path)
	check(Progress.unlocked_level() == 4, "an outside change to the file is picked up")
	DirAccess.remove_absolute(Progress.path)


# M6: saves with an impossible difficulty or wrong field types are skipped.
func _check_saves() -> void:
	DirAccess.make_dir_recursive_absolute(Saves.dir)
	for stale in DirAccess.get_files_at(Saves.dir):
		DirAccess.remove_absolute(Saves.dir.path_join(stale))
	var good := {"version": 2, "id": "good", "created_unix": 1.0, "level_index": 0, "score": 0, "lives": 3, "kills": 0, "run_time": 0.0, "shield": 100.0, "energy": 100.0, "missiles": 3, "difficulty": 1}
	var bad_diff := good.duplicate()
	bad_diff["id"] = "bad_diff"
	bad_diff["difficulty"] = 99
	var bad_type := good.duplicate()
	bad_type["id"] = "bad_type"
	bad_type["score"] = "lots"
	for save: Dictionary in [good, bad_diff, bad_type]:
		var f := FileAccess.open(Saves.dir.path_join(save["id"] + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(save))
		f.close()
	var ids := Saves.list().map(func(s): return s["id"])
	check(ids == ["good"], "saves with a bad difficulty or field type are skipped %s" % str(ids))
	var listed := Saves.list()
	listed.clear()
	check(Saves.list().size() == 1, "the cached save list can't be changed by a caller")
	Saves.delete("good")
	check(Saves.list().is_empty(), "deleting a save refreshes the cached list")
	var id := Saves.write(good)
	check(Saves.list().size() == 1 and Saves.list()[0]["id"] == id, "writing a save refreshes the cached list")
	Saves.delete(id)
	for stale in DirAccess.get_files_at(Saves.dir):
		DirAccess.remove_absolute(Saves.dir.path_join(stale))


# L18, L19: malformed controls files and keys with only a logical keycode.
func _check_controls() -> void:
	var cfg := ConfigFile.new()
	var action: String = Controls.actions()[0]
	cfg.set_value(Controls.KEYBOARD, action, [1, 2])
	cfg.set_value(Controls.KEYBOARD, Controls.actions()[1], ["k65", "bogus"])
	cfg.set_value("view", "layout", "xbox")
	cfg.save(Controls.path)
	Controls.load_file()
	check(Controls.bindings[Controls.KEYBOARD][action] == Controls.defaults(Controls.KEYBOARD)[action], "a controls file with non-string codes falls back to defaults")
	check(Controls.bindings[Controls.KEYBOARD][Controls.actions()[1]] == Controls.defaults(Controls.KEYBOARD)[Controls.actions()[1]], "a malformed code falls back to defaults")
	Controls.apply()
	var logical := InputEventKey.new()
	logical.keycode = KEY_F7
	logical.pressed = true
	var code := Controls.code_for(logical, Controls.KEYBOARD)
	var rebuilt := Controls.event_for(code)
	check(rebuilt is InputEventKey and rebuilt.keycode == KEY_F7 and rebuilt.physical_keycode == KEY_NONE, "a logical-only key is rebuilt as that logical key (%s)" % code)
	check(Controls.describe(code) == "F7", "and named as it (%s)" % Controls.describe(code))
	DirAccess.remove_absolute(Controls.path)
	Controls.load_file()
	Controls.apply()


# M1: an extra life crossed by the escape bonus is granted.
func _check_escape_bonus() -> void:
	Game.finished = false
	Game.score = Game.EXTRA_LIFE_EVERY - 100
	Game._life_mark = Game.score / Game.EXTRA_LIFE_EVERY
	Game.lives = 1
	Game.escape_left = 10.0
	Game.end_run(true, "test")
	check(Game.lives == 2, "the escape bonus grants the extra life it crosses (lives %d)" % Game.lives)
