class_name Cutscene
extends Node3D
## Plays one story chapter in the game's own 3D, with radio dialogue over it.
## A plain per-frame state machine, so skipping or leaving can't strand a coroutine.

enum State { CARD, FADE_OUT, FADE_IN, TYPING, HOLD, ENDING, CREDITS, DONE }

const CARD_TIME := 3.4
const FADE_TIME := 0.4
const CHARS_PER_SECOND := 46.0
const HOLD_BASE := 1.3
const HOLD_PER_CHAR := 0.022
const HOLD_MAX := 4.0
const CREDITS_TIME := 7.0
const BAR_HEIGHT := 120.0
const BLIP_EVERY := 3
const WAVE_GAIN := 2.4
## Room a cutscene robot keeps from walls and from the robot beside it, and its braking run.
const THREAT_WALL_MARGIN := 1.8
const THREAT_GAP := 2.0
const THREAT_BRAKE := 6.0
## How much tunnel the robots fly down before the room, in cells.
const THREAT_TUNNEL_CELLS := 7
## Half-width of the lane kept free in front of the tunnel for the robots still coming.
const THREAT_LANE := 5.0
const FRAME_ASPECT := 16.0 / 9.0
const WAVE_RESPONSE := 16.0
## Pause after a spoken line, before the next one starts.
const VOICE_GAP := 0.35
const RING_MODEL_RADIUS := 70.0
## Inside the asteroid model's frame once turned: where its shaft meets the surface.
const MOUTH_Z := 167.0
const BLAST_SHIP_SPEED := 90.0
const INDOOR_AMBIENT := 0.55
## Long enough for the ship to arrive and the door to shut behind it.
const MINE_MIN_SHOT := 7.5

var chapter: Dictionary
var chapter_index := 0
var state := State.CARD
var shot_index := -1
var line_index := 0

var _t := 0.0
var _press := false
var _chars := 0.0
var _rate := CHARS_PER_SECOND
var _voiced := false
var _voice: AudioStreamPlayer
var _last_blip := 0
var _shot_t := 0.0
var _shot_length := 1.0
## The last line of a shot waits for this, so a scene can finish what it is showing.
var _shot_hold := 0.0
var _scope_phase := 0.0
var _wave_amount := 0.0

var _set: Node3D
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _cam_from := Vector3.ZERO
var _cam_to := Vector3.ONE
var _look_from := Vector3.ZERO
var _look_to := Vector3.ZERO
var _follow: Node3D
var _look_node: Node3D
var _movers: Array = []
var _glides: Array = []
## Robots marching along a route at a steady speed: [node, Curve3D, launch time, speed].
var _marches: Array = []
## The threat shot's final camera, used to keep every robot in frame.
var _frame_eye := Vector3.ZERO
var _lane_clear := false
var _frame_look := Vector3.FORWARD
var _open_cells: Dictionary = {}
var _cell_size := 10.0
var _door_upper: Node3D
var _door_lower: Node3D
var _door_close_at := 0.0
var _door_closing := false
var _look_offset := Vector3.ZERO
var _blasts := 0.0
var _blast_size := 0.0
var _blast_radius := 150.0
var _packed: Dictionary = {}

var _fade: ColorRect
var _card: VBoxContainer
var _title: Label
var _place: Label
var _status: Label
var _strip: Control
var _speaker: Label
var _line: Label
var _scope: Control
var _hint: Label
var _credits: VBoxContainer


func _ready() -> void:
	chapter_index = Game.story_chapter
	chapter = StoryData.CHAPTERS[chapter_index]
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"Voice"
	add_child(_voice)
	_build_world()
	_build_ui()
	Music.play_track("ascent" if chapter_index == StoryData.ENDING else "story")
	Sfx.play("comm_open", null, -6.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/space_sky.png")
	sky_mat.energy_multiplier = 1.4
	sky.sky_material = sky_mat
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.56, 0.7)
	_env.ambient_light_energy = 0.28
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_white = 6.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.05
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-24, 40, 0)
	_sun.light_color = Color(1.0, 0.93, 0.84)
	_sun.light_energy = 2.2
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 52.0
	_cam.far = 9000.0
	_cam.near = 0.1
	add_child(_cam)
	_cam.make_current()
	_set = Node3D.new()
	add_child(_set)


func _text(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = BAR_HEIGHT * 0.6
		else:
			bar.offset_top = -BAR_HEIGHT * 1.35
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := HBoxContainer.new()
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -BAR_HEIGHT * 1.2
	box.offset_bottom = -14.0
	box.offset_left = 150.0
	box.offset_right = -150.0
	box.add_theme_constant_override("separation", 24)
	_scope = Control.new()
	_scope.custom_minimum_size = Vector2(120, 80)
	_scope.draw.connect(_paint_scope)
	box.add_child(_scope)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(words)
	_speaker = _text(words, 18, MenuStyle.ACCENT)
	_line = _text(words, 25, MenuStyle.TEXT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _text(root, 14, Color(0.6, 0.65, 0.72))
	_hint.text = "Space: next    Esc: skip"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hint.position = Vector2(_hint.position.x - 190.0, 20.0)

	_card = VBoxContainer.new()
	root.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.add_theme_constant_override("separation", 12)
	var number := _text(_card, 20, Color(0.7, 0.76, 0.84))
	number.text = "EPILOGUE" if chapter_index == StoryData.ENDING else "CHAPTER %d" % (chapter_index + 1)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = _text(_card, 62, MenuStyle.ACCENT)
	_title.text = str(chapter["title"]).to_upper()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place = _text(_card, 24, MenuStyle.TEXT)
	_place.text = chapter["place"]
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = _text(_card, 22, Color(1.0, 0.45, 0.32))
	_status.text = chapter["status"]
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip = Control.new()
	_strip.custom_minimum_size = Vector2(520, 40)
	_strip.draw.connect(_paint_strip)
	_card.add_child(_strip)

	_credits = VBoxContainer.new()
	root.add_child(_credits)
	_credits.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_credits.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_credits.grow_vertical = Control.GROW_DIRECTION_BOTH
	_credits.add_theme_constant_override("separation", 12)
	_credits.visible = false
	for row: Array in [["ASCENT", 66, MenuStyle.ACCENT], ["Thank you for flying.", 26, MenuStyle.TEXT], ["Every ship, level, sound and song was generated from code.", 19, Color(0.7, 0.76, 0.84)]]:
		var credit := _text(_credits, row[1], row[2])
		credit.text = row[0]
		credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Where this chapter sits in the campaign: one tick per level.
func _paint_strip() -> void:
	var count := StoryData.ENDING
	var width := _strip.size.x
	var y := _strip.size.y * 0.5
	var step := width / float(count - 1)
	_strip.draw_line(Vector2(0, y), Vector2(width, y), Color(0.4, 0.46, 0.55, 0.6), 2.0, true)
	for i in count:
		var at := Vector2(i * step, y)
		var reached := i <= chapter_index
		_strip.draw_circle(at, 9.0 if i == chapter_index else 5.0, MenuStyle.ACCENT if reached else Color(0.3, 0.34, 0.4))


## Silent lines have no audio to follow, so they get a plain talking wobble.
func _update_wave(delta: float) -> void:
	var wanted := 0.0
	if _voiced and _voice.playing:
		var bus := AudioServer.get_bus_index(&"Voice")
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))
		wanted = clampf(db_to_linear(peak) * WAVE_GAIN, 0.0, 1.0)
	elif not _voiced and state == State.TYPING:
		wanted = 0.7
	_wave_amount = lerpf(_wave_amount, wanted, 1.0 - exp(-WAVE_RESPONSE * delta))


## Only there while someone is speaking; the wave follows the real voice.
func _paint_scope() -> void:
	if _speaker.text.is_empty():
		return
	var size := _scope.size
	var color: Color = StoryData.SPEAKER_COLORS.get(_speaker.text, MenuStyle.ACCENT)
	_scope.draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.08))
	_scope.draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.5), false, 1.4)
	var points := PackedVector2Array()
	for i in 41:
		var x := size.x * float(i) / 40.0
		var wave := sin(float(i) * 0.7 + _scope_phase) * sin(float(i) * 0.13 + _scope_phase * 0.31)
		points.append(Vector2(x, size.y * 0.5 + wave * size.y * (0.04 + 0.42 * _wave_amount)))
	_scope.draw_polyline(points, color, 1.8, true)


# --- Flow --------------------------------------------------------------------------
func advance() -> void:
	_press = true


func skip() -> void:
	if state == State.CREDITS:
		state = State.DONE
		Game.story_finished()
	elif state != State.DONE and state != State.ENDING:
		_begin_ending()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		skip()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		advance()
		get_viewport().set_input_as_handled()


func _begin_ending() -> void:
	_voice.stop()
	state = State.ENDING
	_t = 0.0
	Sfx.play("comm_close", null, -6.0)


func _process(delta: float) -> void:
	_scope_phase += delta * 11.0
	_update_wave(delta)
	_animate(delta)
	_scope.queue_redraw()
	var pressed := _press
	_press = false
	_t += delta
	match state:
		State.CARD:
			_fade.modulate.a = 1.0
			if _t >= CARD_TIME or pressed:
				_card.visible = false
				_goto_shot(0)
		State.FADE_OUT:
			_fade.modulate.a = clampf(_t / FADE_TIME, 0.0, 1.0)
			if _t >= FADE_TIME:
				_build_shot()
				state = State.FADE_IN
				_t = 0.0
		State.FADE_IN:
			_fade.modulate.a = 1.0 - clampf(_t / FADE_TIME, 0.0, 1.0)
			if _t >= FADE_TIME:
				_start_line(0)
		State.TYPING:
			_chars += delta * _rate
			var shown := mini(int(_chars), _line.text.length())
			_line.visible_characters = shown
			if not _voiced and shown - _last_blip >= BLIP_EVERY:
				_last_blip = shown
				Sfx.play("comm_blip", null, -20.0, randf_range(0.92, 1.08))
			if pressed and _voiced:
				_voice.stop()
				_next_line()
			elif pressed or shown >= _line.text.length():
				_line.visible_characters = -1
				state = State.HOLD
				_t = 0.0
		State.HOLD:
			if pressed or (_t >= (VOICE_GAP if _voiced else _hold_time(_line.text)) and _scene_finished()):
				_voice.stop()
				_next_line()
		State.ENDING:
			_fade.modulate.a = clampf(_t / FADE_TIME, 0.0, 1.0)
			if _t >= FADE_TIME:
				_after_shots()
		State.CREDITS:
			if pressed or _t >= CREDITS_TIME:
				state = State.DONE
				Game.story_finished()


## A scene may need longer than its dialogue, but only the last line waits for it.
func _scene_finished() -> bool:
	var lines: Array = chapter["shots"][shot_index]["lines"]
	return line_index + 1 < lines.size() or _shot_t >= _shot_hold


func _hold_time(text: String) -> float:
	return minf(HOLD_MAX, HOLD_BASE + text.length() * HOLD_PER_CHAR)


func _goto_shot(index: int) -> void:
	shot_index = index
	state = State.FADE_OUT
	_t = 0.0
	_speaker.text = ""
	_line.text = ""
	if index > 0:
		Sfx.play("comm_blip", null, -12.0, 0.5)
	else:
		_fade.modulate.a = 1.0
		_t = FADE_TIME


func _start_line(index: int) -> void:
	line_index = index
	var line: Array = chapter["shots"][shot_index]["lines"][index]
	_speaker.text = line[0]
	_speaker.add_theme_color_override("font_color", StoryData.SPEAKER_COLORS.get(line[0], MenuStyle.ACCENT))
	_line.text = line[1]
	_line.visible_characters = 0
	var spoken := voice_stream(chapter_index, shot_index, index)
	_voiced = spoken != null
	_line.visible = Settings.story_subtitles or not _voiced
	_rate = CHARS_PER_SECOND
	if _voiced:
		_rate = str(line[1]).length() / maxf(spoken.get_length(), 0.1)
		_voice.stream = spoken
		_voice.play()
	_chars = 0.0
	_last_blip = 0
	state = State.TYPING
	_t = 0.0


static func voice_stream(chapter_at: int, shot_at: int, line_at: int) -> AudioStream:
	var path := "res://assets/voice/%02d_%d_%d.ogg" % [chapter_at, shot_at, line_at]
	return load(path) if ResourceLoader.exists(path) else null


func _next_line() -> void:
	var lines: Array = chapter["shots"][shot_index]["lines"]
	if line_index + 1 < lines.size():
		_start_line(line_index + 1)
	elif shot_index + 1 < chapter["shots"].size():
		_goto_shot(shot_index + 1)
	else:
		_begin_ending()


func _after_shots() -> void:
	_speaker.text = ""
	_line.text = ""
	Sfx.play("comm_close", null, -6.0)
	if chapter_index == StoryData.ENDING:
		state = State.CREDITS
		_t = 0.0
		_credits.visible = true
		_clear_set()
	else:
		state = State.DONE
		Game.story_finished()


# --- Staging -----------------------------------------------------------------------
func _clear_set() -> void:
	for child in _set.get_children():
		child.queue_free()
	_movers.clear()
	_glides.clear()
	_marches.clear()
	_follow = null
	_look_node = null
	_blasts = 0.0
	_door_upper = null
	_door_lower = null
	_look_offset = Vector3.ZERO
	_open_cells.clear()


## shot_at is the shot's index (its voice files are numbered by it); find() is only a
## fallback, since two identical shots would both resolve to the first.
func _shot_duration(shot: Dictionary, shot_at := -1) -> float:
	var total := FADE_TIME
	if shot_at < 0:
		shot_at = chapter["shots"].find(shot)
	for i in shot["lines"].size():
		var spoken := voice_stream(chapter_index, shot_at, i)
		if spoken != null:
			total += spoken.get_length() + VOICE_GAP
		else:
			var text := str(shot["lines"][i][1])
			total += text.length() / CHARS_PER_SECOND + _hold_time(text)
	return total


func _build_shot() -> void:
	_clear_set()
	var shot: Dictionary = chapter["shots"][shot_index]
	_shot_length = _shot_duration(shot, shot_index)
	_shot_hold = 0.0
	_shot_t = 0.0
	_env.background_mode = Environment.BG_SKY
	_sun.visible = true
	_sun.light_color = Color(1.0, 0.93, 0.84)
	_sun.light_energy = 2.2
	_env.ambient_light_energy = 0.28
	_env.glow_intensity = 0.7
	call("_stage_" + str(shot["stage"]), shot)


func _model(file: String, at: Vector3, model_scale := 1.0) -> Node3D:
	if not _packed.has(file):
		_packed[file] = load("res://assets/models/%s.glb" % file)
	var node: Node3D = _packed[file].instantiate()
	Mats.apply(node)
	if file == "wren9":
		ShipLoadout.attach(node)  # every cutscene ship flies the stock guns and missiles
	_set.add_child(node)
	node.position = at
	node.scale = Vector3.ONE * model_scale
	return node


func _light(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	_set.add_child(l)


func _move(node: Node3D, velocity: Vector3, spin := Vector3.ZERO) -> void:
	_movers.append([node, velocity, spin])


## Carries a node between two points over part of the shot.
func _glide(node: Node3D, from: Vector3, to: Vector3, start: float, end: float, eased := true) -> void:
	node.position = from
	_glides.append([node, from, to, start, end, eased])


func _camera(from: Vector3, to: Vector3, look_from: Vector3, look_to: Vector3) -> void:
	_cam_from = from
	_cam_to = to
	_look_from = look_from
	_look_to = look_to


## Inside the mine: no sky or sun, only what is lit in there.
func _indoors() -> void:
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.006, 0.008, 0.012)
	_env.ambient_light_energy = INDOOR_AMBIENT
	_sun.visible = false


func _face(node: Node3D, target: Vector3) -> void:
	node.look_at(target, Vector3.UP)


## Harbor Ring. A slow spin unless it is holding still for the ship to dock.
func _ring(at: Vector3, radius: float, spinning := true) -> Node3D:
	var root := _model("harbor_ring", at, radius / RING_MODEL_RADIUS)
	root.rotation = Vector3(0.45, 0.0, 0.2) if spinning else Vector3.ZERO
	if spinning:
		_move(root, Vector3.ZERO, Vector3(0.0, 0.08, 0.0))
	return root


func _mesh_in(parent: Node3D, mesh: Mesh, at: Vector3, angles: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	mi.position = at
	mi.rotation = angles
	return mi


func _thrusters(rock: Node3D) -> void:
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire.albedo_color = Color(0.9, 1.6, 3.2, 0.7)
	for offset: Vector3 in [Vector3(-90, 40, 170), Vector3(80, -30, 175), Vector3(0, 90, 165)]:
		var cone := CylinderMesh.new()
		cone.top_radius = 34.0
		cone.bottom_radius = 2.0
		cone.height = 420.0
		cone.material = fire
		_mesh_in(rock, cone, offset + Vector3(0, 0, 210), Vector3(PI * 0.5, 0, 0))


## This chapter's asteroid: each level has its own shape. after_level picks the one just
## escaped from, for the blast that opens the next chapter.
func _asteroid_file(after_level := false) -> String:
	var path := EscapeRun.asteroid_model(EscapeRun.level_id(chapter_index - (1 if after_level else 0)))
	return path.get_file().get_basename()


## Asteroid turned so its mine shaft opens towards +Z.
func _asteroid_mouth_forward(after_level := false) -> Node3D:
	var rock := _model(_asteroid_file(after_level), Vector3.ZERO)
	rock.rotation.y = PI
	return rock


func _ship_with_lamp(at: Vector3) -> Node3D:
	var ship := _model("wren9", at)
	var lamp := SpotLight3D.new()
	lamp.spot_range = 90.0
	lamp.spot_angle = 40.0
	lamp.light_energy = 6.0
	lamp.position = Vector3(0, 0.3, -4.0)
	ship.add_child(lamp)
	return ship


## Loads a real level to stage a scene in. Doors stay shut, so only frames show.
func _level_set(index: int) -> Dictionary:
	var info: Dictionary = Game.levels[index]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(info["data"]))
	var mesh: Node3D = load(info["model"]).instantiate()
	Mats.apply(mesh)
	_set.add_child(mesh)
	WallParts.populate(mesh, data)
	_cell_size = data["cell_size"]
	for c in data["cells"]:
		_open_cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	_indoors()
	return data


func _level_index(shot: Dictionary) -> int:
	return int(shot.get("level", mini(chapter_index, Game.levels.size() - 1)))


func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _level_lights(data: Dictionary, center: Vector3, reach: float) -> void:
	for l: Dictionary in data["lights"]:
		var at := _v3(l["pos"])
		if at.distance_to(center) < reach:
			_light(at, Color(l["color"][0], l["color"][1], l["color"][2]), l["energy"], l["range"])


func _is_open(p: Vector3) -> bool:
	return _open_cells.has(Vector3i((p / _cell_size).round()))


## The furthest point towards an offset that is still inside the mine.
func _open_point(center: Vector3, offset: Vector3) -> Vector3:
	for share: float in [1.0, 0.85, 0.7, 0.55, 0.4, 0.25]:
		var p := center + offset * share
		if _is_open(p):
			return p
	return center + Vector3(0, 2, 0)


func _stage_ring(_shot: Dictionary) -> void:
	_ring(Vector3.ZERO, 70.0)
	_model(_asteroid_file(), Vector3(-520, -90, -1100))
	_camera(Vector3(150, 46, 210), Vector3(112, 34, 158), Vector3.ZERO, Vector3(0, 6, 0))


## Flies at the shaft and disappears down it. The camera waits outside the mouth.
func _stage_approach(_shot: Dictionary) -> void:
	_asteroid_mouth_forward()
	var ship := _ship_with_lamp(Vector3.ZERO)
	_glide(ship, Vector3(0, 0, MOUTH_Z + 260.0), Vector3(0, 0, MOUTH_Z - 46.0), 0.0, _shot_length, false)
	_look_node = ship
	_light(Vector3(0, 0, MOUTH_Z + 30.0), Color(1.0, 0.8, 0.55), 10.0, 120.0)
	# Behind the ship and looking at the asteroid, so the shaft is in view throughout.
	_camera(Vector3(34, 20, MOUTH_Z + 330.0), Vector3(22, 14, MOUTH_Z + 120.0), Vector3.ZERO, Vector3.ZERO)


func _stage_drive(_shot: Dictionary) -> void:
	var rock := _model(_asteroid_file(), Vector3.ZERO)
	_thrusters(rock)
	_ring(Vector3(-40, 60, -2100), 90.0)
	_light(Vector3(0, 0, 520), Color(0.5, 0.75, 1.0), 22.0, 900.0)
	_camera(Vector3(560, 130, 420), Vector3(470, 110, 300), Vector3(0, 0, 80), Vector3(0, 0, 0))


## The robots come out of the tunnel into the spawn room, towards the camera:
## single file round the bend and down the tunnel, then each to its own clear spot.
func _stage_threat(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var start := _v3(data["start"])
	_level_lights(data, start, 90.0)
	var eye := start + Vector3(4, 2, 11)
	var route := _tunnel_route()
	_frame_eye = eye + Vector3(-1.5, -0.5, 2.5)
	_frame_look = Vector3(0, 10, 2)
	var kinds: Array = shot.get("actors", [])
	var targets: Array[Vector3] = []
	var radii: Array[float] = []
	for i in kinds.size():
		var r := _actor_radius(kinds[i])
		radii.append(r)
		# Anyone with robots still to come out keeps off the line out of the tunnel.
		_lane_clear = i + 1 < kinds.size()
		targets.append(_threat_spot(i, kinds.size(), r, targets, radii))
	# One speed for all, launched a body-length apart, so nobody overtakes in the tunnel.
	var gaps: Array[float] = [0.0]
	for i in range(1, kinds.size()):
		# Plus a braking run, so the one behind cannot close up while the leader slows down.
		gaps.append(gaps[i - 1] + radii[i] + radii[i - 1] + THREAT_GAP + THREAT_BRAKE)
	var curves: Array[Curve3D] = []
	var need := 0.0
	for i in kinds.size():
		var curve := _route_curve(route, targets[i])
		curves.append(curve)
		need = maxf(need, gaps[i] + curve.get_baked_length() + THREAT_BRAKE)
	var speed := need / maxf(_shot_length * 0.85, 0.1)
	for i in kinds.size():
		var robot := _model(kinds[i], curves[i].sample_baked(0.0))
		_face(robot, eye)
		robot.visible = false
		_marches.append([robot, curves[i], gaps[i] / speed, speed])
	_light(eye + Vector3(0, 2, -4), Color(0.86, 0.9, 1.0), 14.0, 70.0)
	_light(Vector3(0, 12, -2), Color(1.0, 0.55, 0.4), 8.0, 40.0)
	_camera(eye, eye + Vector3(-1.5, -0.5, 2.5), Vector3(0, 10, 4), Vector3(0, 10, 2))


func _actor_radius(kind: String) -> float:
	return float(Robot.TYPES[kind].get("radius", 2.5)) if Robot.TYPES.has(kind) else 2.5


## The straight run of tunnel behind the room's way out (0, 1, 0), nearest cells only,
## ending half a cell into the room so nobody turns until clear of the mouth.
func _tunnel_route() -> Array[Vector3]:
	var cell := Vector3i(0, 1, 0)
	var route: Array[Vector3] = [Vector3(cell) * _cell_size + Vector3(0, 0, _cell_size * 0.5)]
	route.push_front(Vector3(cell) * _cell_size)
	while route.size() < THREAT_TUNNEL_CELLS and _open_cells.has(cell + Vector3i(0, 0, -1)):
		cell += Vector3i(0, 0, -1)
		route.push_front(Vector3(cell) * _cell_size)
	return route


func _route_curve(route: Array[Vector3], target: Vector3) -> Curve3D:
	var points: Array[Vector3] = route.duplicate()
	points.append(target)
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	for i in points.size():
		var before := points[maxi(i - 1, 0)]
		var after := points[mini(i + 1, points.size() - 1)]
		var handle := (after - before) * 0.18
		curve.add_point(points[i], -handle, handle)
	return curve


## A spot in the room that the whole robot fits in, clear of the ones already placed.
func _threat_spot(i: int, count: int, radius: float, placed: Array[Vector3], radii: Array[float]) -> Vector3:
	var base := Vector3((float(i) - float(count - 1) * 0.5) * 8.0, 10.0 + 3.0 * float(i % 2), 15.0 - 2.5 * float(i))
	# Low rooms can't give a big robot the full margin; it then gets as much as fits.
	for margin: float in [THREAT_WALL_MARGIN, 1.0, 0.5]:
		var spot := _threat_spot_with(base, margin, radius, placed, radii)
		if spot != Vector3.INF:
			return spot
	return Vector3(0, 10, base.z)


func _threat_spot_with(base: Vector3, margin: float, radius: float, placed: Array[Vector3], radii: Array[float]) -> Vector3:
	var best := Vector3.INF
	var best_score := INF
	for xi in range(-8, 9):
		for yi in range(-2, 4):
			for zi in range(0, 6):
				var p := Vector3(xi * 2.0, 10.0 + yi * 2.5, 7.0 + zi * 2.5)
				var score := p.distance_squared_to(base)
				if score < best_score and _fits(p, radius, margin) and _clear_of(p, radius, placed, radii) and _in_frame(p, radius) and _off_lane(p, radius):
					best = p
					best_score = score
	return best


func _off_lane(p: Vector3, radius: float) -> bool:
	return not _lane_clear or Vector2(p.x, p.y - 10.0).length() >= radius + THREAT_LANE


## Whether a whole robot shows in the shot's last frame, with a little room to spare.
func _in_frame(p: Vector3, radius: float) -> bool:
	var view := Basis.looking_at(_frame_look - _frame_eye, Vector3.UP)
	var local := view.inverse() * (p - _frame_eye)
	var depth := -local.z
	if depth <= radius:
		return false
	var half_v := deg_to_rad(_cam.fov) * 0.5
	var half_h := atan(tan(half_v) * FRAME_ASPECT)
	var spread := asin(clampf(radius / p.distance_to(_frame_eye), 0.0, 1.0))
	return absf(atan2(local.x, depth)) + spread < half_h * 0.82 and absf(atan2(local.y, depth)) + spread < half_v * 0.82


func _fits(p: Vector3, radius: float, margin := THREAT_WALL_MARGIN) -> bool:
	var m := radius + margin
	for x: float in [-m, 0.0, m]:
		for y: float in [-m, 0.0, m]:
			for z: float in [-m, 0.0, m]:
				if not _is_open(p + Vector3(x, y, z)):
					return false
	return true


func _clear_of(p: Vector3, radius: float, placed: Array[Vector3], radii: Array[float]) -> bool:
	for j in placed.size():
		if p.distance_to(placed[j]) < radius + radii[j] + THREAT_GAP:
			return false
	return true


func _stage_reactor(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var at := _v3(data["reactor"])
	_level_lights(data, at, 80.0)
	var reactor := _model("reactor", at, float(data["reactor_scale"]))
	for i in 3:
		var ring: Node3D = reactor.find_child("Ring%d" % i, true, false)
		if ring != null:
			_move(ring, Vector3.ZERO, Vector3(0.0, 0.8 + i * 0.7, 0.0))
	var eye_a := _open_point(at, Vector3(-52, 12, 52))
	var eye_b := _open_point(at, Vector3(-34, 16, 58))
	# The core is far brighter than the room; softer bloom and a fill light show the machine.
	_env.glow_intensity = 0.25
	_light(eye_a + Vector3(0, 6, 0), Color(0.86, 0.9, 1.0), 24.0, 130.0)
	_light(at + Vector3(20, 22, -10), Color(0.6, 0.85, 1.0), 16.0, 90.0)
	_camera(eye_a, eye_b, at, at + Vector3(0, 3, 0))


func _stage_overseer(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var at := _v3(data["start"]) + Vector3(0, 0, -60)
	for r: Dictionary in data["robots"]:
		if r["type"] == "overseer":
			at = _v3(r["pos"])
	_level_lights(data, at, 90.0)
	_model("overseer", at, 1.0)
	var eye_a := _open_point(at, Vector3(-18, 2, 40))
	var eye_b := _open_point(at, Vector3(-6, 4, 26))
	_light(at + Vector3(0, -10, 16), Color(1.0, 0.3, 0.16), 26.0, 70.0)
	_light(eye_a + Vector3(6, 8, 0), Color(0.86, 0.9, 1.0), 40.0, 120.0)
	_light(at + Vector3(-16, 14, 8), Color(0.7, 0.8, 1.0), 22.0, 70.0)
	_camera(eye_a, eye_b, at + Vector3(0, 2, 0), at + Vector3(0, 5, 0))


## The Overseer speaks through a wall turret, watching the camera.
func _stage_overseer_voice(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var turret: Dictionary = data["turrets"][0]
	var at := _v3(turret["pos"])
	var normal := _v3(turret["normal"])
	_level_lights(data, at, 60.0)
	var sentry := _model("sentry", at, 1.6)
	sentry.look_at(at + normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.BACK)
	var side := normal.cross(Vector3.UP).normalized()
	var eye := at + normal * 9.0 + side * 3.0 + Vector3(0, 1.2, 0)
	_light(eye + Vector3(0, 3, 0), Color(0.86, 0.9, 1.0), 7.0, 34.0)
	_light(at + normal * 5.0, Color(1.0, 0.22, 0.12), 6.0, 20.0)
	_camera(eye, eye - normal * 2.5 - side * 1.5, at + normal, at + normal)


## Survivors waiting in a room of the level they were found in.
func _stage_survivors(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var at := _v3(data["astronauts"][0])
	_level_lights(data, at, 70.0)
	var away := Vector3.BACK
	for option: Vector3 in [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]:
		if _is_open(at + option * _cell_size):
			away = option
			break
	var eye := at + away * 11.0 + Vector3(0, 1.5, 0)
	var across := away.cross(Vector3.UP).normalized()
	for i in 3:
		var person := _model("astronaut", at + across * (float(i) - 1.0) * 3.4 + Vector3(0, sin(float(i) * 2.0) * 0.9, -float(i % 2)), 1.3)
		_face(person, eye + Vector3(0, -0.5, 0))
		_move(person, Vector3(0.0, 0.05 if i % 2 == 0 else -0.05, 0.0))
	_light(eye + Vector3(0, 4, 0), Color(1.0, 0.92, 0.8), 8.0, 34.0)
	_camera(eye, eye - away * 2.0 + across * 1.2, at, at + Vector3(0, 0.5, 0))


## The ship arrives through the room's entry door and stops where the level begins.
func _stage_mine(shot: Dictionary) -> void:
	var data := _level_set(_level_index(shot))
	var start := _v3(data["start"])
	var entry: Dictionary = data["doors"].filter(func(d: Dictionary) -> bool: return d["lock"] == "entry")[0]
	var door_at := Vector3(entry["cell"][0], entry["cell"][1], entry["cell"][2]) * _cell_size
	_level_lights(data, start, door_at.distance_to(start) + 50.0)
	_shot_length = maxf(_shot_length, MINE_MIN_SHOT)
	_shot_hold = _shot_length
	var door := _model("door", door_at)
	_door_upper = door.find_child("Upper", true, false)
	_door_lower = door.find_child("Lower", true, false)
	_door_close_at = _shot_length * 0.68
	_door_closing = false
	Sfx.play("door", null, -4.0)
	var ship := _ship_with_lamp(Vector3.ZERO)
	_glide(ship, door_at + Vector3(0, 0, 34), start, 0.0, _shot_length * 0.66)
	_look_node = ship
	# Aimed a little above the ship, so it stays clear of the bottom bar as it stops.
	_look_offset = Vector3(0, 1.2, 0)
	_light(start + Vector3(-5, 7, -14), Color(0.86, 0.9, 1.0), 7.0, 44.0)
	_camera(start + Vector3(-8, 2.5, -21), start + Vector3(-5, 1.5, -17), Vector3.ZERO, Vector3.ZERO)


## Leaves the shaft nose-first, with the asteroid going up behind the ship.
func _stage_blast(shot: Dictionary) -> void:
	_asteroid_mouth_forward(true)
	var from := Vector3(0, 0, MOUTH_Z - 10.0)
	var to := from + Vector3(30, 26, _shot_length * BLAST_SHIP_SPEED)
	var ship := _model("wren9", from)
	ship.look_at_from_position(from, to, Vector3.UP)
	_glide(ship, from, to, 0.0, _shot_length, false)
	_blasts = 0.05
	_blast_size = 9.0 if shot.get("small", false) else 24.0
	# Just above the rock, so the bursts break the surface instead of hiding inside it.
	_blast_radius = 192.0
	_look_node = ship
	_light(Vector3.ZERO, Color(1.0, 0.45, 0.2), 30.0, 900.0)
	# Waits ahead of the ship, which flies out of the shaft towards it and stops close by.
	var eye := to + Vector3(9, 3.5, 16)
	_camera(eye, eye + Vector3(-1.5, -0.5, 1.0), Vector3.ZERO, Vector3.ZERO)


## Comes home and settles in front of the docking bay, clear of the station.
func _stage_home(_shot: Dictionary) -> void:
	_ring(Vector3.ZERO, 70.0, false)
	var bay_z := 70.0 + 26.0
	var ship := _model("wren9", Vector3.ZERO)
	_glide(ship, Vector3(10, 5, bay_z + 280.0), Vector3(0, 0, bay_z + 16.0), 0.0, _shot_length * 0.9)
	# Rides behind the ship looking at the bay, so the station fills more of the view as it nears.
	_follow = ship
	_sun.light_color = Color(1.0, 0.82, 0.6)
	_sun.light_energy = 3.0
	_light(Vector3(0, 6, bay_z + 18.0), Color(0.9, 0.95, 1.0), 12.0, 60.0)
	_camera(Vector3(-9, 4, 24), Vector3(-6, 2.5, 17), Vector3(0, 0, bay_z), Vector3(0, 0, bay_z))


func _stage_fragment(_shot: Dictionary) -> void:
	var rock := _model(_asteroid_file(), Vector3.ZERO, 0.12)
	_move(rock, Vector3.ZERO, Vector3(0.01, 0.03, 0.008))
	_light(Vector3(0, 30, 60), Color(0.85, 0.75, 1.0), 20.0, 180.0)
	var core := SphereMesh.new()
	core.radius = 1.4
	core.height = 2.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(4.0, 0.6, 0.5)
	core.material = mat
	_mesh_in(rock, core, Vector3(0, 0, 186), Vector3.ZERO)
	_camera(Vector3(0, 4, 90), Vector3(0, 2, 52), Vector3.ZERO, Vector3(0, 0, 8))


func _animate(delta: float) -> void:
	if shot_index < 0 or state == State.CARD or state == State.CREDITS:
		return
	_shot_t += delta
	for mover: Array in _movers:
		var node: Node3D = mover[0]
		if is_instance_valid(node):
			node.position += mover[1] * delta
			node.rotation += mover[2] * delta
	for glide: Array in _glides:
		var node: Node3D = glide[0]
		if is_instance_valid(node):
			var along := clampf(inverse_lerp(glide[3], glide[4], _shot_t), 0.0, 1.0)
			node.position = (glide[1] as Vector3).lerp(glide[2], smoothstep(0.0, 1.0, along) if glide[5] else along)
	_update_marches()
	_animate_door()
	var k := smoothstep(0.0, 1.0, clampf(_shot_t / maxf(_shot_length, 0.1), 0.0, 1.0))
	var base := _follow.global_position if is_instance_valid(_follow) else Vector3.ZERO
	var eye: Vector3 = base + _cam_from.lerp(_cam_to, k)
	var target: Vector3 = _look_node.global_position + _look_offset if is_instance_valid(_look_node) else _look_from.lerp(_look_to, k)
	_cam.global_position = eye
	if eye.distance_to(target) > 0.5:
		_cam.look_at(target, Vector3.UP)
	if _blasts > 0.0:
		_blasts -= delta
		if _blasts <= 0.0:
			_blasts = randf_range(0.14, 0.4)
			_explode_on_rock()


## The entry door opens as the shot begins and shuts behind the ship.
## Cruise along the route, then brake over the last few metres onto the spot.
func _update_marches() -> void:
	for march: Array in _marches:
		var node: Node3D = march[0]
		if not is_instance_valid(node):
			continue
		var curve: Curve3D = march[1]
		var elapsed: float = _shot_t - float(march[2])
		node.visible = elapsed >= 0.0
		if elapsed < 0.0:
			continue
		var speed: float = march[3]
		var length := curve.get_baked_length()
		var cruise := maxf(length - THREAT_BRAKE, 0.0)
		var s := speed * elapsed
		if s > cruise:
			var u := elapsed - cruise / speed
			s = minf(cruise + speed * u - speed * speed * u * u / (4.0 * THREAT_BRAKE), length)
			if u >= 2.0 * THREAT_BRAKE / speed:
				s = length
		node.position = curve.sample_baked(s, true)
		# They come out watching the camera, as if they know it is there.
		if node.position.distance_to(_cam.global_position) > 1.0:
			node.look_at(_cam.global_position, Vector3.UP)


func _animate_door() -> void:
	if not is_instance_valid(_door_upper) or not is_instance_valid(_door_lower):
		return
	var opened := clampf(_shot_t / Door.OPEN_TIME, 0.0, 1.0)
	var closed := clampf((_shot_t - _door_close_at) / Door.OPEN_TIME, 0.0, 1.0)
	if closed > 0.0 and not _door_closing:
		_door_closing = true
		Sfx.play("door", null, -2.0)
	var amount: float = smoothstep(0.0, 1.0, opened) * (1.0 - smoothstep(0.0, 1.0, closed))
	_door_upper.position.y = Door.TRAVEL * amount
	_door_lower.position.y = -Door.TRAVEL * amount


## Fx draws into Game.level, which is the current set for just this one call.
func _explode_on_rock() -> void:
	Game.level = _set
	var at := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.2, 1)).normalized() * _blast_radius
	Fx.explosion(at, _blast_size, false)
	Game.level = null
