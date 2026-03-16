extends Control

# Node references
@onready var runtime: LorelineRuntime = $LorelineRuntime
@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var output_table: HBoxContainer = $MarginContainer/ScrollContainer/OutputTable
@onready var content_column: VBoxContainer = $MarginContainer/ScrollContainer/OutputTable/ContentColumn
@onready var keeper_column: Control = $MarginContainer/ScrollContainer/OutputTable/KeeperColumn

# Fonts
var font_regular: Font
var font_semibold: Font
var font_italic: Font

# State
var script_data: LorelineScript
var interpreter: LorelineInterpreter
var waiting_for_click: bool = false
var click_prompt: Label = null

# Colors
const BG_COLOR := Color("#19171f")
const TEXT_COLOR := Color("#f0eef5")
const TEXT_MUTED := Color("#c0bdd0")
const TEXT_DIM := Color("#6b6580")
const ACCENT_PURPLE := Color("#8b5cf6")
const BORDER_COLOR := Color("#2e2a3a")
const BORDER_HOVER := Color("#8b5cf6")
const GLOW_BG := Color(0.545, 0.361, 0.965, 0.1)
const CHOICE_BG := Color("#15131b")

# Sizing
const FONT_SIZE := 16
const CHOICE_FONT_SIZE := 15
const LINE_SPACING := 12
const CHOICE_SPACING := 8
const SECTION_SPACING := 18
const FADE_DURATION := 0.45
const SCROLL_MIN_DURATION := 0.25
const SCROLL_MAX_DURATION := 0.6


func _ready() -> void:
	font_regular = load("res://fonts/Outfit-Regular.ttf")
	font_semibold = load("res://fonts/Outfit-SemiBold.ttf")
	font_italic = load("res://fonts/Literata-Italic.ttf")

	var file := FileAccess.open("res://story/CoffeeShop.lor", FileAccess.READ)
	var source := file.get_as_text()
	file.close()
	script_data = runtime.parse(source, "res://story/CoffeeShop.lor")
	_start_story()


func _start_story() -> void:
	# Clear previous content
	for child in content_column.get_children():
		child.queue_free()
	keeper_column.custom_minimum_size.y = 0
	waiting_for_click = false
	click_prompt = null

	interpreter = script_data.play("")
	interpreter.dialogue.connect(_on_dialogue)
	interpreter.choice.connect(_on_choice)
	interpreter.finished.connect(_on_finished)


func _input(event: InputEvent) -> void:
	if waiting_for_click:
		if event is InputEventMouseButton and event.pressed:
			_advance_dialogue()
		elif event is InputEventKey and event.pressed:
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				_advance_dialogue()


func _advance_dialogue() -> void:
	waiting_for_click = false
	if click_prompt and is_instance_valid(click_prompt):
		click_prompt.queue_free()
		click_prompt = null
	interpreter.advance()


# --- Signal Handlers ---

func _on_dialogue(character: String, text: String, _tags: Array) -> void:
	# Add spacing before new dialogue if content exists
	if content_column.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = LINE_SPACING
		content_column.add_child(spacer)

	var line_container := VBoxContainer.new()
	content_column.add_child(line_container)

	if character != "":
		# Character name label
		var char_label := RichTextLabel.new()
		char_label.bbcode_enabled = true
		char_label.fit_content = true
		char_label.scroll_active = false
		char_label.add_theme_font_override("bold_font", font_semibold)
		char_label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
		char_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
		char_label.text = "[b][color=#8b5cf6]" + character + "[/color][/b]"
		line_container.add_child(char_label)

	# Dialogue text label
	var text_label := Label.new()
	text_label.text = text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_override("font", font_regular)
	text_label.add_theme_font_size_override("font_size", FONT_SIZE)
	if character == "":
		# Narrative text (no character) — italic, muted
		text_label.add_theme_font_override("font", font_italic)
		text_label.add_theme_color_override("font_color", TEXT_MUTED)
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		text_label.add_theme_color_override("font_color", TEXT_COLOR)
	line_container.add_child(text_label)

	# Fade in
	_fade_in(line_container)

	# Show click prompt
	_show_click_prompt()

	# Scroll to bottom
	_update_keeper()
	_smooth_scroll_to_bottom()


func _on_choice(options: Array) -> void:
	# Add spacing
	var spacer := Control.new()
	spacer.custom_minimum_size.y = SECTION_SPACING
	content_column.add_child(spacer)

	var choices_container := VBoxContainer.new()
	choices_container.add_theme_constant_override("separation", CHOICE_SPACING)
	content_column.add_child(choices_container)

	for i in range(options.size()):
		var option: Dictionary = options[i]
		var enabled: bool = option["enabled"]
		var btn := Button.new()
		btn.text = option["text"]
		btn.add_theme_font_override("font", font_regular)
		btn.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		# Style the button
		var style := StyleBoxFlat.new()
		style.bg_color = CHOICE_BG
		style.border_color = BORDER_COLOR
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(10)
		style.content_margin_left = 14
		style.content_margin_right = 14
		btn.add_theme_stylebox_override("normal", style)

		# Hover style
		var hover_style := style.duplicate()
		hover_style.border_color = BORDER_HOVER
		hover_style.bg_color = GLOW_BG
		btn.add_theme_stylebox_override("hover", hover_style)

		# Pressed style
		var pressed_style := style.duplicate()
		pressed_style.border_color = ACCENT_PURPLE
		pressed_style.bg_color = Color(GLOW_BG.r, GLOW_BG.g, GLOW_BG.b, 0.2)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		# Disabled style
		var disabled_style := style.duplicate()
		disabled_style.bg_color = Color(CHOICE_BG.r, CHOICE_BG.g, CHOICE_BG.b, 0.5)
		btn.add_theme_stylebox_override("disabled", disabled_style)

		# Text colors
		btn.add_theme_color_override("font_color", TEXT_COLOR)
		btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
		btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)
		btn.add_theme_color_override("font_disabled_color", TEXT_DIM)

		if not enabled:
			btn.disabled = true
		else:
			var index := i
			var container_ref := choices_container
			btn.pressed.connect(_on_choice_selected.bind(index, btn, container_ref))

		choices_container.add_child(btn)

		# Staggered fade in
		btn.modulate.a = 0
		btn.position.y += 8
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(btn, "modulate:a", 1.0, FADE_DURATION).set_delay(i * 0.08)
		tween.parallel().tween_property(btn, "position:y", 0.0, FADE_DURATION).set_delay(i * 0.08)

	_update_keeper()
	_smooth_scroll_to_bottom()


func _on_choice_selected(index: int, selected_btn: Button, container: VBoxContainer) -> void:
	# Disable all buttons immediately
	for child in container.get_children():
		if child is Button:
			child.disabled = true
			if child != selected_btn:
				# Fade out non-selected
				var tween := create_tween()
				tween.tween_property(child, "modulate:a", 0.0, 0.3)
				tween.tween_callback(child.queue_free)

	# Highlight selected
	var highlight_style := StyleBoxFlat.new()
	highlight_style.bg_color = Color(GLOW_BG.r, GLOW_BG.g, GLOW_BG.b, 0.15)
	highlight_style.border_color = ACCENT_PURPLE
	highlight_style.set_border_width_all(1)
	highlight_style.set_corner_radius_all(8)
	highlight_style.set_content_margin_all(10)
	highlight_style.content_margin_left = 14
	highlight_style.content_margin_right = 14
	selected_btn.add_theme_stylebox_override("disabled", highlight_style)
	selected_btn.add_theme_color_override("font_disabled_color", TEXT_COLOR)

	# Wait then select
	await get_tree().create_timer(0.4).timeout
	interpreter.select(index)


func _on_finished() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = SECTION_SPACING * 2
	content_column.add_child(spacer)

	# Restart button
	var btn := Button.new()
	btn.text = "Restart"
	btn.add_theme_font_override("font", font_regular)
	btn.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = CHOICE_BG
	style.border_color = ACCENT_PURPLE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate()
	hover_style.bg_color = GLOW_BG
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", ACCENT_PURPLE)
	btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
	btn.pressed.connect(_start_story)

	var center := CenterContainer.new()
	center.add_child(btn)
	content_column.add_child(center)

	_fade_in(center)
	_update_keeper()
	_smooth_scroll_to_bottom()


# --- Helpers ---

func _fade_in(node: Control) -> void:
	node.modulate.a = 0
	var original_y := node.position.y
	node.position.y += 4
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 1.0, FADE_DURATION)
	tween.parallel().tween_property(node, "position:y", original_y, FADE_DURATION)


func _show_click_prompt() -> void:
	waiting_for_click = true
	click_prompt = Label.new()
	click_prompt.text = "\u25bc"
	click_prompt.add_theme_font_override("font", font_regular)
	click_prompt.add_theme_font_size_override("font_size", 10)
	click_prompt.add_theme_color_override("font_color", TEXT_DIM)
	click_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	content_column.add_child(spacer)
	content_column.add_child(click_prompt)

	# Blink animation
	_blink_prompt()


func _blink_prompt() -> void:
	if not is_instance_valid(click_prompt):
		return
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(click_prompt, "modulate:a", 0.0, 0.5)
	tween.tween_property(click_prompt, "modulate:a", 1.0, 0.5)


func _update_keeper() -> void:
	await get_tree().process_frame
	var content_height := content_column.size.y
	if content_height > keeper_column.custom_minimum_size.y:
		keeper_column.custom_minimum_size.y = content_height


func _smooth_scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var target: float = scroll_container.get_v_scroll_bar().max_value
	var current: int = scroll_container.scroll_vertical
	var dist: float = absf(target - current)
	var duration: float = clampf(dist * 0.002, SCROLL_MIN_DURATION, SCROLL_MAX_DURATION)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(scroll_container, "scroll_vertical", int(target), duration)
