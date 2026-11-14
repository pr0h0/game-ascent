extends Node
## Run state, input map and the objective flow.

signal message(text: String, color: Color)
signal player_hurt(amount: float)
## Where a hit came from, so the HUD can show its direction.
signal player_hit(from: Vector3)
## The player's weapon connected with a robot.
signal enemy_hit(killed: bool)
signal player_died
signal run_ended(won: bool, detail: String)

const WORLD := 1
const PLAYER := 2
const ENEMY := 4
const ESCAPE_SECONDS := 60.0
const DEFAULT_MISSILES := 6
const LASER_PREFIX := "laser_"
const WEAPON_PREFIX := "weapon_"
const MAX_CATCH_UP := 2
const SECRET_SCORE := 500
const EXTRA_LIFE_EVERY := 30000
const MAX_LIVES := 9
const DEFAULT_DIFFICULTY := 1
## "ai" scales robot tactics: flanking, dodging, falling back, calling for help, searching.
const DIFFICULTIES := [
	{"name": "Recruit", "damage": 0.6, "hp": 0.8, "fire": 1.3, "react": 1.4, "score": 0.75, "lives": 5, "ai": 0.3},
	{"name": "Pilot", "damage": 1.0, "hp": 1.0, "fire": 1.0, "react": 1.0, "score": 1.0, "lives": 3, "ai": 0.65},
	{"name": "Veteran", "damage": 1.35, "hp": 1.25, "fire": 0.85, "react": 0.8, "score": 1.5, "lives": 3, "ai": 0.85},
	{"name": "Nightmare", "damage": 1.65, "hp": 1.5, "fire": 0.7, "react": 0.55, "score": 2.5, "lives": 2, "ai": 1.0},
]
const KEY_COLORS := {
	"blue": Color(0.25, 0.5, 1.0),
	"yellow": Color(1.0, 0.8, 0.15),
	"red": Color(1.0, 0.2, 0.12),
}

var level: Node3D
var player: CharacterBody3D
var score := 0:
	set(value):
		score = value
		_award_extra_lives()
var lives := 3
var kills := 0
var keys: Dictionary = {}
var astronauts_rescued := 0
var astronauts_total := 0
var secrets_found := 0
var secrets_total := 0
var reactor_down := false
var escape_left := -1.0
var finished := false
var cinematic := false
var run_time := 0.0
var won := false
var escape_bonus := 0
var level_index := 0
var difficulty := DEFAULT_DIFFICULTY
var deaths := 0
var robots_total := 0
var _life_mark := 0
## A script is flying the ship: the mouse stays free and the bot supplies the aim.
var autopilot := false
var levels: Array[Dictionary] = [
	{"name": "First Shift", "data": "res://assets/levels/first_shift.json", "model": "res://assets/models/first_shift.glb", "base_missiles": 6, "music": "shift", "ambience": "ambience"},
	{"name": "The Vein", "data": "res://assets/levels/the_vein.json", "model": "res://assets/models/the_vein.glb", "base_missiles": 6, "music": "shift", "ambience": "ambience"},
	{"name": "Black Shaft", "data": "res://assets/levels/black_shaft.json", "model": "res://assets/models/black_shaft.glb", "base_missiles": 8, "music": "shift", "ambience": "ambience_deep"},
	{"name": "Smelter Row", "data": "res://assets/levels/smelter_row.json", "model": "res://assets/models/smelter_row.glb", "base_missiles": 8, "music": "smelter", "ambience": "ambience"},
	{"name": "Hollow Reach", "data": "res://assets/levels/hollow_reach.json", "model": "res://assets/models/hollow_reach.glb", "base_missiles": 10, "music": "smelter", "ambience": "ambience_deep"},
	{"name": "Deep Cut", "data": "res://assets/levels/deep_cut.json", "model": "res://assets/models/deep_cut.glb", "base_missiles": 10, "music": "smelter", "ambience": "ambience_deep"},
	{"name": "The Overseer's Pit", "data": "res://assets/levels/overseer_pit.json", "model": "res://assets/models/overseer_pit.glb", "base_missiles": 12, "music": "smelter", "ambience": "ambience_deep"},
	{"name": "Glass Seam", "data": "res://assets/levels/glass_seam.json", "model": "res://assets/models/glass_seam.glb", "base_missiles": 12, "music": "glass", "ambience": "ambience_glass"},
	{"name": "Last Light", "data": "res://assets/levels/last_light.json", "model": "res://assets/models/last_light.glb", "base_missiles": 12, "music": "glass", "ambience": "ambience_glass"},
	{"name": "Core Zero", "data": "res://assets/levels/core_zero.json", "model": "res://assets/models/core_zero.glb", "base_missiles": 12, "music": "core", "ambience": "ambience_deep"},
]
var level_start: Dictionary = {}
var story_chapter := 0
## What follows the cutscene: "level" launches the level, "title" returns to the menu.
var after_story := "level"
var start_shield := 100.0
var start_energy := 100.0
var start_missiles := DEFAULT_MISSILES
## Installed cannon upgrades, e.g. "dual_fire". Part of every level-start snapshot.
var upgrades: Array = []
var start_ammo: Dictionary = {}


func _enter_tree() -> void:
	Controls.setup()
	_bind("menu_confirm", [KEY_ENTER, KEY_KP_ENTER])


func _bind(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _award_extra_lives() -> void:
	var earned := score / EXTRA_LIFE_EVERY
	if earned <= _life_mark:
		return
	var gained := earned - _life_mark
	_life_mark = earned
	if level != null and is_instance_valid(player) and not finished:
		# The cap stops the count growing; it never takes airframes away.
		lives = maxi(lives, mini(MAX_LIVES, lives + gained))
		say("EXTRA AIRFRAME", Color(0.6, 1.0, 0.7))
		Sfx.play("pickup_upgrade", null, -3.0, 1.2)


func diff(key: String) -> float:
	return float(DIFFICULTIES[difficulty][key])


func reset_run() -> void:
	level_index = 0
	score = 0
	lives = int(diff("lives"))
	_life_mark = 0
	kills = 0
	run_time = 0.0
	start_shield = Player.START_SHIELD
	start_energy = Player.START_ENERGY
	start_missiles = DEFAULT_MISSILES
	upgrades = []
	start_ammo = {}
	_reset_level_state()


func _reset_level_state() -> void:
	keys = {}
	deaths = 0
	robots_total = 0
	astronauts_rescued = 0
	astronauts_total = 0
	secrets_found = 0
	secrets_total = 0
	cinematic = false
	reactor_down = false
	escape_left = -1.0
	finished = false
	won = false


func current_level() -> Dictionary:
	return levels[level_index]


func level_title(index: int) -> String:
	return "Level %d: %s" % [index + 1, levels[index]["name"]]


func has_next_level() -> bool:
	return level_index + 1 < levels.size()


func _make_snapshot() -> Dictionary:
	return {
		"level_index": level_index, "score": score, "lives": lives, "kills": kills, "run_time": run_time,
		"difficulty": difficulty, "shield": start_shield, "energy": start_energy, "missiles": start_missiles, "upgrades": upgrades.duplicate(), "ammo": start_ammo.duplicate(),
	}


func _apply_snapshot(s: Dictionary) -> void:
	level_index = int(s["level_index"])
	difficulty = clampi(int(s.get("difficulty", DEFAULT_DIFFICULTY)), 0, DIFFICULTIES.size() - 1)
	score = int(s["score"])
	_life_mark = int(s["score"]) / EXTRA_LIFE_EVERY
	lives = int(s["lives"])
	kills = int(s["kills"])
	run_time = float(s["run_time"])
	start_shield = float(s["shield"])
	start_energy = float(s["energy"])
	start_missiles = int(s["missiles"])
	start_ammo = s.get("ammo", {}).duplicate()
	upgrades = Array(s.get("upgrades", [])).map(func(u): return "laser_2" if u == "overcharge" else u)
	_reset_level_state()


## New game: snapshot the start of level one, then fly it.
func new_game() -> void:
	start_level(0, true)


## A fresh start on any unlocked level: full stats, that level's base ammo, a new save.
func start_level(index: int, with_story := false) -> void:
	reset_run()
	level_index = index
	start_missiles = levels[index]["base_missiles"]
	start_ammo = base_ammo(index)
	level_start = _make_snapshot()
	Saves.write(level_start)
	if with_story and Settings.show_story:
		play_story(index, "level")
	else:
		_launch()


func continue_game() -> void:
	var latest: Dictionary = Saves.latest()
	if not latest.is_empty():
		load_snapshot(latest)


## Loading never writes a save, so replays don't multiply the list.
func load_snapshot(s: Dictionary) -> void:
	level_start = s
	_apply_snapshot(s)
	_launch()


func restart_level() -> void:
	_apply_snapshot(level_start)
	_launch()


## Moves to the next level, carrying the ship's state, and writes that level's snapshot.
func prepare_next_level() -> void:
	start_shield = maxf(player.shield, Player.START_SHIELD)
	start_energy = maxf(player.energy, Player.START_ENERGY)
	level_index += 1
	start_missiles = maxi(player.missiles, int(levels[level_index]["base_missiles"]))
	start_ammo = base_ammo(level_index)
	for kind: String in player.ammo:
		if kind != "homing":
			start_ammo[kind] = maxi(int(start_ammo.get(kind, 0)), int(player.ammo[kind]))
	_reset_level_state()
	level_start = _make_snapshot()
	Saves.write(level_start)


func next_level() -> void:
	prepare_next_level()
	if Settings.show_story:
		play_story(level_index, "level")
	else:
		_launch()


func play_story(chapter: int, then: String) -> void:
	story_chapter = chapter
	after_story = then
	Sfx.stop_all_loops()
	level = null
	player = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/cutscene.tscn")


func play_ending() -> void:
	Progress.mark_finished()
	play_story(StoryData.ENDING, "title")


func story_finished() -> void:
	match after_story:
		"level":
			_launch()
		"title":
			to_title()


func _launch() -> void:
	Sfx.stop_all_loops()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func to_title() -> void:
	Sfx.stop_all_loops()
	level = null
	player = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/title.tscn")


func _process(delta: float) -> void:
	if level == null or finished:
		return
	run_time += delta
	if reactor_down and escape_left >= 0.0 and not cinematic:
		escape_left -= delta
		if escape_left <= 0.0:
			escape_left = 0.0
			end_run(false, "The mine went up with you inside it.")


func say(text: String, color := Color(0.75, 0.95, 1.0)) -> void:
	message.emit(text, color)


func has_key(color: String) -> bool:
	return keys.has(color)


func collect_key(color: String) -> void:
	keys[color] = true
	say("%s KEY ACQUIRED" % color.to_upper(), KEY_COLORS[color])
	checkpoint()


func on_reactor_destroyed() -> void:
	reactor_down = true
	escape_left = ESCAPE_SECONDS
	score += int(5000 * diff("score"))
	say("CORE BREACH — MINE COLLAPSE IMMINENT", Color(1.0, 0.3, 0.2))
	checkpoint()


## The shared core-failure sequence for a reactor or a boss dying at `at`:
## the blast and its after-shocks, then the countdown, the alarm and the escape music.
func trigger_core_failure(at: Vector3) -> void:
	Fx.explosion(at, 24.0, true)
	for i in 6:
		var spot := at + Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
		get_tree().create_timer(0.25 + i * 0.28).timeout.connect(Fx.explosion.bind(spot, randf_range(7.0, 14.0), true))
	on_reactor_destroyed()
	if level != null:
		level.start_alarm()
	Sfx.loop("alarm", -20.0)
	Music.play_track("escape")


## Big mines would be miserable to restart: a fresh airframe launches from here on.
func checkpoint() -> void:
	if player != null and not player.dead:
		player.set_checkpoint()


func has_upgrade(upgrade: String) -> bool:
	if upgrade.begins_with(LASER_PREFIX):
		return laser_level() >= int(upgrade.trim_prefix(LASER_PREFIX))
	return upgrades.has(upgrade)


## 1 (green) to 4 (magenta), from the highest laser upgrade held.
func laser_level() -> int:
	var best := 1
	for upgrade: String in upgrades:
		if upgrade.begins_with(LASER_PREFIX):
			best = maxi(best, int(upgrade.trim_prefix(LASER_PREFIX)))
	return best


## A duplicate is never wasted: it tops up energy instead.
func collect_upgrade(upgrade: String, message: String, color: Color) -> void:
	if has_upgrade(upgrade):
		player.energy = minf(Player.MAX_ENERGY, player.energy + Pickup.ENERGY_BOOST)
		say("ENERGY +%d" % int(Pickup.ENERGY_BOOST), Pickup.INFO["energy"]["color"])
		return
	upgrades.append(upgrade)
	say(message, color)
	if upgrade.begins_with(WEAPON_PREFIX):
		player.select_primary(upgrade.trim_prefix(WEAPON_PREFIX))


## Starting stock of missile types introduced before this level.
func base_ammo(index: int) -> Dictionary:
	var out: Dictionary = {}
	for i in index:
		for item in GalleryData.level_data(i)["pickups"]:
			var kind: String = item["type"]
			if kind.begins_with("ammo_"):
				var m := kind.trim_prefix("ammo_")
				out[m] = maxi(int(out.get(m, 0)), int(Weapons.SECONDARY[m]["gain"]))
	return out


## A reminder of what the last two levels offered, not the whole history.
func earlier_upgrades(index: int) -> Array:
	var out: Array = []
	for i in range(index - 1, maxi(index - 3, -1), -1):
		for item in GalleryData.level_data(i)["pickups"]:
			var kind: String = item["type"]
			if kind.begins_with("upgrade_") and not out.has(kind) and out.size() < MAX_CATCH_UP:
				out.append(kind)
	return out


func on_secret_found() -> void:
	secrets_found += 1
	score += SECRET_SCORE
	say("SECRET AREA FOUND  +%d" % SECRET_SCORE, Color(0.7, 0.5, 1.0))


func rescue_astronaut() -> void:
	astronauts_rescued += 1
	score += Astronaut.SCORE
	say("ASTRONAUT RESCUED  +%d" % Astronaut.SCORE, Color(0.55, 1.0, 0.7))


func add_kill(points: int) -> void:
	kills += 1
	score += int(points * diff("score"))


func end_run(won: bool, detail: String) -> void:
	if finished:
		return
	if won:
		# Before finished is set: the score setter only grants an extra life
		# crossed by the bonus while the run is still going.
		escape_bonus = int(escape_left) * 100
		score += escape_bonus
	finished = true
	self.won = won
	if won:
		Progress.unlock(level_index + 1)
		Progress.record_result(level_index, difficulty, score_this_level(), level_rank())
	run_ended.emit(won, detail)


func score_this_level() -> int:
	return score - int(level_start.get("score", 0))


## Thoroughness, not speed: clear the robots, find the secrets, stay alive.
func level_rank() -> String:
	var points := 30.0 * clampf(float(kills - int(level_start.get("kills", 0))) / maxf(float(robots_total), 1.0), 0.0, 1.0)
	points += 25.0 * (float(secrets_found) / float(secrets_total) if secrets_total > 0 else 1.0)
	points += 15.0 * (float(astronauts_rescued) / float(astronauts_total) if astronauts_total > 0 else 1.0)
	points += 30.0 * clampf(1.0 - float(deaths) * 0.4, 0.0, 1.0)
	for rank: Array in [[92.0, "S"], [75.0, "A"], [55.0, "B"], [35.0, "C"]]:
		if points >= rank[0]:
			return rank[1]
	return "D"
