class_name VehicleInventory
extends VBoxContainer

const VEHICLE_TOKEN_SCENE: PackedScene = preload("res://scenes/ui/vehicle_token.tscn")

signal token_drag_started(token: VehicleToken)
signal token_drag_released(token: VehicleToken)


@export var vehicle_entries: Array[VehicleInventoryEntry] = []
@export var stack_offset: Vector2 = Vector2(10.0, 0.0)
@export var stack_width: float = 150.0
@export var token_size: float = 112.0

func _ready() -> void:
	for entry in vehicle_entries:
		if entry == null:
			continue
		if entry.starting_count <= 0:
			continue
		create_vehicle_stack(entry)

func create_vehicle_stack(entry: VehicleInventoryEntry) -> void:
	var stack: Control = Control.new()
	stack.name = str(RouteSegment.TransportMode.keys()[entry.transport_mode], "Stack")
	stack.custom_minimum_size = Vector2(stack_width, token_size)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(stack)

	for index in range(entry.starting_count):
		create_vehicle_token(stack, entry, index)

	layout_stack(stack)	
	
func create_vehicle_token(stack: Control, entry: VehicleInventoryEntry, index: int) -> void:
	var token: VehicleToken = (VEHICLE_TOKEN_SCENE.instantiate() as VehicleToken)
	if token == null:
		return

	token.name = str(RouteSegment.TransportMode.keys()[entry.transport_mode], "Token", index + 1)
	token.transport_mode = entry.transport_mode
	token.icon_texture = entry.icon

	stack.add_child(token)
	token.vehicle_drag_started.connect(_on_token_drag_started)
	token.vehicle_drag_released.connect(_on_token_drag_released)
	
func create_token_stack(stack: Control, amount: int, mode: RouteSegment.TransportMode, icon: Texture2D) -> void:
	for index in range(amount):
		var token: VehicleToken = (VEHICLE_TOKEN_SCENE.instantiate() as VehicleToken)
		if token == null:
			continue

		token.transport_mode = mode
		token.icon_texture = icon
		token.name = str(RouteSegment.TransportMode.keys()[mode], "Token", index + 1)

		stack.add_child(token)
		token.vehicle_drag_started.connect(_on_token_drag_started)
		token.vehicle_drag_released.connect(_on_token_drag_released)

	layout_stack(stack)
	
func layout_stack(stack: Control) -> void:
	var tokens: Array[VehicleToken] = []
	for child in stack.get_children():
		if child is VehicleToken:
			tokens.append(child as VehicleToken)
	for index in range(tokens.size()):
		var token: VehicleToken = tokens[index]
		var reverse_index: int = tokens.size() - 1 - index
		token.position = stack_offset * reverse_index
		token.z_index = index
		token.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if index == tokens.size() - 1
			else Control.MOUSE_FILTER_IGNORE
		)
	
func consume_token(token: VehicleToken) -> void:
	var stack: Control = token.get_parent() as Control

	if stack == null:
		return

	var consumed_mode: RouteSegment.TransportMode = token.transport_mode
	stack.remove_child(token)
	token.queue_free()

	layout_stack(stack)

	print("[consume_token:vehicle_inventory.gd] Mode: ", RouteSegment.TransportMode.keys()[consumed_mode], " | Tersisa: ", stack.get_child_count())
	
func restore_vehicle(transport_mode: RouteSegment.TransportMode) -> bool:
	var matching_entry: VehicleInventoryEntry = null
	for entry in vehicle_entries:
		if entry == null:
			continue
		if entry.transport_mode == transport_mode:
			matching_entry = entry
			break

	if matching_entry == null:
		print("VehicleInventoryEntry tidak ditemukan untuk mode: ", RouteSegment.TransportMode.keys()[transport_mode])
		return false

	var stack_name: String = str(RouteSegment.TransportMode.keys()[transport_mode], "Stack")

	var stack: Control = get_node_or_null(NodePath(stack_name)) as Control

	if stack == null:
		print("Stack kendaraan tidak ditemukan: ", stack_name)
		return false

	var new_token_index: int = stack.get_child_count()

	create_vehicle_token(stack, matching_entry, new_token_index)

	layout_stack(stack)

	print("[restore_vehicle:vehicle_inventory.gd] Mode: ", RouteSegment.TransportMode.keys()[transport_mode], " | Tersedia: ", stack.get_child_count())
	return true	
	
func register_stack_tokens(stack: Control) -> void:
	for child in stack.get_children():
		var token: VehicleToken = child as VehicleToken

		if token == null:
			continue

		token.vehicle_drag_started.connect(_on_token_drag_started)
		token.vehicle_drag_released.connect(_on_token_drag_released)
		
func _on_token_drag_started(token: VehicleToken) -> void:
	token_drag_started.emit(token)


func _on_token_drag_released(token: VehicleToken) -> void:
	token_drag_released.emit(token)
