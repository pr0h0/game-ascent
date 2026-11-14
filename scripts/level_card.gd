class_name LevelCard
extends CanvasLayer
## Opens a level on black: the title holds while the first frames settle, then fades.

const HOLD := 1.0
const FADE := 0.7


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	black.add_child(column)
	var title := Label.new()
	title.text = Game.level_title(Game.level_index).to_upper()
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", MenuStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := Label.new()
	sub.text = str(Game.DIFFICULTIES[Game.difficulty]["name"])
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", MenuStyle.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var t := black.create_tween()
	t.tween_interval(HOLD)
	t.tween_property(black, "modulate:a", 0.0, FADE)
	t.tween_callback(queue_free)
