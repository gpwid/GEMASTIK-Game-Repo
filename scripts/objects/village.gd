extends Area2D

signal route_drag_finished(target_position: Vector2, target_village: Area2D)
signal village_failed(failed_village: Area2D)
signal cargo_received(received_amount: int)

const CARGO_MAX_CAPACITY: int = 6
var request_count: int = 0
var requested_cargo: Array[int] = []
var is_crisis_active: bool = false
var is_failure_countdown_active: bool = false
var is_failed: bool = false
var has_supply_route: bool = false
var has_received_valid_delivery: bool = false
var crisis_level: float = 0.0

@onready var request_slots_child = $RequestSlots.get_children()
@onready var request_timer = $RequestTimer
@onready var full_queue_timer = $FullQueueTimer
@onready var failure_timer = $FailureTimer
@onready var crisis_gauge = $CrisisGauge

@export var crisis_rise_per_second: float = 10.0
@export var island_id: int = 0
@export var is_coastal: bool = false
@export var sustaining_request_limit: int = 2
@export var food_icon: Texture2D
@export var medical_icon: Texture2D
@export var infrastructure_icon: Texture2D

func can_accept_route() -> bool:
	if not has_supply_route and not is_failed:
		return true
	return false	
	
func is_self_sustaining() -> bool:
	return (
		has_supply_route
		and has_received_valid_delivery
		and request_count <= sustaining_request_limit
		and not is_crisis_active
		and not is_failure_countdown_active
		and not is_failed
	)
		
func supports_truck() -> bool:
	return true
	
func supports_ship() -> bool:
	return is_coastal

func set_route_connected() -> void:
	has_supply_route = true
	print("[set_route_connected:village.gd] ", name, " terhubung")
	
func set_route_disconnected() -> void:
	has_supply_route = false	
	
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

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed == false:
			var global_pos_route_target = $RouteTarget.global_position
			emit_signal("route_drag_finished", global_pos_route_target, self)

func get_requested_cargo() -> Array[int]:
	return requested_cargo.duplicate()

func _on_request_timer_timeout() -> void:
	if requested_cargo.size() < CARGO_MAX_CAPACITY:
		var rng_cargo: int = randi_range(0, CargoTypes.Type.size() - 1)
		requested_cargo.append(rng_cargo)
		request_count = requested_cargo.size()
		print("[_on_request_timer_timeout:village.gd] Village: ", name, " Cargo baru: ", rng_cargo, " Kebutuhan: ", requested_cargo, " Kapasitas: ", request_count, "/", CARGO_MAX_CAPACITY)
		update_request_display()
		update_full_queue_state()
		
func update_request_display() -> void:
	for index in range(request_slots_child.size()):
		var slot = request_slots_child[index]
		var has_request: bool = index < requested_cargo.size()

		slot.visible = has_request

		if has_request:
			var cargo_type: int = requested_cargo[index]
			slot.texture = get_cargo_icon(cargo_type)

func get_cargo_icon(cargo_type: int) -> Texture2D:
	match cargo_type:
		CargoTypes.Type.FOOD:
			return food_icon
		CargoTypes.Type.MEDICAL:
			return medical_icon
		CargoTypes.Type.INFRASTRUCTURE:
			return infrastructure_icon
		_:
			return null

func receive_cargo_batch(cargo_items: Array[int]) -> Array[int]:
	var undelivered_cargo: Array[int] = []
	for cargo_type in cargo_items:
		var requested_index: int = requested_cargo.find(cargo_type)
		if requested_index != -1:
			requested_cargo.remove_at(requested_index)
		else:
			undelivered_cargo.append(cargo_type)
	request_count = requested_cargo.size()
	update_request_display()
	update_full_queue_state()
	print("[receive_cargo_batch:village.gd] Village: ", name, " Cargo datang: ", cargo_items, " Ditolak: ", undelivered_cargo, " Kebutuhan tersisa: ", requested_cargo)
	
	var received_amount: int = cargo_items.size() - undelivered_cargo.size()
	if received_amount > 0:
		has_received_valid_delivery = true
		cargo_received.emit(received_amount)
	return undelivered_cargo

func _on_full_queue_timer_timeout() -> void:
	is_crisis_active = true
	crisis_gauge.tint_progress = Color("#E45757")
	print("[_on_full_queue_timer_timeout:village.gd] ", name, " failure countdown dimulai")
	
func update_full_queue_state() -> void:
	if request_count == CARGO_MAX_CAPACITY and full_queue_timer.is_stopped() and not is_crisis_active:
		full_queue_timer.start()
		print("[update_full_queue_state:village.gd] ", name, "memasuki fase krisis")
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
	print("[_on_failure_timer_timeout:village.gd] ", name, " lenyap karena kekurangan suplai")
	emit_signal("village_failed", self)
