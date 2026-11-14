class_name CockpitMfd
extends Node3D
## A live cockpit display: draws 2D instruments into a viewport shown on a dash quad.

enum Mode { STATUS, RADAR }

const SIZE := Vector2i(400, 272)
const SCREEN := Vector2(0.44, 0.3)
const RADAR_RANGE := 190.0
const REDRAW_INTERVAL := 1.0 / 15.0
const CYAN := Color(0.45, 0.92, 1.0)
const AMBER := Color(1.0, 0.72, 0.28)
const BG := Color(0.012, 0.035, 0.06)

var mode := Mode.STATUS
var _viewport: SubViewport
var _material: StandardMaterial3D
var _canvas: Control
var _timer := 0.0
var _sweep := 0.0
## Every scanline as one batch of segments, built once.
static var _scanlines := PackedVector2Array()


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	add_child(_viewport)
	_canvas = Control.new()
	_canvas.size = Vector2(SIZE)
	_canvas.draw.connect(_paint)
	_viewport.add_child(_canvas)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_material = mat
	var quad := QuadMesh.new()
	quad.size = SCREEN
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func set_brightness(amount: float) -> void:
	_material.albedo_color = Color(amount, amount, amount)


## Outside the cockpit nobody sees the screens, so they neither render nor redraw.
func set_active(on: bool) -> void:
	set_process(on)
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_timer = 0.0


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta * 2.2, TAU)
	_timer -= delta
	if _timer <= 0.0:
		_timer = REDRAW_INTERVAL
		_canvas.queue_redraw()


func _paint() -> void:
	var p: Player = Game.player
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), BG)
	if p == null:
		return
	if mode == Mode.STATUS:
		_status(p)
	else:
		_radar(p)
	# Scanlines and a frame give the panel a physical, CRT-like finish.
	if _scanlines.is_empty():
		for y in range(0, SIZE.y, 4):
			_scanlines.append(Vector2(0, y))
			_scanlines.append(Vector2(SIZE.x, y))
	_canvas.draw_multiline(_scanlines, Color(0, 0, 0, 0.16), 1.0)
	_canvas.draw_rect(Rect2(Vector2(3, 3), Vector2(SIZE) - Vector2(6, 6)), Color(CYAN, 0.4), false, 2.0)


func _text(text: String, at: Vector2, font_size: int, color: Color) -> void:
	_canvas.draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _bar(label: String, at: Vector2, ratio: float, color: Color) -> void:
	_text(label, at + Vector2(0, -6), 18, Color(color, 0.8))
	var size := Vector2(226, 20)
	for i in 20:
		var cell := Rect2(at + Vector2(i * size.x / 20.0, 0), Vector2(size.x / 20.0 - 3.0, size.y))
		var lit := float(i) / 20.0 < clampf(ratio, 0.0, 1.0)
		_canvas.draw_rect(cell, Color(color, 0.95 if lit else 0.12))


func _status(p: Player) -> void:
	_text("WR-9 SYSTEMS", Vector2(18, 32), 20, CYAN)
	var low := p.shield < Player.LOW_SHIELD
	_bar("SHIELD", Vector2(18, 74), p.shield / Player.MAX_SHIELD, Color(1, 0.3, 0.2) if low else CYAN)
	_bar("ENERGY", Vector2(18, 128), p.energy / Player.MAX_ENERGY, AMBER)
	_text("%s %02d" % [Weapons.SECONDARY[p.current_secondary]["name"], int(p.ammo.get(p.current_secondary, 0))], Vector2(18, 188), 26, Color(1.0, 0.55, 0.4))
	_text("%03d M/S" % int(p.velocity.length()), Vector2(18, 226), 26, Color(0.8, 0.92, 1.0))
	var x := 292.0
	_text("KEYS", Vector2(x, 42), 18, Color(CYAN, 0.8))
	var i := 0
	for color: String in ["blue", "yellow", "red"]:
		var col: Color = Game.KEY_COLORS[color]
		var box := Rect2(Vector2(x, 58.0 + i * 42.0), Vector2(84, 32))
		_canvas.draw_rect(box, Color(col, 0.9 if Game.has_key(color) else 0.1))
		_canvas.draw_rect(box, Color(col, 0.75), false, 2.0)
		i += 1
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	if Game.reactor_down:
		_text("CORE", Vector2(x, 216), 22, Color(1, 0.25, 0.15, pulse))
		_text("BREACH", Vector2(x, 242), 22, Color(1, 0.25, 0.15, pulse))


func _radar(p: Player) -> void:
	var center := Vector2(200, 142)
	var radius := 118.0
	_text("RADAR", Vector2(18, 32), 20, CYAN)
	_text("%dm" % int(RADAR_RANGE), Vector2(330, 32), 18, Color(CYAN, 0.6))
	for f: float in [0.33, 0.66, 1.0]:
		_canvas.draw_arc(center, radius * f, 0.0, TAU, 56, Color(CYAN, 0.32), 1.5, true)
	_canvas.draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(CYAN, 0.2), 1.0)
	_canvas.draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(CYAN, 0.2), 1.0)
	for i in 14:
		var a := _sweep - float(i) * 0.05
		var fade := 0.34 * (1.0 - float(i) / 14.0)
		_canvas.draw_line(center, center + Vector2(cos(a), sin(a)) * radius, Color(0.4, 1.0, 0.8, fade), 3.0, true)
	var inv := p.global_transform.affine_inverse()
	# Threats and supplies: the radar never points the way to an objective.
	for e in p.get_tree().get_nodes_in_group("enemy"):
		if not e is Reactor and e.can_be_locked():
			_blip(inv * (e.global_position as Vector3), center, radius, Color(1.0, 0.32, 0.22), 3.5)
	# Keys stay off the radar on purpose: finding them is the level's puzzle.
	for n in p.get_tree().get_nodes_in_group("pickup"):
		if not n.kind.begins_with("key_"):
			_blip(inv * (n.global_position as Vector3), center, radius, Pickup.INFO[n.kind]["color"], 5.5 if n.kind.begins_with("upgrade_") else 3.0)
	_canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(6, 7), center + Vector2(-6, 7)]), Color(0.9, 1.0, 1.0))


## Local x/z map to the screen; blips above or below the ship draw a stalk.
func _blip(local: Vector3, center: Vector2, radius: float, color: Color, size: float) -> void:
	var flat := Vector2(local.x, local.z) / RADAR_RANGE
	if flat.length() > 1.0:
		return
	var at := center + flat * radius
	var lift := clampf(local.y / RADAR_RANGE, -0.3, 0.3) * radius
	if absf(lift) > 2.0:
		_canvas.draw_line(at, at + Vector2(0, -lift), Color(color, 0.5), 1.5)
	_canvas.draw_circle(at + Vector2(0, -lift), size, color)
