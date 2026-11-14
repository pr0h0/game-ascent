class_name ResultsScreen
extends Control
## End of a run: the outcome, how it went, and where to go next.

const WIN := Color(0.45, 1.0, 0.6)
const LOSE := Color(1.0, 0.3, 0.22)
const FADE_TIME := 0.9

var stats: Dictionary = {}
var primary: Button
var _backdrop: ColorRect
var _column: VBoxContainer


func _ready() -> void:
	# Already in the tree here, so offsets must be reset too or the size stays zero.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuStyle.make_theme()
	visible = false
	_backdrop = MenuStyle.backdrop(self, Color(0.02, 0.04, 0.07, 0.95))
	_column = MenuStyle.column(self, 560.0)


func show_results(won: bool, detail: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	var title := MenuStyle.heading(_column, "MINE CLEARED" if won else "RUN FAILED", 56)
	title.add_theme_color_override("font_color", WIN if won else LOSE)
	var subtitle := Label.new()
	subtitle.text = "%s\n%s" % [Game.level_title(Game.level_index), detail]
	subtitle.add_theme_color_override("font_color", MenuStyle.TEXT)
	_column.add_child(subtitle)
	MenuStyle.spacer(_column, 20.0)

	var level_time := Game.run_time - float(Game.level_start.get("run_time", 0.0))
	var level_kills := Game.kills - int(Game.level_start.get("kills", 0))
	_stat("Robots destroyed", str(level_kills))
	if Game.astronauts_total > 0:
		_stat("Astronauts rescued", "%d / %d" % [Game.astronauts_rescued, Game.astronauts_total])
	if Game.secrets_total > 0:
		_stat("Secrets found", "%d / %d" % [Game.secrets_found, Game.secrets_total])
	_stat("Flight time", "%d:%02d" % [int(level_time) / 60, int(level_time) % 60])
	if won:
		_stat("Time to spare", "%d s" % int(Game.escape_left))
		_stat("Escape bonus", "+%d" % Game.escape_bonus)
	_stat("Lives left", str(maxi(Game.lives, 0)))
	_stat("Difficulty", str(Game.DIFFICULTIES[Game.difficulty]["name"]))
	if won:
		_stat("Rank", Game.level_rank(), 34)
	MenuStyle.spacer(_column, 8.0)
	_stat("Score", str(Game.score), 34)
	MenuStyle.spacer(_column, 24.0)

	var has_next: bool = won and Game.has_next_level()
	var finished_campaign: bool = won and not has_next
	var label := "Next Level" if has_next else ("Continue" if won else "Retry Level")
	var next_step: Callable = Game.next_level if has_next else (Game.play_ending if finished_campaign else Game.restart_level)
	primary = MenuStyle.button(_column, label, next_step)
	MenuStyle.button(_column, "Main Menu", Game.to_title)
	primary.grab_focus.call_deferred()

	# Fades in over whatever ended the run, like the escape's white-out.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME)


func _stat(label_text: String, value: String, font_size := 22) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(MenuStyle.TEXT, 0.72))
	row.add_child(label)
	var number := Label.new()
	number.text = value
	number.add_theme_font_size_override("font_size", font_size)
	number.add_theme_color_override("font_color", MenuStyle.ACCENT)
	row.add_child(number)
	_column.add_child(row)
	stats[label_text] = value


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.to_title()
