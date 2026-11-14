class_name GamepadPage
extends Control
## Full-screen gamepad bindings: a drawn controller beside the list of actions.

signal closed

var rows: BindRows
var diagram: GamepadDiagram
var _layout_pick: OptionButton
var _pad_label: Label
var _status: Label


func _ready() -> void:
	theme = MenuStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuStyle.backdrop(self, Color(0.01, 0.02, 0.04, 0.97))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	column.add_child(top)
	MenuStyle.heading(top, "Gamepad", 40)
	_layout_pick = OptionButton.new()
	for choice in ["Detect controller", "Xbox", "PlayStation 4 / 5"]:
		_layout_pick.add_item(choice)
	_layout_pick.selected = Controls.layout_choice
	_layout_pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_layout_pick.item_selected.connect(_layout_chosen)
	top.add_child(_layout_pick)
	_pad_label = Label.new()
	_pad_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pad_label.modulate = MenuStyle.DIM
	top.add_child(_pad_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)
	diagram = GamepadDiagram.new()
	body.add_child(diagram)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 440.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	rows = BindRows.new()
	rows.device = Controls.GAMEPAD
	rows.label_width = 190.0
	scroll.add_child(rows)
	rows.message.connect(_show_message)
	rows.changed.connect(_bindings_changed)
	rows.highlighted.connect(func(code: String): diagram.selected_code = code)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 24)
	column.add_child(bottom)
	_status = Label.new()
	_status.text = ""
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", MenuStyle.ACCENT)
	bottom.add_child(_status)
	MenuStyle.button(bottom, "Reset to defaults", _reset)
	MenuStyle.button(bottom, "Back", close)
	Input.joy_connection_changed.connect(_joy_changed)
	_refresh_layout()


func open() -> void:
	visible = true
	_status.text = ""
	_refresh_layout()
	rows.first_slot().grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not rows.is_listening():
		get_viewport().set_input_as_handled()
		close()


func _layout_chosen(index: int) -> void:
	Controls.set_layout_choice(index)
	_refresh_layout()


func _joy_changed(_device: int, _connected: bool) -> void:
	_refresh_layout()


func _refresh_layout() -> void:
	var active := Controls.active_layout()
	diagram.layout = active
	rows.layout = active
	rows.refresh()
	var pad := Controls.connected_pad()
	_pad_label.text = "No controller connected" if pad < 0 else Input.get_joy_name(pad)


func _bindings_changed() -> void:
	diagram.queue_redraw()


func _show_message(text: String) -> void:
	_status.text = text


func _reset() -> void:
	Controls.reset(Controls.GAMEPAD)
	rows.refresh()
	diagram.queue_redraw()
	_status.text = "Gamepad controls reset."
