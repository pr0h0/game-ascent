class_name Crucible
extends Boss
## Smelter Row's foundry vessel (level 4), rebuilt around the shaft's power core.
## It lobs slag, and announces a sweeping pour with a white-hot mouth. A pour
## overheats it: the three hatches on its back swing open to vent, and the grates
## under them are soft. Later it casts Cinders from the melt, and at the end it
## charges, after rearing its clamp arms and showing the line it will take.

const POUR_WARNING := 1.6
const POUR_TIME := 2.0
## Half the angle the pour sweeps across, centred on the ship.
const POUR_SPREAD := 0.7
const POUR_DAMAGE := 14.0
const POUR_GAP := 0.05
const POUR_COLOR := Color(1.0, 0.42, 0.08)
const VENT_TIME := 6.0
const CAST_INTERVAL := 13.0
const CHARGE_WARNING := 1.4
const CHARGE_TIME := 1.7
const CHARGE_SPEED := 58.0
const CHARGE_DAMAGE := 45.0
const CHARGE_KNOCKBACK := 45.0
const SLAG_SHOTS := 3
const SLAG_DAMAGE := 18.0

var vents_left := 0.0
var _vent_anim := 0.0
var _heat := 0.0
var _mouth_mat: StandardMaterial3D
var _hatches: Array[Node3D] = []
var _hatch_rest: Array[Basis] = []
var _vent_lights: Array[OmniLight3D] = []
var _arms: Array[Node3D] = []
var _cooler: Node3D
var _mouth: Node3D
var _pour_from := Vector3.FORWARD
var _pour_to := Vector3.FORWARD
var _pour_cd := 0.0
var _charge_dir := Vector3.ZERO
var _charging := false
var _charge_hit := false
var _cast_cd := 8.0
var _cinders: Array = []
var _next_is_charge := false


func _ready() -> void:
	super()
	_glow.light_color = Color(1.0, 0.45, 0.12)
	_mouth = _model.find_child("Mouth", true, false)
	_mouth_mat = StandardMaterial3D.new()
	_mouth_mat.albedo_color = Color.BLACK
	_mouth_mat.emission_enabled = true
	_mouth_mat.emission = POUR_COLOR
	_mouth_mat.emission_energy_multiplier = 4.0
	if _mouth is MeshInstance3D:
		_mouth.material_override = _mouth_mat
	for i in 3:
		var hatch: Node3D = _model.find_child("Vent%d" % i, true, false)
		_hatches.append(hatch)
		_hatch_rest.append(hatch.basis)
		var marker: Node3D = _model.find_child("Weak_Vent%d" % i, true, false)
		var light := OmniLight3D.new()
		light.light_color = POUR_COLOR
		light.light_energy = 0.0
		light.omni_range = 16.0
		marker.add_child(light)
		_vent_lights.append(light)
	for n in ["Arm_L", "Arm_R"]:
		_arms.append(_model.find_child(n, true, false))
	_cooler = _model.find_child("Fan", true, false)


func title() -> String:
	return "CRUCIBLE"


func _setup_weak_points() -> void:
	add_weak_point("Weak_Mouth", 1.6, 6.5, -1.0, false)
	for i in 3:
		add_weak_point("Weak_Vent%d" % i, 2.6, 5.5, -1.0, false)


func armor() -> float:
	return 0.35


func venting() -> bool:
	return vents_left > 0.0


func _physics_process(delta: float) -> void:
	vents_left -= delta
	var mouth_open := special == "pour"
	weak_points[0]["open"] = mouth_open
	for i in range(1, weak_points.size()):
		weak_points[i]["open"] = venting()
	super(delta)


func _animate(delta: float) -> void:
	super(delta)
	var heat_goal := 0.0
	if special == "pour":
		heat_goal = clampf(_special_t / POUR_WARNING, 0.0, 1.0) if _special_t < POUR_WARNING else 1.3
	_heat = lerpf(_heat, heat_goal, 1.0 - exp(-4.0 * delta))
	_mouth_mat.emission_energy_multiplier = 3.0 + _heat * 14.0 + sin(Time.get_ticks_msec() * 0.004) * 0.6
	_vent_anim = move_toward(_vent_anim, 1.0 if venting() else 0.0, delta * 2.5)
	for i in _hatches.size():
		if _hatches[i] != null:
			_hatches[i].basis = _hatch_rest[i] * Basis(Vector3.RIGHT, _vent_anim * 1.5)
		_vent_lights[i].light_energy = _vent_anim * 6.0
	if _cooler != null:
		_cooler.rotate_object_local(Vector3.FORWARD, (2.0 + _vent_anim * 14.0) * delta)
	# The clamp arms rear up before a charge and swing while it runs.
	var lift := 0.0
	if special == "charge":
		lift = 0.9 if _special_t < CHARGE_WARNING else 0.3
	for arm in _arms:
		if arm != null:
			arm.rotation.x = lerpf(arm.rotation.x, lift + sin(Time.get_ticks_msec() * 0.0015 + _phase) * 0.08, 1.0 - exp(-5.0 * delta))
	if venting() and randf() < delta * 8.0:
		var m: Node3D = weak_points[1 + randi() % 3]["node"]
		Fx.sparks(m.global_position, (m.global_position - global_position).normalized(), POUR_COLOR)


func _combat_move(to: Vector3, speed: float) -> Vector3:
	if _charging:
		return _charge_dir * CHARGE_SPEED
	return super._combat_move(to, speed)


func _attack(delta: float, to: Vector3) -> void:
	if _reaction > 0.0:
		_reaction -= delta
		return
	_fire_cd -= delta
	_cast_cd -= delta
	if _run_special(delta, to):
		return
	if _fire_cd <= 0.0:
		_fire_cd = float(cfg["fire"]) * Game.diff("fire") / (1.0 + 0.3 * (phase() - 1))
		_slag(to)
	if phase() >= 2 and _cast_cd <= 0.0:
		_cast_cd = CAST_INTERVAL
		_cast()


## Slow, heavy globs from the shoulder mortars. Easy to see, painful to ignore.
func _slag(to: Vector3) -> void:
	var p: Player = Game.player
	for i in SLAG_SHOTS:
		_side = 1 - _side
		var at: Vector3 = _muzzles[_side].global_position
		var travel := at.distance_to(p.global_position) / float(cfg["bolt"])
		var lead: Vector3 = p.global_position + p.velocity * travel * 0.6
		var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (2.0 + i * 3.0)
		Bolt.launch(at, (lead + spread - at).normalized(), cfg["bolt"], SLAG_DAMAGE, POUR_COLOR, Game.WORLD | Game.PLAYER, 2.8, self)
	Sfx.play("enemy_shot_heavy", global_position, 6.0, 0.6)


## Casts fresh Cinders from the melt.
func _cast() -> void:
	_cinders = _cinders.filter(func(c): return is_instance_valid(c))
	var count := (1 if Game.diff("ai") < 0.5 else 2) + (1 if phase() >= 3 else 0)
	Sfx.play("hive_spawn", global_position, 4.0, 0.7)
	Fx.pulse(_mouth_point(), 14.0, POUR_COLOR)
	for i in maxi(0, count - _cinders.size()):
		var at := _mouth_point() + Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4))
		_cinders.append(Game.level.spawn_robot("cinder", at, true, false))


func _mouth_point() -> Vector3:
	return weak_points[0]["node"].global_position - global_basis.z * 2.0


func _choose_special(_to: Vector3) -> String:
	if phase() >= 3:
		_next_is_charge = not _next_is_charge
		if _next_is_charge:
			return "charge"
	return "pour"


func _special_interval() -> float:
	return [8.5, 7.0, 5.5][phase() - 1]


func _warning_time() -> float:
	return CHARGE_WARNING if special == "charge" else POUR_WARNING


func _active_time() -> float:
	return CHARGE_TIME if special == "charge" else POUR_TIME


func _begin_special(to: Vector3) -> void:
	var aim := to.normalized()
	if special == "charge":
		_charge_dir = aim
		_charge_hit = false
		Sfx.play("boss_roar", global_position, 6.0, 1.15)
		Sfx.play("mine_rumble", global_position, 6.0, 0.8)
		return
	# Sweeps across the ship's bearing, in a plane that varies so it can't be learnt.
	var axis := Vector3.UP if randf() < 0.6 else aim.cross(Vector3.UP).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.RIGHT
	var flip := 1.0 if randf() < 0.5 else -1.0
	_pour_from = aim.rotated(axis, -POUR_SPREAD * flip)
	_pour_to = aim.rotated(axis, POUR_SPREAD * flip)
	Sfx.play("fire_roar", global_position, 6.0, 0.7)
	Sfx.play("rail_charge", global_position, 6.0, 0.5)


func _draw_warning(_to: Vector3, progress: float) -> void:
	if special == "charge":
		var from := global_position
		var end := from + _charge_dir * CHARGE_SPEED * CHARGE_TIME
		Weapons.beam(from + _charge_dir * 11.0, end, SIGHT_COLOR, 0.5 + progress * 1.5)
		_glow.light_energy = 7.0 + progress * 10.0
		return
	# Shows the whole fan the pour will sweep, brightening as the mouth heats.
	var mouth := _mouth_point()
	for i in 5:
		var dir := _pour_from.slerp(_pour_to, float(i) / 4.0)
		Weapons.beam(mouth, mouth + dir * lerpf(25.0, 110.0, progress), POUR_COLOR if i % 4 == 0 else SIGHT_COLOR, 0.1 + progress * 0.2)


func _update_special(delta: float, _to: Vector3, t: float) -> bool:
	if special == "charge":
		return _update_charge(t)
	_pour_cd -= delta
	if _pour_cd > 0.0:
		return true
	_pour_cd = POUR_GAP
	var dir := _pour_from.slerp(_pour_to, clampf(t / POUR_TIME, 0.0, 1.0))
	var mouth := _mouth_point()
	for i in 2:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.03
		Bolt.launch(mouth, (dir + jitter).normalized(), 80.0, POUR_DAMAGE, POUR_COLOR, Game.WORLD | Game.PLAYER, 2.2, self)
	if randf() < 0.3:
		Sfx.play("fire_roar", mouth, 2.0, randf_range(0.8, 1.0))
	return true


func _update_charge(_t: float) -> bool:
	_charging = true
	var p: Player = Game.player
	if not _charge_hit and p != null and not p.dead and global_position.distance_to(p.global_position) < float(cfg["radius"]) + Player.RADIUS + 3.0:
		_charge_hit = true
		p.take_damage(CHARGE_DAMAGE, global_position, self)
		p.velocity += _charge_dir * CHARGE_KNOCKBACK
		Fx.sparks(p.global_position, -_charge_dir, POUR_COLOR)
		Sfx.play("melee_hit", global_position, 8.0, 0.6)
	# Slamming into rock ends it early, with a shower of sparks.
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is StaticBody3D and c.get_normal().dot(_charge_dir) < -0.5:
			Fx.sparks(c.get_position(), c.get_normal(), POUR_COLOR)
			Sfx.play("wall_bump", global_position, 8.0, 0.5)
			_charging = false
			return false
	return true


func _end_special() -> void:
	if special == "pour":
		# Overheated: the vents open and the soft grates under them are exposed.
		vents_left = VENT_TIME
		Sfx.play("mine_steam", global_position, 8.0, 0.7)
		Sfx.play("boss_phase", global_position, 0.0, 1.3)
	if special == "charge":
		_charging = false
		velocity *= 0.2
	super._end_special()
