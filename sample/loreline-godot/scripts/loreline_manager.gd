extends Control

# Loreline runtime
var loreline: Loreline = Loreline.shared()

# Node references
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var output_table: HBoxContainer = $ScrollContainer/MarginContainer/OutputTable
@onready var content_column: VBoxContainer = $ScrollContainer/MarginContainer/OutputTable/ContentColumn
@onready var keeper_column: Control = $ScrollContainer/MarginContainer/OutputTable/KeeperColumn

# Fonts
var font_regular: Font
var font_semibold: Font
var font_italic: Font

# State
var script_data: LorelineScript
var bottom_spacer: Control

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
const LINE_SPACING := 16
const CHOICE_SPACING := 8
const SECTION_SPACING := 18
const FADE_DURATION := 0.45
const SCROLL_MIN_DURATION := 0.25
const SCROLL_MAX_DURATION := 0.6
const DIALOGUE_DELAY := 0.6
const CHOICE_DELAY := 0.5
const TOP_PADDING := 30
const BOTTOM_PADDING := 200


func _ready() -> void:
	font_regular = load("res://fonts/Outfit-Regular.ttf")
	font_semibold = load("res://fonts/Outfit-SemiBold.ttf")
	font_italic = load("res://fonts/Literata-Italic.ttf")
	if font_regular == null or font_semibold == null or font_italic == null:
		var err := "Loreline sample: missing font files in res://fonts/ (Outfit-Regular.ttf, Outfit-SemiBold.ttf, Literata-Italic.ttf)"
		push_error(err)
		printerr(err)
		return

	# Remove default ScrollContainer panel padding
	scroll_container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# Style scrollbar — thin, subtle
	var scrollbar := scroll_container.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 7
	var grabber_style := StyleBoxFlat.new()
	grabber_style.bg_color = BORDER_COLOR
	grabber_style.set_corner_radius_all(2)
	scrollbar.add_theme_stylebox_override("grabber", grabber_style)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber_style)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber_style)
	var scroll_bg := StyleBoxEmpty.new()
	scrollbar.add_theme_stylebox_override("scroll", scroll_bg)

	script_data = loreline.parse("res://story/CoffeeShop.lor")
	if script_data == null:
		var err := "Loreline sample: failed to parse res://story/CoffeeShop.lor"
		push_error(err)
		printerr(err)
		return

	# To override how files are loaded (e.g. encrypted files, network, etc.),
	# you can load the source manually and provide a file handler for imports:
	#
	# var file := FileAccess.open("res://story/CoffeeShop.lor", FileAccess.READ)
	# var source := _decrypt(file.get_buffer(file.get_length()))
	# file.close()
	# script_data = loreline.parse(source, "res://story/CoffeeShop.lor", _handle_file)
	#
	# See _handle_file() below for the file handler example.

	_start_story()


func _start_story() -> void:
	# Clear previous content
	for child in content_column.get_children():
		child.queue_free()
	keeper_column.custom_minimum_size.y = 0

	# Top padding spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size.y = TOP_PADDING
	content_column.add_child(top_spacer)

	# Bottom padding spacer (kept at end of content column)
	bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size.y = BOTTOM_PADDING
	content_column.add_child(bottom_spacer)

	loreline.play(script_data, _on_dialogue, _on_choice, _on_finished)


# --- Signal Handlers ---

func _on_dialogue(interp: LorelineInterpreter, character: String, text: String, _tags: Array, advance: Callable) -> void:
	# Add spacing before new dialogue if content exists (> 2 because of top_spacer + bottom_spacer)
	if content_column.get_child_count() > 2:
		var spacer := Control.new()
		spacer.custom_minimum_size.y = LINE_SPACING
		_add_content(spacer)

	if character != "":
		# Resolve display name
		var display_name: String = interp.get_character_field(character, "name")
		if display_name != "":
			character = display_name

		# Character name + dialogue on same line (matching Unity/web)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.add_theme_font_override("normal_font", font_regular)
		label.add_theme_font_override("bold_font", font_semibold)
		label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
		label.add_theme_font_size_override("bold_font_size", FONT_SIZE)
		label.add_theme_color_override("default_color", TEXT_COLOR)
		label.text = "[b]" + _gradient_bbcode(character + " : ") + "[/b]" + text
		_add_content(label)
		_fade_in(label)
	else:
		# Narrative text — italic, muted
		var text_label := Label.new()
		text_label.text = text
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.add_theme_font_override("font", font_italic)
		text_label.add_theme_font_size_override("font_size", FONT_SIZE)
		text_label.add_theme_color_override("font_color", TEXT_MUTED)
		_add_content(text_label)
		_fade_in(text_label)

	_update_keeper()
	_smooth_scroll_to_bottom()

	# Auto-advance after delay (matching Unity/web)
	await get_tree().create_timer(DIALOGUE_DELAY).timeout
	advance.call()


func _on_choice(_interp: LorelineInterpreter, options: Array, select: Callable) -> void:
	# Delay before showing choices (matching Unity/web)
	await get_tree().create_timer(CHOICE_DELAY).timeout

	# Add spacing
	var spacer := Control.new()
	spacer.custom_minimum_size.y = SECTION_SPACING
	_add_content(spacer)

	var choices_container := VBoxContainer.new()
	choices_container.add_theme_constant_override("separation", CHOICE_SPACING)
	_add_content(choices_container)

	for i in range(options.size()):
		var option: Dictionary = options[i]
		var enabled: bool = option["enabled"]
		if not enabled:
			continue

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

		# Disabled style (same dimensions as normal to prevent layout shift on disable)
		var disabled_style := style.duplicate()
		btn.add_theme_stylebox_override("disabled", disabled_style)
		btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)

		# Text colors
		btn.add_theme_color_override("font_color", TEXT_COLOR)
		btn.add_theme_color_override("font_hover_color", TEXT_COLOR)
		btn.add_theme_color_override("font_pressed_color", TEXT_COLOR)

		var index := i
		var container_ref := choices_container
		btn.pressed.connect(_on_choice_selected.bind(index, btn, container_ref, select))

		choices_container.add_child(btn)

		# Fade in all buttons simultaneously
		btn.modulate.a = 0
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(btn, "modulate:a", 1.0, FADE_DURATION)

	_update_keeper()
	_smooth_scroll_to_bottom()


func _on_choice_selected(index: int, selected_btn: Button, container: VBoxContainer, select: Callable) -> void:
	# Prevent double-clicks
	for child in container.get_children():
		if child is Button:
			child.disabled = true

	# Phase 1 (0ms): Highlight selected, fade out others
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

	for child in container.get_children():
		if child is Button and child != selected_btn:
			var fade := create_tween()
			fade.tween_property(child, "modulate:a", 0.0, 0.25)

	# Phase 2 (300ms): Slide selected button to top of container
	await get_tree().create_timer(0.3).timeout
	var offset: float = selected_btn.global_position.y - container.global_position.y
	if offset > 0:
		var slide := create_tween()
		slide.set_ease(Tween.EASE_IN_OUT)
		slide.set_trans(Tween.TRANS_CUBIC)
		slide.tween_property(selected_btn, "position:y", selected_btn.position.y - offset, 0.35)

	# Phase 3 (700ms): Hide others, reset position, continue
	await get_tree().create_timer(0.4).timeout
	for child in container.get_children():
		if child is Button and child != selected_btn:
			child.visible = false
	# Reset position offset — VBox now places button at top, so net visual change is zero
	selected_btn.position.y = 0

	select.call(index)


func _on_finished(_interp: LorelineInterpreter) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = SECTION_SPACING * 2
	_add_content(spacer)

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
	_add_content(center)

	_fade_in(center)
	_update_keeper()
	_smooth_scroll_to_bottom()


# File handler example for custom loading (encrypted files, network, etc.):
# func _handle_file(path: String) -> String:
# 	var f := FileAccess.open(path, FileAccess.READ)
# 	if f == null: return ""
# 	return _decrypt(f.get_buffer(f.get_length()))


# --- Helpers ---

func _add_content(node: Control) -> void:
	content_column.add_child(node)
	content_column.move_child(bottom_spacer, -1)


func _fade_in(node: Control) -> void:
	node.modulate.a = 0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(node, "modulate:a", 1.0, FADE_DURATION)


func _update_keeper() -> void:
	await get_tree().process_frame
	var content_height := content_column.size.y
	if content_height > keeper_column.custom_minimum_size.y:
		keeper_column.custom_minimum_size.y = content_height


func _smooth_scroll_to_bottom() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scrollbar := scroll_container.get_v_scroll_bar()
	var target: float = scrollbar.max_value - scrollbar.page
	var current: float = scroll_container.scroll_vertical
	if target <= current + 1.0:
		return
	var dist: float = target - current
	var duration: float = clampf(dist * 0.0012, SCROLL_MIN_DURATION, SCROLL_MAX_DURATION)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(scroll_container, "scroll_vertical", int(target), duration)


func _gradient_bbcode(text: String) -> String:
	# 3-stop gradient matching Unity/web: #ff5eab → #8b5cf6 → #56a0f6
	var r0 := 255.0; var g0 := 94.0;  var b0 := 171.0  # #ff5eab (pink)
	var r1 := 139.0; var g1 := 92.0;  var b1 := 246.0  # #8b5cf6 (purple)
	var r2 := 86.0;  var g2 := 160.0; var b2 := 246.0  # #56a0f6 (blue)
	var t_min := 0.30
	var t_max := 0.70
	var result := ""
	var text_len := text.length()
	for i in range(text_len):
		var t: float = 0.4 if text_len <= 1 else t_min + (t_max - t_min) * float(i) / float(text_len - 1)
		var r: float; var g: float; var b: float
		if t <= 0.4:
			var s := t / 0.4
			r = r0 + (r1 - r0) * s
			g = g0 + (g1 - g0) * s
			b = b0 + (b1 - b0) * s
		else:
			var s := (t - 0.4) / 0.6
			r = r1 + (r2 - r1) * s
			g = g1 + (g2 - g1) * s
			b = b1 + (b2 - b1) * s
		var hex := "%02x%02x%02x" % [roundi(r), roundi(g), roundi(b)]
		result += "[color=#" + hex + "]" + text[i] + "[/color]"
	return result
