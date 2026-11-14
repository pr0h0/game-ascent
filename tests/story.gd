extends Node
## Every chapter must play to its end, skip cleanly and hand off to the right place.
## godot --headless --path . res://tests/story.tscn
## With a directory after "--", also saves a frame of each shot (needs a display).

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_story_saves"
	DirAccess.remove_absolute(Progress.path)
	_check_data()
	var shots_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for i in StoryData.CHAPTERS.size():
		await _play_chapter(i, shots_dir)
	await _check_skip()
	await _check_flow()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _check_data() -> void:
	check(StoryData.CHAPTERS.size() == Game.levels.size() + 1, "one chapter per level, plus the ending")
	for i in Game.levels.size():
		check(StoryData.CHAPTERS[i]["title"] == Game.levels[i]["name"], "chapter %d is titled after its level" % (i + 1))
	var stages := Cutscene.new()
	for chapter: Dictionary in StoryData.CHAPTERS:
		check(chapter["shots"].size() >= 2, "%s has several shots" % chapter["title"])
		for shot: Dictionary in chapter["shots"]:
			check(stages.has_method("_stage_" + str(shot["stage"])), "stage exists: " + str(shot["stage"]))
			for kind in shot.get("actors", []):
				check(ResourceLoader.exists("res://assets/models/%s.glb" % kind), "actor model exists: " + str(kind))
			if shot["stage"] == "mine":
				check(int(shot["level"]) < Game.levels.size(), "mine shot names a real level")
			for line: Array in shot["lines"]:
				check(StoryData.SPEAKER_COLORS.has(line[0]), "known speaker: " + str(line[0]))
				check(str(line[1]).length() <= 140, "line fits on screen: " + str(line[1]).left(30))
	stages.free()


func _make(index: int) -> Cutscene:
	Game.story_chapter = index
	Game.after_story = "test"
	var scene: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(scene)
	return scene


func _play_chapter(index: int, shots_dir: String) -> void:
	var scene := _make(index)
	var title: String = StoryData.CHAPTERS[index]["title"]
	await get_tree().process_frame
	check(scene.state == Cutscene.State.CARD, title + ": opens on its title card")
	var seen := {}
	var saw_text := false
	var guard := 0
	# Taps through at speed, the way an impatient player would.
	while scene.state != Cutscene.State.DONE and scene.state != Cutscene.State.CREDITS and guard < 4000:
		guard += 1
		await get_tree().process_frame
		if scene.shot_index >= 0 and scene._line.text != "":
			saw_text = true
			if not seen.has(scene.shot_index):
				seen[scene.shot_index] = true
				if shots_dir != "":
					for i in 25:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("%s/ch%02d_%d.png" % [shots_dir, index, scene.shot_index])
		if scene.state == Cutscene.State.TYPING or scene.state == Cutscene.State.HOLD or scene.state == Cutscene.State.CARD:
			scene.advance()
	check(guard < 4000, title + ": plays through")
	check(saw_text, title + ": shows dialogue")
	check(seen.size() == StoryData.CHAPTERS[index]["shots"].size(), "%s: every shot was shown (%d)" % [title, seen.size()])
	if index == StoryData.ENDING:
		check(scene.state == Cutscene.State.CREDITS and scene._credits.visible, "the ending rolls credits")
	if Game.level != null:
		check(false, title + ": left Game.level set")
	if scene.is_inside_tree() and scene.state != Cutscene.State.DONE:
		scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check_skip() -> void:
	var scene := _make(0)
	await get_tree().process_frame
	scene.advance()
	for i in 90:
		await get_tree().process_frame
	check(scene.shot_index == 0, "the first shot starts")
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	for i in 60:
		await get_tree().process_frame
	check(scene.state == Cutscene.State.DONE, "Esc skips the rest")
	scene.queue_free()
	await get_tree().process_frame


func _scene_is(path: String) -> bool:
	return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path


func _settle() -> void:
	for i in 12:
		await get_tree().process_frame


## These calls replace the running scene, so this test steps aside first and survives them.
func _check_flow() -> void:
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	Settings.show_story = true
	Game.difficulty = 1
	Game.new_game()
	await _settle()
	check(_scene_is("res://scenes/cutscene.tscn") and Game.story_chapter == 0, "New Game opens with the story")
	check(Game.after_story == "level", "the story leads into the level")
	(get_tree().current_scene as Cutscene).skip()
	for i in 80:
		await get_tree().process_frame
	await _settle()
	check(_scene_is("res://scenes/level.tscn") and Game.player != null, "skipping lands in the level")
	Game.player.shield = 150.0
	Game.next_level()
	await _settle()
	check(_scene_is("res://scenes/cutscene.tscn") and Game.story_chapter == 1, "the next level gets its chapter")
	(get_tree().current_scene as Cutscene).skip()
	for i in 80:
		await get_tree().process_frame
	await _settle()
	check(_scene_is("res://scenes/level.tscn") and Game.level_index == 1, "that chapter leads into level 2")
	Settings.show_story = false
	Game.next_level()
	await _settle()
	check(_scene_is("res://scenes/level.tscn") and Game.level_index == 2, "the setting turns the story off")
	Settings.show_story = true
	Game.start_level(4)
	await _settle()
	check(_scene_is("res://scenes/level.tscn"), "Select Level goes straight to the level")
	check(not Progress.finished_game(), "the epilogue starts locked")
	Game.play_ending()
	await _settle()
	check(_scene_is("res://scenes/cutscene.tscn") and Game.story_chapter == StoryData.ENDING and Progress.finished_game(), "beating the game plays and unlocks the epilogue")
	(get_tree().current_scene as Cutscene).skip()
	for i in 80:
		await get_tree().process_frame
	(get_tree().current_scene as Cutscene).advance()
	await _settle()
	check(_scene_is("res://scenes/title.tscn"), "the epilogue returns to the title")
