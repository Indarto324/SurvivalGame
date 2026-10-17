extends Node

@onready var hud: Control = $HUD

func _enter_tree() -> void:
	EventSystem.HUD_hide_hud.connect(hide_hud)
	EventSystem.HUD_show_hud.connect(show_hud)
	EventSystem.PLA_freeze_player.connect(set_mobile_stats.bind(false))
	EventSystem.PLA_unfreeze_player.connect(set_mobile_stats.bind(true))


func _ready() -> void:
	hide_hud()


func hide_hud() -> void:
	hud.hide()


func show_hud() -> void:
	hud.show()
	if MobileInput.enabled:
		hud.get_node("MarginContainer/Hotbar").hide()
		var stats := hud.find_child("PlayerStatsContainer", true, false) as Control
		if stats.get_parent() != hud:
			stats.reparent(hud)
		stats.position = MobileInput.safe_rect.position + Vector2(24, 24)
		stats.visible = not MobileInput.frozen


func set_mobile_stats(show_stats: bool) -> void:
	if MobileInput.enabled and is_instance_valid(hud):
		var stats := hud.find_child("PlayerStatsContainer", true, false) as Control
		stats.visible = show_stats
