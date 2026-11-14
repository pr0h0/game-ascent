extends Node
## Renders every level's asteroid, shaft side towards the camera.
## xvfb-run -a godot --path . --resolution 960x720 res://tests/asteroid_shots.tscn -- <out dir>


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var world := Node3D.new()
	add_child(world)
	var mats = Mats
	var game = Game
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/space_sky.png")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24.0, 118.0, 0.0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.95, 0.86)
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.far = 5000.0
	cam.fov = 50.0
	world.add_child(cam)
	cam.current = true
	for i in game.levels.size():
		var id: String = EscapeRun.level_id(i)
		var rock: Node3D = load(EscapeRun.asteroid_model(id)).instantiate()
		mats.apply(rock)
		world.add_child(rock)
		# Seen as the escape sees it, from in front of the shaft, then from the side.
		for v in 2:
			var from := Vector3(170, 140, -560) if v == 0 else Vector3(600, 120, 60)
			cam.look_at_from_position(from, Vector3(0, 0, -20), Vector3.UP)
			for f in 8:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/asteroid_%02d_%s_%s.png" % [out, i + 1, id, "front" if v == 0 else "side"])
		rock.free()
	get_tree().quit()
