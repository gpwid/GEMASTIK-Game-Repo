class_name LeaderProfile
extends Resource

@export var leader_id: String = ""
@export var leader_name: String = "Pemimpin Ekspedisi"
@export var leader_color: Color = Color.WHITE
@export var icon_texture: Texture2D


func is_valid_profile() -> bool:
	return (
		not leader_id.strip_edges().is_empty()
		and not leader_name.strip_edges().is_empty()
	)
