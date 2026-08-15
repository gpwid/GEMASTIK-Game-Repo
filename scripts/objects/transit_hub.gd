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
