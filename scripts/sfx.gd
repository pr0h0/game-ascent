extends Node
## Plays one-shot sounds at a position and owns the looping beds.

const DIR := "res://assets/audio/"
## A busy firefight mustn't stack dozens of copies of one sample.
const MAX_VOICES := 8
const MIN_GAP_MS := 28
const MAX_HEARD_DISTANCE := 260.0
## Sounds in this list keep working while the game is paused, and skip the cave reverb.
const INTERFACE_PREFIX := "ui_"
## Every robot class has an engine voice. Only the nearest few actually play.
const HUM_SOUNDS := {
	"tick": "hum_buzz", "hornet": "hum_buzz", "cinder": "hum_buzz",
	"ripper": "hum_rotor", "wraith": "hum_rotor", "drillback": "hum_rotor",
	"lancer": "hum_turbine", "longshot": "hum_turbine", "glint": "hum_turbine", "warden": "hum_turbine",
	"sower": "hum_turbine", "phase": "hum_turbine", "shade": "hum_turbine", "revenant": "hum_turbine",
	"spark": "hum_arc",
	"bulwark": "hum_heavy", "hive": "hum_heavy", "siege": "hum_heavy",
	"gravitar": "hum_grav",
	"overseer": "hum_boss", "crucible": "hum_boss", "zero": "hum_boss",
}
## Each class's engine sits at its own pitch, so two of a sound still tell apart.
const HUM_PITCH := {"tick": 1.15, "hornet": 0.92, "cinder": 1.3, "ripper": 1.1, "wraith": 0.85, "drillback": 0.7,
	"lancer": 0.9, "longshot": 0.78, "glint": 1.18, "warden": 0.84, "sower": 1.0, "phase": 1.08, "shade": 1.25, "revenant": 0.72,
	"bulwark": 1.0, "hive": 0.82, "siege": 0.9, "overseer": 1.0, "crucible": 0.85, "zero": 0.75}
const HUM_VOICES := 6
const HUM_RANGE := 90.0
const HUM_IDLE_DB := -17.0
const HUM_ALERT_DB := -8.0
## Robot guns that fire ordinary bolts each get their own report.
const ROBOT_SHOTS := {
	"tick": "shot_tick", "hornet": "shot_hornet", "lancer": "shot_lancer", "bulwark": "shot_bulwark",
	"siege": "shot_siege", "warden": "shot_plasma", "sower": "shot_plasma", "phase": "shot_phase",
	"shade": "shot_phase", "revenant": "shot_revenant", "hive": "shot_hive",
	"overseer": "shot_boss", "crucible": "shot_boss", "zero": "shot_boss",
}
## The cave reverb follows how much open space surrounds the ship.
const ROOM_CHECK := 0.25
const ROOM_RADIUS := 3
const DRY_WET := 0.04
const CAVERN_WET := 0.34

var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _voices: Dictionary = {}
var _last_played: Dictionary = {}
var played_total := 0
## Set briefly while effects are drawn just to get them loaded.
var silent := false
## 0 in a narrow tunnel, 1 in the middle of a big cavern.
var room_openness := 0.0
var _room_target := 0.0
var _room_cd := 0.0
var _room_offsets: Array[Vector3i] = []
var _reverb: AudioEffectReverb
var _looped_streams: Dictionary = {}
## Each entry: [robot, player, base pitch]. Players live on the robot and die with it.
var _hums: Array = []
var _hum_cd := 0.0


func _ready() -> void:
	for x in range(-ROOM_RADIUS, ROOM_RADIUS + 1):
		for y in range(-ROOM_RADIUS, ROOM_RADIUS + 1):
			for z in range(-ROOM_RADIUS, ROOM_RADIUS + 1):
				if x * x + y * y + z * z <= ROOM_RADIUS * ROOM_RADIUS + 1:
					_room_offsets.append(Vector3i(x, y, z))


func _process(delta: float) -> void:
	_update_room(delta)
	_update_hums(delta)


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = load(DIR + sound + ".wav")
	return _streams[sound]


func _allowed(sound: String) -> bool:
	if silent:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < MIN_GAP_MS or int(_voices.get(sound, 0)) >= MAX_VOICES:
		return false
	_last_played[sound] = now
	_voices[sound] = int(_voices.get(sound, 0)) + 1
	return true


## Runs on tree_exiting, so a player freed mid-sound (a level change, a cutscene
## set being cleared) gives its voice back as well as one that finished.
func _release(sound: String) -> void:
	_voices[sound] = maxi(0, int(_voices.get(sound, 0)) - 1)


func play(sound: String, at = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if at is Vector3 and Game.level != null:
		if Game.player != null and Game.player.global_position.distance_squared_to(at) > MAX_HEARD_DISTANCE * MAX_HEARD_DISTANCE:
			return
		if not _allowed(sound):
			return
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = _stream(sound)
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.unit_size = 22.0
		p3.max_distance = MAX_HEARD_DISTANCE
		p3.bus = &"Effects"
		Game.level.add_child(p3)
		p3.global_position = at
		p3.tree_exiting.connect(_release.bind(sound))
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		if not _allowed(sound):
			return
		var p2 := AudioStreamPlayer.new()
		p2.stream = _stream(sound)
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		p2.process_mode = Node.PROCESS_MODE_ALWAYS
		p2.bus = &"Interface" if sound.begins_with(INTERFACE_PREFIX) else &"Effects"
		add_child(p2)
		p2.tree_exiting.connect(_release.bind(sound))
		p2.finished.connect(p2.queue_free)
		p2.play()
	played_total += 1


func _looped(sound: String) -> AudioStreamWAV:
	if _looped_streams.has(sound):
		return _looped_streams[sound]
	var s := (load(DIR + sound + ".wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	_looped_streams[sound] = s
	return s


## The bolt report for a robot class, or the generic one it would otherwise use.
func robot_shot(kind: String, fallback: String) -> String:
	return ROBOT_SHOTS.get(kind, fallback)


## Gives a robot its engine sound. It stays silent until it is one of the nearest few.
func robot_hum(robot: Node3D, kind: String) -> void:
	if not HUM_SOUNDS.has(kind):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _looped(HUM_SOUNDS[kind])
	p.unit_size = 9.0
	p.max_distance = HUM_RANGE
	p.volume_db = HUM_IDLE_DB
	p.bus = &"Effects"
	p.attenuation_filter_cutoff_hz = 6000.0
	robot.add_child(p)
	_hums.append([robot, p, float(HUM_PITCH.get(kind, 1.0)) * randf_range(0.96, 1.04)])


## Picks the closest robots a few times a second; between picks only their pitch
## and loudness move, following speed and whether they have noticed the ship.
func _update_hums(delta: float) -> void:
	if _hums.is_empty():
		return
	_hum_cd -= delta
	var listener: Variant = Game.player
	if not is_instance_valid(listener):
		listener = null
	if _hum_cd <= 0.0:
		_hum_cd = 0.2
		_hums = _hums.filter(func(h): return is_instance_valid(h[0]) and is_instance_valid(h[1]))
		var near: Array = []
		if listener != null and listener.is_inside_tree() and not get_tree().paused:
			for h in _hums:
				if not h[0].is_inside_tree():
					continue
				var d: float = listener.global_position.distance_squared_to(h[0].global_position)
				if d < HUM_RANGE * HUM_RANGE:
					near.append([d, h])
			near.sort_custom(func(a, b): return a[0] < b[0])
		var keep: Dictionary = {}
		for i in mini(near.size(), HUM_VOICES):
			keep[near[i][1][1]] = true
		for h in _hums:
			var p: AudioStreamPlayer3D = h[1]
			if not p.is_inside_tree():
				continue
			if keep.has(p) and not p.playing:
				p.play(randf() * 1.9)
			elif not keep.has(p) and p.playing:
				p.stop()
	for h in _hums:
		if not is_instance_valid(h[1]) or not is_instance_valid(h[0]) or not h[1].playing:
			continue
		var p: AudioStreamPlayer3D = h[1]
		var robot: Node3D = h[0]
		var alerted: bool = robot.get("alerted") == true
		var speed: float = robot.velocity.length() if robot is CharacterBody3D else 0.0
		p.volume_db = move_toward(p.volume_db, HUM_ALERT_DB if alerted else HUM_IDLE_DB, 20.0 * delta)
		p.pitch_scale = lerpf(p.pitch_scale, float(h[2]) * (1.0 + clampf(speed / 40.0, 0.0, 0.3)), 1.0 - exp(-4.0 * delta))


## Measures how much of the space around the ship is open mine, and lets the
## Effects reverb grow from a dry tunnel into a long cavern echo.
func _update_room(delta: float) -> void:
	if _reverb == null:
		var bus := AudioServer.get_bus_index(&"Effects")
		for i in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus, i) is AudioEffectReverb:
				_reverb = AudioServer.get_bus_effect(bus, i)
		if _reverb == null:
			return
	_room_cd -= delta
	if _room_cd <= 0.0:
		_room_cd = ROOM_CHECK
		_room_target = _measure_room()
	room_openness = move_toward(room_openness, _room_target, delta * 0.7)
	var big := smoothstep(0.3, 0.95, room_openness)
	_reverb.wet = lerpf(DRY_WET, CAVERN_WET, big) * Settings.cave_reverb
	_reverb.room_size = lerpf(0.35, 0.9, big)
	_reverb.damping = lerpf(0.7, 0.42, big)
	_reverb.predelay_msec = lerpf(18.0, 75.0, big)


func _measure_room() -> float:
	var level: Variant = Game.level
	var listener: Variant = Game.player
	if not is_instance_valid(level) or not is_instance_valid(listener) or not listener.is_inside_tree() or not (level.get("cell_ids") is Dictionary):
		return 0.3
	var cells: Dictionary = level.get("cell_ids")
	var size: float = level.get("cell_size")
	var here := Vector3i((listener.global_position / size).round())
	if not cells.has(here) and not cells.has(here + Vector3i.UP) and not cells.has(here + Vector3i.DOWN):
		# Outside the mine altogether (the finale's open space): nothing to echo off.
		return 0.0
	var open := 0
	for o: Vector3i in _room_offsets:
		if cells.has(here + o):
			open += 1
	return float(open) / _room_offsets.size()


## Non-positional loop; calling again just adjusts volume and pitch.
func loop(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _loops.has(sound):
		var p := AudioStreamPlayer.new()
		p.stream = _looped(sound)
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = &"Ambience" if sound.begins_with("ambience") else &"Effects"
		add_child(p)
		p.play()
		_loops[sound] = p
	_loops[sound].volume_db = volume_db
	_loops[sound].pitch_scale = pitch


func stop_loop(sound: String) -> void:
	if _loops.has(sound):
		_loops[sound].queue_free()
		_loops.erase(sound)


func stop_all_loops() -> void:
	for sound in _loops.keys():
		stop_loop(sound)


func positional_loop(sound: String, parent: Node3D, unit_size: float, volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _looped(sound)
	p.unit_size = unit_size
	p.volume_db = volume_db
	p.max_distance = 300.0
	p.bus = &"Effects"
	parent.add_child(p)
	p.play()
	return p
