extends Node
## Every weapon, enemy behaviour, mine and power-up, staged in the open launch bay.
## godot --headless --path . res://tests/weapons.tscn

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
	p.energy = 200.0
	p._fire_cd = 0.0
	p._missile_cd = 0.0
	p._disrupted = 0.0
	p.shield = 1e6
	p._invuln = 0.0
	p.invincible_left = 0.0
	p.cloak_left = 0.0


func dummy(kind := "lancer", at := AHEAD) -> Robot:
	var r: Robot = Game.level.spawn_robot(kind, at)
	await frames(2)
	r.set_physics_process(false)
	r.hp = 100000.0
	return r


func _ready() -> void:
	Progress.path = "user://test_progress.cfg"
	Settings.unlock_all = false
	Game.reset_run()
	add_child(load("res://scenes/level.tscn").instantiate())
	await frames(30)
	p = Game.player
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await frames(2)
	reset_ship()

	# Colours follow damage.
	check(Bolt.color_for_damage(10.0) == Player.LASER_COLORS[0], "10 damage is green")
	check(Bolt.color_for_damage(13.0) == Player.LASER_COLORS[0], "13 damage is green")
	check(Bolt.color_for_damage(14.0) == Player.LASER_COLORS[1], "14 damage is yellow")
	check(Bolt.color_for_damage(25.0) == Player.LASER_COLORS[2], "25 damage is red")
	check(Bolt.color_for_damage(99.0) == Player.LASER_COLORS[3], "99 damage is magenta")
	var low := []
	for kind in Robot.TYPES:
		var c: Dictionary = Robot.TYPES[kind]
		if c.has("dmg") and c["dmg"] < 10.0:
			low.append(kind)
	check(low.is_empty() and Sentry.SHOT_DAMAGE >= 10.0 and Reactor.NOVA_DAMAGE >= 10.0, "no enemy does under 10 damage %s" % str(low))

	# Every robot type spawns and has a working model.
	for kind in Robot.TYPES:
		var r: Robot = Game.level.spawn_robot(kind, Vector3(0, 10, 0))
		await frames(1)
		check(is_instance_valid(r) and r._model != null, kind + " spawns")
		r.free()

	# Primaries.
	for weapon in ["cutter", "arc", "prism", "singularity", "rail"]:
		reset_ship()
		Game.upgrades.append("weapon_" + weapon)
		p.select_primary(weapon)
		check(p.current_primary == weapon, weapon + " can be selected once held")
		var near := AHEAD if weapon != "cutter" else SHIP + Vector3(0, 0, -11)
		var t: Robot = await dummy("lancer", near)
		var hp0 := t.hp
		var energy0 := p.energy
		if weapon == "rail":
			p.rail_charge = 1.0
			p.release_rail()
		else:
			p.fire_primary()
		await frames(340 if weapon == "singularity" else 60)
		check(t.hp < hp0, "%s damages a robot (%.0f)" % [weapon, hp0 - t.hp])
		if weapon != "cutter":
			check(p.energy < energy0, weapon + " spends energy")
		t.free()
	await _power_scaling()
	reset_ship()
	Game.upgrades = []
	p.select_primary("arc")
	p.current_primary = "laser"
	p.select_primary("arc")
	check(p.current_primary == "laser", "a weapon you don't hold can't be selected")

	# Prism bolts bounce off walls and rail goes through a line of targets.
	reset_ship()
	# Sideways, at the spawn room wall: the way ahead is a generated tunnel of any length.
	var b := Bolt.launch(SHIP, Vector3.LEFT, 200.0, 10.0, Weapons.PRISM_COLOR, Game.WORLD, 1.0, p, 3)
	await frames(90)
	check(not is_instance_valid(b) or b.bounces < 3, "prism bolts bounce")
	var first: Robot = await dummy("tick", AHEAD + Vector3(0, 0, 10))
	var second: Robot = await dummy("tick", AHEAD)
	var hp1 := first.hp
	var hp2 := second.hp
	Weapons.rail(SHIP + Vector3(0, 0, -3), Vector3.FORWARD, 50.0, Game.WORLD | Game.ENEMY, p)
	check(first.hp < hp1 and second.hp < hp2, "rail pierces every target in line")
	first.free()
	second.free()
	var arc_a: Robot = await dummy("tick", AHEAD)
	var arc_b: Robot = await dummy("tick", AHEAD + Vector3(14, 0, 0))
	var arc_a0 := arc_a.hp
	var arc_b0 := arc_b.hp
	Weapons.arc(SHIP, Vector3.FORWARD, 18.0, true, p)
	check(arc_a.hp < arc_a0 and arc_b.hp < arc_b0, "arc jumps between robots")
	arc_a.free()
	arc_b.free()

	# Missiles.
	for kind in ["cluster", "bunker", "swarm"]:
		reset_ship()
		p.ammo[kind] = 2
		p.select_secondary(kind)
		var t: Robot = await dummy("lancer", SHIP + Vector3(0, 0, -30))
		p.lock_target = t
		var hp0 := t.hp
		p.fire_missile()
		check(int(p.ammo[kind]) == 1, kind + " uses ammo")
		await frames(220)
		check(t.hp < hp0, "%s damages a robot (%.0f)" % [kind, hp0 - t.hp])
		t.free()
	reset_ship()
	p.ammo["emp"] = 1
	p.select_secondary("emp")
	var stunned: Robot = await dummy("tick", SHIP + Vector3(0, 0, -30))
	p.lock_target = stunned
	var stun_hp := stunned.hp
	p.fire_missile()
	await frames(120)
	check(stunned._stunned > 0.0 and stunned.hp == stun_hp, "EMP stuns without damage")
	stunned.free()
	reset_ship()
	p.ammo["mine"] = 1
	p.select_secondary("mine")
	p.fire_missile()
	await frames(2)
	var mines := get_tree().root.find_children("*", "Mine", true, false)
	check(mines.size() == 1 and mines[0].kind == "player", "a mine is dropped behind the ship")
	var bait: Robot = await dummy("lancer", mines[0].global_position + Vector3(4, 0, 0))
	var bait_hp := bait.hp
	await frames(100)
	check(bait.hp < bait_hp, "dropped mines catch robots")
	bait.free()

	# Melee and enemy-specific weapons, using the same shots as the player.
	reset_ship()
	var saw: Robot = Game.level.spawn_robot("ripper", SHIP + Vector3(0, 0, -6), true)
	var s0 := p.shield
	await frames(120)
	check(p.shield < s0, "melee robots hit on contact")
	saw.queue_free()
	await frames(2)
	reset_ship()
	var bomb: Robot = Game.level.spawn_robot("cinder", SHIP + Vector3(0, 0, -6), true)
	s0 = p.shield
	await frames(120)
	check(not is_instance_valid(bomb) and p.shield < s0, "kamikazes blow themselves up on you")
	await frames(2)
	for kind in ["spark", "longshot", "glint", "gravitar"]:
		reset_ship()
		var shooter: Robot = Game.level.spawn_robot(kind, AHEAD, true)
		await frames(3)
		shooter.look_at(p.global_position, Vector3.UP)
		s0 = p.shield
		var seen := false
		for i in 1500:
			await get_tree().physics_frame
			reset_ship_pos()
			if p.shield < s0:
				seen = true
				break
		check(seen, kind + " can hurt the player with its own weapon")
		shooter.queue_free()
		await frames(2)

	# Abilities.
	reset_ship()
	var hurt: Robot = await dummy("lancer", AHEAD)
	hurt.cfg = hurt.cfg.duplicate()
	hurt.cfg["hp"] = 100.0
	hurt.hp = 10.0
	var medic: Robot = Game.level.spawn_robot("warden", AHEAD + Vector3(6, 0, 0), true)
	await frames(240)
	check(hurt.hp > 10.0, "wardens repair allies")
	medic.queue_free()
	hurt.free()
	await frames(2)
	var shade: Robot = await dummy("shade", AHEAD)
	var saw_hidden := false
	var saw_visible := false
	for i in 200:
		shade._phase += 0.05
		if shade._is_cloaked():
			saw_hidden = true
		else:
			saw_visible = true
	check(saw_hidden and saw_visible, "regular cloakers fade in and out")
	shade._reveal = 1.0
	check(not shade._is_cloaked(), "hitting a cloaker reveals it")
	shade.free()

	# Mines.
	for kind in ["prox", "pulse"]:
		reset_ship()
		var m := Mine.spawn(kind, SHIP + Vector3(0, 0, -8))
		await frames(100)
		check(not is_instance_valid(m), kind + " mine triggers when close")
		if kind == "pulse":
			check(p.is_disrupted(), "pulse mines knock weapons offline")
			var before := get_tree().get_nodes_in_group("enemy").size()
			var d: Robot = await dummy("lancer", AHEAD)
			var d0 := d.hp
			p._fire_cd = 0.0
			p.current_primary = "laser"
			p.fire_primary()
			await frames(30)
			check(d.hp == d0, "weapons really are offline (%d)" % before)
			d.free()
	reset_ship()
	var seeker := Mine.spawn("seeker", SHIP + Vector3(0, 0, -30))
	await frames(80)
	var z0 := seeker.global_position.z
	await frames(40)
	check(is_instance_valid(seeker) and seeker.global_position.z > z0, "seeker mines chase the ship")
	seeker.queue_free()
	reset_ship()
	var wire := Mine.spawn("tripwire", Vector3(-24.5, 10, 30), Vector3.RIGHT)
	await frames(100)
	check(is_instance_valid(wire) and wire._wire_end != Vector3.ZERO, "tripwire draws a beam and waits")
	p.global_position = Vector3(0, 10, 30)
	await frames(10)
	check(not is_instance_valid(wire), "crossing the beam sets it off")
	await frames(2)
	reset_ship()
	var shootable := Mine.spawn("prox", AHEAD)
	await frames(2)
	shootable.take_damage(100.0, AHEAD, p)
	check(not is_instance_valid(shootable) or shootable.is_queued_for_deletion(), "mines can be shot")
	await frames(2)

	# Power-ups.
	reset_ship()
	p.activate_power("power_invincible")
	s0 = p.shield
	p.take_damage(50.0, SHIP, null)
	check(p.shield == s0 and p.invincible_left > 29.0, "invincibility blocks damage for 30 s")
	reset_ship()
	var hunter: Robot = Game.level.spawn_robot("lancer", SHIP + Vector3(0, 0, -30), true)
	await frames(40)
	check(hunter.has_los, "robots see a visible ship")
	p.activate_power("power_cloak")
	await frames(40)
	check(not hunter.has_los and p.cloak_left > 28.0, "invisibility hides the ship from a distance")
	p.global_position = hunter.global_position + Vector3(0, 0, 10)
	await frames(40)
	check(hunter.has_los, "flying right past a robot still gets noticed")
	hunter.queue_free()
	await frames(2)

	# Boss.
	reset_ship()
	var boss: Boss = Game.level.spawn_robot("overseer", AHEAD, true) as Boss
	await frames(3)
	check(boss.phase() == 1, "boss starts in phase one")
	boss.hp = boss.cfg["hp"] * 0.5
	check(boss.phase() == 2, "boss enters phase two")
	boss.hp = boss.cfg["hp"] * 0.2
	check(boss.phase() == 3, "boss enters phase three")
	boss.stun(5.0)
	check(boss._stunned <= Boss.STUN_LIMIT, "EMP only staggers the boss")
	boss._stunned = 0.0
	s0 = p.shield
	var hit := false
	for i in 900:
		await get_tree().physics_frame
		reset_ship_pos()
		if p.shield < s0:
			hit = true
			break
	check(hit, "boss attacks")
	boss.hp = 1.0
	boss.take_damage(10.0, AHEAD, p)
	check(Game.reactor_down, "killing the boss starts the escape")
	await frames(10)

	# Catch-up pickups only come from the last two levels, at most two of them.
	check(Game.earlier_upgrades(0).is_empty(), "no catch-up on level 1")
	check(Game.earlier_upgrades(9).size() <= 2 and not Game.earlier_upgrades(9).has("upgrade_dual_fire"), "level 10 offers only recent upgrades")
	check(Game.earlier_upgrades(2).has("upgrade_dual_fire"), "level 3 still offers Cannon Sync")
	DirAccess.remove_absolute(Progress.path)
	print("RESULT failures=%d" % failures)
	get_tree().quit(failures)


## Every primary scales with the laser level exactly as the cannon does, so their
## level-1 balance holds at every level; missiles scale by a gentler curve.
func _power_scaling() -> void:
	var levels := Player.LASER_DAMAGE.size()
	var primaries := ["laser", "cutter", "arc", "rail", "prism", "singularity"]
	var base := {}
	for w in primaries:
		base[w] = Weapons.primary_damage(w, 1)
	check(is_equal_approx(base["laser"], Player.LASER_DAMAGE[0]) and is_equal_approx(base["cutter"], Weapons.PRIMARY["cutter"]["damage"]) and is_equal_approx(base["rail"], Weapons.RAIL_MAX_DAMAGE), "laser level 1 keeps every weapon's listed damage")
	var order := primaries.duplicate()
	order.sort_custom(func(a, b): return base[a] < base[b])
	for level in range(1, levels + 1):
		var mult := Weapons.power_mult(level)
		check(is_equal_approx(mult, Player.LASER_DAMAGE[level - 1] / Player.LASER_DAMAGE[0]), "laser level %d multiplies damage by the cannon's own ratio (%.2f)" % [level, mult])
		var line := []
		var ok := true
		for w in primaries:
			var d := Weapons.primary_damage(w, level)
			ok = ok and is_equal_approx(d, base[w] * mult)
			line.append("%s %.0f" % [w, d])
		check(ok, "laser level %d: every primary does base x %.2f (%s)" % [level, mult, ", ".join(line)])
		check(is_equal_approx(Weapons.primary_damage("laser", level), Player.LASER_DAMAGE[level - 1]), "laser level %d: the cannon still fires its table damage" % level)
		var now := primaries.duplicate()
		now.sort_custom(func(a, b): return Weapons.primary_damage(a, level) < Weapons.primary_damage(b, level))
		check(now == order, "laser level %d keeps the weapons' damage order" % level)
		check(is_equal_approx(Weapons.rail_damage(0.0, level), Weapons.RAIL_MIN_DAMAGE * mult), "laser level %d: an uncharged rail scales too" % level)
		var mm := Weapons.missile_mult(level)
		var mline := []
		var mok := mm >= 1.0 and mm <= mult
		for m in ["homing", "cluster", "cluster_bomblet", "swarm", "bunker", "mine"]:
			var lvl1 := Weapons.secondary_damage(m, 1)
			mok = mok and is_equal_approx(Weapons.secondary_damage(m, level), lvl1 * mm)
			mline.append("%s %.0f" % [m, Weapons.secondary_damage(m, level)])
		check(mok, "laser level %d: missiles scale gentler, x %.2f (%s)" % [level, mm, ", ".join(mline)])
	check(Weapons.secondary_damage("emp", levels) == 0.0, "the EMP still does no damage")
	check(Weapons.power_mult(levels + 3) == Weapons.power_mult(levels) and Weapons.power_mult(0) == Weapons.power_mult(Game.laser_level()), "past the last level the curve holds; 0 means the ship's own level")

	# In flight: the cutter and the prism hit harder, by the cannon's ratio, once the
	# lasers are upgraded, and so does a homing missile, by the gentler one.
	var top := Game.LASER_PREFIX + str(levels)
	for w in ["cutter", "prism"]:
		var dealt := []
		for upgraded in [false, true]:
			reset_ship()
			Game.upgrades = ["weapon_" + w]
			if upgraded:
				Game.upgrades.append(top)
			p.select_primary(w)
			var t: Robot = await dummy("lancer", AHEAD if w != "cutter" else SHIP + Vector3(0, 0, -11))
			var hp0 := t.hp
			p.fire_primary()
			await frames(60)
			dealt.append(hp0 - t.hp)
			t.free()
		var ratio: float = dealt[1] / maxf(dealt[0], 0.001)
		check(absf(ratio - Weapons.power_mult(levels)) < 0.05, "%s at laser level %d hits %.2fx as hard (%.0f vs %.0f)" % [w, levels, ratio, dealt[1], dealt[0]])
	var hits := []
	for upgraded in [false, true]:
		reset_ship()
		Game.upgrades = [top] if upgraded else []
		p.ammo["homing"] = 2
		p.select_secondary("homing")
		var t: Robot = await dummy("lancer", SHIP + Vector3(0, 0, -30))
		p.lock_target = t
		var hp0 := t.hp
		p.fire_missile()
		await frames(120)
		hits.append(hp0 - t.hp)
		t.free()
	var mratio: float = hits[1] / maxf(hits[0], 0.001)
	check(absf(mratio - Weapons.missile_mult(levels)) < 0.05, "a homing missile at laser level %d hits %.2fx as hard (%.0f vs %.0f)" % [levels, mratio, hits[1], hits[0]])
	Game.upgrades = []


func reset_ship_pos() -> void:
	p.global_position = SHIP
	p.velocity = Vector3.ZERO
	p._invuln = 0.0
