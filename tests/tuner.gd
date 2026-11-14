extends Node
## The cockpit tuner has to drive the real cameras, and save without harming the game.
## godot --headless --path . res://tests/tuner.tscn [-- <dir for screenshots>]

const REAL_FILE := "res://assets/view_tuning.tres"
const TEST_FILE := "user://test_view_tuning.tres"

var failures := 0
var t: Node
var p: Player


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


## Sliders snap to steps, which can leave a last-digit difference once written to disk.
func same_values(a: Dictionary, b: Dictionary) -> bool:
	for key: String in a:
		var x: Variant = a[key]
		var y: Variant = b[key]
		var equal: bool = x.is_equal_approx(y) if x is Vector3 else (is_equal_approx(x, y) if x is float else x == y)
		if not equal:
			return false
	return a.size() == b.size()


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func slide(property: String, value: float) -> void:
	t._sliders[property].value = value
	await frames()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var real_before := FileAccess.get_file_as_string(REAL_FILE)
	_check_defaults()
	DirAccess.remove_absolute(TEST_FILE)
	ViewTuning.path = TEST_FILE
	ViewTuning._current = null
	t = load("res://tools/cockpit_tuner.tscn").instantiate()
	add_child(t)
	await t.tuner_ready
	p = Game.player
	await frames(3)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await _screens(args[0])
	await _check_cockpit()
	await _check_rear()
	await _check_screens()
	await _check_files()
	await _check_flying()
	check(FileAccess.get_file_as_string(REAL_FILE) == real_before, "the game's real tuning file was not touched")
	DirAccess.remove_absolute(TEST_FILE)
	print("RESULT failures=%d" % failures)
	get_tree().paused = false
	get_tree().quit(failures)


func _check_defaults() -> void:
	var v := ViewTuning.new()
	check(v.cockpit_eye == Vector3(0.0, 0.1, -0.3) and v.cabin_offset == v.cockpit_eye, "default cockpit eye matches the old fixed view")
	check(v.rear_eye == Vector3(0.0, 1.4, 0.1) and near(deg_to_rad(v.rear_pitch), -0.12), "default rear view matches the old fixed view")
	check(ViewTuning.current().values().keys() == v.values().keys(), "the shipped file loads every setting")


func _check_cockpit() -> void:
	check(get_tree().paused, "world is frozen while tuning")
	check(get_tree().get_nodes_in_group("enemy").all(func(e): return e is Reactor), "no enemies to interrupt tuning")
	check(p.cockpit.visible and not p.rear_view, "starts in the cockpit")
	await slide("cockpit_eye:z", -0.6)
	var want: Vector3 = p.global_position + p.global_basis * t.tuning.cockpit_eye
	check(p.cam.global_position.distance_to(want) < 0.001, "eye slider moves the real camera")
	await slide("cockpit_pitch", 10.0)
	var angle := (-p.global_basis.z).angle_to(-p.cam.global_basis.z)
	check(near(rad_to_deg(angle), 10.0), "pitch slider tilts the real camera (%.2f)" % rad_to_deg(angle))
	await slide("cockpit_fov_offset", 6.0)
	check(near(p.cam.fov, Settings.fov + 6.0), "field of view offset applies")
	await slide("cabin_offset:y", -0.4)
	check(near(p.cockpit.position.y, -0.4), "cabin slider moves the cabin")
	await slide("cabin_scale", 1.2)
	check(near(p.cockpit.scale.x, 1.2), "scale slider resizes the cabin")
	await slide("camera_near", 0.1)
	check(near(p.cam.near, 0.1), "near clip applies")
	check(t._status.text == "Unsaved changes", "panel reports unsaved changes")


func _check_rear() -> void:
	t._tabs.current_tab = 1
	await frames()
	check(p.rear_view and not p.cockpit.visible and p.ship.visible, "Rear tab switches the real view")
	await slide("rear_eye:y", 1.8)
	var want: Vector3 = p.global_position + p.global_basis * t.tuning.rear_eye
	check(p.cam.global_position.distance_to(want) < 0.001, "rear eye slider moves the real camera")
	var back := p.global_basis.z
	check((-p.cam.global_basis.z).dot(back) > 0.9, "rear camera looks backward")
	await slide("rear_fov_offset", -5.0)
	check(near(p.cam.fov, Settings.fov - 5.0), "rear field of view offset applies")
	t._checks["rear_show_ship"].button_pressed = false
	await frames()
	check(not p.ship.visible, "ship can be hidden in the rear view")
	t._tabs.current_tab = 0
	await frames()
	check(not p.rear_view and p.cockpit.visible, "Cockpit tab comes back")


func _check_screens() -> void:
	t._tabs.current_tab = 2
	await frames()
	check(not p.rear_view and p.cockpit.visible, "Screens tab shows the cockpit")
	var left: Node3D = p._screen_mounts[0]
	var right: Node3D = p._screen_mounts[1]
	check(left.transform.is_equal_approx(p._screen_rest[0]) and right.transform.is_equal_approx(p._screen_rest[1]), "untouched screens stay where the model puts them")
	check(left.find_child("Pod_L", true, false) != null and right.find_child("Pod_R", true, false) != null, "each screen's frame moves with it")
	await slide("screen_left_offset:x", 0.25)
	check(near(left.position.x, p._screen_rest[0].origin.x + 0.25), "left screen moves")
	check(right.transform.is_equal_approx(p._screen_rest[1]), "right screen stays put")
	await slide("screen_left_rotation:x", 20.0)
	var angle := p._screen_rest[0].basis.z.angle_to(left.basis.z)
	check(near(rad_to_deg(angle), 20.0), "left screen tilts (%.2f)" % rad_to_deg(angle))
	await slide("screen_right_scale", 1.4)
	check(near(right.basis.x.length(), 1.4), "right screen resizes")
	await slide("screen_right_brightness", 0.5)
	check(near(p._mfds[1]._material.albedo_color.r, 0.5), "right screen dims")
	check(near(p._mfds[0]._material.albedo_color.r, 1.0), "left screen keeps its brightness")
	t._tabs.current_tab = 0
	await frames()


func _check_files() -> void:
	t.save()
	check(FileAccess.file_exists(TEST_FILE) and t._status.text.begins_with("Saved"), "save writes the file")
	var disk := ResourceLoader.load(TEST_FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as ViewTuning
	check(disk != null and same_values(disk.values(), t.tuning.values()), "saved values read back the same")
	await slide("cockpit_eye:x", 0.7)
	t.revert()
	await frames()
	check(near(t.tuning.cockpit_eye.x, 0.0) and near(t._sliders["cockpit_eye:x"].value, 0.0), "revert restores saved values and sliders")
	check(near(t.tuning.cockpit_eye.z, -0.6), "revert keeps what was saved")
	t.defaults()
	await frames()
	check(t.tuning.values() == ViewTuning.new().values(), "defaults restores every value")
	check(p.cockpit.position.is_equal_approx(Vector3(0.0, 0.1, -0.3)), "defaults reaches the ship")
	check(t._status.text.begins_with("Defaults"), "panel says the defaults aren't saved")


func _check_flying() -> void:
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	t._input(f1)
	await frames()
	check(t.flying and not get_tree().paused and not t._panel.visible, "F1 starts flying")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	t._input(esc)
	await frames()
	check(not t.flying and get_tree().paused and t._panel.visible, "Esc returns to tuning")


func _screens(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await frames(6)
	get_viewport().get_texture().get_image().save_png(dir.path_join("tuner_cockpit.png"))
	t._tabs.current_tab = 1
	await frames(6)
	get_viewport().get_texture().get_image().save_png(dir.path_join("tuner_rear.png"))
	t._tabs.current_tab = 2
	await frames(2)
	await slide("screen_left_offset:x", 0.3)
	await slide("screen_left_rotation:y", 25.0)
	await slide("screen_right_scale", 1.35)
	await frames(6)
	get_viewport().get_texture().get_image().save_png(dir.path_join("tuner_screens.png"))
	t.defaults()
	t._tabs.current_tab = 0
	await frames(2)
