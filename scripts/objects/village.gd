extends Area2D

signal route_drag_finished(target_position: Vector2, target_village: Area2D)
signal village_failed(failed_village: Area2D)

const CARGO_MAX_CAPACITY: int = 6
var request_count: int = 0
var is_crisis_active: bool = false
var is_failure_countdown_active: bool = false
var is_failed: bool = false
var has_supply_route: bool = false

@onready var request_slots_child = $RequestSlots.get_children()
@onready var request_timer = $RequestTimer
@onready var full_queue_timer = $FullQueueTimer
@onready var failure_timer = $FailureTimer
@onready var crisis_gauge = $CrisisGauge

@export var crisis_rise_per_second: float = 10.0
var crisis_level: float = 0.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	update_request_display()
	
func _process(delta: float) -> void:
	if not full_queue_timer.is_stopped():
		var elapsed_time: float = full_queue_timer.wait_time - full_queue_timer.time_left
		var percentage: float = elapsed_time / full_queue_timer.wait_time * 100
		crisis_gauge.value = percentage
	elif is_crisis_active:
		crisis_level += crisis_rise_per_second * delta
		crisis_level = clampf(crisis_level, 0.0, 100.0)
		crisis_gauge.value = crisis_level
		if crisis_level >= 100 and is_failure_countdown_active == false and not is_failed:
			is_failure_countdown_active = true
			failure_timer.start()
			print("Failure countdown... STARTED")
				
		
func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed == false:
			var global_pos_route_target = $RouteTarget.global_position
			emit_signal("route_drag_finished", global_pos_route_target, self)


func _on_request_timer_timeout() -> void:
	if request_count < CARGO_MAX_CAPACITY:
		request_count += 1
		update_request_display()
		update_full_queue_state()
		
func update_request_display() -> void:
	for index in range(request_slots_child.size()):
		var slot = request_slots_child[index]
		slot.visible = index < request_count
		
func receive_delivery(cargo_amount: int) -> int:
	var received_amount: int = mini(cargo_amount, request_count)
	request_count -= received_amount
	update_request_display()
	update_full_queue_state()
	print("Delivered: ", received_amount, " | Remaining: ", request_count)
	return received_amount

func _on_full_queue_timer_timeout() -> void:
	is_crisis_active = true
	crisis_gauge.tint_progress = Color("#E45757")
	print("Crisis started")
	
func update_full_queue_state() -> void:
	if request_count == CARGO_MAX_CAPACITY and full_queue_timer.is_stopped() and not is_crisis_active:
		full_queue_timer.start()
	elif request_count < CARGO_MAX_CAPACITY:
		failure_timer.stop()
		full_queue_timer.stop()
		is_crisis_active = false
		is_failure_countdown_active = false
		crisis_level = 0.0
		crisis_gauge.value = 0
		crisis_gauge.tint_progress = Color("c98d00")


func _on_failure_timer_timeout() -> void:
	is_failed = true
	is_crisis_active = false
	is_failure_countdown_active = false
	full_queue_timer.stop()
	failure_timer.stop()
	request_timer.stop()
	set_process(false)
	print(name, " lenyap karena kekurangan suplai")
	emit_signal("village_failed", self)
	
func set_route_connected() -> void:
	has_supply_route = true
	print(name, " terhubung!")
	
func can_accept_route() -> bool:
	if not has_supply_route and not is_failed:
		return true
	return false	
	
func is_self_sustaining() -> bool:
	if has_supply_route and request_count < CARGO_MAX_CAPACITY and is_crisis_active == false and is_failure_countdown_active == false and is_failed == false:
		return true	
	else:
		return false
