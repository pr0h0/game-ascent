class_name Pickup
extends Node3D
## Bobbing, spinning collectible; collected by proximity.

const SHIELD_BOOST := 30.0
const ENERGY_BOOST := 40.0
## The plain "ammo" pickup refills homing missiles, so it shares their numbers.
const AMMO_BOOST: int = Weapons.SECONDARY["homing"]["gain"]
const MAX_MISSILES: int = Weapons.SECONDARY["homing"]["cap"]

const INFO := {
	"shield": {"model": "pickup_shield", "color": Color(0.2, 0.9, 1.0), "text": "SHIELD"},
	"energy": {"model": "pickup_energy", "color": Color(1.0, 0.7, 0.2), "text": "ENERGY"},
	"ammo": {"model": "pickup_ammo", "color": Color(1.0, 0.25, 0.15), "text": "MISSILES"},
	"upgrade_dual_fire": {"model": "pickup_upgrade_dual", "color": Color(0.3, 0.9, 1.0), "text": "CANNON SYNC INSTALLED"},
	"upgrade_laser_2": {"model": "pickup_upgrade_overcharge", "color": Color(1.0, 0.85, 0.2), "text": "LASER LEVEL 2"},
	"upgrade_laser_3": {"model": "pickup_upgrade_overcharge", "color": Color(1.0, 0.22, 0.15), "text": "LASER LEVEL 3"},
	"upgrade_laser_4": {"model": "pickup_upgrade_overcharge", "color": Color(1.0, 0.25, 0.9), "text": "LASER LEVEL 4"},
	"upgrade_weapon_cutter": {"model": "weapon_plasma_cutter", "color": Weapons.SLASH_COLOR, "text": "PLASMA CUTTER [2]"},
	"upgrade_weapon_arc": {"model": "weapon_arc_caster", "color": Weapons.ARC_COLOR, "text": "ARC CASTER [3]"},
	"upgrade_weapon_rail": {"model": "weapon_rail_lance", "color": Weapons.RAIL_COLOR, "text": "RAIL LANCE [4]"},
	"upgrade_weapon_prism": {"model": "weapon_prism_repeater", "color": Weapons.PRISM_COLOR, "text": "PRISM REPEATER [5]"},
	"upgrade_weapon_singularity": {"model": "weapon_singularity_launcher", "color": Singularity.COLOR, "text": "SINGULARITY [6]"},
	"ammo_cluster": {"model": "missile_cluster", "color": Color(1.0, 0.6, 0.2), "text": "CLUSTER MISSILES"},
	"ammo_swarm": {"model": "missile_swarm", "color": Color(0.4, 1.0, 0.5), "text": "SEEKER SWARM"},
	"ammo_bunker": {"model": "missile_bunker", "color": Color(1.0, 0.4, 0.2), "text": "BUNKER BUSTER"},
	"ammo_emp": {"model": "missile_emp", "color": Weapons.ARC_COLOR, "text": "EMP TORPEDO"},
	"ammo_mine": {"model": "missile_mine", "color": Color(1.0, 0.25, 0.2), "text": "PROXIMITY MINES"},
	"power_invincible": {"model": "power_invincible", "color": Color(1.0, 0.75, 0.2), "text": "INVINCIBILITY"},
	"power_cloak": {"model": "power_cloak", "color": Color(0.7, 0.4, 1.0), "text": "INVISIBILITY"},
	"key_blue": {"model": "pickup_key", "color": Color(0.25, 0.5, 1.0), "text": ""},
	"key_yellow": {"model": "pickup_key", "color": Color(1.0, 0.8, 0.15), "text": ""},
	"key_red": {"model": "pickup_key", "color": Color(1.0, 0.2, 0.12), "text": ""},
}

var kind := "shield"
var _model: Node3D
var _time := 0.0


func _ready() -> void:
	add_to_group("pickup")
	_time = randf() * TAU
	_model = load("res://assets/models/%s.glb" % INFO[kind]["model"]).instantiate()
	Mats.apply(_model)
	add_child(_model)
	var is_key := kind.begins_with("key_")
	_model.scale = Vector3.ONE * (2.4 if is_key else (1.9 if kind.begins_with("upgrade_") else 1.5))
	if is_key:
		var glow := Mats.unique_glow(_model, "glow_blue")
		glow.emission = INFO[kind]["color"]
		glow.emission_energy_multiplier = 2.6
	elif kind.begins_with("upgrade_laser"):
		var coil := Mats.unique_glow(_model, "glow_violet")
		coil.emission = INFO[kind]["color"]
		coil.emission_energy_multiplier = 3.0
	var l := OmniLight3D.new()
	l.light_color = INFO[kind]["color"]
	l.light_energy = 5.0 if is_key else 2.2
	l.omni_range = 22.0 if is_key else 11.0
	add_child(l)


func _process(delta: float) -> void:
	_time += delta
	_model.rotate_y(delta * 1.3)
	_model.position.y = sin(_time * 1.8) * 0.3
	var p := Game.player
	if p != null and not p.dead and p.global_position.distance_to(global_position) < 5.0:
		_collect(p)


func _collect(p: Player) -> void:
	if kind.begins_with("key_"):
		Game.collect_key(kind.trim_prefix("key_"))
		Sfx.play("key", null, -2.0)
		queue_free()
		return
	if kind.begins_with("upgrade_"):
		Game.collect_upgrade(kind.trim_prefix("upgrade_"), INFO[kind]["text"], INFO[kind]["color"])
		Sfx.play("pickup_upgrade", null, -2.0)
		queue_free()
		return
	if kind.begins_with("power_"):
		p.activate_power(kind)
		Game.say(INFO[kind]["text"], INFO[kind]["color"])
		Sfx.play("pickup_power", null, -2.0)
		queue_free()
		return
	if kind.begins_with("ammo_"):
		var missile := kind.trim_prefix("ammo_")
		var w: Dictionary = Weapons.SECONDARY[missile]
		var have := int(p.ammo.get(missile, 0))
		# Full: leave it for later, as shield and energy do.
		if have >= int(w["cap"]):
			return
		p.ammo[missile] = mini(int(w["cap"]), have + int(w["gain"]))
		p.select_secondary(missile)
		Game.say("%s +%d" % [INFO[kind]["text"], int(p.ammo[missile]) - have], INFO[kind]["color"])
		Sfx.play("pickup_ammo", null, -3.0)
		queue_free()
		return
	var gain := 0
	match kind:
		"shield":
			if p.shield >= Player.MAX_SHIELD:
				return
			p.shield = minf(Player.MAX_SHIELD, p.shield + SHIELD_BOOST)
			gain = int(SHIELD_BOOST)
		"energy":
			if p.energy >= Player.MAX_ENERGY:
				return
			p.energy = minf(Player.MAX_ENERGY, p.energy + ENERGY_BOOST)
			gain = int(ENERGY_BOOST)
		"ammo":
			if p.missiles >= MAX_MISSILES:
				return
			gain = mini(MAX_MISSILES, p.missiles + AMMO_BOOST) - p.missiles
			p.missiles += gain
	Game.say("%s +%d" % [INFO[kind]["text"], gain], INFO[kind]["color"])
	Sfx.play({"shield": "pickup_shield", "energy": "pickup_energy"}.get(kind, "pickup_ammo"), null, -4.0)
	queue_free()
