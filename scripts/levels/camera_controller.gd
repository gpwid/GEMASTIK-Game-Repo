class_name MapCameraController
extends Camera2D

@export_category("Camera Markers")
@export var top_left_bound: Marker2D
@export var bottom_right_bound: Marker2D
@export var camera_start: Marker2D

@export_category("Interaction")
@export var route_network_manager: RouteNetworkManager
@export_enum("Left:1", "Right:2", "Middle:3")
var pan_mouse_button: int = MOUSE_BUTTON_LEFT
@export_range(0.1, 3.0, 0.1) var pan_speed: float = 1.0
@export_range(0.0, 32.0, 1.0) var drag_threshold_pixels: float = 6.0

@export_category("Zoom")
@export_range(0.1, 4.0, 0.05) var minimum_zoom: float = 0.5
@export_range(0.1, 4.0, 0.05) var maximum_zoom: float = 1.5
@export_range(0.05, 0.5, 0.05) var zoom_step: float = 0.1

@export_category("Bounds")
@export var bounds_padding: Vector2 = Vector2.ZERO

var _is_pan_candidate: bool = false
var _is_panning: bool = false
var _drag_start_screen_position: Vector2 = Vector2.ZERO

var _bounds_left: float = 0.0
var _bounds_top: float = 0.0
var _bounds_right: float = 0.0
var _bounds_bottom: float = 0.0


func _ready() -> void:
	if not _validate_references():
		set_process_unhandled_input(false)
		return

	enabled = true
	make_current()
	zoom = Vector2.ONE * clampf(
		zoom.x,
		minimum_zoom,
		maximum_zoom
	)
	_update_camera_bounds()

	if camera_start != null:
		global_position = camera_start.global_position

	_clamp_camera_position()

	if not get_viewport().size_changed.is_connected(
		_on_viewport_size_changed
	):
		get_viewport().size_changed.connect(
			_on_viewport_size_changed
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _validate_references() -> bool:
	var is_valid := true

	if top_left_bound == null:
		push_error("MapCameraController: Top Left Bound belum diisi")
		is_valid = false
	if bottom_right_bound == null:
		push_error("MapCameraController: Bottom Right Bound belum diisi")
		is_valid = false

	return is_valid


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at_screen_position(zoom.x + zoom_step, event.position)
		return

	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at_screen_position(zoom.x - zoom_step, event.position)
		return

	if event.button_index != pan_mouse_button:
		return

	if event.pressed:
		if _is_camera_interaction_blocked():
			_stop_panning()
			return

		_is_pan_candidate = true
		_is_panning = false
		_drag_start_screen_position = event.position
	else:
		_stop_panning()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_pan_candidate:
		return

	if _is_camera_interaction_blocked():
		_stop_panning()
		return

	if not _is_panning:
		var drag_distance := event.position.distance_to(
			_drag_start_screen_position
		)
		if drag_distance < drag_threshold_pixels:
			return
		_is_panning = true

	var safe_zoom_x := maxf(zoom.x, 0.001)
	var safe_zoom_y := maxf(zoom.y, 0.001)
	var world_drag := Vector2(
		event.relative.x / safe_zoom_x,
		event.relative.y / safe_zoom_y
	)

	global_position -= world_drag * pan_speed
	_clamp_camera_position()
	get_viewport().set_input_as_handled()


func _is_camera_interaction_blocked() -> bool:
	if route_network_manager == null:
		return false

	return (
		route_network_manager.is_drawing_route
		or route_network_manager.dragged_leader_token != null
	)


func _stop_panning() -> void:
	_is_pan_candidate = false
	_is_panning = false

func _get_effective_minimum_zoom() -> float:
	var bounds_width: float = maxf(
		_bounds_right - _bounds_left,
		1.0
	)
	var bounds_height: float = maxf(
		_bounds_bottom - _bounds_top,
		1.0
	)
	var viewport_size: Vector2 = get_viewport_rect().size

	var horizontal_fit: float = viewport_size.x / bounds_width
	var vertical_fit: float = viewport_size.y / bounds_height
	var zoom_needed_to_fit: float = maxf(
		horizontal_fit,
		vertical_fit
	)

	return maxf(minimum_zoom, zoom_needed_to_fit)

func _zoom_at_screen_position(
	target_zoom: float,
	screen_position: Vector2
) -> void:
	if _is_camera_interaction_blocked():
		return

	var effective_minimum: float = _get_effective_minimum_zoom()
	var effective_maximum: float = maxf(
		maximum_zoom,
		effective_minimum
	)

	var clamped_zoom: float = clampf(
		target_zoom,
		effective_minimum,
		effective_maximum
	)
	
	if is_equal_approx(clamped_zoom, zoom.x):
		return

	var viewport_center := get_viewport_rect().size * 0.5
	var cursor_from_center := screen_position - viewport_center
	var world_offset_before := Vector2(
		cursor_from_center.x / maxf(zoom.x, 0.001),
		cursor_from_center.y / maxf(zoom.y, 0.001)
	)

	zoom = Vector2.ONE * clamped_zoom

	var world_offset_after := cursor_from_center / clamped_zoom
	global_position += world_offset_before - world_offset_after
	_clamp_camera_position()
	get_viewport().set_input_as_handled()


func _update_camera_bounds() -> void:
	var first_corner := top_left_bound.global_position
	var second_corner := bottom_right_bound.global_position

	_bounds_left = minf(first_corner.x, second_corner.x)
	_bounds_top = minf(first_corner.y, second_corner.y)
	_bounds_right = maxf(first_corner.x, second_corner.x)
	_bounds_bottom = maxf(first_corner.y, second_corner.y)

	_bounds_left += bounds_padding.x
	_bounds_top += bounds_padding.y
	_bounds_right -= bounds_padding.x
	_bounds_bottom -= bounds_padding.y

	limit_left = floori(_bounds_left)
	limit_top = floori(_bounds_top)
	limit_right = ceili(_bounds_right)
	limit_bottom = ceili(_bounds_bottom)


func _clamp_camera_position() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_zoom_x := maxf(zoom.x, 0.001)
	var safe_zoom_y := maxf(zoom.y, 0.001)
	var half_visible_world := Vector2(
		viewport_size.x / safe_zoom_x,
		viewport_size.y / safe_zoom_y
	) * 0.5

	var minimum_center := Vector2(
		_bounds_left + half_visible_world.x,
		_bounds_top + half_visible_world.y
	)
	var maximum_center := Vector2(
		_bounds_right - half_visible_world.x,
		_bounds_bottom - half_visible_world.y
	)

	var new_position := global_position

	if minimum_center.x <= maximum_center.x:
		new_position.x = clampf(
			new_position.x,
			minimum_center.x,
			maximum_center.x
		)
	else:
		new_position.x = (_bounds_left + _bounds_right) * 0.5

	if minimum_center.y <= maximum_center.y:
		new_position.y = clampf(
			new_position.y,
			minimum_center.y,
			maximum_center.y
		)
	else:
		new_position.y = (_bounds_top + _bounds_bottom) * 0.5

	global_position = new_position


func refresh_camera_bounds() -> void:
	_update_camera_bounds()
	_clamp_camera_position()

func focus_on(world_position: Vector2) -> void:
	global_position = world_position
	_clamp_camera_position()

func _on_viewport_size_changed() -> void:
	var effective_minimum: float = _get_effective_minimum_zoom()

	if zoom.x < effective_minimum:
		zoom = Vector2.ONE * effective_minimum

	_clamp_camera_position()
