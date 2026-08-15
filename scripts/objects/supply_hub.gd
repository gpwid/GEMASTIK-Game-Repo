extends Area2D

signal route_drag_started(origin_position: Vector2)

@export var island_id: int = 0

var next_cargo_type: int = 0

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var global_pos = $RouteOrigin.global_position
			emit_signal("route_drag_started", global_pos)
				
func supports_truck() -> bool:
	return true

func supports_ship() -> bool:
	return false
	
func refuels_vehicle() -> bool:
	return true

func provide_cargo(requested_amount: int) -> Array[int]:
	var provided_cargo: Array[int] = []
	for _i in range(requested_amount):
		provided_cargo.append(next_cargo_type)
		next_cargo_type = (next_cargo_type + 1) % CargoTypes.Type.keys().size()		
	print("[provide_cargo:supply_hub.gd] Produksi: ", provided_cargo, " Tipe selanjutnya: ", next_cargo_type)
	return provided_cargo
	
	
