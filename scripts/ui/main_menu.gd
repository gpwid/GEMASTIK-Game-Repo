class_name MainMenu
extends Control

## Main Menu membaca progres dari SaveManager.
## Signal tombol tetap dihubungkan melalui tab Signals pada editor Godot.

const LEVEL_SELECTION_PATH: String = (
	"res://scenes/ui/level_selection.tscn"
)
const DISPLAYED_LEVEL_ID: String = "level_01"

@onready var continue_button: Button = %Continue
@onready var new_game_button: Button = %NewGameButton
@onready var right_switcher: TabContainer = %RightSwitcher

@onready var record_level_label: Label = %RecordLevelLabel
@onready var best_day_label: Label = %BestDayLabel
@onready var best_time_label: Label = %BestTimeLabel
@onready var best_logistics_label: Label = %BestLogisticsLabel


func _ready() -> void:
	_resume_normal_time()
	right_switcher.current_tab = 0
	_refresh_continue_button()
	_refresh_best_record()

	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()


## Mengaktifkan Continue hanya jika save menunjuk ke scene yang valid.
func _refresh_continue_button() -> void:
	var last_scene_path: String = SaveManager.get_last_level_scene()
	var has_valid_scene: bool = (
		SaveManager.has_any_progress()
		and not last_scene_path.is_empty()
		and ResourceLoader.exists(last_scene_path)
	)

	continue_button.disabled = not has_valid_scene

	if has_valid_scene:
		continue_button.tooltip_text = "Lanjutkan permainan terakhir"
	else:
		continue_button.tooltip_text = "Belum ada permainan tersimpan"


## Membaca personal best Level 1 dan memasukkannya ke label Main Menu.
func _refresh_best_record() -> void:
	var record: Dictionary = SaveManager.get_level_record(
		DISPLAYED_LEVEL_ID
	)
	var is_completed := bool(record.get("completed", false))

	record_level_label.text = "Level 1"

	if not is_completed:
		best_day_label.text = "Day: -"
		best_time_label.text = "Time: --:--:--"
		best_logistics_label.text = "Supplies Delivered: -"
		return

	var best_day := int(record.get("best_day", -1))
	var best_time := float(record.get("best_time_seconds", -1.0))
	var best_logistics := int(record.get("best_logistics", 0))

	best_day_label.text = "Day: %d" % best_day
	best_time_label.text = "Time: %s" % _format_time(best_time)
	best_logistics_label.text = (
		"Supplies Delivered: %d" % best_logistics
	)


## Mengubah detik menjadi format jam:menit:detik.
func _format_time(total_time_seconds: float) -> String:
	if total_time_seconds < 0.0:
		return "--:--:--"

	var total_seconds := floori(total_time_seconds)
	var hours := int(total_seconds / 3600)
	var minutes := int((total_seconds % 3600) / 60)
	var seconds := total_seconds % 60

	return "%02d:%02d:%02d" % [hours, minutes, seconds]


## Dipanggil signal pressed milik tombol Continue.
func _on_continue_pressed() -> void:
	var last_scene_path: String = SaveManager.get_last_level_scene()

	if (
		last_scene_path.is_empty()
		or not ResourceLoader.exists(last_scene_path)
	):
		push_warning(
			"MainMenu: scene Continue tidak valid: "
			+ last_scene_path
		)
		_refresh_continue_button()
		return

	_change_scene(last_scene_path)


## Dipanggil signal pressed milik tombol New Game.
func _on_new_game_button_pressed() -> void:
	if not ResourceLoader.exists(LEVEL_SELECTION_PATH):
		push_error(
			"MainMenu: Level Selection tidak ditemukan: "
			+ LEVEL_SELECTION_PATH
		)
		return

	_change_scene(LEVEL_SELECTION_PATH)


## Dipanggil signal pressed milik tombol Exit.
func _on_exit_button_pressed() -> void:
	get_tree().quit()


## Hover/focus tombol selain Credits mengembalikan panel rekor.
func show_best_record() -> void:
	right_switcher.current_tab = 0


## Hover/focus tombol Credits mengganti panel kanan dengan credits.
func show_credits() -> void:
	right_switcher.current_tab = 1


func _change_scene(scene_path: String) -> void:
	_resume_normal_time()
	get_tree().change_scene_to_file(scene_path)


func _resume_normal_time() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
