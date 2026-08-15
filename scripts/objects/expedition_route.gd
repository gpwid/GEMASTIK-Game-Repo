class_name ExpeditionRoute
extends Node

## Satu rute multimoda linear dari Supply Hub sampai satu Village.
## Nama class dipertahankan agar transport_route.tscn lama tetap bekerja.

signal leader_returned(
	leader_id: String,
	leader_name: String,
	leader_color: Color,
	icon_texture: Texture2D
)
signal vehicle_selected(vehicle: TransportVehicle)

const TRUCK_SCENE: PackedScene = preload(
	"res://scenes/objects/truck.tscn"
)
const SHIP_SCENE: PackedScene = preload(
	"res://scenes/objects/ship.tscn"
)

var segments: Array[RouteSegment] = []
var assigned_leaders: Array[ExpeditionLeader] = []

@export var route_color: Color = Color("#57C7FF")
@export var inactive_route_color: Color = Color("#66747A")
@export var leader_departure_interval: float = 1.5
@export var reservation_retry_interval: float = 0.5
@export var turnaround_duration: float = 0.4
@export var drop_detection_radius: float = 48.0

@onready var combined_path: Path2D = $CombinedPath


func _process(delta: float) -> void:
	for leader in assigned_leaders.duplicate():
		if leader.status == ExpeditionLeader.Status.REPAIRING:
			continue

		if leader.status == ExpeditionLeader.Status.WAITING:
			_process_waiting_leader(leader, delta)
		elif leader.status == ExpeditionLeader.Status.TRAVELING:
			_process_traveling_leader(leader, delta)


func add_segment(segment: RouteSegment) -> bool:
	if segment == null:
		return false

	if segments.is_empty():
		segments.append(segment)
		segment.parent_expedition_route = self
		rebuild_combined_path()
		update_route_visual()
		return true

	# Rute yang sudah mencapai Village tidak dapat diperpanjang.
	if is_complete():
		return false

	var last_segment: RouteSegment = segments.back()
	if last_segment.end_point != segment.start_point:
		return false

	segments.append(segment)
	segment.parent_expedition_route = self
	rebuild_combined_path()
	update_route_visual()
	return true


func is_complete() -> bool:
	var start_point := get_route_start_point()
	var end_point := get_route_end_point()

	if start_point == null or end_point == null:
		return false

	return (
		start_point.has_method("provide_matching_cargo")
		and end_point.has_method("reserve_cargo")
		and end_point.has_method("receive_reserved_cargo")
	)


func get_route_start_point() -> Area2D:
	if segments.is_empty():
		return null
	return segments.front().start_point


func get_route_end_point() -> Area2D:
	if segments.is_empty():
		return null
	return segments.back().end_point


func get_distance_to_route(world_position: Vector2) -> float:
	if combined_path.curve == null or combined_path.curve.point_count < 2:
		return INF

	var local_position := combined_path.to_local(world_position)
	var closest_position := combined_path.curve.get_closest_point(local_position)
	return local_position.distance_to(closest_position)


func rebuild_combined_path() -> void:
	var new_combined_curve := Curve2D.new()

	for segment in segments:
		if segment.curve == null:
			continue

		for point in segment.curve.get_baked_points():
			var global_point := segment.to_global(point)
			var combined_local_point := combined_path.to_local(global_point)

			if new_combined_curve.point_count > 0:
				var last_index := new_combined_curve.point_count - 1
				var last_point := new_combined_curve.get_point_position(
					last_index
				)
				if last_point.is_equal_approx(combined_local_point):
					continue

			new_combined_curve.add_point(combined_local_point)

	combined_path.curve = new_combined_curve
	print(
		"[ExpeditionRoute] ", name,
		" | Segment: ", segments.size(),
		" | Panjang: ", new_combined_curve.get_baked_length()
	)


func update_route_visual() -> void:
	var is_active := not assigned_leaders.is_empty()
	var displayed_color := route_color if is_active else inactive_route_color

	for segment in segments:
		if is_instance_valid(segment):
			segment.set_route_visual(displayed_color, is_active)


func try_assign_leader(
	leader_id: String,
	leader_name: String,
	leader_color: Color,
	icon_texture: Texture2D
) -> bool:
	if not is_complete():
		print("[ExpeditionRoute] Token hanya dapat dipasang pada rute lengkap")
		return false

	for existing_leader in assigned_leaders:
		if existing_leader.leader_id == leader_id:
			return false

	var leader := ExpeditionLeader.new(
		leader_id,
		leader_name,
		leader_color,
		icon_texture,
		6
	)
	leader.departure_delay = assigned_leaders.size() * leader_departure_interval
	leader.reservation_retry_delay = 0.0
	assigned_leaders.append(leader)

	_ensure_idle_vehicle(leader)
	update_route_visual()
	print("[ExpeditionRoute] ", leader_name, " ditugaskan ke ", name)
	return true


func return_all_leaders() -> void:
	var leaders_copy: Array[ExpeditionLeader] = assigned_leaders.duplicate()
	for leader in leaders_copy:
		_return_leader_to_inventory(leader)


func remove_last_segment(segment: RouteSegment) -> bool:
	if segment == null or segments.is_empty():
		return false

	if segments.back() != segment:
		print("[ExpeditionRoute] Undo ditolak: segment bukan yang terakhir")
		return false

	# Jika rute berubah, seluruh leader dikembalikan agar runtime aman.
	return_all_leaders()
	segments.pop_back()
	segment.parent_expedition_route = null

	if segments.is_empty():
		combined_path.curve = Curve2D.new()
	else:
		rebuild_combined_path()
		update_route_visual()

	return true


func _process_waiting_leader(
	leader: ExpeditionLeader,
	delta: float
) -> void:
	if leader.departure_delay > 0.0:
		leader.departure_delay = maxf(leader.departure_delay - delta, 0.0)
		return

	if leader.reservation_retry_delay > 0.0:
		leader.reservation_retry_delay = maxf(
			leader.reservation_retry_delay - delta,
			0.0
		)
		return

	if not _try_start_new_trip(leader):
		leader.reservation_retry_delay = reservation_retry_interval


func _try_start_new_trip(leader: ExpeditionLeader) -> bool:
	if not is_complete():
		return false

	var source := get_route_start_point()
	var destination := get_route_end_point()
	var reserved_variant: Variant = destination.call(
		"reserve_cargo",
		leader.leader_id,
		leader.cargo_capacity
	)
	var reserved_cargo := _variant_to_int_array(reserved_variant)

	if reserved_cargo.is_empty():
		_ensure_idle_vehicle(leader)
		return false

	var provided_variant: Variant = source.call(
		"provide_matching_cargo",
		reserved_cargo,
		leader.cargo_capacity
	)
	var provided_cargo := _variant_to_int_array(provided_variant)

	if provided_cargo.is_empty():
		destination.call("release_cargo_reservation", leader.leader_id)
		return false

	leader.clear_cargo()
	leader.cargo_manifest.append_array(provided_cargo)
	leader.current_segment_index = 0
	leader.is_outbound = true
	leader.status = ExpeditionLeader.Status.TRAVELING

	if not is_instance_valid(leader.current_vehicle):
		_spawn_vehicle_for_current_segment(leader, 0.0)
	else:
		leader.current_vehicle.refuel()
		leader.current_vehicle.rotation = 0.0
		leader.current_vehicle.configure_for_leader(leader)
		leader.current_vehicle.expedition_status = leader.get_status_text()

	print(
		"[ExpeditionRoute] ", leader.leader_name,
		" berangkat membawa ", leader.cargo_manifest,
		" menuju ", destination.name
	)
	return true


func _process_traveling_leader(
	leader: ExpeditionLeader,
	delta: float
) -> void:
	if not is_instance_valid(leader.follower):
		return
	if not is_instance_valid(leader.current_vehicle):
		return

	var follower := leader.follower
	var vehicle := leader.current_vehicle
	var direction := 1.0 if leader.is_outbound else -1.0
	var previous_progress := follower.progress

	follower.progress += (
		vehicle.get_effective_travel_speed()
		* direction
		* delta
	)

	var traveled_distance := absf(follower.progress - previous_progress)
	vehicle.consume_fuel(traveled_distance)
	vehicle.update_fuel_condition(delta)

	if vehicle.is_broken_down:
		return

	if leader.is_outbound and follower.progress_ratio >= 1.0:
		follower.progress_ratio = 1.0
		_finish_outbound_segment(leader)
	elif not leader.is_outbound and follower.progress_ratio <= 0.0:
		follower.progress_ratio = 0.0
		_finish_return_segment(leader)


func _finish_outbound_segment(leader: ExpeditionLeader) -> void:
	if leader.current_segment_index >= segments.size() - 1:
		_deliver_leader_cargo(leader)
		_turn_at_destination(leader)
		return

	leader.current_segment_index += 1
	_spawn_vehicle_for_current_segment(leader, 0.0)


func _finish_return_segment(leader: ExpeditionLeader) -> void:
	if leader.current_segment_index <= 0:
		_turn_at_origin(leader)
		return

	leader.current_segment_index -= 1
	_spawn_vehicle_for_current_segment(leader, 1.0)


func _deliver_leader_cargo(leader: ExpeditionLeader) -> void:
	var destination := get_route_end_point()
	var delivered_manifest: Array[int] = leader.cargo_manifest.duplicate()
	var undelivered_variant: Variant = destination.call(
		"receive_reserved_cargo",
		leader.leader_id,
		delivered_manifest
	)
	var undelivered_cargo := _variant_to_int_array(undelivered_variant)

	leader.clear_cargo()
	leader.cargo_manifest.append_array(undelivered_cargo)

	if is_instance_valid(leader.current_vehicle):
		leader.current_vehicle.configure_for_leader(leader)

	print(
		"[ExpeditionRoute] ", leader.leader_name,
		" tiba di ", destination.name,
		" | Dibawa: ", delivered_manifest,
		" | Ditolak: ", undelivered_cargo
	)


func _turn_at_destination(leader: ExpeditionLeader) -> void:
	if not is_instance_valid(leader.current_vehicle):
		return

	leader.status = ExpeditionLeader.Status.TURNING
	leader.current_vehicle.expedition_status = leader.get_status_text()
	var vehicle := leader.current_vehicle
	var turn_tween := create_tween()
	turn_tween.set_trans(Tween.TRANS_SINE)
	turn_tween.set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(
		vehicle,
		"rotation",
		vehicle.rotation + PI,
		turnaround_duration
	)

	await turn_tween.finished
	if not assigned_leaders.has(leader):
		return
	if not is_instance_valid(leader.current_vehicle):
		return

	leader.is_outbound = false
	leader.status = ExpeditionLeader.Status.TRAVELING
	leader.current_vehicle.expedition_status = leader.get_status_text()


func _turn_at_origin(leader: ExpeditionLeader) -> void:
	if not is_instance_valid(leader.current_vehicle):
		return

	leader.status = ExpeditionLeader.Status.TURNING
	leader.current_vehicle.expedition_status = leader.get_status_text()
	var vehicle := leader.current_vehicle
	var turn_tween := create_tween()
	turn_tween.set_trans(Tween.TRANS_SINE)
	turn_tween.set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(
		vehicle,
		"rotation",
		vehicle.rotation + PI,
		turnaround_duration
	)

	await turn_tween.finished
	if not assigned_leaders.has(leader):
		return
	if not is_instance_valid(leader.current_vehicle):
		return

	leader.clear_cargo()
	leader.current_segment_index = 0
	leader.is_outbound = true
	leader.status = ExpeditionLeader.Status.WAITING
	leader.departure_delay = leader_departure_interval
	leader.reservation_retry_delay = 0.0
	leader.current_vehicle.rotation = 0.0
	leader.current_vehicle.refuel()
	leader.current_vehicle.configure_for_leader(leader)
	leader.current_vehicle.expedition_status = leader.get_status_text()

	print("[ExpeditionRoute] ", leader.leader_name, " kembali ke Supply Hub")


func _ensure_idle_vehicle(leader: ExpeditionLeader) -> void:
	if is_instance_valid(leader.current_vehicle):
		return

	leader.current_segment_index = 0
	leader.is_outbound = true
	leader.status = ExpeditionLeader.Status.WAITING
	_spawn_vehicle_for_current_segment(leader, 0.0)


func _spawn_vehicle_for_current_segment(
	leader: ExpeditionLeader,
	progress_ratio: float
) -> void:
	_cleanup_leader_runtime(leader)

	if leader.current_segment_index < 0:
		return
	if leader.current_segment_index >= segments.size():
		return

	var segment := segments[leader.current_segment_index]
	var vehicle_scene := _get_vehicle_scene(segment.transport_mode)
	if vehicle_scene == null:
		print("[ExpeditionRoute] Scene kendaraan untuk segment tidak tersedia")
		return

	var follower := PathFollow2D.new()
	follower.loop = false
	follower.rotates = true
	segment.add_child(follower)
	follower.progress_ratio = progress_ratio

	var vehicle := vehicle_scene.instantiate() as TransportVehicle
	if vehicle == null:
		follower.queue_free()
		return

	follower.add_child(vehicle)
	vehicle.configure_for_leader(leader)
	vehicle.expedition_status = leader.get_status_text()
	vehicle.rotation = 0.0 if leader.is_outbound else PI
	vehicle.return_requested.connect(
		_on_vehicle_return_requested.bind(leader)
	)
	vehicle.broken_down.connect(
		_on_vehicle_broken_down.bind(leader)
	)
	vehicle.selected.connect(_on_vehicle_selected)

	leader.follower = follower
	leader.current_vehicle = vehicle

	print(
		"[ExpeditionRoute] ", leader.leader_name,
		" menggunakan ",
		RouteSegment.TransportMode.keys()[segment.transport_mode],
		" | Segment ", leader.current_segment_index + 1,
		"/", segments.size()
	)


func _get_vehicle_scene(
	transport_mode: RouteSegment.TransportMode
) -> PackedScene:
	match transport_mode:
		RouteSegment.TransportMode.TRUCK:
			return TRUCK_SCENE
		RouteSegment.TransportMode.SHIP:
			return SHIP_SCENE
		_:
			return null


func _cleanup_leader_runtime(leader: ExpeditionLeader) -> void:
	if is_instance_valid(leader.follower):
		leader.follower.queue_free()
	leader.follower = null
	leader.current_vehicle = null


func _on_vehicle_return_requested(
	_vehicle: TransportVehicle,
	leader: ExpeditionLeader
) -> void:
	_return_leader_to_inventory(leader)


func _return_leader_to_inventory(leader: ExpeditionLeader) -> void:
	if not assigned_leaders.has(leader):
		return

	var destination := get_route_end_point()
	if (
		destination != null
		and destination.has_method("release_cargo_reservation")
	):
		destination.call(
			"release_cargo_reservation",
			leader.leader_id
		)

	assigned_leaders.erase(leader)
	_cleanup_leader_runtime(leader)
	leader.clear_cargo()
	update_route_visual()
	leader_returned.emit(
		leader.leader_id,
		leader.leader_name,
		leader.leader_color,
		leader.icon_texture
	)
	print("[ExpeditionRoute] ", leader.leader_name, " kembali ke roster")


func _on_vehicle_broken_down(
	vehicle: TransportVehicle,
	leader: ExpeditionLeader
) -> void:
	if not assigned_leaders.has(leader):
		return
	if leader.status == ExpeditionLeader.Status.REPAIRING:
		return

	var destination := get_route_end_point()
	if destination != null and destination.has_method(
		"release_cargo_reservation"
	):
		destination.call(
			"release_cargo_reservation",
			leader.leader_id
		)

	var repair_time := vehicle.repair_duration
	leader.status = ExpeditionLeader.Status.REPAIRING
	leader.clear_cargo()
	_cleanup_leader_runtime(leader)
	print(
		"[ExpeditionRoute] ", leader.leader_name,
		" breakdown | Perbaikan ", repair_time, " detik"
	)

	await get_tree().create_timer(repair_time).timeout
	if not assigned_leaders.has(leader):
		return

	leader.current_segment_index = 0
	leader.is_outbound = true
	leader.status = ExpeditionLeader.Status.WAITING
	leader.departure_delay = leader_departure_interval
	leader.reservation_retry_delay = 0.0
	_ensure_idle_vehicle(leader)
	print("[ExpeditionRoute] ", leader.leader_name, " selesai diperbaiki")


func _on_vehicle_selected(vehicle: TransportVehicle) -> void:
	vehicle_selected.emit(vehicle)


func _variant_to_int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is not Array:
		return result

	for item in value:
		result.append(int(item))
	return result
