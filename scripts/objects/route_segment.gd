class_name RouteSegment
extends Path2D

## Satu potongan fisik rute. Moda ditentukan oleh kedua node ujungnya.
## Beberapa segment berurutan digabungkan oleh ExpeditionRoute menjadi
## satu ekspedisi multimoda dari Supply Hub sampai Village.

enum TransportMode {
	INVALID,
	TRUCK,
	SHIP,
}

@export var inactive_route_color: Color = Color("#66747A")

var transport_mode: TransportMode = TransportMode.INVALID
var start_point: Area2D = null
var end_point: Area2D = null
var parent_expedition_route: ExpeditionRoute = null
var original_line_points: PackedVector2Array = PackedVector2Array()
var visual_lane_offset: float = 0.0
var is_drop_highlighted: bool = false
var normal_route_width: float = 6.0

@export var drop_highlight_width_addition: float = 6.0

@onready var route_line: Line2D = $RouteLine


func _ready() -> void:
	# Garis berada di bawah bangunan dan kendaraan.
	z_index = -20
	set_route_visual(inactive_route_color, false)


func set_route_visual(route_color: Color, is_active: bool) -> void:
	if not is_node_ready():
		return

	route_line.default_color = (
		route_color if is_active else inactive_route_color
	)

	normal_route_width = 8.0 if is_active else 6.0
	apply_route_line_width()

	route_line.joint_mode = Line2D.LINE_JOINT_ROUND
	route_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	route_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	route_line.antialiased = true
	
func apply_route_line_width() -> void:
	route_line.width = normal_route_width

	if is_drop_highlighted:
		route_line.width += drop_highlight_width_addition
		
func set_drop_highlight(is_highlighted: bool) -> void:
	is_drop_highlighted = is_highlighted
	apply_route_line_width()

	if is_highlighted:
		route_line.self_modulate = Color("#CFF4FF")
	else:
		route_line.self_modulate = Color.WHITE
			
func set_visual_lane_offset(new_offset: float) -> void:
	if not is_node_ready():
		return

	if original_line_points.is_empty():
		original_line_points = route_line.points.duplicate()

	if original_line_points.size() < 2:
		return

	visual_lane_offset = new_offset

	var first_point: Vector2 = original_line_points[0]
	var last_point: Vector2 = original_line_points[
		original_line_points.size() - 1
	]

	var line_direction := (last_point - first_point).normalized()
	var perpendicular_direction := Vector2(
		-line_direction.y,
		line_direction.x
	)

	var offset_points := PackedVector2Array()

	for point in original_line_points:
		offset_points.append(
			point + perpendicular_direction * visual_lane_offset
		)

	route_line.points = offset_points
	
	for child in get_children():
		if child is PathFollow2D:
			var follower := child as PathFollow2D
			follower.v_offset = visual_lane_offset

func get_distance_to_visual_line(
	world_position: Vector2
) -> float:
	if route_line.points.size() < 2:
		return INF

	var local_position := route_line.to_local(world_position)
	var closest_distance: float = INF

	for index in range(route_line.points.size() - 1):
		var point_a: Vector2 = route_line.points[index]
		var point_b: Vector2 = route_line.points[index + 1]

		var closest_point := Geometry2D.get_closest_point_to_segment(
			local_position,
			point_a,
			point_b
		)

		var distance := local_position.distance_to(closest_point)
		closest_distance = minf(closest_distance, distance)

	return closest_distance
