class_name DeathScreen
extends CanvasLayer

# ============================================================
# DeathScreen — 死亡结算界面 ("你死了" + 重新开始 / 读档)
# ============================================================
# 由 GameManager.game_over() 在主角死亡时弹出。
# 暂停游戏树后显示, 自身 process_mode=ALWAYS 保证暂停期间按钮仍可点击。
# 两个选项:
#   重新开始 → GameManager.restart_from_death() (开新游戏)
#   读档     → GameManager.load_from_death()    (读最后一次存档)

var _panel: PanelContainer = null
var _reason_label: Label = null
var _load_btn: Button = null


func _ready() -> void:
	# 高于一切 UI (hud=60 / container_ui&action_menu=100 / item_action_menu=200)
	layer = 300
	# 暂停游戏树期间本界面仍可接收输入 (按钮可点)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide_screen()


func _build_ui() -> void:
	# 全屏暗化遮罩: 拦截点击, 防止点到背后 UI
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.1, 0.11, 0.98)
	sb.border_color = Color(0.75, 0.22, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 34
	sb.content_margin_bottom = 34
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "你 死 了"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.92, 0.26, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_reason_label = Label.new()
	_reason_label.add_theme_font_size_override("font_size", 16)
	_reason_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.88))
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_reason_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 28)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var restart_btn := Button.new()
	restart_btn.text = "重新开始"
	restart_btn.custom_minimum_size = Vector2(190, 58)
	restart_btn.add_theme_font_size_override("font_size", 23)
	restart_btn.pressed.connect(_on_restart)
	btn_row.add_child(restart_btn)

	_load_btn = Button.new()
	_load_btn.text = "读档"
	_load_btn.custom_minimum_size = Vector2(190, 58)
	_load_btn.add_theme_font_size_override("font_size", 23)
	_load_btn.pressed.connect(_on_load)
	btn_row.add_child(_load_btn)


## 显示死亡界面
## reason: 死因(可选, 空则不显示); can_load: 是否有存档(决定读档按钮可用性)
func show_screen(reason: String, can_load: bool) -> void:
	if reason != "":
		_reason_label.text = reason
		_reason_label.visible = true
	else:
		_reason_label.visible = false
	_load_btn.disabled = not can_load
	visible = true


func hide_screen() -> void:
	visible = false


func _on_restart() -> void:
	if GameManager and GameManager.has_method("restart_from_death"):
		GameManager.restart_from_death()


func _on_load() -> void:
	# 打开存档读档面板选槽 (面板内部会处理隐藏死亡屏 + 读档)
	var slp := get_tree().current_scene.find_child("SaveLoadPanel", true, false) if get_tree() else null
	if slp and slp.has_method("open"):
		slp.open()
	elif GameManager and GameManager.has_method("load_from_death"):
		# 兜底: 面板不存在时走旧逻辑
		GameManager.load_from_death()
