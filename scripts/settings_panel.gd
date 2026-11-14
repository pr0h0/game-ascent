class_name SettingsPanel
extends VBoxContainer
## Video, audio and control options. Used on the home screen and in the pause menu.

signal back_pressed

var _back: Button
var _key_rows: BindRows
var _key_status: Label
var _gamepad_button: Button
var _gamepad_page: GamepadPage
## Slider keys previewed but not yet committed with Settings.change.
var _pending: Dictionary = {}


func _ready() -> void:
	MenuStyle.heading(self, "Settings", 40)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 430)
	tabs.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	add_child(tabs)

	var video := _tab(tabs, "Video")
	_check(video, "Fullscreen", "fullscreen")
	_check(video, "V-Sync", "vsync")
	_choice(video, "Graphics quality", "quality", ["Low", "Medium", "High"])
	_slider(video, "Field of view", "fov", 65.0, 100.0, 1.0, "%d°")
	_slider(video, "Render scale", "render_scale", 0.5, 1.0, 0.05, "", 100.0)
	_slider(video, "Screen shake", "screen_shake", 0.0, 1.0, 0.05, "", 100.0)
	_check(video, "Show frame rate", "show_fps")
	_check(video, "Play story scenes", "show_story")
	_check(video, "Unlock everything (testing)", "unlock_all")

	var audio := _tab(tabs, "Audio")
	_slider(audio, "Master volume", "master_volume", 0.0, 1.0, 0.05, "", 100.0)
	_slider(audio, "Effects", "effects_volume", 0.0, 1.0, 0.05, "", 100.0)
	_slider(audio, "Music", "music_volume", 0.0, 1.0, 0.05, "", 100.0)
	_slider(audio, "Ambience", "ambience_volume", 0.0, 1.0, 0.05, "", 100.0)
	_slider(audio, "Story voices", "voice_volume", 0.0, 1.0, 0.05, "", 100.0)
	_slider(audio, "Cave echo", "cave_reverb", 0.0, 1.0, 0.05, "", 100.0)
	_check(audio, "Story subtitles", "story_subtitles")

	var controls := _tab(tabs, "Controls")
	_slider(controls, "Mouse sensitivity", "mouse_sensitivity", 0.2, 3.0, 0.05, "%.2f")
	_check(controls, "Invert mouse Y", "invert_y")
	_add_key_bindings(controls)
	MenuStyle.spacer(self, 14.0)
	_back = MenuStyle.button(self, "Back", func(): back_pressed.emit())


func _add_key_bindings(page: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_key_rows = BindRows.new()
	_key_rows.label_width = 190.0
	scroll.add_child(_key_rows)
	_key_status = Label.new()
	_key_status.text = "Click a slot, then press a key. Right-click clears. Wheel also cycles missiles."
	_key_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_status.add_theme_color_override("font_color", MenuStyle.ACCENT)
	page.add_child(_key_status)
	_key_rows.message.connect(func(text: String): if text != "": _key_status.text = text)
	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	MenuStyle.button(buttons, "Reset keys", _reset_keys)
	_gamepad_button = MenuStyle.button(buttons, "Gamepad...", _open_gamepad)
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_gamepad_page = GamepadPage.new()
	_gamepad_page.visible = false
	layer.add_child(_gamepad_page)
	_gamepad_page.closed.connect(func(): _gamepad_button.grab_focus.call_deferred())
	# A CanvasLayer ignores its parent's visibility, so when the pause menu (or the
	# home screen) hides this panel the full-screen gamepad page must go too.
	visibility_changed.connect(func():
		if not is_visible_in_tree() and _gamepad_page.visible:
			_gamepad_page.visible = false)


func _reset_keys() -> void:
	Controls.reset(Controls.KEYBOARD)
	_key_rows.refresh()
	_key_status.text = "Keyboard and mouse controls reset."


func _open_gamepad() -> void:
	_gamepad_page.open()


func focus_back() -> void:
	_back.grab_focus.call_deferred()


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 10)
	tabs.add_child(page)
	return page


func _row_label(row: HBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(250, 0)
	row.add_child(label)


func _check(page: Control, text: String, key: String) -> void:
	var row := HBoxContainer.new()
	_row_label(row, text)
	var box := CheckButton.new()
	box.button_pressed = Settings.get(key)
	box.toggled.connect(func(on: bool): Settings.change(key, on))
	row.add_child(box)
	page.add_child(row)


func _choice(page: Control, text: String, key: String, options: Array) -> void:
	var row := HBoxContainer.new()
	_row_label(row, text)
	var pick := OptionButton.new()
	for o in options:
		pick.add_item(o)
	pick.selected = Settings.get(key)
	pick.item_selected.connect(func(index: int): Settings.change(key, index))
	row.add_child(pick)
	page.add_child(row)


## scale_factor turns a 0-1 value into a percentage for display.
func _slider(page: Control, text: String, key: String, low: float, high: float, step_size: float, fmt: String, scale_factor := 1.0) -> void:
	var row := HBoxContainer.new()
	_row_label(row, text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = Settings.get(key)
	slider.custom_minimum_size = Vector2(260, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var readout := Label.new()
	var show_value := func(v: float) -> void:
		readout.text = (fmt % v) if not fmt.is_empty() else "%d%%" % int(round(v * scale_factor))
	show_value.call(slider.value)
	# Dragging only previews the value; the full apply, the disk write and
	# settings_changed run once the drag ends or the value rests for a moment.
	var commit := Timer.new()
	commit.one_shot = true
	commit.wait_time = 0.3
	commit.process_mode = Node.PROCESS_MODE_ALWAYS
	row.add_child(commit)
	var flush := func() -> void:
		commit.stop()
		if _pending.has(key):
			_pending.erase(key)
			Settings.change(key, slider.value)
	commit.timeout.connect(flush)
	slider.drag_ended.connect(func(_changed: bool): flush.call())
	slider.tree_exiting.connect(flush)
	slider.value_changed.connect(func(v: float):
		show_value.call(v)
		Settings.preview(key, v)
		_pending[key] = true
		commit.start())
	row.add_child(readout)
	page.add_child(row)
