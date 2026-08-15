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

@onready var route_line: Line2D = $RouteLine


func _ready() -> void:
	# Garis berada di bawah bangunan dan kendaraan.
	z_index = -20
	set_route_visual(inactive_route_color, false)


func set_route_visual(route_color: Color, is_active: bool) -> void:
	if not is_node_ready():
		return

	route_line.default_color = route_color if is_active else inactive_route_color
	route_line.width = 8.0 if is_active else 6.0
	route_line.joint_mode = Line2D.LINE_JOINT_ROUND
	route_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	route_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	route_line.antialiased = true
