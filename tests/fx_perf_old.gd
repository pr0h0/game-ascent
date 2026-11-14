extends RefCounted
## Explosions, sparks and flashes. Materials are cached so effects stay cheap.

static var _cache: Dictionary = {}
static var _sphere: SphereMesh


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
	m.albedo_texture = load("res://assets/textures/%s.png" % tex_name)
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


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


static func _particles(parent: Node3D, at: Vector3, count: int, life: float, mat: ParticleProcessMaterial, draw: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.process_material = mat
	p.draw_pass_1 = draw
	p.visibility_aabb = AABB(Vector3.ONE * -80, Vector3.ONE * 160)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)
	return p


static func _quad(mat: Material, size: float) -> QuadMesh:
	var key := "quad%d_%.1f" % [mat.get_instance_id(), snappedf(size, 0.5)]
	if _cache.has(key):
		return _cache[key]
	var q := QuadMesh.new()
	_cache[key] = q
	q.size = Vector2.ONE * size
	q.material = mat
	return q


static func _process_mat(key: String, speed: Vector2, damping: float, ramp: Array, curve: Array, gravity := Vector3.ZERO) -> ParticleProcessMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 180.0
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


static func explosion(at: Vector3, size: float, big_sound := false) -> void:
	var world: Node3D = Game.level
	if world == null:
		return
	var fire := _process_mat(
		"fire", Vector2(3, 14), 12.0,
		[[0.0, Color(5, 4.2, 3, 1)], [0.25, Color(4.5, 1.8, 0.3, 0.95)], [0.65, Color(0.9, 0.2, 0.03, 0.45)], [1.0, Color(0.1, 0.02, 0, 0)]],
		[[0.0, 0.25], [0.3, 1.0], [1.0, 1.3]]
	)
	var sparks := _process_mat(
		"sparks", Vector2(22, 66), 6.0,
		[[0.0, Color(6, 5, 3, 1)], [0.6, Color(5, 1.8, 0.3, 1)], [1.0, Color(1, 0.1, 0, 0)]],
		[[0.0, 1.0], [1.0, 0.15]]
	)
	var smoke := _process_mat(
		"smoke", Vector2(2, 8), 4.0,
		[[0.0, Color(0.08, 0.07, 0.07, 0.0)], [0.2, Color(0.1, 0.09, 0.09, 0.55)], [1.0, Color(0.05, 0.05, 0.05, 0.0)]],
		[[0.0, 0.5], [1.0, 1.6]]
	)
	var debris := _process_mat("debris", Vector2(10, 36), 1.2, [[0.0, Color.WHITE], [1.0, Color.WHITE]], [[0.0, 1.0], [0.8, 1.0], [1.0, 0.0]], Vector3(0, -4, 0))
	# Big soft sprites filling the screen are the costliest thing the game draws.
	var n := clampf(size / 3.0, 0.8, 2.0)
	_particles(world, at, int(18 * n), 0.85, fire, _quad(_sprite("fx_puff"), minf(size * 2.0, 26.0)))
	_particles(world, at, int(36 * n), 0.9, sparks, _quad(_sprite("fx_glow"), 0.34 + size * 0.05))
	_particles(world, at, int(7 * n), 2.4, smoke, _quad(_sprite("fx_puff", false), minf(size * 2.6, 30.0)))
	var chunk_key := "chunk%.1f" % snappedf(clampf(size * 0.3, 0.5, 2.0), 0.5)
	if not _cache.has(chunk_key):
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.2, 0.34) * clampf(size * 0.3, 0.5, 2.0)
		box.material = Mats.get_material("hull_dark")
		_cache[chunk_key] = box
	var chunk: BoxMesh = _cache[chunk_key]
	_particles(world, at, int(10 * n), 1.8, debris, chunk)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.62, 0.3)
	flash.light_energy = 18.0
	flash.omni_range = size * 9.0
	world.add_child(flash)
	flash.global_position = at
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.5)
	tween.tween_callback(flash.queue_free)
	_shockwave(world, at, size)
	Sfx.play(_blast_sound(size, big_sound), at, 3.0 if big_sound else 0.0, randf_range(0.9, 1.1))
	if Game.player != null:
		var dist := Game.player.global_position.distance_to(at)
		Game.player.add_shake(clampf(size * 2.4 / maxf(dist, 4.0), 0.0, 1.0))


static func _blast_sound(size: float, big: bool) -> String:
	if size >= 20.0:
		return "explode_boss"
	if big or size >= 9.0:
		return "explode_big" if size >= 10.0 else "explode_medium"
	return "explode_tiny" if size < 3.6 else "explode_small"


static func _shockwave(world: Node3D, at: Vector3, size: float, color := Color(1.4, 0.7, 0.3)) -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radial_segments = 24
		_sphere.rings = 12
	var mesh := _sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	world.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.2
	var t := mi.create_tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE * size * 5.0, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.42)
	t.chain().tween_callback(mi.queue_free)


## An expanding coloured sphere, for EMP blasts and singularity bursts.
static func pulse(at: Vector3, radius: float, color: Color) -> void:
	var world: Node3D = Game.level
	if world != null:
		_shockwave(world, at, radius / 5.0, color)


static func sparks(at: Vector3, normal: Vector3, color: Color) -> void:
	var world: Node3D = Game.level
	if world == null:
		return
	var key := "hit" + color.to_html()
	var m: ParticleProcessMaterial
	if _cache.has(key):
		m = _cache[key]
	else:
		m = ParticleProcessMaterial.new()
		m.direction = Vector3.UP
		m.spread = 62.0
		m.initial_velocity_min = 8.0
		m.initial_velocity_max = 30.0
		m.damping_min = 8.0
		m.damping_max = 14.0
		m.scale_curve = _curve([[0.0, 1.0], [1.0, 0.0]])
		m.color = Color(color.r * 4.0, color.g * 4.0, color.b * 4.0)
		_cache[key] = m
	var p := _particles(world, at, 14, 0.42, m, _quad(_sprite("fx_glow"), 0.5))
	if normal.length_squared() > 0.5 and absf(normal.dot(Vector3.UP)) < 0.99:
		p.look_at(at + normal, Vector3.UP)
		p.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 4.0
	flash.omni_range = 9.0
	world.add_child(flash)
	flash.global_position = at + normal * 0.5
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.14)
	tween.tween_callback(flash.queue_free)
