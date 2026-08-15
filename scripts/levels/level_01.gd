extends Node2D

## Pengendali Level 1: menggambar rute linear multimoda, memasang
## Expedition Leader, menghitung kemenangan, dan mengelola Undo.

const ROUTE_SEGMENT_SCENE: PackedScene = preload(
	"res://scenes/objects/route_segment.tscn"
)
const EXPEDITION_ROUTE_SCEBE: PackedScene = preload(
	"res://scenes/objects/expedition_route.tscn"
)
const LEVEL_SELECTION_PATH: String = (
	"res://scenes/ui/level_selection.tscn"
)

@export var route_palette: Array[Color] = [
	Color("#57C7FF"),
	Color("#FFB84D"),
	Color("#D786FF"),
	Color("#66D68B"),
	Color("#FF6F91"),
]

var is_drawing_route: bool = false
var is_game_over: bool = false
var is_victory: bool = false
var total_logistics_delivered: int = 0
var villages: Array[Area2D] = []
var expedition_routes: Array[ExpeditionRoute] = []
var created_segments: Array[RouteSegment] = []
var connection_start_node: Area2D = null
var dragged_leader_token: LeaderToken = null

@onready var route_preview: Line2D = $Routes/RoutePreview
@onready var game_over_screen: ColorRect = $UI/GameOverScreen
@onready var failed_village_label: Label = get_node(
	"UI/GameOverScreen/CenterContainer/PanelContainer/"
	+ "MarginContainer/VBoxContainer/FailedVillageLabel"
) as Label
@onready var sustain_timer: Timer = $SustainTimer
@onready var victory_screen: ColorRect = $UI/VictoryScreen
@onready var supply_hub: Area2D = $MapObjects/SupplyHub
@onready var leader_roster: LeaderRoster = $UI/LeaderRoster
@onready var game_hud: GameHUD = %GameHud


func _ready() -> void:
	for child in $MapObjects.get_children():
		if child.name.begins_with("Village") and child is Area2D:
			var village := child as Area2D
			villages.append(village)
			if village.has_signal("cargo_received"):
				village.connect(
					"cargo_received",
					_on_village_cargo_received
				)

	game_hud.undo_route_requested.connect(
		_on_game_hud_undo_route_requested
	)
	leader_roster.leader_drag_started.connect(
		_on_leader_token_drag_started
	)
	leader_roster.leader_drag_released.connect(
		_on_leader_token_drag_released
	)
	game_hud.set_route_count(0)


func _process(_delta: float) -> void:
	if is_drawing_route:
		var local_mouse_position := route_preview.get_local_mouse_position()
		route_preview.set_point_position(1, local_mouse_position)

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			cancel_route_drawing()

	update_sustain_timer()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		game_hud.hide_vehicle_info()
	elif event.is_action_pressed("ui_cancel"):
		game_hud.hide_vehicle_info()
		cancel_route_drawing()


func begin_connection_drawing(
	start_node: Area2D,
	origin_position: Vector2
) -> void:
	connection_start_node = start_node
	route_preview.clear_points()
	var local_position := route_preview.to_local(origin_position)
	route_preview.add_point(local_position)
	route_preview.add_point(local_position)
	route_preview.visible = true
	is_drawing_route = true
	print("[Level01] Mulai rute dari ", start_node.name)


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

	if connection_start_node == end_node:
		print("[Level01] Node tidak dapat dihubungkan ke dirinya sendiri")
		cancel_route_drawing()
		return

	# Setelah keluar dari Supply Hub, pemain hanya boleh meneruskan
	# ujung rute linear yang belum mencapai Village.
	if (
		connection_start_node != supply_hub
		and not can_continue_route_from(connection_start_node)
	):
		print("[Level01] Mulai rute baru kembali dari Supply Hub")
		cancel_route_drawing()
		return

	if end_node.has_method("can_accept_route"):
		var can_accept_variant: Variant = end_node.call(
			"can_accept_route"
		)
		if not bool(can_accept_variant):
			print("[Level01] Village sudah memiliki rute")
			cancel_route_drawing()
			return

	var mode := determine_transport_mode(
		connection_start_node,
		end_node
	)
	if mode == RouteSegment.TransportMode.INVALID:
		print("[Level01] Sambungan tidak valid")
		cancel_route_drawing()
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
		cancel_route_drawing()
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

	$Routes.add_child(new_segment, true)
	var route_line := new_segment.get_node("RouteLine") as Line2D
	route_line.points = route_preview.points

	var registered := register_segment(new_segment)
	if not registered:
		new_segment.queue_free()
		cancel_route_drawing()
		return

	created_segments.append(new_segment)
	game_hud.set_can_undo(true)

	if end_node is TransitHub:
		(end_node as TransitHub).mark_connected()
	elif end_node.has_method("set_route_connected"):
		end_node.call("set_route_connected")

	print(
		"[Level01] Segment dibuat: ",
		new_segment.name,
		" | Moda: ",
		RouteSegment.TransportMode.keys()[mode]
	)
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
	for transport_route in expedition_routes:
		if (
			is_instance_valid(transport_route)
			and not transport_route.is_complete()
			and transport_route.get_route_end_point() == start_node
		):
			return true
	return false


func register_segment(new_segment: RouteSegment) -> bool:
	for transport_route in expedition_routes:
		if transport_route.add_segment(new_segment):
			print(
				"[Level01] ", new_segment.name,
				" digabung ke ", transport_route.name
			)
			return true

	# Sebuah rute baru wajib berasal dari Supply Hub.
	if new_segment.start_point != supply_hub:
		print("[Level01] Rute baru harus berasal dari Supply Hub")
		return false

	var new_route := (
		EXPEDITION_ROUTE_SCEBE.instantiate() as ExpeditionRoute
	)
	if new_route == null:
		return false

	new_route.name = str("ExpeditionRoute", expedition_routes.size() + 1)
	new_route.route_color = _get_next_route_color()
	$ExpeditionRoutes.add_child(new_route)
	new_route.leader_returned.connect(
		_on_expedition_route_leader_returned
	)
	new_route.vehicle_selected.connect(
		_on_expedition_route_vehicle_selected
	)

	expedition_routes.append(new_route)
	new_route.add_segment(new_segment)
	game_hud.set_route_count(expedition_routes.size())
	print("[Level01] Rute baru dibuat: ", new_route.name)
	return true


func _get_next_route_color() -> Color:
	if route_palette.is_empty():
		return Color("#57C7FF")
	return route_palette[expedition_routes.size() % route_palette.size()]


func find_expedition_route_at_position(
	world_position: Vector2
) -> ExpeditionRoute:
	var closest_route: ExpeditionRoute = null
	var closest_distance: float = INF

	for transport_route in expedition_routes:
		if not transport_route.is_complete():
			continue

		var distance := transport_route.get_distance_to_route(
			world_position
		)
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
		if not bool(village.call("is_self_sustaining")):
			return false

	return true


func update_sustain_timer() -> void:
	if is_game_over or is_victory:
		return

	if are_all_villages_sustaining():
		if sustain_timer.is_stopped():
			sustain_timer.start()
			print("[Level01] Sustain countdown dimulai")
	else:
		if not sustain_timer.is_stopped():
			sustain_timer.stop()
			print("[Level01] Sustain countdown diulang")


func trigger_game_over(failed_village: Area2D) -> void:
	if is_game_over or is_victory:
		return

	is_game_over = true
	failed_village_label.text = str(
		failed_village.name,
		" gagal menerima bantuan."
	)
	game_over_screen.visible = true
	get_tree().paused = true


func get_last_created_segment() -> RouteSegment:
	while not created_segments.is_empty():
		var last_segment: RouteSegment = created_segments.back()
		if is_instance_valid(last_segment):
			return last_segment
		created_segments.pop_back()
	return null


func undo_last_route() -> void:
	var last_segment := get_last_created_segment()
	if last_segment == null:
		print("[Level01] Tidak ada rute untuk Undo")
		return

	var parent_route: ExpeditionRoute = last_segment.parent_expedition_route
	if not is_instance_valid(parent_route):
		return

	if not parent_route.remove_last_segment(last_segment):
		return

	created_segments.pop_back()
	last_segment.queue_free()
	game_hud.hide_vehicle_info()

	if parent_route.segments.is_empty():
		expedition_routes.erase(parent_route)
		parent_route.queue_free()

	game_hud.set_route_count(expedition_routes.size())
	game_hud.set_can_undo(not created_segments.is_empty())
	recalculate_supply_network()
	print("[Level01] Undo berhasil")


func recalculate_supply_network() -> void:
	for node in get_tree().get_nodes_in_group("transit_hubs"):
		if node is TransitHub:
			(node as TransitHub).reset_connection()

	for village in villages:
		if village.has_method("set_route_disconnected"):
			village.call("set_route_disconnected")

	var reachable_nodes: Dictionary = {supply_hub: true}
	var network_changed := true

	while network_changed:
		network_changed = false

		for transport_route in expedition_routes:
			for segment in transport_route.segments:
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
		print("[Level01] ", start_hub.name, " belum terhubung")
		return

	if not can_continue_route_from(start_hub):
		print(
			"[Level01] ", start_hub.name,
			" bukan ujung rute aktif. Mulai dari Supply Hub."
		)
		return

	begin_connection_drawing(start_hub, start_hub.global_position)


func _on_transit_connection_drag_finished(
	end_hub: TransitHub
) -> void:
	finish_connection(end_hub, end_hub.global_position)


func _on_village_a_route_drag_finished(
	target_position: Vector2,
	target_village: Area2D
) -> void:
	finish_connection(target_village, target_position)


func _on_village_b_route_drag_finished(
	target_position: Vector2,
	target_village: Area2D
) -> void:
	finish_connection(target_village, target_position)


func _on_village_a_village_failed(
	failed_village: Area2D
) -> void:
	trigger_game_over(failed_village)


func _on_village_b_village_failed(
	failed_village: Area2D
) -> void:
	trigger_game_over(failed_village)


func _on_leader_token_drag_started(token: LeaderToken) -> void:
	dragged_leader_token = token
	print("[Level01] Menyeret token ", token.leader_name)


func _on_leader_token_drag_released(token: LeaderToken) -> void:
	if dragged_leader_token != token:
		return

	var world_drop_position := get_global_mouse_position()
	var target_route := find_expedition_route_at_position(
		world_drop_position
	)

	if target_route == null:
		print("[Level01] Drop gagal: tidak ada rute lengkap")
		token.return_to_roster()
		dragged_leader_token = null
		return

	var assigned := target_route.try_assign_leader(
		token.leader_id,
		token.leader_name,
		token.leader_color,
		token.icon_texture
	)

	if assigned:
		leader_roster.consume_leader_token(token)
	else:
		token.return_to_roster()

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
	game_hud.hide_vehicle_info()


func _on_expedition_route_vehicle_selected(
	vehicle: TransportVehicle
) -> void:
	if is_instance_valid(vehicle):
		game_hud.show_vehicle_info(vehicle)


func _on_village_cargo_received(received_amount: int) -> void:
	total_logistics_delivered += received_amount
	game_hud.set_logistics_count(total_logistics_delivered)


func _on_game_hud_undo_route_requested() -> void:
	undo_last_route()


func _on_sustain_timer_timeout() -> void:
	if is_game_over or is_victory:
		return

	is_victory = true
	victory_screen.visible = true
	get_tree().paused = true
	print("[Level01] LEVEL COMPLETED")


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _on_replay_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _on_level_selection_button_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(LEVEL_SELECTION_PATH)
