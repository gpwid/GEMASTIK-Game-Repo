extends Area2D

signal route_drag_finished(target_position: Vector2, target_village: Area2D)
const CARGO_MAX_CAPACITY: int = 6
var request_count: int = 0
@onready var request_slots_child = $RequestSlots.get_children()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_request_display()


func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed == false:
			var global_pos_route_target = $RouteTarget.global_position
			emit_signal("route_drag_finished", global_pos_route_target, self)


func _on_request_timer_timeout() -> void:
	if request_count < CARGO_MAX_CAPACITY:
		request_count += 1
		update_request_display()
		
func update_request_display() -> void:
	for index in range(request_slots_child.size()):
		var slot = request_slots_child[index]
		slot.visible = index < request_count
		
func receive_delivery(cargo_amount: int) -> int:
	var received_amount: int = mini(cargo_amount, request_count)
	request_count -= received_amount
	update_request_display()
	print("Delivered: ", received_amount, " | Remaining: ", request_count)
	return received_amount
	
