extends Node

func _ready() -> void:
	call_deferred("verify")

func verify() -> void:
	var tools := get_tree().root.get_node("DeveloperTools")
	var mobile := get_tree().root.get_node("MobileInput")
	var ok: bool = not tools.available() and tools.panel == null
	# Even direct calls and a forged player cannot bypass the runtime gate.
	var player := Player.new()
	tools.player = player
	tools.invincible = true
	tools.unlimited_needs = true
	tools.flying = true
	tools.speed_multiplier = 3.0
	ok = ok and not tools.damage_protected() and not tools.needs_protected() and not tools.is_flying() and tools.movement_multiplier() == 1.0
	ok = ok and not tools.set_cheat("invincible",true) and tools.give_item(ItemConfig.Keys.Axe,1) == 0 and not tools.recover()
	mobile.configure_layout(Rect2(0,0,1920,1080))
	ok = ok and not mobile.buttons.has("developer") and not mobile.buttons.has("fly_up")
	tools.player = null
	player.free()
	print("DEVELOPER GATE: ", "PASS" if ok else "FAIL", " debug=",OS.is_debug_build()," editor=",OS.has_feature("editor"))
	get_tree().quit(0 if ok else 1)
