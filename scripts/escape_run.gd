class_name EscapeRun
extends Node3D
## The finale: about six seconds of autopilot down the tunnel with the blast on
## its tail, then out of the mine as the asteroid goes up behind it.

const TRIGGER_RADIUS := 9.0
const SPEED_START := 65.0
const SPEED_END := 90.0
const SPEED_RAMP_TIME := 1.5
const GAP_START := 58.0
const GAP_END := 7.0
const BLEND_TIME := 0.35
const FIRE_BLOBS := 7
const WHITEOUT_DISTANCE := 70.0

## The exterior is staged far from the mine so none of the level can be seen from it.
const SPACE_ORIGIN := Vector3(0.0, 7000.0, 0.0)
const ASTEROID_RADIUS := 180.0
const SPACE_DURATION := 2.3
const SPACE_SPEED := 170.0
const FLYBY_SHOT_TIME := 0.85
const FLASH_FADE_TIME := 0.25
const BLAST_DELAY := 0.75
const BLAST_GROW_TIME := 1.3
const BLAST_END_RADIUS := 2.3 * ASTEROID_RADIUS
const FINAL_FADE_TIME := 0.35
const FIRE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable;
uniform float heat = 1.0;
void fragment() {
	float n = texture(noise_tex, UV * vec2(3.0, 2.0) + vec2(TIME * 0.35, -TIME * 1.3)).r;
	n *= texture(noise_tex, UV.yx * 2.0 - vec2(TIME * 0.7, TIME * 0.2)).r * 2.0;
	float facing = pow(abs(dot(NORMAL, VIEW)), 1.4);
	vec3 hot = mix(vec3(1.5, 0.2, 0.02), vec3(2.6, 1.2, 0.22), smoothstep(0.25, 0.8, n));
	ALBEDO = hot * heat;
	ALPHA = clamp(facing * smoothstep(0.08, 0.5, n) * 0.7, 0.0, 1.0);
}
"""

var _points := PackedVector3Array()
var _ups := PackedVector3Array()
var _trigger := Vector3.ZERO
var _running := false
var _done := false
var _t := 0.0
var _s := 0.0
var _s0 := 0.0
var _fire_s := 0.0
var _speed := SPEED_START
var _start_xf: Transform3D
var _spark_cd := 0.0
var _player: Player

var _in_space := false
var _space_t := 0.0
var _mouth := Vector3.ZERO
var _asteroid: Node3D
## Furthest the current asteroid reaches from its centre: some shapes are longer than others.
var _asteroid_extent := ASTEROID_RADIUS
var _blast: MeshInstance3D
var _blast_light: OmniLight3D
var _debris: GPUParticles3D
var _blasted := false

var _fire_root: Node3D
var _fire_mat: ShaderMaterial
var _blobs: Array[MeshInstance3D] = []
var _front_light: OmniLight3D
var _rear_light: OmniLight3D
var _particles: GPUParticles3D
var _overlay: CanvasLayer
var _white: ColorRect
var _bars: Array[ColorRect] = []


## Every level has its own asteroid shape, named after the level; the old one is the fallback.
static func asteroid_model(level_id: String) -> String:
	var themed := "res://assets/models/asteroid_%s.glb" % level_id
	return themed if level_id != "" and ResourceLoader.exists(themed) else "res://assets/models/asteroid.glb"


## A level's id is the name of its data file, as in first_shift.
static func level_id(index: int) -> String:
	return str(Game.levels[clampi(index, 0, Game.levels.size() - 1)]["data"]).get_file().get_basename()


func setup(path: Array, trigger: Vector3) -> void:
	_trigger = trigger
	_build_path(path)
	# The noise texture (generated on a thread) and the shader are made now, at level
	# load, so the moment the escape triggers doesn't hitch on them.
	_prepare_fire_material()


## Total running time so far, tunnel plus exterior.
func elapsed() -> float:
	return _t + _space_t


## Resamples the cell-centre polyline every metre, then rounds its corners.
func _build_path(path: Array) -> void:
	var raw: Array[Vector3] = []
	for i in path.size() - 1:
		var a := Vector3(path[i][0], path[i][1], path[i][2])
		var b := Vector3(path[i + 1][0], path[i + 1][1], path[i + 1][2])
		var count := int(a.distance_to(b))
		for n in count:
			raw.append(a.lerp(b, float(n) / count))
	var last: Array = path[path.size() - 1]
	raw.append(Vector3(last[0], last[1], last[2]))
	for pass_i in 3:
		var smoothed: Array[Vector3] = []
		for i in raw.size():
			var sum := Vector3.ZERO
			for o in range(-5, 6):
				sum += raw[clampi(i + o, 0, raw.size() - 1)]
			smoothed.append(sum / 11.0)
		raw = smoothed
	_points = PackedVector3Array(raw)
	# Up vectors are carried along the path, easing back to world-up where possible.
	var up := Vector3.UP
	_ups.resize(_points.size())
	for i in _points.size():
		var f := _dir_at(float(i))
		if absf(f.y) < 0.9:
			up = up.lerp(Vector3.UP, 0.03)
		up = (up - f * up.dot(f)).normalized()
		_ups[i] = up


func _length() -> float:
	return float(_points.size() - 1)


func _point(s: float) -> Vector3:
	var c := clampf(s, 0.0, _length())
	var i := mini(int(c), _points.size() - 2)
	return _points[i].lerp(_points[i + 1], c - i)


func _dir_at(s: float) -> Vector3:
	return (_point(s + 5.0) - _point(s - 3.0)).normalized()


func _up_at(s: float) -> Vector3:
	return _ups[clampi(int(s), 0, _ups.size() - 1)]


func _process(delta: float) -> void:
	if _done:
		return
	if not _running:
		var p: Player = Game.player
		if Game.reactor_down and p != null and not p.dead and not Game.finished and p.global_position.distance_to(_trigger) < TRIGGER_RADIUS:
			_begin(p)
		return
	if _in_space:
		_advance_space(delta)
	else:
		_advance_tunnel(delta)


func _begin(p: Player) -> void:
	_running = true
	_player = p
	Game.cinematic = true
	_start_xf = p.global_transform
	var nearest := 0
	var best := INF
	for i in range(0, _points.size(), 2):
		var d := _points[i].distance_squared_to(p.global_position)
		if d < best:
			best = d
			nearest = i
	_s0 = float(nearest)
	_s = _s0
	p.begin_cinematic()
	_build_fire()
	_build_overlay()
	Sfx.play("explode_boss", null, 4.0, 0.85)
	Sfx.loop("fire_roar", -12.0)


func _prepare_fire_material() -> void:
	if _fire_mat != null:
		return
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.noise = noise
	var shader := Shader.new()
	shader.code = FIRE_SHADER
	_fire_mat = ShaderMaterial.new()
	_fire_mat.shader = shader
	_fire_mat.set_shader_parameter("noise_tex", tex)


func _build_fire() -> void:
	_fire_root = Node3D.new()
	add_child(_fire_root)
	_prepare_fire_material()
	for i in FIRE_BLOBS:
		var sphere := SphereMesh.new()
		sphere.radius = 8.0
		sphere.height = 16.0
		sphere.radial_segments = 24
		sphere.rings = 14
		sphere.material = _fire_mat
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fire_root.add_child(mi)
		_blobs.append(mi)
	var pm := Fx._process_mat(
		"blast_front", Vector2(4, 22), 3.0,
		[[0.0, Color(2.2, 1.2, 0.3, 0.5)], [0.3, Color(1.8, 0.55, 0.08, 0.45)], [0.75, Color(0.7, 0.13, 0.02, 0.25)], [1.0, Color(0.1, 0.02, 0, 0)]],
		[[0.0, 0.5], [0.4, 1.0], [1.0, 1.4]]
	).duplicate() as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.5
	_particles = GPUParticles3D.new()
	_particles.amount = 420
	_particles.lifetime = 0.9
	_particles.local_coords = false
	_particles.process_material = pm
	_particles.draw_pass_1 = Fx._quad(Fx._sprite("fx_puff"), 9.0)
	_particles.visibility_aabb = AABB(Vector3.ONE * -9000, Vector3.ONE * 18000)
	_fire_root.add_child(_particles)
	_front_light = _fire_light(30.0, 90.0)
	_rear_light = _fire_light(24.0, 70.0)


func _fire_light(energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.14)
	l.light_energy = energy
	l.omni_range = reach
	l.light_volumetric_fog_energy = 0.0
	_fire_root.add_child(l)
	return l


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 1
	add_child(_overlay)
	_white = ColorRect.new()
	_white.color = Color(1.0, 0.96, 0.86, 0.0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_white)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 96)
		if not top:
			bar.offset_top = -96.0
		_overlay.add_child(bar)
		_bars.append(bar)


# ---------------------------------------------------------------- inside the tunnel
func _advance_tunnel(delta: float) -> void:
	_t += delta
	_speed = lerpf(SPEED_START, SPEED_END, smoothstep(0.0, SPEED_RAMP_TIME, _t))
	_s += _speed * delta
	if _s >= _length():
		_start_space()
		return
	var progress := (_s - _s0) / (_length() - _s0)
	var surge := sin(_t * 5.0) * 4.0
	var gap := lerpf(GAP_START, GAP_END, pow(progress, 0.8)) + surge * (1.0 - progress)
	_fire_s = maxf(_s - gap, 0.0)
	_move_ship()
	_move_fire()
	_spawn_sparks(delta)
	_tunnel_camera(progress, gap)
	_white.color.a = smoothstep(_length() - WHITEOUT_DISTANCE, _length() - 4.0, _s)
	Sfx.loop("fire_roar", lerpf(-12.0, -3.0, progress))


func _move_ship() -> void:
	var forward := _dir_at(_s)
	var up := _up_at(_s)
	# Bank into upcoming bends, plus a nervous weave while the blast closes in.
	var ahead := _dir_at(_s + 26.0)
	var turn := forward.cross(ahead).dot(up)
	var bank := clampf(turn * 2.2, -1.1, 1.1) + sin(_t * 6.0) * 0.08
	var xf := Transform3D(Basis.looking_at(forward, up).rotated(forward, -bank), _point(_s))
	var blend := smoothstep(0.0, BLEND_TIME, _t)
	_player.global_transform = _start_xf.interpolate_with(xf, blend) if blend < 1.0 else xf


func _move_fire() -> void:
	var flicker := 1.0 + sin(_t * 41.0) * 0.12 + sin(_t * 23.0) * 0.1
	for i in _blobs.size():
		_place_blob(i, _point(_fire_s - float(i) * 9.0))
	_particles.global_position = _point(_fire_s)
	_front_light.global_position = _point(_fire_s + 7.0)
	_front_light.light_energy = 30.0 * flicker
	_rear_light.global_position = _point(_fire_s - 30.0)


func _place_blob(i: int, at: Vector3) -> void:
	var blob := _blobs[i]
	blob.global_position = at
	blob.scale = Vector3.ONE * (1.0 + sin(_t * 9.0 + i * 1.7) * 0.09) * (1.0 - float(i) * 0.03)
	blob.rotation = Vector3(_t * 0.7 + i, _t * 1.1, i * 2.0)


func _spawn_sparks(delta: float) -> void:
	_spark_cd -= delta
	if _spark_cd > 0.0:
		return
	_spark_cd = randf_range(0.05, 0.12)
	var s := _s + randf_range(25.0, 110.0)
	var forward := _dir_at(s)
	var up := _up_at(s)
	var side := forward.cross(up).normalized()
	var a := randf() * TAU
	var offset := (side * cos(a) + up * sin(a)) * 4.2
	Fx.sparks(_point(s) + offset, -offset.normalized(), Color(1.0, 0.6, 0.2))


## Three shots, each used once: behind the ship, ahead of it looking back, then the final dive.
func _tunnel_camera(progress: float, gap: float) -> void:
	var cam := _player.cam
	var up := _up_at(_s)
	var forward := _dir_at(_s)
	var side := forward.cross(up).normalized()
	var ship := _point(_s)
	var at: Vector3
	var target: Vector3
	if progress < 0.25:
		at = _point(_s - 15.0) + _up_at(_s - 15.0) * 3.0
		target = _point(_s + 30.0)
	elif progress < 0.78:
		at = _point(_s + 14.0) + _up_at(_s + 14.0) * 1.1 + side * 1.2
		target = ship - forward * (gap * 0.3)
	else:
		at = _point(_s - 10.0) + _up_at(_s - 10.0) * 2.0
		target = _point(_s + 60.0)
	var danger := 1.0 - clampf(gap / GAP_START, 0.0, 1.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.05 + danger * 0.4)
	var look_up := up if absf((target - at).normalized().dot(up)) < 0.95 else forward
	cam.look_at_from_position(at + jitter, target, look_up)
	cam.fov = lerpf(72.0, 92.0, danger)


# ---------------------------------------------------------------- out in space
func _start_space() -> void:
	_in_space = true
	Sfx.stop_loop("alarm")
	Game.level.enter_space()
	_player.cam.far = 4000.0
	_player.cam.fov = 58.0
	_player.headlight.visible = false
	_white.color.a = 1.0
	_asteroid = load(asteroid_model(level_id(Game.level_index))).instantiate()
	Mats.apply(_asteroid)
	add_child(_asteroid)
	for mi in _asteroid.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		for i in 8:
			_asteroid_extent = maxf(_asteroid_extent, box.get_endpoint(i).length())
	_asteroid.global_position = SPACE_ORIGIN
	_mouth = SPACE_ORIGIN + Vector3.FORWARD * ASTEROID_RADIUS * 0.95
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24.0, 118.0, 0.0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.95, 0.86)
	add_child(sun)
	_blast = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	# Dimmer than the tunnel fire: this one fills the screen and would burn out to white.
	var blast_mat := _fire_mat.duplicate() as ShaderMaterial
	blast_mat.set_shader_parameter("heat", 0.42)
	sphere.material = blast_mat
	sphere.radius = 1.0
	sphere.height = 2.0
	_blast.mesh = sphere
	_blast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blast.visible = false
	add_child(_blast)
	_blast.global_position = SPACE_ORIGIN
	_blast_light = OmniLight3D.new()
	_blast_light.light_color = Color(1.0, 0.55, 0.2)
	_blast_light.light_energy = 0.0
	_blast_light.omni_range = 2500.0
	_blast_light.omni_attenuation = 0.4
	add_child(_blast_light)
	_blast_light.global_position = SPACE_ORIGIN
	_debris = _make_debris()


func _make_debris() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = ASTEROID_RADIUS * 0.7
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 90.0
	pm.initial_velocity_max = 330.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 3.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	var rock := SphereMesh.new()
	rock.radial_segments = 6
	rock.rings = 3
	rock.radius = 5.0
	rock.height = 8.0
	rock.material = Mats.theme_rock(level_id(Game.level_index))
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 3.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.process_material = pm
	p.draw_pass_1 = rock
	p.visibility_aabb = AABB(Vector3.ONE * -2000, Vector3.ONE * 4000)
	add_child(p)
	p.global_position = SPACE_ORIGIN
	return p


func _advance_space(delta: float) -> void:
	_space_t += delta
	if _space_t >= SPACE_DURATION:
		_finish()
		return
	var away := Vector3.FORWARD
	var dist := 8.0 + SPACE_SPEED * _space_t
	var ship_at := _mouth + away * dist
	var roll := _space_t * 1.5
	_player.global_transform = Transform3D(Basis.looking_at(away, Vector3.UP).rotated(away, -roll), ship_at)

	# The blast chases the ship out of the mouth until the asteroid itself goes.
	var front := maxf(dist - 34.0, 0.0)
	for i in _blobs.size():
		_place_blob(i, _mouth + away * maxf(front - float(i) * 9.0, 0.0))
	_particles.global_position = _mouth + away * front
	_front_light.global_position = _mouth + away * (front + 7.0)
	_rear_light.global_position = _mouth

	_space_blast()
	_space_camera(ship_at, away)
	var flash := 1.0 - clampf(_space_t / FLASH_FADE_TIME, 0.0, 1.0)
	var final_fade := smoothstep(SPACE_DURATION - FINAL_FADE_TIME, SPACE_DURATION, _space_t)
	_white.color.a = maxf(flash, final_fade)
	Sfx.loop("fire_roar", lerpf(-3.0, -22.0, clampf(_space_t / SPACE_DURATION, 0.0, 1.0)))


func _space_blast() -> void:
	var since := _space_t - BLAST_DELAY
	if since < 0.0:
		return
	if not _blasted:
		_blasted = true
		_blast.visible = true
		_debris.emitting = true
		Sfx.play("explode_big", null, 8.0, 0.5)
	var grow := clampf(since / BLAST_GROW_TIME, 0.0, 1.0)
	var radius := lerpf(ASTEROID_RADIUS * 0.5, BLAST_END_RADIUS, 1.0 - pow(1.0 - grow, 2.0))
	_blast.scale = Vector3.ONE * radius
	_blast_light.light_energy = 60.0 * (1.0 - grow * 0.5)
	# Hidden once the fireball has swallowed it, leaving only flying rubble.
	_asteroid.visible = radius < maxf(ASTEROID_RADIUS * 1.1, _asteroid_extent)


## Two shots: from out front as the ship bursts past, then flying ahead of it, looking back.
func _space_camera(ship_at: Vector3, away: Vector3) -> void:
	var cam := _player.cam
	var at: Vector3
	var target: Vector3
	if _space_t < FLYBY_SHOT_TIME:
		at = _mouth + away * 165.0 + Vector3.RIGHT * 26.0 + Vector3.UP * 9.0
		target = ship_at
	else:
		at = ship_at + away * 24.0 + Vector3.RIGHT * 7.0 + Vector3.UP * 3.5
		target = ship_at - away * 40.0
	cam.look_at_from_position(at, target, Vector3.UP)


func _finish() -> void:
	_done = true
	_white.color.a = 1.0
	for bar in _bars:
		bar.visible = false
	_fire_root.visible = false
	Sfx.stop_loop("fire_roar")
	Game.end_run(true, "You outran the blast with %d seconds on the clock." % int(Game.escape_left))
