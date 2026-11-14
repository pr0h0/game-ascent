extends SceneTree
## Renders a model turntable to PNGs: godot --path . -s tests/shot_model.gd -- model.glb out.png [dist]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load("res://assets/models/" + args[0])
	var world := Node3D.new()
	root.add_child(world)
	var inst := scene.instantiate()
	world.add_child(inst)
	await process_frame
	var mats = root.get_node("Mats")
	mats.apply(inst)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 140, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.5, 0.65, 1.0)
	world.add_child(fill)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 40
	var dist := float(args[2]) if args.size() > 2 else 12.0
	var views := [Vector3(1, 0.55, -1), Vector3(-1, 0.4, 1), Vector3(0.2, 1.4, 0.1), Vector3(-0.8, -0.6, -0.8)]
	for i in views.size():
		cam.look_at_from_position(views[i].normalized() * dist, Vector3.ZERO, Vector3.UP if i != 2 else Vector3.FORWARD)
		for f in 6:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(args[1].replace(".png", "_%d.png" % i))
	quit()
