class_name Player
extends CharacterBody3D
## WREN-9: six-degrees-of-freedom flight, weapons and camera rigs.

enum View { CHASE, COCKPIT, CLEAN }

const ACCEL := 66.0
const DRAG := 1.65  # top speed = ACCEL / DRAG = 40 m/s
const AFTERBURNER_ACCEL := 52.0  # adds on top of ACCEL for a top speed near 72 m/s
const AFTERBURNER_DRAIN := 9.0
const AFTERBURNER_MIN_ENERGY := 2.0
const AFTERBURNER_FOV := 9.0
const ROLL_RATE := 2.6
const KEY_LOOK_RATE := 1.7
const MOUSE_SENS := 0.0021
## The pulse cannons' numbers live in Weapons.PRIMARY; these copies are for the gallery.
const FIRE_INTERVAL: float = Weapons.PRIMARY["laser"]["interval"]
const MISSILE_INTERVAL := 0.55
const FLARE_INTERVAL := 0.45
const POWER_DURATION := 30.0
const FLARE_ENERGY := 0.5
## Holding the rear-view key longer than this means "peek": letting go returns forward.
const REAR_HOLD_TIME := 0.25
const ENERGY_PER_SHOT: float = Weapons.PRIMARY["laser"]["energy"]
const ENERGY_REGEN := 1.6
const BOLT_SPEED := 300.0
## Laser levels 1 to 4: green, yellow, red, magenta.
const LASER_DAMAGE := [13.0, 21.0, 30.0, 42.0]
const LASER_COLORS := [Color(0.3, 1.0, 0.35), Color(1.0, 0.85, 0.2), Color(1.0, 0.22, 0.15), Color(1.0, 0.25, 0.9)]
const UPGRADE_DUAL := "dual_fire"
const CHASE_OFFSET := Vector3(0.0, 2.9, 12.5)
const RADIUS := 2.0
const WALL_BOUNCE_SPEED := 15.0
const WALL_DAMAGE_SPEED := 20.0
const WALL_DAMAGE_SCALE := 0.075  # a full-speed head-on crash costs about 1.5 shield
const WALL_SAFE_SHIELD := 10.0  # as in Descent, walls can never finish you off
const START_SHIELD := 100.0
const MAX_SHIELD := 200.0
const START_ENERGY := 100.0
const MAX_ENERGY := 200.0
const FLAME_LENGTH := 5.0
const LOW_SHIELD := 30.0
const LOW_SHIELD_BEEP := 1.15
const POWER_WARNING := 3.0
const LOCK_INTERVAL := 0.05
const MUZZLE_FLASH_TIME := 0.07
const MUZZLE_FLASH_ENERGY := 3.0

var shield := START_SHIELD
var energy := START_ENERGY
var ammo: Dictionary = {"homing": Game.DEFAULT_MISSILES}
var missiles: int:
	get:
		return ammo.get("homing", 0)
	set(value):
		ammo["homing"] = value
var current_primary := "laser"
var current_secondary := "homing"
var rail_charge := 0.0
var _disrupted := 0.0
var invincible_left := 0.0
var cloak_left := 0.0
var dead := false
var lock_target: Node3D

var _mouse := Vector2.ZERO
var view_mode := View.COCKPIT
var cinematic := false
var rear_view := false
var _rear_pressed_at := 0.0
var _flare_cd := 0.0
var _cabin_sway := Vector3.ZERO
var _mfds: Array[CockpitMfd] = []
## Each screen's mount and the transform the cabin model gives it.
var _screen_mounts: Array[Node3D] = []
var _screen_rest: Array[Transform3D] = []
var _fire_cd := 0.0
var _missile_cd := 0.0
var _shot_side := 1
var _missile_side := 1
var _shake := 0.0
var _invuln := 2.0
var _thrust_level := 0.0
var _roll_input := 0.0
var _visual_tilt := Vector3.ZERO
var _chase_pos := Vector3.ZERO
var _chase_basis := Basis.IDENTITY
var _spawn_transform: Transform3D
var afterburning := false
var _lock_cd := 0.0
## What landed the last hit, for test reports.
var last_attacker := ""
var _burn_fov := 0.0
var _low_beep := 0.0
var _rail_sound_on := false
var _bump_cd := 0.0

var ship: Node3D
var cockpit: Node3D
var cam: Camera3D
var view_tuning: ViewTuning = ViewTuning.current()
var headlight: SpotLight3D
var _muzzles: Array[Node3D] = []
var _ports: Array[Node3D] = []
var loadout: ShipLoadout
var _flames: Array[MeshInstance3D] = []
var _engine_light: OmniLight3D
var _glow_mat: StandardMaterial3D
## One reusable flash light per gun, pulsed on each shot instead of a new light per bolt.
var _flash_lights: Array[OmniLight3D] = []
var _flash_left: Array[float] = []


func _ready() -> void:
	Game.player = self
	shield = Game.start_shield
	energy = Game.start_energy
	ammo = Game.start_ammo.duplicate()
	ammo["homing"] = Game.start_missiles
	add_to_group("player")
	collision_layer = Game.PLAYER
	collision_mask = Game.WORLD | Game.ENEMY
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	ship = load("res://assets/models/wren9.glb").instantiate()
	Mats.apply(ship)
	add_child(ship)
	_glow_mat = Mats.unique_glow(ship, "glow_engine")
	for n in ["Muzzle_R", "Muzzle_L"]:
		_muzzles.append(ship.find_child(n, true, false))
	for n in ["MissilePort_R", "MissilePort_L"]:
		_ports.append(ship.find_child(n, true, false))
	for n in ["EngineFX_R", "EngineFX_L"]:
		_flames.append(_make_flame(ship.find_child(n, true, false)))
	# The equipped gun and missiles are models on the hull's hardpoints; bolts leave their muzzles.
	loadout = ShipLoadout.attach(ship, current_primary, current_secondary, int(ammo.get(current_secondary, 0)), self)
	if loadout != null and not loadout.muzzles.is_empty():
		_muzzles = loadout.muzzles

	cockpit = load("res://assets/models/cockpit.glb").instantiate()
	Mats.apply(cockpit)
	add_child(cockpit)
	for mount_mode in [["Screen_L", CockpitMfd.Mode.STATUS], ["Screen_R", CockpitMfd.Mode.RADAR]]:
		var mfd := CockpitMfd.new()
		mfd.mode = mount_mode[1]
		var mount: Node3D = cockpit.find_child(mount_mode[0], true, false)
		mount.add_child(mfd)
		_mfds.append(mfd)
		_screen_mounts.append(mount)
		_screen_rest.append(mount.transform)

	cam = Camera3D.new()
	cam.top_level = true
	cam.fov = Settings.fov
	cam.far = 900.0
	add_child(cam)
	cam.make_current()
	apply_view_tuning()

	headlight = SpotLight3D.new()
	headlight.spot_range = 95.0
	headlight.spot_angle = 36.0
	headlight.spot_attenuation = 0.9
	headlight.light_energy = 7.0
	headlight.light_color = Color(0.92, 0.96, 1.0)
	headlight.shadow_enabled = Settings.uses_shadows()
	headlight.light_volumetric_fog_energy = 0.45
	headlight.position = Vector3(0, 0.3, -3.8)
	add_child(headlight)

	_engine_light = OmniLight3D.new()
	_engine_light.light_color = Color(0.35, 0.7, 1.0)
	_engine_light.omni_range = 20.0
	_engine_light.position = Vector3(0, 0, 5.2)
	add_child(_engine_light)

	Settings.settings_changed.connect(_on_settings_changed)

	_spawn_transform = global_transform
	if not Game.autopilot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_view_mode()
	_chase_pos = global_position
	_chase_basis = global_basis


## Puts the cabin where the tuning says; the cameras read it every frame.
func apply_view_tuning() -> void:
	cockpit.position = view_tuning.cabin_offset + _cabin_sway
	cockpit.rotation_degrees = view_tuning.cabin_rotation
	cockpit.scale = Vector3.ONE * view_tuning.cabin_scale
	cam.near = view_tuning.camera_near
	_place_screen(0, view_tuning.screen_left_offset, view_tuning.screen_left_rotation, view_tuning.screen_left_scale, view_tuning.screen_left_brightness)
	_place_screen(1, view_tuning.screen_right_offset, view_tuning.screen_right_rotation, view_tuning.screen_right_scale, view_tuning.screen_right_brightness)
	_apply_view_mode()


## Moves in cabin axes, and turns about the screen's own axes.
func _place_screen(index: int, offset: Vector3, degrees: Vector3, size: float, brightness: float) -> void:
	var rest := _screen_rest[index]
	var turn := Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))
	_screen_mounts[index].transform = Transform3D((rest.basis * turn).scaled_local(Vector3.ONE * size), rest.origin + offset)
	_mfds[index].set_brightness(brightness)


## Redraws the camera while the world is paused, for the cockpit tuner.
func refresh_view() -> void:
	_update_camera(0.0)
	_update_fov()


func _on_settings_changed() -> void:
	headlight.shadow_enabled = Settings.uses_shadows()
	if not cinematic:
		cam.fov = Settings.fov


func _make_flame(mount: Node3D) -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint = vec3(0.45, 1.1, 2.6);
void fragment() {
	float along = 1.0 - UV.y;
	float core = pow(abs(dot(NORMAL, VIEW)), 1.6);
	ALBEDO = mix(tint, vec3(2.2, 2.6, 3.0), along * along);
	ALPHA = clamp(core * along * along * 1.1, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var cone := CylinderMesh.new()
	cone.top_radius = 0.46
	cone.bottom_radius = 0.04
	cone.height = FLAME_LENGTH
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	cone.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(mi)
	# Cylinder +Y is the wide end: tip it so the taper trails behind the ship.
	mi.rotation_degrees = Vector3(-90, 0, 0)
	return mi


func _apply_view_mode() -> void:
	ship.visible = _ship_shown()
	cockpit.visible = view_mode == View.COCKPIT and not cinematic and not rear_view
	for mfd in _mfds:
		mfd.set_active(cockpit.visible)


func _ship_shown() -> bool:
	return view_mode == View.CHASE or cinematic or (_rear_from_cockpit() and view_tuning.rear_show_ship)


func _rear_from_cockpit() -> bool:
	return rear_view and view_mode == View.COCKPIT


func _unhandled_input(event: InputEvent) -> void:
	if cinematic:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += event.relative
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		cycle_secondary(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	elif event.is_action_pressed("next_missile"):
		cycle_secondary(1)
	elif event.is_action_pressed("toggle_view"):
		view_mode = ((view_mode + 1) % 3) as View
		_apply_view_mode()
		Game.say(["CHASE VIEW", "COCKPIT VIEW", "CLEAN VIEW"][view_mode])
		_chase_pos = global_position + global_basis * CHASE_OFFSET
		_chase_basis = global_basis
	elif event.is_action_pressed("rear_view"):
		_rear_pressed_at = Time.get_ticks_msec() / 1000.0
		set_rear_view(not rear_view)
	elif event.is_action_released("rear_view"):
		if rear_view and Time.get_ticks_msec() / 1000.0 - _rear_pressed_at > REAR_HOLD_TIME:
			set_rear_view(false)
	elif event.is_action_pressed("toggle_light"):
		headlight.visible = not headlight.visible
	else:
		var slot := _weapon_key(event)
		if slot >= 0:
			select_primary(Weapons.SLOTS[slot], true)


func _weapon_key(event: InputEvent) -> int:
	for i in Weapons.SLOTS.size():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			return i
	return -1


func _physics_process(delta: float) -> void:
	_fire_cd -= delta
	_missile_cd -= delta
	_flare_cd -= delta
	_disrupted -= delta
	invincible_left = maxf(0.0, invincible_left - delta)
	if cloak_left > 0.0:
		cloak_left = maxf(0.0, cloak_left - delta)
		if cloak_left <= 0.0:
			_fade_ship(0.0)
	_invuln -= delta
	_bump_cd -= delta
	if invincible_left > 0.0 and invincible_left - delta * 0.5 < POWER_WARNING and invincible_left + delta * 0.5 >= POWER_WARNING:
		Sfx.play("power_ending", null, -2.0)
	if cloak_left > 0.0 and cloak_left - delta * 0.5 < POWER_WARNING and cloak_left + delta * 0.5 >= POWER_WARNING:
		Sfx.play("power_ending", null, -2.0)
	if cinematic:
		return
	if dead or Game.finished:
		velocity *= exp(-3.0 * delta)
		return
	_steer(delta)
	_translate(delta)
	# Passive recharge only refills to the starting level; beyond that takes pickups.
	if energy < START_ENERGY:
		energy = minf(START_ENERGY, energy + ENERGY_REGEN * delta)
	_lock_cd -= delta
	if _lock_cd <= 0.0:
		_lock_cd = LOCK_INTERVAL
		_update_lock()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Game.autopilot:
		var trigger := Input.is_action_pressed("fire_primary")
		if current_primary == "rail":
			_update_rail(trigger, delta)
		elif trigger:
			fire_primary()
		if Input.is_action_pressed("fire_secondary"):
			fire_missile()
		if Input.is_action_pressed("fire_flare"):
			fire_flare()


func _steer(delta: float) -> void:
	var sens := MOUSE_SENS * Settings.mouse_sensitivity
	var yaw := -_mouse.x * sens
	var pitch := -_mouse.y * sens * (-1.0 if Settings.invert_y else 1.0)
	_mouse = Vector2.ZERO
	yaw += Input.get_axis("look_right", "look_left") * KEY_LOOK_RATE * delta
	pitch += Input.get_axis("look_down", "look_up") * KEY_LOOK_RATE * delta
	var want_roll := Input.get_axis("roll_right", "roll_left")
	_roll_input = lerpf(_roll_input, want_roll, 1.0 - exp(-10.0 * delta))
	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.RIGHT, pitch)
	rotate_object_local(Vector3.BACK, _roll_input * ROLL_RATE * delta)
	global_basis = global_basis.orthonormalized()
	_visual_tilt = _visual_tilt.lerp(Vector3(pitch * 9.0, yaw * 9.0, 0), 1.0 - exp(-9.0 * delta))


func _translate(delta: float) -> void:
	var input := Vector3(
		Input.get_axis("strafe_left", "strafe_right"),
		Input.get_axis("strafe_down", "strafe_up"),
		Input.get_axis("thrust_forward", "thrust_back")
	).limit_length(1.0)
	_update_afterburner(delta)
	velocity += global_basis * input * ACCEL * delta
	if afterburning:
		velocity += -global_basis.z * AFTERBURNER_ACCEL * delta
	velocity *= exp(-DRAG * delta)
	var before := velocity
	move_and_slide()
	_thrust_level = lerpf(_thrust_level, maxf(-input.z, 0.25 * input.length()), 1.0 - exp(-7.0 * delta))
	ship.rotation = Vector3(_visual_tilt.x, _visual_tilt.y, clampf(-input.x * 0.28 + _roll_input * 0.2, -0.6, 0.6))
	if get_slide_collision_count() == 0:
		return
	var col := get_slide_collision(0)
	var n := col.get_normal()
	var impact := -before.dot(n)
	if impact > WALL_BOUNCE_SPEED:
		velocity += n * impact * 0.55
		if _bump_cd <= 0.0:
			_bump_cd = 0.25
			Sfx.play("wall_bump", null, -7.0 + clampf(impact * 0.12, 0.0, 5.0), randf_range(0.9, 1.1))
		if impact > WALL_DAMAGE_SPEED and shield > WALL_SAFE_SHIELD:
			take_damage((impact - WALL_DAMAGE_SPEED) * WALL_DAMAGE_SCALE, col.get_position(), null)
		add_shake(0.35)
		Fx.sparks(col.get_position(), n, Color(1.0, 0.7, 0.3))


## Shift burns energy for a large surge of forward speed.
func _update_afterburner(delta: float) -> void:
	var want := Input.is_action_pressed("afterburner") and energy > AFTERBURNER_MIN_ENERGY
	if want and not afterburning:
		Sfx.play("afterburner", null, -5.0)
	afterburning = want
	if afterburning:
		energy = maxf(0.0, energy - AFTERBURNER_DRAIN * delta)
		Sfx.loop("afterburner_loop", -13.0, 0.85 + velocity.length() / 120.0)
	else:
		Sfx.stop_loop("afterburner_loop")


func aim_point() -> Vector3:
	var origin := global_position if rear_view else cam.global_position
	var forward := _aim_forward()
	var query := PhysicsRayQueryParameters3D.create(origin + forward * 2.0, origin + forward * 700.0, Game.WORLD | Game.ENEMY)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else origin + forward * 700.0


## Guns always point out the nose, even while the camera looks backward.
func _aim_forward() -> Vector3:
	return -global_basis.z if rear_view else -cam.global_basis.z


func fire_primary() -> void:
	var w: Dictionary = Weapons.PRIMARY[current_primary]
	if current_primary == "rail" or _fire_cd > 0.0:
		return
	if energy < float(w["energy"]) or _disrupted > 0.0:
		_fire_cd = 0.3
		Sfx.play("weapon_empty", null, -8.0)
		return
	_fire_cd = w["interval"]
	energy -= float(w["energy"])
	var aim := aim_point()
	var nose := global_position + (-global_basis.z) * 4.0
	var dir := (aim - nose).normalized()
	match current_primary:
		"cutter":
			Weapons.slash(global_position, -global_basis.z, global_basis.x, Weapons.primary_damage("cutter"), self)
		"arc":
			Weapons.arc(_next_muzzle(), dir, Weapons.primary_damage("arc"), true, self)
		"prism":
			var at := _next_muzzle()
			var bolt_dir := (aim - at).normalized()
			Bolt.launch(at + bolt_dir * 1.5, bolt_dir, w["speed"], Weapons.primary_damage("prism"), Weapons.PRISM_COLOR, Game.WORLD | Game.ENEMY, 1.0, self, w["bounces"])
			Sfx.play("prism", null, -8.0, randf_range(0.95, 1.08))
		"singularity":
			Singularity.launch(nose + dir * 4.0, dir, Weapons.primary_damage("singularity"), true)
		_:
			_fire_lasers(aim)


func _fire_lasers(aim: Vector3) -> void:
	_shot_side = 1 - _shot_side
	var sound := "laser_%d" % Game.laser_level()
	if Game.has_upgrade(UPGRADE_DUAL):
		for muzzle in _muzzles:
			_fire_bolt(muzzle, aim)
		Sfx.play(sound, null, -6.0, randf_range(0.9, 0.98))
	else:
		_fire_bolt(_muzzles[_shot_side], aim)
		Sfx.play(sound, null, -8.0, randf_range(0.96, 1.08))


## Alternates between the mounted guns' muzzles, for weapons that fire one at a time.
func _next_muzzle() -> Vector3:
	_shot_side = (_shot_side + 1) % _muzzles.size()
	return _muzzles[_shot_side].global_position


## Hold to charge; letting go fires however much has built up.
func _update_rail(pressed: bool, delta: float) -> void:
	var w: Dictionary = Weapons.PRIMARY["rail"]
	if pressed and _fire_cd <= 0.0 and energy >= float(w["energy"]) and _disrupted <= 0.0:
		if not _rail_sound_on:
			_rail_sound_on = true
			Sfx.play("rail_charge", null, -8.0)
		rail_charge = minf(1.0, rail_charge + delta / Weapons.RAIL_CHARGE_TIME)
	elif rail_charge > 0.0 and not pressed:
		release_rail()


func release_rail() -> void:
	var w: Dictionary = Weapons.PRIMARY["rail"]
	# Knocked offline or drained (by a pulse mine or the afterburner) while charging: it fizzles.
	if _disrupted > 0.0 or energy < float(w["energy"]):
		cancel_rail()
		_fire_cd = 0.3
		Sfx.play("weapon_empty", null, -8.0)
		return
	_fire_cd = w["interval"]
	energy -= float(w["energy"])
	_rail_sound_on = false
	var at := _next_muzzle()
	Weapons.rail(at, (aim_point() - at).normalized(), Weapons.rail_damage(rail_charge), Game.WORLD | Game.ENEMY, self)
	rail_charge = 0.0


func cancel_rail() -> void:
	rail_charge = 0.0
	_rail_sound_on = false


func select_primary(weapon: String, audible := false) -> void:
	if weapon == "laser" or Game.has_upgrade("weapon_" + weapon):
		current_primary = weapon
		cancel_rail()
		if audible:
			Sfx.play("weapon_select", null, -6.0)
	elif audible:
		Sfx.play("weapon_empty", null, -8.0)


func select_secondary(kind: String) -> void:
	if int(ammo.get(kind, 0)) > 0:
		current_secondary = kind


func cycle_secondary(step: int) -> void:
	var at: int = Weapons.ORDER.find(current_secondary)
	for i in range(1, Weapons.ORDER.size() + 1):
		var candidate: String = Weapons.ORDER[posmod(at + step * i, Weapons.ORDER.size())]
		if int(ammo.get(candidate, 0)) > 0:
			if candidate != current_secondary:
				Sfx.play("weapon_select", null, -8.0, 0.8)
			current_secondary = candidate
			return


## Knocks weapons offline and drains energy; used by pulse mines.
func disrupt(seconds: float, drain: float) -> void:
	if cinematic or _invuln > 0.0:
		return
	_disrupted = maxf(_disrupted, seconds)
	energy = maxf(0.0, energy - drain)


## Thirty seconds of either: no damage at all, or robots can't see you past close range.
func activate_power(kind: String) -> void:
	if kind == "power_invincible":
		invincible_left = POWER_DURATION
	else:
		cloak_left = POWER_DURATION
		_fade_ship(0.65)


func is_cloaked() -> bool:
	return cloak_left > 0.0


func _fade_ship(amount: float) -> void:
	for mesh in ship.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).transparency = amount


func is_disrupted() -> bool:
	return _disrupted > 0.0


func _fire_bolt(muzzle: Node3D, aim: Vector3) -> void:
	var tier: int = Game.laser_level() - 1
	var at := muzzle.global_position
	var dir := (aim - at).normalized()
	var damage := Weapons.primary_damage("laser")
	var color: Color = LASER_COLORS[tier]
	# In the cockpit the muzzles sit outside the view, so bolts need a head start.
	Bolt.launch(at + dir * 1.5, dir, BOLT_SPEED, damage, color, Game.WORLD | Game.ENEMY, 1.0, self)
	_muzzle_flash(maxi(0, _muzzles.find(muzzle)), at, color)


func _muzzle_flash(index: int, at: Vector3, color: Color) -> void:
	while _flash_lights.size() <= index:
		var light := OmniLight3D.new()
		light.omni_range = 10.0
		light.visible = false
		add_child(light)
		_flash_lights.append(light)
		_flash_left.append(0.0)
	var flash := _flash_lights[index]
	flash.light_color = color
	flash.light_energy = MUZZLE_FLASH_ENERGY
	flash.global_position = at
	flash.visible = true
	_flash_left[index] = MUZZLE_FLASH_TIME


## Fades the muzzle flashes out, then hides them so they cost nothing between shots.
func _fade_flashes(delta: float) -> void:
	for i in _flash_lights.size():
		if _flash_left[i] <= 0.0:
			continue
		_flash_left[i] -= delta
		if _flash_left[i] <= 0.0:
			_flash_lights[i].visible = false
		else:
			_flash_lights[i].light_energy = MUZZLE_FLASH_ENERGY * _flash_left[i] / MUZZLE_FLASH_TIME


func fire_missile() -> void:
	if _missile_cd > 0.0 or _disrupted > 0.0:
		return
	if int(ammo.get(current_secondary, 0)) <= 0:
		_missile_cd = MISSILE_INTERVAL
		Sfx.play("weapon_empty", null, -8.0)
		return
	_missile_cd = MISSILE_INTERVAL
	ammo[current_secondary] = int(ammo[current_secondary]) - 1
	_missile_side = 1 - _missile_side
	var at := _ports[_missile_side].global_position
	var forward := -global_basis.z
	var mask := Game.WORLD | Game.ENEMY
	var w: Dictionary = Weapons.SECONDARY[current_secondary]
	match current_secondary:
		"swarm":
			_fire_swarm(at, forward, mask)
			Sfx.play("missile_swarm", null, -2.0)
		"bunker":
			Missile.launch(at, forward, null, mask, true, w["speed"], Weapons.secondary_damage("bunker"), "bunker")
		"cluster", "emp":
			Missile.launch(at, forward, _live_lock(), mask, true, Missile.SPEED, Weapons.secondary_damage(current_secondary), current_secondary)
		"mine":
			Mine.spawn("player", global_position + global_basis.z * 6.0)
		_:
			Missile.launch(at, forward, _live_lock(), mask, true, Missile.SPEED, Weapons.secondary_damage("homing"))
	if int(ammo[current_secondary]) <= 0:
		cycle_secondary(1)


## The lock is refreshed a few times a second, so its target may have just died.
func _live_lock() -> Node3D:
	return lock_target if is_instance_valid(lock_target) else null


func _fire_swarm(at: Vector3, forward: Vector3, mask: int) -> void:
	var targets: Array = get_tree().get_nodes_in_group("enemy").filter(func(e): return e.can_be_locked() and e.global_position.distance_to(global_position) < 220.0 and has_line_of_sight(e))
	targets.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	for i in Weapons.SWARM_COUNT:
		var target: Node3D = targets[i % targets.size()] if not targets.is_empty() else null
		var drift := global_basis.x * randf_range(-1, 1) + global_basis.y * randf_range(-1, 1)
		var missile := Missile.launch(at + drift, (forward + drift * 0.3).normalized(), target, mask, true, Missile.SPEED, Weapons.secondary_damage("swarm"))
		missile.scale = Vector3.ONE * 0.55


## Like Descent's, a flare still fires on an empty energy bank.
func fire_flare() -> void:
	if _flare_cd > 0.0:
		return
	_flare_cd = FLARE_INTERVAL
	energy = maxf(0.0, energy - FLARE_ENERGY)
	# Launched from inside the ship's sphere so it can't start on the far side of a wall.
	var dir := (aim_point() - global_position).normalized()
	Flare.launch(global_position + dir * 1.5, dir)


func _update_lock() -> void:
	var best: Node3D = null
	var best_dot := 0.94
	var forward := _aim_forward()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.can_be_locked():
			continue
		var to: Vector3 = e.global_position - global_position
		if to.length() > 260.0:
			continue
		var dot := forward.dot(to.normalized())
		if dot > best_dot and has_line_of_sight(e):
			best_dot = dot
			best = e
	lock_target = best


func has_line_of_sight(target: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, Weapons.target_point(target), Game.WORLD)
	# The reactor is on the world layer too; it must not occlude itself.
	if target is CollisionObject3D:
		q.exclude = [target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func take_damage(amount: float, at: Vector3, source: Object) -> void:
	if dead or _invuln > 0.0 or Game.finished or cinematic:
		return
	if invincible_left > 0.0:
		Sfx.play("shield_absorb", null, -6.0, randf_range(1.2, 1.5))
		return
	# Scraping a wall has no source, and isn't an enemy to be made tougher.
	var scaled: float = amount * Game.diff("damage") if source != null else amount
	shield -= scaled
	Game.player_hurt.emit(scaled)
	if source != null:
		last_attacker = str(source.get("kind")) if source.get("kind") != null else source.get_class()
		Game.player_hit.emit(at)
		Sfx.play("shield_absorb", null, -5.0, randf_range(0.9, 1.1))
	add_shake(clampf(scaled * 0.03, 0.05, 0.5))
	Sfx.play("player_hurt", null, -7.0, randf_range(0.9, 1.1))
	if shield <= 0.0:
		_die()


func _die() -> void:
	shield = 0.0
	dead = true
	cancel_rail()
	Game.lives -= 1
	Game.deaths += 1
	Game.player_died.emit()
	Sfx.play("player_die", null, 0.0)
	Sfx.stop_loop("afterburner_loop")
	afterburning = false
	Fx.explosion(global_position, 8.0, true)
	ship.visible = false
	cockpit.visible = false
	collision_layer = 0
	velocity = Vector3.ZERO
	if Game.lives <= 0:
		Game.end_run(false, "WREN-9 destroyed. No spare airframes.")
		return
	Game.say("AIRFRAME LOST — REDEPLOYING AT LAST CHECKPOINT", Color(1, 0.5, 0.3))
	get_tree().create_timer(2.4).timeout.connect(_respawn)


func _respawn() -> void:
	if Game.finished:
		return
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	dead = false
	rear_view = false
	shield = START_SHIELD
	energy = maxf(energy, 60.0)
	missiles = maxi(missiles, 3)
	_invuln = 2.5
	cancel_rail()
	collision_layer = Game.PLAYER
	Sfx.play("respawn", null, -3.0)
	_apply_view_mode()
	_chase_pos = global_position + global_basis * CHASE_OFFSET
	_chase_basis = global_basis


func set_checkpoint() -> void:
	_spawn_transform = global_transform


func set_rear_view(on: bool) -> void:
	rear_view = on
	_apply_view_mode()
	_chase_pos = global_position + global_basis * _chase_offset()
	_chase_basis = _view_basis(global_basis)


func _chase_offset() -> Vector3:
	return Vector3(CHASE_OFFSET.x, CHASE_OFFSET.y, -CHASE_OFFSET.z) if rear_view else CHASE_OFFSET


## The ship's orientation, turned around when looking backward.
func _view_basis(ship_basis: Basis) -> Basis:
	return ship_basis.rotated(ship_basis.y, PI) if rear_view else ship_basis


## Hands the ship to EscapeRun: no input, collision or damage from here on.
func begin_cinematic() -> void:
	cinematic = true
	rear_view = false
	afterburning = false
	Sfx.stop_loop("afterburner_loop")
	cloak_left = 0.0
	_fade_ship(0.0)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	lock_target = null
	headlight.visible = true
	_apply_view_mode()


func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


func _process(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 2.2)
	_fade_flashes(delta)
	if cinematic:
		_thrust_level = 1.0
	else:
		_update_camera(delta)
	var thrust := _thrust_level * (0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.05))
	var show_ship := _ship_shown()
	for f in _flames:
		var length_scale := 0.25 + thrust * 1.15
		f.scale = Vector3(0.75 + thrust * 0.35, length_scale, 0.75 + thrust * 0.35)
		f.position.z = FLAME_LENGTH * 0.5 * length_scale
		f.visible = show_ship and not dead
	_glow_mat.emission_energy_multiplier = 4.0 + thrust * 14.0
	_engine_light.light_energy = 0.6 + thrust * 3.5 if show_ship or rear_view else 0.0
	_burn_fov = lerpf(_burn_fov, AFTERBURNER_FOV if afterburning else 0.0, 1.0 - exp(-6.0 * delta))
	if not cinematic:
		_update_fov()
	if not dead and shield < LOW_SHIELD and not cinematic and not Game.finished:
		_low_beep -= delta
		if _low_beep <= 0.0:
			_low_beep = LOW_SHIELD_BEEP
			Sfx.play("shield_low", null, -9.0)
	var speed_ratio := velocity.length() / (ACCEL / DRAG)
	Sfx.loop("engine", lerpf(-24.0, -13.0, _thrust_level), 0.8 + speed_ratio * 0.55)


func _update_fov() -> void:
	var offset := 0.0
	if _rear_from_cockpit():
		offset = view_tuning.rear_fov_offset
	elif view_mode != View.CHASE:
		offset = view_tuning.cockpit_fov_offset
	cam.fov = clampf(Settings.fov + _burn_fov + offset, 1.0, 179.0)


func _update_camera(delta: float) -> void:
	var extra := 0.0
	if Game.reactor_down and not Game.finished:
		extra = 0.07 + 0.18 * (1.0 - Game.escape_left / Game.ESCAPE_SECONDS)
	var amount := pow(_shake + extra, 1.5) * Settings.screen_shake
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * amount
	var xf := global_transform
	var chase := view_mode == View.CHASE
	if chase:
		_chase_camera(delta, xf)
	elif _rear_from_cockpit():
		_rear_eye_camera(xf)
	else:
		cam.global_transform = Transform3D(_view_basis(xf.basis), xf.origin + xf.basis * view_tuning.cockpit_eye)
		cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(view_tuning.cockpit_pitch))
		# The cabin lags slightly behind the camera, so thrust and turns are felt.
		var local_v := xf.basis.inverse() * velocity
		var want := Vector3(-local_v.x, -local_v.y, -local_v.z * 0.6) * view_tuning.sway_velocity + Vector3(_visual_tilt.y * -view_tuning.sway_tilt, _visual_tilt.x * view_tuning.sway_tilt, 0.0)
		_cabin_sway = _cabin_sway.lerp(want, 1.0 - exp(-view_tuning.sway_response * delta))
		cockpit.position = view_tuning.cabin_offset + _cabin_sway
	cam.global_position += cam.global_basis * jitter * (0.24 if chase else view_tuning.cockpit_shake)
	cam.rotate_object_local(Vector3.BACK, jitter.x * 0.03)


func _rear_eye_camera(xf: Transform3D) -> void:
	var at := xf.origin + xf.basis * view_tuning.rear_eye
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(xf.origin, at, Game.WORLD))
	if not hit.is_empty():
		at = hit.position + hit.normal * 0.4
	cam.global_transform = Transform3D(_view_basis(xf.basis), at)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(view_tuning.rear_yaw))
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(view_tuning.rear_pitch))


func _chase_camera(delta: float, xf: Transform3D) -> void:
	var want := xf.origin + xf.basis * _chase_offset()
	var from := xf.origin + xf.basis * Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, want, Game.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = hit.position + hit.normal * 0.8
	_chase_pos = _chase_pos.lerp(want, 1.0 - exp(-14.0 * delta))
	_chase_basis = _chase_basis.slerp(_view_basis(xf.basis), 1.0 - exp(-12.0 * delta)).orthonormalized()
	cam.global_transform = Transform3D(_chase_basis, _chase_pos)
