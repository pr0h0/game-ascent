class_name Boss
extends Robot
## The mine's big machines share this: three phases as the armour fails, weak points
## that take far more damage than the plating, special attacks that are announced
## before they land, and a death that sets off the same escape a reactor would.
## On its own this script is the Overseer (level 7).

const FAN_SHOTS := 7
const SUMMON_INTERVAL := 9.0
const RAIL_INTERVAL := 4.0
const SINGULARITY_INTERVAL := 8.0
const MINE_INTERVAL := 6.0
const STUN_LIMIT := 1.0
const BOSS_HP_SCALING := 0.5
const PHASE_TWO := 0.66
const PHASE_THREE := 0.33
## Plating soaks most of a hit; a weak point takes extra.
const ARMOR := 0.55
const WEAK_RADIUS := 5.0
const WEAK_COLOR := Color(1.0, 0.85, 0.3)
const ARMOR_COLOR := Color(0.6, 0.65, 0.75)
const WARN_COLOR := Color(1.0, 0.2, 0.08)
## Bosses hover inside their arena instead of chasing the ship down tunnels.
const LEASH := 34.0
const SWEEP_WARNING := 1.5
const SWEEP_TIME := 2.4
const SWEEP_INTERVAL := 11.0
const SWEEP_ARMS := 4
const SWEEP_DAMAGE := 14.0

var _rail_cd := 3.0
var _summon_cd := 5.0
var _orb_cd := 4.0
var _mine_cd := 3.0
var _minions: Array = []
var _last_phase := 1
var _glow: OmniLight3D
## {"node": Node3D, "mult": float, "radius": float, "open": bool, "hp": float (<0 = unbreakable)}
var weak_points: Array[Dictionary] = []
var _ping_cd := 0.0
## The current announced attack: "" when none. Its clock counts the warning, then the attack.
var special := ""
var _special_t := 0.0
var _special_cd := 6.0
var _warn_cd := 0.0
var _sweep_angle := 0.0
var _sweep_up := Vector3.UP
var _sweep_side := Vector3.RIGHT
var _crown_speed := 1.0


## The arena is dark and this is what everyone should be looking at.
func _ready() -> void:
	super()
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.3, 0.2)
	_glow.light_energy = 7.0
	_glow.omni_range = 75.0
	add_child(_glow)
	_setup_weak_points()


func title() -> String:
	return "OVERSEER"


func _setup_weak_points() -> void:
	add_weak_point("Weak_Eye", 1.9, 6.0)


## Marks a model node as a weak point. hp < 0 means it can't be shot off.
func add_weak_point(node_name: String, mult: float, radius := WEAK_RADIUS, part_hp := -1.0, open := true) -> void:
	var node: Node3D = _model.find_child(node_name, true, false)
	if node == null:
		push_warning("%s has no %s" % [kind, node_name])
		return
	weak_points.append({"node": node, "mult": mult, "radius": radius, "open": open, "hp": part_hp * Game.diff("hp") if part_hp > 0.0 else -1.0})


func _uses_tactics() -> bool:
	return false


## Half the usual armour scaling: a boss already hits harder and fires faster on the
## hard settings, and a fight that also runs half again as long turns from climax to wall.
func max_hp() -> float:
	return float(cfg["hp"]) * (1.0 + (Game.diff("hp") - 1.0) * BOSS_HP_SCALING)


func phase() -> int:
	var r := hp_ratio()
	return 3 if r < PHASE_THREE else (2 if r < PHASE_TWO else 1)


## EMP can only stagger it, or it would be trivial.
func stun(seconds: float) -> void:
	super.stun(minf(seconds, STUN_LIMIT))


func _rushes() -> bool:
	return false


func alert() -> void:
	if not alerted:
		Music.play_track(str(cfg.get("music", "boss")))
		Sfx.play("boss_roar", null, 2.0)
	super.alert()


## Where guns and missiles should go: the exposed weak point nearest the ship.
func body_center() -> Vector3:
	var best := global_position
	var best_d := INF
	var from: Vector3 = Game.player.global_position if Game.player != null else global_position
	for w in weak_points:
		if w["open"] and float(w["hp"]) != 0.0:
			var at: Vector3 = w["node"].global_position
			var d := at.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = at
	return best


func weak_open() -> bool:
	for w in weak_points:
		if w["open"] and float(w["hp"]) != 0.0:
			return true
	return false


func armor() -> float:
	return float(cfg.get("armor", ARMOR))


## Plating soaks the hit; an open weak point near where it landed takes extra.
## Arcs and cutters strike the middle of the body, so they count as plating
## unless something is open.
func take_damage(amount: float, at: Vector3, source: Object) -> void:
	if _dead:
		return
	var mult := armor()
	var struck := -1
	var best := INF
	for i in weak_points.size():
		var w: Dictionary = weak_points[i]
		if not w["open"] or float(w["hp"]) == 0.0:
			continue
		var d: float = at.distance_to(w["node"].global_position)
		if d < float(w["radius"]) and d < best:
			best = d
			struck = i
	if struck >= 0:
		var w: Dictionary = weak_points[struck]
		mult = float(w["mult"])
		if float(w["hp"]) > 0.0:
			w["hp"] = maxf(0.0, float(w["hp"]) - amount)
			if float(w["hp"]) == 0.0:
				_part_destroyed(struck)
		_flash_hit(at, WEAK_COLOR, "reactor_hit")
	elif at.distance_to(global_position) < 0.5 and weak_open():
		mult = 1.0
	else:
		_flash_hit(at, ARMOR_COLOR, "")
	super.take_damage(amount * mult, at, source)


func _flash_hit(at: Vector3, color: Color, sound: String) -> void:
	if Time.get_ticks_msec() * 0.001 < _ping_cd:
		return
	_ping_cd = Time.get_ticks_msec() * 0.001 + 0.12
	Fx.sparks(at, (at - global_position).normalized(), color)
	if sound != "":
		Sfx.play(sound, at, -1.0, randf_range(1.1, 1.3))


## A weak point with its own health was shot off.
func _part_destroyed(index: int) -> void:
	var node: Node3D = weak_points[index]["node"]
	Fx.explosion(node.global_position, 7.0, true)
	node.visible = false
	hp -= max_hp() * 0.04


func _physics_process(delta: float) -> void:
	super(delta)
	if _dead:
		return
	if phase() != _last_phase:
		_last_phase = phase()
		_on_phase(_last_phase)
	# An attack in progress is called off once the ship is out of sight.
	if special != "" and not has_los:
		_end_special()
	_animate(delta)


func _on_phase(_n: int) -> void:
	Sfx.play("boss_phase", null, 2.0)
	Sfx.play("boss_roar", global_position, 8.0, 0.9)
	Fx.pulse(global_position, float(cfg["radius"]) * 3.0, WARN_COLOR)


func _animate(delta: float) -> void:
	_crown_speed = lerpf(_crown_speed, 6.0 if special == "sweep" else 1.0, 1.0 - exp(-2.0 * delta))
	if _spinner != null and _crown_speed > 1.05:
		_spinner.rotate_object_local(Vector3.UP, (_crown_speed - 1.0) * 3.0 * delta)
	var warn := special != "" and _special_t > 0.0 and _warning_left() > 0.0
	_glow.light_energy = 7.0 + (6.0 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)) if warn else 0.0)


## Hovers at range but never strays far from the middle of its arena.
func _combat_move(to: Vector3, speed: float) -> Vector3:
	var want := super._combat_move(to, speed)
	var off := global_position - home
	if off.length() > LEASH:
		want += -off.normalized() * speed * clampf((off.length() - LEASH) / 10.0, 0.0, 2.0)
	return want


func _attack(delta: float, to: Vector3) -> void:
	if _reaction > 0.0:
		_reaction -= delta
		return
	_fire_cd -= delta
	_rail_cd -= delta
	_summon_cd -= delta
	_orb_cd -= delta
	_mine_cd -= delta
	update_rail_charge(delta, 40.0)
	if _run_special(delta, to):
		return
	var aim := to.normalized()
	if _fire_cd <= 0.0:
		# Faster as it gets hurt, but not a solid wall of fire by the end.
		_fire_cd = cfg["fire"] / (1.0 + 0.5 * (phase() - 1))
		_fan(aim)
	if _rail_cd <= 0.0:
		_rail_cd = RAIL_INTERVAL
		_side = 1 - _side
		begin_rail_charge()
	if phase() >= 2 and _summon_cd <= 0.0:
		_summon_cd = SUMMON_INTERVAL
		_summon()
	if phase() >= 2 and _orb_cd <= 0.0:
		_orb_cd = SINGULARITY_INTERVAL
		Singularity.launch(global_position + aim * 14.0, aim, 40.0, false)
	if phase() >= 3 and _mine_cd <= 0.0:
		_mine_cd = MINE_INTERVAL
		var seeker := Mine.spawn("seeker", global_position + aim * 16.0)
		seeker.life = 25.0


# --- Announced attacks -------------------------------------------------------------
## Starts, advances and ends the special attack. True while it owns the guns.
func _run_special(delta: float, to: Vector3) -> bool:
	if special == "":
		_special_cd -= delta
		if _special_cd > 0.0 or _rail_charge > 0.0:
			return false
		var next := _choose_special(to)
		if next == "":
			return false
		special = next
		_special_t = 0.0
		_begin_special(to)
	_special_t += delta
	var warning := _warning_time()
	if _special_t < warning:
		_warn_cd -= delta
		if _warn_cd <= 0.0:
			_warn_cd = 0.05
			_draw_warning(to, _special_t / warning)
		return true
	if _special_t - warning > _active_time() or not _update_special(delta, to, _special_t - warning):
		_end_special()
	return true


func _warning_left() -> float:
	return _warning_time() - _special_t


func _end_special() -> void:
	special = ""
	_special_cd = _special_interval()


func _special_interval() -> float:
	return SWEEP_INTERVAL / (1.0 + 0.25 * (phase() - 1))


func _choose_special(_to: Vector3) -> String:
	return "sweep" if phase() >= 2 else ""


func _warning_time() -> float:
	return SWEEP_WARNING


func _active_time() -> float:
	return SWEEP_TIME


## The crown spins up and lays out the plane it's about to fill with fire.
func _begin_special(to: Vector3) -> void:
	# A flat disc through the ship: flying up or down out of it is the dodge.
	_sweep_up = Vector3.UP
	_sweep_side = to.normalized().slide(_sweep_up).normalized()
	if _sweep_side.length_squared() < 0.5:
		_sweep_side = Vector3.RIGHT
	_sweep_angle = randf() * TAU
	Sfx.play("rail_charge", global_position, 8.0, 0.6)
	Sfx.play("boss_roar", global_position, 4.0, 1.2)


func _draw_warning(_to: Vector3, progress: float) -> void:
	var fwd := _sweep_side
	var right := _sweep_up.cross(fwd)
	for i in SWEEP_ARMS:
		var a := _sweep_angle + float(i) / SWEEP_ARMS * TAU
		var dir := fwd * cos(a) + right * sin(a)
		Weapons.beam(global_position + dir * 11.0, global_position + dir * lerpf(30.0, 140.0, progress), SIGHT_COLOR, 0.12 + progress * 0.25)


func _update_special(_delta: float, _to: Vector3, t: float) -> bool:
	_warn_cd -= _delta
	if _warn_cd > 0.0:
		return true
	_warn_cd = 0.07
	var fwd := _sweep_side
	var right := _sweep_up.cross(fwd)
	var damage := SWEEP_DAMAGE
	var turn := _sweep_angle + t * 1.6
	for i in SWEEP_ARMS:
		var a := turn + float(i) / SWEEP_ARMS * TAU
		var dir := fwd * cos(a) + right * sin(a)
		Bolt.launch(global_position + dir * 12.0, dir, 70.0, damage, Bolt.color_for_damage(damage), Game.WORLD | Game.PLAYER, 1.6, self)
	Sfx.play("enemy_shot_heavy", global_position, 4.0, 0.7)
	return true


func _fan(aim: Vector3) -> void:
	var side := aim.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var damage: float = cfg["dmg"]
	for i in FAN_SHOTS:
		var d := (aim + side * lerpf(-0.3, 0.3, float(i) / float(FAN_SHOTS - 1))).normalized()
		Bolt.launch(global_position + d * 12.0, d, cfg["bolt"], damage, Bolt.color_for_damage(damage), Game.WORLD | Game.PLAYER, 1.8, self)
	Sfx.play("enemy_shot_heavy", global_position, 8.0, 0.8)


func _summon() -> void:
	_minions = _minions.filter(func(m): return is_instance_valid(m))
	for i in 3 - mini(_minions.size(), 3):
		var kind_name: String = ["ripper", "hornet", "cinder"][i]
		var offset := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized() * 18.0
		_minions.append(Game.level.spawn_robot(kind_name, global_position + offset, true, false))


func _die(_credit := true) -> void:
	if _dead:
		return
	_dead = true
	remove_from_group("enemy")
	_all.erase(self)
	Game.add_kill(cfg["score"])
	Game.trigger_core_failure(global_position)
	queue_free()
