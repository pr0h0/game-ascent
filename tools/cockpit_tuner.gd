extends Node
## Dev tool: tune the cockpit and rear views over a real level, using the real ship.
## Run this scene from the editor (F6), or:
##   godot --path . res://tools/cockpit_tuner.tscn
## H hides the panel. F1 flies the ship to feel the motion; F1 or Esc comes back.

signal tuner_ready

const LEVEL_INDEX := 0
const PANEL_WIDTH := 400.0
const WARM_UP_LIMIT_MS := 8000
const HUD_SCRIPT := preload("res://scripts/hud.gd")

## A string starts a section. Otherwise: label, property, min, max, step.
const COCKPIT_FIELDS := [
	"Camera",
	["Eye left / right", "cockpit_eye:x", -2.0, 2.0, 0.01],
	["Eye down / up", "cockpit_eye:y", -2.0, 2.0, 0.01],
	["Eye forward / back", "cockpit_eye:z", -2.0, 2.0, 0.01],
	["Pitch", "cockpit_pitch", -30.0, 30.0, 0.1],
	["FOV offset", "cockpit_fov_offset", -30.0, 30.0, 0.5],
	["Near clip", "camera_near", 0.02, 0.5, 0.01],
	["Shake", "cockpit_shake", 0.0, 0.5, 0.01],
	"Cabin model",
	["Left / right", "cabin_offset:x", -2.0, 2.0, 0.01],
	["Down / up", "cabin_offset:y", -2.0, 2.0, 0.01],
	["Forward / back", "cabin_offset:z", -2.0, 2.0, 0.01],
	["Pitch", "cabin_rotation:x", -30.0, 30.0, 0.1],
	["Yaw", "cabin_rotation:y", -30.0, 30.0, 0.1],
	["Roll", "cabin_rotation:z", -30.0, 30.0, 0.1],
	["Scale", "cabin_scale", 0.5, 1.5, 0.01],
	"Cabin motion (F1 to feel it)",
	["From speed", "sway_velocity", 0.0, 0.01, 0.0001],
	["From turning", "sway_tilt", 0.0, 1.0, 0.01],
	["Response", "sway_response", 1.0, 30.0, 0.5],
]
const SCREEN_FIELDS := [
	"Left screen (stats)",
	["Left / right", "screen_left_offset:x", -2.0, 2.0, 0.01],
	["Down / up", "screen_left_offset:y", -2.0, 2.0, 0.01],
	["Forward / back", "screen_left_offset:z", -2.0, 2.0, 0.01],
	["Tilt", "screen_left_rotation:x", -60.0, 60.0, 0.5],
	["Turn", "screen_left_rotation:y", -60.0, 60.0, 0.5],
	["Roll", "screen_left_rotation:z", -60.0, 60.0, 0.5],
	["Size", "screen_left_scale", 0.3, 2.0, 0.01],
	["Brightness", "screen_left_brightness", 0.2, 2.0, 0.01],
	"Right screen (radar)",
	["Left / right", "screen_right_offset:x", -2.0, 2.0, 0.01],
	["Down / up", "screen_right_offset:y", -2.0, 2.0, 0.01],
	["Forward / back", "screen_right_offset:z", -2.0, 2.0, 0.01],
	["Tilt", "screen_right_rotation:x", -60.0, 60.0, 0.5],
	["Turn", "screen_right_rotation:y", -60.0, 60.0, 0.5],
	["Roll", "screen_right_rotation:z", -60.0, 60.0, 0.5],
	["Size", "screen_right_scale", 0.3, 2.0, 0.01],
	["Brightness", "screen_right_brightness", 0.2, 2.0, 0.01],
]
const REAR_FIELDS := [
	"Camera",
	["Eye left / right", "rear_eye:x", -6.0, 6.0, 0.01],
	["Eye down / up", "rear_eye:y", -6.0, 6.0, 0.01],
	["Eye forward / back", "rear_eye:z", -6.0, 6.0, 0.01],
	["Pitch", "rear_pitch", -45.0, 45.0, 0.1],
	["Yaw", "rear_yaw", -30.0, 30.0, 0.1],
	["FOV offset", "rear_fov_offset", -30.0, 30.0, 0.5],
	"Ship",
	["Show the ship", "rear_show_ship"],
]

var tuning: ViewTuning
var flying := false
var _player: Player
var _hud: CanvasLayer
var _layer: CanvasLayer
var _panel: PanelContainer
var _tabs: TabContainer
var _status: Label
var _sliders: Dictionary = {}
var _checks: Dictionary = {}
var _saved: Dictionary = {}
var _message := ""


func _ready() -> void:
	# A tool must never touch the player's real progress or saves.
	Progress.path = "user://test_progress.cfg"
	Saves.dir = "user://test_tuner_saves"
	AudioServer.set_bus_mute(0, true)
	tuning = ViewTuning.current()
	_saved = tuning.values()
	await _load_level()
	_build_ui()
	_set_flying(false)
	_refresh_rows()
	tuner_ready.emit()


func _load_level() -> void:
	Game.reset_run()
	Game.level_index = LEVEL_INDEX
	Game.start_missiles = Game.levels[LEVEL_INDEX]["base_missiles"]
	Game.start_ammo = Game.base_ammo(LEVEL_INDEX)
	Game.level_start = Game._make_snapshot()
	var level: Node = load("res://scenes/level.tscn").instantiate()
	# This node keeps running while paused; the level must not inherit that.
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = Game.player
	for child in level.get_children():
		if child.get_script() == HUD_SCRIPT:
			_hud = child
	# The start card fades away on its own, and the ship is alone for tuning.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WARM_UP_LIMIT_MS and level.get_children().any(func(c): return c is LevelCard):
		await get_tree().process_frame
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not enemy is Reactor:
			enemy.queue_free()
	await get_tree().process_frame


func _process(_delta: float) -> void:
	if _player != null and not flying:
		_player.refresh_view()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if event.keycode == KEY_F1:
		_set_flying(not flying)
	elif event.keycode == KEY_ESCAPE:
		if flying:
			_set_flying(false)
	elif event.keycode == KEY_H and not typing and not flying:
		_panel.visible = not _panel.visible
	else:
		return
	get_viewport().set_input_as_handled()


func _set_flying(on: bool) -> void:
	flying = on
	get_tree().paused = not on
	_panel.visible = not on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if not on:
		_player.velocity = Vector3.ZERO
		_apply_tab(_tabs.current_tab)


func _apply_tab(tab: int) -> void:
	_player.set_rear_view(tab == 1)


func _changed(property: String, value: Variant) -> void:
	tuning.set_indexed(NodePath(property), value)
	_player.apply_view_tuning()
	_message = ""
	_update_status()


func _is_dirty() -> bool:
	return tuning.values() != _saved


func save() -> void:
	var err := tuning.save_file()
	if err == OK:
		_saved = tuning.values()
		_message = "Saved to " + ViewTuning.path
	else:
		_message = "Save failed: " + error_string(err)
	_update_status()


func revert() -> void:
	tuning.reload_file()
	_saved = tuning.values()
	_after_bulk_change("Back to the saved values")


func defaults() -> void:
	tuning.reset_to_defaults()
	_after_bulk_change("Defaults loaded, not saved yet")


func _after_bulk_change(text: String) -> void:
	_player.apply_view_tuning()
	_refresh_rows()
	_message = text
	_update_status()


func _update_status() -> void:
	if _message != "":
		_status.text = _message
	else:
		_status.text = "Unsaved changes" if _is_dirty() else "Everything saved"
	_status.modulate = MenuStyle.ACCENT if _is_dirty() else MenuStyle.TEXT


func _refresh_rows() -> void:
	for property: String in _sliders:
		_sliders[property].set_value_no_signal(float(tuning.get_indexed(NodePath(property))))
	for property: String in _checks:
		_checks[property].set_pressed_no_signal(bool(tuning.get_indexed(NodePath(property))))
	_update_status()


# --- Panel ------------------------------------------------------------------------
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.theme = _make_theme()
	_panel.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH
	_layer.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var title := Label.new()
	title.text = "Cockpit tuner"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "H: hide panel    F1: fly and feel it"
	hint.modulate = MenuStyle.DIM
	column.add_child(hint)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_add_tab("Cockpit", COCKPIT_FIELDS)
	_add_tab("Rear", REAR_FIELDS)
	_add_tab("Screens", SCREEN_FIELDS)
	_tabs.tab_changed.connect(_apply_tab)

	var show_hud := CheckBox.new()
	show_hud.text = "Show HUD"
	show_hud.button_pressed = true
	show_hud.focus_mode = Control.FOCUS_NONE
	show_hud.toggled.connect(func(on: bool): if _hud != null: _hud.visible = on)
	column.add_child(show_hud)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_add_button(buttons, "Save", save)
	_add_button(buttons, "Revert", revert)
	_add_button(buttons, "Defaults", defaults)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", MenuStyle.TEXT)
	return t


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)


func _add_tab(tab_name: String, fields: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for field: Variant in fields:
		if field is String:
			_add_section(rows, field)
		elif field.size() == 2:
			_add_check(rows, field[0], field[1])
		else:
			_add_slider(rows, field[0], field[1], field[2], field[3], field[4])


func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MenuStyle.ACCENT)
	parent.add_child(label)


func _add_slider(parent: Control, text: String, property: String, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 132.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.allow_greater = true
	slider.allow_lesser = true
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.custom_minimum_size.x = 84.0
	spin.share(slider)
	row.add_child(spin)
	slider.value_changed.connect(func(v: float): _changed(property, v))
	_sliders[property] = slider


func _add_check(parent: Control, text: String, property: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool): _changed(property, on))
	parent.add_child(check)
	_checks[property] = check
