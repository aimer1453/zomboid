class_name QuestPanel
extends CanvasLayer

# ============================================================
# QuestPanel — 任务面板 (主线任务展示)
# ============================================================
# 底部"任务"按钮 → 打开当前角色的主线任务:
#   - 角色名 + 异能系列 + 背景故事
#   - 主线步骤: 已完成(绿)/进行中(黄)/未解锁(灰)
# 进度由 GameManager.story_progress 驱动 (共享里程碑推进)。

var _root: Control = null
var _bg: ColorRect = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _series_label: Label = null
var _bg_label: Label = null
var _quest_box: VBoxContainer = null


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_panel()


func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.55)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.gui_input.connect(_on_bg_input)
	_root.add_child(_bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -220
	_panel.offset_right = 220
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title_label)

	_series_label = Label.new()
	_series_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_series_label.add_theme_font_size_override("font_size", 14)
	_series_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	vbox.add_child(_series_label)

	_bg_label = Label.new()
	_bg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bg_label.add_theme_font_size_override("font_size", 13)
	_bg_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	_bg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_bg_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_quest_box = VBoxContainer.new()
	_quest_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_quest_box)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(280, 48)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

	_panel.add_child(vbox)
	_root.add_child(_panel)


func _refresh() -> void:
	var quest: Dictionary = GameManager.get_current_quest()
	_title_label.text = "主线任务 · " + quest.get("name", "")
	_series_label.text = quest.get("series", "")
	_bg_label.text = quest.get("background", "")
	var steps: Array = quest.get("steps", [])
	var current: int = int(quest.get("current", 0))
	for c in _quest_box.get_children():
		c.queue_free()
	for i in steps.size():
		var row := HBoxContainer.new()
		var mark := Label.new()
		var text := Label.new()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 14)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i < current:
			mark.text = "✓"
			mark.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
			text.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
		elif i == current:
			mark.text = "▶"
			mark.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
			text.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
		else:
			mark.text = "○"
			mark.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
			text.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
		mark.add_theme_font_size_override("font_size", 16)
		text.text = "%d. %s" % [i + 1, steps[i]]
		row.add_child(mark)
		row.add_child(text)
		_quest_box.add_child(row)


func _toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func open() -> void:
	_root.visible = true
	_refresh()


func close() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
