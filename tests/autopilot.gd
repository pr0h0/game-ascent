class_name Autopilot
extends Node
## Plays a level through the same controls a person uses: it presses the flight
## actions, moves the aim like a mouse and pulls the triggers. It finds keys, fights
## what it sees, opens secrets, kills the objective and flies out. Anything that
## would strand a player (a route it can't fly, a door that won't open) gets logged.

const REPLAN_TIME := 0.4
const TARGET_TIME := 0.2
const LOOK_RANGE := 150.0
const MAX_TURN_RATE := 6.5
const CRUISE_SPEED := 36.0
const COMBAT_SPEED := 24.0
const FIRE_CONE := 0.035
const STUCK_TIME := 14.0
const TARGET_PATIENCE := 16.0
const SHIP_SWEEP := 2.3
const SECRET_PATIENCE := 150.0
const WEAPON_ROTATE_TIME := 7.0
## Beyond these distances a weapon can't touch anything. Others reach across any room.
const WEAPON_REACH := {"cutter": Weapons.CUTTER_RANGE, "arc": Weapons.ARC_RANGE}
## Switches to the cutter a little inside its range, so it doesn't flip at the edge.
const CUTTER_SWITCH_IN := Weapons.CUTTER_RANGE - 2.0
## Telegraphed attacks within this range get a sidestep, held this long.
const DODGE_WATCH_RANGE := 300.0
const DODGE_TIME := 1.1
const DODGE_SPEED := 30.0
const MISSILE_DODGE_RANGE := 30.0
## sqrt(3) * 5 m plus the hull: further than this from every cell centre is inside rock.
const LEAK_DISTANCE := 11.0
const ACTIONS := ["thrust_forward", "thrust_back", "strafe_left", "strafe_right", "strafe_up", "strafe_down", "fire_primary", "fire_secondary", "fire_flare", "afterburner"]

var player: Player
var level: Node3D
var hunt_secrets := true
var clear_robots := true
var max_seconds := 1500.0
var elapsed := 0.0
var log_lines: Array[String] = []
var stuck_events := 0
var teleports := 0
var targets_engaged := 0
var goal_kind := ""
var done := false
## "weapon name" -> seconds it was selected while firing: proves each one got used.
var weapons_used: Dictionary = {}
var missiles_used: Dictionary = {}

var _path := PackedVector3Array()
var _path_index := 0
var _goal := Vector3.ZERO
var _replan := 0.0
var _target_cd := 0.0
var _target: Node3D
var _target_since := 0.0
var _ignored: Dictionary = {}
var _secrets_left: Array = []
var _secret_door: Door
var _secret_since := 0.0
var _best_goal_dist := INF
var _last_progress := 0.0
var _weapon_cd := 0.0
var _rail_hold := 0.0
var _flare_cd := 20.0
var _weave := 0.0
var _fire_now := false
var _strafe_sign := 1.0
var _dodge_dir := Vector3.ZERO
var _dodge_left := 0.0
## Hostile singularity orbs in flight: slow, glowing and loud, so a pilot flies clear.
var _orbs: Array = []
## Robot missiles in flight. They turn slowly, so a hard slide late in their run beats them.
var _missiles: Array = []
var _leak_cd := 0.0
var _leak_from := Vector3.ZERO
var _was_outside := false


func begin(p: Player, world: Node3D) -> void:
	player = p
	level = world
	for door in level.get_children():
		if door is Door and door.hidden_door:
			_secrets_left.append(door)
	_replan = 0.0
	world.child_entered_tree.connect(_on_level_child)
	Game.run_ended.connect(_on_ended)
	Game.player_died.connect(_on_died)


func _on_level_child(n: Node) -> void:
	if n is Singularity and not n.from_player:
		_orbs.append(n)
	elif n is Missile and not n.from_player:
		_missiles.append(n)


func note(text: String) -> void:
	log_lines.append("[%6.1fs] %s" % [elapsed, text])


func _on_died() -> void:
	note("DIED going to %s at %s, last hit by %s (engaging %s)" % [goal_kind, player.global_position, player.last_attacker, _target.name if is_instance_valid(_target) else "nothing"])


func _on_ended(_won: bool, _detail: String) -> void:
	done = true
	_release_all()


func _release_all() -> void:
	for action: String in ACTIONS:
		Input.action_release(action)


func _physics_process(delta: float) -> void:
	if player == null or done or not is_instance_valid(player):
		return
	elapsed += delta
	if Game.cinematic or Game.finished or player.dead:
		_release_all()
		_last_progress = elapsed
		_best_goal_dist = INF
		return
	_release_all()
	_replan -= delta
	_target_cd -= delta
	_weave += delta
	if _replan <= 0.0:
		_replan = REPLAN_TIME
		_plan()
	_dodge_left -= delta
	if _target_cd <= 0.0:
		_target_cd = TARGET_TIME
		_pick_target()
		_watch_telegraphs()
	_steer(delta)
	_check_stuck()
	_rotate_weapons(delta)
	_check_leak(delta)


# --- Choosing where to go ---------------------------------------------------
func _plan() -> void:
	_unblock_open_doors()
	var kind := ""
	var at := Vector3.ZERO
	if Game.reactor_down:
		kind = "escape"
		at = level.v3(level.data["escape_trigger"])
	else:
		var near_pickup = _wanted_pickup()
		var key = _nearest_key()
		_update_secret_goal()
		if near_pickup != null:
			kind = "pickup"
			at = near_pickup.global_position
		elif key != null:
			kind = "key"
			at = key.global_position
		elif _secret_door != null:
			kind = "secret"
			at = _secret_door.global_position
		else:
			var goal = _objective()
			if goal == null:
				return
			kind = "objective"
			at = goal.global_position
	if kind != goal_kind or at.distance_to(_goal) > 12.0:
		_best_goal_dist = INF
		_last_progress = elapsed
	goal_kind = kind
	_goal = at
	var fresh: PackedVector3Array = level.find_path(player.global_position, at)
	if fresh.is_empty():
		if at.distance_to(player.global_position) > 18.0:
			note("NO ROUTE to %s at %s from %s (keys %s)" % [kind, at, player.global_position.snapped(Vector3.ONE), Game.keys.keys()])
			_replan = 3.0
	_path = fresh
	_path_index = 0


## Keys open doors for planning as soon as they're held; the door swings on approach.
func _unblock_open_doors() -> void:
	for d in level.get_children():
		if d is Door and not d.hidden_door and d._unlocked():
			level.set_cell_blocked(d.cell, false)


func _nearest_key() -> Node3D:
	var best: Node3D = null
	var best_len := INF
	for k in get_tree().get_nodes_in_group("pickup"):
		if not k.kind.begins_with("key_"):
			continue
		var route: PackedVector3Array = level.find_path(player.global_position, k.global_position)
		if route.is_empty() or route[-1].distance_to(k.global_position) > 14.0:
			continue
		if route.size() < best_len:
			best_len = route.size()
			best = k
	return best


func _wanted_pickup() -> Node3D:
	var best: Node3D = null
	var best_dist := 60.0
	var targets: Array = get_tree().get_nodes_in_group("pickup") + get_tree().get_nodes_in_group("astronaut")
	for n in targets:
		var d := player.global_position.distance_to(n.global_position)
		if d < best_dist and _wants(n) and float(_ignored.get(n.get_instance_id(), 0.0)) <= elapsed and player.has_line_of_sight(n):
			best = n
			best_dist = d
	return best


func _wants(n: Node) -> bool:
	if n is Astronaut:
		return true
	match n.kind:
		"shield":
			return player.shield < 185.0
		"energy":
			return player.energy < 170.0
		"ammo":
			return player.missiles < Pickup.MAX_MISSILES
	# A full rack leaves the pickup where it is, so don't hover on it.
	if n.kind.begins_with("ammo_"):
		var missile: String = n.kind.trim_prefix("ammo_")
		return int(player.ammo.get(missile, 0)) < int(Weapons.SECONDARY[missile]["cap"])
	return true


func _update_secret_goal() -> void:
	if not hunt_secrets:
		return
	if _secret_door != null and (_secret_door._is_open or elapsed - _secret_since > SECRET_PATIENCE):
		if not _secret_door._is_open:
			note("SECRET door at %s never opened" % _secret_door.global_position)
		_secrets_left.erase(_secret_door)
		_secret_door = null
	if _secret_door == null and not _secrets_left.is_empty() and _nearest_key() == null:
		_secret_door = _secrets_left[0]
		_secret_since = elapsed


func _objective() -> Node3D:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Reactor or e is Boss:
			return e
	return null


# --- Choosing what to shoot ---------------------------------------------------
func _pick_target() -> void:
	if not is_instance_valid(_target) or not _target.can_be_locked():
		_target = null
	if _target != null:
		if elapsed - _target_since > TARGET_PATIENCE and not (_target is Reactor or _target is Boss):
			_ignored[_target.get_instance_id()] = elapsed + 20.0
			_target = null
		elif not player.has_line_of_sight(_target):
			_target = null
	var best: Node3D = null
	var best_score := INF
	var running := Game.reactor_down
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.can_be_locked():
			continue
		if float(_ignored.get(e.get_instance_id(), 0.0)) > elapsed:
			continue
		var d := player.global_position.distance_to(e.global_position)
		if d > LOOK_RANGE:
			continue
		if running and d > 45.0:
			continue
		if e is Mine and d < 18.0:
			continue
		var score := d
		if e is Reactor:
			score += 400.0
		if e is Mine:
			score += 60.0
		if score < best_score and player.has_line_of_sight(e):
			best_score = score
			best = e
	if best != null and (_target == null or best_score + 20.0 < player.global_position.distance_to(_target.global_position)):
		if best != _target:
			_target_since = elapsed
			targets_engaged += 1
		_target = best


# --- Dodging -----------------------------------------------------------------------
## Reacts to the attacks that are announced: a rail sight line on the ship, or a boss
## winding up its special. A pilot sees these coming and slides off the line.
func _watch_telegraphs() -> void:
	if _dodge_left > 0.0:
		return
	_missiles = _missiles.filter(func(m): return is_instance_valid(m))
	for m in _missiles:
		var to_me: Vector3 = player.global_position - m.global_position
		var d := to_me.length()
		if d < MISSILE_DODGE_RANGE and m.velocity.normalized().dot(to_me / maxf(d, 0.01)) > 0.8:
			_dodge_dir = _dodge_direction(m.velocity.normalized(), false)
			_dodge_left = 0.7
			return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e is Robot or not e.has_los:
			continue
		var from_enemy: Vector3 = player.global_position - e.global_position
		if from_enemy.length() > DODGE_WATCH_RANGE:
			continue
		var sweep := false
		var threat: bool = e._rail_charge > 0.0
		if e is Boss and e.special != "" and e._warning_left() > -0.3:
			threat = true
			sweep = e.special == "sweep"
		if e is Zero and e.special == "beam":
			# The beam follows the ship until it locks, then shows the way it will sweep:
			# wait for that, then go the other way until it's over.
			if not e._beam_locked:
				continue
			var away: Vector3 = -(e._beam_to - e._beam_from).slide(from_enemy.normalized())
			if away.length_squared() > 0.0001:
				_dodge_dir = away.normalized()
				_dodge_left = maxf(0.0, e._warning_left()) + e._active_time()
				return
		if not threat:
			continue
		_dodge_dir = _dodge_direction(from_enemy.normalized(), sweep)
		_dodge_left = DODGE_TIME
		return


## Away from any enemy singularity close enough for its burst to reach.
func _flee_orbs() -> Vector3:
	var push := Vector3.ZERO
	for orb in _orbs:
		if not is_instance_valid(orb):
			continue
		var away: Vector3 = player.global_position - orb.global_position
		if away.length() < Singularity.BURST_RADIUS + 10.0:
			push += away.normalized() * 40.0
	if _orbs.size() > 8:
		_orbs = _orbs.filter(func(o): return is_instance_valid(o))
	return push


## Across the line of fire, toward open space. A flat sweep is dodged up or down.
func _dodge_direction(line: Vector3, sweep: bool) -> Vector3:
	var options: Array[Vector3] = []
	if sweep:
		options = [Vector3.UP, Vector3.DOWN]
	else:
		var side := line.cross(Vector3.UP)
		if side.length_squared() < 0.1:
			side = line.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(line).normalized()
		options = [side, -side, up, -up]
	options.shuffle()
	var space := player.get_world_3d().direct_space_state
	for dir in options:
		var q := PhysicsRayQueryParameters3D.create(player.global_position, player.global_position + dir * 14.0, Game.WORLD)
		if space.intersect_ray(q).is_empty():
			return dir
	return options[0]


# --- Flying -----------------------------------------------------------------------
func _waypoint() -> Vector3:
	if _path.is_empty():
		return _goal
	# The route ends at a cell centre; the last few metres go straight to the item.
	if player.global_position.distance_to(_goal) < 30.0 and _sweep_clear(player.global_position, _goal):
		return _goal
	while _path_index < _path.size() - 1 and player.global_position.distance_to(_path[_path_index]) < 9.0:
		_path_index += 1
	# Cut corners whenever the ship's whole width can fly the straight line.
	var chosen := _path_index
	for i in range(_path_index, mini(_path_index + 8, _path.size())):
		if _sweep_clear(player.global_position, _path[i]):
			chosen = i
	return _path[chosen]


func _sweep_clear(a: Vector3, b: Vector3) -> bool:
	# A sweep that starts touching a wall can report clear straight through the rock.
	var ray := PhysicsRayQueryParameters3D.create(a, b, Game.WORLD)
	if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return false
	var shape := SphereShape3D.new()
	shape.radius = SHIP_SWEEP
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, a)
	q.motion = b - a
	q.collision_mask = Game.WORLD
	var result: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(q)
	return result[0] >= 1.0


func _steer(delta: float) -> void:
	# Killed since the last target pick (a missile or a splash landed this frame).
	if _target != null and not is_instance_valid(_target):
		_target = null
	var at := _waypoint()
	var route_dir := (at - player.global_position).normalized()
	var want_velocity := route_dir * CRUISE_SPEED
	var aim_point := at
	_fire_now = false
	var opening_secret := goal_kind == "secret" and _secret_door != null and player.global_position.distance_to(_secret_door.global_position) < 34.0 and player.has_line_of_sight(_secret_door)
	if opening_secret:
		aim_point = _secret_door.global_position
		want_velocity = Vector3.ZERO
		_force_weapon("laser")
		_fire_now = _aim_error(aim_point) < 0.08
	elif _target != null:
		_fit_weapon_to_range()
		aim_point = Weapons.target_point(_target) + _lead(_target)
		_fire_now = _aim_error(aim_point) < _fire_cone(_target)
		want_velocity = _combat_velocity(route_dir)
	if goal_kind == "escape" and _target == null:
		want_velocity = route_dir * 60.0
		Input.action_press("afterburner")
	if _dodge_left > 0.0:
		want_velocity += _dodge_dir * DODGE_SPEED
	want_velocity += _flee_orbs()
	_aim(aim_point, delta)
	_apply_velocity(_avoid_lava(want_velocity))
	if _fire_now:
		_trigger(delta)
	elif player.rail_charge > 0.0:
		Input.action_release("fire_primary")
	_use_tools(delta)


## Keeps clear of molten floors: climbs whenever the hull, a moment ahead, nears the heat.
func _avoid_lava(want: Vector3) -> Vector3:
	var lava = level.get("lava")
	if lava == null or not lava.has_lava():
		return want
	var h: float = lava.height_above(player.global_position + player.velocity * 0.3, 2)
	if h < lava.heat + 2.0:
		want.y = maxf(want.y, 16.0)
	return want


func _lead(t: Node3D) -> Vector3:
	var speed := 300.0 if player.current_primary == "laser" else 200.0
	var d := player.global_position.distance_to(t.global_position)
	return (t.velocity if t is CharacterBody3D else Vector3.ZERO) * (d / speed) * 0.9


func _fire_cone(t: Node3D) -> float:
	var d := maxf(player.global_position.distance_to(t.global_position), 1.0)
	var radius: float = 8.0 if t is Reactor else (float(t.cfg["radius"]) if t is Robot else 1.5)
	return maxf(FIRE_CONE, atan2(radius, d) * 0.85)


func _combat_velocity(route_dir: Vector3) -> Vector3:
	var to: Vector3 = _target.global_position - player.global_position
	var d := to.length()
	var side := to.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	if fmod(_weave, 3.0) < 0.02:
		_strafe_sign = -_strafe_sign
	var want := side * _strafe_sign * COMBAT_SPEED
	var rushes: bool = _target is Robot and _target._rushes()
	if Game.reactor_down:
		return route_dir * CRUISE_SPEED + side * _strafe_sign * 8.0
	if rushes and d < 40.0:
		want += -to.normalized() * 30.0
	elif _target is Robot and _target.cfg.get("weapon", "") == "arc" and d < Weapons.ARC_RANGE + 6.0:
		# Arc casters can't miss inside their reach; the counter is to stay outside it.
		want += -to.normalized() * 24.0
	elif d > 70.0 and clear_robots:
		want += to.normalized() * 22.0
	elif d < 34.0:
		want += -to.normalized() * 18.0
	return want


func _aim_error(point: Vector3) -> float:
	return (-player.cam.global_basis.z).angle_to(point - player.cam.global_position)


func _aim(point: Vector3, delta: float) -> void:
	var local: Vector3 = player.global_basis.inverse() * (point - player.global_position).normalized()
	var yaw := atan2(-local.x, -local.z)
	var pitch := asin(clampf(local.y, -1.0, 1.0))
	var limit := MAX_TURN_RATE * delta
	# Slight proportional easing, so it doesn't vibrate on the target.
	yaw = clampf(yaw * 0.45, -limit, limit)
	pitch = clampf(pitch * 0.45, -limit, limit)
	var sens := Player.MOUSE_SENS * Settings.mouse_sensitivity
	player._mouse += Vector2(-yaw / sens, -pitch / sens)


## Converts a wanted velocity into thruster presses, the way thumbs would.
func _apply_velocity(want: Vector3) -> void:
	var acc := want * Player.DRAG + (want - player.velocity) * 3.0
	var local := (player.global_basis.inverse() * acc) / Player.ACCEL
	local = local.limit_length(1.0)
	_press_axis("strafe_right", "strafe_left", local.x)
	_press_axis("strafe_up", "strafe_down", local.y)
	_press_axis("thrust_back", "thrust_forward", local.z)


func _press_axis(positive: String, negative: String, value: float) -> void:
	if value > 0.02:
		Input.action_press(positive, value)
	elif value < -0.02:
		Input.action_press(negative, -value)


func _trigger(delta: float) -> void:
	weapons_used[player.current_primary] = float(weapons_used.get(player.current_primary, 0.0)) + delta
	if player.current_primary == "rail":
		_rail_hold += delta
		if _rail_hold < 0.9:
			Input.action_press("fire_primary")
		else:
			_rail_hold = 0.0
	else:
		Input.action_press("fire_primary")
	var tough: bool = _target is Reactor or _target is Boss or (_target is Robot and float(_target.cfg["hp"]) >= 100.0)
	if _target != null and tough and player.lock_target == _target and player._missile_cd <= 0.0 and int(player.ammo.get(player.current_secondary, 0)) > 0:
		missiles_used[player.current_secondary] = int(missiles_used.get(player.current_secondary, 0)) + 1
		Input.action_press("fire_secondary")


func _force_weapon(weapon: String) -> void:
	if player.current_primary != weapon:
		player.select_primary(weapon)


func _use_tools(delta: float) -> void:
	_flare_cd -= delta
	if _flare_cd <= 0.0:
		_flare_cd = 25.0
		Input.action_press("fire_flare")


func _target_distance() -> float:
	return player.global_position.distance_to(_target.global_position) if _target != null else 0.0


func _reaches(weapon: String, distance: float) -> bool:
	return distance <= float(WEAPON_REACH.get(weapon, INF))


func _owned_weapons() -> Array:
	var owned: Array = Weapons.SLOTS.filter(func(w): return w == "laser" or Game.has_upgrade("weapon_" + w))
	if player.energy < 25.0:
		owned = owned.filter(func(w): return float(Weapons.PRIMARY[w]["energy"]) < 1.0)
	return owned


## Takes out the cutter when something is in its face, and puts away anything
## that can't reach the target, the way a pilot would.
func _fit_weapon_to_range() -> void:
	var d := _target_distance()
	if d < CUTTER_SWITCH_IN and _target is Robot and Game.has_upgrade("weapon_cutter"):
		_force_weapon("cutter")
	elif not _reaches(player.current_primary, d):
		_force_weapon("laser")
		_rail_hold = 0.0


## Spends time on every weapon the ship owns, so a broken one can't hide.
func _rotate_weapons(delta: float) -> void:
	_weapon_cd -= delta
	if _weapon_cd > 0.0:
		return
	_weapon_cd = WEAPON_ROTATE_TIME
	var d := _target_distance()
	var owned: Array = _owned_weapons().filter(func(w): return _reaches(w, d))
	if owned.is_empty():
		owned = ["laser"]
	var i: int = (owned.find(player.current_primary) + 1) % owned.size()
	player.select_primary(owned[i])
	_rail_hold = 0.0
	player.cycle_secondary(1)


## Notes the ship leaving the mine: every flyable space is a 10 m route cell, so a hull
## further than a cell's half-diagonal from any cell centre has gone through a wall.
func _check_leak(delta: float) -> void:
	_leak_cd -= delta
	if _leak_cd > 0.0:
		return
	_leak_cd = 0.25
	var here := player.global_position
	var astar: AStar3D = level.astar
	var id := astar.get_closest_point(here, true)
	var outside := id < 0 or astar.get_point_position(id).distance_to(here) > LEAK_DISTANCE
	if outside and not _was_outside:
		note("LEAK: the ship is outside the mine at %s; last inside at %s (keys %s)" % [here.snapped(Vector3.ONE), _leak_from.snapped(Vector3.ONE), Game.keys.keys()])
	_was_outside = outside
	if not outside:
		_leak_from = here


# --- Getting unstuck ---------------------------------------------------------------
## Metres of tunnel still to fly: straight-line distance misleads on winding routes.
func _route_left() -> float:
	if _path.is_empty():
		return player.global_position.distance_to(_goal)
	var total := player.global_position.distance_to(_path[_path_index])
	for i in range(_path_index, _path.size() - 1):
		total += _path[i].distance_to(_path[i + 1])
	return total


func _check_stuck() -> void:
	var dist := _route_left()
	if dist < _best_goal_dist - 1.5 or _target != null:
		_best_goal_dist = minf(dist, _best_goal_dist)
		_last_progress = elapsed
		return
	if elapsed - _last_progress < STUCK_TIME or goal_kind == "objective" and player.global_position.distance_to(_goal) < 40.0:
		return
	stuck_events += 1
	note("STUCK going to %s near %s (goal %s, %d waypoints, at wp %s, next %s, speed %.1f, collisions %d, target %s, left %.0f best %.0f)" % [goal_kind, player.global_position, _goal, _path.size(), _path[_path_index] if not _path.is_empty() else Vector3.ZERO, _waypoint(), player.velocity.length(), player.get_slide_collision_count(), _target, _route_left(), _best_goal_dist])
	_last_progress = elapsed
	_best_goal_dist = INF
	if goal_kind == "pickup":
		# Tucked against a wall where the ship can't get within reach: leave it for a while.
		for n in get_tree().get_nodes_in_group("pickup") + get_tree().get_nodes_in_group("astronaut"):
			if n.global_position.distance_to(_goal) < 1.0:
				_ignored[n.get_instance_id()] = elapsed + 60.0
	if _path.size() > _path_index + 2:
		teleports += 1
		player.global_position = _path[mini(_path_index + 2, _path.size() - 1)]
		player.velocity = Vector3.ZERO
	_replan = 0.0
