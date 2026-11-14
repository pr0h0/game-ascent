class_name GamepadDiagram
extends Control
## A drawn Xbox or PlayStation controller, with each control labelled by its action.
## Controls light up when pressed on a real pad or picked in the bindings list.

const DESIGN := Vector2(1320.0, 620.0)
const CENTER := 660.0
const COLUMN := 250.0
const EDGE := 12.0
const FONT_SIZE := 18
const LINE_HEIGHT := 22.0
const GROUP_GAP := 12.0
const BODY := Color(0.13, 0.15, 0.19)
const OUTLINE := Color(0.5, 0.56, 0.64)
const PART := Color(0.21, 0.24, 0.29)
const LEADER := Color(0.42, 0.47, 0.54, 0.75)
const LIT := MenuStyle.ACCENT
const DIRECTIONS := ["Up", "Down", "Left", "Right"]

const XBOX_OUTLINE := [Vector2(0, 142), Vector2(120, 132), Vector2(190, 114), Vector2(245, 127), Vector2(290, 177), Vector2(318, 262), Vector2(345, 382), Vector2(345, 442), Vector2(318, 472), Vector2(275, 464), Vector2(235, 402), Vector2(190, 374), Vector2(120, 374), Vector2(0, 374)]
const PS_OUTLINE := [Vector2(0, 132), Vector2(150, 127), Vector2(230, 120), Vector2(280, 142), Vector2(310, 202), Vector2(335, 322), Vector2(365, 432), Vector2(350, 482), Vector2(305, 477), Vector2(265, 402), Vector2(225, 362), Vector2(170, 374), Vector2(0, 374)]

var layout: int = Controls.Layout.XBOX:
	set(value):
		layout = value
		queue_redraw()
var selected_code := "":
	set(value):
		selected_code = value
		queue_redraw()
var _font: Font
var _outline_cache := {}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	if is_visible_in_tree() and Controls.connected_pad() >= 0:
		queue_redraw()


func _is_ps() -> bool:
	return layout == Controls.Layout.PLAYSTATION


func _lit(code: String) -> bool:
	if code == selected_code and code != "":
		return true
	var pad := Controls.connected_pad()
	if pad < 0:
		return false
	var number := code.substr(1).to_int()
	if code[0] == "b":
		return Input.is_joy_button_pressed(pad, number as JoyButton)
	var value := Input.get_joy_axis(pad, number as JoyAxis)
	return value > Controls.AXIS_PRESS if code.ends_with("+") else value < -Controls.AXIS_PRESS


func _any_lit(codes: Array) -> bool:
	return codes.any(_lit)


func _at(dx: float, y: float) -> Vector2:
	return Vector2(CENTER + dx, y)


# --- Where each control sits -------------------------------------------------------
func _left_stick() -> Vector2:
	return _at(-80, 345) if _is_ps() else _at(-170, 235)


func _right_stick() -> Vector2:
	return _at(80, 345) if _is_ps() else _at(85, 345)


func _dpad() -> Vector2:
	return _at(-175, 240) if _is_ps() else _at(-85, 345)


func _face() -> Vector2:
	return _at(175, 240) if _is_ps() else _at(170, 235)


func _back_button() -> Vector2:
	return _at(-108, 168) if _is_ps() else _at(-50, 235)


func _start_button() -> Vector2:
	return _at(108, 168) if _is_ps() else _at(50, 235)


# --- Drawing ----------------------------------------------------------------------
func _draw() -> void:
	var fit := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if fit <= 0.0:
		return
	draw_set_transform((size - DESIGN * fit) * 0.5, 0.0, Vector2(fit, fit))
	_draw_shoulders()
	_draw_body()
	_draw_sticks()
	_draw_dpad()
	_draw_face()
	_draw_small_buttons()
	_draw_callouts()


func _pill(rect: Rect2, fill: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = OUTLINE
	box.set_border_width_all(2)
	box.set_corner_radius_all(int(minf(rect.size.x, rect.size.y) * 0.45))
	draw_style_box(box, rect)


func _part_color(lit: bool) -> Color:
	return LIT if lit else PART


func _draw_shoulders() -> void:
	for side: float in [-1.0, 1.0]:
		var left := side < 0.0
		var trigger := Controls.axis_code(JOY_AXIS_TRIGGER_LEFT if left else JOY_AXIS_TRIGGER_RIGHT, 1)
		var bumper := Controls.button_code(JOY_BUTTON_LEFT_SHOULDER if left else JOY_BUTTON_RIGHT_SHOULDER)
		_pill(Rect2(_shoulder_x(side) - 42.0, 62.0, 84.0, 54.0), _part_color(_lit(trigger)))
		_pill(Rect2(_shoulder_x(side) - 66.0, 102.0, 132.0, 28.0), _part_color(_lit(bumper)))


func _shoulder_x(side: float) -> float:
	return CENTER + side * 190.0


func _draw_body() -> void:
	var outline := _body_outline()
	draw_colored_polygon(outline, BODY)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, OUTLINE, 2.5, true)
	if _is_ps():
		var touch := Rect2(CENTER - 82.0, 148.0, 164.0, 98.0)
		_pill(touch, _part_color(_lit(Controls.button_code(JOY_BUTTON_TOUCHPAD))))


## The outline as one smooth closed shape, cached since it only depends on the layout.
func _body_outline() -> PackedVector2Array:
	if _outline_cache.has(layout):
		return _outline_cache[layout]
	var half: Array = PS_OUTLINE if _is_ps() else XBOX_OUTLINE
	var points: Array = []
	for p: Vector2 in half:
		points.append(_at(p.x, p.y))
	for i in range(half.size() - 2, 0, -1):
		points.append(_at(-half[i].x, half[i].y))
	for round_pass in 3:
		var smooth: Array = []
		for i in points.size():
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			smooth.append(a.lerp(b, 0.25))
			smooth.append(a.lerp(b, 0.75))
		points = smooth
	var out := PackedVector2Array(points)
	_outline_cache[layout] = out
	return out


func _draw_sticks() -> void:
	var left := [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_BUTTON_LEFT_STICK]
	var right := [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_BUTTON_RIGHT_STICK]
	for entry: Array in [[_left_stick(), left], [_right_stick(), right]]:
		var at: Vector2 = entry[0]
		var ids: Array = entry[1]
		var moved := _stick_tilt(ids[0], ids[1])
		var lit := _any_lit([Controls.axis_code(ids[0], 1), Controls.axis_code(ids[0], -1), Controls.axis_code(ids[1], 1), Controls.axis_code(ids[1], -1), Controls.button_code(ids[2])])
		draw_circle(at, 46.0, Color(0.07, 0.08, 0.11))
		draw_arc(at, 46.0, 0.0, TAU, 48, OUTLINE, 2.0, true)
		draw_circle(at + moved * 16.0, 30.0, _part_color(lit))
		draw_arc(at + moved * 16.0, 30.0, 0.0, TAU, 40, OUTLINE, 2.0, true)


func _stick_tilt(axis_x: int, axis_y: int) -> Vector2:
	var pad := Controls.connected_pad()
	if pad < 0:
		return Vector2.ZERO
	return Vector2(Input.get_joy_axis(pad, axis_x as JoyAxis), Input.get_joy_axis(pad, axis_y as JoyAxis))


func _draw_dpad() -> void:
	var at := _dpad()
	var arms := {
		JOY_BUTTON_DPAD_UP: Rect2(at + Vector2(-15, -48), Vector2(30, 34)),
		JOY_BUTTON_DPAD_DOWN: Rect2(at + Vector2(-15, 14), Vector2(30, 34)),
		JOY_BUTTON_DPAD_LEFT: Rect2(at + Vector2(-48, -15), Vector2(34, 30)),
		JOY_BUTTON_DPAD_RIGHT: Rect2(at + Vector2(14, -15), Vector2(34, 30)),
	}
	draw_rect(Rect2(at - Vector2(15, 15), Vector2(30, 30)), PART)
	for button: int in arms:
		_pill(arms[button], _part_color(_lit(Controls.button_code(button))))


func _draw_face() -> void:
	var at := _face()
	var xbox_colors := [Color(0.35, 0.8, 0.4), Color(0.95, 0.35, 0.3), Color(0.35, 0.6, 1.0), Color(1.0, 0.82, 0.3)]
	var ps_colors := [Color(0.45, 0.65, 1.0), Color(0.98, 0.4, 0.4), Color(0.95, 0.5, 0.8), Color(0.4, 0.85, 0.7)]
	var buttons := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
	for i in buttons.size():
		var spot := at + _face_offset(buttons[i])
		var mark: Color = ps_colors[i] if _is_ps() else xbox_colors[i]
		if _lit(Controls.button_code(buttons[i])):
			mark = Color(0.08, 0.08, 0.1)
			draw_circle(spot, 21.0, LIT)
		else:
			draw_circle(spot, 21.0, PART)
		draw_arc(spot, 21.0, 0.0, TAU, 32, OUTLINE, 2.0, true)
		if _is_ps():
			_draw_ps_glyph(spot, buttons[i], mark)
		else:
			var letter: String = Controls.button_name(buttons[i], Controls.Layout.XBOX)
			draw_string(_font, spot + Vector2(-10.0, 8.0), letter, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 24, mark)


func _face_offset(button: int) -> Vector2:
	match button:
		JOY_BUTTON_A:
			return Vector2(0, 46)
		JOY_BUTTON_B:
			return Vector2(46, 0)
		JOY_BUTTON_X:
			return Vector2(-46, 0)
	return Vector2(0, -46)


func _draw_ps_glyph(at: Vector2, button: int, color: Color) -> void:
	const R := 10.0
	match button:
		JOY_BUTTON_A:
			draw_line(at + Vector2(-R, -R), at + Vector2(R, R), color, 2.5, true)
			draw_line(at + Vector2(-R, R), at + Vector2(R, -R), color, 2.5, true)
		JOY_BUTTON_B:
			draw_arc(at, R, 0.0, TAU, 28, color, 2.5, true)
		JOY_BUTTON_X:
			draw_rect(Rect2(at - Vector2(R, R), Vector2(R, R) * 2.0), color, false, 2.5)
		_:
			var tip := at + Vector2(0, -R - 1.0)
			var left := at + Vector2(-R, R - 2.0)
			var right := at + Vector2(R, R - 2.0)
			draw_polyline(PackedVector2Array([tip, left, right, tip]), color, 2.5, true)


func _draw_small_buttons() -> void:
	for entry: Array in [[_back_button(), JOY_BUTTON_BACK], [_start_button(), JOY_BUTTON_START]]:
		var at: Vector2 = entry[0]
		var lit := _lit(Controls.button_code(entry[1]))
		_pill(Rect2(at - Vector2(19, 11), Vector2(38, 22)), _part_color(lit))
	var guide := _at(0, 278) if _is_ps() else _at(0, 180)
	draw_circle(guide, 17.0, _part_color(_lit(Controls.button_code(JOY_BUTTON_GUIDE))))
	draw_arc(guide, 17.0, 0.0, TAU, 28, OUTLINE, 2.0, true)


# --- Labels -----------------------------------------------------------------------
func _bound(code: String) -> String:
	var table: Dictionary = Controls.bindings[Controls.GAMEPAD]
	for action: String in table:
		if table[action][0] == code:
			return Controls.action_label(action)
	return ""


## Label for a single control: one row, or nothing if it does no work.
func _single(side: int, anchor: Vector2, title: String, code: String) -> Dictionary:
	var action := _bound(code)
	return {"side": side, "anchor": anchor, "rows": [] if action == "" else ["%s: %s" % [title, action]], "codes": [code]}


## Label for a stick or d-pad: a title and a row per direction that does something.
func _multi(side: int, anchor: Vector2, title: String, codes: Array, names: Array) -> Dictionary:
	var rows: Array = []
	for i in codes.size():
		var action := _bound(codes[i])
		if action != "":
			rows.append("%s: %s" % [names[i], action])
	if not rows.is_empty():
		rows.push_front(title)
	return {"side": side, "anchor": anchor, "rows": rows, "codes": codes}


func _stick(side: int, anchor: Vector2, title: String, x: int, y: int, click: int) -> Dictionary:
	var codes := [Controls.axis_code(y, -1), Controls.axis_code(y, 1), Controls.axis_code(x, -1), Controls.axis_code(x, 1), Controls.button_code(click)]
	return _multi(side, anchor, title, codes, DIRECTIONS + ["Press"])


func _callouts() -> Array:
	var name_of := func(button: int) -> String: return Controls.button_name(button, layout)
	var dpad_codes := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT].map(Controls.button_code)
	var face := _face()
	var out := [
		_single(-1, Vector2(_shoulder_x(-1.0), 86.0), "L2" if _is_ps() else "LT", Controls.axis_code(JOY_AXIS_TRIGGER_LEFT, 1)),
		_single(-1, Vector2(_shoulder_x(-1.0), 116.0), name_of.call(JOY_BUTTON_LEFT_SHOULDER), Controls.button_code(JOY_BUTTON_LEFT_SHOULDER)),
		_stick(-1, _left_stick(), "Left stick", JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_BUTTON_LEFT_STICK),
		_multi(-1, _dpad(), "D-pad", dpad_codes, DIRECTIONS),
		_single(-1, _back_button(), name_of.call(JOY_BUTTON_BACK), Controls.button_code(JOY_BUTTON_BACK)),
		_single(1, Vector2(_shoulder_x(1.0), 86.0), "R2" if _is_ps() else "RT", Controls.axis_code(JOY_AXIS_TRIGGER_RIGHT, 1)),
		_single(1, Vector2(_shoulder_x(1.0), 116.0), name_of.call(JOY_BUTTON_RIGHT_SHOULDER), Controls.button_code(JOY_BUTTON_RIGHT_SHOULDER)),
		_single(1, face + _face_offset(JOY_BUTTON_Y), name_of.call(JOY_BUTTON_Y), Controls.button_code(JOY_BUTTON_Y)),
		_single(1, face + _face_offset(JOY_BUTTON_B), name_of.call(JOY_BUTTON_B), Controls.button_code(JOY_BUTTON_B)),
		_single(1, face + _face_offset(JOY_BUTTON_X), name_of.call(JOY_BUTTON_X), Controls.button_code(JOY_BUTTON_X)),
		_single(1, face + _face_offset(JOY_BUTTON_A), name_of.call(JOY_BUTTON_A), Controls.button_code(JOY_BUTTON_A)),
		_stick(1, _right_stick(), "Right stick", JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_BUTTON_RIGHT_STICK),
		{"side": 1, "anchor": _start_button(), "rows": ["%s: Pause" % name_of.call(JOY_BUTTON_START)], "codes": [Controls.button_code(JOY_BUTTON_START)]},
	]
	return out.filter(func(c: Dictionary) -> bool: return not c["rows"].is_empty())


func _draw_callouts() -> void:
	var all := _callouts()
	for side: int in [-1, 1]:
		var group: Array = all.filter(func(c: Dictionary) -> bool: return c["side"] == side)
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["anchor"].y < b["anchor"].y)
		var y := 30.0
		for callout: Dictionary in group:
			var rows: Array = callout["rows"]
			var height: float = rows.size() * LINE_HEIGHT
			y = maxf(y, callout["anchor"].y - height * 0.5)
			y = minf(y, DESIGN.y - height - 10.0)
			_draw_callout(callout, side, y)
			y += height + GROUP_GAP


func _draw_callout(callout: Dictionary, side: int, top: float) -> void:
	var rows: Array = callout["rows"]
	var left := side < 0
	var text_x := EDGE if left else DESIGN.x - EDGE - COLUMN
	var lead_x := EDGE + COLUMN + 6.0 if left else DESIGN.x - EDGE - COLUMN - 6.0
	var lit := _any_lit(callout["codes"])
	var mid := top + rows.size() * LINE_HEIGHT * 0.5
	draw_line(Vector2(lead_x, mid), callout["anchor"], LIT if lit else LEADER, 1.5, true)
	draw_circle(callout["anchor"], 3.0, LIT if lit else LEADER)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	for i in rows.size():
		var title_row: bool = rows.size() > 1 and i == 0
		var color: Color = LIT if lit or title_row else MenuStyle.TEXT
		draw_string(_font, Vector2(text_x, top + (i + 0.8) * LINE_HEIGHT), rows[i], align, COLUMN, FONT_SIZE, color)
