extends Control

# ============================================================
# MainMenu — 开始游戏界面: 选择角色 / 继续游戏
# ============================================================
# - 标题 + 继续游戏(有档时)
# - 角色卡片网格: 已解锁可选, 锁定显示成就提示
# - 选中角色展示背景故事 + 主线任务预览
# - 开始游戏 → GameManager.start_new_game(selected)

const CHAR_ORDER := [
	GameManager.CharacterID.SPECIAL_FORCE,
	GameManager.CharacterID.HUNTER,
	GameManager.CharacterID.DOCTOR,
	GameManager.CharacterID.ELECTRICIAN,
	GameManager.CharacterID.PSYCHIC,
]

var _selected_id: int = GameManager.CharacterID.SPECIAL_FORCE
var _cards: Dictionary = {}        # id -> Button(卡片)
var _detail_title: Label = null
var _detail_series: Label = null
var _detail_bg: Label = null
var _detail_quest: VBoxContainer = null
var _start_btn: Button = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# 暗色背景
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 竖屏居中列 (720x1280 设计分辨率, 手机习惯: 顶部标题 → 角色网格 → 详情 → 开始)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 40
	vbox.offset_right = -40
	vbox.offset_top = 32
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title := Label.new()
	title.text = "末 日 生 存"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "选择你的幸存者"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(sub)

	# 继续游戏 (有档时)
	if GameManager.has_save():
		var cont := Button.new()
		cont.text = "继续游戏"
		cont.custom_minimum_size = Vector2(220, 44)
		cont.add_theme_font_size_override("font_size", 18)
		cont.pressed.connect(_on_continue)
		vbox.add_child(cont)

	# 角色卡片网格: 2 列 (5 卡 → 3 行, 手机习惯; 720 宽 - 边距 80 = 640, 每卡 ~306)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	for id in CHAR_ORDER:
		var card := _make_card(id)
		_cards[id] = card
		grid.add_child(card)

	# 详情面板
	var detail := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.1, 0.11, 0.15, 0.95)
	dsb.border_color = Color(0.4, 0.4, 0.5)
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(12)
	dsb.content_margin_left = 18
	dsb.content_margin_right = 18
	dsb.content_margin_top = 12
	dsb.content_margin_bottom = 12
	detail.add_theme_stylebox_override("panel", dsb)
	# 详情面板: 水平撑满 vbox (vbox 宽 = 720 - 80 边距 = 640), 垂直继续扩展填剩余空间
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(detail)

	var dvbox := VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 6)
	dvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 占满 Panel 内部宽
	detail.add_child(dvbox)

	_detail_title = Label.new()
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.add_theme_font_size_override("font_size", 22)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_title)

	_detail_series = Label.new()
	_detail_series.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_series.add_theme_font_size_override("font_size", 13)
	_detail_series.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	_detail_series.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_series)

	_detail_bg = Label.new()
	_detail_bg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_bg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_bg.add_theme_font_size_override("font_size", 13)
	_detail_bg.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	_detail_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_bg)

	var qlabel := Label.new()
	qlabel.text = "主线任务"
	qlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	qlabel.add_theme_font_size_override("font_size", 14)
	qlabel.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	qlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(qlabel)

	_detail_quest = VBoxContainer.new()
	_detail_quest.add_theme_constant_override("separation", 3)
	_detail_quest.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 任务列表也撑满
	dvbox.add_child(_detail_quest)

	# 开始按钮
	_start_btn = Button.new()
	_start_btn.text = "开始游戏"
	_start_btn.custom_minimum_size = Vector2(240, 52)
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.pressed.connect(_on_start)
	vbox.add_child(_start_btn)

	# 默认选中第一个已解锁角色
	_select(GameManager.CharacterID.SPECIAL_FORCE)


func _make_card(id: int) -> Button:
	var unlocked: bool = GameManager.is_character_unlocked(id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_font_size_override("font_size", 15)
	card.pressed.connect(_select.bind(id))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)

	var name_l := Label.new()
	name_l.text = GameManager.get_character_name(id)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 19)
	col.add_child(name_l)

	var series_l := Label.new()
	series_l.text = GameManager.get_character_series(id)
	series_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	series_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	series_l.add_theme_font_size_override("font_size", 11)
	series_l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	col.add_child(series_l)

	if unlocked:
		var tag := Label.new()
		tag.text = "● 已解锁"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		col.add_child(tag)
	else:
		var lock := Label.new()
		lock.text = "🔒 未解锁"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", 12)
		lock.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
		col.add_child(lock)
		var hint := Label.new()
		hint.text = GameManager.get_unlock_hint(id)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
		col.add_child(hint)

	card.add_child(col)
	return card


func _select(id: int) -> void:
	_selected_id = id
	# 刷新卡片边框 (选中=亮边, 其他=暗边)
	for cid in _cards.keys():
		var card: Button = _cards[cid]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		if cid == _selected_id:
			sb.bg_color = Color(0.16, 0.2, 0.28, 1.0)
			sb.border_color = Color(0.95, 0.8, 0.3)
			sb.set_border_width_all(3)
		else:
			sb.bg_color = Color(0.12, 0.13, 0.17, 1.0)
			sb.border_color = Color(0.3, 0.3, 0.38)
			sb.set_border_width_all(1)
		card.add_theme_stylebox_override("normal", sb)
	# 详情
	var profile: Dictionary = GameManager.get_character_profile(id)
	_detail_title.text = GameManager.get_character_name(id)
	_detail_series.text = GameManager.get_character_series(id)
	_detail_bg.text = GameManager.get_character_background(id)
	# 主线步骤
	for c in _detail_quest.get_children():
		c.queue_free()
	var steps: Array = GameManager.get_character_quest(id)
	for i in steps.size():
		var s := Label.new()
		s.text = "%d. %s" % [i + 1, steps[i]]
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # 占满任务列表列宽
		_detail_quest.add_child(s)
	# 开始按钮可用性
	_start_btn.disabled = not GameManager.is_character_unlocked(id)


func _on_continue() -> void:
	GameManager.load_game()


func _on_start() -> void:
	if not GameManager.is_character_unlocked(_selected_id):
		return
	GameManager.start_new_game(_selected_id)
