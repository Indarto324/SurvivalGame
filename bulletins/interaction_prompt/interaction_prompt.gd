extends Bulletin
class_name InteractionPrompt


@onready var label: Label = $Label


var prompt_text := ""


func initialize(prompt) -> void:
	if prompt is String:
		prompt_text = ("Tap Interact\n" if MobileInput.enabled else "E\n") + prompt


func _ready() -> void:
	if MobileInput.enabled:
		label.custom_minimum_size.x = 320
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
	label.text = prompt_text

