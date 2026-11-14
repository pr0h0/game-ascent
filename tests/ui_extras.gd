extends Node
## Lives display, gallery inspect mode and spoken story lines.
## godot --headless --path . res://tests/ui_extras.tscn

const HUD := preload("res://scripts/hud.gd")

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_extras_saves"
	AudioServer.set_bus_mute(0, true)
	_check_lives()
	await _check_inspect()
	_check_voice_files()
	await _check_cutscene()
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _check_lives() -> void:
	for row: Array in [[0, 0, 0], [1, 1, 0], [3, 3, 0], [5, 5, 0], [6, 3, 3], [7, 3, 4], [99, 3, 96]]:
		var shown: Dictionary = HUD.lives_display(row[0])
		check(shown["marks"] == row[1] and shown["extra"] == row[2], "%d lives show %d marks and +%d" % row)


func _check_inspect() -> void:
	var title: Node = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await frames(5)
	var menu: MainMenu = title.get_children().filter(func(n): return n is MainMenu)[0]
	menu.show_panel("gallery")
	await frames(3)
	check(not is_zero_approx(title._cam.h_offset), "the gallery model starts off to the side")
	menu.gallery.inspect_button.pressed.emit()
	await frames(90)
	check(menu.inspecting and not menu._root.visible and menu._inspect_hint.visible, "Inspect hides the menu and shows the hint")
	check(absf(title._shown_offset) < 0.01, "Inspect centres the model (%.3f)" % title._shown_offset)
	var yaw0: float = title.yaw
	title.orbit(Vector2(50, 0))
	check(title.yaw != yaw0, "the model can still be rotated while inspecting")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	menu._unhandled_input(esc)
	await frames(90)
	check(not menu.inspecting and menu._root.visible and not menu._inspect_hint.visible and menu.current == "gallery", "Esc comes back to the gallery")
	check(title._shown_offset > 0.2, "the model moves back beside the panel")
	title.queue_free()
	await frames(3)


func _check_voice_files() -> void:
	var missing: Array = []
	var short: Array = []
	for c in StoryData.CHAPTERS.size():
		var shots: Array = StoryData.CHAPTERS[c]["shots"]
		for s in shots.size():
			for l in shots[s]["lines"].size():
				var stream := Cutscene.voice_stream(c, s, l)
				if stream == null:
					missing.append([c, s, l])
				elif stream.get_length() < 0.3:
					short.append([c, s, l])
	check(missing.is_empty(), "every story line has a recorded voice %s" % str(missing))
	check(short.is_empty(), "no voice clip is empty %s" % str(short))


func _check_cutscene() -> void:
	Game.story_chapter = 0
	Game.after_story = "stay"
	Settings.story_subtitles = false
	var cut: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(cut)
	await frames(3)
	check(AudioServer.get_bus_index("Voice") >= 0 and cut._voice.bus == &"Voice", "story voices use their own volume bus")
	cut.advance()
	for i in 240:
		await get_tree().process_frame
		if cut.state == Cutscene.State.TYPING:
			break
	check(cut.state == Cutscene.State.TYPING and cut._voice.playing and cut._voiced, "a line plays its voice")
	check(not cut._line.visible, "subtitles are off by default for spoken lines")
	check(cut._speaker.text != "", "the speaker's name is still shown")
	var first: int = cut.line_index
	cut.advance()
	await frames(3)
	check(cut.line_index == first + 1 and cut._voice.playing, "Space moves on to the next spoken line")
	Settings.story_subtitles = true
	cut._start_line(cut.line_index)
	check(cut._line.visible, "subtitles can be turned on")
	Settings.story_subtitles = false
	cut.skip()
	await frames(2)
	check(not cut._voice.playing, "skipping stops the voice")
	var length: float = Cutscene.voice_stream(0, 0, 0).get_length()
	check(cut._shot_duration(cut.chapter["shots"][0]) >= length, "shots last as long as their speech")
	check(cut._hint.visible, "the in-game hint is still shown")
	cut.queue_free()
	await frames(2)
	await _check_keys()


## Space and Esc, the way a player presses them, at each stage of a scene.
func _check_keys() -> void:
	Game.story_chapter = 0
	Game.after_story = "stay"
	var cut: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(cut)
	await frames(3)
	var space := InputEventAction.new()
	space.action = "ui_accept"
	space.pressed = true
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	cut._unhandled_input(space)
	for i in 240:
		await get_tree().process_frame
		if cut.state == Cutscene.State.TYPING:
			break
	check(cut.state == Cutscene.State.TYPING and cut._voice.playing, "Space leaves the title card and the narration starts")
	check(not cut._speaker.text.is_empty(), "the voice box shows while someone speaks")
	var before: int = cut.line_index
	cut._unhandled_input(space)
	await frames(2)
	check(cut.line_index == before + 1 and cut._voice.playing, "Space jumps to the next line of narration")
	cut._unhandled_input(space)
	for i in 240:
		await get_tree().process_frame
		if cut.state == Cutscene.State.TYPING:
			break
	check(cut.shot_index == 1, "Space on a shot's last line moves to the next shot")
	cut._unhandled_input(esc)
	await frames(2)
	check(cut.state == Cutscene.State.ENDING and not cut._voice.playing, "Esc silences the voice straight away")
	cut.queue_free()
	await frames(2)
	Game.story_chapter = StoryData.ENDING
	var last: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(last)
	await frames(3)
	last.state = Cutscene.State.CREDITS
	last._unhandled_input(esc)
	await frames(2)
	check(last.state == Cutscene.State.DONE, "Esc leaves the credits instead of restarting them")
	last.queue_free()
	await frames(2)
	var door := Door.new()
	door.lock = "entry"
	door._denied_cd = 0.0
	door._deny()
	check(door._denied_cd == 0.0, "the entry door never says it needs a key")
	door.free()
