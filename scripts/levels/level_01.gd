extends Node2D

const ROUTE_SCENE: PackedScene = preload("res://scenes/objects/route.tscn")

var is_drawing_route: bool = false
var is_game_over: bool = false
var is_victory: bool = false

var villages: Array[Area2D] = []
@onready var route_preview: Line2D = $Routes/RoutePreview
@onready var game_over_screen: ColorRect = $UI/GameOverScreen
@onready var failed_village_label: Label = $UI/GameOverScreen/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FailedVillageLabel
@onready var sustain_timer: Timer = $SustainTimer
@onready var victory_screen: ColorRect = $UI/VictoryScreen

func _ready() -> void:
	for child in $MapObjects.get_children():
		if child.name.begins_with("Village"):
			villages.append(child)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if is_drawing_route:
		var local_mouse_pos = route_preview.get_local_mouse_position()
		route_preview.set_point_position(1, local_mouse_pos)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			cancel_route_drawing()
	update_sustain_timer()	


func _on_supply_hub_route_drag_started(origin_position: Vector2) -> void:
	print(origin_position)
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
	
func finish_route(target_position: Vector2, target_village: Area2D) -> void:
	if not is_drawing_route:
		return
	
	if not target_village.has_method("can_accept_route") or not target_village.call("can_accept_route"):
		cancel_route_drawing()
		print("Ga bisa letak rute sini")
		return
		
	print("Target Village: ", target_village.name)

	var local_pos = route_preview.to_local(target_position)
	route_preview.set_point_position(1, local_pos)
	var start_pos = route_preview.get_point_position(0)
	var end_pos = route_preview.get_point_position(1)
	var new_route: SupplyRoute = ROUTE_SCENE.instantiate() as SupplyRoute
	new_route.target_village = target_village
	print("Route destination saved: ", new_route.target_village.name)
	
	var new_curve: Curve2D = Curve2D.new()
	new_curve.add_point(start_pos)
	new_curve.add_point(end_pos)
	new_route.curve = new_curve
	
	var route_line: Line2D = new_route.get_node("RouteLine") as Line2D
	route_line.points = route_preview.points
	$Routes.add_child(new_route, true)
	if target_village.has_method("set_route_connected"):
		target_village.call("set_route_connected")
		print(are_all_villages_sustaining())
	cancel_route_drawing()
	
	print("Route Completed")
			
func _on_village_a_route_drag_finished(target_position: Vector2, target_village: Area2D) -> void:
	finish_route(target_position, target_village)

func _on_village_b_route_drag_finished(target_position: Vector2, target_village: Area2D) -> void:
	finish_route(target_position, target_village)


func _on_village_a_village_failed(failed_village: Area2D) -> void:
	trigger_game_over(failed_village)


func _on_village_b_village_failed(failed_village: Area2D) -> void:
	trigger_game_over(failed_village)	
	
func trigger_game_over(failed_village: Area2D) -> void:
	if is_game_over or is_victory:
		return
	is_game_over = true
	failed_village_label.text = str(failed_village.name, " gagal menerima bantuan.")
	game_over_screen.visible = true
	get_tree().paused = true

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
	
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
			print("Sustain countdown dimulai")
	else:
		if not sustain_timer.is_stopped():
			sustain_timer.stop()
			print("Sustain countdown reset")

func _on_sustain_timer_timeout() -> void:
	if is_game_over or is_victory:
		return
	is_victory = true
	victory_screen.visible = true
	print("LEVEL COMPLETED")
	get_tree().paused = true

func _on_replay_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
