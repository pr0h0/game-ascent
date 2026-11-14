extends Node
## Which levels the player has unlocked. Level one is always open; finishing a
## level opens the next. Saves from before this existed still count as progress.

const SECTION := "progress"

var path := "user://progress.cfg"
## The file's text is read each time but only parsed when it differs from the
## last read, so menus asking for 40 best scores don't parse it 40 times.
## A file that fails to parse is never overwritten.
var _cfg: ConfigFile
var _cfg_key := ""
var _corrupt := false


func _key() -> String:
	return path + "\n" + (FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "")


func _load() -> ConfigFile:
	var key := _key()
	if _cfg != null and key == _cfg_key:
		return _cfg
	_cfg = ConfigFile.new()
	_cfg_key = key
	_corrupt = false
	if FileAccess.file_exists(path):
		var err := _cfg.parse(key.substr(path.length() + 1))
		if err != OK:
			push_error("Progress file %s could not be read (error %d); it will not be overwritten." % [path, err])
			_corrupt = true
	return _cfg


func _save(cfg: ConfigFile) -> void:
	if _corrupt:
		return
	cfg.save(path)
	_cfg_key = _key()


func unlocked_level() -> int:
	if Settings.unlock_all:
		return Game.levels.size() - 1
	var cfg := _load()
	var stored: int = cfg.get_value(SECTION, "unlocked_level", 0)
	var from_saves := 0
	for save in Saves.list():
		from_saves = maxi(from_saves, int(save["level_index"]))
	if from_saves > stored:
		unlock(from_saves)
	return clampi(maxi(stored, from_saves), 0, Game.levels.size() - 1)


func unlock(index: int) -> void:
	var cfg := _load()
	var best := maxi(cfg.get_value(SECTION, "unlocked_level", 0), index)
	cfg.set_value(SECTION, "unlocked_level", clampi(best, 0, Game.levels.size() - 1))
	_save(cfg)


## Keeps the best score and rank for each level, per difficulty.
func record_result(level: int, difficulty: int, score: int, rank: String) -> void:
	var cfg := _load()
	var section := "best_%d_%d" % [level, difficulty]
	if score > int(cfg.get_value(section, "score", -1)):
		cfg.set_value(section, "score", score)
		cfg.set_value(section, "rank", rank)
		_save(cfg)


func best(level: int, difficulty: int) -> Dictionary:
	var cfg := _load()
	var section := "best_%d_%d" % [level, difficulty]
	if not cfg.has_section(section):
		return {}
	return {"score": cfg.get_value(section, "score", 0), "rank": cfg.get_value(section, "rank", "D")}


func mark_finished() -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "finished_game", true)
	_save(cfg)


func finished_game() -> bool:
	var cfg := _load()
	return cfg.get_value(SECTION, "finished_game", false) or Settings.unlock_all


func is_unlocked(index: int) -> bool:
	return index <= unlocked_level()
