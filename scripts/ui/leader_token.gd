class_name LeaderToken
extends Button

signal leader_drag_started(token: LeaderToken)
signal leader_drag_released(token: LeaderToken)

@export var leader_id: String = ""
@export var leader_name: String = "Pemimpin Ekspedisi"
@export var leader_color: Color = Color.WHITE
@export var icon_texture: Texture2D

@onready var leader_icon: TextureRect = $LeaderIcon

var roster_z_index: int = 0
var is_dragging: bool = false
var roster_position: Vector2


func _ready() -> void:
	pivot_offset = size / 2.0
	set_process(false)
	update_token_visual()


func configure(profile: LeaderProfile) -> void:
	if profile == null:
		return

	leader_id = profile.leader_id
	leader_name = profile.leader_name
	leader_color = profile.leader_color
	icon_texture = profile.icon_texture

	if is_node_ready():
		update_token_visual()


func update_token_visual() -> void:
	tooltip_text = leader_name
	self_modulate = leader_color.lightened(0.45)

	if icon_texture != null:
		leader_icon.texture = icon_texture


func _process(_delta: float) -> void:
	if not is_dragging:
		return

	global_position = get_global_mouse_position() - size / 2.0


func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_event.pressed:
		begin_drag()
	else:
		end_drag()

	accept_event()


func begin_drag() -> void:
	if is_dragging:
		return

	is_dragging = true
	roster_position = global_position
	roster_z_index = z_index
	z_index = 100
	scale = Vector2(1.08, 1.08)
	set_process(true)

	leader_drag_started.emit(self)


func end_drag() -> void:
	if not is_dragging:
		return

	is_dragging = false
	z_index = roster_z_index
	scale = Vector2.ONE
	set_process(false)

	leader_drag_released.emit(self)


func return_to_roster() -> void:
	global_position = roster_position
