extends Node
## Plays one story chapter and quits, for recording with Godot's Movie Maker:
## godot --path . --resolution 1920x1080 --write-movie out.avi --fixed-fps 30 res://tests/render_story.tscn -- <chapter index>

const TAIL_FRAMES := 45


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_render_saves"
	Settings.quality = Settings.Quality.HIGH
	Settings.render_scale = 1.0
	Settings.apply()
	Game.story_chapter = int(OS.get_cmdline_user_args()[0])
	# An unknown destination means the finished scene just stays put.
	Game.after_story = "stay"
	var cut: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
	add_child(cut)
	# The controls hint belongs in the game, not in a recording.
	cut._hint.visible = false
	while cut.state != Cutscene.State.DONE:
		await get_tree().process_frame
	for i in TAIL_FRAMES:
		await get_tree().process_frame
	get_tree().quit()
