class_name Zero
extends Boss
## Core Zero's resident (level 10): the mind the Overseer was only the voice of,
## grown into the mine's last reactor. Six armour petals keep its core shut while
## four conduit pods feed it; each pod can be shot off. To fire its beam it has to
## bloom open, which is announced and leaves the core bare for a few seconds. In
## the last phase half the petals tear away for good.

const BEAM_WARNING := 1.7
const BEAM_TIME := 2.6
## The beam locks where it was aimed when the warning ends, then sweeps this far.
const BEAM_SWEEP := 1.1
const BEAM_DAMAGE := 9.0
const BEAM_TICK := 0.2
const BEAM_RANGE := 420.0
const BEAM_COLOR := Color(0.85, 0.35, 1.0)
const EXPOSE_TIME := 3.5
const WELL_WARNING := 1.1
const WELL_DAMAGE := 40.0
const SUMMON_GAP := 22.0
const PULSE_MINE_GAP := 9.0
const LANCE_GAP := 5.5
const PRISM_DAMAGE := 12.0
const PETAL_TRAVEL := 6.5
## Share of the boss's health each conduit pod holds before it breaks.
const CONDUIT_SHARE := 0.05

var exposed_left := 0.0
var conduits_lost := 0
var _open := 0.0
var _petals: Array[MeshInstance3D] = []
var _petal_dirs: Array[Vector3] = []
var _torn := false
var _core_mat: StandardMaterial3D
var _ring: Node3D
var _ring2: Node3D
var _beam_from := Vector3.FORWARD
var _beam_to := Vector3.FORWARD
var _beam_tick := 0.0
var _beam_draw := 0.0
var _lance_cd := 4.0
var _summon_left := 10.0
var _pulse_cd := 6.0
var _minion_list: Array = []
var _next_well := false
var _beam_locked := false


func _ready() -> void:
	super()
	# The gyroscope rings turn slowly; Robot would spin them like a drone's blades.
	_ring = _spinner
	_spinner = null
	_ring2 = _model.find_child("Ring2", true, false)
	_glow.light_color = BEAM_COLOR
	_glow.omni_range = 95.0
	var core: Node3D = _model.find_child("Core", true, false)
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = Color.BLACK
	_core_mat.emission_enabled = true
	_core_mat.emission = BEAM_COLOR
	_core_mat.emission_energy_multiplier = 5.0
	if core is MeshInstance3D:
		core.material_override = _core_mat
	for i in 6:
		var petal: MeshInstance3D = _model.find_child("Petal%d" % i, true, false)
		_petals.append(petal)
		_petal_dirs.append((petal.transform * petal.get_aabb().get_center()).normalized())


func title() -> String:
	return "ZERO"


func _setup_weak_points() -> void:
	add_weak_point("Weak_Core", 2.3, 14.0, -1.0, false)
	for i in 4:
		add_weak_point("Weak_Conduit%d" % i, 1.6, 4.5, float(cfg["hp"]) * CONDUIT_SHARE)


func armor() -> float:
	return 0.45 if _torn else 0.3


func core_open() -> bool:
	return _open > 0.5 or _torn


## With the core showing, everything should go at the core.
func body_center() -> Vector3:
	if core_open():
		return global_position
	return super.body_center()


func _physics_process(delta: float) -> void:
	exposed_left -= delta
	weak_points[0]["open"] = core_open()
	weak_points[0]["mult"] = 2.3 if _open > 0.5 else 1.4
	for i in range(1, weak_points.size()):
		weak_points[i]["open"] = true
	super(delta)


func _part_destroyed(index: int) -> void:
	super(index)
	conduits_lost += 1
	var pod: Node3D = _model.find_child("Conduit%d" % (index - 1), true, false)
	if pod != null:
		pod.visible = false
	Sfx.play("explode_big", global_position, 6.0, 0.8)
	Sfx.play("boss_roar", global_position, 6.0, 1.3)


func _on_phase(n: int) -> void:
	super(n)
	if n >= 3 and not _torn:
		_torn = true
		# Half the bloom tears away; the core stays bare from here on.
		for i in [0, 2, 4]:
			var petal := _petals[i]
			Fx.explosion(global_position + _petal_dirs[i] * 10.0, 10.0, true)
			petal.visible = false


func _animate(delta: float) -> void:
	super(delta)
	var want := 0.0
	if special == "beam" or exposed_left > 0.0:
		want = 1.0
	# Starved conduits make it bloom wider and slower to close.
	_open = move_toward(_open, want, delta * (1.6 if want > _open else 0.8 + 0.2 * (4 - conduits_lost)))
	for i in _petals.size():
		_petals[i].position = _petal_dirs[i] * _open * PETAL_TRAVEL
	var charging := special != "" and _special_t < _warning_time()
	var spin := 0.5 + (2.8 if charging else 0.0) + _open * 0.6
	if _ring != null:
		_ring.rotate_object_local(Vector3.UP, spin * delta)
	if _ring2 != null:
		_ring2.rotate_object_local(Vector3.FORWARD, -spin * 0.7 * delta)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.004 + _open * 0.01))
	_core_mat.emission_energy_multiplier = 4.0 + _open * 10.0 + pulse * 2.0 + (6.0 if charging else 0.0)
	_glow.light_energy = 6.0 + _open * 8.0


func _attack(delta: float, to: Vector3) -> void:
	if _reaction > 0.0:
		_reaction -= delta
		return
	_fire_cd -= delta
	_lance_cd -= delta
	_summon_left -= delta
	_pulse_cd -= delta
	update_rail_charge(delta, 40.0)
	if _run_special(delta, to):
		return
	var aim := to.normalized()
	if _fire_cd <= 0.0:
		_fire_cd = float(cfg["fire"]) * Game.diff("fire") / (1.0 + 0.25 * (phase() - 1))
		_prism_fan(aim)
	if _lance_cd <= 0.0 and _rail_charge <= 0.0:
		_lance_cd = LANCE_GAP / (1.0 + 0.2 * (phase() - 1))
		_side = 1 - _side
		begin_rail_charge()
	if phase() >= 2 and _summon_left <= 0.0:
		_summon_left = SUMMON_GAP
		_call_guards()
	if phase() >= 3 and _pulse_cd <= 0.0:
		_pulse_cd = PULSE_MINE_GAP
		var mine := Mine.spawn("pulse", global_position + aim * 18.0)
		mine.life = 25.0


## Three bouncing prism bolts, the same as the player's repeater.
func _prism_fan(aim: Vector3) -> void:
	var side := aim.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var w: Dictionary = Weapons.PRIMARY["prism"]
	for i in 3:
		_side = 1 - _side
		var d := (aim + side * (float(i) - 1.0) * 0.12).normalized()
		Bolt.launch(_muzzles[_side].global_position, d, w["speed"] * 0.55, PRISM_DAMAGE, Weapons.PRISM_COLOR, Game.WORLD | Game.PLAYER, 1.4, self, w["bounces"])
	Sfx.play("prism", global_position, 2.0, 0.6)


func _call_guards() -> void:
	_minion_list = _minion_list.filter(func(m): return is_instance_valid(m))
	# The arena already has its own guards; these only top it up.
	var kinds := ["phase"] if phase() < 3 else ["phase", "wraith"]
	Sfx.play("hive_spawn", global_position, 4.0, 0.6)
	for i in maxi(0, kinds.size() - _minion_list.size()):
		var offset := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized() * 22.0
		_minion_list.append(Game.level.spawn_robot(kinds[i], global_position + offset, true, false))


func _choose_special(_to: Vector3) -> String:
	if phase() >= 2:
		_next_well = not _next_well
		if _next_well:
			return "well"
	return "beam"


func _special_interval() -> float:
	return [11.0, 8.5, 6.5][phase() - 1]


func _warning_time() -> float:
	return WELL_WARNING if special == "well" else BEAM_WARNING


func _active_time() -> float:
	if special == "well":
		return 0.1
	return BEAM_TIME * (1.3 if _torn else 1.0)


func _begin_special(to: Vector3) -> void:
	if special == "well":
		Sfx.play("singularity_fire", global_position, 6.0, 0.6)
		return
	_beam_from = to.normalized()
	_beam_locked = false
	Sfx.play("rail_charge", global_position, 8.0, 0.45)
	Sfx.play("boss_roar", global_position, 4.0, 0.7)


## Shows the beam's line while it tracks the ship, then the arc it will sweep.
func _draw_warning(to: Vector3, progress: float) -> void:
	var core := global_position
	if special == "well":
		Fx.pulse(core, lerpf(30.0, 12.0, progress), BEAM_COLOR)
		return
	# Tracks until the last third, then holds still: that's the moment to move.
	if progress < 0.66:
		_beam_from = to.normalized()
	elif not _beam_locked:
		_beam_locked = true
		_beam_to = _sweep_end(_beam_from)
		Sfx.play("mine_beep", core, 8.0, 0.5)
	Weapons.beam(core + _beam_from * 12.0, core + _beam_from * 160.0, SIGHT_COLOR if not _beam_locked else Color.WHITE, 0.15 + progress * 0.4)
	if _beam_locked:
		for i in range(1, 5):
			var dir := _beam_from.slerp(_beam_to, float(i) / 4.0)
			Weapons.beam(core + dir * 12.0, core + dir * 70.0, BEAM_COLOR, 0.1)


## The beam swings away to one side, in a plane that changes every time.
func _sweep_end(from: Vector3) -> Vector3:
	var axis := Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized()
	if randf() < 0.4:
		axis = from.cross(Vector3.UP).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.RIGHT
	return from.rotated(axis, BEAM_SWEEP * (1.0 if randf() < 0.5 else -1.0))


func _update_special(delta: float, _to: Vector3, t: float) -> bool:
	if special == "well":
		var p: Player = Game.player
		for s in [-1.0, 1.0]:
			_side = 1 - _side
			var at: Vector3 = _muzzles[_side].global_position
			var dir: Vector3 = (p.global_position - at).normalized().rotated(Vector3.UP, s * 0.15)
			Singularity.launch(at + dir * 4.0, dir, WELL_DAMAGE, false)
		return false
	var dir := _beam_from.slerp(_beam_to, clampf(t / _active_time(), 0.0, 1.0))
	var core := global_position
	var q := PhysicsRayQueryParameters3D.create(core + dir * 12.0, core + dir * BEAM_RANGE, Game.WORLD | Game.PLAYER)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if not hit.is_empty() else core + dir * BEAM_RANGE
	_beam_draw -= delta
	if _beam_draw <= 0.0:
		_beam_draw = 0.04
		Weapons.beam(core + dir * 10.0, end, BEAM_COLOR, 1.6)
		Weapons.beam(core + dir * 10.0, end, Color.WHITE, 0.5)
		if not hit.is_empty():
			Fx.sparks(end, hit.normal, BEAM_COLOR)
	_beam_tick -= delta
	if _beam_tick <= 0.0 and not hit.is_empty() and hit.collider is Player:
		_beam_tick = BEAM_TICK
		hit.collider.take_damage(BEAM_DAMAGE, end, self)
	if randf() < delta * 6.0:
		Sfx.play("rail_fire", core, 2.0, 0.5)
	return true


func _end_special() -> void:
	if special == "beam":
		exposed_left = EXPOSE_TIME
		Sfx.play("boss_phase", global_position, 0.0, 0.8)
	super._end_special()
