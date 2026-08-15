extends Area2D

## Village menghasilkan kebutuhan cargo dan menyimpan reservasi tiap leader.
## Reservasi mencegah dua leader membawa cargo untuk permintaan yang sama.

signal route_drag_finished(target_position: Vector2, target_village: Area2D)
signal village_failed(failed_village: Area2D)
signal cargo_received(received_amount: int)

const CARGO_MAX_CAPACITY: int = 6

var request_count: int = 0
var requested_cargo: Array[int] = []
var cargo_reservations: Dictionary = {}
var is_crisis_active: bool = false
var is_failure_countdown_active: bool = false
var is_failed: bool = false
var has_supply_route: bool = false
var has_received_valid_delivery: bool = false
var crisis_level: float = 0.0

@export var crisis_rise_per_second: float = 10.0
@export var island_id: int = 0
@export var is_coastal: bool = false
@export var sustaining_request_limit: int = 2
@export var food_icon: Texture2D
@export var medical_icon: Texture2D
@export var infrastructure_icon: Texture2D

@onready var request_slots_child: Array[Node] = $RequestSlots.get_children()
@onready var request_timer: Timer = $RequestTimer
@onready var full_queue_timer: Timer = $FullQueueTimer
@onready var failure_timer: Timer = $FailureTimer
@onready var crisis_gauge: TextureProgressBar = $CrisisGauge


func _ready() -> void:
	update_request_display()


func _process(delta: float) -> void:
	if not full_queue_timer.is_stopped():
		var elapsed_time := full_queue_timer.wait_time - full_queue_timer.time_left
		crisis_gauge.value = elapsed_time / full_queue_timer.wait_time * 100.0
	elif is_crisis_active:
		crisis_level = clampf(
			crisis_level + crisis_rise_per_second * delta,
			0.0,
			100.0
		)
		crisis_gauge.value = crisis_level

		if (
			crisis_level >= 100.0
			and not is_failure_countdown_active
			and not is_failed
		):
			is_failure_countdown_active = true
			failure_timer.start()
			print("[Village] ", name, " memasuki failure countdown")


func can_accept_route() -> bool:
	return not has_supply_route and not is_failed


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
	print("[Village] ", name, " terhubung ke jaringan")


func set_route_disconnected() -> void:
	has_supply_route = false


func get_requested_cargo() -> Array[int]:
	return requested_cargo.duplicate()


func get_unreserved_cargo() -> Array[int]:
	var available_cargo: Array[int] = requested_cargo.duplicate()

	for reservation_variant in cargo_reservations.values():
		var reservation: Array = reservation_variant
		for cargo_variant in reservation:
			var cargo_type := int(cargo_variant)
			var cargo_index := available_cargo.find(cargo_type)
			if cargo_index != -1:
				available_cargo.remove_at(cargo_index)

	return available_cargo


func reserve_cargo(leader_id: String, requested_amount: int) -> Array[int]:
	if leader_id.is_empty() or requested_amount <= 0 or is_failed:
		return []

	# Satu leader hanya boleh memiliki satu reservasi aktif.
	if cargo_reservations.has(leader_id):
		return _get_reservation(leader_id)

	var available_cargo := get_unreserved_cargo()
	var selected_cargo: Array[int] = []
	var allowed_amount := mini(requested_amount, available_cargo.size())

	for index in range(allowed_amount):
		selected_cargo.append(available_cargo[index])

	if not selected_cargo.is_empty():
		cargo_reservations[leader_id] = selected_cargo.duplicate()
		print(
			"[Village] ", name,
			" reservasi untuk ", leader_id,
			": ", selected_cargo
		)

	return selected_cargo


func release_cargo_reservation(leader_id: String) -> Array[int]:
	var released_cargo := _get_reservation(leader_id)
	cargo_reservations.erase(leader_id)
	return released_cargo


func receive_reserved_cargo(
	leader_id: String,
	cargo_items: Array[int]
) -> Array[int]:
	var reservation := _get_reservation(leader_id)
	var undelivered_cargo: Array[int] = []
	var received_amount: int = 0

	for cargo_type in cargo_items:
		var reservation_index := reservation.find(cargo_type)
		var requested_index := requested_cargo.find(cargo_type)

		if reservation_index != -1 and requested_index != -1:
			reservation.remove_at(reservation_index)
			requested_cargo.remove_at(requested_index)
			received_amount += 1
		else:
			undelivered_cargo.append(cargo_type)

	cargo_reservations.erase(leader_id)
	request_count = requested_cargo.size()
	update_request_display()
	update_full_queue_state()

	if received_amount > 0:
		has_received_valid_delivery = true
		cargo_received.emit(received_amount)

	print(
		"[Village] ", name,
		" menerima ", received_amount,
		" cargo dari ", leader_id,
		" | Sisa kebutuhan: ", requested_cargo
	)
	return undelivered_cargo


func receive_cargo_batch(cargo_items: Array[int]) -> Array[int]:
	# Fungsi kompatibilitas untuk pengiriman yang belum memakai reservasi.
	var undelivered_cargo: Array[int] = []
	var received_amount: int = 0

	for cargo_type in cargo_items:
		var requested_index := requested_cargo.find(cargo_type)
		if requested_index != -1:
			requested_cargo.remove_at(requested_index)
			received_amount += 1
		else:
			undelivered_cargo.append(cargo_type)

	request_count = requested_cargo.size()
	update_request_display()
	update_full_queue_state()

	if received_amount > 0:
		has_received_valid_delivery = true
		cargo_received.emit(received_amount)

	return undelivered_cargo


func _get_reservation(leader_id: String) -> Array[int]:
	var result: Array[int] = []
	if not cargo_reservations.has(leader_id):
		return result

	var stored_reservation: Array = cargo_reservations[leader_id]
	for cargo_variant in stored_reservation:
		result.append(int(cargo_variant))
	return result


func _on_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		route_drag_finished.emit($RouteTarget.global_position, self)


func _on_request_timer_timeout() -> void:
	if requested_cargo.size() >= CARGO_MAX_CAPACITY:
		return

	var cargo_type := randi_range(0, CargoTypes.Type.size() - 1)
	requested_cargo.append(cargo_type)
	request_count = requested_cargo.size()
	update_request_display()
	update_full_queue_state()

	print(
		"[Village] ", name,
		" kebutuhan baru: ", cargo_type,
		" | Antrean: ", requested_cargo
	)


func update_request_display() -> void:
	for index in range(request_slots_child.size()):
		var slot := request_slots_child[index] as Sprite2D
		if slot == null:
			continue

		var has_request := index < requested_cargo.size()
		slot.visible = has_request

		if has_request:
			slot.texture = get_cargo_icon(requested_cargo[index])


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


func update_full_queue_state() -> void:
	if (
		request_count == CARGO_MAX_CAPACITY
		and full_queue_timer.is_stopped()
		and not is_crisis_active
	):
		full_queue_timer.start()
		print("[Village] ", name, " memasuki fase penuh")
	elif request_count < CARGO_MAX_CAPACITY:
		failure_timer.stop()
		full_queue_timer.stop()
		is_crisis_active = false
		is_failure_countdown_active = false
		crisis_level = 0.0
		crisis_gauge.value = 0.0
		crisis_gauge.tint_progress = Color("#C98D00")


func _on_full_queue_timer_timeout() -> void:
	is_crisis_active = true
	crisis_gauge.tint_progress = Color("#E45757")
	print("[Village] ", name, " memasuki krisis")


func _on_failure_timer_timeout() -> void:
	if is_failed:
		return

	is_failed = true
	is_crisis_active = false
	is_failure_countdown_active = false
	full_queue_timer.stop()
	failure_timer.stop()
	request_timer.stop()
	set_process(false)
	village_failed.emit(self)
	print("[Village] ", name, " gagal menerima bantuan")
