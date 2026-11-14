class_name Sentry
extends StaticBody3D
## Wall turret: tracks the player over a hemisphere in front of its mount.

const MAX_HP := 70.0
const SHOT_DAMAGE := 10.0
const SCORE := 200
const REACTION := 0.9
const BOLT_SPEED := 62.0
const BODY_OFFSET := 1.25
## A turret that spots the ship raises the alarm with robots that can see it.
const ALARM_RANGE := 70.0
const ALARM_GAP := 12.0
## Line of sight is re-checked this often rather than every physics frame.
const SIGHT_GAP := 0.12

var hp := MAX_HP
var normal := Vector3.FORWARD
var _head: Node3D
var _muzzles: Array[Node3D] = []
var _cd := 1.2
var _side := 0
var _dead := false
var _stunned := 0.0
var _active := false
var _alarm_cd := 0.0
var _sight_cd := 0.0
var _sees := false
var _query: PhysicsRayQueryParameters3D


func setup(at: Vector3, wall_normal: Vector3) -> void:
	global_position = at
	normal = wall_normal.normalized()
	var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.BACK
	look_at(at + normal, up)


func _ready() -> void:
	add_to_group("enemy")
	_sight_cd = randf() * SIGHT_GAP
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = Game.WORLD
	collision_layer = Game.ENEMY
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 2.0
	shape.shape = s
	shape.position = Vector3(0, 0, -BODY_OFFSET)
	add_child(shape)
	var model: Node3D = load("res://assets/models/sentry.glb").instantiate()
	Mats.apply(model)
	add_child(model)
	_head = model.find_child("Head", true, false)
	for n in ["Muzzle_R", "Muzzle_L"]:
		_muzzles.append(_head.find_child(n, true, false))


## The turret's origin is on the wall, so a line to it would end inside the rock.
func body_center() -> Vector3:
	return global_position + normal * BODY_OFFSET


func can_be_locked() -> bool:
	return not _dead


func stun(seconds: float) -> void:
	_stunned = maxf(_stunned, seconds)


func hp_ratio() -> float:
	return hp / MAX_HP


func _physics_process(delta: float) -> void:
	_stunned -= delta
	_alarm_cd -= delta
	var p := Game.player
	if p == null or p.dead or _stunned > 0.0:
		return
	var pivot := _head.global_position
	var to: Vector3 = p.global_position - pivot
	if to.length() > 150.0 or to.normalized().dot(normal) < 0.08 or p.is_cloaked():
		_lose_sight()
		_sight_cd = 0.0
		return
	_sight_cd -= delta
	if _sight_cd <= 0.0:
		_sight_cd = SIGHT_GAP
		_query.from = pivot + normal * 2.5
		_query.to = p.global_position
		_sees = get_world_3d().direct_space_state.intersect_ray(_query).is_empty()
	var was_active := _active
	_active = _sees
	if not _active:
		_lose_sight()
		return
	if not was_active and _alarm_cd <= 0.0:
		_alarm_cd = ALARM_GAP
		_raise_alarm(p.global_position)
	var up := Vector3.UP if absf(to.normalized().y) < 0.95 else Vector3.BACK
	var goal := Basis.looking_at(to.normalized(), up)
	_head.global_basis = _head.global_basis.orthonormalized().slerp(goal, 1.0 - exp(-5.0 * delta)).orthonormalized()
	_cd -= delta
	if _cd <= 0.0 and (-_head.global_basis.z).dot(to.normalized()) > 0.96:
		_cd = randf_range(0.5, 0.85)
		_side = 1 - _side
		var at := _muzzles[_side].global_position
		Bolt.launch(at, (p.global_position - at).normalized(), BOLT_SPEED, SHOT_DAMAGE, Bolt.color_for_damage(SHOT_DAMAGE), Game.WORLD | Game.PLAYER, 1.1, self)
		Sfx.play("enemy_shot", at, -6.0, 1.3)


func _raise_alarm(seen_at: Vector3) -> void:
	var reach := ALARM_RANGE * Robot.tactics()
	var space := get_world_3d().direct_space_state
	for other in get_tree().get_nodes_in_group("enemy"):
		if not other is Robot or other.alerted or other is Boss:
			continue
		var d: float = body_center().distance_to(other.global_position)
		if d > reach:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(body_center() + normal, other.global_position, Game.WORLD)).is_empty():
			other.hear_call(seen_at, d, 0.0)


## The barrels keep tracking during this delay, which doubles as a warning.
func _lose_sight() -> void:
	_active = false
	_cd = REACTION


func take_damage(amount: float, _at: Vector3, _source: Object) -> void:
	if _dead:
		return
	hp -= amount
	if hp <= 0.0:
		_dead = true
		Game.add_kill(SCORE)
		Fx.explosion(_head.global_position, 4.5)
		queue_free()
