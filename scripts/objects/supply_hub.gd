extends Area2D

## Sumber cargo tanpa batas untuk MVP.
## Expedition Leader meminta cargo yang sudah disesuaikan dengan reservasi desa.

signal route_drag_started(origin_position: Vector2)

@export var island_id: int = 0

var next_cargo_type: int = 0


func supports_truck() -> bool:
	return true


func supports_ship() -> bool:
	return false


func refuels_vehicle() -> bool:
	return true


func provide_matching_cargo(
	requested_types: Array[int],
	requested_amount: int
) -> Array[int]:
	var provided_cargo: Array[int] = []
	var allowed_amount := mini(requested_amount, requested_types.size())

	for index in range(allowed_amount):
		provided_cargo.append(requested_types[index])

	print("[SupplyHub] Menyiapkan cargo: ", provided_cargo)
	return provided_cargo


func provide_cargo(requested_amount: int) -> Array[int]:
	# Fungsi kompatibilitas untuk sistem lama atau testing manual.
	var provided_cargo: Array[int] = []

	for _index in range(requested_amount):
		provided_cargo.append(next_cargo_type)
		next_cargo_type = (
			(next_cargo_type + 1)
			% CargoTypes.Type.keys().size()
		)

	return provided_cargo


func _on_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		route_drag_started.emit($RouteOrigin.global_position)
