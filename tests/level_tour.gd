extends Node
## Photographs a generated level from the viewpoints its generator suggests (data "tour").
## godot --path . res://tests/level_tour.tscn -- <output dir> <level index> [max shots]

func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	Game.reset_run()
	Game.level_index = int(args[1])
	var limit := int(args[2]) if args.size() > 2 else 99
	add_child(load("res://scenes/level.tscn").instantiate())
	await _wait(30)
	var p: Player = Game.player
	p._invuln = 1e9
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	p.view_mode = 2
	p._apply_view_mode()
	_experiment(OS.get_environment("ASCENT_FX").split(",", false))
	await _wait(30)
	var n := 0
	for v: Array in Game.level.data.get("tour", []):
		if n >= limit:
			break
		n += 1
		var eye: Vector3 = Game.level.v3(v[1])
		var at: Vector3 = Game.level.v3(v[2])
		p.global_position = eye
		var dir: Vector3 = (at - eye).normalized()
		p.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
		p.velocity = Vector3.ZERO
		await _wait(45)
		get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, v[0]])
		# Steady frame rate here, once shaders for this view have compiled.
		await _wait(30)
		var t0 := Time.get_ticks_usec()
		await _wait(60)
		var fps := 60.0 / ((Time.get_ticks_usec() - t0) / 1e6)
		print("shot %s fps=%.0f draws=%d prims=%dk" % [v[0], fps, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	get_tree().quit()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		if is_instance_valid(Game.player):
			Game.player.velocity = Vector3.ZERO


## Experimental renderer features, comma-separated in ASCENT_FX: sdfgi, ssil, ssr, noocc (turns occlusion culling off).
func _experiment(fx: PackedStringArray) -> void:
	var e: Environment = Game.level._env
	if "sdfgi" in fx:
		e.sdfgi_enabled = true
		e.sdfgi_use_occlusion = true
		e.sdfgi_cascades = 4
		e.sdfgi_min_cell_size = 0.4
		e.sdfgi_energy = 1.0
		for l: OmniLight3D in Game.level.lights:
			l.light_bake_mode = Light3D.BAKE_DYNAMIC
	if "ssil" in fx:
		e.ssil_enabled = true
		e.ssil_radius = 6.0
		e.ssil_intensity = 1.2
	if "ssr" in fx:
		e.ssr_enabled = true
		e.ssr_max_steps = 48
	if "noocc" in fx:
		get_viewport().use_occlusion_culling = false
