extends SceneTree
## Renders each boss at rest and mid-attack (vents open, petals bloomed) to PNGs.
## xvfb-run -a godot --path . -s tests/boss_shots.gd -- docs/bosses

const BOSSES := {
	"overseer": {"dist": 34.0, "yaw": 0.6},
	"crucible": {"dist": 44.0, "yaw": 2.2},
	"zero": {"dist": 52.0, "yaw": 0.5},
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "docs/bosses"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.5
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 150, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.5, 0.65, 1.0)
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 45
	world.add_child(cam)
	cam.current = true
	await process_frame
	var mats = root.get_node("Mats")
	for kind: String in BOSSES:
		var model: Node3D = load("res://assets/models/%s.glb" % kind).instantiate()
		mats.apply(model)
		world.add_child(model)
		var spec: Dictionary = BOSSES[kind]
		var yaw: float = spec["yaw"]
		var eye := Vector3(sin(yaw), 0.35, -cos(yaw)).normalized() * float(spec["dist"])
		cam.look_at_from_position(eye, Vector3.ZERO, Vector3.UP)
		for state in (["rest"] if kind == "overseer" else ["rest", "attack"]):
			_pose(model, kind, state == "attack")
			for f in 8:
				await process_frame
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, kind, state])
		model.queue_free()
		await process_frame
	quit()


## Puts the moving parts where they are mid-fight.
func _pose(model: Node3D, kind: String, attacking: bool) -> void:
	match kind:
		"crucible":
			for i in 3:
				var hatch: Node3D = model.find_child("Vent%d" % i, true, false)
				if not hatch.has_meta("rest"):
					hatch.set_meta("rest", hatch.basis)
				hatch.basis = hatch.get_meta("rest") * Basis(Vector3.RIGHT, 1.5 if attacking else 0.0)
			for n in ["Arm_L", "Arm_R"]:
				model.find_child(n, true, false).rotation.x = 0.9 if attacking else 0.0
		"zero":
			for i in 6:
				var petal: MeshInstance3D = model.find_child("Petal%d" % i, true, false)
				var dir := (petal.transform * petal.get_aabb().get_center()).normalized()
				if not petal.has_meta("rest"):
					petal.set_meta("rest", petal.position)
				petal.position = petal.get_meta("rest") + (dir * 6.5 if attacking else Vector3.ZERO)
