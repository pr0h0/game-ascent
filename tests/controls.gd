extends Node
## Rebinding: defaults, swaps, saving, and the keyboard and gamepad pages.
## godot --headless --path . res://tests/controls.tscn [-- <dir for screenshots>]

const TEST_FILE := "user://test_controls.cfg"

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func key_event(key: int, pressed := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key as Key
	ev.pressed = pressed
	return ev


func pad_button(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button as JoyButton
	ev.pressed = true
	return ev


func pad_axis(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis as JoyAxis
	ev.axis_value = value
	return ev


func has_key(action: String, key: int) -> bool:
	return InputMap.action_has_event(action, key_event(key))


func _ready() -> void:
	DirAccess.remove_absolute(TEST_FILE)
	Controls.path = TEST_FILE
	Controls.load_file()
	Controls.apply()
	_check_defaults()
	_check_assign()
	_check_file()
	_check_pause()
	await _check_keyboard_rows()
	await _check_gamepad_page()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await _screens(args[0])
	DirAccess.remove_absolute(TEST_FILE)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _check_defaults() -> void:
	check(has_key("thrust_forward", KEY_W) and has_key("automap", KEY_TAB) and has_key("automap", KEY_M) and has_key("strafe_down", KEY_C), "default keys are installed")
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	check(InputMap.action_has_event("fire_primary", fire), "left mouse fires")
	check(InputMap.action_has_event("thrust_forward", pad_axis(JOY_AXIS_LEFT_Y, -1.0)), "left stick thrusts")
	check(InputMap.action_has_event("strafe_up", pad_button(JOY_BUTTON_A)), "pad button A strafes up")
	check(InputMap.action_has_event("weapon_1", pad_button(JOY_BUTTON_DPAD_UP)), "the d-pad picks weapons")
	var missing: Array = []
	for action: String in Controls.actions():
		if InputMap.action_get_events(action).is_empty():
			missing.append(action)
	check(missing.is_empty(), "every action has a default binding %s" % str(missing))
	check(Controls.describe(Controls.button_code(JOY_BUTTON_A), Controls.Layout.PLAYSTATION) == "Cross", "PlayStation names are used")
	check(Controls.describe(Controls.button_code(JOY_BUTTON_A), Controls.Layout.XBOX) == "A", "Xbox names are used")
	check(Controls.describe(Controls.axis_code(JOY_AXIS_TRIGGER_RIGHT, 1), Controls.Layout.PLAYSTATION) == "R2", "PlayStation trigger names are used")


func _check_assign() -> void:
	var other := Controls.assign(Controls.KEYBOARD, "thrust_forward", 0, Controls.key_code(KEY_S))
	check(other == "thrust_back", "taking a used key reports who had it")
	check(has_key("thrust_forward", KEY_S) and has_key("thrust_back", KEY_W), "the two actions trade keys")
	check(not has_key("thrust_forward", KEY_W), "the old key is gone")
	Controls.assign(Controls.KEYBOARD, "automap", 1, Controls.key_code(KEY_TAB))
	check(Controls.bindings[Controls.KEYBOARD]["automap"][0] != Controls.bindings[Controls.KEYBOARD]["automap"][1], "one action can't hold a key twice")
	Controls.reset(Controls.KEYBOARD)
	Controls.clear(Controls.KEYBOARD, "toggle_light", 0)
	check(not has_key("toggle_light", KEY_L), "a slot can be cleared")
	Controls.reset(Controls.KEYBOARD)
	check(has_key("toggle_light", KEY_L) and has_key("thrust_forward", KEY_W), "reset restores the keys")
	check(Controls.code_for(key_event(KEY_ESCAPE), Controls.KEYBOARD) == "", "Esc can't be bound")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	check(Controls.code_for(wheel, Controls.KEYBOARD) == "", "the wheel can't be bound")
	check(Controls.code_for(pad_button(JOY_BUTTON_START), Controls.GAMEPAD) == "", "Start stays as pause")
	check(Controls.code_for(pad_axis(JOY_AXIS_LEFT_X, 0.2), Controls.GAMEPAD) == "", "a slight stick drift isn't a press")
	check(Controls.code_for(pad_axis(JOY_AXIS_LEFT_X, -0.9), Controls.GAMEPAD) == Controls.axis_code(JOY_AXIS_LEFT_X, -1), "a stick push is a press")


func _check_file() -> void:
	Controls.assign(Controls.KEYBOARD, "fire_flare", 1, Controls.mouse_code(MOUSE_BUTTON_MIDDLE))
	Controls.assign(Controls.GAMEPAD, "rear_view", 0, Controls.button_code(JOY_BUTTON_TOUCHPAD))
	Controls.set_layout_choice(Controls.Layout.PLAYSTATION)
	var before: Dictionary = Controls.bindings.duplicate(true)
	Controls.bindings = {Controls.KEYBOARD: {}, Controls.GAMEPAD: {}}
	Controls.load_file()
	Controls.apply()
	check(Controls.bindings == before, "bindings survive a restart")
	check(Controls.layout_choice == Controls.Layout.PLAYSTATION, "controller picture choice survives a restart")
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	check(InputMap.action_has_event("fire_flare", middle), "a saved mouse binding is live")
	Controls.reset(Controls.KEYBOARD)
	Controls.reset(Controls.GAMEPAD)
	Controls.set_layout_choice(Controls.Layout.AUTO)


func _check_pause() -> void:
	check(InputMap.action_has_event("pause_game", key_event(KEY_ESCAPE)) and InputMap.action_has_event("pause_game", pad_button(JOY_BUTTON_START)), "Esc and Start pause")
	check(not InputMap.action_has_event("pause_game", pad_button(JOY_BUTTON_B)), "strafing down with B can't pause")
	print("INFO  ui_cancel has pad B: ", InputMap.action_has_event("ui_cancel", pad_button(JOY_BUTTON_B)))


func _check_keyboard_rows() -> void:
	var rows := BindRows.new()
	add_child(rows)
	await frames()
	check(rows._slots.size() == Controls.actions().size() * 2, "keyboard page has two slots per action")
	rows.listen("roll_left", 0)
	check(rows._slots["roll_left/0"].text == "Press a key...", "slot shows it is waiting")
	rows._input(key_event(KEY_ESCAPE))
	check(not rows.is_listening() and has_key("roll_left", KEY_Q), "Esc cancels and keeps the old key")
	rows.listen("roll_left", 0)
	rows._input(key_event(KEY_P, false))
	check(rows.is_listening(), "a key release doesn't bind")
	rows._input(key_event(KEY_P))
	check(not rows.is_listening() and has_key("roll_left", KEY_P) and not has_key("roll_left", KEY_Q), "pressing a key binds it")
	check(rows._slots["roll_left/0"].text == "P", "slot shows the new key")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	rows._slot_input(click, "roll_left", 0)
	check(not has_key("roll_left", KEY_P) and rows._slots["roll_left/0"].text == "Not set", "right-click clears")
	rows.queue_free()
	Controls.reset(Controls.KEYBOARD)
	await frames()


func _check_gamepad_page() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var page := GamepadPage.new()
	page.visible = false
	layer.add_child(page)
	await frames()
	page.open()
	await frames()
	check(page.visible and page.rows._slots.size() == Controls.actions().size(), "gamepad page opens with one slot per action")
	page.rows.listen("rear_view", 0)
	page.rows._input(pad_axis(JOY_AXIS_RIGHT_X, 0.1))
	check(page.rows.is_listening(), "stick drift doesn't bind")
	page.rows._input(pad_button(JOY_BUTTON_START))
	check(page.rows.is_listening(), "Start is refused")
	page.rows._input(pad_button(JOY_BUTTON_TOUCHPAD))
	check(InputMap.action_has_event("rear_view", pad_button(JOY_BUTTON_TOUCHPAD)), "a pad press binds on the gamepad page")
	page.rows.listen("rear_view", 0)
	page.rows._input(pad_button(JOY_BUTTON_A))
	check(InputMap.action_has_event("rear_view", pad_button(JOY_BUTTON_A)) and InputMap.action_has_event("strafe_up", pad_button(JOY_BUTTON_TOUCHPAD)), "pad bindings swap too")
	page._reset()
	check(InputMap.action_has_event("strafe_up", pad_button(JOY_BUTTON_A)), "gamepad reset works")
	for choice: int in [Controls.Layout.XBOX, Controls.Layout.PLAYSTATION]:
		page._layout_chosen(choice)
		await frames()
		check(page.diagram.layout == choice, "layout %d draws" % choice)
		check(page.diagram._callouts().size() >= 10, "layout %d labels its controls" % choice)
	page._layout_chosen(Controls.Layout.AUTO)
	page.rows.highlighted.emit(Controls.button_code(JOY_BUTTON_A))
	check(page.diagram._lit(Controls.button_code(JOY_BUTTON_A)), "picking a row lights the control")
	page.close()
	check(not page.visible, "Back closes the page")
	layer.queue_free()
	await frames()


func _screens(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var layer := CanvasLayer.new()
	add_child(layer)
	var page := GamepadPage.new()
	page.visible = false
	layer.add_child(page)
	await frames()
	page.open()
	for choice: int in [Controls.Layout.XBOX, Controls.Layout.PLAYSTATION]:
		page._layout_chosen(choice)
		await frames(6)
		get_viewport().get_texture().get_image().save_png(dir.path_join("gamepad_%d.png" % choice))
	page._layout_chosen(Controls.Layout.AUTO)
	layer.queue_free()
	await frames()
