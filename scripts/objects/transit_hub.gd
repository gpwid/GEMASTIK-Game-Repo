class_name TransitHub
extends Area2D

signal connection_drag_started(start_hub: TransitHub)
signal connection_drag_finished(end_hub: TransitHub)

@export var is_port: bool = false
@export var island_id: int = 0
@export var cargo_storage_capacity: int = 16

var cargo_storage: Array[int] = []
var is_connected_to_supply: bool = false

@onready var land_visual: Sprite2D = $LandVisual
@onready var port_visual: Sprite2D = $PortVisual
@onready var truck_stop: Marker2D = $TruckStop
@onready var ship_dock: Marker2D = $ShipDock

func supports_truck() -> bool:
	return true
	
func supports_ship() -> bool:
	return is_port
	
func transfers_cargo() -> bool:
	return is_port		

func refuels_vehicle() -> bool:
	return true

func can_start_connection() -> bool:
	return is_connected_to_supply

func reset_connection() -> void:
	is_connected_to_supply = false	
	
func mark_connected() -> void:
	is_connected_to_supply = true	

func _ready() -> void:
	add_to_group("transit_hubs")
	update_hub_visual()
	
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			connection_drag_started.emit(self)
		else:
			connection_drag_finished.emit(self)

func update_hub_visual() -> void:
	land_visual.visible = not is_port
	port_visual.visible = is_port

func get_remaining_storage_capacity() -> int:
	var max_capacity: int = cargo_storage_capacity
	return maxi(max_capacity - cargo_storage.size(), 0)
	
func store_cargo(cargo_items: Array[int]) -> Array[int]:
	var remaining_cargo: Array[int] = []
	if not transfers_cargo():
		return cargo_items.duplicate()
	
	for cargo_type in cargo_items:
		if get_remaining_storage_capacity() > 0:
			cargo_storage.append(cargo_type)
		else:
			remaining_cargo.append(cargo_type)
	
	return remaining_cargo	

func take_matching_cargo(requested_types: Array[int], requested_amount: int) -> Array[int]:
	var selected_cargo: Array[int] = []
	if not transfers_cargo():
		return selected_cargo
	if requested_amount <= 0:
		return selected_cargo
	for requested_type in requested_types:
		if selected_cargo.size() >= requested_amount:
			break
		
		var cargo_index: int = cargo_storage.find(requested_type)
		if cargo_index != -1:
			selected_cargo.append(cargo_storage[cargo_index])
			cargo_storage.remove_at(cargo_index)
		
	return selected_cargo	
	
func take_cargo(requested_amount: int) -> Array[int]:
	var given_cargo: Array[int] = []
	if not transfers_cargo():
		return given_cargo
	var allowed_cargo_amount: int = mini(requested_amount, cargo_storage.size())
	for _i in range(allowed_cargo_amount):
		var front_cargo: int = cargo_storage.pop_front()
		given_cargo.append(front_cargo)
	return given_cargo
