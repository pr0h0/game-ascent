extends Node
## Flies the camera through the level and saves screenshots plus frame timings.
## godot --path . res://tests/shots.tscn -- <output dir>

const LEVEL_ONE_VIEWS := [
	["l1_spine", 1, Vector3(0, 10, -30), Vector3(0, 10, -100)],
	["l1_door", 0, Vector3(0, 10, -72), Vector3(0, 10, -110)],
	["l1_key", 1, Vector3(18, -32, -125), Vector3(-5, -32, -145)],
	["l1_reactor", 1, Vector3(50, 12, -222), Vector3(50, 10, -255)],
]
const LEVEL_THREE_VIEWS := [
	["l3_entry", 1, Vector3(0, 12, -78), Vector3(0, -40, -115)],
	["l3_down", 0, Vector3(-20, 30, -115), Vector3(20, -120, -115)],
	["l3_hall", 1, Vector3(120, -115, -90), Vector3(170, -125, -145)],
	["l3_overhang", 0, Vector3(-35, 10, -120), Vector3(40, 30, -120)],
	["l3_bridge", 0, Vector3(-36, -102, -115), Vector3(18, -82, -120)],
	["l3_reactor", 1, Vector3(60, -28, -255), Vector3(60, -30, -295)],
]
const LATE_VIEWS := [
	["l4_start", 1, Vector3(0, 10, -60), Vector3(0, 10, -120)],
]
const BOSS_VIEWS := [
	["l7_boss", 0, Vector3(0, 10, -95), Vector3(0, 10, -130)],
]
const PRESETS := {"level1": [0, LEVEL_ONE_VIEWS], "level3": [2, LEVEL_THREE_VIEWS], "level4": [3, LATE_VIEWS], "level7": [6, BOSS_VIEWS]}
const VIEWS := [
	["bay_cockpit", 1, Vector3(0, 10, 25), Vector3(0, 10, -30)],
	["bay_chase", 0, Vector3(0, 12, 20), Vector3(0, 8, -30)],
	["spine", 1, Vector3(0, 10, -15), Vector3(0, 10, -90)],
]


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	var args := OS.get_cmdline_user_args()
	var level_one: bool = args.size() > 1 and PRESETS.has(args[1])
	Game.reset_run()
	Game.level_index = PRESETS[args[1]][0] if level_one else 1
	add_child(load("res://scenes/level.tscn").instantiate())
	var out: String = OS.get_cmdline_user_args()[0]
	await _wait(30)
	var p: Player = Game.player
	p._invuln = 1e9  # no fake shield number on the HUD
	p._invuln = 1e9
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var only: Array = Array(args[1].split(",")) if args.size() > 1 and not level_one else []
	if level_one:
		only = ["level1"]
	for v in (PRESETS[args[1]][1] if level_one else VIEWS):
		if not level_one and not only.is_empty() and not only.has(v[0]):
			continue
		p.view_mode = v[1]
		p._apply_view_mode()
		p.global_position = v[2]
		var dir: Vector3 = (v[3] - v[2]).normalized()
		p.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)
		p._chase_pos = p.global_position + p.global_basis * p.CHASE_OFFSET
		p._chase_basis = p.global_basis
		p._thrust_level = 0.8
		await _wait(120)
		print("%s fps=%d draw=%d prims=%d" % [v[0], Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, v[0]])
	if not only.is_empty():
		get_tree().quit()
		return

	# Flares in a dim tunnel, then the rear view in both camera styles.
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()
	# Down the spine: every generated level starts with the same straight tunnel.
	p.global_position = Vector3(0, 10, -15)
	p.global_basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	await _wait(10)
	Flare.launch(p.global_position + Vector3(0, 0, -4), Vector3(0.03, -0.03, -1))
	await _wait(90)
	_save(out, "flare")
	p.global_position = Vector3(0, 10, -60)
	p.global_basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	p.set_rear_view(true)
	await _wait(30)
	_save(out, "rear_cockpit")
	p.view_mode = Player.View.CHASE
	p._apply_view_mode()
	p.set_rear_view(true)
	await _wait(30)
	_save(out, "rear_chase")
	p.set_rear_view(false)

	# Trigger the finale and sample it across its length.
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Reactor:
			n.take_damage(1e6, n.global_position, null)
	await _wait(20)
	p.global_position = Game.level.v3(Game.level.data["escape_trigger"])
	await _wait(10)
	for i in 10:
		await get_tree().create_timer(0.62).timeout
		print("escape_%d fps=%d" % [i, Engine.get_frames_per_second()])
		get_viewport().get_texture().get_image().save_png("%s/escape_%d.png" % [out, i])
	get_tree().quit()



func _save(out: String, shot_name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shot_name])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame
