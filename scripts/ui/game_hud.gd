class_name GameHUD
extends Control

signal undo_route_requested

const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"

@export var seconds_per_day: float = 60.0

@export var pause_icon: Texture2D
@export var play_icon: Texture2D

var elapsed_game_time: float = 0.0
var current_game_speed: float = 1.0
var last_displayed_second: int = -1
var is_simulation_paused: bool = false

@onready var vehicle_info_panel: VehicleInfoPanel = $VehicleInfoPanel
@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton
@onready var undo_route_button: Button = %UndoRouteButton
@onready var settings_button: Button = %SettingsButton

@onready var day_label: Label = %DayLabel
@onready var time_label: Label = %TimeLabel
@onready var logistics_label: Label = %LogisticsLabel
@onready var route_label: Label = %RouteLabel

func _ready() -> void:
	pause_button.icon = pause_icon
	speed_button.tooltip_text = "Kecepatan: 1×"
	set_can_undo(false)

	update_time_display()
	set_logistics_count(0)
	set_route_count(0)
	
func _process(delta: float) -> void:
	if get_tree().paused or is_simulation_paused:
		return

	elapsed_game_time += delta

	var whole_second: int = floori(elapsed_game_time)

	if whole_second == last_displayed_second:
		return

	last_displayed_second = whole_second
	update_time_display()
	
func update_time_display() -> void:
	var total_seconds: int = floori(elapsed_game_time)

	var hours: int = int(total_seconds / 3600)
	var minutes: int = int((total_seconds % 3600) / 60)
	var seconds: int = total_seconds % 60

	time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]

	day_label.text = str(get_current_day())

func _on_pause_button_pressed() -> void:
	is_simulation_paused = not is_simulation_paused

	if is_simulation_paused:
		Engine.time_scale = 0.0
		pause_button.icon = play_icon
		pause_button.tooltip_text = "Lanjutkan"
	else:
		Engine.time_scale = current_game_speed
		pause_button.icon = pause_icon
		pause_button.tooltip_text = "Jeda"

func _on_speed_button_pressed() -> void:
	if is_simulation_paused:
		is_simulation_paused = false
		current_game_speed = 2.0

		pause_button.icon = pause_icon
		pause_button.tooltip_text = "Jeda"
	else:
		if current_game_speed == 1.0:
			current_game_speed = 2.0
		else:
			current_game_speed = 1.0

	Engine.time_scale = current_game_speed

	if current_game_speed == 2.0:
		speed_button.self_modulate = Color("#C7F5FF")
	else:
		speed_button.self_modulate = Color.WHITE

	speed_button.tooltip_text = str(
		"Kecepatan: ",
		int(current_game_speed),
		"x"
	)
	
func _on_undo_route_button_pressed() -> void:
	undo_route_requested.emit()

func _on_settings_button_pressed() -> void:
	if not ResourceLoader.exists(MAIN_MENU_PATH):
		push_error(
			"GameHUD: Main Menu tidak ditemukan: "
			+ MAIN_MENU_PATH
		)
		return

	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
	
func set_can_undo(can_undo: bool) -> void:
	undo_route_button.disabled = not can_undo
	if can_undo:
		undo_route_button.tooltip_text = ("Batalkan rute terakhir")
	else:
		undo_route_button.tooltip_text = ("Belum ada rute yang dapat dibatalkan")
		
func set_logistics_count(total_delivered: int) -> void:
	logistics_label.text = str(total_delivered)

func set_route_count(route_count: int) -> void:
	route_label.text = str(route_count)
	
func show_vehicle_info(vehicle: TransportVehicle) -> void:
	vehicle_info_panel.show_vehicle(vehicle)
	
func hide_vehicle_info() -> void:
	vehicle_info_panel.hide_vehicle_info()

func get_elapsed_game_time() -> float:
	return elapsed_game_time

func get_current_day() -> int:
	var safe_seconds_per_day: float = maxf(seconds_per_day, 0.001)
	return floori(elapsed_game_time / safe_seconds_per_day) + 1

func _exit_tree() -> void:
	Engine.time_scale = 1.0
