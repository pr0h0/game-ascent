extends CanvasLayer
## Flight HUD, pause menu and end-of-run panel. Drawn entirely in code.

const CYAN := Color(0.55, 0.95, 1.0)
const AMBER := Color(1.0, 0.72, 0.28)
const RED := Color(1.0, 0.28, 0.2)
const HIT_ARROW_TIME := 1.1
const MAX_INCOMING := 6
## Below this the shield warning turns into a heartbeat and a flashing call-out.
const CRITICAL_SHIELD := 15.0
const HEARTBEAT_GAP := 0.85

const MAX_LIFE_MARKS := 5
const CONDENSED_LIFE_MARKS := 3
const LIFE_SPACING := 16.0
const LIFE_TEXT_GAP := 12.0
const LIFE_TEXT_SIZE := 15
const TARGET_RANGE := 240.0
## Target brackets re-check line of sight this often instead of every frame.
const SIGHT_CHECK_GAP := 0.1

var _draw_layer: Control
var _feed: VBoxContainer
var _timer: Label
var _hurt := 0.0
var _hit_marker := 0.0
var _kill_marker := 0.0
var _heartbeat := 0.0
## Recent hits on the ship as [world position, time left].
var _incoming: Array = []
var pause_menu: PauseMenu
var results: ResultsScreen
## The enemy group, fetched once per frame for the brackets and the boss bar.
var _enemies: Array = []
## Instance ids of enemies the ship could see at the last sight check.
var _in_sight: Dictionary = {}
var _sight_cd := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	_draw_layer = Control.new()
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.draw.connect(_paint)
	add_child(_draw_layer)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(30, 24)
	add_child(_feed)
	_timer = _label(52, RED)
	_timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer.position.y = 26
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.visible = false

	results = ResultsScreen.new()
	add_child(results)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)

	Game.message.connect(_on_message)
	Game.player_hurt.connect(func(amount): _hurt = minf(1.0, _hurt + amount * 0.05))
	Game.player_hit.connect(func(from: Vector3): _incoming.append([from, HIT_ARROW_TIME]))
	Game.enemy_hit.connect(_on_enemy_hit)
	Game.run_ended.connect(_on_run_ended)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	return l


func _on_message(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	_feed.add_child(l)
	var t := l.create_tween()
	t.tween_interval(4.0)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)


func _on_run_ended(won: bool, detail: String) -> void:
	Sfx.stop_loop("alarm")
	Music.sting("sting_win" if won else "sting_lose")
	results.show_results(won, detail)


func _on_enemy_hit(killed: bool) -> void:
	_hit_marker = 1.0
	if killed:
		_kill_marker = 1.0
		Sfx.play("kill_confirm", null, -7.0)
	else:
		Sfx.play("hit_confirm", null, -14.0, randf_range(0.95, 1.05))


func _process(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta * 1.6)
	_hit_marker = maxf(0.0, _hit_marker - delta * 7.0)
	_kill_marker = maxf(0.0, _kill_marker - delta * 3.0)
	if not _incoming.is_empty():
		for hit: Array in _incoming:
			hit[1] -= delta
		_incoming = _incoming.filter(func(h): return h[1] > 0.0).slice(-MAX_INCOMING)
	_enemies = get_tree().get_nodes_in_group("enemy")
	_sight_cd -= delta
	if _sight_cd <= 0.0:
		_sight_cd = SIGHT_CHECK_GAP
		_check_sight()
	_update_heartbeat(delta)
	var escaping: bool = Game.reactor_down and not Game.finished and not Game.cinematic
	_timer.visible = escaping
	_feed.visible = not Game.cinematic
	if escaping:
		_timer.text = "%05.2f" % Game.escape_left
	_draw_layer.queue_redraw()


func _paint() -> void:
	var p: Player = Game.player
	if p == null:
		return
	var size := _draw_layer.size
	var c := size * 0.5
	if _hurt > 0.0:
		_draw_layer.draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.05, _hurt * 0.2))
	if Game.finished or Game.cinematic:
		return
	_power_tint(p, size)
	_hit_arrows(p, c)
	_hit_ticks(c)
	# Weapons only face forward, so there's nothing to aim with in the rear view.
	if p.rear_view:
		_center_text(ThemeDB.fallback_font, "REAR VIEW", Vector2(c.x, 46.0), 22, Color(CYAN, 0.9))
	else:
		_reticle(c)
	if p.rail_charge > 0.0:
		_draw_layer.draw_arc(c, 36.0, -PI / 2.0, -PI / 2.0 + TAU * p.rail_charge, 40, Weapons.RAIL_COLOR, 3.0, true)
	if p.is_disrupted():
		_center_text(ThemeDB.fallback_font, "WEAPONS OFFLINE", c + Vector2(0, 70), 22, RED)
	_boss_bar(size)
	if p.invincible_left > 0.0:
		_center_text(ThemeDB.fallback_font, "INVINCIBLE %d" % ceili(p.invincible_left), c + Vector2(0, 100), 20, AMBER)
	if p.cloak_left > 0.0:
		_center_text(ThemeDB.fallback_font, "INVISIBLE %d" % ceili(p.cloak_left), c + Vector2(0, 126), 20, Color(0.75, 0.55, 1.0))
	_gauges(p, c, size)
	_weapon_row(p, Vector2(30.0, size.y - 34.0))
	_targets(p, c)
	if Settings.show_fps:
		_draw_layer.draw_string(ThemeDB.fallback_font, Vector2(30.0, size.y - 66.0), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 1.0, 0.7))


## Under the warning beep, a heartbeat once the shield is nearly gone.
func _update_heartbeat(delta: float) -> void:
	var p: Player = Game.player
	if p == null or p.dead or p.shield >= CRITICAL_SHIELD or Game.finished or Game.cinematic or get_tree().paused:
		_heartbeat = 0.0
		return
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_heartbeat = HEARTBEAT_GAP
		Sfx.play("shield_critical", null, -6.0)


## A faint screen-edge colour says a power-up is running, without a text box.
func _power_tint(p: Player, size: Vector2) -> void:
	var color := Color.TRANSPARENT
	if p.invincible_left > 0.0:
		color = Color(1.0, 0.75, 0.2)
	elif p.cloak_left > 0.0:
		color = Color(0.7, 0.45, 1.0)
	elif p.shield < Player.LOW_SHIELD and not p.dead:
		color = RED
	if color.a == 0.0:
		return
	var strength := 0.12 + 0.05 * sin(Time.get_ticks_msec() * 0.008)
	var band := 26.0
	_draw_layer.draw_rect(Rect2(0, 0, size.x, band), Color(color, strength))
	_draw_layer.draw_rect(Rect2(0, size.y - band, size.x, band), Color(color, strength))
	_draw_layer.draw_rect(Rect2(0, band, band, size.y - band * 2.0), Color(color, strength))
	_draw_layer.draw_rect(Rect2(size.x - band, band, band, size.y - band * 2.0), Color(color, strength))


## An arc on the side a hit came from, including hits from behind.
func _hit_arrows(p: Player, c: Vector2) -> void:
	var radius := 150.0
	for hit: Array in _incoming:
		var local: Vector3 = p.cam.global_basis.inverse() * ((hit[0] as Vector3) - p.cam.global_position)
		var angle := atan2(-local.y, local.x)
		if Vector2(local.x, local.y).length() < 0.2:
			angle = PI * 0.5
		var alpha := clampf(float(hit[1]) / HIT_ARROW_TIME, 0.0, 1.0)
		_draw_layer.draw_arc(c, radius, angle - 0.32, angle + 0.32, 18, Color(RED, alpha * 0.9), 7.0, true)


## Small crosshair ticks confirm a connection; red and larger for a kill.
func _hit_ticks(c: Vector2) -> void:
	var amount := maxf(_hit_marker, _kill_marker)
	if amount <= 0.0:
		return
	var colour := Color(RED, _kill_marker) if _kill_marker > 0.0 else Color(1, 1, 1, _hit_marker)
	var reach := 15.0 + (_kill_marker * 10.0)
	for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_draw_layer.draw_line(c + d.normalized() * reach, c + d.normalized() * (reach + 9.0), colour, 2.0, true)


## One box per gun slot: dim when not owned, bright when selected.
func _weapon_row(p: Player, at: Vector2) -> void:
	var font := ThemeDB.fallback_font
	_draw_layer.draw_string(font, at + Vector2(0.0, -8.0), Weapons.PRIMARY[p.current_primary]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 1.0, 0.8))
	for i in Weapons.SLOTS.size():
		var weapon: String = Weapons.SLOTS[i]
		var owned := weapon == "laser" or Game.has_upgrade("weapon_" + weapon)
		var selected := weapon == p.current_primary
		var rect := Rect2(at + Vector2(i * 30.0, 0.0), Vector2(26.0, 20.0))
		var tint := Color(0.75, 1.0, 0.8) if selected else (Color(CYAN, 0.65) if owned else Color(0.5, 0.55, 0.6, 0.25))
		_draw_layer.draw_rect(rect, Color(tint, 0.22 if selected else 0.06))
		_draw_layer.draw_rect(rect, tint, false, 1.3 if not selected else 2.0)
		_draw_layer.draw_string(font, rect.position + Vector2(0.0, 15.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 26.0, 13, tint)


func _boss_bar(size: Vector2) -> void:
	for e in _enemies:
		if not is_instance_valid(e):
			continue
		if e is Boss and e.alerted:
			var w := size.x * 0.4
			var at := Vector2((size.x - w) * 0.5, 30.0)
			_draw_layer.draw_rect(Rect2(at, Vector2(w, 12)), Color(0, 0, 0, 0.6))
			_draw_layer.draw_rect(Rect2(at, Vector2(w * clampf(e.hp_ratio(), 0.0, 1.0), 12)), RED)
			_center_text(ThemeDB.fallback_font, e.title(), Vector2(size.x * 0.5, 66.0), 18, RED)


func _reticle(c: Vector2) -> void:
	var col := Color(CYAN, 0.9)
	var gap := 11.0
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]:
		_draw_layer.draw_line(c + d * gap, c + d * (gap + 13.0), col, 1.6, true)
	_draw_layer.draw_arc(c, 27.0, deg_to_rad(205), deg_to_rad(335), 24, Color(CYAN, 0.45), 1.3, true)
	_draw_layer.draw_circle(c, 1.5, col)


func _gauges(p: Player, c: Vector2, size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var base := Vector2(c.x, size.y - 40.0)
	var radius := 86.0
	# Shield arc on the left, energy arc on the right, around a central readout.
	var low_shield := p.shield < Player.LOW_SHIELD
	_arc_gauge(base, radius, 180.0, 262.0, p.shield / Player.MAX_SHIELD, RED if low_shield else CYAN)
	_arc_gauge(base, radius, 360.0, 278.0, p.energy / Player.MAX_ENERGY, AMBER)
	_center_text(font, "%d" % ceili(p.shield), base + Vector2(-126, -8), 30, RED if low_shield else CYAN)
	_center_text(font, "SHIELD", base + Vector2(-126, 12), 12, Color(CYAN, 0.7))
	if low_shield and not p.dead:
		var critical := p.shield < CRITICAL_SHIELD
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.014 if critical else 0.007))
		_center_text(font, "SHIELD CRITICAL" if critical else "SHIELD LOW", base + Vector2(-126, -44), 16 if critical else 14, Color(RED, 0.35 + 0.65 * blink))
	_center_text(font, "%d" % ceili(p.energy), base + Vector2(126, -8), 30, AMBER)
	_center_text(font, "ENERGY", base + Vector2(126, 12), 12, Color(AMBER, 0.7))
	_center_text(font, "%s %02d" % [Weapons.SECONDARY[p.current_secondary]["name"], int(p.ammo.get(p.current_secondary, 0))], base + Vector2(0, -44), 20, Color(1, 0.55, 0.4))
	_center_text(font, "%03d m/s" % int(p.velocity.length()), base + Vector2(0, -20), 17, Color(0.8, 0.9, 1.0))
	_draw_lives(font, base + Vector2(0, 2))
	var right := size.x - 30.0
	_draw_layer.draw_string(font, Vector2(right - 260, 42), "SCORE %07d" % Game.score, HORIZONTAL_ALIGNMENT_RIGHT, 260, 22, Color(0.85, 0.95, 1.0))
	var i := 0
	for color: String in ["blue", "yellow", "red"]:
		var key_col: Color = Game.KEY_COLORS[color]
		var rect := Rect2(Vector2(right - 92.0 + i * 34.0, 56.0), Vector2(26, 16))
		_draw_layer.draw_rect(rect, Color(key_col, 0.95 if Game.has_key(color) else 0.14))
		_draw_layer.draw_rect(rect, Color(key_col, 0.8), false, 1.4)
		i += 1


## Up to five lives are drawn one by one; beyond that, three and a "+N" for the rest.
static func lives_display(lives: int) -> Dictionary:
	if lives <= MAX_LIFE_MARKS:
		return {"marks": maxi(lives, 0), "extra": 0}
	return {"marks": CONDENSED_LIFE_MARKS, "extra": lives - CONDENSED_LIFE_MARKS}


## The whole row, marks and count together, stays centred on the gauge.
func _draw_lives(font: Font, center: Vector2) -> void:
	var shown := lives_display(Game.lives)
	var marks: int = shown["marks"]
	var extra := "+%d" % shown["extra"] if shown["extra"] > 0 else ""
	var extra_width := font.get_string_size(extra, HORIZONTAL_ALIGNMENT_LEFT, -1, LIFE_TEXT_SIZE).x if extra != "" else 0.0
	var marks_width := maxf(marks - 1, 0) * LIFE_SPACING
	var width := marks_width + (LIFE_TEXT_GAP + extra_width if extra != "" else 0.0)
	var left := center.x - width * 0.5
	for i in marks:
		_draw_layer.draw_colored_polygon(_chevron(Vector2(left + i * LIFE_SPACING, center.y)), Color(CYAN, 0.8))
	if extra != "":
		var at := Vector2(left + marks_width + LIFE_TEXT_GAP, center.y + 3.0)
		_draw_layer.draw_string_outline(font, at, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, LIFE_TEXT_SIZE, 4, Color(0, 0, 0, 0.6))
		_draw_layer.draw_string(font, at, extra, HORIZONTAL_ALIGNMENT_LEFT, -1, LIFE_TEXT_SIZE, Color(CYAN, 0.9))


func _chevron(at: Vector2) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0, -8), at + Vector2(6, 2), at + Vector2(0, -2), at + Vector2(-6, 2)])


func _center_text(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	_draw_layer.draw_string_outline(font, at + Vector2(-90, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 180, font_size, 4, Color(0, 0, 0, 0.6))
	_draw_layer.draw_string(font, at + Vector2(-90, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 180, font_size, color)


func _arc_gauge(center: Vector2, radius: float, from_deg: float, to_deg: float, ratio: float, color: Color) -> void:
	var a0 := deg_to_rad(from_deg)
	var a1 := deg_to_rad(to_deg)
	_draw_layer.draw_arc(center, radius, a0, a1, 40, Color(color, 0.18), 13.0, true)
	if ratio > 0.0:
		_draw_layer.draw_arc(center, radius, a0, lerpf(a0, a1, clampf(ratio, 0.0, 1.0)), 40, color, 13.0, true)


## Which bracketed enemies are in plain view; one ray each, a few times a second.
func _check_sight() -> void:
	_in_sight.clear()
	var p: Player = Game.player
	if p == null or p.dead or Game.cinematic:
		return
	for e in _enemies:
		if is_instance_valid(e) and e.can_be_locked() and p.global_position.distance_squared_to(e.global_position) < TARGET_RANGE * TARGET_RANGE and not p.cam.is_position_behind(e.global_position) and p.has_line_of_sight(e):
			_in_sight[e.get_instance_id()] = true


func _targets(p: Player, c: Vector2) -> void:
	var cam := p.cam
	for e in _enemies:
		if not is_instance_valid(e) or not _in_sight.has(e.get_instance_id()) or not e.can_be_locked():
			continue
		var pos: Vector3 = e.global_position
		var dist := p.global_position.distance_to(pos)
		if dist > TARGET_RANGE or cam.is_position_behind(pos):
			continue
		var s := cam.unproject_position(pos)
		var bracket := clampf(1200.0 / dist, 14.0, 74.0)
		var locked: bool = e == p.lock_target
		var col := Color(1.0, 0.3, 0.2, 0.95) if locked else Color(1.0, 0.55, 0.3, 0.55)
		_corners(s, bracket, col, 2.0 if locked else 1.2)
		var bar := Vector2(bracket * 2.0, 3.0)
		_draw_layer.draw_rect(Rect2(s + Vector2(-bracket, bracket + 6.0), bar), Color(0, 0, 0, 0.5))
		_draw_layer.draw_rect(Rect2(s + Vector2(-bracket, bracket + 6.0), Vector2(bar.x * clampf(e.hp_ratio(), 0.0, 1.0), bar.y)), col)
		if locked:
			_center_text(ThemeDB.fallback_font, "LOCK %d" % int(dist), s + Vector2(0, -bracket - 8.0), 14, col)


func _corners(s: Vector2, r: float, col: Color, w: float) -> void:
	var l := r * 0.45
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := s + Vector2(sx, sy) * r
			_draw_layer.draw_line(corner, corner - Vector2(sx, 0) * l, col, w, true)
			_draw_layer.draw_line(corner, corner - Vector2(0, sy) * l, col, w, true)
