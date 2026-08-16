extends Node

signal save_updated(level_id: String)

const SAVE_PATH: String = "user://pasokan_save.cfg"
const GENERAL_SECTION: String = "general"

const KEY_LAST_LEVEL_ID: String = "last_level_id"
const KEY_LAST_LEVEL_SCENE: String = "last_level_scene"
const KEY_COMPLETED: String = "completed"
const KEY_BEST_TIME: String = "best_time_seconds"
const KEY_BEST_DAY: String = "best_day"
const KEY_BEST_LOGISTICS: String = "best_logistics"

var _config: ConfigFile = ConfigFile.new()
var _is_loaded: bool = false


func _ready() -> void:
	load_save()


func load_save() -> void:
	_config = ConfigFile.new()
	var load_error: Error = _config.load(SAVE_PATH)

	if load_error == OK:
		print("[SaveManager] Save berhasil dimuat")
	elif load_error == ERR_FILE_NOT_FOUND:
		## Normal pada permainan pertama. File dibuat saat progres disimpan.
		print("[SaveManager] Belum ada save; memulai data baru")
	else:
		push_warning(
			"SaveManager: save gagal dibaca. Error: "
			+ error_string(load_error)
		)
		_config = ConfigFile.new()

	_is_loaded = true


func mark_level_started(level_id: String, scene_path: String) -> void:
	## Menyimpan level terakhir agar tombol Continue mengetahui tujuannya.
	_ensure_loaded()

	var section := _get_level_section(level_id)
	if section.is_empty():
		push_error("SaveManager: level_id tidak boleh kosong")
		return

	_config.set_value(GENERAL_SECTION, KEY_LAST_LEVEL_ID, section)
	_config.set_value(
		GENERAL_SECTION,
		KEY_LAST_LEVEL_SCENE,
		scene_path
	)
	if _save_to_disk():
		save_updated.emit(section)


func record_level_completion(
	level_id: String,
	completion_time_seconds: float,
	completion_day: int,
	delivered_logistics: int
) -> void:
	## Setiap statistik dibandingkan dengan personal best sebelumnya.
	_ensure_loaded()

	var section := _get_level_section(level_id)
	if section.is_empty():
		push_error("SaveManager: level_id tidak boleh kosong")
		return

	var safe_time := maxf(completion_time_seconds, 0.0)
	var safe_day := maxi(completion_day, 1)
	var safe_logistics := maxi(delivered_logistics, 0)
	var was_completed := bool(
		_config.get_value(section, KEY_COMPLETED, false)
	)

	_config.set_value(section, KEY_COMPLETED, true)

	var previous_time := float(
		_config.get_value(section, KEY_BEST_TIME, -1.0)
	)
	if not was_completed or previous_time < 0.0 or safe_time < previous_time:
		_config.set_value(section, KEY_BEST_TIME, safe_time)

	var previous_day := int(
		_config.get_value(section, KEY_BEST_DAY, -1)
	)
	if not was_completed or previous_day < 0 or safe_day < previous_day:
		_config.set_value(section, KEY_BEST_DAY, safe_day)

	var previous_logistics := int(
		_config.get_value(section, KEY_BEST_LOGISTICS, 0)
	)
	if not was_completed or safe_logistics > previous_logistics:
		_config.set_value(
			section,
			KEY_BEST_LOGISTICS,
			safe_logistics
		)

	if not _save_to_disk():
		return

	save_updated.emit(section)

	print(
		"[SaveManager] Record diperbarui | Level: ", section,
		" | Waktu: ", get_best_time(section),
		" | Hari: ", get_best_day(section),
		" | Logistik: ", get_best_logistics(section)
	)


func has_any_progress() -> bool:
	_ensure_loaded()
	return not get_last_level_scene().is_empty()


func is_level_completed(level_id: String) -> bool:
	_ensure_loaded()
	var section := _get_level_section(level_id)
	return bool(_config.get_value(section, KEY_COMPLETED, false))


func get_best_time(level_id: String) -> float:
	_ensure_loaded()
	var section := _get_level_section(level_id)
	return float(_config.get_value(section, KEY_BEST_TIME, -1.0))


func get_best_day(level_id: String) -> int:
	_ensure_loaded()
	var section := _get_level_section(level_id)
	return int(_config.get_value(section, KEY_BEST_DAY, -1))


func get_best_logistics(level_id: String) -> int:
	_ensure_loaded()
	var section := _get_level_section(level_id)
	return int(_config.get_value(section, KEY_BEST_LOGISTICS, 0))


func get_level_record(level_id: String) -> Dictionary:
	## Bentuk Dictionary ini dapat langsung dibaca Main Menu/Level Selection.
	return {
		"completed": is_level_completed(level_id),
		"best_time_seconds": get_best_time(level_id),
		"best_day": get_best_day(level_id),
		"best_logistics": get_best_logistics(level_id),
	}


func get_last_level_id() -> String:
	_ensure_loaded()
	return String(
		_config.get_value(GENERAL_SECTION, KEY_LAST_LEVEL_ID, "")
	)


func get_last_level_scene() -> String:
	_ensure_loaded()
	return String(
		_config.get_value(
			GENERAL_SECTION,
			KEY_LAST_LEVEL_SCENE,
			""
		)
	)


func _get_level_section(level_id: String) -> String:
	return level_id.strip_edges()


func _ensure_loaded() -> void:
	if not _is_loaded:
		load_save()


func _save_to_disk() -> bool:
	var save_error: Error = _config.save(SAVE_PATH)
	if save_error != OK:
		push_error(
			"SaveManager: save gagal ditulis. Error: "
			+ error_string(save_error)
		)
		return false

	return true
