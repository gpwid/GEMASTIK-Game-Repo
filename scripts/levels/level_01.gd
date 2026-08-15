extends Node2D

const ROUTE_SEGMENT_SCENE: PackedScene = preload("res://scenes/objects/route_segment.tscn")
const TRANSPORT_ROUTE_SCENE: PackedScene = preload("res://scenes/objects/transport_route.tscn")
const LEVEL_SELECTION_PATH: String = "res://scenes/ui/level_selection.tscn"

var is_drawing_route: bool = false
var is_game_over: bool = false
var is_victory: bool = false
var route_segment_count: int = 0
var total_logistics_delivered: int = 0
var villages: Array[Area2D] = []
var transport_routes: Array[TransportRoute] = []
var created_segments: Array[RouteSegment] = []
var connection_start_node: Area2D = null
var dragged_vehicle_token: VehicleToken = null

@onready var route_preview: Line2D = $Routes/RoutePreview
@onready var game_over_screen: ColorRect = $UI/GameOverScreen
@onready var failed_village_label: Label = $UI/GameOverScreen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FailedVillageLabel
@onready var sustain_timer: Timer = $SustainTimer
@onready var victory_screen: ColorRect = $UI/VictoryScreen
@onready var supply_hub: Area2D = $MapObjects/SupplyHub
@onready var vehicle_inventory: VehicleInventory = $UI/VehicleInventory
@onready var game_hud: GameHUD = %GameHud

func _ready() -> void:
	for child in $MapObjects.get_children():
		if child.name.begins_with("Village"):
			villages.append(child)
			if child.has_signal("cargo_received"):
				child.connect("cargo_received", _on_village_cargo_received)
	
	game_hud.undo_route_requested.connect(_on_game_hud_undo_route_requested)
	vehicle_inventory.token_drag_started.connect(_on_vehicle_token_drag_started)
	vehicle_inventory.token_drag_released.connect(_on_vehicle_token_drag_released)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if is_drawing_route:
		var local_mouse_pos = route_preview.get_local_mouse_position()
		route_preview.set_point_position(1, local_mouse_pos)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			cancel_route_drawing()
	update_sustain_timer()	

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		game_hud.hide_vehicle_info()

	elif event.is_action_pressed("ui_cancel"):
		game_hud.hide_vehicle_info()

func begin_connection_drawing(start_node: Area2D, origin_position: Vector2) -> void:
	print("[begin_connection_drawing:level_01.gd] Asal: ", start_node.name, "Posisi: ", origin_position)
	connection_start_node = start_node
	route_preview.clear_points()
	var local_pos = route_preview.to_local(origin_position)
	route_preview.add_point(local_pos)
	route_preview.add_point(local_pos)
	route_preview.visible = true
	is_drawing_route = true

func cancel_route_drawing() -> void:
	route_preview.clear_points()
	route_preview.visible = false
	is_drawing_route = false	
	connection_start_node = null

func finish_connection(end_node: Area2D, target_global_position: Vector2) -> void:
	if not is_drawing_route:
		return
	if connection_start_node == null:
		return
	
	if connection_start_node == end_node:
		print("Tidak bisa menghubungkan node ke dirinya sendiri")	
		cancel_route_drawing()
		return
	
	if end_node.has_method("can_accept_route"):
		var can_accept = end_node.call("can_accept_route")
		
		if not can_accept:
			print("Tujuan udah memiliki rute")
			cancel_route_drawing()
			return

	var mode: RouteSegment.TransportMode = determine_transport_mode(connection_start_node, end_node)
	
	if mode == RouteSegment.TransportMode.INVALID:
		print("Sambungan tidak valid")
		cancel_route_drawing()
		return
	
	var start_global_position: Vector2 = route_preview.to_global(route_preview.get_point_position(0))
	var end_global_position: Vector2 = target_global_position
	
	if connection_start_node is TransitHub:
		var start_hub: TransitHub = connection_start_node as TransitHub
		if mode == RouteSegment.TransportMode.SHIP:
			start_global_position = start_hub.ship_dock.global_position
		else:
			start_global_position = start_hub.truck_stop.global_position	
			
	if end_node is TransitHub:
		var end_hub: TransitHub = end_node as TransitHub
		if mode == RouteSegment.TransportMode.SHIP:
			end_global_position = end_hub.ship_dock.global_position
		else:
			end_global_position = end_hub.truck_stop.global_position
			
	var start_local_position: Vector2 = route_preview.to_local(start_global_position)
	var end_local_position: Vector2 = route_preview.to_local(end_global_position)
	
	route_preview.set_point_position(0, start_local_position)
	route_preview.set_point_position(1, end_local_position)
	
	print("[finish_connection:level_01.gd] Asal: ", connection_start_node.name,  " Tujuan : ", end_node.name, " Mode Transportasi: ", RouteSegment.TransportMode.keys()[mode])
	
	var start_pos: Vector2 = route_preview.get_point_position(0)
	var end_pos: Vector2 = route_preview.get_point_position(1)
	
	var new_segment: RouteSegment = ROUTE_SEGMENT_SCENE.instantiate() as RouteSegment
	new_segment.start_point = connection_start_node
	new_segment.end_point = end_node
	new_segment.name = str(connection_start_node.name + "_To_" + end_node.name)
	new_segment.transport_mode = mode
	var new_curve: Curve2D = Curve2D.new()
	new_curve.add_point(start_pos)
	new_curve.add_point(end_pos)
	new_segment.curve = new_curve
	
	var route_line: Line2D = new_segment.get_node("RouteLine") as Line2D
	route_line.points = route_preview.points
	$Routes.add_child(new_segment, true)
	register_segment(new_segment)
	created_segments.append(new_segment)
	game_hud.set_can_undo(true)
	route_segment_count += 1
	game_hud.set_route_count(route_segment_count)
	if end_node is TransitHub:
		var connected_hub: TransitHub = end_node as TransitHub
		connected_hub.mark_connected()
	elif end_node.has_method("set_route_connected"):
		end_node.call("set_route_connected")
	cancel_route_drawing()

func determine_transport_mode(start_node: Area2D, end_node: Area2D) -> RouteSegment.TransportMode:
	var island_id_start_node: int = start_node.get("island_id")
	var island_id_end_node: int = end_node.get("island_id")
	
	if island_id_start_node == island_id_end_node:
		if start_node.call("supports_truck") and end_node.call("supports_truck"):
			return RouteSegment.TransportMode.TRUCK
	elif island_id_start_node != island_id_end_node:
		if start_node.call("supports_ship") and end_node.call("supports_ship"):
			return RouteSegment.TransportMode.SHIP
	
	return RouteSegment.TransportMode.INVALID	
	
func register_segment(new_segment: RouteSegment) -> void:
	for transport_route in transport_routes:
		if transport_route.add_segment(new_segment):
			new_segment.parent_transport_route = transport_route
			print("[register_segment:level_01.gd] ", new_segment.name, "berhasil digabung dgn", transport_route.name, "Total Segmen: ", transport_route.segments.size())
			return
	
	var new_transport_route: TransportRoute = TRANSPORT_ROUTE_SCENE.instantiate() as TransportRoute
	new_transport_route.name = str("TransportRoute", transport_routes.size() + 1)
	
	$TransportRoutes.add_child(new_transport_route)
	new_transport_route.vehicle_returned.connect(_on_transport_route_vehicle_returned)
	new_transport_route.vehicle_selected.connect(_on_transport_route_vehicle_selected)

	transport_routes.append(new_transport_route)
	new_transport_route.add_segment(new_segment)
	new_segment.parent_transport_route = new_transport_route
	print("[register_segment:level_01.gd] Route baru:", new_transport_route.name, " Mode: ", RouteSegment.TransportMode.keys()[new_transport_route.transport_mode], " Segment: ", new_segment.name)

func find_transport_route_at_position(world_position: Vector2, vehicle_mode: RouteSegment.TransportMode) -> TransportRoute:
	var closest_route: TransportRoute = null
	var closest_distance: float = INF

	for transport_route in transport_routes:
		if transport_route.transport_mode != vehicle_mode:
			continue

		var distance: float = transport_route.get_distance_to_route(world_position)

		if distance > transport_route.drop_detection_radius:
			continue

		if distance < closest_distance:
			closest_distance = distance
			closest_route = transport_route

	return closest_route

func are_all_villages_sustaining() -> bool:
	if villages.is_empty():
		return false

	for village in villages:
		if not village.has_method("is_self_sustaining"):
			return false

		if not village.call("is_self_sustaining"):
			return false

	return true

func update_sustain_timer() -> void:
	if is_game_over or is_victory:
		return
		
	var all_sustaining: bool = are_all_villages_sustaining()
	if all_sustaining:
		if sustain_timer.is_stopped():
			sustain_timer.start()
			print("[on_sustain_timer_timeout:level_01.gd] Sustain countdown dimulai")
	else:
		if not sustain_timer.is_stopped():
			sustain_timer.stop()
			print("[on_sustain_timer_timeout:level_01.gd] Sustain countdown reset")
			
func trigger_game_over(failed_village: Area2D) -> void:
	if is_game_over or is_victory:
		return
	is_game_over = true
	failed_village_label.text = str(failed_village.name, " gagal menerima bantuan.")
	game_over_screen.visible = true
	get_tree().paused = true

func get_last_created_segment() -> RouteSegment:
	while not created_segments.is_empty():
		var last_segment: RouteSegment = created_segments.back()
		if is_instance_valid(last_segment):
			return last_segment
		created_segments.pop_back()
	return null

func recalculate_supply_network() -> void:
	for node in get_tree().get_nodes_in_group("transit_hubs"):
		if node is TransitHub:
			var transit_hub: TransitHub = node as TransitHub
			transit_hub.reset_connection()

	for village in villages:
		if village.has_method("set_route_disconnected"):
			village.call("set_route_disconnected")

	var reachable_nodes: Dictionary = {supply_hub: true}
	var network_changed: bool = true

	while network_changed:
		network_changed = false

		for transport_route in transport_routes:
			if not is_instance_valid(transport_route):
				continue

			for segment in transport_route.segments:
				if not is_instance_valid(segment):
					continue

				var start_is_reachable: bool = (reachable_nodes.has(segment.start_point))
				var end_is_reachable: bool = (reachable_nodes.has(segment.end_point))
				if start_is_reachable and not end_is_reachable:
					reachable_nodes[segment.end_point] = true
					network_changed = true

	for node_variant in reachable_nodes.keys():
		var reachable_node: Area2D = node_variant as Area2D
		if reachable_node == null:
			continue
		if reachable_node is TransitHub:
			var reachable_hub: TransitHub = (reachable_node as TransitHub)
			reachable_hub.mark_connected()
		elif reachable_node.has_method("set_route_connected"):
			reachable_node.call("set_route_connected")

func undo_last_route() -> void:
	var last_segment: RouteSegment = get_last_created_segment()

	if last_segment == null:
		print("[undo_last_route:level_01.gd] Tidak ada rute")
		return

	var parent_route: TransportRoute = (last_segment.parent_transport_route)

	if not is_instance_valid(parent_route):
		print("[undo_last_route:level_01.gd] ", "TransportRoute tidak valid")
		return

	var was_removed: bool = parent_route.remove_last_segment(last_segment)

	if not was_removed:
		print("[undo_last_route:level_01.gd] ", "Undo ditolak. Kembalikan kendaraan terlebih dahulu")
		return

	created_segments.pop_back()
	game_hud.set_can_undo(not created_segments.is_empty())
	game_hud.hide_vehicle_info()
	route_segment_count = maxi(route_segment_count - 1, 0)
	game_hud.set_route_count(route_segment_count)
	last_segment.queue_free()

	if parent_route.segments.is_empty():
		transport_routes.erase(parent_route)
		parent_route.queue_free()
	recalculate_supply_network()

	print("[undo_last_route:level_01.gd] ", "Rute berhasil dihapus | Tersisa: ", route_segment_count)

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
	
func _on_replay_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _on_sustain_timer_timeout() -> void:
	if is_game_over or is_victory:
		return
	is_victory = true
	victory_screen.visible = true
	print("[on_sustain_timer_timeout:level_01.gd] LEVEL COMPLETED")
	get_tree().paused = true

func _on_supply_hub_route_drag_started(origin_position: Vector2) -> void:
	begin_connection_drawing(supply_hub, origin_position)

func _on_village_a_route_drag_finished(target_position: Vector2, target_village: Area2D) -> void:
	finish_connection(target_village, target_position)

func _on_village_b_route_drag_finished(target_position: Vector2, target_village: Area2D) -> void:
	finish_connection(target_village, target_position)

func _on_village_a_village_failed(failed_village: Area2D) -> void:
	trigger_game_over(failed_village)

func _on_village_b_village_failed(failed_village: Area2D) -> void:
	trigger_game_over(failed_village)	

func _on_transit_connection_drag_started(start_hub: TransitHub) -> void:
	if not start_hub.can_start_connection():
		print("[_on_transit_connection_drag_started:level_01.gd] ", start_hub.name, " belum terhubung ke jaringan suplai")
		return
	
	begin_connection_drawing(start_hub, start_hub.global_position)
	print("[_on_transit_connection_drag_started:level_01.gd] Hubungan dimulai dari: ", start_hub.name)
	
func _on_transit_connection_drag_finished(end_hub: TransitHub) -> void:
	finish_connection(end_hub, end_hub.global_position)

func _on_vehicle_token_drag_started(token: VehicleToken) -> void:
	dragged_vehicle_token = token
	print("[vehicle_drag_started:level_01.gd] Mode: ", RouteSegment.TransportMode.keys()[token.transport_mode])

func _on_vehicle_token_drag_released(token: VehicleToken) -> void:
	if dragged_vehicle_token != token:
		return

	var world_drop_position: Vector2 = get_global_mouse_position()
	var target_route: TransportRoute = find_transport_route_at_position(world_drop_position, token.transport_mode)

	if target_route == null:
		print("[vehicle_drop:level_01.gd] Drop gagal | Mode: ", RouteSegment.TransportMode.keys()[token.transport_mode])
		token.return_to_inventory()
		dragged_vehicle_token = null
		return

	print("[vehicle_drop:level_01.gd] Rute ditemukan: ", target_route.name, " | Mode: ", RouteSegment.TransportMode.keys()[target_route.transport_mode])

	var vehicle_installed: bool = target_route.try_install_vehicle()	
	if vehicle_installed:
		print("[vehicle_drop:level_01.gd] Token digunakan pada ", target_route.name)
		vehicle_inventory.consume_token(token)
	else:
		print("[vehicle_drop:level_01.gd] Kendaraan gagal dipasang pada ", target_route.name)
		token.return_to_inventory()

	dragged_vehicle_token = null

func _on_village_cargo_received(received_amount: int) -> void:
	total_logistics_delivered += received_amount
	game_hud.set_logistics_count(total_logistics_delivered)
	
func _on_level_selection_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(LEVEL_SELECTION_PATH)
	
func _on_transport_route_vehicle_returned(transport_mode: RouteSegment.TransportMode) -> void:
	var was_restored: bool = vehicle_inventory.restore_vehicle(transport_mode)
	if not was_restored:
		print("Kendaraan gagal dikembalikan ke inventory: ", RouteSegment.TransportMode.keys()[transport_mode])
	
func _on_transport_route_vehicle_selected(vehicle: TransportVehicle) -> void:
	if not is_instance_valid(vehicle):
		return

	game_hud.show_vehicle_info(vehicle)
	print("[_on_transport_route_vehicle_selected:level_01.gd] ", "Kendaraan dipilih: ", vehicle.vehicle_name)
	
func _on_game_hud_undo_route_requested() -> void:
	undo_last_route()
