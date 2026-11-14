class_name Bolt
extends Node3D
## Energy bolt. Sweeps a ray along its path every tick, so it can't tunnel.

static var _mesh: CapsuleMesh
static var _mats: Dictionary = {}
## Only every LIGHT_EVERY-th bolt carries a light: a laser stream or a nova fan
## would otherwise spawn dozens of short-lived omni lights.
const LIGHT_EVERY := 3
static var _launched := 0

var velocity := Vector3.ZERO
var damage := 10.0
var color := Color.WHITE
var mask := 1
var life := 3.0
var shooter: Object
var bounces := 0
var _query: PhysicsRayQueryParameters3D


static func launch(at: Vector3, direction: Vector3, speed: float, dmg: float, col: Color, hit_mask: int, scale_factor := 1.0, source: Object = null, bounce_count := 0) -> Bolt:
	var b := Bolt.new()
	b.velocity = direction.normalized() * speed
	b.damage = dmg
	b.color = col
	b.mask = hit_mask
	b.shooter = source
	b.bounces = bounce_count
	b.scale = Vector3.ONE * scale_factor
	b.position = Game.level.to_local(at)
	Game.level.add_child(b)
	return b


## Laser colour by how hard the shot hits, the same scale for player and robots.
static func color_for_damage(damage: float) -> Color:
	for i in Player.LASER_DAMAGE.size():
		if damage <= Player.LASER_DAMAGE[i]:
			return Player.LASER_COLORS[i]
	return Player.LASER_COLORS[-1]


func _ready() -> void:
	if _mesh == null:
		_mesh = CapsuleMesh.new()
		_mesh.radius = 0.14
		_mesh.height = 3.4
		_mesh.radial_segments = 8
		_mesh.rings = 2
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r * 2.4, color.g * 2.4, color.b * 2.4)
		m.disable_receive_shadows = true
		_mats[key] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(90, 0, 0)
	add_child(mi)
	_launched += 1
	if _launched % LIGHT_EVERY == 0:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.0
		light.omni_range = 12.0
		light.light_volumetric_fog_energy = 0.0
		add_child(light)
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	if _query == null:
		_query = PhysicsRayQueryParameters3D.create(from, to, mask)
	_query.from = from
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = to
		return
	if bounces > 0 and hit.collider.collision_layer == Game.WORLD:
		if hit.collider.has_method("take_damage") and is_instance_valid(shooter):
			hit.collider.take_damage(damage, hit.position, shooter)
		bounces -= 1
		velocity = velocity.bounce(hit.normal)
		Sfx.play("prism_bounce", hit.position, -4.0, randf_range(0.9, 1.15))
		global_position = hit.position + hit.normal * 0.2
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
		return
	# The shooter may have been destroyed while this bolt was in flight.
	var source: Object = shooter if is_instance_valid(shooter) else null
	if hit.collider != source and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(damage, hit.position, source)
	# Hits on the player happen beside the camera; the HUD flash and shake cover those.
	if hit.collider != Game.player:
		Fx.sparks(hit.position, hit.normal, color)
		var struck_robot: bool = hit.collider is Robot or hit.collider is Reactor or hit.collider is Mine
		Sfx.play("hit" if struck_robot else "hit_wall", hit.position, -4.0, randf_range(0.8, 1.3))
	queue_free()
