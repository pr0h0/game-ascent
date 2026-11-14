class_name Controls
extends RefCounted
## Every rebindable action, its defaults, and the player's own bindings.
## A binding is a short code: k87 key, m1 mouse button, b0 pad button, a1- pad axis.

const KEYBOARD := "keyboard"
const GAMEPAD := "gamepad"
const SLOTS := {KEYBOARD: 2, GAMEPAD: 1}
const VIEW_SECTION := "gamepad_view"
const AXIS_PRESS := 0.6

enum Layout { AUTO, XBOX, PLAYSTATION }

const GROUPS := [
	["Flight", [
		["thrust_forward", "Thrust"], ["thrust_back", "Reverse"],
		["strafe_left", "Strafe left"], ["strafe_right", "Strafe right"],
		["strafe_up", "Strafe up"], ["strafe_down", "Strafe down"],
		["roll_left", "Roll left"], ["roll_right", "Roll right"],
		["afterburner", "Afterburner"],
	]],
	["Aim", [
		["look_up", "Aim up"], ["look_down", "Aim down"],
		["look_left", "Aim left"], ["look_right", "Aim right"],
	]],
	["Weapons", [
		["fire_primary", "Fire cannons"], ["fire_secondary", "Fire missile"],
		["next_missile", "Next missile"], ["fire_flare", "Flare"],
		["weapon_1", "Laser"], ["weapon_2", "Plasma Cutter"], ["weapon_3", "Arc"],
		["weapon_4", "Rail"], ["weapon_5", "Prism"], ["weapon_6", "Singularity"],
	]],
	["Systems", [
		["automap", "Map"], ["toggle_view", "Cycle view"],
		["rear_view", "Rear view"], ["toggle_light", "Headlight"],
	]],
]

const DEFAULT_KEYS := {
	"thrust_forward": [KEY_W], "thrust_back": [KEY_S], "strafe_left": [KEY_A], "strafe_right": [KEY_D],
	"strafe_up": [KEY_SPACE], "strafe_down": [KEY_CTRL, KEY_C], "roll_left": [KEY_Q], "roll_right": [KEY_E],
	"look_up": [KEY_UP], "look_down": [KEY_DOWN], "look_left": [KEY_LEFT], "look_right": [KEY_RIGHT],
	"toggle_view": [KEY_V], "toggle_light": [KEY_L], "fire_flare": [KEY_F], "next_missile": [KEY_G],
	"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4], "weapon_5": [KEY_5], "weapon_6": [KEY_6],
	"rear_view": [KEY_R], "afterburner": [KEY_SHIFT], "automap": [KEY_TAB, KEY_M],
}
const DEFAULT_MOUSE := {"fire_primary": MOUSE_BUTTON_LEFT, "fire_secondary": MOUSE_BUTTON_RIGHT}
const DEFAULT_PAD_AXES := {
	"thrust_forward": [JOY_AXIS_LEFT_Y, -1], "thrust_back": [JOY_AXIS_LEFT_Y, 1],
	"strafe_left": [JOY_AXIS_LEFT_X, -1], "strafe_right": [JOY_AXIS_LEFT_X, 1],
	"look_left": [JOY_AXIS_RIGHT_X, -1], "look_right": [JOY_AXIS_RIGHT_X, 1],
	"look_up": [JOY_AXIS_RIGHT_Y, -1], "look_down": [JOY_AXIS_RIGHT_Y, 1],
	"fire_primary": [JOY_AXIS_TRIGGER_RIGHT, 1], "fire_secondary": [JOY_AXIS_TRIGGER_LEFT, 1],
}
const DEFAULT_PAD_BUTTONS := {
	"strafe_up": JOY_BUTTON_A, "strafe_down": JOY_BUTTON_B, "fire_flare": JOY_BUTTON_X, "next_missile": JOY_BUTTON_Y,
	"roll_left": JOY_BUTTON_LEFT_SHOULDER, "roll_right": JOY_BUTTON_RIGHT_SHOULDER, "toggle_view": JOY_BUTTON_BACK,
	"afterburner": JOY_BUTTON_LEFT_STICK, "automap": JOY_BUTTON_RIGHT_STICK,
	"weapon_1": JOY_BUTTON_DPAD_UP, "weapon_2": JOY_BUTTON_DPAD_RIGHT, "weapon_3": JOY_BUTTON_DPAD_DOWN, "weapon_4": JOY_BUTTON_DPAD_LEFT,
}

const XBOX_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Xbox", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "LS click", JOY_BUTTON_RIGHT_STICK: "RS click",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
}
const PS_BUTTONS := {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Share", JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const DPAD_NAMES := {JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"}
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5"}
const WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

static var path := "user://controls.cfg"
static var layout_choice: int = Layout.AUTO
static var bindings := {KEYBOARD: {}, GAMEPAD: {}}


static func key_code(key: int) -> String:
	return "k%d" % key


## A key event that carries no physical keycode (some synthetic or virtual keyboard
## events) is bound by its logical keycode instead, and matched the same way.
static func logical_key_code(key: int) -> String:
	return "l%d" % key


static func mouse_code(button: int) -> String:
	return "m%d" % button


static func button_code(button: int) -> String:
	return "b%d" % button


static func axis_code(axis: int, direction: int) -> String:
	return "a%d%s" % [axis, "+" if direction > 0 else "-"]


static func actions() -> Array:
	var out: Array = []
	for group: Array in GROUPS:
		for entry: Array in group[1]:
			out.append(entry[0])
	return out


static func action_label(action: String) -> String:
	for group: Array in GROUPS:
		for entry: Array in group[1]:
			if entry[0] == action:
				return entry[1]
	return action


static func setup() -> void:
	for action: String in actions():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	# Pausing stays fixed, so nobody can lock themselves out of the menu.
	if not InputMap.has_action("pause_game"):
		InputMap.add_action("pause_game")
		InputMap.action_add_event("pause_game", event_for(key_code(KEY_ESCAPE)))
		InputMap.action_add_event("pause_game", event_for(button_code(JOY_BUTTON_START)))
	load_file()
	apply()


static func defaults(device: String) -> Dictionary:
	var table := {}
	for action: String in actions():
		var codes: Array = []
		if device == KEYBOARD:
			for key: int in DEFAULT_KEYS.get(action, []):
				codes.append(key_code(key))
			if DEFAULT_MOUSE.has(action):
				codes.append(mouse_code(DEFAULT_MOUSE[action]))
		elif DEFAULT_PAD_AXES.has(action):
			codes.append(axis_code(DEFAULT_PAD_AXES[action][0], DEFAULT_PAD_AXES[action][1]))
		elif DEFAULT_PAD_BUTTONS.has(action):
			codes.append(button_code(DEFAULT_PAD_BUTTONS[action]))
		while codes.size() < int(SLOTS[device]):
			codes.append("")
		table[action] = codes
	return table


static func apply() -> void:
	for action: String in actions():
		InputMap.action_erase_events(action)
		for device: String in [KEYBOARD, GAMEPAD]:
			for code: String in bindings[device][action]:
				if code != "":
					InputMap.action_add_event(action, event_for(code))


static func event_for(code: String) -> InputEvent:
	var number := code.substr(1).to_int()
	match code[0]:
		"k":
			var key := InputEventKey.new()
			key.physical_keycode = number as Key
			return key
		"l":
			var logical := InputEventKey.new()
			logical.keycode = number as Key
			return logical
		"m":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = number as MouseButton
			return mouse
		"b":
			var button := InputEventJoypadButton.new()
			button.button_index = number as JoyButton
			return button
	var axis := InputEventJoypadMotion.new()
	axis.axis = number as JoyAxis
	axis.axis_value = 1.0 if code.ends_with("+") else -1.0
	return axis


## The code for what was just pressed, or "" if it can't be bound here.
static func code_for(event: InputEvent, device: String) -> String:
	if device == KEYBOARD:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode != KEY_NONE:
				return "" if event.physical_keycode == KEY_ESCAPE else key_code(event.physical_keycode)
			return "" if event.keycode == KEY_ESCAPE or event.keycode == KEY_NONE else logical_key_code(event.keycode)
		if event is InputEventMouseButton and event.pressed and not event.button_index in WHEEL_BUTTONS:
			return mouse_code(event.button_index)
		return ""
	if event is InputEventJoypadButton and event.pressed:
		return "" if event.button_index == JOY_BUTTON_START else button_code(event.button_index)
	if event is InputEventJoypadMotion and absf(event.axis_value) > AXIS_PRESS:
		return axis_code(event.axis, 1 if event.axis_value > 0.0 else -1)
	return ""


## Binds a control. If another action already uses it, the two trade places,
## so nothing goes silently unbound. Returns the other action, or "".
static func assign(device: String, action: String, slot: int, code: String) -> String:
	var table: Dictionary = bindings[device]
	var previous: String = table[action][slot]
	var displaced := ""
	for other: String in table:
		for i in table[other].size():
			if table[other][i] == code and not (other == action and i == slot):
				table[other][i] = previous
				if other != action:
					displaced = other
	table[action][slot] = code
	apply()
	save()
	return displaced


static func clear(device: String, action: String, slot: int) -> void:
	bindings[device][action][slot] = ""
	apply()
	save()


static func reset(device: String) -> void:
	bindings[device] = defaults(device)
	apply()
	save()


static func set_layout_choice(choice: int) -> void:
	layout_choice = choice
	save()


static func save() -> void:
	var cfg := ConfigFile.new()
	for device: String in bindings:
		for action: String in bindings[device]:
			cfg.set_value(device, action, bindings[device][action])
	cfg.set_value(VIEW_SECTION, "layout", layout_choice)
	cfg.save(path)


## Anything missing from the file, like an action added later, keeps its default.
static func load_file() -> void:
	bindings = {KEYBOARD: defaults(KEYBOARD), GAMEPAD: defaults(GAMEPAD)}
	layout_choice = Layout.AUTO
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var layout: Variant = cfg.get_value(VIEW_SECTION, "layout", Layout.AUTO)
	layout_choice = clampi(int(layout), 0, Layout.size() - 1) if (layout is int or layout is float) else Layout.AUTO
	for device: String in bindings:
		for action: String in bindings[device]:
			if not cfg.has_section_key(device, action):
				continue
			var saved: Variant = cfg.get_value(device, action)
			if saved is Array and saved.size() == int(SLOTS[device]) and saved.all(_is_code):
				bindings[device][action] = saved


## "" (unbound) or one of the codes made by key_code, mouse_code and the rest.
static func _is_code(code: Variant) -> bool:
	if not code is String:
		return false
	if code == "":
		return true
	if code.length() < 2 or not code[0] in ["k", "l", "m", "b", "a"]:
		return false
	var number: String = code.substr(1)
	if code[0] == "a":
		if not (number.ends_with("+") or number.ends_with("-")):
			return false
		number = number.left(-1)
	return number.is_valid_int()


static func connected_pad() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


## Which drawing and button names to use: the player's choice, or a guess from the pad.
static func active_layout() -> int:
	if layout_choice != Layout.AUTO:
		return layout_choice
	var pad := connected_pad()
	if pad < 0:
		return Layout.XBOX
	var pad_name := Input.get_joy_name(pad).to_lower()
	for hint: String in ["ps3", "ps4", "ps5", "dualshock", "dualsense", "playstation", "sony", "wireless controller"]:
		if pad_name.contains(hint):
			return Layout.PLAYSTATION
	return Layout.XBOX


static func button_name(button: int, layout: int) -> String:
	if DPAD_NAMES.has(button):
		return DPAD_NAMES[button]
	var names: Dictionary = PS_BUTTONS if layout == Layout.PLAYSTATION else XBOX_BUTTONS
	return names.get(button, "Button %d" % button)


static func describe(code: String, layout: int = Layout.XBOX) -> String:
	if code == "":
		return "Not set"
	var number := code.substr(1).to_int()
	match code[0]:
		"k":
			return _key_name(number)
		"l":
			return OS.get_keycode_string(number as Key)
		"m":
			return MOUSE_NAMES.get(number, "Mouse %d" % number)
		"b":
			return button_name(number, layout)
	var positive := code.ends_with("+")
	match number:
		JOY_AXIS_LEFT_X:
			return "Left stick right" if positive else "Left stick left"
		JOY_AXIS_LEFT_Y:
			return "Left stick down" if positive else "Left stick up"
		JOY_AXIS_RIGHT_X:
			return "Right stick right" if positive else "Right stick left"
		JOY_AXIS_RIGHT_Y:
			return "Right stick down" if positive else "Right stick up"
		JOY_AXIS_TRIGGER_LEFT:
			return "L2" if layout == Layout.PLAYSTATION else "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2" if layout == Layout.PLAYSTATION else "RT"
	return "Axis %d%s" % [number, "+" if positive else "-"]


static func _key_name(physical: int) -> String:
	# The browser can't map physical keys to the local layout (it logs an error per call).
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var local := DisplayServer.keyboard_get_keycode_from_physical(physical as Key)
		if local != KEY_NONE:
			return OS.get_keycode_string(local)
	return OS.get_keycode_string(physical as Key)


## The binding names for one action, e.g. "Tab or M", for on-screen hints.
static func hint(action: String) -> String:
	var names: Array = []
	for code: String in bindings[KEYBOARD].get(action, []):
		if code != "":
			names.append(describe(code))
	return " or ".join(names) if not names.is_empty() else "Not set"
