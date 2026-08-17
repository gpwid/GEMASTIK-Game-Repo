extends Node

## Kumpulan ambiance
@export var ambience_tracks: Array[AudioStream] = []

## Kumpulan suara expedition leader ketika berhasil dipasang ke rute
@export var leader_voices: Array[AudioStream] = []

## Efek suara gameplay
@export var route_connected_sound: AudioStream
@export var error_sound: AudioStream
@export var supply_delivered_sound: AudioStream
@export var critical_fuel_sound: AudioStream
@export var vehicle_breakdown_sound: AudioStream
@export var game_over_sound: AudioStream
@export var victory_sound: AudioStream

## Efek suara tombol antarmuka
@export var ui_click_sound: AudioStream

@onready var ambience_player: AudioStreamPlayer = $AmbiencePlayer
@onready var sfx_player: AudioStreamPlayer = $SFXPlayer
@onready var voice_player: AudioStreamPlayer = $VoicePlayer
@onready var ui_player: AudioStreamPlayer = $UIPlayer

var last_leader_voice_index: int = -1

func _ready() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)

	call_deferred("_register_existing_ui_buttons")
	
## Mendaftarkan tombol yang sudah ada ketika scene dibuka.
func _register_existing_ui_buttons() -> void:
	var all_nodes: Array[Node] = get_tree().root.find_children(
		"*",
		"",
		true,
		false
	)

	for node in all_nodes:
		if node is BaseButton:
			_register_ui_button(node as BaseButton)


## Mendeteksi tombol yang baru ditambahkan saat runtime.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register_ui_button(node as BaseButton)


## Menghubungkan satu tombol ke suara UI.
func _register_ui_button(button: BaseButton) -> void:
	if button.is_in_group("no_ui_click"):
		return

	if button.pressed.is_connected(_on_ui_button_pressed):
		return

	button.pressed.connect(_on_ui_button_pressed)


func _on_ui_button_pressed() -> void:
	play_ui_click()

## Memilih satu ambiance secara acak trus diputer
func play_random_ambience() -> void:
	if ambience_tracks.is_empty():
		push_warning("AudioManager: ambiance belum dimasukkan")
		return

	var selected_index: int = randi_range(
		0,
		ambience_tracks.size() - 1
	)

	ambience_player.stream = ambience_tracks[selected_index]
	ambience_player.play()


## Memilih suara leader
func play_random_leader_voice() -> void:
	if leader_voices.is_empty():
		push_warning("AudioManager: suara leader belum dimasukkan")
		return

	var selected_index: int = 0

	if leader_voices.size() > 1:
		selected_index = randi_range(
			0,
			leader_voices.size() - 1
		)

		while selected_index == last_leader_voice_index:
			selected_index = randi_range(
				0,
				leader_voices.size() - 1
			)

	last_leader_voice_index = selected_index
	voice_player.stream = leader_voices[selected_index]
	voice_player.play()


## Memutar satu efek gameplay
func play_sfx(audio_stream: AudioStream) -> void:
	if audio_stream == null:
		return

	sfx_player.stream = audio_stream
	sfx_player.play()


func play_route_connected() -> void:
	play_sfx(route_connected_sound)


func play_error() -> void:
	play_sfx(error_sound)


func play_supply_delivered() -> void:
	play_sfx(supply_delivered_sound)


func play_critical_fuel() -> void:
	play_sfx(critical_fuel_sound)


func play_vehicle_breakdown() -> void:
	play_sfx(vehicle_breakdown_sound)


func play_game_over() -> void:
	ambience_player.stop()
	play_sfx(game_over_sound)


func play_victory() -> void:
	ambience_player.stop()
	play_sfx(victory_sound)


func play_ui_click() -> void:
	if ui_click_sound == null:
		return

	ui_player.stream = ui_click_sound
	ui_player.play()
