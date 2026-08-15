class_name TransportVehicle
extends Node2D

## Kendaraan adalah alat perjalanan sementara milik Expedition Leader.
## Kendaraan menyimpan fuel dan statistik moda, sedangkan manifest cargo
## tetap dimiliki leader dan hanya direferensikan oleh kendaraan aktif.

signal return_requested(vehicle: TransportVehicle)
signal broken_down(vehicle: TransportVehicle)
signal selected(vehicle: TransportVehicle)

@export var cargo_capacity: int = 6
@export var travel_speed: float = 80.0
@export var leader_name: String = "Pemimpin Ekspedisi"
@export var max_fuel: float = 100.0
@export var current_fuel: float = 100.0
@export var red_fuel_threshold: float = 20.0
@export var empty_fuel_grace_duration: float = 10.0
@export var repair_duration: float = 10.0
@export var fuel_consumption_per_distance: float = 0.05
@export_range(0.1, 1.0) var conservation_speed_multiplier: float = 0.5
@export var vehicle_name: String = "Kendaraan Ekspedisi"
@export var vehicle_icon: Texture2D

var leader_id: String = ""
var expedition_status: String = "Menunggu"
var empty_fuel_duration: float = 0.0
var is_broken_down: bool = false
var cargo_manifest: Array[int] = []


func configure_for_leader(leader: ExpeditionLeader) -> void:
	leader_id = leader.leader_id
	leader_name = leader.leader_name
	cargo_capacity = leader.cargo_capacity
	cargo_manifest = leader.cargo_manifest
	expedition_status = leader.get_status_text()

	self_modulate = leader.leader_color.lightened(0.35)


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


func load_cargo_batch(cargo_items: Array[int]) -> Array[int]:
	var remaining_cargo: Array[int] = []

	for cargo_type in cargo_items:
		if not load_cargo(cargo_type):
			remaining_cargo.append(cargo_type)

	return remaining_cargo


func unload_all_cargo() -> Array[int]:
	var unloaded_cargo: Array[int] = cargo_manifest.duplicate()
	cargo_manifest.clear()
	return unloaded_cargo


func consume_fuel(distance_traveled: float) -> void:
	if is_broken_down:
		return

	current_fuel = maxf(
		current_fuel - distance_traveled * fuel_consumption_per_distance,
		0.0
	)


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
		print("[Vehicle] ", leader_name, " mengalami breakdown")


func refuel() -> void:
	current_fuel = max_fuel
	empty_fuel_duration = 0.0
	is_broken_down = false


func get_effective_travel_speed() -> float:
	if is_broken_down:
		return 0.0

	if current_fuel <= red_fuel_threshold:
		return travel_speed * conservation_speed_multiplier

	return travel_speed


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
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
