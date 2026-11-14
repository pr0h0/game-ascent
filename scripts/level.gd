extends Node3D
## Assembles the mine at runtime from the Blender GLB and its gameplay JSON.

const WARM_MODELS := ["missile", "missile_cluster", "missile_bunker", "missile_emp", "missile_swarm", "missile_mine", "mine_prox", "mine_seeker", "pickup_shield", "pickup_energy", "pickup_ammo", "tick"]
const ALARM_RANGE := 220.0
const ALARM_COLOR := Color(1.0, 0.16, 0.08)
## Brightness of an alarm light out of the ship's range: the middle of the pulse.
const ALARM_HOLD := 0.55

var data: Dictionary
var cell_size := 10.0
var astar := AStar3D.new()
var cell_ids: Dictionary = {}
var lights: Array[OmniLight3D] = []
var _light_base: Array = []
var _alarm := false
## Per light: whether the alarm pulse is currently driving it (it's near the ship).
var _alarm_pulsing := PackedByteArray()
var _env: Environment
## Set once the finale leaves the mine; settings changes mustn't bring the tunnel murk back.
var _in_space := false
var automap: Automap
var _combat_check := 0.0
var _atmosphere_cd := 8.0
var _alarm_tick := 0.0
var _preloaded: Array = []
## Molten floors, if this level has any (scripts/lava.gd).
var lava: Lava
## Pathing cost of a cell just over lava, so routes take the open space above a pool.
const LAVA_PATH_COST := 8.0


func _ready() -> void:
	Game.level = self
	data = JSON.parse_string(FileAccess.get_file_as_string(Game.current_level()["data"]))
	cell_size = data["cell_size"]
	_build_environment()
	_build_geometry()
	_build_navigation()
	_build_lava()
	_build_lights()
	_spawn_entities()
	_warm_up()
	var hud := preload("res://scripts/hud.gd").new()
	add_child(hud)
	automap = Automap.new()
	add_child(automap)
	Sfx.loop(str(Game.current_level().get("ambience", "ambience")), -11.0)
	Music.play_song(str(Game.current_level().get("music", "shift")))
	Sfx.play("ui_start", null, -6.0)


func _build_environment() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.01, 0.014)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.52, 0.66)
	# Each level's rock theme tints the ambient light and the haze a little.
	var theme := Mats.theme(str(data.get("theme", "")))
	if not theme.is_empty():
		e.ambient_light_color = e.ambient_light_color.lerp(Mats._color(theme["ambient"]), 0.6)
	e.ambient_light_energy = 0.19
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_white = 6.0
	e.ssao_enabled = Settings.uses_ssao()
	e.ssao_radius = 2.2
	e.ssao_intensity = 2.4
	e.glow_enabled = true
	e.glow_intensity = 0.62
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.volumetric_fog_enabled = Settings.uses_volumetric_fog()
	e.volumetric_fog_density = 0.0085
	e.volumetric_fog_albedo = Color(0.82, 0.82, 0.86) if theme.is_empty() else Mats._color(theme["fog"])
	e.volumetric_fog_length = 90.0
	e.volumetric_fog_gi_inject = 0.0
	var world := WorldEnvironment.new()
	world.environment = e
	add_child(world)
	_env = e
	Settings.settings_changed.connect(_on_settings_changed)


## Pause-menu settings take effect without reloading the level.
func _on_settings_changed() -> void:
	if _in_space:
		return
	_env.ssao_enabled = Settings.uses_ssao()
	_env.volumetric_fog_enabled = Settings.uses_volumetric_fog()


## The finale leaves the mine: stars outside, and none of the tunnel's murk.
func enter_space() -> void:
	_in_space = true
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/space_sky.png")
	sky_mat.energy_multiplier = 1.6
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_energy = 0.3
	_env.volumetric_fog_enabled = false
	_env.ssao_enabled = false


func _build_geometry() -> void:
	var scene: PackedScene = load(Game.current_level()["model"])
	var mesh_root: Node3D = scene.instantiate()
	add_child(mesh_root)
	Mats.apply(mesh_root)
	_disable_detail_shadows(mesh_root)
	WallParts.populate(mesh_root, data)
	var body := StaticBody3D.new()
	body.collision_layer = Game.WORLD
	body.collision_mask = 0
	add_child(body)
	_add_collision(mesh_root, body)
	_add_occluders(mesh_root)


## The rock shell hides everything behind it, so it doubles as the occluder: whole rooms
## and tunnels out of sight skip rendering (3-8x fewer draw calls in the big mines).
## The web build has no occlusion culling, so it skips this.
func _add_occluders(node: Node) -> void:
	if not ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false):
		return
	for m in node.find_children("Shell_*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(si)
			var occ := ArrayOccluder3D.new()
			occ.set_arrays(a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_INDEX])
			var oi := OccluderInstance3D.new()
			oi.occluder = occ
			m.add_child(oi)


## Greebles sit flush on walls, so their shadows cost far more than they show.
func _disable_detail_shadows(node: Node) -> void:
	if node is MeshInstance3D and node.name.begins_with("Detail_"):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		_disable_detail_shadows(c)


func _add_collision(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D and node.name.begins_with("Shell_"):
		var shape := CollisionShape3D.new()
		shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
	for c in node.get_children():
		_add_collision(c, body)


func _build_navigation() -> void:
	var dirs := [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	for c in data["cells"]:
		var cell := Vector3i(int(c[0]), int(c[1]), int(c[2]))
		var id := cell_ids.size()
		cell_ids[cell] = id
		astar.add_point(id, Vector3(cell) * cell_size)
	for cell: Vector3i in cell_ids:
		for d: Vector3i in dirs:
			if cell_ids.has(cell + d):
				astar.connect_points(cell_ids[cell], cell_ids[cell + d])


func _build_lava() -> void:
	lava = Lava.new()
	add_child(lava)
	lava.setup(data)
	for c: Array in data.get("lava_cells", []):
		var cell := Vector3i(int(c[0]), int(c[1]), int(c[2]))
		if cell_ids.has(cell):
			astar.set_point_weight_scale(cell_ids[cell], LAVA_PATH_COST)


func set_cell_blocked(cell: Vector3i, blocked: bool) -> void:
	if cell_ids.has(cell):
		astar.set_point_disabled(cell_ids[cell], blocked)


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	if a < 0 or b < 0:
		return PackedVector3Array()
	return astar.get_point_path(a, b)


func _build_lights() -> void:
	for l in data["lights"]:
		var light := OmniLight3D.new()
		light.position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		light.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		light.light_energy = l["energy"]
		light.omni_range = l["range"]
		light.omni_attenuation = 1.1
		light.light_specular = 0.6
		light.light_volumetric_fog_energy = 0.8
		add_child(light)
		lights.append(light)
		_light_base.append(l["energy"])


func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _spawn_entities() -> void:
	var player := preload("res://scripts/player.gd").new()
	add_child(player)
	player.global_position = v3(data["start"])
	# The ship noted its spawn in _ready, before it was moved: an airframe lost before the
	# first checkpoint would otherwise relaunch at the origin, inside the rock.
	player.set_checkpoint()
	Game.robots_total = data["robots"].size()
	for r in data["robots"]:
		spawn_robot(r["type"], v3(r["pos"]))
	for t in data["turrets"]:
		var sentry := preload("res://scripts/sentry.gd").new()
		add_child(sentry)
		sentry.setup(v3(t["pos"]), v3(t["normal"]))
	for p in data["pickups"]:
		spawn_pickup(p["type"], v3(p["pos"]))
	for at in data["astronauts"]:
		var survivor := Astronaut.new()
		add_child(survivor)
		survivor.global_position = v3(at)
		Game.astronauts_total += 1
	_spawn_catch_up_upgrades()
	for d in data["doors"]:
		var door := preload("res://scripts/door.gd").new()
		door.hidden_door = d["lock"] == "secret"
		add_child(door)
		door.setup(d, cell_size)
		if d["lock"] == "secret":
			Game.secrets_total += 1
	if data["reactor"] != null:
		var reactor := preload("res://scripts/reactor.gd").new()
		reactor.model_scale = data["reactor_scale"]
		reactor.max_hp = data["reactor_hp"]
		reactor.fires_novas = data["reactor_nova"]
		add_child(reactor)
		reactor.global_position = v3(data["reactor"])
	for m in data.get("mines", []):
		Mine.spawn(m["type"], v3(m["pos"]), v3(m["normal"]))
	var run := EscapeRun.new()
	add_child(run)
	run.setup(data["escape_path"], v3(data["escape_trigger"]))


## Upgrades from earlier levels reappear here, so skipping or dying never locks you out.
func _spawn_catch_up_upgrades() -> void:
	var spots: Array = data.get("catch_up", [])
	var kinds: Array = Game.earlier_upgrades(Game.level_index)
	if kinds.size() > spots.size():
		push_error("Level needs %d CATCH_UP spots but has %d" % [kinds.size(), spots.size()])
	for i in mini(kinds.size(), spots.size()):
		spawn_pickup(kinds[i], v3(spots[i]))


## bounty false: spawned mid-fight (brood, boss guards), so worth no score, kill or drop.
func spawn_robot(kind: String, at: Vector3, awake := false, bounty := true) -> Node3D:
	var robot: Robot = Robot.make(kind)
	robot.kind = kind
	robot.home = at
	robot.bounty = bounty
	add_child(robot)
	robot.global_position = at
	if awake:
		robot.alert()
	return robot


func spawn_pickup(kind: String, at: Vector3) -> void:
	var p := preload("res://scripts/pickup.gd").new()
	p.kind = kind
	add_child(p)
	p.global_position = at


func start_alarm() -> void:
	_alarm = true
	# Every light turns red at once; the ones near the ship then pulse.
	_alarm_pulsing.resize(lights.size())
	_alarm_pulsing.fill(0)
	for i in lights.size():
		_hold_alarm_light(i)
	for at in data["alarm_spawns"]:
		spawn_robot("tick", v3(at), true)


## Music reacts to robots actually fighting, and the mine groans around the ship.
func _update_audio_state(delta: float) -> void:
	_combat_check -= delta
	if _combat_check <= 0.0 and Game.player != null and not Game.reactor_down:
		_combat_check = 0.3
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Robot and e.alerted and e.has_los:
				Music.report_combat()
				break
	_atmosphere_cd -= delta
	if _atmosphere_cd <= 0.0 and Game.player != null and not Game.player.dead and not Game.cinematic:
		_atmosphere_cd = randf_range(7.0, 18.0)
		var sound: String = ["mine_creak", "mine_drip", "mine_clank", "mine_rumble", "mine_steam"].pick_random()
		var spot: Vector3 = Game.player.global_position + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized() * randf_range(25.0, 55.0)
		Sfx.play(sound, spot, -7.0, randf_range(0.85, 1.1))


## Everything that first appears mid-fight is loaded and drawn once, behind the title card.
func _warm_up() -> void:
	for file: String in WARM_MODELS:
		_preloaded.append(load("res://assets/models/%s.glb" % file))
	if Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return
	var card := LevelCard.new()
	add_child(card)
	var p: Player = Game.player
	var ahead: Vector3 = p.global_position - p.global_basis.z * 12.0
	Sfx.silent = true
	Fx.explosion(ahead, 5.0)
	Fx.explosion(ahead, 12.0, true)
	Fx.sparks(ahead, Vector3.UP, Color(1.0, 0.7, 0.3))
	Fx.pulse(ahead, 20.0, Weapons.ARC_COLOR)
	for color in Player.LASER_COLORS + [Weapons.PRISM_COLOR]:
		Bolt.launch(ahead, Vector3.FORWARD, 1.0, 0.0, color, 0).life = 0.15
	Weapons.beam(ahead, ahead + Vector3.UP * 8.0, Weapons.RAIL_COLOR, 0.42)
	for packed: PackedScene in _preloaded:
		var model: Node3D = packed.instantiate()
		Mats.apply(model)
		add_child(model)
		model.global_position = ahead
		get_tree().create_timer(0.15).timeout.connect(model.queue_free)
	Sfx.silent = false
	p._shake = 0.0


func _process(delta: float) -> void:
	_update_audio_state(delta)
	if not _alarm:
		return
	_alarm_tick -= delta
	if _alarm_tick > 0.0:
		return
	# Only the lights around the ship can be seen; updating all of them is wasted.
	_alarm_tick = 0.03
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	if Game.player == null:
		return
	var here: Vector3 = Game.player.global_position
	for i in lights.size():
		var l := lights[i]
		if l.position.distance_squared_to(here) > ALARM_RANGE * ALARM_RANGE:
			# Leaving range: settle on a steady level instead of freezing mid-pulse.
			if _alarm_pulsing[i] == 1:
				_hold_alarm_light(i)
			continue
		_alarm_pulsing[i] = 1
		l.light_energy = float(_light_base[i]) * pulse


func _hold_alarm_light(i: int) -> void:
	_alarm_pulsing[i] = 0
	lights[i].light_color = ALARM_COLOR
	lights[i].light_energy = float(_light_base[i]) * ALARM_HOLD
