class_name TransportRoute	
extends Node

signal vehicle_returned(transport_mode: RouteSegment.TransportMode)
signal vehicle_selected(vehicle: TransportVehicle)

const TRUCK_SCENE: PackedScene = preload("res://scenes/objects/truck.tscn")
const SHIP_SCENE: PackedScene = preload("res://scenes/objects/boat.tscn")

var segments: Array[RouteSegment] = []
var transport_mode: RouteSegment.TransportMode = RouteSegment.TransportMode.INVALID
var vehicle_followers: Array[PathFollow2D] = []
var vehicles_under_repair: int = 0

@export var vehicle_departure_interval: float = 1.0
@export var turnaround_duration: float = 0.4
@export var drop_detection_radius: float = 48.0

@onready var combined_path: Path2D = $CombinedPath

func _process(delta: float) -> void:
	for follower in vehicle_followers:
		if not is_instance_valid(follower):
			continue
		if follower.get_child_count() == 0:
			continue

		var vehicle: TransportVehicle = follower.get_child(0) as TransportVehicle
		if vehicle == null:
			continue
		if vehicle.departure_delay > 0.0:
			vehicle.departure_delay = maxf(vehicle.departure_delay - delta,0.0)
			continue
		if vehicle.is_turning:
			continue

		var previous_progress: float = follower.progress
		var effective_speed: float = vehicle.get_effective_travel_speed()

		follower.progress += (effective_speed * vehicle.travel_direction * delta)

		var traveled_distance: float = absf(follower.progress - previous_progress)

		vehicle.consume_fuel(traveled_distance)
		vehicle.update_fuel_condition(delta)
		if vehicle.is_broken_down:
			continue
			
		if vehicle.travel_direction > 0.0 and follower.progress_ratio >= 1.0:
			follower.progress_ratio = 1.0
			handle_vehicle_arrival(vehicle, true)
			start_turnaround(vehicle)
		elif vehicle.travel_direction < 0.0 and follower.progress_ratio <= 0.0:
			follower.progress_ratio = 0.0
			handle_vehicle_arrival(vehicle, false)
			start_turnaround(vehicle)
	
func add_segment(segment: RouteSegment) -> bool:
	if segment == null:
		return false
	if segments.is_empty():
		transport_mode = segment.transport_mode
		segments.append(segment)
		rebuild_combined_path()
		return true
	if segment.transport_mode != transport_mode:
		return false
	
	var last_segment: RouteSegment = segments.back()
	if last_segment.end_point != segment.start_point:
		return false
	
	var junction: Area2D = last_segment.end_point
	if transport_mode != RouteSegment.TransportMode.TRUCK:
		return false
	if junction is not TransitHub:
		return false
	var junction_hub: TransitHub = junction as TransitHub	
	if junction_hub.is_port:
		return false	
		
	segments.append(segment)
	rebuild_combined_path()
	return true
	
func rebuild_combined_path() -> void:
	var new_combined_curve: Curve2D = Curve2D.new()
	for segment in segments:
		var baked_points: PackedVector2Array = segment.curve.get_baked_points()
		for point in baked_points:
			var global_point: Vector2 = segment.to_global(point)
			var combined_local_point: Vector2 = combined_path.to_local(global_point)
			
			if new_combined_curve.point_count > 0:
				var last_index: int = new_combined_curve.point_count - 1
				var last_point: Vector2 = new_combined_curve.get_point_position(last_index)
				
				if last_point.is_equal_approx(combined_local_point):
					continue
			
			new_combined_curve.add_point(combined_local_point)
	
	combined_path.curve = new_combined_curve
	print("[rebuild_combined_path:transport_route.gd]", name, " | Segments: ", segments.size(), " | Points: ", new_combined_curve.point_count, " | Length: ", new_combined_curve.get_baked_length())
	
func get_route_start_point() -> Area2D:
	if segments.is_empty():
		return null

	return segments.front().start_point

func get_route_end_point() -> Area2D:
	if segments.is_empty():
		return null

	return segments.back().end_point

func get_distance_to_route(world_position: Vector2) -> float:
	if combined_path.curve == null:
		return INF

	if combined_path.curve.point_count < 2:
		return INF

	var local_position: Vector2 = combined_path.to_local(world_position)
	var closest_position: Vector2 = combined_path.curve.get_closest_point(local_position)

	return local_position.distance_to(closest_position)

func try_install_vehicle() -> bool:
	var vehicle_scene: PackedScene

	if transport_mode == RouteSegment.TransportMode.TRUCK:
		vehicle_scene = TRUCK_SCENE
	elif transport_mode == RouteSegment.TransportMode.SHIP:
		vehicle_scene = SHIP_SCENE
	else:
		print("[try_install_vehicle:transport_route.gd] Mode rute invalid")
		return false

	if combined_path.curve == null or combined_path.curve.point_count < 2:
		print("[try_install_vehicle:transport_route.gd] Rute belum memiliki kurva valid")
		return false

	var new_follower: PathFollow2D = PathFollow2D.new()
	new_follower.loop = false
	new_follower.rotates = true

	combined_path.add_child(new_follower)
	new_follower.progress_ratio = 0.0

	var vehicle: TransportVehicle = vehicle_scene.instantiate() as TransportVehicle

	if vehicle == null:
		new_follower.queue_free()
		print("[try_install_vehicle:transport_route.gd] Scene kendaraan gagal dibuat")
		return false

	new_follower.add_child(vehicle)
	vehicle.return_requested.connect(_on_vehicle_return_requested.bind(new_follower))
	vehicle.broken_down.connect(_on_vehicle_broken_down.bind(new_follower))
	vehicle.selected.connect(_on_vehicle_selected)
	vehicle.departure_delay = vehicle_followers.size() * vehicle_departure_interval
	vehicle_followers.append(new_follower)

	handle_vehicle_arrival(vehicle, false)

	print("[try_install_vehicle:transport_route.gd] Kendaraan dipasang. Route: ", name, " | Mode: ", RouteSegment.TransportMode.keys()[transport_mode])

	return true

func start_turnaround(vehicle: TransportVehicle) -> void:
	if vehicle.is_turning:
		return
	vehicle.is_turning = true
	var turn_tween: Tween = create_tween()
	turn_tween.set_trans(Tween.TRANS_SINE)
	turn_tween.set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(vehicle, "rotation", vehicle.rotation + PI, turnaround_duration)

	await turn_tween.finished
	if not is_instance_valid(vehicle):
		return
	vehicle.travel_direction *= -1.0
	vehicle.is_turning = false

func handle_vehicle_arrival(vehicle: TransportVehicle, arrived_at_end: bool) -> void:
	var arrival_point: Area2D
	
	if arrived_at_end:
		arrival_point = get_route_end_point()
	else:
		arrival_point = get_route_start_point()

	if arrival_point == null:
		return
	
	if arrival_point.has_method("refuels_vehicle") and arrival_point.call("refuels_vehicle"):
		vehicle.refuel()

	print("[handle_vehicle_arrival:transport_route.gd] ", vehicle.driver_name, " tiba di ", arrival_point.name, " Manifest: ", vehicle.cargo_manifest)
	
	if arrival_point is TransitHub:
		var arrival_hub: TransitHub = arrival_point as TransitHub
		if arrival_hub.transfers_cargo():
			if arrived_at_end:
				var unloaded_cargo: Array[int] = vehicle.unload_all_cargo()
				var remaining_cargo: Array[int] = arrival_hub.store_cargo(unloaded_cargo)
				var stored_amount: int = unloaded_cargo.size() - remaining_cargo.size()
				vehicle.load_cargo_batch(remaining_cargo)
				print("[handle_vehicle_arrival:transport_route.gd] Route: ", name, " Hub: ", arrival_hub.name, " Dibongkar: ", unloaded_cargo, " Tersimpan: ", stored_amount, " Gudang: ", arrival_hub.cargo_storage, " Sisa kendaraan: ", vehicle.cargo_manifest)
			else:
				var returned_cargo: Array[int] = vehicle.unload_all_cargo()
				var route_destination: Area2D = get_route_end_point()
				var empty_slots: int = vehicle.get_remaining_capacity()
				var taken_cargo: Array[int] = []
				var requested_types: Array[int] = []
				
				if route_destination.has_method("get_requested_cargo"):
					requested_types = route_destination.call("get_requested_cargo")
					taken_cargo = arrival_hub.take_matching_cargo(requested_types, empty_slots)
				else:
					taken_cargo = arrival_hub.take_cargo(empty_slots)
				
				var cargo_not_stored: Array[int] = arrival_hub.store_cargo(returned_cargo)
				vehicle.load_cargo_batch(taken_cargo)
				
				if not cargo_not_stored.is_empty():
					vehicle.load_cargo_batch(cargo_not_stored)
					
				print("[handle_vehicle_arrival:transport_route.gd] Route: ", name, " Hub: ", arrival_hub.name, " Cargo dikembalikan: ", returned_cargo, " Kebutuhan tujuan: ", requested_types, " Cargo dipilih: ", taken_cargo, " Gagal disimpan: ", cargo_not_stored, " Gudang akhir: ", arrival_hub.cargo_storage, " Manifest: ", vehicle.cargo_manifest)
	
	if arrived_at_end and arrival_point.has_method("receive_cargo_batch"):
		var unloaded_cargo: Array[int] = vehicle.unload_all_cargo()
		var undelivered_cargo: Array[int] = arrival_point.call("receive_cargo_batch", unloaded_cargo)
		vehicle.load_cargo_batch(undelivered_cargo)
		var received_amt: int = unloaded_cargo.size() - undelivered_cargo.size()
		print("[handle_vehicle_arrival:transport_route.gd] Route: ", name, " Village: ", arrival_point.name, " Dikirim: ", unloaded_cargo, " Diterima: ", received_amt, " Ditolak: ", undelivered_cargo, " Manifest pulang: ", vehicle.cargo_manifest)
		
	if arrival_point.has_method("provide_cargo"):
		var requested_amount: int = vehicle.get_remaining_capacity()
		if requested_amount <= 0:
			print("[handle_vehicle_arrival:transport_route.gd] Kendaraan dah penuh, Route: ", name, " Manifest: ", vehicle.cargo_manifest)
			return
		var provided_cargo: Array[int] = arrival_point.call("provide_cargo", requested_amount)
		var remaining_cargo: Array[int] = vehicle.load_cargo_batch(provided_cargo)
		print("[handle_vehicle_arrival:transport_route.gd] Route: ", name, " Source: ", arrival_point.name, " Dimuat: ", provided_cargo.size() - remaining_cargo.size(), " Manifest: ", vehicle.cargo_manifest)

func has_active_vehicles() -> bool:
	if vehicles_under_repair > 0:
		return true

	for follower in vehicle_followers:
		if is_instance_valid(follower):
			return true
	return false
	
func remove_last_segment(segment: RouteSegment) -> bool:
	if segment == null:
		return false
	if segments.is_empty():
		return false
	if has_active_vehicles():
		print("[remove_last_segment:transport_route.gd] ", "Route masih memiliki kendaraan: ", name)
		return false

	var current_last_segment: RouteSegment = segments.back()
	if current_last_segment != segment:
		print("[remove_last_segment:transport_route.gd] ", "Segment bukan bagian terakhir route: ", segment.name)
		return false

	segments.pop_back()
	segment.parent_transport_route = null
	if segments.is_empty():
		transport_mode = RouteSegment.TransportMode.INVALID
		combined_path.curve = Curve2D.new()
	else:
		rebuild_combined_path()

	print("[remove_last_segment:transport_route.gd] ", "Segment dilepas: ", segment.name, " | Segment tersisa: ", segments.size())
	return true

func _on_vehicle_return_requested(vehicle: TransportVehicle, follower: PathFollow2D) -> void:
	if not is_instance_valid(vehicle):
		return
	if not is_instance_valid(follower):
		return
	if vehicle.get_parent() != follower:
		return

	vehicle_followers.erase(follower)
	vehicle_returned.emit(transport_mode)
	follower.queue_free()
	print("[_on_vehicle_return_requested:transport_route.gd] Kendaraan dikembalikan | Route: ", name, " | Mode: ", RouteSegment.TransportMode.keys()[transport_mode], " | Kendaraan tersisa: ", vehicle_followers.size())

func _on_vehicle_broken_down(vehicle: TransportVehicle, follower: PathFollow2D) -> void:
	if not is_instance_valid(vehicle):
		return
	if not is_instance_valid(follower):
		return

	var repair_time: float = vehicle.repair_duration
	var broken_vehicle_name: String = vehicle.vehicle_name
	var original_rotation: float = vehicle.rotation
	var faded_color: Color = vehicle.modulate
	faded_color.a = 0.0
	
	vehicles_under_repair += 1
	vehicle_followers.erase(follower)
	print("[_on_vehicle_broken_down:transport_route.gd] ", broken_vehicle_name, " rusak | Perbaikan: ", repair_time, " detik")

	var breakdown_tween: Tween = create_tween()
	breakdown_tween.set_trans(Tween.TRANS_SINE)
	breakdown_tween.set_ease(Tween.EASE_IN_OUT)

	breakdown_tween.tween_property(vehicle, "rotation", original_rotation - 0.12, 0.08)
	breakdown_tween.tween_property(vehicle, "rotation", original_rotation + 0.12, 0.08)
	breakdown_tween.tween_property(vehicle, "rotation", original_rotation - 0.08, 0.08)
	breakdown_tween.tween_property(vehicle, "rotation", original_rotation, 0.08)
	breakdown_tween.tween_property(vehicle, "modulate", faded_color, 0.35)

	await breakdown_tween.finished
	if not is_instance_valid(follower):
		vehicles_under_repair = maxi(vehicles_under_repair - 1, 0)
		return
	follower.queue_free()
	await get_tree().create_timer(repair_time).timeout
	vehicle_returned.emit(transport_mode)
	print("[_on_vehicle_broken_down:transport_route.gd] ", broken_vehicle_name, " selesai diperbaiki")
	
func _on_vehicle_selected(vehicle: TransportVehicle) -> void:
	vehicle_selected.emit(vehicle)
	print("[_on_vehicle_selected:transport_route.gd] ", "Route: ", name, " | Kendaraan: ", vehicle.vehicle_name)
