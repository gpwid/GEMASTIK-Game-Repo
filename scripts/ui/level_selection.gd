class_name LevelSelection
extends Control

const MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const LEVEL_01_PATH: String = "res://scenes/levels/level_01.tscn"

@onready var level_1_button: Button = %Level1Button

func _ready() -> void:
	level_1_button.grab_focus()
	
func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
	
func _on_level_1_button_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_01_PATH)
