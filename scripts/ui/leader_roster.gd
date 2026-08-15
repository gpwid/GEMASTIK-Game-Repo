class_name LeaderRoster
extends VBoxContainer

const LEADER_TOKEN_SCENE: PackedScene = preload(
	"res://scenes/ui/leader_token.tscn"
)

signal leader_drag_started(token: LeaderToken)
signal leader_drag_released(token: LeaderToken)

@export var leader_profiles: Array[LeaderProfile] = []
@export var stack_offset: Vector2 = Vector2(10.0, 0.0)
@export var stack_width: float = 150.0
@export var token_size: float = 112.0

var leader_stack: Control = null


func _ready() -> void:
	create_leader_stack()

	var registered_ids: Dictionary = {}

	for profile in leader_profiles:
		if profile == null:
			push_warning("LeaderRoster memiliki profile kosong")
			continue

		if not profile.is_valid_profile():
			push_warning("LeaderProfile tidak valid: " + profile.leader_name)
			continue

		if registered_ids.has(profile.leader_id):
			push_warning("Leader ID duplikat: " + profile.leader_id)
			continue

		registered_ids[profile.leader_id] = true
		create_leader_token(profile)

	layout_leader_stack()


func create_leader_stack() -> void:
	leader_stack = Control.new()
	leader_stack.name = "LeaderStack"
	leader_stack.custom_minimum_size = Vector2(
		stack_width,
		token_size
	)
	leader_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(leader_stack)


func create_leader_token(profile: LeaderProfile) -> LeaderToken:
	if leader_stack == null:
		return null

	var token: LeaderToken = (
		LEADER_TOKEN_SCENE.instantiate() as LeaderToken
	)

	if token == null:
		return null

	token.name = str(
		"LeaderToken",
		leader_stack.get_child_count() + 1
	)
	token.configure(profile)

	leader_stack.add_child(token)

	token.leader_drag_started.connect(
		_on_leader_drag_started
	)
	token.leader_drag_released.connect(
		_on_leader_drag_released
	)

	return token


func layout_leader_stack() -> void:
	if leader_stack == null:
		return

	var tokens: Array[LeaderToken] = []

	for child in leader_stack.get_children():
		if child is LeaderToken:
			tokens.append(child as LeaderToken)

	for index in range(tokens.size()):
		var token: LeaderToken = tokens[index]
		var reverse_index: int = tokens.size() - 1 - index

		token.position = stack_offset * reverse_index
		token.z_index = index

		if index == tokens.size() - 1:
			token.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			token.mouse_filter = Control.MOUSE_FILTER_IGNORE


func consume_leader_token(token: LeaderToken) -> void:
	if token == null:
		return

	if token.get_parent() != leader_stack:
		return

	var consumed_name: String = token.leader_name

	leader_stack.remove_child(token)
	token.queue_free()

	layout_leader_stack()

	print("[LeaderRoster] Leader ditugaskan: ", consumed_name)


func restore_leader(
	leader_id: String,
	leader_name: String,
	leader_color: Color,
	icon_texture: Texture2D
) -> bool:
	if leader_stack == null:
		return false

	if has_available_leader(leader_id):
		push_warning("Leader sudah ada di roster: " + leader_id)
		return false

	var restored_profile: LeaderProfile = LeaderProfile.new()
	restored_profile.leader_id = leader_id
	restored_profile.leader_name = leader_name
	restored_profile.leader_color = leader_color
	restored_profile.icon_texture = icon_texture

	var token: LeaderToken = create_leader_token(restored_profile)

	if token == null:
		return false

	layout_leader_stack()

	print("[LeaderRoster] Leader kembali: ", leader_name)
	return true


func has_available_leader(leader_id: String) -> bool:
	if leader_stack == null:
		return false

	for child in leader_stack.get_children():
		if child is LeaderToken:
			var token: LeaderToken = child as LeaderToken
			if token.leader_id == leader_id:
				return true

	return false


func _on_leader_drag_started(token: LeaderToken) -> void:
	leader_drag_started.emit(token)


func _on_leader_drag_released(token: LeaderToken) -> void:
	leader_drag_released.emit(token)
