extends Node3D
## Home screen: the WREN-9 on its pad. Drag to orbit, scroll to zoom; it turns
## by itself until touched, and again after a few idle seconds.

## Share of the view the ship sits right of centre, leaving the left to the menu.
const SHIP_SCREEN_OFFSET := 0.2
## Further right in the gallery, clear of its wider panels.
const SHOWCASE_SCREEN_OFFSET := 0.25
const DEFAULT_DISTANCE := 21.5
const MIN_DISTANCE := 7.5
const MAX_DISTANCE := 32.0
const DEFAULT_YAW := 2.45
const DEFAULT_PITCH := 0.25
const MIN_PITCH := -1.35
const MAX_PITCH := 1.35
const AUTO_SPIN := 0.28
const AUTO_SPIN_DELAY := 3.5
const DRAG_SPEED := 0.0075
const ZOOM_STEP := 0.9
const SMOOTHING := 12.0
## Below this pitch the camera would be under the pad, so the pad gets out of the way.
const PAD_HIDE_PITCH := -0.04
## Gallery models are scaled so their longest side is this many metres.
const SHOWCASE_SIZE := 7.5
const SHOWCASE_FLOOR := -1.4

var yaw := DEFAULT_YAW
var pitch := DEFAULT_PITCH
var distance := DEFAULT_DISTANCE
var dragging := false

var _shown_yaw := DEFAULT_YAW
var _shown_pitch := DEFAULT_PITCH
var _shown_distance := DEFAULT_DISTANCE
var _idle := AUTO_SPIN_DELAY
var _showcase_rest_y := 0.0
var _time := 0.0
var _ship: Node3D
var _cam: Camera3D
var _pad: Array[Node3D] = []
var _showcase: Node3D
var inspecting := false
var _shown_offset := SHIP_SCREEN_OFFSET


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.012, 0.016, 0.024)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.58, 0.75)
	e.ambient_light_energy = 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = Settings.uses_ssao()
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)

	_ship = load("res://assets/models/wren9.glb").instantiate()
	Mats.apply(_ship)
	add_child(_ship)
	ShipLoadout.attach(_ship)

	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 6.2
	floor_mesh.bottom_radius = 6.5
	floor_mesh.height = 0.5
	floor_mesh.radial_segments = 64
	var pad := MeshInstance3D.new()
	pad.mesh = floor_mesh
	pad.position.y = -2.2
	var pad_mat := Mats.get_material("floor_metal").duplicate() as StandardMaterial3D
	pad_mat.uv1_scale = Vector3(5, 5, 5)
	pad.material_override = pad_mat
	add_child(pad)
	var ring := TorusMesh.new()
	ring.inner_radius = 5.85
	ring.outer_radius = 5.96
	var glow := MeshInstance3D.new()
	glow.mesh = ring
	glow.position.y = -1.92
	glow.material_override = Mats.get_material("glow_cyan")
	add_child(glow)
	_pad = [pad, glow]

	_add_light(self, Vector3(5, 7, 7), Color(1.0, 0.94, 0.85), 34.0, Settings.uses_shadows())
	_add_light(self, Vector3(-8, 3, -3), Color(0.35, 0.6, 1.0), 26.0, false)
	_add_light(self, Vector3(2, -1.5, -9), Color(1.0, 0.4, 0.15), 14.0, false)

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.1
	add_child(_cam)
	_cam.make_current()
	# Rides with the camera so whichever side you inspect stays lit.
	_add_light(_cam, Vector3(0, 2, 0), Color(0.95, 0.97, 1.0), 9.0, false)
	var menu := MainMenu.new()
	menu.showcase_changed.connect(show_entry)
	menu.inspect_changed.connect(func(on: bool): inspecting = on)
	add_child(menu)
	Sfx.loop("ambience", -18.0)
	Music.play_track("menu")


func _add_light(parent: Node3D, at: Vector3, col: Color, energy: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 34.0
	l.shadow_enabled = shadow
	parent.add_child(l)


func _process(delta: float) -> void:
	_time += delta
	_idle += delta
	if _idle >= AUTO_SPIN_DELAY and not dragging:
		yaw += AUTO_SPIN * delta
	var blend := 1.0 - exp(-SMOOTHING * delta)
	_shown_yaw = lerpf(_shown_yaw, yaw, blend)
	_shown_pitch = lerpf(_shown_pitch, pitch, blend)
	_shown_distance = lerpf(_shown_distance, distance, blend)
	_ship.position.y = sin(_time * 0.7) * 0.1
	if is_instance_valid(_showcase):
		_showcase.position.y = _showcase_rest_y + sin(_time * 0.7) * 0.1
	var flat := cos(_shown_pitch) * _shown_distance
	_cam.position = Vector3(sin(_shown_yaw) * flat, sin(_shown_pitch) * _shown_distance, cos(_shown_yaw) * flat)
	var up := Vector3.UP
	_cam.look_at(Vector3.ZERO, up)
	# h_offset grows with distance so the ship holds the same place on screen.
	var half_width := tan(deg_to_rad(_cam.fov * 0.5)) * _shown_distance * _aspect()
	var wanted_offset := 0.0 if inspecting else (SHOWCASE_SCREEN_OFFSET if is_instance_valid(_showcase) else SHIP_SCREEN_OFFSET)
	_shown_offset = lerpf(_shown_offset, wanted_offset, blend)
	_cam.h_offset = -half_width * _shown_offset * 2.0
	for part in _pad:
		part.visible = _shown_pitch > PAD_HIDE_PITCH


## Puts a gallery entry on the pad, or the ship back when given an empty entry.
func show_entry(entry: Dictionary) -> void:
	if is_instance_valid(_showcase):
		_showcase.queue_free()
	_showcase = null
	_ship.visible = entry.is_empty()
	if entry.is_empty():
		return
	_showcase = load(entry["model"]).instantiate()
	Mats.apply(_showcase)
	add_child(_showcase)
	if entry.get("id") == "wren9":
		ShipLoadout.attach(_showcase)
	var tint: Color = entry["tint"]
	if tint != Color.BLACK:
		var glow := Mats.unique_glow(_showcase, entry.get("tint_mat", "glow_blue"))
		glow.emission = tint
		glow.emission_energy_multiplier = 2.6
	_fit_showcase()


func _fit_showcase() -> void:
	var bounds := _merged_bounds(_showcase)
	var factor := SHOWCASE_SIZE / maxf(bounds.get_longest_axis_size(), 0.01)
	_showcase.scale = Vector3.ONE * factor
	var center := bounds.get_center() * factor
	# Centred, unless that would sink the model through the pad.
	_showcase_rest_y = maxf(-center.y, SHOWCASE_FLOOR - bounds.position.y * factor)
	_showcase.position = Vector3(-center.x, _showcase_rest_y, -center.z)


func _merged_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	var inverse := root.global_transform.affine_inverse()
	for node in meshes:
		var box: AABB = (inverse * (node as MeshInstance3D).global_transform) * (node as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _aspect() -> float:
	var size := get_viewport().get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


## Only clicks that miss the menu start a drag; once started it runs until release,
## even across the menu, so it is tracked in _input.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(ZOOM_STEP)
	elif event is InputEventPanGesture:
		zoom(event.delta.y)
	elif event is InputEventMagnifyGesture:
		zoom((1.0 - event.factor) * 12.0)


func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		orbit(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * DRAG_SPEED
	pitch = clampf(pitch + relative.y * DRAG_SPEED, MIN_PITCH, MAX_PITCH)
	_idle = 0.0


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, MIN_DISTANCE, MAX_DISTANCE)
	_idle = 0.0
