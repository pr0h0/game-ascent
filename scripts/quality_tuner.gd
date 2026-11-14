extends Node
## Scales how far each mine draws with the graphics quality, after the level has built
## itself: distant wall parts and tunnel chunks are culled with visibility ranges, far
## lamps fade out, and where there is no volumetric fog a cheap depth fog hides the cut.
## Like level_mood.gd it only adjusts what level.gd built, so geometry stays with level.gd.

## Per quality (LOW, MEDIUM, HIGH). 0 means never culled.
## Wall parts are batched in 160 m chunks, so a chunk's centre can sit ~140 m from its nearest part.
const PART_RANGE := [230.0, 330.0, 600.0]
## Tunnel shell chunks are 80 m across; only culled where depth fog has swallowed them.
const SHELL_RANGE := [400.0, 480.0, 0.0]
const RANGE_MARGIN := 12.0
## Lamps fade out over LIGHT_FADE_LENGTH from this distance; their light pools are small.
const LIGHT_FADE := [110.0, 170.0, 260.0]
const LIGHT_FADE_LENGTH := [25.0, 30.0, 40.0]
## Glow levels kept at each quality; fewer and smaller ones are cheaper blur passes.
const GLOW_LEVELS := [[1, 2, 3], [1, 3, 5], [3, 5]]

var _level_id := 0
var _env: Environment
var _in_space := false


func _ready() -> void:
	Settings.settings_changed.connect(_on_settings_changed)


func _process(_delta: float) -> void:
	var level: Variant = Game.level
	if not is_instance_valid(level):
		_level_id = 0
		_env = null
		return
	if level.get_instance_id() != _level_id:
		if not (level.get("_env") is Environment):
			return
		_level_id = level.get_instance_id()
		_env = level.get("_env")
		_in_space = false
		_apply(level)
	# The finale swaps the mine's murk for a starfield; depth fog must not follow it out.
	var space := _env.background_mode == Environment.BG_SKY
	if space != _in_space:
		_in_space = space
		_apply_fog()


func _on_settings_changed() -> void:
	if is_instance_valid(Game.level) and Game.level.get_instance_id() == _level_id:
		_apply(Game.level)


func _q() -> int:
	return clampi(Settings.quality, 0, 2)


func _apply(level: Node) -> void:
	var q := _q()
	for root in level.get_children():
		if root.get_script() != null or not (root is Node3D):
			continue
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			if node is MultiMeshInstance3D:
				_set_range(node, PART_RANGE[q])
			elif node is MeshInstance3D and node.name.begins_with("Shell_"):
				_set_range(node, SHELL_RANGE[q])
	var lights: Variant = level.get("lights")
	if lights is Array:
		for light: Light3D in lights:
			if is_instance_valid(light):
				light.distance_fade_enabled = true
				light.distance_fade_begin = LIGHT_FADE[q]
				light.distance_fade_length = LIGHT_FADE_LENGTH[q]
				light.distance_fade_shadow = LIGHT_FADE[q]
	for i in 7:
		_env.set_glow_level(i, 1.0 if (i + 1) in GLOW_LEVELS[q] else 0.0)
	_apply_fog()


func _set_range(node: GeometryInstance3D, end: float) -> void:
	node.visibility_range_end = end
	node.visibility_range_end_margin = RANGE_MARGIN if end > 0.0 else 0.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Without volumetric fog (low and medium quality, and the web renderer, which has none)
## distant tunnel fades into a dim haze of the mine's fog colour instead. The background
## gets the same haze, so a culled chunk shows the colour it was already fading to.
func _apply_fog() -> void:
	if _env == null:
		return
	var volumetric := Settings.uses_volumetric_fog()
	_env.fog_enabled = not volumetric and not _in_space
	if not _env.fog_enabled:
		return
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_density = maxf(_env.volumetric_fog_density, 0.0085) * 0.7
	_env.fog_light_color = _env.volumetric_fog_albedo * 0.07 + _env.volumetric_fog_emission
	_env.fog_light_energy = 1.0
	_env.fog_sun_scatter = 0.0
	_env.fog_sky_affect = 1.0
