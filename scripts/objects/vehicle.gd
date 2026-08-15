class_name TransportVehicle
extends Node2D

signal return_requested(vehicle: TransportVehicle)
signal broken_down(vehicle: TransportVehicle)
signal selected(vehicle: TransportVehicle)

@export var cargo_capacity: int = 4
@export var travel_speed: float = 80.0
@export var driver_name: String = "Agus Panjaitan"
@export var max_fuel: float = 100.0
@export var current_fuel: float = 100.0
@export var red_fuel_threshold: float = 20.0
@export var empty_fuel_grace_duration: float = 10.0
@export var repair_duration: float = 10.0
@export var fuel_consumption_per_distance: float = 0.05
@export_range(0.1, 1.0) var conservation_speed_multiplier: float = 0.5
@export var vehicle_name: String = "Truk 1"
@export var vehicle_icon: Texture2D

var empty_fuel_duration: float = 0.0
var is_broken_down: bool = false
var cargo_manifest: Array[int] = []
var travel_direction: float = 1.0
var is_turning: bool = false
var departure_delay: float = 0.0

func get_cargo_count() -> int:
	return cargo_manifest.size()

func get_remaining_capacity() -> int:
	return maxi(cargo_capacity - get_cargo_count(), 0)
	
func can_load_cargo() -> bool:
	return get_remaining_capacity() > 0
	
func load_cargo(cargo_type: int) -> bool:
	if not can_load_cargo():
		return false

	cargo_manifest.append(cargo_type)
	return true

func unload_all_cargo() -> Array[int]:
	var unloaded_cargo: Array[int] = cargo_manifest.duplicate()
	cargo_manifest.clear()
	return unloaded_cargo
		
func load_cargo_batch(cargo_items: Array[int]) -> Array[int]:
	var remaining_cargo: Array[int] = []

	for cargo_type in cargo_items:
		var was_loaded: bool = load_cargo(cargo_type)
		if not was_loaded:
			remaining_cargo.append(cargo_type)

	return remaining_cargo
	
func consume_fuel(distance_traveled: float) -> void:
	if is_broken_down:
		return

	var consumed_fuel: float = distance_traveled * fuel_consumption_per_distance
	current_fuel = maxf(current_fuel - consumed_fuel, 0.0)

func update_fuel_condition(delta: float) -> void:
	if is_broken_down:
		return
	if current_fuel > 0.0:
		empty_fuel_duration = 0.0
		return
	empty_fuel_duration += delta

	if empty_fuel_duration >= empty_fuel_grace_duration:
		is_broken_down = true
		broken_down.emit(self)
		print("[update_fuel_condition:vehicle.gd] ", driver_name, " mengalami breakdown")
		
func refuel() -> void:
	current_fuel = max_fuel
	empty_fuel_duration = 0.0
	print("[refuel:vehicle.gd] ", driver_name, " mengisi fuel hingga ", current_fuel)

func get_effective_travel_speed() -> float:
	if is_broken_down:
		return 0.0
	if current_fuel <= red_fuel_threshold:
		return travel_speed * conservation_speed_multiplier

	return travel_speed

func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = (event as InputEventMouseButton)
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(self)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if is_broken_down:
			return

		return_requested.emit(self)
		get_viewport().set_input_as_handled()
