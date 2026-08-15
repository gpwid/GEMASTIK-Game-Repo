class_name MainMenu
extends Control

const LEVEL_SELECTION_PATH: String = "res://scenes/ui/level_selection.tscn"

@onready var new_game_button: Button = %NewGameButton
@onready var exit_button: Button = %ExitButton
@onready var right_switcher: TabContainer = %RightSwitcher


func _ready() -> void:
	right_switcher.current_tab = 0
	new_game_button.grab_focus()


func _on_exit_button_pressed() -> void:
	get_tree().quit()
	
func _on_new_game_button_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECTION_PATH)
	
func show_best_record() -> void:
	right_switcher.current_tab = 0
	
func show_credits() -> void:
	right_switcher.current_tab = 1
