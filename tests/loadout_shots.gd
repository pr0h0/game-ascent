extends Node
## The ship wearing each loadout, from the chase angle and a front quarter, plus the
## real chase camera in a level and the home-screen turntable.
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 res://tests/loadout_shots.tscn -- <dir>

const LOADOUTS := [
	["laser", "homing"], ["cutter", "cluster"], ["arc", "swarm"],
	["rail", "bunker"], ["prism", "emp"], ["singularity", "mine"],
]
const CHASE_EYE := Vector3(3.6, 3.4, 9.5)
const FRONT_EYE := Vector3(-6.0, 1.4, -7.0)
const UNDER_EYE := Vector3(6.2, -3.6, 1.2)


func _ready() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(dir)
	await _studio(dir)
	await _in_game(dir)
	get_tree().quit()


func _studio(dir: String) -> void:
	var world := Node3D.new()
	add_child(world)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = e
	world.add_child(we)
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
	cam.fov = 45
	world.add_child(cam)
	cam.current = true
	var ship: Node3D = load("res://assets/models/wren9.glb").instantiate()
	Mats.apply(ship)
	world.add_child(ship)
	var loadout := ShipLoadout.attach(ship)
	for pair in LOADOUTS:
		loadout.show_loadout(pair[0], pair[1], 6, false)
		for view in [["chase", CHASE_EYE, Vector3(0, 0, -1.5)], ["front", FRONT_EYE, Vector3(0, -0.2, 0)], ["rack", UNDER_EYE, Vector3(1.6, -0.6, -0.6)]]:
			cam.look_at_from_position(view[1], view[2], Vector3.UP)
			await _shot("%s/%s_%s_%s.png" % [dir, view[0], pair[0], pair[1]])
	# Mid-deploy, to check the animation reads.
	loadout.show_loadout("rail", "homing", 3, true)
	await get_tree().create_timer(ShipLoadout.DEPLOY_TIME * 0.4).timeout
	cam.look_at_from_position(CHASE_EYE, Vector3(0, 0, -1.5), Vector3.UP)
	await _shot(dir + "/deploying.png")
	world.queue_free()
	await get_tree().process_frame


func _in_game(dir: String) -> void:
	Progress.path = "user://test_progress.cfg"
	Game.autopilot = true
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await get_tree().create_timer(0.5).timeout
	var p: Player = Game.player
	p.view_mode = Player.View.CHASE
	p._apply_view_mode()
	p.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	Game.upgrades.append("weapon_arc")
	p.ammo["cluster"] = 5
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/game_chase_laser.png")
	p.select_primary("arc")
	p.select_secondary("cluster")
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/game_chase_arc.png")
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/game_cockpit.png")
	Game.level.queue_free()
	await get_tree().process_frame
	var title: Node = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/home_screen.png")
	DirAccess.remove_absolute(Progress.path)


func _shot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
