class_name VehicleInfoPanel
extends PanelContainer


@export var follow_offset: Vector2 = Vector2(48.0, -100.0)
@export var screen_margin: float = 12.0
@export var normal_fuel_color: Color = Color("#39D325")
@export var critical_fuel_color: Color = Color("#F0B429")
@export var empty_fuel_color: Color = Color("#E45757")

var selected_vehicle: TransportVehicle = null
var fuel_fill_style: StyleBoxFlat = StyleBoxFlat.new()

@onready var vehicle_icon: TextureRect = %VehicleIcon
@onready var vehicle_name_label: Label = %VehicleNameLabel
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var driver_name_label: Label = %DriverNameLabel
@onready var status_label: Label = %StatusLabel
@onready var food_count_label: Label = %FoodCountLabel
@onready var medical_count_label: Label = %MedicalCountLabel
@onready var infrastructure_count_label: Label = %InfrastructureCountLabel

	
func _process(_delta: float) -> void:
	if not is_instance_valid(selected_vehicle):
		hide_vehicle_info()
		return
	update_display()
	update_panel_position()
	
func _ready() -> void:
	fuel_fill_style.bg_color = normal_fuel_color
	fuel_fill_style.corner_radius_top_left = 6
	fuel_fill_style.corner_radius_top_right = 6
	fuel_fill_style.corner_radius_bottom_left = 6
	fuel_fill_style.corner_radius_bottom_right = 6
	fuel_bar.add_theme_stylebox_override("fill",fuel_fill_style)
	visible = false

func show_vehicle(vehicle: TransportVehicle) -> void:
	if vehicle == null:
		return
	selected_vehicle = vehicle
	visible = true
	update_display()
	
func hide_vehicle_info() -> void:
	selected_vehicle = null
	visible = false
	
func update_display() -> void:
	if not is_instance_valid(selected_vehicle):
		hide_vehicle_info()
		return

	vehicle_icon.texture = selected_vehicle.vehicle_icon
	vehicle_name_label.text = selected_vehicle.vehicle_name
	driver_name_label.text = selected_vehicle.driver_name

	fuel_bar.max_value = selected_vehicle.max_fuel
	fuel_bar.value = selected_vehicle.current_fuel

	update_fuel_visual()
	update_status()
	update_cargo_display()
	
func update_status() -> void:
	if selected_vehicle.is_broken_down:
		status_label.text = "Status: Rusak"

	elif selected_vehicle.current_fuel <= 0.0:
		var remaining_time: float = maxf(selected_vehicle.empty_fuel_grace_duration - selected_vehicle.empty_fuel_duration, 0.0)

		status_label.text = str("Status: Darurat — rusak dalam ", ceili(remaining_time), " detik")

	elif (selected_vehicle.current_fuel <= selected_vehicle.red_fuel_threshold):
		status_label.text = "Status: Konservasi"
	else:
		status_label.text = "Status: Normal"
		

func update_cargo_display() -> void:
	var food_count: int = selected_vehicle.cargo_manifest.count(CargoTypes.Type.FOOD)
	var medical_count: int = selected_vehicle.cargo_manifest.count(CargoTypes.Type.MEDICAL)
	var infrastructure_count: int = selected_vehicle.cargo_manifest.count(CargoTypes.Type.INFRASTRUCTURE)

	food_count_label.text = str(food_count, "×")
	medical_count_label.text = str(medical_count, "×")
	infrastructure_count_label.text = str(infrastructure_count, "×")

func update_panel_position() -> void:
	var vehicle_screen_position: Vector2 = (selected_vehicle.get_global_transform_with_canvas().origin)
	var viewport_size: Vector2 = (get_viewport().get_visible_rect().size)
	var target_position: Vector2 = (vehicle_screen_position + follow_offset)

	if target_position.x + size.x > viewport_size.x - screen_margin:
		target_position.x = (vehicle_screen_position.x - size.x - absf(follow_offset.x))
	target_position.x = clampf(target_position.x, screen_margin, viewport_size.x - size.x - screen_margin)
	target_position.y = clampf(target_position.y, screen_margin, viewport_size.y - size.y - screen_margin)
	global_position = target_position
	
func update_fuel_visual() -> void:
	if selected_vehicle.is_broken_down:
		fuel_fill_style.bg_color = empty_fuel_color
	elif selected_vehicle.current_fuel <= 0.0:
		fuel_fill_style.bg_color = empty_fuel_color
	elif (selected_vehicle.current_fuel <= selected_vehicle.red_fuel_threshold):
		fuel_fill_style.bg_color = critical_fuel_color
	else:
		fuel_fill_style.bg_color = normal_fuel_color
