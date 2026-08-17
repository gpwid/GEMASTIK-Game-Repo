## Kelas global sebagai basis dan pengendali dari semua aturan level di game
class_name BaseLevel
extends Node2D

#bismillah semoga masih ingat semua isi ini

## Ekspor kategori untuk level designer
@export_category("Level Identity")
@export var level_id: String = "level_01"

@export_category("Level References")
@export var route_network_manager: RouteNetworkManager
@export var game_hud: GameHUD
@export var sustain_timer: Timer
@export var game_over_screen: Control
@export var failed_village_label: Label
@export var victory_screen: Control

@export_category("Navigation")
@export_file("*.tscn") var level_selection_scene_path: String = (
	"res://scenes/ui/level_selection.tscn"
)

@export_category("Optional Tutorial")
@export var tutorial_overlay: Control
@export var start_tutorial_on_ready: bool = false

# State penting dalam permainan
var is_game_over: bool = false
var is_victory: bool = false
var total_logistics_delivered: int = 0
var villages: Array[Area2D] = []

# Onready untuk referensi ke label-label Ui agar bisa di modifikasi in-code
@onready var victory_day_label: Label = %VictoryDayLabel
@onready var victory_time_label: Label = %VictoryTimeLabel
@onready var victory_logistics_label: Label = %VictoryLogisticsLabel
@onready var victory_route_label: Label = %VictoryRouteLabel

func _ready() -> void:
	if not _validate_scene_references():
		set_process(false)
		return

	AudioManager.play_random_ambience()

	_register_level_visit()
	_register_villages()
	_register_level_systems()
	
	game_hud.set_route_count(
		route_network_manager.expedition_routes.size()
	)
	game_hud.set_can_undo(
		not route_network_manager.created_segments.is_empty()
	)
	game_hud.set_logistics_count(total_logistics_delivered)

	if start_tutorial_on_ready and tutorial_overlay != null:
		call_deferred("_start_optional_tutorial")
		
	game_over_screen.visible = false
	victory_screen.visible = false


func _process(_delta: float) -> void:
	update_sustain_timer()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		game_hud.hide_vehicle_info()
	elif event.is_action_pressed("ui_cancel"):
		game_hud.hide_vehicle_info()
		route_network_manager.cancel_route_drawing()


func _validate_scene_references() -> bool:
	var is_valid := true

	if level_id.strip_edges().is_empty():
		push_error("BaseLevel: Level ID tidak boleh kosong")
		is_valid = false
	if route_network_manager == null:
		push_error("BaseLevel: Route Network Manager belum diisi")
		is_valid = false
	if game_hud == null:
		push_error("BaseLevel: Game HUD belum diisi")
		is_valid = false
	if sustain_timer == null:
		push_error("BaseLevel: Sustain Timer belum diisi")
		is_valid = false
	if game_over_screen == null:
		push_error("BaseLevel: Game Over Screen belum diisi")
		is_valid = false
	if failed_village_label == null:
		push_error("BaseLevel: Failed Village Label belum diisi")
		is_valid = false
	if victory_screen == null:
		push_error("BaseLevel: Victory Screen belum diisi")
		is_valid = false

	return is_valid


## Menyimpan level terakhir yang dimainkan agar tombol Continue mengetahui
## scene mana yang harus dibuka kembali.
func _register_level_visit() -> void:
	var current_scene := get_tree().current_scene
	var current_scene_path := ""

	if current_scene != null:
		current_scene_path = current_scene.scene_file_path

	SaveManager.mark_level_started(level_id, current_scene_path)


func _register_villages() -> void:
	villages.clear()

	var failure_callback := Callable(self, "_on_village_failed")
	var cargo_callback := Callable(
		self,
		"_on_village_cargo_received"
	)

	for node in get_tree().get_nodes_in_group("villages"):
		if node is not Area2D or not is_ancestor_of(node):
			continue

		var village := node as Area2D
		villages.append(village)

		if (
			village.has_signal("village_failed")
			and not village.is_connected(
				"village_failed",
				failure_callback
			)
		):
			village.connect("village_failed", failure_callback)

		if (
			village.has_signal("cargo_received")
			and not village.is_connected(
				"cargo_received",
				cargo_callback
			)
		):
			village.connect("cargo_received", cargo_callback)


func _register_level_systems() -> void:
	if not route_network_manager.route_count_changed.is_connected(
		_on_route_count_changed
	):
		route_network_manager.route_count_changed.connect(
			_on_route_count_changed
		)
	if not route_network_manager.can_undo_changed.is_connected(
		_on_can_undo_changed
	):
		route_network_manager.can_undo_changed.connect(
			_on_can_undo_changed
		)
	if not route_network_manager.vehicle_selected.is_connected(
		_on_route_vehicle_selected
	):
		route_network_manager.vehicle_selected.connect(
			_on_route_vehicle_selected
		)
	if not route_network_manager.vehicle_info_cleared.is_connected(
		_on_route_vehicle_info_cleared
	):
		route_network_manager.vehicle_info_cleared.connect(
			_on_route_vehicle_info_cleared
		)
	if not game_hud.undo_route_requested.is_connected(
		_on_game_hud_undo_route_requested
	):
		game_hud.undo_route_requested.connect(
			_on_game_hud_undo_route_requested
		)


func _start_optional_tutorial() -> void:
	if tutorial_overlay.has_method("start_tutorial"):
		tutorial_overlay.call("start_tutorial")


func are_all_villages_sustaining() -> bool:
	if villages.is_empty():
		return false

	for village in villages:
		if not village.has_method("is_self_sustaining"):
			return false
		if not bool(village.call("is_self_sustaining")):
			return false

	return true


func update_sustain_timer() -> void:
	if is_game_over or is_victory:
		return

	if are_all_villages_sustaining():
		if sustain_timer.is_stopped():
			sustain_timer.start()
			print("[BaseLevel] Sustain countdown dimulai")
	else:
		if not sustain_timer.is_stopped():
			sustain_timer.stop()
			print("[BaseLevel] Sustain countdown diulang")


func trigger_game_over(failed_village: Area2D) -> void:
	if is_game_over or is_victory:
		return

	is_game_over = true
	failed_village_label.text = str(
		failed_village.name,
		" gagal menerima bantuan."
	)
	game_over_screen.visible = true
	AudioManager.play_game_over()
	get_tree().paused = true

func _update_victory_summary() -> void:
	var elapsed_time: float = game_hud.get_elapsed_game_time()
	var total_seconds: int = floori(elapsed_time)

	var hours: int = int(total_seconds / 3600)
	var minutes: int = int((total_seconds % 3600) / 60)
	var seconds: int = total_seconds % 60

	victory_day_label.text = "Hari: %d" % game_hud.get_current_day()
	victory_time_label.text = (
		"Waktu: %02d:%02d:%02d"
		% [hours, minutes, seconds]
	)
	victory_logistics_label.text = (
		"Suplai terkirim: %d"
		% total_logistics_delivered
	)
	victory_route_label.text = (
		"Rute dibuat: %d"
		% route_network_manager.expedition_routes.size()
	)

func _on_village_failed(failed_village: Area2D) -> void:
	trigger_game_over(failed_village)


func _on_village_cargo_received(received_amount: int) -> void:
	if received_amount <= 0:
		return

	total_logistics_delivered += received_amount
	game_hud.set_logistics_count(total_logistics_delivered)

	AudioManager.play_supply_delivered()


func _on_route_count_changed(route_count: int) -> void:
	game_hud.set_route_count(route_count)


func _on_can_undo_changed(can_undo: bool) -> void:
	game_hud.set_can_undo(can_undo)


func _on_route_vehicle_selected(vehicle: TransportVehicle) -> void:
	if is_instance_valid(vehicle):
		game_hud.show_vehicle_info(vehicle)


func _on_route_vehicle_info_cleared() -> void:
	game_hud.hide_vehicle_info()


func _on_game_hud_undo_route_requested() -> void:
	route_network_manager.undo_last_route()


func _on_sustain_timer_timeout() -> void:
	if is_game_over or is_victory:
		return

	is_victory = true
	SaveManager.record_level_completion(
		level_id,
		game_hud.get_elapsed_game_time(),
		game_hud.get_current_day(),
		total_logistics_delivered
	)
	_update_victory_summary()
	victory_screen.visible = true
	AudioManager.play_victory()
	get_tree().paused = true
	print("[BaseLevel] LEVEL COMPLETED")


func _on_restart_button_pressed() -> void:
	_resume_normal_time()
	get_tree().reload_current_scene()


func _on_replay_button_pressed() -> void:
	_resume_normal_time()
	get_tree().reload_current_scene()


func _on_level_selection_button_pressed() -> void:
	_resume_normal_time()

	if level_selection_scene_path.is_empty():
		push_error("BaseLevel: path Level Selection kosong")
		return
	if not ResourceLoader.exists(level_selection_scene_path):
		push_error(
			"BaseLevel: scene tidak ditemukan: "
			+ level_selection_scene_path
		)
		return

	get_tree().change_scene_to_file(level_selection_scene_path)

func _on_main_menu_button_pressed() -> void:
	_resume_normal_time()
	get_tree().change_scene_to_file(
		"res://scenes/ui/main_menu.tscn"
	)

func _resume_normal_time() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
