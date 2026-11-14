extends Node
## Saves one in-level picture of a level's rock theme (and lava, where it has any).
## xvfb-run -a godot --path . --resolution 1280x720 res://tests/theme_shots.tscn -- <out dir> <level number> [eye_x,eye_y,eye_z at_x,at_y,at_z]


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var index := int(args[1]) - 1
	Game.reset_run()
	Game.level_index = index
	add_child(load("res://scenes/level.tscn").instantiate())
	await _wait(20)
	var level = Game.level
	var p: Player = Game.player
	p._invuln = 1e9
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Robot:
			n.queue_free()
	var view = level.data.get("view")
	var eye: Vector3 = level.v3(level.data["start"])
	var at: Vector3 = eye + Vector3(0, 0, -30)
	if args.size() > 3:
		eye = _parse(args[2])
		at = _parse(args[3])
	elif view != null:
		eye = level.v3(view["eye"])
		at = level.v3(view["at"])
	p.view_mode = Player.View.CLEAN
	p._apply_view_mode()
	p.set_physics_process(false)
	p.global_position = eye
	var dir := (at - eye).normalized()
	p.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
	p._chase_pos = p.global_position
	p._chase_basis = p.global_basis
	await _wait(150)
	for c in level.get_children():
		if c is CanvasLayer:
			c.visible = false
	await _wait(4)
	var id: String = EscapeRun.level_id(index)
	var path := "%s/%02d_%s%s.png" % [out, index + 1, id, args[4] if args.size() > 4 else ""]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved %s fps=%d draw=%d" % [path, Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()


func _parse(text: String) -> Vector3:
	var v := text.split(",")
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
