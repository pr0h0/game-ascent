class_name MainMenu
extends CanvasLayer
## Home screen UI: main list, saved games and settings.

const TITLE_SHADER := """
shader_type canvas_item;
uniform float top = 0.0;
uniform float bottom = 80.0;
varying float y;
void vertex() {
	y = VERTEX.y;
}
void fragment() {
	float t = clamp((y - top) / (bottom - top), 0.0, 1.0);
	// Molten metal: white-hot at the top, cooling through orange to ember at the base.
	vec3 c = mix(vec3(1.0, 0.98, 0.88), vec3(1.0, 0.78, 0.31), smoothstep(0.12, 0.45, t));
	c = mix(c, vec3(0.94, 0.43, 0.08), smoothstep(0.45, 0.75, t));
	c = mix(c, vec3(0.59, 0.12, 0.04), smoothstep(0.75, 1.0, t));
	COLOR.rgb *= c;
}
"""

var buttons: Dictionary = {}
var panels: Dictionary = {}
var current := "main"
var load_rows: VBoxContainer
var level_rows: VBoxContainer
var gallery: GalleryPanel
var difficulty_buttons: Array[Button] = []
var _pending_level := 0
var story_rows: VBoxContainer
var _from_new_game := false
var inspecting := false
var _root: Control
var _inspect_hint: Label

signal showcase_changed(entry: Dictionary)
signal inspect_changed(on: bool)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MenuStyle.make_theme()
	add_child(root)
	_root = root
	_inspect_hint = Label.new()
	_inspect_hint.text = "Drag: rotate    Wheel: zoom    Esc: back"
	_inspect_hint.add_theme_font_size_override("font_size", 20)
	_inspect_hint.add_theme_color_override("font_color", MenuStyle.TEXT)
	_inspect_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_inspect_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inspect_hint.offset_top = -56.0
	_inspect_hint.offset_bottom = -24.0
	_inspect_hint.visible = false
	add_child(_inspect_hint)
	panels["main"] = _build_main(root)
	panels["load"] = _build_load(root)
	var settings := SettingsPanel.new()
	root.add_child(settings)
	MenuStyle.place_left(settings, 680.0)
	settings.back_pressed.connect(show_panel.bind("main"))
	panels["settings"] = settings
	panels["levels"] = _build_levels(root)
	panels["difficulty"] = _build_difficulty(root)
	panels["story"] = _build_story(root)
	gallery = GalleryPanel.new()
	root.add_child(gallery)
	MenuStyle.place_left(gallery, 690.0)
	gallery.entry_selected.connect(func(entry): showcase_changed.emit(entry))
	gallery.back_pressed.connect(show_panel.bind("main"))
	gallery.inspect_pressed.connect(set_inspecting.bind(true))
	panels["gallery"] = gallery
	show_panel("main")


func _menu_button(parent: Control, key: String, text: String, action: Callable) -> void:
	buttons[key] = MenuStyle.button(parent, text, action)


func _build_main(root: Control) -> Control:
	var column := MenuStyle.column(root, 380.0)
	_style_title(MenuStyle.heading(column, "ASCENT", 84))
	_menu_button(column, "new", "New Game", _new_game_pressed)
	_menu_button(column, "continue", "Continue", Game.continue_game)
	_menu_button(column, "load", "Load Saved Game", show_panel.bind("load"))
	_menu_button(column, "levels", "Select Level", show_panel.bind("levels"))
	_menu_button(column, "story", "Story", show_panel.bind("story"))
	_menu_button(column, "gallery", "Gallery", show_panel.bind("gallery"))
	_menu_button(column, "settings", "Settings", show_panel.bind("settings"))
	if not OS.has_feature("web"):   # in a browser quitting only freezes the page
		_menu_button(column, "quit", "Quit", get_tree().quit)
	return column


## Stencilled lettering in a molten-metal gradient with a dark ember drop shadow.
func _style_title(title: Label) -> void:
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/BlackOpsOne.ttf")
	font.spacing_glyph = 10
	title.add_theme_font_override("font", font)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0.16, 0.03, 0.01, 0.95))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	var shader := Shader.new()
	shader.code = TITLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# The gradient spans the capitals (baseline up one cap height), not the whole line box.
	var size := title.get_theme_font_size("font_size")
	var ascent := font.get_ascent(size)
	mat.set_shader_parameter("top", ascent - size * 0.65)
	mat.set_shader_parameter("bottom", ascent)
	title.material = mat


func _build_difficulty(root: Control) -> Control:
	var column := MenuStyle.column(root, 620.0)
	MenuStyle.heading(column, "Difficulty", 40)
	for i in Game.DIFFICULTIES.size():
		var d: Dictionary = Game.DIFFICULTIES[i]
		var b := MenuStyle.button(column, str(d["name"]), _start_on.bind(i))
		var note := Label.new()
		note.text = "Enemy damage %d%%  ·  Enemy armour %d%%  ·  Lives %d  ·  Score ×%s" % [int(d["damage"] * 100.0), int(d["hp"] * 100.0), int(d["lives"]), str(d["score"])]
		note.add_theme_color_override("font_color", Color(MenuStyle.TEXT, 0.6))
		note.add_theme_font_size_override("font_size", 16)
		column.add_child(note)
		difficulty_buttons.append(b)
	MenuStyle.spacer(column, 14.0)
	MenuStyle.button(column, "Back", show_panel.bind("main"))
	return column


func _build_story(root: Control) -> Control:
	var column := MenuStyle.column(root, 560.0)
	MenuStyle.heading(column, "Story", 40)
	story_rows = VBoxContainer.new()
	story_rows.add_theme_constant_override("separation", 6)
	column.add_child(story_rows)
	MenuStyle.spacer(column, 14.0)
	MenuStyle.button(column, "Back", show_panel.bind("main"))
	return column


## Only what has been reached can be rewatched, so nothing is spoiled.
func _refresh_story() -> void:
	for row in story_rows.get_children():
		story_rows.remove_child(row)
		row.queue_free()
	var unlocked: int = Progress.unlocked_level()
	for i in StoryData.CHAPTERS.size():
		var open: bool = Progress.finished_game() if i == StoryData.ENDING else i <= unlocked
		var label := "Epilogue" if i == StoryData.ENDING else "Chapter %d" % (i + 1)
		var title: String = str(StoryData.CHAPTERS[i]["title"]) if open else "Locked"
		var b := MenuStyle.button(story_rows, "%s: %s" % [label, title], Game.play_story.bind(i, "title"))
		b.disabled = not open
		if i == 0:
			b.grab_focus.call_deferred()


func _new_game_pressed() -> void:
	_from_new_game = true
	_ask_difficulty(0)


func _ask_difficulty(level: int) -> void:
	_pending_level = level
	show_panel("difficulty")
	difficulty_buttons[Game.difficulty].grab_focus.call_deferred()


func _start_on(difficulty: int) -> void:
	Game.difficulty = difficulty
	Game.start_level(_pending_level, _from_new_game)


func _build_load(root: Control) -> Control:
	var column := MenuStyle.column(root, 760.0)
	MenuStyle.heading(column, "Load Saved Game", 40)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	column.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	load_rows = VBoxContainer.new()
	load_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(load_rows)
	MenuStyle.spacer(column, 14.0)
	MenuStyle.button(column, "Back", show_panel.bind("main"))
	return column


func _build_levels(root: Control) -> Control:
	var column := MenuStyle.column(root, 560.0)
	MenuStyle.heading(column, "Select Level", 40)
	level_rows = VBoxContainer.new()
	level_rows.add_theme_constant_override("separation", 6)
	column.add_child(level_rows)
	MenuStyle.spacer(column, 14.0)
	MenuStyle.button(column, "Back", show_panel.bind("main"))
	return column


func _refresh_levels() -> void:
	for row in level_rows.get_children():
		level_rows.remove_child(row)
		row.queue_free()
	var unlocked: int = Progress.unlocked_level()
	for i in Game.levels.size():
		var open := i <= unlocked
		var b := MenuStyle.button(level_rows, _level_label(i) if open else "Level %d: Locked" % (i + 1), _pick_level.bind(i))
		b.disabled = not open
		if i == 0:
			b.grab_focus.call_deferred()


## Level title plus the best rank earned on it, on any difficulty.
func _pick_level(i: int) -> void:
	_from_new_game = false
	_ask_difficulty(i)


func _level_label(i: int) -> String:
	var best_rank := ""
	for d in Game.DIFFICULTIES.size():
		var result: Dictionary = Progress.best(i, d)
		if not result.is_empty() and (best_rank == "" or "SABCD".find(result["rank"]) < "SABCD".find(best_rank)):
			best_rank = result["rank"]
	return Game.level_title(i) + ("    [%s]" % best_rank if best_rank != "" else "")


func _refresh_load_list() -> void:
	for row in load_rows.get_children():
		load_rows.remove_child(row)
		row.queue_free()
	for save in Saves.list():
		load_rows.add_child(_save_row(save))


func _save_row(save: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var open := Button.new()
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.text = "%s    %s    Score %d    Lives %d" % [Game.level_title(int(save["level_index"])), _date_text(save["created_unix"]), int(save["score"]), int(save["lives"])]
	open.pressed.connect(Game.load_snapshot.bind(save))
	row.add_child(open)
	var remove := Button.new()
	remove.text = "Delete"
	remove.pressed.connect(_on_delete_pressed.bind(remove, save["id"]))
	# A second press confirms; moving away cancels.
	remove.focus_exited.connect(func(): remove.text = "Delete")
	remove.mouse_exited.connect(func(): remove.text = "Delete")
	row.add_child(remove)
	return row


func _on_delete_pressed(button: Button, id: String) -> void:
	if button.text != "Confirm?":
		button.text = "Confirm?"
		return
	Saves.delete(id)
	_refresh_load_list()
	_refresh_main()
	if not Saves.has_any():
		show_panel("main")


func _date_text(unix: float) -> String:
	var local := int(unix) + int(Time.get_time_zone_from_system()["bias"]) * 60
	return Time.get_datetime_string_from_unix_time(local, true).left(16)


func _refresh_main() -> void:
	var has_saves: bool = Saves.has_any()
	buttons["continue"].disabled = not has_saves
	buttons["load"].disabled = not has_saves


func show_panel(panel: String) -> void:
	current = panel
	for key in panels:
		panels[key].visible = key == panel
	_refresh_main()
	if panel == "load":
		_refresh_load_list()
	if panel == "levels":
		_refresh_levels()
	if panel == "story":
		_refresh_story()
	if panel == "gallery":
		gallery.refresh()
	else:
		showcase_changed.emit({})
	if panel == "main":
		var first: Button = buttons["continue"] if not buttons["continue"].disabled else buttons["new"]
		first.grab_focus.call_deferred()


## Clears the screen and centres the model, so it can be turned and studied.
func set_inspecting(on: bool) -> void:
	inspecting = on
	_root.visible = not on
	_inspect_hint.visible = on
	inspect_changed.emit(on)
	if not on:
		gallery.inspect_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if inspecting:
		if event.is_action_pressed("ui_cancel"):
			set_inspecting(false)
			get_viewport().set_input_as_handled()
		return
	if current != "main" and event.is_action_pressed("ui_cancel"):
		show_panel("main")
		get_viewport().set_input_as_handled()
