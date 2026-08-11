extends Area2D

signal route_drag_started(origin_position: Vector2)

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			print("Supply Hub Clicked")
			var global_pos = $RouteOrigin.global_position
			emit_signal("route_drag_started", global_pos)
				
