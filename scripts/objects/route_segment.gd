class_name RouteSegment
extends Path2D

enum TransportMode {
	INVALID,
	TRUCK,
	SHIP,
}

@export var truck_route_color: Color = "#e0ad1f"
@export var ship_route_color: Color = "#acfafa"

var transport_mode: TransportMode = TransportMode.INVALID
var start_point: Area2D = null
var end_point: Area2D = null
var parent_transport_route: TransportRoute = null

@onready var route_line: Line2D = $RouteLine

		
func _ready() -> void:
	update_route_visual()

func update_route_visual() -> void:
	if transport_mode == TransportMode.TRUCK:
		route_line.default_color = truck_route_color
	elif transport_mode == TransportMode.SHIP:
		route_line.default_color = ship_route_color
		
	
