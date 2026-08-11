extends Node2D

const ROUTE_SCENE: PackedScene = preload("res://scenes/objects/route.tscn")
var is_drawing_route = false
@onready var route_preview: Line2D = $Routes/RoutePreview

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_drawing_route:
		var local_mouse_pos = route_preview.get_local_mouse_position()
		route_preview.set_point_position(1, local_mouse_pos)


func _on_supply_hub_route_drag_started(origin_position: Vector2) -> void:
	print(origin_position)
	route_preview.clear_points()
	var local_pos = route_preview.to_local(origin_position)
	route_preview.add_point(local_pos)
	route_preview.add_point(local_pos)
	route_preview.visible = true
	is_drawing_route = true
	
func finish_route(target_position: Vector2) -> void:
	if is_drawing_route == false:
		return
	
	var local_pos = route_preview.to_local(target_position)
	route_preview.set_point_position(1, local_pos)
	var start_pos = route_preview.get_point_position(0)
	var end_pos = route_preview.get_point_position(1)
	var new_route: Path2D = ROUTE_SCENE.instantiate() as Path2D
	var new_curve: Curve2D = Curve2D.new()
	new_curve.add_point(start_pos)
	new_curve.add_point(end_pos)
	new_route.curve = new_curve
	var route_line: Line2D = new_route.get_node("RouteLine") as Line2D
	route_line.points = route_preview.points
	$Routes.add_child(new_route, true)
	route_preview.clear_points()
	route_preview.visible = false
	is_drawing_route = false
	print("Route Completed")
	
func _on_village_a_route_drag_finished(target_position: Vector2) -> void:
	finish_route(target_position)

func _on_village_b_route_drag_finished(target_position: Vector2) -> void:
	finish_route(target_position)
