class_name GameHUD
extends Control

signal undo_route_requested

@export var seconds_per_day: float = 60.0

@export var pause_icon: Texture2D
@export var play_icon: Texture2D

var elapsed_game_time: float = 0.0
var current_game_speed: float = 1.0
var last_displayed_second: int = -1

@onready var vehicle_info_panel: VehicleInfoPanel = $VehicleInfoPanel
@onready var pause_button: Button = %PauseButton
@onready var speed_button: Button = %SpeedButton
@onready var undo_route_button: Button = %UndoRouteButton

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
	if get_tree().paused:
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

	var current_day: int = floori(elapsed_game_time / seconds_per_day) + 1

	day_label.text = str(current_day)

func _on_pause_button_pressed() -> void:
	var should_pause: bool = not get_tree().paused
	get_tree().paused = should_pause

	if should_pause:
		pause_button.icon = play_icon
		pause_button.tooltip_text = "Lanjutkan"
	else:
		pause_button.icon = pause_icon
		pause_button.tooltip_text = "Jeda"


func _on_speed_button_pressed() -> void:
	if current_game_speed == 1.0:
		current_game_speed = 2.0
		speed_button.self_modulate = Color("#C7F5FF")
	else:
		current_game_speed = 1.0
		speed_button.self_modulate = Color.WHITE

	Engine.time_scale = current_game_speed
	speed_button.tooltip_text = str("Kecepatan: ", int(current_game_speed), "x")
	
func _on_undo_route_button_pressed() -> void:
	undo_route_requested.emit()
	
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

func _exit_tree() -> void:
	Engine.time_scale = 1.0
