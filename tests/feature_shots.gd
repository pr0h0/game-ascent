extends Node
## Screenshots of the title card, the automap and a difficulty-scaled HUD.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 res://tests/feature_shots.tscn -- <dir>


func _ready() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	Progress.path = "user://test_progress.cfg"
	Game.autopilot = true
	Game.reset_run()
	Game.level_index = 4
	Game.level_start = Game._make_snapshot()
	add_child(load("res://scenes/level.tscn").instantiate())
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/card.png")
	for i in 30:
		await get_tree().process_frame
	var level: Node3D = Game.level
	for id in level.astar.get_point_ids().slice(0, 5000):
		if id % 7 == 0:
			level.automap.reveal_around(level.astar.get_point_position(id))
	level.automap.open()
	await get_tree().create_timer(0.4).timeout
	level.automap._zoom = 620.0
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/map.png")
	level.automap.close()
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
