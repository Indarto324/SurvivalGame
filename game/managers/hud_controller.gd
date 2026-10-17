extends Node

@onready var hud: Control = $HUD

func _enter_tree() -> void:
	EventSystem.HUD_hide_hud.connect(hide_hud)
	EventSystem.HUD_show_hud.connect(show_hud)


func _ready() -> void:
	hide_hud()


func hide_hud() -> void:
	hud.hide()


func show_hud() -> void:
	hud.show()
