extends Node
## The soundtrack. Mine songs are three synced stems: calm always plays, the combat
## stem rises in a fight, and the intense stem joins when the fight gets heavy.

const DIR := "res://assets/music/"
const CROSSFADE := 1.4
const SILENT_DB := -60.0
const COMBAT_ATTACK := 0.9
const COMBAT_RELEASE := 0.22
## Keeps the drums going for a moment after the last shot.
const COMBAT_HOLD := 6.0
const PAUSED_DB := -7.0
const INTENSE_ATTACK := 0.6
const INTENSE_RELEASE := 0.15
## Engaged robots (alerted and in sight, this close) that make a fight "heavy".
const INTENSE_ROBOTS := 3
const THREAT_RANGE := 150.0
## A robot this big counts for two.
const BIG_RADIUS := 3.4
const LOW_SHIELD := 30.0

var current := ""
var combat_level := 0.0
var intense_level := 0.0
## How many robots are fighting the ship right now, weighted by size.
var threat := 0.0
var _threat_cd := 0.0
var _stems := 2
var _decks: Array[AudioStreamPlayer] = []
var _active := 0
var _sync: AudioStreamSynchronized
var _hold := 0.0
var _sting: AudioStreamPlayer
var _pause_db := 0.0
var _fades: Dictionary = {}
var _music_bus := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var deck := AudioStreamPlayer.new()
		deck.bus = &"Music"
		deck.volume_db = SILENT_DB
		add_child(deck)
		_decks.append(deck)
	_sting = AudioStreamPlayer.new()
	_sting.bus = &"Music"
	add_child(_sting)


func _load(track: String, looping: bool) -> AudioStreamOggVorbis:
	var s := (load(DIR + track + ".ogg") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	s.loop = looping
	return s


## A mine song: "calm" plays throughout, "combat" and "intense" sit on top waiting to be raised.
func play_song(song: String) -> void:
	if current == song:
		return
	var stems := AudioStreamSynchronized.new()
	_stems = 3 if ResourceLoader.exists(DIR + song + "_intense.ogg") else 2
	stems.stream_count = _stems
	stems.set_sync_stream(0, _load(song + "_calm", true))
	stems.set_sync_stream(1, _load(song + "_combat", true))
	stems.set_sync_stream_volume(0, 0.0)
	stems.set_sync_stream_volume(1, SILENT_DB)
	if _stems == 3:
		stems.set_sync_stream(2, _load(song + "_intense", true))
		stems.set_sync_stream_volume(2, SILENT_DB)
	combat_level = 0.0
	intense_level = 0.0
	_hold = 0.0
	_swap(song, stems)
	_sync = stems


## A single track, for the menu, the boss and the escape.
func play_track(track: String) -> void:
	if current == track:
		return
	_swap(track, _load(track, true))
	_sync = null


func stop(fade := CROSSFADE) -> void:
	current = ""
	_sync = null
	_fade_out(_decks[_active], fade)


## A one-off cue at the end of a run; the current music gets out of its way.
func sting(track: String) -> void:
	stop(0.6)
	_sting.stream = _load(track, false)
	_sting.play()


func _swap(track: String, stream: AudioStream) -> void:
	_fade_out(_decks[_active], CROSSFADE)
	_active = 1 - _active
	var deck := _decks[_active]
	_stop_tweens(deck)
	deck.stream = stream
	deck.volume_db = SILENT_DB
	deck.play()
	var t := create_tween()
	t.tween_property(deck, "volume_db", 0.0, CROSSFADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fades[deck] = t
	current = track
	_sting.stop()


func _fade_out(deck: AudioStreamPlayer, fade: float) -> void:
	if not deck.playing:
		return
	_stop_tweens(deck)
	var t := create_tween()
	t.tween_property(deck, "volume_db", SILENT_DB, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(deck.stop)
	_fades[deck] = t


func _stop_tweens(deck: AudioStreamPlayer) -> void:
	var running: Tween = _fades.get(deck)
	if running != null and running.is_valid():
		running.kill()


## Called by the level a few times a second while robots are engaging the player.
func report_combat() -> void:
	_hold = COMBAT_HOLD


func _process(delta: float) -> void:
	_hold = maxf(0.0, _hold - delta)
	var want := 1.0 if _hold > 0.0 else 0.0
	var rate := COMBAT_ATTACK if want > combat_level else COMBAT_RELEASE
	combat_level = move_toward(combat_level, want, rate * delta)
	_threat_cd -= delta
	if _threat_cd <= 0.0:
		_threat_cd = 0.4
		threat = _measure_threat()
	var heavy := 1.0 if _hold > 0.0 and _is_heavy() else 0.0
	intense_level = move_toward(intense_level, minf(heavy, combat_level), (INTENSE_ATTACK if heavy > intense_level else INTENSE_RELEASE) * delta)
	if _sync != null:
		# Equal-power curve: a linear dB ramp would jump in right at the end.
		_sync.set_sync_stream_volume(1, linear_to_db(maxf(sin(combat_level * PI * 0.5), 0.001)))
		if _stems == 3:
			_sync.set_sync_stream_volume(2, linear_to_db(maxf(sin(intense_level * PI * 0.5), 0.001)))
	var want_db := PAUSED_DB if get_tree().paused else 0.0
	_pause_db = move_toward(_pause_db, want_db, 18.0 * delta)
	if _music_bus < 0 or _music_bus >= AudioServer.bus_count or AudioServer.get_bus_name(_music_bus) != &"Music":
		_music_bus = AudioServer.get_bus_index(&"Music")
	if _music_bus >= 0:
		# Compared with the bus itself, so a write by Settings.apply is corrected too,
		# but nothing is written on the frames where the level is steady.
		var bus_db := Settings.bus_db("music_volume") + _pause_db
		if absf(AudioServer.get_bus_volume_db(_music_bus) - bus_db) > 0.01:
			AudioServer.set_bus_volume_db(_music_bus, bus_db)


func _is_heavy() -> bool:
	if threat >= INTENSE_ROBOTS:
		return true
	var p: Node3D = Game.player
	return threat >= 1.0 and p != null and float(p.get("shield")) < LOW_SHIELD


## Counts robots that are alerted and can see the ship. Read-only; a few times a second.
func _measure_threat() -> float:
	var p: Node3D = Game.player
	if p == null or Game.level == null or not is_inside_tree():
		return 0.0
	var total := 0.0
	for e in get_tree().get_nodes_in_group("enemy"):
		# Duck-typed, so the music never depends on the robot script compiling.
		if e.get("alerted") != true or e.get("has_los") != true:
			continue
		if e.global_position.distance_squared_to(p.global_position) > THREAT_RANGE * THREAT_RANGE:
			continue
		var cfg: Variant = e.get("cfg")
		total += 2.0 if cfg is Dictionary and float(cfg.get("radius", 1.0)) >= BIG_RADIUS else 1.0
	return total
