extends Node
## Regression checks for the code-review fixes in the player, robots, HUD, sentries,
## cockpit screens and level. godot --headless --path . res://tests/review_fixes_b.tscn

const SHIP := Vector3(0, 10, 38)
const AHEAD := Vector3(0, 10, 18)

var failures := 0
var p: Player


func check(cond: bool, what: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func reset_ship() -> void:
	p.global_position = SHIP
	p.global_basis = Basis.IDENTITY
	p.velocity = Vector3.ZERO
	p.energy = 100.0
	p._fire_cd = 0.0
	p._disrupted = 0.0
	p.shield = 1e6
	p._invuln = 0.0
	p.cloak_left = 0.0
	p.rail_charge = 0.0


func robot(kind: String, at: Vector3, awake := false, bounty := true) -> Robot:
	var r: Robot = Game.level.spawn_robot(kind, at, awake, bounty)
	await frames(1)
	return r


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	AudioServer.set_bus_mute(0, true)
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	p = Game.player
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await frames(2)
	reset_ship()
	await _player_checks()
	await _robot_checks()
	await _ui_checks()
	_level_checks()
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


func _player_checks() -> void:
	# M2: a rail charge fizzles when disrupted or drained, and never leaves energy negative.
	p.current_primary = "rail"
	p.rail_charge = 0.8
	p._disrupted = 1.0
	p.energy = 100.0
	p.release_rail()
	check(p.rail_charge == 0.0 and p.energy == 100.0, "a disrupted rail charge fizzles without firing")
	reset_ship()
	p.rail_charge = 0.8
	p.energy = 5.0
	p.release_rail()
	check(p.rail_charge == 0.0 and p.energy == 5.0, "a rail charge without the energy for it fizzles")
	reset_ship()
	p.rail_charge = 0.6
	p.release_rail()
	check(p.rail_charge == 0.0 and p.energy < 100.0 and p.energy >= 0.0, "a normal rail release still fires and spends energy")
	p.current_primary = "laser"
	# L23: the gallery's laser numbers are the gameplay ones.
	check(is_equal_approx(Player.FIRE_INTERVAL, float(Weapons.PRIMARY["laser"]["interval"])) and is_equal_approx(Player.ENERGY_PER_SHOT, float(Weapons.PRIMARY["laser"]["energy"])), "Player laser constants follow Weapons.PRIMARY")
	# M10: muzzle flashes reuse one light per gun instead of adding a node per shot.
	reset_ship()
	for i in 12:
		p._fire_cd = 0.0
		p.fire_primary()
		await frames(1)
	check(p._flash_lights.size() <= p._muzzles.size(), "laser fire reuses one flash light per muzzle (%d lights)" % p._flash_lights.size())
	await frames(12)
	check(p._flash_lights.all(func(l): return not l.visible), "muzzle flashes go dark between shots")
	for b in Game.level.get_children():
		if b is Bolt:
			b.queue_free()

	# M2 + M3: a death clears the rail charge; only robots that were fighting or away from home stand down.
	reset_ship()
	var sleeper := await robot("lancer", SHIP + Vector3(0, 0, -60))
	sleeper.set_physics_process(false)
	var fighter := await robot("lancer", SHIP + Vector3(0, 0, -40), true)
	var lives := Game.lives
	Game.lives = 5
	p.rail_charge = 0.7
	p._die()
	check(p.rail_charge == 0.0, "dying drops a held rail charge")
	check(not sleeper._returning and not sleeper._needs_home_path, "a death doesn't wake a robot asleep at its post")
	check(fighter._returning and not fighter.alerted, "a death sends a fighting robot home")
	for i in 600:
		await get_tree().physics_frame
		if not p.dead:
			break
	check(not p.dead and p.rail_charge == 0.0, "the ship respawns with no charge (dead=%s finished=%s)" % [p.dead, Game.finished])
	Game.lives = lives
	for r in [sleeper, fighter]:
		if is_instance_valid(r):
			r.queue_free()
	await frames(2)


func _robot_checks() -> void:
	# M4: a cinder blowing itself up isn't a kill, and drops nothing.
	reset_ship()
	var kills := Game.kills
	var score := Game.score
	var pickups := get_tree().get_nodes_in_group("pickup").size()
	var bomb := await robot("cinder", SHIP + Vector3(0, 0, -8), true)
	for i in 240:
		await get_tree().physics_frame
		if not is_instance_valid(bomb):
			break
	await frames(2)
	check(not is_instance_valid(bomb), "the cinder detonated")
	check(Game.kills == kills and Game.score == score, "a self-detonating cinder gives no kill or score")
	check(get_tree().get_nodes_in_group("pickup").size() == pickups, "a self-detonating cinder drops nothing")
	# Shooting one down still counts.
	reset_ship()
	var shot := await robot("cinder", SHIP + Vector3(0, 0, -60))
	shot.take_damage(1e6, shot.global_position, p)
	check(Game.kills == kills + 1, "a cinder the player destroys is a kill")
	# Brood and other mid-fight spawns are worth nothing.
	kills = Game.kills
	score = Game.score
	var hive := await robot("hive", SHIP + Vector3(0, 0, -50), true)
	hive._ability_cd = 0.0
	hive._use_ability(0.016, Vector3.ZERO)
	check(hive._brood.size() == 1 and not hive._brood[0].bounty, "hive brood is spawned without a bounty")
	var tick: Robot = hive._brood[0]
	tick.take_damage(1e6, tick.global_position, p)
	check(Game.kills == kills and Game.score == score, "killing brood gives no kill or score")
	hive.queue_free()
	await frames(2)

	# L5: a longshot's charge doesn't survive a stun or losing sight.
	reset_ship()
	var sniper := await robot("longshot", SHIP + Vector3(0, 0, -60), true)
	sniper._rail_charge = 0.5
	sniper.stun(1.0)
	check(sniper._rail_charge == 0.0, "a stun clears a robot's rail charge")
	sniper._stunned = 0.0
	sniper.has_los = true
	sniper._rail_charge = 0.5
	p.cloak_left = 10.0
	sniper._think()
	check(not sniper.has_los and sniper._rail_charge == 0.0, "losing sight clears a robot's rail charge")
	p.cloak_left = 0.0
	sniper.queue_free()

	# L6: the saw spins down once the robot stands down.
	var saw := await robot("ripper", SHIP + Vector3(0, 0, -30), true)
	saw._melee(0.016, Vector3(0, 0, 30))
	check(saw._saw != null, "a ripper starts its saw")
	saw._stand_down()
	check(saw._saw != null and not saw._saw.playing, "the saw stops when the ripper stands down")
	saw.queue_free()

	# M13: wardens repair on the think beat, by the time that has passed.
	var hurt := await robot("lancer", SHIP + Vector3(0, 0, -60))
	hurt.set_physics_process(false)
	hurt.hp = 10.0
	var medic := await robot("warden", SHIP + Vector3(6, 0, -60))
	medic.set_physics_process(false)
	medic._heal_allies(0.05)
	check(hurt.hp == 10.0, "no repair before the think beat")
	medic._heal_allies(0.05)
	medic._heal_allies(0.05)
	var expected := 10.0 + float(medic.cfg["heal"]) * 0.15
	check(absf(hurt.hp - expected) < 0.01, "repair is scaled by the elapsed time (%.2f, want %.2f)" % [hurt.hp, expected])
	hurt.queue_free()
	medic.queue_free()
	await frames(2)

	# L1: separation comes from the shared roster.
	var a := await robot("tick", SHIP + Vector3(0, 0, -80), true)
	var b := await robot("tick", SHIP + Vector3(4, 0, -80), true)
	a.set_physics_process(false)
	b.set_physics_process(false)
	Robot._roster_frame = -100
	a._sense_neighbours()
	check(a._separation.x < -0.1, "robots push apart using the shared roster")
	a.queue_free()
	b.queue_free()
	await frames(2)

	# Idle robots hover on the model without running physics, and stay put.
	p.cloak_left = 100.0
	var idle := await robot("lancer", SHIP + Vector3(0, 0, -45))
	var home_at := idle.global_position
	var bobbed := false
	for i in 40:
		await get_tree().physics_frame
		bobbed = bobbed or absf(idle._model.position.y) > 0.01
	check(idle.global_position == home_at and bobbed, "an idle robot bobs in place without moving its body")
	p.cloak_left = 0.0
	idle.alert()
	await frames(2)
	check(idle._model.position.y == 0.0, "an alerted robot's model returns to its body")
	idle.queue_free()

	# Far, unseen robots move on alternate frames and ignore each other's bodies.
	var far := await robot("lancer", SHIP + Vector3(0, 0, -150), true)
	far.has_los = false
	check(far._half_rate(), "an unseen robot far from the ship moves at half rate")
	far.has_los = true
	check(not far._half_rate(), "a robot in sight moves every frame")
	far.queue_free()

	# Flank routes put lava cells' extra cost back afterwards.
	var level = Game.level
	var astar: AStar3D = level.astar
	var flanker := await robot("hornet", SHIP + Vector3(0, 0, -10), true)
	flanker.set_physics_process(false)
	var ids := astar.get_point_ids()
	var from_id := astar.get_closest_point(flanker.global_position)
	var goal_id := -1
	for id in ids:
		if astar.get_id_path(from_id, id).size() > 12:
			goal_id = id
			break
	if goal_id >= 0:
		var direct := astar.get_id_path(from_id, goal_id)
		var marked: int = direct[4]
		astar.set_point_weight_scale(marked, 8.0)
		flanker.flank_side = 1
		flanker._pack_count = 1
		flanker.mode = "hunt"
		flanker._route_to(astar.get_point_position(goal_id))
		check(astar.get_point_weight_scale(marked) == 8.0, "a flank route restores a cell's own path cost")
		astar.set_point_weight_scale(marked, 1.0)
	flanker.queue_free()
	await frames(2)


func _ui_checks() -> void:
	# M14: cockpit screens stop redrawing outside the cockpit.
	p.view_mode = Player.View.CHASE
	p._apply_view_mode()
	check(p._mfds.all(func(m): return not m.is_processing()), "cockpit screens stop processing in chase view")
	p.view_mode = Player.View.COCKPIT
	p._apply_view_mode()
	check(p._mfds.all(func(m): return m.is_processing()), "cockpit screens resume in the cockpit")
	# M13: the HUD's line-of-sight cache picks up a robot in plain view.
	reset_ship()
	var hud = Game.level.get_children().filter(func(n): return n is CanvasLayer and n.has_method("_paint"))[0]
	var target := await robot("lancer", SHIP + Vector3(0, 0, -25))
	target.set_physics_process(false)
	await frames(15)
	check(hud._in_sight.has(target.get_instance_id()), "the HUD's sight cache sees a robot ahead")
	target.queue_free()
	await frames(2)
	# M13: sentries re-check sight on a timer, not every frame.
	var sentry := preload("res://scripts/sentry.gd").new()
	Game.level.add_child(sentry)
	sentry.setup(SHIP + Vector3(0, -6, -20), Vector3.UP)
	await frames(2)
	check(sentry._sight_cd <= Sentry.SIGHT_GAP and sentry._query != null, "sentries reuse one sight query on a timer")
	sentry.queue_free()


func _level_checks() -> void:
	var level = Game.level
	# L9: every light turns red when the alarm starts, not only the ones near the ship.
	level.start_alarm()
	check(level.lights.all(func(l): return l.light_color == level.ALARM_COLOR), "the alarm reddens every light at once")
	# L15: settings changes don't bring fog and SSAO back in space.
	level.enter_space()
	Settings.settings_changed.emit()
	check(not level._env.volumetric_fog_enabled and not level._env.ssao_enabled, "settings changes keep space clear of fog and SSAO")
