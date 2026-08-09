class_name SaveLoadPanel
extends CanvasLayer

# ============================================================
# SaveLoadPanel — 统一存档/读档多槽位管理界面
# ============================================================
# HUD 底部"存档读档"按钮 / 死亡界面"读档"按钮 → 打开此面板.
# 显示 3 个存档槽, 每槽可存/读/删. 空槽只能存, 有档才能读/删.
# 存档写入当前游戏状态到选中槽; 读档从选中槽加载并切场景.

const SLOT_COUNT := 3

var _root: Control = null
var _bg: ColorRect = null
var _panel: PanelContainer = null
var _slot_containers: Array[Control] = []  # 每槽的 UI 容器


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_panel()


func _build_panel() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.6)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.gui_input.connect(_on_bg_input)
	_root.add_child(_bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -240
	_panel.offset_right = 240
	_panel.offset_top = -300
	_panel.offset_bottom = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.98)
	sb.border_color = Color(0.6, 0.6, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# 标题
	var title := Label.new()
	title.text = "存档 / 读档"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "选择一个存档槽位进行操作"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	vbox.add_child(hint)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 3 个槽位
	for slot_idx in range(SLOT_COUNT):
		var slot_ui := _build_slot_row(slot_idx)
		_slot_containers.append(slot_ui)
		vbox.add_child(slot_ui)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(440, 44)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

	_panel.add_child(vbox)
	_root.add_child(_panel)


## 构建单个槽位的 UI 行
func _build_slot_row(slot_idx: int) -> Control:
	var row := PanelContainer.new()
	var row_sb := StyleBoxFlat.new()
	row_sb.bg_color = Color(0.18, 0.19, 0.22, 0.9)
	row_sb.set_corner_radius_all(8)
	row_sb.content_margin_left = 12
	row_sb.content_margin_right = 12
	row_sb.content_margin_top = 10
	row_sb.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", row_sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	# 左侧: 槽号 + 信息
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := Label.new()
	header.text = "存档 %d" % [slot_idx + 1]
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	info_vbox.add_child(header)

	var detail := Label.new()
	detail.name = "detail_label"
	detail.text = "— 空槽 —"
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_child(detail)

	hbox.add_child(info_vbox)

	# 右侧: 操作按钮
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 6)

	var save_btn := Button.new()
	save_btn.text = "存档"
	save_btn.custom_minimum_size = Vector2(70, 34)
	save_btn.add_theme_font_size_override("font_size", 13)
	save_btn.pressed.connect(_on_save.bind(slot_idx))
	btn_hbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.name = "load_btn"
	load_btn.text = "读档"
	load_btn.custom_minimum_size = Vector2(70, 34)
	load_btn.add_theme_font_size_override("font_size", 13)
	load_btn.pressed.connect(_on_load.bind(slot_idx))
	btn_hbox.add_child(load_btn)

	var del_btn := Button.new()
	del_btn.name = "del_btn"
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(70, 34)
	del_btn.add_theme_font_size_override("font_size", 13)
	del_btn.pressed.connect(_on_delete.bind(slot_idx))
	btn_hbox.add_child(del_btn)

	hbox.add_child(btn_hbox)
	row.add_child(hbox)
	return row


## 刷新所有槽位显示 (打开时调用)
func _refresh_slots() -> void:
	for slot_idx in range(SLOT_COUNT):
		var container: Control = _slot_containers[slot_idx]
		var detail: Label = container.get_node_or_null("detail_label")
		var load_btn: Button = container.get_node_or_null("load_btn")
		var del_btn: Button = container.get_node_or_null("del_btn")

		if DataManager.save_exists(slot_idx):
			var data: Dictionary = DataManager.load_from_slot(slot_idx)
			if not data.is_empty():
				var char_id: int = data.get("character", 0)
				var char_name: String = GameManager.get_character_name(char_id) if GameManager else "未知"
				detail.text = "角色: %s" % char_name
				if load_btn:
					load_btn.disabled = false
				if del_btn:
					del_btn.disabled = false
			else:
				detail.text = "— 数据损坏 —"
				if load_btn:
					load_btn.disabled = true
				if del_btn:
					del_btn.disabled = false
		else:
			detail.text = "— 空槽 —"
			if load_btn:
				load_btn.disabled = true
			if del_btn:
				del_btn.disabled = true


func open() -> void:
	_refresh_slots()
	_root.visible = true


func close() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func _toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


## 存档到指定槽
func _on_save(slot_idx: int) -> void:
	if not GameManager:
		return
	var ok: bool = GameManager.save_game_slot(slot_idx)
	if ok:
		_refresh_slots()
		print("[SaveLoadPanel] 存档成功: 槽 ", slot_idx + 1)
	else:
		print("[SaveLoadPanel] 存档失败: 槽 ", slot_idx + 1)


## 从指定槽读档
func _on_load(slot_idx: int) -> void:
	if not GameManager or not DataManager.save_exists(slot_idx):
		return
	close()
	# 如果是从死亡界面打开的, 先隐藏死亡屏再读档
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		GameManager.hide_death_screen()
	GameManager.load_game_slot(slot_idx)


## 删除指定槽存档
func _on_delete(slot_idx: int) -> void:
	DataManager.delete_slot(slot_idx)
	_refresh_slots()
	print("[SaveLoadPanel] 已删除存档: 槽 ", slot_idx + 1)
