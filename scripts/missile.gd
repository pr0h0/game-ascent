class_name Missile
extends Node3D
## Homing missile with limited turn rate and blast damage on impact.

const SPEED := 82.0
const DAMAGE := 90.0
const MODELS := {
	"homing": "res://assets/models/missile.glb", "cluster": "res://assets/models/missile_cluster.glb",
	"bunker": "res://assets/models/missile_bunker.glb", "emp": "res://assets/models/missile_emp.glb",
}

var velocity := Vector3.ZERO
var target: Node3D
var mask := 1
var turn_rate := 3.4
var damage := DAMAGE
var from_player := true
var kind := "homing"
var life := 6.0
var _query: PhysicsRayQueryParameters3D
## One trail material for every missile; a swarm launches eight at once.
static var _trail_mat: ParticleProcessMaterial


static func launch(at: Vector3, direction: Vector3, tracked: Node3D, hit_mask: int, is_player: bool, speed := SPEED, dmg := DAMAGE, missile_kind := "homing") -> Missile:
	var m := Missile.new()
	m.velocity = direction.normalized() * speed
	m.target = tracked
	m.mask = hit_mask
	m.from_player = is_player
	m.damage = dmg
	m.kind = missile_kind
	# Placed before add_child so _ready (orientation, launch sound) sees the real spot.
	m.position = Game.level.to_local(at)
	Game.level.add_child(m)
	return m


func _ready() -> void:
	var model: Node3D = load(MODELS.get(kind, MODELS["homing"])).instantiate()
	Mats.apply(model)
	add_child(model)
	var trail := GPUParticles3D.new()
	trail.amount = 60
	trail.lifetime = 0.8
	trail.local_coords = false
	if _trail_mat == null:
		_trail_mat = ParticleProcessMaterial.new()
		_trail_mat.spread = 12.0
		_trail_mat.initial_velocity_min = 0.5
		_trail_mat.initial_velocity_max = 2.5
		_trail_mat.gravity = Vector3.ZERO
		_trail_mat.direction = Vector3(0, 0, 1)
		_trail_mat.color_ramp = Fx._ramp([[0.0, Color(5, 2.2, 0.5, 0.8)], [0.25, Color(0.6, 0.4, 0.3, 0.32)], [1.0, Color(0.2, 0.2, 0.2, 0)]])
		_trail_mat.scale_curve = Fx._curve([[0.0, 0.3], [1.0, 1.0]])
	trail.process_material = _trail_mat
	trail.draw_pass_1 = Fx._quad(Fx._sprite("fx_puff"), 1.3)
	trail.position = Vector3(0, 0, 1.0)
	trail.visibility_aabb = AABB(Vector3.ONE * -60, Vector3.ONE * 120)
	add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.55, 0.2)
	light.light_energy = 3.5
	light.omni_range = 18.0
	light.position = Vector3(0, 0, 1.0)
	add_child(light)
	_orient()
	Sfx.play({"cluster": "missile_cluster", "bunker": "missile_bunker", "emp": "missile_cluster"}.get(kind, "missile"), global_position, 0.0, randf_range(0.95, 1.05))


func _orient() -> void:
	var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
	look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_detonate(global_position, Vector3.ZERO)
		return
	if is_instance_valid(target):
		var aim_at: Vector3 = target.global_position
		var want := (aim_at - global_position).normalized()
		var cur := velocity.normalized()
		var angle := cur.angle_to(want)
		if angle > 0.001:
			velocity = cur.slerp(want, minf(1.0, turn_rate * delta / angle)).normalized() * velocity.length()
			_orient()
	var from := global_position
	var to := from + velocity * delta
	if _query == null:
		_query = PhysicsRayQueryParameters3D.create(from, to, mask)
	_query.from = from
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = to
	else:
		if hit.collider.has_method("take_damage"):
			hit.collider.take_damage(damage, hit.position, self)
		_detonate(hit.position, hit.normal, hit.collider)


func _detonate(at: Vector3, _normal: Vector3, direct: Object = null) -> void:
	if kind == "emp":
		Weapons.emp_pulse(at)
		queue_free()
		return
	if kind == "cluster":
		_scatter_bomblets(at)
	Fx.explosion(at, 9.0 if kind == "bunker" else 5.0, kind == "bunker")
	if from_player:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e == direct or not e.has_method("take_damage"):
				continue
			var d: float = e.global_position.distance_to(at)
			if d < 16.0:
				e.take_damage(damage * 0.5 * (1.0 - d / 16.0), at, self)
	elif Game.player != null and direct != Game.player:
		var d := Game.player.global_position.distance_to(at)
		if d < 12.0:
			Game.player.take_damage(damage * 0.5 * (1.0 - d / 12.0), at, self)
	queue_free()


func _scatter_bomblets(at: Vector3) -> void:
	var bomblet := Weapons.secondary_damage("cluster_bomblet") if from_player else Weapons.CLUSTER_BOMBLET_DAMAGE
	for i in Weapons.CLUSTER_BOMBLETS:
		var spot := at + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(5.0, 24.0)
		get_tree().create_timer(0.1 + i * 0.07).timeout.connect(Missile._bomblet.bind(spot, bomblet))


static func _bomblet(spot: Vector3, dmg := Weapons.CLUSTER_BOMBLET_DAMAGE) -> void:
	if Game.level == null:
		return
	Fx.explosion(spot, 3.0)
	Weapons.splash_enemies(spot, 10.0, dmg, Game.player)
