class_name VehicleInventoryEntry
extends Resource

@export var transport_mode: RouteSegment.TransportMode = RouteSegment.TransportMode.TRUCK
@export_range(0, 99, 1) var starting_count: int = 0
@export var icon: Texture2D
