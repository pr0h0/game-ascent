class_name PauseMenu
extends Control
## In-flight pause: resume, restart the level, change settings or leave.

var buttons: Dictionary = {}
var _main: VBoxContainer
var _settings: SettingsPanel


func _ready() -> void:
	# Already in the tree here, so offsets must be reset too or the size stays zero.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuStyle.make_theme()
	visible = false
	MenuStyle.backdrop(self, Color(0.01, 0.02, 0.04, 0.72))
	_main = MenuStyle.column(self, 460.0)
	MenuStyle.heading(_main, "PAUSED", 52)
	buttons["resume"] = MenuStyle.button(_main, "Resume", close)
	buttons["restart"] = MenuStyle.button(_main, "Restart Level", Game.restart_level)
	buttons["settings"] = MenuStyle.button(_main, "Settings", _show_settings.bind(true))
	buttons["menu"] = MenuStyle.button(_main, "Main Menu", Game.to_title)
	# In a browser quitting only freezes the page, and fullscreen is one click away instead.
	if OS.has_feature("web"):
		buttons["fullscreen"] = MenuStyle.button(_main, "Toggle Fullscreen", toggle_fullscreen)
	else:
		buttons["quit"] = MenuStyle.button(_main, "Quit to Desktop", get_tree().quit)
	_settings = SettingsPanel.new()
	add_child(_settings)
	MenuStyle.place_left(_settings, 680.0)
	_settings.back_pressed.connect(_show_settings.bind(false))
	_settings.visible = false


## Reads the real window mode: the browser leaves fullscreen on its own when Esc is pressed.
func toggle_fullscreen() -> void:
	Settings.change("fullscreen", DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
	buttons["resume"].grab_focus.call_deferred()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_settings(false)


func close() -> void:
	visible = false
	get_tree().paused = false
	if not Game.autopilot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_settings(on: bool) -> void:
	_settings.visible = on
	_main.visible = not on
	if on:
		_settings.focus_back()
	else:
		buttons["resume"].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if Game.finished or Game.cinematic:
		return
	# The automap is open: it handles Start and Esc itself (by closing).
	if not visible and Game.level != null and Game.level.get("automap") != null and Game.level.automap.is_open:
		return
	# Esc is on both actions; Start is only on pause_game, so it can open and close.
	if not (event.is_action_pressed("pause_game") or (visible and event.is_action_pressed("ui_cancel"))):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		open()
	elif _settings.visible:
		_show_settings(false)
	else:
		close()
