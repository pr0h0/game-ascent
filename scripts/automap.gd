class_name Automap
extends CanvasLayer
## A wireframe of everywhere the ship has been. Drag to orbit, wheel to zoom.
## Only explored tunnels are drawn, and only keys and doors actually seen are marked.

const REVEAL_DEPTH := 4
const REVEAL_INTERVAL := 0.25
const DRAG_SPEED := 0.008
const MIN_ZOOM := 25.0
const MAX_ZOOM := 900.0
const LINE_COLOR := Color(0.32, 0.72, 1.0)
const CURRENT_COLOR := Color(0.55, 1.0, 0.75)
const FACE_DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var explored: Dictionary = {}
var is_open := false
var _level: Node3D
var _reveal_cd := 0.0
var _viewport: SubViewport
var _container: SubViewportContainer
var _camera: Camera3D
var _world: Node3D
var _lines: MeshInstance3D
var _markers: Node3D
var _player_marker: MeshInstance3D
var _yaw := 0.6
var _pitch := -0.7
var _zoom := 180.0
var _focus := Vector3.ZERO
var _legend: Label
var _dragging := false
var _seen_doors: Dictionary = {}
var _seen_keys: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	_level = Game.level
	_container = SubViewportContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.visible = false
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.016, 0.03)
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	_camera = Camera3D.new()
	_camera.far = 4000.0
	_camera.fov = 55.0
	_world.add_child(_camera)
	_lines = MeshInstance3D.new()
	_world.add_child(_lines)
	_markers = Node3D.new()
	_world.add_child(_markers)
	_player_marker = _make_marker(Color(1.0, 1.0, 1.0), 5.0, true)
	_world.add_child(_player_marker)
	_legend = Label.new()
	_legend.position = Vector2(34, 24)
	_legend.add_theme_font_size_override("font_size", 20)
	_legend.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_legend.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_legend.add_theme_constant_override("outline_size", 4)
	_legend.visible = false
	add_child(_legend)


func _process(delta: float) -> void:
	if is_open:
		_update_camera()
		return
	_reveal_cd -= delta
	if _reveal_cd <= 0.0 and Game.player != null and not Game.player.dead:
		_reveal_cd = REVEAL_INTERVAL
		reveal_around(Game.player.global_position)
		_note_landmarks()


## Spreads through open cells only, so nothing is revealed through a wall or a shut door.
func reveal_around(pos: Vector3) -> void:
	var start_id: int = _level.astar.get_closest_point(pos)
	if start_id < 0:
		return
	var start := Vector3i((_level.astar.get_point_position(start_id) / _level.cell_size).round())
	var frontier: Array[Vector3i] = [start]
	var seen := {start: true}
	explored[start] = true
	for depth in REVEAL_DEPTH:
		var next: Array[Vector3i] = []
		for cell in frontier:
			for dir: Vector3i in FACE_DIRS:
				var other: Vector3i = cell + dir
				if seen.has(other) or not _level.cell_ids.has(other):
					continue
				seen[other] = true
				if _level.astar.is_point_disabled(_level.cell_ids[other]):
					continue
				explored[other] = true
				next.append(other)
		frontier = next


func _note_landmarks() -> void:
	var p: Player = Game.player
	for door in _level.get_children():
		if door is Door and not door.hidden_door and not _seen_doors.has(door) and p.global_position.distance_to(door.global_position) < 70.0 and _visible_from_ship(door):
			_seen_doors[door] = true
	for pickup in get_tree().get_nodes_in_group("pickup"):
		if pickup.kind.begins_with("key_") and not _seen_keys.has(pickup) and p.global_position.distance_to(pickup.global_position) < 90.0 and p.has_line_of_sight(pickup):
			_seen_keys[pickup] = pickup.kind.trim_prefix("key_")


func _visible_from_ship(door: Door) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Game.player.global_position, door.global_position, Game.WORLD)
	q.exclude = [door.get_rid()]
	return Game.player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if Game.finished or Game.cinematic or Game.player == null or Game.player.dead:
		return
	is_open = true
	get_tree().paused = true
	Sfx.play("map_open", null, -5.0)
	if not Game.autopilot:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_container.visible = true
	_legend.visible = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rebuild()
	_focus = Game.player.global_position
	_yaw = Game.player.global_rotation.y + 0.5
	_update_camera()


func close() -> void:
	is_open = false
	get_tree().paused = false
	Sfx.play("map_close", null, -5.0)
	_dragging = false
	if not Game.autopilot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_container.visible = false
	_legend.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _update_camera() -> void:
	var basis_now := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.global_transform = Transform3D(basis_now, _focus + basis_now.z * _zoom)
	if Game.player != null:
		_player_marker.global_transform = Game.player.global_transform
		_player_marker.scale = Vector3.ONE * clampf(_zoom * 0.04, 2.0, 18.0)


## One outline per exposed cell face: rooms read as hulls and tunnels as tubes.
func _rebuild() -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var size: float = _level.cell_size
	var half := size * 0.5
	var here := Vector3i((Game.player.global_position / size).round())
	for cell: Vector3i in explored:
		var center := Vector3(cell) * size
		var close_to_ship := cell.distance_to(here) < 14.0
		var tone: Color = CURRENT_COLOR if close_to_ship else LINE_COLOR.lerp(Color(0.5, 0.45, 1.0), clampf((float(cell.y) + 20.0) / 40.0, 0.0, 1.0))
		for dir: Vector3i in FACE_DIRS:
			if _level.cell_ids.has(cell + dir):
				continue
			var n := Vector3(dir)
			var u := Vector3(n.y, n.z, n.x) * half
			var v := n.cross(u.normalized()) * half
			var c := center + n * half
			var corners := [c - u - v, c + u - v, c + u + v, c - u + v]
			for i in 4:
				points.append(corners[i])
				points.append(corners[(i + 1) % 4])
				colors.append(tone)
				colors.append(tone)
	if points.is_empty():
		_lines.mesh = null
	else:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.55)
		mesh.surface_set_material(0, mat)
		_lines.mesh = mesh
	_rebuild_markers()
	_legend.text = "MAP — %s    %d%% explored\nDrag to orbit  ·  Wheel to zoom  ·  Tab to close" % [Game.level_title(Game.level_index), int(100.0 * explored.size() / maxf(float(_level.cell_ids.size()), 1.0))]


func _rebuild_markers() -> void:
	for child in _markers.get_children():
		child.queue_free()
	for door: Door in _seen_doors:
		if not is_instance_valid(door):
			continue
		var marker := _make_marker(Color(0.3, 1.0, 0.4) if door._is_open else Game.KEY_COLORS.get(door.lock, Color(1.0, 0.45, 0.2)), 4.0, false)
		_markers.add_child(marker)
		marker.global_position = door.global_position
	for key_node in _seen_keys:
		if is_instance_valid(key_node):
			var marker := _make_marker(Game.KEY_COLORS[_seen_keys[key_node]], 5.5, false)
			_markers.add_child(marker)
			marker.global_position = key_node.global_position


func _make_marker(color: Color, size: float, arrow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	if arrow:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.55
		cone.height = 2.2
		cone.material = mat
		mi.mesh = cone
		# The cone's tip is +Y; the ship flies along -Z.
		var holder := MeshInstance3D.new()
		holder.add_child(mi)
		mi.rotation_degrees = Vector3(-90, 0, 0)
		return holder
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	box.material = mat
	mi.mesh = box
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("automap"):
		# The pause menu owns the screen while it's up.
		if get_tree().paused and not is_open:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	# Start (pause_game) closes the map too, so it never opens the pause menu on top
	# of it, where Resume would unpause the game with the map still up.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.88, MIN_ZOOM, MAX_ZOOM)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.14, MIN_ZOOM, MAX_ZOOM)
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * DRAG_SPEED
		_pitch = clampf(_pitch - event.relative.y * DRAG_SPEED, -1.5, 1.5)
