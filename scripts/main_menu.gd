extends Node2D
## The title screen. The animated forest and the menu itself live in the MenuUI
## autoload, which stays alive across scene changes, so this scene only has to
## tell it to show the main menu.

func _ready() -> void:
	MenuUI.open_main_menu()
