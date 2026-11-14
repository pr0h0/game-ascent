class_name MenuStyle
extends RefCounted
## The look shared by the home screen, pause menu and results screen.

const ACCENT := Color(1.0, 0.72, 0.3)
const TEXT := Color(0.86, 0.92, 0.98)
const DIM := Color(0.42, 0.47, 0.54)
const PANEL_BG := Color(0.02, 0.04, 0.07, 0.86)
const LEFT_MARGIN := 96.0


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 16.0
	empty.content_margin_top = 6.0
	empty.content_margin_bottom = 6.0
	var active := StyleBoxFlat.new()
	active.bg_color = Color(ACCENT, 0.1)
	active.border_color = ACCENT
	active.border_width_left = 3
	active.content_margin_left = 16.0
	active.content_margin_top = 6.0
	active.content_margin_bottom = 6.0
	t.set_stylebox("normal", "Button", empty)
	t.set_stylebox("disabled", "Button", empty)
	t.set_stylebox("hover", "Button", active)
	t.set_stylebox("pressed", "Button", active)
	t.set_stylebox("focus", "Button", active)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", ACCENT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("font_color", "Label", TEXT)
	return t


## A column pinned to the left edge and centred vertically.
static func column(root: Control, width: float) -> VBoxContainer:
	var c := VBoxContainer.new()
	root.add_child(c)
	place_left(c, width)
	return c


static func place_left(c: Control, width: float) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	c.offset_left = LEFT_MARGIN
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.custom_minimum_size = Vector2(width, 0)
	c.add_theme_constant_override("separation", 6)


static func heading(parent: Control, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	spacer(parent, 26.0)
	return label


static func spacer(parent: Control, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	parent.add_child(gap)


static func button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(action)
	add_sounds(b)
	parent.add_child(b)
	return b


static func add_sounds(b: BaseButton) -> void:
	b.pressed.connect(Sfx.play.bind("ui_click", null, -6.0))
	b.mouse_entered.connect(func(): if not b.disabled: Sfx.play("ui_hover", null, -8.0))
	b.focus_entered.connect(func(): if Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down"): Sfx.play("ui_hover", null, -8.0))


static func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_content_margin_all(18.0)
	return s


## Dark layer behind a menu; full-screen so clicks can't reach the game.
static func backdrop(parent: Control, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r
