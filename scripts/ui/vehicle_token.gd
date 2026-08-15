class_name VehicleToken
extends Button

signal vehicle_drag_started(token: VehicleToken)
signal vehicle_drag_released(token: VehicleToken)

@export var transport_mode: RouteSegment.TransportMode = RouteSegment.TransportMode.TRUCK
@export var icon_texture: Texture2D

@onready var vehicle_icon: TextureRect = $VehicleIcon

var is_dragging: bool = false
var inventory_position: Vector2

func _ready() -> void:
	pivot_offset = size / 2.0
	set_process(false)
	
	if icon_texture != null:
		vehicle_icon.texture = icon_texture
	
func _process(_delta: float) -> void:
	if not is_dragging:
		return
	global_position = get_global_mouse_position() - size / 2.0	
	
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				begin_drag()
			else:
				end_drag()

			accept_event()
			
func begin_drag() -> void:
	if is_dragging:
		return

	is_dragging = true
	inventory_position = global_position
	z_index = 100
	scale = Vector2(1.08, 1.08)
	set_process(true)

	vehicle_drag_started.emit(self)
	
func end_drag() -> void:
	if not is_dragging:
		return

	is_dragging = false
	z_index = 0
	scale = Vector2.ONE
	set_process(false)

	vehicle_drag_released.emit(self)
	
func return_to_inventory() -> void:
	global_position = inventory_position
	
