extends Node
## Home screen checks: godot --path . res://tests/menu.tscn -- <screenshot dir>
## Screenshots are only saved when not running headless.

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	Saves.dir = "user://test_menu_saves"
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	DirAccess.remove_absolute(Progress.path)
	_clear()
	# Hand "current scene" to a throwaway node so this test survives real scene changes.
	var holder := Node.new()
	get_tree().root.add_child.call_deferred(holder)
	await get_tree().process_frame
	get_tree().current_scene = holder
	var title: Node = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await _wait(20)
	var menu: MainMenu = title.get_children().filter(func(n): return n is MainMenu)[0]
	check(menu.buttons["continue"].disabled and menu.buttons["load"].disabled, "Continue and Load are disabled with no saves")
	check(not menu.buttons["new"].disabled, "New Game is always available")
	for score in [1200, 4300, 9100]:
		Saves.write({"level_index": 0, "score": score, "lives": 3, "kills": 2, "run_time": 40.0, "shield": 100.0, "energy": 100.0, "missiles": 6})
		await get_tree().create_timer(0.01).timeout
	menu.show_panel("main")
	await _wait(5)
	check(not menu.buttons["continue"].disabled and not menu.buttons["load"].disabled, "Continue and Load enable once saves exist")
	_shot("menu_main")
	menu.show_panel("load")
	await _wait(5)
	check(menu.load_rows.get_child_count() == 3, "load screen lists every save")
	check(int(Saves.latest()["score"]) == 9100, "Continue targets the newest save")
	_shot("menu_load")
	var row: Control = menu.load_rows.get_child(0)
	var delete_button: Button = row.get_child(1)
	delete_button.pressed.emit()
	await _wait(2)
	check(Saves.list().size() == 3, "first Delete press only asks to confirm")
	delete_button.pressed.emit()
	await _wait(2)
	check(Saves.list().size() == 2 and menu.load_rows.get_child_count() == 2, "second press deletes that save")
	menu.show_panel("settings")
	await _wait(5)
	_shot("menu_settings")
	Settings.path = "user://test_settings.cfg"
	Settings.change("mouse_sensitivity", 1.75)
	Settings.mouse_sensitivity = 1.0
	Settings.load_settings()
	check(is_equal_approx(Settings.mouse_sensitivity, 1.75), "settings persist to disk")
	Settings.change("mouse_sensitivity", 1.0)
	if DisplayServer.get_name() != "headless":
		var was_fullscreen: bool = Settings.fullscreen
		for on: bool in [not was_fullscreen, was_fullscreen]:
			Settings.change("fullscreen", on)
			await _wait(20)
			var mode := DisplayServer.window_get_mode()
			var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			check(is_full == on, "fullscreen switches instantly to %s" % on)
	DirAccess.remove_absolute(Settings.path)
	Settings.path = "user://settings.cfg"

	Settings.show_story = false
	# New Game asks for a difficulty first.
	menu.buttons["new"].pressed.emit()
	await _wait(2)
	check(menu.current == "difficulty" and menu.difficulty_buttons.size() == Game.DIFFICULTIES.size(), "New Game offers every difficulty")
	_shot("menu_difficulty")
	menu.show_panel("main")

	# Level picker: only unlocked levels can be started.
	menu.show_panel("levels")
	await _wait(3)
	check(menu.level_rows.get_child_count() == Game.levels.size(), "picker lists every level")
	check(not menu.level_rows.get_child(0).disabled and menu.level_rows.get_child(1).disabled, "only level one starts unlocked")
	_shot("menu_levels")

	# Gallery: everything is listed, but only what's in unlocked levels can be opened.
	var all := GalleryData.entries()
	for entry in all:
		check(ResourceLoader.exists(entry["model"]) and not entry["lore"].is_empty() and not entry["stats"].is_empty(), "gallery entry complete: " + entry["id"])
	menu.show_panel("gallery")
	await _wait(5)
	var g: GalleryPanel = menu.gallery
	check(g.rows.size() == all.size(), "every entry is listed")
	for id in ["wren9", "tick", "lancer", "sentry", "key_blue", "reactor", "shield", "energy", "ammo", "door"]:
		check(not g.rows[id].disabled, id + " is unlocked from the start")
	for id in ["bulwark", "astronaut", "key_yellow", "key_red", "arc_caster", "overseer", "mine_tripwire", "power_cloak"]:
		check(g.rows[id].disabled and g.rows[id].text == "? ? ?", id + " is locked until level two")
	check(title._showcase != null and not title._ship.visible, "gallery shows the selected model on the pad")
	_shot("gallery")
	Progress.unlock(1)
	menu.show_panel("gallery")
	await _wait(3)
	check(not g.rows["bulwark"].disabled and not g.rows["astronaut"].disabled and not g.rows["key_red"].disabled, "unlocking level two reveals its contents")
	for entry in all:
		if entry["id"] == "bulwark" or entry["id"] == "key_red":
			g.select(entry)
			await _wait(4)
			_shot("gallery_" + entry["id"])
	menu.show_panel("main")
	await _wait(3)
	check(title._showcase == null and title._ship.visible, "leaving the gallery brings the ship back")

	# Home-screen ship: drag orbits, scroll zooms, and both respect their limits.
	var yaw0: float = title.yaw
	title.orbit(Vector2(120, 0))
	check(title.yaw != yaw0, "dragging orbits the ship")
	title.orbit(Vector2(0, 99999))
	check(title.pitch == title.MAX_PITCH, "orbit stops at the pole")
	var spun: float = title.yaw
	await _wait(5)
	check(title.yaw == spun, "auto-spin waits after the player touches it")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var d0: float = title.distance
	title._unhandled_input(wheel)
	check(title.distance < d0, "scroll wheel zooms in")
	for i in 100:
		title.zoom(-5.0)
	check(title.distance == title.MIN_DISTANCE, "zoom stops at its limit")
	title.pitch = 0.2
	title.yaw = 2.2
	await _wait(60)
	_shot("menu_zoom")
	title.distance = title.DEFAULT_DISTANCE
	title.pitch = -1.0
	await _wait(60)
	check(not title._pad[0].visible, "pad hides when viewing the ship from below")
	_shot("menu_below")

	# Real flow through scene changes.
	var before: int = Saves.list().size()
	title.queue_free()

	# Starting from the picker: fresh stats on the chosen level, and a new save.
	Game.score = 4242
	Game.start_level(1)
	await _wait_for_new_player(null)
	check(Game.level_index == 1 and Game.score == 0, "picker starts the chosen level fresh")
	check(Game.player.shield == 100.0 and Game.player.energy == 100.0 and Game.player.missiles == int(Game.levels[1]["base_missiles"]), "level start gives 100/100 and base ammo")
	check(Saves.list().size() == before + 1 and int(Saves.latest()["level_index"]) == 1, "picking a level writes its snapshot")
	before = Saves.list().size()
	var picked_ship = Game.player
	Game.new_game()
	await _wait_for_new_player(picked_ship)
	check(Game.player != null and is_instance_valid(Game.player), "New Game loads the level")
	check(Saves.list().size() == before + 1, "New Game writes one level-start snapshot")
	check(Game.player.shield == 100.0 and Game.player.energy == 100.0, "New Game starts at 100/100")
	var first_ship = Game.player
	first_ship.shield = 12.0
	Game.score = 777
	Game.restart_level()
	await _wait_for_new_player(first_ship)
	check(Game.player.shield == 100.0 and Game.score == 0, "retry restores the start of the level")
	check(Saves.list().size() == before + 1, "retrying does not add a save")
	var second_ship = Game.player
	Game.continue_game()
	await _wait_for_new_player(second_ship)
	check(is_instance_valid(Game.player) and Saves.list().size() == before + 1, "Continue loads without adding a save")

	# Pause menu.
	await _wait(30)
	var hud: Node = Game.level.get_children().filter(func(n): return n is CanvasLayer and n.get("pause_menu") != null)[0]
	var pause: PauseMenu = hud.pause_menu
	pause.open()
	await _wait(3)
	check(get_tree().paused and pause.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "pause stops the game and frees the mouse")
	check(pause.size == get_viewport().get_visible_rect().size, "pause menu fills the screen")
	_shot("pause")
	pause.buttons["settings"].pressed.emit()
	await _wait(3)
	check(pause._settings.visible and not pause._main.visible, "Settings opens inside the pause menu")
	Settings.path = "user://test_settings.cfg"
	Settings.change("fov", 95.0)
	check(Game.player.cam.fov == 95.0, "field of view changes live while paused")
	Settings.change("fov", 80.0)
	DirAccess.remove_absolute(Settings.path)
	Settings.path = "user://settings.cfg"
	pause._settings.back_pressed.emit()
	await _wait(2)
	pause.buttons["resume"].pressed.emit()
	await _wait(3)
	check(not get_tree().paused and not pause.is_open(), "Resume returns to the game")

	# Results.
	Game.score = 4200
	Game.escape_left = 37.0
	Game.end_run(true, "You outran the blast with 37 seconds on the clock.")
	await _wait(90)
	var results: ResultsScreen = hud.results
	check(results.visible and results.stats["Time to spare"] == "37 s" and results.stats["Escape bonus"] == "+3700" and results.stats["Score"] == "7900", "win screen shows the bonus and final score")
	check(Progress.is_unlocked(1), "winning unlocks the next level")
	check(results.primary.text == "Next Level", "finishing level one offers the next level")
	check(results.size == get_viewport().get_visible_rect().size, "win screen fills the screen")
	_shot("win")
	Game.finished = false
	Game.to_title()
	await _wait(10)
	check(get_tree().current_scene.name == "Title", "main menu returns from a level")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.remove_absolute(Progress.path)
	_clear()
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _wait_for_new_player(old: Object) -> void:
	for i in 900:
		await get_tree().process_frame
		if is_instance_valid(Game.player) and Game.player != old and Game.player.is_inside_tree():
			return


func _clear() -> void:
	if DirAccess.dir_exists_absolute(Saves.dir):
		for f in DirAccess.get_files_at(Saves.dir):
			DirAccess.remove_absolute(Saves.dir.path_join(f))


func _shot(shot_name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not args.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [args[0], shot_name])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
