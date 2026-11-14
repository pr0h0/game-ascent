class_name BindRows
extends VBoxContainer
## A list of actions with clickable binding slots, for the keyboard or a gamepad.
## Click a slot and press something to bind it. Esc cancels; right-click clears.

signal message(text: String)
signal changed
signal highlighted(code: String)

const SLOT_WIDTH := 190.0

var device := Controls.KEYBOARD
var label_width := 200.0
var layout: int = Controls.Layout.XBOX
var _slots: Dictionary = {}
var _listening: Button
var _listening_action := ""
var _listening_slot := 0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	for group: Array in Controls.GROUPS:
		var header := Label.new()
		header.text = group[0]
		header.add_theme_color_override("font_color", MenuStyle.ACCENT)
		add_child(header)
		for entry: Array in group[1]:
			_add_row(entry[0], entry[1])
	visibility_changed.connect(_cancel_if_hidden)
	refresh()


func _add_row(action: String, text: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = label_width
	row.add_child(label)
	for slot in int(Controls.SLOTS[device]):
		var button := Button.new()
		button.custom_minimum_size.x = SLOT_WIDTH
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.pressed.connect(listen.bind(action, slot))
		button.gui_input.connect(_slot_input.bind(action, slot))
		button.mouse_entered.connect(_hover.bind(action, slot))
		button.focus_entered.connect(_hover.bind(action, slot))
		MenuStyle.add_sounds(button)
		row.add_child(button)
		_slots[_slot_id(action, slot)] = button
	add_child(row)


func _slot_id(action: String, slot: int) -> String:
	return "%s/%d" % [action, slot]


func first_slot() -> Button:
	return _slots[_slot_id(Controls.actions()[0], 0)]


func is_listening() -> bool:
	return _listening != null


func listen(action: String, slot: int) -> void:
	_stop()
	_listening = _slots[_slot_id(action, slot)]
	_listening_action = action
	_listening_slot = slot
	_listening.text = "Press a key..." if device == Controls.KEYBOARD else "Press a control..."
	message.emit("Binding %s. Esc cancels." % Controls.action_label(action))


func _input(event: InputEvent) -> void:
	if _listening == null or not is_visible_in_tree():
		return
	if not (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	# A left click on a different slot moves the listening there; it isn't a binding.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _slot_under(event.position) not in [null, _listening]:
		return
	var cancels: bool = event is InputEventKey and event.pressed and (event.physical_keycode == KEY_ESCAPE or (event.physical_keycode == KEY_NONE and event.keycode == KEY_ESCAPE))
	var code := Controls.code_for(event, device)
	if device == Controls.GAMEPAD and event is InputEventMouseButton and event.pressed:
		cancels = true
	if cancels:
		_stop()
		message.emit("")
	elif code != "":
		var action := _listening_action
		var slot := _listening_slot
		var displaced := Controls.assign(device, action, slot, code)
		_stop()
		refresh()
		changed.emit()
		var bound := "%s is now %s." % [Controls.action_label(action), Controls.describe(code, layout)]
		message.emit(bound + (" Swapped with %s." % Controls.action_label(displaced) if displaced != "" else ""))
	# A motion below the threshold shouldn't be eaten, or the sticks would feel dead.
	if not event is InputEventJoypadMotion or code != "":
		get_viewport().set_input_as_handled()


func _slot_under(at: Vector2) -> Button:
	for button: Button in _slots.values():
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return button
	return null


func _slot_input(event: InputEvent, action: String, slot: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _listening == null:
		Controls.clear(device, action, slot)
		refresh()
		changed.emit()
		message.emit("%s cleared." % Controls.action_label(action))
		accept_event()


func _hover(action: String, slot: int) -> void:
	highlighted.emit(Controls.bindings[device][action][slot])


func _stop() -> void:
	_listening = null
	refresh()


func _cancel_if_hidden() -> void:
	if not is_visible_in_tree() and _listening != null:
		_stop()


func refresh() -> void:
	for action: String in Controls.actions():
		for slot in int(Controls.SLOTS[device]):
			var button: Button = _slots[_slot_id(action, slot)]
			if button == _listening:
				continue
			var code: String = Controls.bindings[device][action][slot]
			button.text = Controls.describe(code, layout)
			button.modulate = MenuStyle.DIM if code == "" else Color.WHITE
