class_name Fx
extends RefCounted
## Explosions, sparks and flashes. Materials are shared and emitters are pooled per
## level, so a firefight reuses a fixed set of particle systems instead of making new ones.

## Particle counts are scaled by this at each graphics quality (LOW, MEDIUM, HIGH).
const QUALITY_SCALE := [0.4, 0.7, 1.0]
## Flash lights alive at once at each quality; the oldest one is reused past this.
const MAX_FLASH_LIGHTS := [1, 3, 5]
const MAX_SPARK_LIGHTS := [0, 2, 3]
## Size classes: small arms, robots, heavy robots, the reactor and the boss.
const CLASS_LIMITS := [4.5, 10.0, 18.0]
const CLASS_SIZE := [3.5, 7.0, 13.0, 24.0]
## Pooled emitters per layer and size class. Big blasts are rare; small ones are not.
const CLASS_POOL := [8, 6, 5, 4]
const SPARK_POOL := 14

static var _cache: Dictionary = {}
static var _sphere: SphereMesh
## Level instance id -> {pool key -> Array of emitters or lights}.
static var _pools: Dictionary = {}


static func quality_scale() -> float:
	return QUALITY_SCALE[clampi(Settings.quality, 0, 2)]


static func _sprite(tex_name: String, additive := true) -> StandardMaterial3D:
	var key := tex_name + str(additive)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = load("res://assets/textures/%s.png" % tex_name) if tex_name.begins_with("fx_") else _generated(tex_name)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


## Textures made on the spot: a soft round core, a thin ring for the shockwave and a
## lumpy cloud whose detail keeps fire and smoke from reading as flat discs.
static func _generated(tex_name: String) -> Texture2D:
	if tex_name == "billow":
		return _billow()
	var g := Gradient.new()
	match tex_name:
		"ring":
			g.offsets = PackedFloat32Array([0.0, 0.62, 0.84, 0.93, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
		_:
			g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


static func _billow() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.045
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var lump := 0.5 + 0.5 * noise.get_noise_2d(x, y)
			var a := clampf((1.0 - smoothstep(0.25, 1.0, d + (0.5 - lump) * 0.45)) * (0.45 + lump * 0.75), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.85 + lump * 0.15, 0.85 + lump * 0.15, 0.85 + lump * 0.15, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Two crossed thin quads that stretch along a particle's travel: a cheap spark streak.
static func _streak(length: float, width: float) -> Array:
	var key := "streak%.2f_%.2f" % [length, width]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = load("res://assets/textures/fx_streak.png")
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	var meshes := []
	for o in [PlaneMesh.FACE_Z, PlaneMesh.FACE_X]:
		var q := QuadMesh.new()
		q.orientation = o
		q.size = Vector2(width, length)
		q.material = m
		meshes.append(q)
	_cache[key] = meshes
	return meshes


static func _ramp(stops: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _quad(mat: Material, size: float) -> QuadMesh:
	# The quad is built at the snapped size, so every caller sharing a key gets the same mesh.
	var snapped := maxf(snappedf(size, 0.05), 0.05)
	var key := "quad%d_%.2f" % [mat.get_instance_id(), snapped]
	if _cache.has(key):
		return _cache[key]
	var q := QuadMesh.new()
	_cache[key] = q
	q.size = Vector2.ONE * snapped
	q.material = mat
	return q


static func _process_mat(key: String, speed: Vector2, damping: float, ramp: Array, curve: Array, gravity := Vector3.ZERO, spread := 180.0) -> ParticleProcessMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.damping_min = damping
	m.damping_max = damping * 1.5
	m.gravity = gravity
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.color_ramp = _ramp(ramp)
	m.scale_curve = _curve(curve)
	_cache[key] = m
	return m


# --- Pools ---------------------------------------------------------------------
static func _level_pools(world: Node3D) -> Dictionary:
	var id := world.get_instance_id()
	if not _pools.has(id):
		for old: int in _pools.keys():
			if not is_instance_id_valid(old):
				_pools.erase(old)
		_pools[id] = {}
	return _pools[id]


## A free emitter for this layer, a new one while under the cap, or else the one
## that finished (or will finish) soonest. Nothing is ever freed during play.
static func _emitter(world: Node3D, key: String, cap: int, count: int, life: float, mat: ParticleProcessMaterial, draws: Array, reach: float) -> GPUParticles3D:
	var pools := _level_pools(world)
	var list: Array = pools.get(key, [])
	pools[key] = list
	var now := Time.get_ticks_msec()
	var oldest: GPUParticles3D = null
	for p: GPUParticles3D in list:
		if int(p.get_meta("free_at")) <= now:
			return p
		if oldest == null or int(p.get_meta("free_at")) < int(oldest.get_meta("free_at")):
			oldest = p
	if list.size() >= cap and oldest != null:
		return oldest
	var e := GPUParticles3D.new()
	e.amount = count
	e.lifetime = life
	e.one_shot = true
	e.explosiveness = 1.0
	e.emitting = false
	e.process_material = mat
	e.draw_passes = draws.size()
	for i in draws.size():
		e.set_draw_pass_mesh(i, draws[i])
	e.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.set_meta("free_at", 0)
	world.add_child(e)
	list.append(e)
	return e


static func _fire(e: GPUParticles3D, at: Vector3, ratio: float, up := Vector3.UP) -> void:
	e.global_transform = Transform3D(_basis_up(up), at)
	e.amount_ratio = clampf(ratio, 0.05, 1.0)
	e.set_meta("free_at", Time.get_ticks_msec() + int((e.lifetime + 0.15) * 1000.0))
	e.restart()


static func _basis_up(up: Vector3) -> Basis:
	var n := up.normalized()
	if n.length_squared() < 0.5 or n.dot(Vector3.UP) > 0.999:
		return Basis.IDENTITY
	if n.dot(Vector3.UP) < -0.999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, n))


## A short-lived light from a small pool; the light that has been lit longest is reused.
static func _flash_light(world: Node3D, key: String, cap: int, at: Vector3, color: Color, energy: float, reach: float, fade: float) -> void:
	if cap <= 0:
		return
	var pools := _level_pools(world)
	var list: Array = pools.get(key, [])
	pools[key] = list
	var light: OmniLight3D = null
	var now := Time.get_ticks_msec()
	for l: OmniLight3D in list:
		if int(l.get_meta("free_at")) <= now:
			light = l
			break
	if light == null and list.size() < cap:
		light = OmniLight3D.new()
		light.shadow_enabled = false
		light.omni_attenuation = 1.4
		world.add_child(light)
		list.append(light)
	if light == null:
		light = list[0]
		list.push_back(list.pop_front())
	if light.has_meta("tween"):
		var old: Tween = light.get_meta("tween")
		if old.is_valid():
			old.kill()
	light.visible = true
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.global_position = at
	light.set_meta("free_at", now + int(fade * 1000.0) + 30)
	var t := light.create_tween()
	t.tween_property(light, "light_energy", 0.0, fade).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(light.hide)
	light.set_meta("tween", t)


# --- Explosions -------------------------------------------------------------------
static func _size_class(size: float) -> int:
	for i in CLASS_LIMITS.size():
		if size < CLASS_LIMITS[i]:
			return i
	return CLASS_LIMITS.size()


## Fireball, a white-hot core, a shockwave ring, fast sparks, slow embers,
## tumbling hull chunks and smoke that hangs about after the light is gone.
static func explosion(at: Vector3, size: float, big_sound := false) -> void:
	var world: Node3D = Game.level
	if world == null:
		return
	var c := _size_class(size)
	var nominal: float = CLASS_SIZE[c]
	var speed: float = [0.75, 1.0, 1.45, 2.0][c]
	var q := quality_scale()
	var cap: int = CLASS_POOL[c]
	var tag := "_%d" % c
	# Within a class, a smaller blast just uses fewer of the particles.
	var fill := clampf(size / nominal, 0.55, 1.0) * q
	var reach := nominal * 8.0

	var core := _process_mat("core" + tag, Vector2(0, 1), 1.0,
		[[0.0, Color(2.6, 2.3, 1.9, 1)], [0.35, Color(2.2, 1.2, 0.45, 0.7)], [1.0, Color(0.8, 0.2, 0.03, 0)]],
		[[0.0, 0.4], [0.25, 1.0], [1.0, 1.1]])
	_fire(_emitter(world, "core" + tag, cap, 1, 0.2, core, [_quad(_sprite("core"), minf(nominal * 1.3, 24.0))], reach), at, 1.0)

	var fire := _process_mat("fire" + tag, Vector2(4, 16) * speed, 9.0,
		[[0.0, Color(2.4, 1.7, 0.9, 1)], [0.15, Color(2.2, 0.85, 0.18, 0.95)], [0.45, Color(1.2, 0.3, 0.05, 0.7)], [0.75, Color(0.25, 0.06, 0.02, 0.4)], [1.0, Color(0.05, 0.02, 0.01, 0)]],
		[[0.0, 0.3], [0.3, 1.0], [1.0, 1.3]])
	fire.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = nominal * 0.25
	fire.scale_min = 0.5
	fire.scale_max = 1.5
	fire.hue_variation_min = -0.025
	fire.hue_variation_max = 0.02
	fire.angular_velocity_min = -90.0
	fire.angular_velocity_max = 90.0
	_fire(_emitter(world, "fire" + tag, cap, [14, 22, 30, 40][c], 0.9, fire, [_quad(_sprite("billow"), minf(nominal * 1.35, 22.0))], reach), at, fill)

	var ring := _process_mat("ring" + tag, Vector2.ZERO, 0.0,
		[[0.0, Color(2.0, 1.2, 0.6, 0.6)], [0.5, Color(1.3, 0.55, 0.2, 0.25)], [1.0, Color(0.5, 0.15, 0.03, 0)]],
		[[0.0, 0.05], [0.35, 0.75], [1.0, 1.0]])
	ring.scale_min = 1.0
	ring.scale_max = 1.0
	_fire(_emitter(world, "ring" + tag, cap, 1, 0.4, ring, [_quad(_sprite("ring"), nominal * 4.5)], reach), at, 1.0)

	var sparks := _process_mat("sparks" + tag, Vector2(24, 70) * speed, 4.0,
		[[0.0, Color(5, 4.4, 3, 1)], [0.5, Color(4, 1.6, 0.3, 1)], [1.0, Color(1, 0.1, 0, 0)]],
		[[0.0, 1.0], [1.0, 0.2]], Vector3(0, -9, 0))
	sparks.particle_flag_align_y = true
	sparks.angle_min = 0.0
	sparks.angle_max = 0.0
	_fire(_emitter(world, "sparks" + tag, cap, [18, 28, 40, 52][c], 0.7, sparks, _streak(1.2 + nominal * 0.1, 0.12 + nominal * 0.01), reach), at, fill)

	if q > 0.5:
		var embers := _process_mat("embers" + tag, Vector2(3, 15) * speed, 1.6,
			[[0.0, Color(5, 3, 1.2, 1)], [0.3, Color(4, 1.4, 0.3, 1)], [0.7, Color(2.5, 0.5, 0.08, 0.9)], [1.0, Color(0.6, 0.1, 0, 0)]],
			[[0.0, 1.0], [0.8, 0.8], [1.0, 0.0]], Vector3(0, -3.0, 0))
		embers.scale_min = 0.5
		embers.scale_max = 1.3
		embers.hue_variation_min = -0.03
		embers.hue_variation_max = 0.03
		embers.lifetime_randomness = 0.5
		_fire(_emitter(world, "embers" + tag, cap, [8, 14, 22, 30][c], 2.4, embers, [_quad(_sprite("fx_glow"), 0.3 + nominal * 0.02)], reach), at, fill)

	var debris := _process_mat("debris" + tag, Vector2(9, 32) * speed, 1.0, [[0.0, Color.WHITE], [1.0, Color.WHITE]], [[0.0, 1.0], [0.85, 1.0], [1.0, 0.0]], Vector3(0, -6, 0))
	debris.particle_flag_rotate_y = true
	debris.angular_velocity_min = -540.0
	debris.angular_velocity_max = 540.0
	debris.scale_min = 0.35
	debris.scale_max = 1.5
	debris.lifetime_randomness = 0.4
	_fire(_emitter(world, "debris" + tag, cap, [5, 9, 14, 20][c], 2.2, debris, [_chunk(c, false), _chunk(c, true)], reach), at, fill)

	var smoke := _process_mat("smoke" + tag, Vector2(2, 7) * speed, 3.5,
		[[0.0, Color(0.12, 0.1, 0.09, 0.0)], [0.12, Color(0.14, 0.125, 0.115, 0.78)], [0.6, Color(0.1, 0.095, 0.09, 0.5)], [1.0, Color(0.06, 0.06, 0.06, 0.0)]],
		[[0.0, 0.45], [1.0, 1.7]], Vector3(0, 0.8, 0))
	smoke.angular_velocity_min = -25.0
	smoke.angular_velocity_max = 25.0
	smoke.lifetime_randomness = 0.3
	_fire(_emitter(world, "smoke" + tag, cap, [5, 8, 12, 16][c], 2.8, smoke, [_quad(_sprite("billow", false), minf(nominal * 2.3, 30.0))], reach), at, fill)

	_flash_light(world, "blast_light", MAX_FLASH_LIGHTS[clampi(Settings.quality, 0, 2)], at, Color(1.0, 0.62, 0.3), 18.0, size * 9.0, 0.5)
	Sfx.play(_blast_sound(size, big_sound), at, 3.0 if big_sound else 0.0, randf_range(0.9, 1.1))
	if Game.player != null:
		var dist := Game.player.global_position.distance_to(at)
		Game.player.add_shake(clampf(size * 2.4 / maxf(dist, 4.0), 0.0, 1.0))


## Hull chunks: flat plates and chunky blocks, half glowing hot at their edges.
static func _chunk(size_class: int, hot: bool) -> Mesh:
	var key := "chunk%d%s" % [size_class, hot]
	if _cache.has(key):
		return _cache[key]
	var scale: float = [0.6, 1.0, 1.5, 2.2][size_class]
	var box := BoxMesh.new()
	if hot:
		box.size = Vector3(0.32, 0.26, 0.3) * scale
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.1, 0.09)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.36, 0.08)
		m.emission_energy_multiplier = 4.0
		m.roughness = 0.8
		box.material = m
	else:
		box.size = Vector3(0.55, 0.12, 0.4) * scale
		box.material = Mats.get_material("hull_dark")
	_cache[key] = box
	return box


static func _blast_sound(size: float, big: bool) -> String:
	if size >= 20.0:
		return "explode_boss"
	if big or size >= 9.0:
		return "explode_big" if size >= 10.0 else "explode_medium"
	return "explode_tiny" if size < 3.6 else "explode_small"


## Shockwave spheres kept per level, each with its own material (its alpha is tweened).
const SHOCKWAVE_POOL := 4
const SHOCKWAVE_TIME := 0.42


static func _shockwave(world: Node3D, at: Vector3, size: float, color := Color(1.4, 0.7, 0.3)) -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radial_segments = 24
		_sphere.rings = 12
	var pools := _level_pools(world)
	var list: Array = pools.get("shockwave", [])
	pools["shockwave"] = list
	var now := Time.get_ticks_msec()
	var mi: MeshInstance3D = null
	for m: MeshInstance3D in list:
		if int(m.get_meta("free_at")) <= now:
			mi = m
			break
	if mi == null and list.size() < SHOCKWAVE_POOL:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_FRONT
		mi = MeshInstance3D.new()
		mi.mesh = _sphere
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		list.append(mi)
	if mi == null:
		mi = list[0]
		list.push_back(list.pop_front())
	if mi.has_meta("tween"):
		var old: Tween = mi.get_meta("tween")
		if old.is_valid():
			old.kill()
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
	mi.visible = true
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.2
	mi.set_meta("free_at", now + int(SHOCKWAVE_TIME * 1000.0) + 30)
	var t := mi.create_tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * size * 5.0, SHOCKWAVE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, SHOCKWAVE_TIME)
	t.chain().tween_callback(mi.hide)
	mi.set_meta("tween", t)


## An expanding coloured sphere, for EMP blasts and singularity bursts.
static func pulse(at: Vector3, radius: float, color: Color) -> void:
	var world: Node3D = Game.level
	if world != null:
		_shockwave(world, at, radius / 5.0, color)


# --- Hit sparks ---------------------------------------------------------------------
## Streaks thrown off the struck surface, a pin-point flash, and for rock and
## steel walls a puff of dust; robots throw more and hotter sparks instead.
static func sparks(at: Vector3, normal: Vector3, color: Color) -> void:
	var world: Node3D = Game.level
	if world == null:
		return
	var q := quality_scale()
	var up := normal if normal.length_squared() > 0.5 else Vector3.UP
	var on_wall := _is_wall(world, at, up)
	var tint := Color(color.r * 3.0 + 1.0, color.g * 3.0 + 1.0, color.b * 3.0 + 1.0)
	var key := "hit" + color.to_html(false)
	var streak_mat: ParticleProcessMaterial = _cache.get(key)
	if streak_mat == null:
		streak_mat = _process_mat(key, Vector2(12, 40), 5.0,
			[[0.0, Color(tint, 1.0)], [0.5, Color(color * 2.5, 0.9)], [1.0, Color(color * 0.8, 0.0)]],
			[[0.0, 1.0], [1.0, 0.25]], Vector3(0, -14, 0), 62.0)
		streak_mat.particle_flag_align_y = true
		streak_mat.angle_min = 0.0
		streak_mat.angle_max = 0.0
		streak_mat.lifetime_randomness = 0.5
	var e := _emitter(world, "hit_streaks", SPARK_POOL, 16, 0.45, streak_mat, _streak(0.9, 0.1), 20.0)
	e.process_material = streak_mat
	_fire(e, at + up * 0.05, (0.7 if on_wall else 1.0) * q, up)

	var flash_key := "hitflash" + color.to_html(false)
	var flash_mat: ParticleProcessMaterial = _cache.get(flash_key)
	if flash_mat == null:
		flash_mat = _process_mat(flash_key, Vector2.ZERO, 0.0, [[0.0, Color(tint, 1.0)], [1.0, Color(color, 0.0)]], [[0.0, 1.0], [1.0, 0.4]])
	var f := _emitter(world, "hit_flash", SPARK_POOL, 1, 0.1, flash_mat, [_quad(_sprite("core"), 1.8)], 4.0)
	f.process_material = flash_mat
	_fire(f, at + up * 0.15, 1.0)

	if on_wall and q > 0.5:
		var dust := _process_mat("hit_dust", Vector2(1.5, 4.0), 3.0,
			[[0.0, Color(0.35, 0.32, 0.3, 0.0)], [0.15, Color(0.3, 0.28, 0.26, 0.35)], [1.0, Color(0.2, 0.19, 0.18, 0.0)]],
			[[0.0, 0.4], [1.0, 1.3]], Vector3(0, -0.6, 0), 50.0)
		_fire(_emitter(world, "hit_dust", SPARK_POOL, 3, 0.9, dust, [_quad(_sprite("billow", false), 1.4)], 8.0), at + up * 0.3, 1.0, up)

	_flash_light(world, "spark_light", MAX_SPARK_LIGHTS[clampi(Settings.quality, 0, 2)], at + up * 0.5, color, 4.0, 9.0, 0.14)


## Robots and the player are off the WORLD layer, so a short probe tells a wall hit apart.
static func _is_wall(world: Node3D, at: Vector3, up: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var probe := PhysicsRayQueryParameters3D.create(at + up * 0.4, at - up * 0.4, Game.WORLD)
	probe.hit_back_faces = true
	return not space.intersect_ray(probe).is_empty()
