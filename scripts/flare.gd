class_name Flare
extends Node3D
## A harmless burning light. Flies straight, sticks where it lands, and opens
## any door it hits that the player has the key for.

const SPEED := 130.0
const BURN_TIME := 14.0
const FADE_TIME := 2.0
const LIGHT_ENERGY := 5.5
const MAX_ACTIVE := 6
## Remaining burn after hitting a door, which is about to slide away.
const DOOR_BURN_TIME := 0.6

static var _active: Array[Flare] = []
static var _core_mat: StandardMaterial3D

var velocity := Vector3.ZERO
var life := BURN_TIME
var stuck := false
var _light: OmniLight3D
var _core: MeshInstance3D
var _query: PhysicsRayQueryParameters3D


static func launch(at: Vector3, direction: Vector3) -> Flare:
	_active = _active.filter(func(f): return is_instance_valid(f))
	while _active.size() >= MAX_ACTIVE:
		_active.pop_front().queue_free()
	var flare := Flare.new()
	flare.velocity = direction.normalized() * SPEED
	# Placed before add_child so the launch sound in _ready plays from the right spot.
	flare.position = Game.level.to_local(at)
	Game.level.add_child(flare)
	_active.append(flare)
	return flare


static func active_count() -> int:
	return _active.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size()


func _ready() -> void:
	if _core_mat == null:
		_core_mat = StandardMaterial3D.new()
		_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_core_mat.albedo_texture = load("res://assets/textures/fx_glow.png")
		_core_mat.albedo_color = Color(2.4, 1.9, 1.2)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.4
	quad.material = _core_mat
	_core = MeshInstance3D.new()
	_core.mesh = quad
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.82, 0.55)
	_light.light_energy = LIGHT_ENERGY
	_light.omni_range = 40.0
	_light.light_volumetric_fog_energy = 0.6
	add_child(_light)
	var sparks := GPUParticles3D.new()
	sparks.amount = 30
	sparks.lifetime = 0.6
	sparks.local_coords = false
	sparks.process_material = Fx._process_mat(
		"flare_sparks", Vector2(1, 7), 2.0,
		[[0.0, Color(3, 2.2, 1, 1)], [1.0, Color(1, 0.3, 0, 0)]],
		[[0.0, 1.0], [1.0, 0.1]], Vector3(0, -7, 0)
	)
	sparks.draw_pass_1 = Fx._quad(Fx._sprite("fx_glow"), 0.2)
	sparks.visibility_aabb = AABB(Vector3.ONE * -30, Vector3.ONE * 60)
	add_child(sparks)
	Sfx.play("flare", global_position, -6.0)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if stuck:
		return
	var from := global_position
	var to := from + velocity * delta
	# World layer only: flares pass through robots and never hurt anything.
	if _query == null:
		_query = PhysicsRayQueryParameters3D.create(from, to, Game.WORLD)
	_query.from = from
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = to
		return
	stuck = true
	global_position = hit.position + hit.normal * 0.3
	if hit.collider is Door:
		hit.collider.take_damage(0.0, hit.position, Game.player)
		if hit.collider.is_opening():
			life = minf(life, DOOR_BURN_TIME)


func _process(_delta: float) -> void:
	var flicker := 0.82 + 0.18 * sin(Time.get_ticks_msec() * 0.05 + get_instance_id())
	var fade := clampf(life / FADE_TIME, 0.0, 1.0)
	_light.light_energy = LIGHT_ENERGY * flicker * fade
	_core.scale = Vector3.ONE * (0.75 + 0.25 * flicker) * maxf(fade, 0.05)
