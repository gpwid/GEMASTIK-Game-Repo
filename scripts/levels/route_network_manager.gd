class_name RouteNetworkManager
extends Node

## Mengelola seluruh jaringan rute pada sebuah level:
## preview, validasi koneksi, ExpeditionRoute, lane paralel,
## Expedition Leader, Undo, dan status keterhubungan jaringan.

signal route_count_changed(route_count: int)
signal can_undo_changed(can_undo: bool)
signal vehicle_selected(vehicle: TransportVehicle)
signal vehicle_info_cleared

const ROUTE_SEGMENT_SCENE: PackedScene = preload(
	"res://scenes/objects/route_segment.tscn"
)
const EXPEDITION_ROUTE_SCENE: PackedScene = preload(
	"res://scenes/objects/expedition_route.tscn"
)

@export_category("Scene References")
@export var route_preview: Line2D
@export var routes_container: Node
@export var expedition_routes_container: Node
@export var supply_hub: Area2D
@export var leader_roster: LeaderRoster

@export_category("Route Rules")
@export_range(1, 10, 1) var max_routes_per_connection: int = 3
@export_range(0.0, 64.0, 1.0) var overlapping_route_spacing: float = 12.0

var is_drawing_route: bool = false
var connection_start_node: Area2D = null
var dragged_leader_token: LeaderToken = null
var highlighted_expedition_route: ExpeditionRoute = null

var expedition_routes: Array[ExpeditionRoute] = []
var created_segments: Array[RouteSegment] = []
var next_route_serial: int = 1


func _ready() -> void:
	if not _validate_scene_references():
		set_process(false)
		return

	_register_route_nodes()
	_register_leader_roster()
	route_preview.visible = false
	route_count_changed.emit(0)
	can_undo_changed.emit(false)


func _process(_delta: float) -> void:
	_update_route_preview()
	_update_leader_drop_highlight()

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	if (
		mouse_event.button_index != MOUSE_BUTTON_RIGHT
		or not mouse_event.pressed
	):
		return

	if is_drawing_route or dragged_leader_token != null:
		return

	var world_mouse_position: Vector2 = (
		route_preview.get_global_mouse_position()
	)

	var selected_route := find_expedition_route_at_position(
		world_mouse_position,
		false
	)

	if selected_route == null:
		return

	delete_expedition_route(selected_route)
	get_viewport().set_input_as_handled()

func _validate_scene_references() -> bool:
	var is_valid := true

	if route_preview == null:
		push_error("RouteNetworkManager: Route Preview belum diisi")
		is_valid = false
	if routes_container == null:
		push_error("RouteNetworkManager: Routes Container belum diisi")
		is_valid = false
	if expedition_routes_container == null:
		push_error(
			"RouteNetworkManager: Expedition Routes Container belum diisi"
		)
		is_valid = false
	if supply_hub == null:
		push_error("RouteNetworkManager: Supply Hub belum diisi")
		is_valid = false
	if leader_roster == null:
		push_error("RouteNetworkManager: Leader Roster belum diisi")
		is_valid = false

	return is_valid


func _register_route_nodes() -> void:
	var supply_callback := Callable(
		self,
		"_on_supply_hub_route_drag_started"
	)
	if (
		supply_hub.has_signal("route_drag_started")
		and not supply_hub.is_connected(
			"route_drag_started",
			supply_callback
		)
	):
		supply_hub.connect("route_drag_started", supply_callback)

	for node in get_tree().get_nodes_in_group("transit_hubs"):
		if node is not TransitHub or not _belongs_to_current_level(node):
			continue

		var hub := node as TransitHub
		if not hub.connection_drag_started.is_connected(
			_on_transit_connection_drag_started
		):
			hub.connection_drag_started.connect(
				_on_transit_connection_drag_started
			)
		if not hub.connection_drag_finished.is_connected(
			_on_transit_connection_drag_finished
		):
			hub.connection_drag_finished.connect(
				_on_transit_connection_drag_finished
			)

	var village_callback := Callable(
		self,
		"_on_village_route_drag_finished"
	)
	for node in get_tree().get_nodes_in_group("villages"):
		if node is not Area2D or not _belongs_to_current_level(node):
			continue
		if (
			node.has_signal("route_drag_finished")
			and not node.is_connected(
				"route_drag_finished",
				village_callback
			)
		):
			node.connect("route_drag_finished", village_callback)


func _register_leader_roster() -> void:
	if not leader_roster.leader_drag_started.is_connected(
		_on_leader_token_drag_started
	):
		leader_roster.leader_drag_started.connect(
			_on_leader_token_drag_started
		)
	if not leader_roster.leader_drag_released.is_connected(
		_on_leader_token_drag_released
	):
		leader_roster.leader_drag_released.connect(
			_on_leader_token_drag_released
		)


func _belongs_to_current_level(node: Node) -> bool:
	var level_root := get_parent()
	return level_root != null and level_root.is_ancestor_of(node)


func _update_route_preview() -> void:
	if not is_drawing_route:
		return

	var local_mouse_position := route_preview.get_local_mouse_position()
	route_preview.set_point_position(1, local_mouse_position)

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cancel_route_drawing()


func begin_connection_drawing(
	start_node: Area2D,
	origin_position: Vector2
) -> void:
	if start_node == null:
		return

	connection_start_node = start_node
	route_preview.clear_points()

	var local_position := route_preview.to_local(origin_position)
	route_preview.add_point(local_position)
	route_preview.add_point(local_position)
	route_preview.visible = true
	is_drawing_route = true

	print("[RouteNetworkManager] Mulai dari ", start_node.name)


func cancel_route_drawing() -> void:
	route_preview.clear_points()
	route_preview.visible = false
	is_drawing_route = false
	connection_start_node = null


func finish_connection(
	end_node: Area2D,
	target_global_position: Vector2
) -> void:
	if not is_drawing_route or connection_start_node == null:
		return
	if end_node == null:
		cancel_route_drawing()
		return
	if connection_start_node == end_node:
		_reject_connection("Node tidak dapat dihubungkan ke dirinya sendiri")
		return

	if (
		connection_start_node != supply_hub
		and not can_continue_route_from(connection_start_node)
	):
		_reject_connection(
			"Rute hanya dapat dilanjutkan dari ujung rute aktif"
		)
		return

	var existing_route_count := get_connection_route_count(
		connection_start_node,
		end_node
	)
	if existing_route_count >= max_routes_per_connection:
		_reject_connection(
			str(
				"Batas koneksi tercapai: ",
				existing_route_count,
				"/",
				max_routes_per_connection
			)
		)
		return

	if end_node.has_method("can_accept_route"):
		var can_accept_variant: Variant = end_node.call(
			"can_accept_route"
		)
		if not bool(can_accept_variant):
			_reject_connection("Tujuan tidak dapat menerima rute")
			return

	var mode := determine_transport_mode(
		connection_start_node,
		end_node
	)
	if mode == RouteSegment.TransportMode.INVALID:
		_reject_connection("Sambungan tidak valid")
		return

	var start_global_position := route_preview.to_global(
		route_preview.get_point_position(0)
	)
	var end_global_position := target_global_position

	if connection_start_node is TransitHub:
		var start_hub := connection_start_node as TransitHub
		start_global_position = (
			start_hub.ship_dock.global_position
			if mode == RouteSegment.TransportMode.SHIP
			else start_hub.truck_stop.global_position
		)

	if end_node is TransitHub:
		var end_hub := end_node as TransitHub
		end_global_position = (
			end_hub.ship_dock.global_position
			if mode == RouteSegment.TransportMode.SHIP
			else end_hub.truck_stop.global_position
		)

	var start_local_position := route_preview.to_local(
		start_global_position
	)
	var end_local_position := route_preview.to_local(
		end_global_position
	)

	route_preview.set_point_position(0, start_local_position)
	route_preview.set_point_position(1, end_local_position)

	var new_segment := (
		ROUTE_SEGMENT_SCENE.instantiate() as RouteSegment
	)
	if new_segment == null:
		_reject_connection("RouteSegment gagal dibuat")
		return

	new_segment.start_point = connection_start_node
	new_segment.end_point = end_node
	new_segment.transport_mode = mode
	new_segment.name = str(
		connection_start_node.name,
		"_To_",
		end_node.name
	)

	var new_curve := Curve2D.new()
	new_curve.add_point(start_local_position)
	new_curve.add_point(end_local_position)
	new_segment.curve = new_curve

	routes_container.add_child(new_segment, true)
	var route_line := new_segment.get_node("RouteLine") as Line2D
	if route_line != null:
		route_line.points = route_preview.points

	if not register_segment(new_segment):
		new_segment.queue_free()
		_reject_connection("Segment tidak dapat dimasukkan ke rute ekspedisi")
		return

	created_segments.append(new_segment)
	refresh_overlapping_route_lanes()
	recalculate_supply_network()
	can_undo_changed.emit(true)

	print(
		"[RouteNetworkManager] Segment dibuat: ",
		new_segment.name,
		" | Moda: ",
		RouteSegment.TransportMode.keys()[mode]
	)
	AudioManager.play_route_connected()
	cancel_route_drawing()


func _reject_connection(reason: String) -> void:
	print("[RouteNetworkManager] ", reason)
	AudioManager.play_error()
	cancel_route_drawing()


func determine_transport_mode(
	start_node: Area2D,
	end_node: Area2D
) -> RouteSegment.TransportMode:
	if (
		not start_node.has_method("supports_truck")
		or not start_node.has_method("supports_ship")
		or not end_node.has_method("supports_truck")
		or not end_node.has_method("supports_ship")
	):
		return RouteSegment.TransportMode.INVALID

	var start_island_variant: Variant = start_node.get("island_id")
	var end_island_variant: Variant = end_node.get("island_id")
	if start_island_variant == null or end_island_variant == null:
		return RouteSegment.TransportMode.INVALID

	var start_island := int(start_island_variant)
	var end_island := int(end_island_variant)

	if start_island == end_island:
		if (
			bool(start_node.call("supports_truck"))
			and bool(end_node.call("supports_truck"))
		):
			return RouteSegment.TransportMode.TRUCK
	else:
		if (
			bool(start_node.call("supports_ship"))
			and bool(end_node.call("supports_ship"))
		):
			return RouteSegment.TransportMode.SHIP

	return RouteSegment.TransportMode.INVALID


func can_continue_route_from(start_node: Area2D) -> bool:
	for index in range(expedition_routes.size() - 1, -1, -1):
		var expedition_route := expedition_routes[index]
		if (
			is_instance_valid(expedition_route)
			and not expedition_route.is_complete()
			and expedition_route.get_route_end_point() == start_node
		):
			return true

	return false


func register_segment(new_segment: RouteSegment) -> bool:
	for index in range(expedition_routes.size() - 1, -1, -1):
		var expedition_route := expedition_routes[index]
		if expedition_route.add_segment(new_segment):
			print(
				"[RouteNetworkManager] ",
				new_segment.name,
				" digabung ke ",
				expedition_route.name
			)
			return true

	if new_segment.start_point != supply_hub:
		print(
			"[RouteNetworkManager] Rute baru wajib berasal dari Supply Hub"
		)
		return false

	var new_route := (
		EXPEDITION_ROUTE_SCENE.instantiate() as ExpeditionRoute
	)
	if new_route == null:
		return false

	new_route.name = str("ExpeditionRoute", next_route_serial)
	next_route_serial += 1
	expedition_routes_container.add_child(new_route)

	new_route.leader_returned.connect(
		_on_expedition_route_leader_returned
	)
	new_route.vehicle_selected.connect(
		_on_expedition_route_vehicle_selected
	)

	if not new_route.add_segment(new_segment):
		new_route.queue_free()
		return false

	expedition_routes.append(new_route)
	route_count_changed.emit(expedition_routes.size())

	print("[RouteNetworkManager] Rute baru dibuat: ", new_route.name)
	return true


func get_connection_route_count(
	first_node: Area2D,
	second_node: Area2D
) -> int:
	var route_count := 0

	for segment in created_segments:
		if not is_instance_valid(segment):
			continue
		if segment.is_queued_for_deletion():
			continue

		var same_direction := (
			segment.start_point == first_node
			and segment.end_point == second_node
		)
		var opposite_direction := (
			segment.start_point == second_node
			and segment.end_point == first_node
		)

		if same_direction or opposite_direction:
			route_count += 1

	return route_count


func refresh_overlapping_route_lanes() -> void:
	var connection_groups: Dictionary = {}

	for segment in created_segments:
		if not is_instance_valid(segment):
			continue

		var key := _get_connection_key(
			segment.start_point,
			segment.end_point
		)
		var grouped_segments: Array = connection_groups.get(key, [])
		grouped_segments.append(segment)
		connection_groups[key] = grouped_segments

	for grouped_variant in connection_groups.values():
		var grouped_segments: Array = grouped_variant
		var center := float(grouped_segments.size() - 1) / 2.0

		for index in range(grouped_segments.size()):
			var segment := grouped_segments[index] as RouteSegment
			if segment == null:
				continue

			var lane_offset := (
				(float(index) - center)
				* overlapping_route_spacing
			)
			if segment.has_method("set_visual_lane_offset"):
				segment.call("set_visual_lane_offset", lane_offset)


func _get_connection_key(
	first_node: Area2D,
	second_node: Area2D
) -> String:
	var first_id := first_node.get_instance_id()
	var second_id := second_node.get_instance_id()
	var smallest_id := mini(first_id, second_id)
	var largest_id := maxi(first_id, second_id)
	return str(smallest_id, ":", largest_id)


func find_expedition_route_at_position(
	world_position: Vector2,
	require_complete: bool = true
) -> ExpeditionRoute:
	var closest_route: ExpeditionRoute = null
	var closest_distance: float = INF

	for index in range(expedition_routes.size() - 1, -1, -1):
		var expedition_route := expedition_routes[index]
		if not is_instance_valid(expedition_route):
			continue
		if require_complete and not expedition_route.is_complete():
			continue

		var distance := expedition_route.get_distance_to_route(
			world_position
		)
		if distance > expedition_route.drop_detection_radius:
			continue
		if distance < closest_distance:
			closest_distance = distance
			closest_route = expedition_route

	return closest_route


func _update_leader_drop_highlight() -> void:
	if dragged_leader_token == null:
		_clear_leader_drop_highlight()
		return

	var world_mouse_position := route_preview.get_global_mouse_position()
	var target_route := find_expedition_route_at_position(
		world_mouse_position
	)

	if target_route == highlighted_expedition_route:
		return

	_clear_leader_drop_highlight()
	highlighted_expedition_route = target_route
	if highlighted_expedition_route != null:
		highlighted_expedition_route.set_drop_highlight(true)


func _clear_leader_drop_highlight() -> void:
	if is_instance_valid(highlighted_expedition_route):
		highlighted_expedition_route.set_drop_highlight(false)
	highlighted_expedition_route = null


func get_last_created_segment() -> RouteSegment:
	while not created_segments.is_empty():
		var last_segment: RouteSegment = created_segments.back()
		if is_instance_valid(last_segment):
			return last_segment
		created_segments.pop_back()

	return null

func delete_expedition_route(
	expedition_route: ExpeditionRoute
) -> bool:
	if not is_instance_valid(expedition_route):
		return false

	if not expedition_routes.has(expedition_route):
		return false

	if not expedition_route.can_be_deleted():
		print(
			"[RouteNetworkManager] ",
			expedition_route.name,
			" tidak dapat dihapus karena masih memiliki leader"
		)
		return false

	if highlighted_expedition_route == expedition_route:
		_clear_leader_drop_highlight()

	var segments_to_delete: Array[RouteSegment] = (
		expedition_route.segments.duplicate()
	)
		
	var deleted_route_name: String = expedition_route.name
	
	for segment in segments_to_delete:
		if not is_instance_valid(segment):
			continue

		created_segments.erase(segment)
		segment.parent_expedition_route = null
		segment.queue_free()

	expedition_route.segments.clear()
	expedition_routes.erase(expedition_route)
	expedition_route.queue_free()

	vehicle_info_cleared.emit()
	refresh_overlapping_route_lanes()
	recalculate_supply_network()

	route_count_changed.emit(expedition_routes.size())
	can_undo_changed.emit(not created_segments.is_empty())

	print(
		"[RouteNetworkManager] Seluruh ekspedisi dihapus: ",
		deleted_route_name
	)

	return true

func undo_last_route() -> void:
	var last_segment := get_last_created_segment()
	if last_segment == null:
		print("[RouteNetworkManager] Tidak ada rute untuk Undo")
		return

	var parent_route: ExpeditionRoute = (
		last_segment.parent_expedition_route
	)
	if not is_instance_valid(parent_route):
		return
	if not parent_route.remove_last_segment(last_segment):
		return

	if highlighted_expedition_route == parent_route:
		_clear_leader_drop_highlight()

	created_segments.pop_back()
	last_segment.queue_free()
	vehicle_info_cleared.emit()

	if parent_route.segments.is_empty():
		expedition_routes.erase(parent_route)
		parent_route.queue_free()

	refresh_overlapping_route_lanes()
	recalculate_supply_network()
	route_count_changed.emit(expedition_routes.size())
	can_undo_changed.emit(not created_segments.is_empty())
	print("[RouteNetworkManager] Undo berhasil")


func recalculate_supply_network() -> void:
	for node in get_tree().get_nodes_in_group("transit_hubs"):
		if node is TransitHub and _belongs_to_current_level(node):
			(node as TransitHub).reset_connection()

	for node in get_tree().get_nodes_in_group("villages"):
		if not _belongs_to_current_level(node):
			continue
		if node.has_method("set_route_disconnected"):
			node.call("set_route_disconnected")

	var reachable_nodes: Dictionary = {supply_hub: true}
	var network_changed := true

	while network_changed:
		network_changed = false

		for expedition_route in expedition_routes:
			for segment in expedition_route.segments:
				if not is_instance_valid(segment):
					continue
				if (
					reachable_nodes.has(segment.start_point)
					and not reachable_nodes.has(segment.end_point)
				):
					reachable_nodes[segment.end_point] = true
					network_changed = true

	for node_variant in reachable_nodes.keys():
		var reachable_node := node_variant as Area2D
		if reachable_node == null:
			continue
		if reachable_node is TransitHub:
			(reachable_node as TransitHub).mark_connected()
		elif reachable_node.has_method("set_route_connected"):
			reachable_node.call("set_route_connected")


func _on_supply_hub_route_drag_started(
	origin_position: Vector2
) -> void:
	begin_connection_drawing(supply_hub, origin_position)


func _on_transit_connection_drag_started(
	start_hub: TransitHub
) -> void:
	if not start_hub.can_start_connection():
		print("[RouteNetworkManager] ", start_hub.name, " belum terhubung")
		return
	if not can_continue_route_from(start_hub):
		print(
			"[RouteNetworkManager] ",
			start_hub.name,
			" bukan ujung rute aktif"
		)
		return

	begin_connection_drawing(start_hub, start_hub.global_position)


func _on_transit_connection_drag_finished(
	end_hub: TransitHub
) -> void:
	finish_connection(end_hub, end_hub.global_position)


func _on_village_route_drag_finished(
	target_position: Vector2,
	target_village: Area2D
) -> void:
	finish_connection(target_village, target_position)


func _on_leader_token_drag_started(token: LeaderToken) -> void:
	dragged_leader_token = token
	print("[RouteNetworkManager] Menyeret token ", token.leader_name)


func _on_leader_token_drag_released(token: LeaderToken) -> void:
	if dragged_leader_token != token:
		return

	var target_route: ExpeditionRoute = highlighted_expedition_route

	if target_route == null:
		target_route = find_expedition_route_at_position(
			route_preview.get_global_mouse_position()
		)

	_clear_leader_drop_highlight()

	if target_route == null:
		print(
			"[RouteNetworkManager] Drop gagal: ",
			"tidak ada rute lengkap"
		)

		AudioManager.play_error()

		token.return_to_roster()
		dragged_leader_token = null
		return

	var assigned: bool = target_route.try_assign_leader(
		token.leader_id,
		token.leader_name,
		token.leader_color,
		token.icon_texture
	)

	if assigned:
		leader_roster.consume_leader_token(token)
		AudioManager.play_random_leader_voice()
	else:
		token.return_to_roster()
		AudioManager.play_error()

	dragged_leader_token = null


func _on_expedition_route_leader_returned(
	leader_id: String,
	leader_name: String,
	leader_color: Color,
	icon_texture: Texture2D
) -> void:
	leader_roster.restore_leader(
		leader_id,
		leader_name,
		leader_color,
		icon_texture
	)
	vehicle_info_cleared.emit()


func _on_expedition_route_vehicle_selected(
	vehicle: TransportVehicle
) -> void:
	if is_instance_valid(vehicle):
		vehicle_selected.emit(vehicle)
