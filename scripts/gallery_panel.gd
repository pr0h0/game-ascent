class_name GalleryPanel
extends VBoxContainer
## Browse everything encountered so far: list on the left, details beside it.
## The selected model is shown on the home screen's turntable.

signal entry_selected(entry: Dictionary)
signal back_pressed
signal inspect_pressed

const LIST_WIDTH := 240.0
const DETAIL_WIDTH := 420.0
const HEIGHT := 560.0

var rows: Dictionary = {}
var current: Dictionary = {}
var _count: Label
var _list: VBoxContainer
var _name: Label
var _category: Label
var _lore: Label
var _stats: VBoxContainer
var inspect_button: Button


func _ready() -> void:
	var title := MenuStyle.heading(self, "Gallery", 40)
	_count = Label.new()
	_count.add_theme_color_override("font_color", MenuStyle.DIM)
	add_child(_count)
	move_child(_count, title.get_index() + 1)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	var list_frame := PanelContainer.new()
	list_frame.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	body.add_child(list_frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_frame.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var detail_frame := PanelContainer.new()
	detail_frame.add_theme_stylebox_override("panel", MenuStyle.panel_style())
	detail_frame.custom_minimum_size = Vector2(DETAIL_WIDTH, HEIGHT)
	body.add_child(detail_frame)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	detail_frame.add_child(detail)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 32)
	_name.add_theme_color_override("font_color", MenuStyle.ACCENT)
	detail.add_child(_name)
	_category = Label.new()
	_category.add_theme_color_override("font_color", MenuStyle.DIM)
	detail.add_child(_category)
	_lore = Label.new()
	_lore.autowrap_mode = TextServer.AUTOWRAP_WORD
	_lore.custom_minimum_size = Vector2(DETAIL_WIDTH - 40.0, 0)
	detail.add_child(_lore)
	MenuStyle.spacer(detail, 10.0)
	_stats = VBoxContainer.new()
	detail.add_child(_stats)
	MenuStyle.spacer(self, 14.0)
	inspect_button = MenuStyle.button(self, "Inspect", func(): inspect_pressed.emit())
	MenuStyle.button(self, "Back", func(): back_pressed.emit())


## Rebuilds the list, since finishing a level can unlock new entries.
func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	rows.clear()
	var unlocked: int = Progress.unlocked_level()
	var all := GalleryData.entries()
	var open_count := 0
	var first: Dictionary = {}
	for category in GalleryData.CATEGORIES:
		var header := Label.new()
		header.text = category.to_upper()
		header.add_theme_color_override("font_color", MenuStyle.DIM)
		_list.add_child(header)
		for entry in all:
			if entry["category"] != category:
				continue
			var is_open := GalleryData.is_unlocked(entry, unlocked)
			var row := Button.new()
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text = entry["name"] if is_open else "? ? ?"
			row.disabled = not is_open
			row.pressed.connect(select.bind(entry))
			MenuStyle.add_sounds(row)
			_list.add_child(row)
			rows[entry["id"]] = row
			if is_open:
				open_count += 1
				if first.is_empty():
					first = entry
		MenuStyle.spacer(_list, 8.0)
	_count.text = "%d of %d discovered" % [open_count, all.size()]
	select(first)
	rows[first["id"]].grab_focus.call_deferred()


func select(entry: Dictionary) -> void:
	current = entry
	_name.text = entry["name"]
	_category.text = entry["category"]
	_lore.text = entry["lore"]
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for stat in entry["stats"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = stat[0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(MenuStyle.TEXT, 0.72))
		row.add_child(label)
		var value := Label.new()
		value.text = stat[1]
		value.add_theme_color_override("font_color", MenuStyle.ACCENT)
		row.add_child(value)
		_stats.add_child(row)
	entry_selected.emit(entry)
