extends Node
## Swaps the named placeholder materials on imported GLBs for real PBR materials.
## Blender only authors geometry and material names; every look lives here, so
## textures are shared across models and can be tuned without re-exporting.

const TEX := "res://assets/textures/"
## Per-level rock, ore and lava colours, written by tools/blender/gen_textures.py from themes.py.
const THEMES_FILE := "res://assets/textures/themes.json"
## Molten floor: two scrolling noise layers, with cooled crust plates split by glowing seams.
## The shell's vertex alpha says how molten each spot is, so pools fade to crust at the rim.
const LAVA_SHADER := """
shader_type spatial;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 hot_color : source_color = vec3(1.0, 0.7, 0.2);
uniform vec3 warm_color : source_color = vec3(1.0, 0.25, 0.03);
uniform float energy = 3.4;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_pos.xz * 0.028;
	float t = TIME * 0.018;
	vec3 a = texture(noise_tex, p + vec2(t, t * 0.4)).rgb;
	float b = texture(noise_tex, p * 2.3 + vec2(-t * 1.3, t * 0.9) + a.rg * 0.15).g;
	float seam = texture(noise_tex, p * 1.3 + a.rg * 0.06 - vec2(t * 0.5, 0.0)).b;
	float melt = COLOR.a;
	float flow = smoothstep(0.38, 0.72, a.r * 0.6 + b * 0.4);
	float heat = clamp(flow + seam * seam * 0.8, 0.0, 1.0) * melt;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.6 + a.g * 12.0);
	ALBEDO = mix(vec3(0.03, 0.026, 0.025), vec3(0.09, 0.03, 0.015), heat) * COLOR.rgb;
	ROUGHNESS = mix(0.95, 0.45, heat);
	EMISSION = mix(warm_color, hot_color, flow * flow) * heat * energy * pulse + warm_color * melt * 0.06;
}
"""

var _cache: Dictionary = {}
var _themes: Dictionary = {}
var _lava_shader: Shader

const SURFACES := {
	# name: [texture set, tint, metallic, uv scale, emission colour-or-null]
	"hull_white": ["hull", Color(0.80, 0.82, 0.84), 0.30, 1.0],
	"hull_grey": ["hull", Color(0.34, 0.37, 0.41), 0.45, 1.0],
	"hull_dark": ["hull", Color(0.075, 0.08, 0.095), 0.6, 1.0],
	"hull_accent": ["hull", Color(0.86, 0.27, 0.05), 0.2, 1.0],
	"metal_bare": ["hull", Color(0.72, 0.73, 0.75), 1.0, 2.0],
	"metal_dark": ["hull", Color(0.11, 0.115, 0.13), 0.95, 2.0],
	"metal_burn": ["hull", Color(0.27, 0.20, 0.23), 1.0, 2.0],
	"robot_shell": ["hull", Color(0.17, 0.19, 0.17), 0.65, 1.0],
	"robot_paint": ["hull", Color(0.62, 0.50, 0.12), 0.25, 1.0],
	"robot_rust": ["wall", Color(0.45, 0.28, 0.17), 0.5, 1.0],
	"wall_metal": ["wall", Color(0.9, 0.92, 0.95), 0.55, 1.0],
	"floor_metal": ["floor", Color(1.0, 1.0, 1.0), 0.85, 1.0],
	"wall_core": ["wall", Color(0.30, 0.34, 0.43), 0.7, 1.0],
}

const GLOWS := {
	"glow_engine": [Color(0.35, 0.75, 1.0), 9.0],
	"glow_orange": [Color(1.0, 0.45, 0.1), 4.5],
	"glow_cyan": [Color(0.15, 0.95, 1.0), 6.0],
	"glow_red": [Color(1.0, 0.07, 0.04), 7.0],
	"glow_green": [Color(0.15, 1.0, 0.3), 5.0],
	"glow_white": [Color(1.0, 0.96, 0.85), 7.0],
	"glow_amber": [Color(1.0, 0.68, 0.25), 5.0],
	"glow_screen": [Color(0.2, 0.75, 1.0), 0.75],
	"glow_crystal": [Color(0.15, 0.95, 0.85), 2.2],
	"glow_core": [Color(0.55, 1.0, 0.9), 12.0],
	"glow_blue": [Color(0.15, 0.4, 1.0), 3.0],
	"glow_yellow": [Color(1.0, 0.72, 0.04), 2.4],
	"glow_visor": [Color(1.0, 0.68, 0.22), 1.1],
	"glow_violet": [Color(0.8, 0.25, 1.0), 4.0],
	"glow_trim": [Color(0.2, 0.8, 1.0), 1.3],
	"glow_dash": [Color(1.0, 0.6, 0.2), 0.9],
	"glow_ore": [Color(1.0, 0.66, 0.2), 3.0],
}


func _tex(name: String) -> Texture2D:
	return load(TEX + name + ".png") as Texture2D


func get_material(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m := _build(mat_name)
	_cache[mat_name] = m
	return m


## A level theme's colours from themes.json, or an empty dictionary.
func theme(theme_id: String) -> Dictionary:
	if _themes.is_empty() and FileAccess.file_exists(THEMES_FILE):
		_themes = JSON.parse_string(FileAccess.get_file_as_string(THEMES_FILE))
	return _themes.get(theme_id, {})


static func _color(a: Array) -> Color:
	return Color(a[0], a[1], a[2])


## The rock and ore materials a level's theme swaps onto shared wall details.
func theme_rock(theme_id: String) -> Material:
	return get_material("rock_" + theme_id) if not theme(theme_id).is_empty() else get_material("wall_rock")


func theme_glow(theme_id: String) -> Material:
	return get_material("glow_ore_" + theme_id) if not theme(theme_id).is_empty() else get_material("glow_ore")


func _build_themed(mat_name: String) -> Material:
	if mat_name.begins_with("lava_"):
		var lt := theme(mat_name.trim_prefix("lava_"))
		if _lava_shader == null:
			_lava_shader = Shader.new()
			_lava_shader.code = LAVA_SHADER
		var lava := ShaderMaterial.new()
		lava.resource_name = mat_name
		lava.shader = _lava_shader
		lava.set_shader_parameter("noise_tex", _tex("lava_noise"))
		if not lt.is_empty():
			lava.set_shader_parameter("hot_color", _color(lt["lava_hot"]))
			lava.set_shader_parameter("warm_color", _color(lt["lava_warm"]))
			lava.set_shader_parameter("energy", float(lt["lava_energy"]))
		return lava
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	if mat_name.begins_with("glow_ore_"):
		var gt := theme(mat_name.trim_prefix("glow_ore_"))
		m.albedo_color = Color.BLACK
		m.emission_enabled = true
		m.emission = _color(gt["glow"])
		m.emission_energy_multiplier = float(gt["glow_energy"])
		m.roughness = 0.3
		return m
	var id := mat_name.trim_prefix("rock_")
	var t := theme(id)
	var set_name := "rock_" + id
	m.albedo_texture = _tex(set_name + "_a")
	m.albedo_color = _color(t["tint"])
	m.roughness_texture = _tex(set_name + "_r")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = _tex(set_name + "_n")
	m.normal_scale = 1.0
	m.emission_enabled = true
	m.emission = Color.WHITE
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.emission_texture = _tex(set_name + "_e")
	m.emission_energy_multiplier = float(t["rock_glow"])
	m.vertex_color_use_as_albedo = true
	return m


func _is_themed(mat_name: String) -> bool:
	if mat_name.begins_with("lava_"):
		return true
	if mat_name.begins_with("glow_ore_"):
		return not theme(mat_name.trim_prefix("glow_ore_")).is_empty()
	if mat_name.begins_with("rock_"):
		return not theme(mat_name.trim_prefix("rock_")).is_empty()
	return false


func _build(mat_name: String) -> Material:
	if _is_themed(mat_name):
		return _build_themed(mat_name)
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	if SURFACES.has(mat_name):
		var def: Array = SURFACES[mat_name]
		var set_name: String = def[0]
		m.albedo_texture = _tex(set_name + "_a")
		m.albedo_color = def[1]
		m.metallic = def[2]
		m.roughness_texture = _tex(set_name + "_r")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.normal_enabled = true
		m.normal_texture = _tex(set_name + "_n")
		m.normal_scale = 1.0
		m.uv1_scale = Vector3.ONE * float(def[3])
		if mat_name.begins_with("wall") or mat_name.begins_with("floor"):
			m.vertex_color_use_as_albedo = true
	elif GLOWS.has(mat_name):
		var g: Array = GLOWS[mat_name]
		m.albedo_color = Color.BLACK
		m.emission_enabled = true
		m.emission = g[0]
		m.emission_energy_multiplier = g[1]
		m.roughness = 0.4
	else:
		match mat_name:
			"glass":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(0.25, 0.42, 0.55, 0.26)
				m.metallic = 0.9
				m.roughness = 0.04
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"hazard":
				m.albedo_texture = _tex("hazard_a")
				m.roughness = 0.6
				m.metallic = 0.2
			"wall_rock":
				m.albedo_texture = _tex("rock_a")
				m.roughness_texture = _tex("rock_r")
				m.roughness = 1.0
				m.normal_enabled = true
				m.normal_texture = _tex("rock_n")
				m.normal_scale = 1.0
				m.emission_enabled = true
				m.emission = Color.WHITE
				m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				m.emission_texture = _tex("rock_e")
				m.emission_energy_multiplier = 1.7
				m.vertex_color_use_as_albedo = true
			_:
				m.albedo_color = Color(1, 0, 1)
				push_warning("Unmapped material: " + mat_name)
	return m


## Replaces every surface material under root, using the imported material name.
func apply(root: Node) -> void:
	if root is MeshInstance3D and root.mesh != null:
		for i in root.mesh.get_surface_count():
			var src: Material = root.mesh.surface_get_material(i)
			if src != null:
				root.set_surface_override_material(i, get_material(src.resource_name))
	for child in root.get_children():
		apply(child)


## Per-instance copy of a glow so one robot's eye can flash without affecting all.
func unique_glow(root: Node, mat_name: String) -> StandardMaterial3D:
	var copy := (get_material(mat_name) as StandardMaterial3D).duplicate() as StandardMaterial3D
	_replace(root, mat_name, copy)
	return copy


func _replace(node: Node, mat_name: String, mat: Material) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var src: Material = node.mesh.surface_get_material(i)
			if src != null and src.resource_name == mat_name:
				node.set_surface_override_material(i, mat)
	for c in node.get_children():
		_replace(c, mat_name, mat)
