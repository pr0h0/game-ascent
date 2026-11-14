extends Node
## Saves single frames of story shots at chosen moments, for checking staging quickly.
## godot --path . res://tests/stage_preview.tscn -- <dir> <chapter>:<shot>:<share> ...

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.quality = Settings.Quality.HIGH
	Settings.apply()
	for spec: String in args.slice(1):
		var parts := spec.split(":")
		Game.story_chapter = int(parts[0])
		Game.after_story = "stay"
		var cut: Cutscene = load("res://scenes/cutscene.tscn").instantiate()
		add_child(cut)
		cut._hint.visible = false
		cut.process_mode = Node.PROCESS_MODE_DISABLED
		cut._card.visible = false
		cut._fade.modulate.a = 0.0
		cut.shot_index = int(parts[1])
		cut.state = Cutscene.State.HOLD
		cut._build_shot()
		var target := float(parts[2]) * cut._shot_length
		while cut._shot_t < target:
			cut._animate(minf(0.1, target - cut._shot_t + 0.0001))
		for i in 8:
			await get_tree().process_frame
		if is_instance_valid(cut._look_node):
			print("%s look=%s cam=%s length=%.2f t=%.2f" % [spec, cut._look_node.global_position, cut._cam.global_position, cut._shot_length, cut._shot_t])
		get_viewport().get_texture().get_image().save_png(dir.path_join(spec.replace(":", "_") + ".png"))
		cut.queue_free()
		await get_tree().process_frame
	get_tree().quit()
