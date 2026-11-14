class_name Reactor
extends StaticBody3D
## The mine's power core. It defends itself; killing it starts the escape timer.

const MODEL_SCALE := 2.0
const MAX_HP := 1100.0
const NOVA_DAMAGE := 10.0
## Heat haze shows within this range and fades out as the ship gets right up close.
const HAZE_RANGE := 160.0
const HAZE_NEAR := 16.0

var model_scale := MODEL_SCALE
var max_hp := MAX_HP
var fires_novas := true
var hp := MAX_HP
var _rings: Array[Node3D] = []
var _core: Node3D
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _nova_cd := 6.0
var _dead := false
var _flash := 0.0
var _haze: MeshInstance3D
var _haze_mat: ShaderMaterial
var _haze_strength := 0.006


func _ready() -> void:
	hp = max_hp
	var size_factor := model_scale / MODEL_SCALE
	add_to_group("enemy")
	collision_layer = Game.ENEMY | Game.WORLD
	collision_mask = 0
	var model: Node3D = load("res://assets/models/reactor.glb").instantiate()
	Mats.apply(model)
	model.scale = Vector3.ONE * model_scale
	add_child(model)
	for i in 3:
		_rings.append(model.find_child("Ring%d" % i, true, false))
	_core = model.find_child("Core", true, false)
	_core_mat = Mats.unique_glow(model, "glow_core")
	var sphere := SphereShape3D.new()
	sphere.radius = 6.6 * size_factor
	var s := CollisionShape3D.new()
	s.shape = sphere
	add_child(s)
	for sy: float in [-1.0, 1.0]:
		var cyl := CylinderShape3D.new()
		cyl.radius = 15.0 * size_factor
		cyl.height = 30.0 * size_factor
		var c := CollisionShape3D.new()
		c.shape = cyl
		c.position = Vector3(0, sy * 36.0 * size_factor, 0)
		add_child(c)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 1.0, 0.9)
	_light.light_energy = 9.0
	_light.omni_range = 70.0
	_light.shadow_enabled = Settings.uses_shadows()
	Settings.settings_changed.connect(_on_settings_changed)
	add_child(_light)
	_hum = Sfx.positional_loop("reactor_hum", self, 40.0, 2.0)
	_build_haze(size_factor)


func _build_haze(size_factor: float) -> void:
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = preload("res://assets/shaders/heat_haze.gdshader")
	_haze_mat.set_shader_parameter("radius", 26.0 * size_factor)
	_haze_mat.set_shader_parameter("pull", 12.0 * size_factor)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_haze = MeshInstance3D.new()
	_haze.mesh = quad
	_haze.material_override = _haze_mat
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader places the disc itself, so culling must not use the 2 m quad.
	_haze.extra_cull_margin = 40.0 * size_factor
	add_child(_haze)
	_update_haze()


## Off on low quality, and hidden when far away so the screen copy isn't paid for.
func _update_haze() -> void:
	var p := Game.player
	var dist := HAZE_RANGE
	if p != null:
		dist = p.global_position.distance_to(global_position)
	var fade := clampf((dist - HAZE_NEAR) / 12.0, 0.0, 1.0) * clampf((HAZE_RANGE - dist) / 40.0, 0.0, 1.0)
	_haze.visible = Settings.quality != Settings.Quality.LOW and fade > 0.01
	if _haze.visible:
		_haze_mat.set_shader_parameter("fade", fade)
		_haze_mat.set_shader_parameter("strength", _haze_strength)


func _on_settings_changed() -> void:
	_light.shadow_enabled = Settings.uses_shadows()


func can_be_locked() -> bool:
	return not _dead


func hp_ratio() -> float:
	return hp / max_hp


func _process(delta: float) -> void:
	_update_haze()
	if _dead:
		return
	# The core runs hotter, and shimmers harder, as it takes damage.
	_haze_strength = lerpf(0.006, 0.013, 1.0 - hp_ratio())
	var speed := 0.5 + (1.0 - hp_ratio()) * 3.0
	_rings[0].rotate_object_local(Vector3.UP, speed * delta)
	_rings[1].rotate_object_local(Vector3.UP, -speed * 1.5 * delta)
	_rings[2].rotate_object_local(Vector3.UP, speed * 2.2 * delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.003 + (1.0 - hp_ratio()) * 0.012))
	_core_mat.emission_energy_multiplier = 8.0 + pulse * 7.0 + _flash * 24.0
	_light.light_energy = 6.0 + pulse * 5.0 + _flash * 10.0
	var p := Game.player
	if not fires_novas or p == null or p.dead or p.is_cloaked() or p.global_position.distance_to(global_position) > 110.0:
		return
	_nova_cd -= delta
	if _nova_cd <= 0.0:
		_nova_cd = lerpf(6.0, 2.6, 1.0 - hp_ratio())
		_nova(p)


func _nova(p: Node3D) -> void:
	var aim: Vector3 = (p.global_position - global_position).normalized()
	var side := aim.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var up := side.cross(aim)
	for i in 12:
		var a := float(i) / 12.0 * TAU
		var dir := (aim + (side * cos(a) + up * sin(a)) * 0.26).normalized()
		Bolt.launch(global_position + dir * 8.0, dir, 58.0, NOVA_DAMAGE, Bolt.color_for_damage(NOVA_DAMAGE), Game.WORLD | Game.PLAYER, 1.8, self)
	Sfx.play("enemy_shot_heavy", global_position, 7.0, 0.7)


func take_damage(amount: float, _at: Vector3, _source: Object) -> void:
	if _dead:
		return
	hp -= amount
	_flash = 1.0
	Sfx.play("reactor_hit", global_position, -3.0, randf_range(0.9, 1.1))
	if hp <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	hp = 0.0
	remove_from_group("enemy")
	_hum.queue_free()
	_core.visible = false
	# What is left burns: the shimmer gets stronger, not weaker.
	_haze_strength = 0.022
	_light.light_color = Color(1.0, 0.3, 0.1)
	Game.trigger_core_failure(global_position)
