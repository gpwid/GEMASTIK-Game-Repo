class_name SupplyRoute
extends Path2D

@export var travel_speed: float = 120.0

const VEHICLE_CARGO_CAPACITY: int = 4

var travel_direction: float = 1.0
var target_village: Area2D

@onready var vehicle_follower: PathFollow2D = $VehicleFollower
@onready var boat: Node2D = $VehicleFollower/Boat

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	vehicle_follower.progress = vehicle_follower.progress + travel_speed * travel_direction * delta
	if vehicle_follower.progress_ratio >= 1.0:
		vehicle_follower.progress_ratio = 1.0
		if target_village != null and target_village.has_method("receive_delivery"):
			target_village.call("receive_delivery", VEHICLE_CARGO_CAPACITY)
		travel_direction = -1
		boat.rotation = PI
	elif vehicle_follower.progress_ratio <= 0.0:
		vehicle_follower.progress_ratio = 0.0
		travel_direction = 1
		boat.rotation = 0.0
