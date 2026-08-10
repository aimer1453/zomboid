extends Control

# ============================================================
# MainMenu — 主页面 → 角色选择 (两阶段, 带过渡动画)
# ============================================================
# 主页面: 居中大标题 + [新的开始] [继续游戏]
# 点"新的开始": 标题平移缩小到左上角, 角色选择卡片上滑入场,
#             继续游戏隐藏, 左上出现 [‹ 返回] 可回主页面

const CHAR_ORDER := [
	GameManager.CharacterID.SPECIAL_FORCE,
	GameManager.CharacterID.HUNTER,
	GameManager.CharacterID.DOCTOR,
	GameManager.CharacterID.ELECTRICIAN,
	GameManager.CharacterID.PSYCHIC,
]
const AVATAR_COLORS := [
	Color("#4E7D96"),  # SPECIAL_FORCE 蓝
	Color("#FF844B"),  # HUNTER 橙
	Color("#7FB069"),  # DOCTOR 绿
	Color("#D4A85A"),  # ELECTRICIAN 黄
	Color("#9B7BB8"),  # PSYCHIC 紫
]

var _state := "home"  # home | select

# 主页面元素
var _title: Label = null
var _home_btns: VBoxContainer = null

# 选择界面元素
var _select_root: Control = null
var _back_btn: Button = null

var _selected_id: int = GameManager.CharacterID.SPECIAL_FORCE
var _rows: Dictionary = {}
var _detail_title: Label = null
var _detail_status: Label = null  # 解锁状态行 (已解锁/未解锁+条件)
var _detail_series: Label = null
var _detail_bg: Label = null
var _detail_quest: VBoxContainer = null
var _prog_label: Label = null
var _fab: Button = null

var TITLE_HOME_POS := Vector2(0, 500)  # 主页面居中 (x 按文字宽度运行时算)
const TITLE_SELECT_POS := Vector2(28, 52)  # select 态: 靠左对齐 (与副标题/返回同左缘)
const TITLE_HOME_FONT := 52
const TITLE_SELECT_SCALE := 0.5


func _ready() -> void:
	_build_ui()
	# 等一帧让 Label 完成布局, 计算居中位置
	await get_tree().process_frame
	_title.pivot_offset = _title.size / 2.0
	TITLE_HOME_POS.x = (720.0 - _title.size.x) / 2.0
	_title.position = TITLE_HOME_POS


func _build_ui() -> void:
	# 主页背景: header 同色浅蓝 (#4E7D96) — 点新开始时这个蓝向上滑, 形成 select 界面 header 上半部分
	var bg := ColorRect.new()
	bg.color = Palette.HEADER_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ============ 主页面: 居中大标题 + 两个主按钮 ============
	_title = Label.new()
	_title.text = "末 日 生 存"
	_title.add_theme_font_size_override("font_size", TITLE_HOME_FONT)
	# home 态: 配色深蓝 #4E7D96 (深色渐变背景上醒目); select 态由过渡切白字 (蓝 header 上可见)
	_title.add_theme_color_override("font_color", Palette.BLUE)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("outline_size", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.z_index = 10
	add_child(_title)

	_home_btns = VBoxContainer.new()
	_home_btns.add_theme_constant_override("separation", 18)
	_home_btns.set_anchors_preset(Control.PRESET_CENTER)
	_home_btns.offset_left = -180
	_home_btns.offset_right = 180
	_home_btns.offset_top = 150
	_home_btns.offset_bottom = 330
	_home_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_home_btns)

	var new_btn := Button.new()
	new_btn.text = "▶  新的开始"
	new_btn.custom_minimum_size = Vector2(0, 66)
	new_btn.add_theme_font_size_override("font_size", 22)
	UiStyle.apply_button(new_btn, UiStyle.cta_button_states())
	new_btn.pressed.connect(_transition_select)
	_home_btns.add_child(new_btn)

	if GameManager.has_save():
		var cont := Button.new()
		cont.text = "继续游戏"
		cont.custom_minimum_size = Vector2(0, 60)
		cont.add_theme_font_size_override("font_size", 20)
		UiStyle.apply_button(cont, UiStyle.pill_button_states(Palette.BLUE))
		cont.pressed.connect(_on_continue)
		_home_btns.add_child(cont)

	# ============ 选择界面 (初始整体下移+透明, 由动画滑入) ============
	_select_root = Control.new()
	_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_root.visible = false  # home 态不可见 → 完全不参与鼠标拾取
	_select_root.modulate.a = 1.0
	_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_root.position.y = 180  # 初始在屏外下方, 动画从这上移到 0
	add_child(_select_root)

	_build_select_ui(_select_root)

	# 返回按钮 (左上角, 初始透明)
	_back_btn = Button.new()
	_back_btn.text = "‹ 返回"
	_back_btn.custom_minimum_size = Vector2(96, 44)
	_back_btn.position = Vector2(28, 20)  # 左缘与标题/副标题对齐 x=28
	_back_btn.add_theme_font_size_override("font_size", 16)
	# 按钮内文字靠左 (与标题/副标题同左缘对齐)
	_back_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiStyle.apply_button(_back_btn, UiStyle.pill_button_states(Palette.LIGHT))
	_back_btn.modulate.a = 0.0
	_back_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE  # home 态透明不拦截
	_back_btn.z_index = 20
	_back_btn.pressed.connect(_transition_home)
	add_child(_back_btn)


func _build_select_ui(root: Control) -> void:
	# 顶部蓝色大圆角 Header (顶部出屏 → 只见底部圆角)
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = -32
	header.offset_bottom = 320
	header.offset_left = 0
	header.offset_right = 0
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Palette.HEADER_BG
	hsb.set_corner_radius_all(28)
	hsb.content_margin_left = 28
	hsb.content_margin_right = 28
	hsb.content_margin_top = 90
	hsb.content_margin_bottom = 24
	header.add_theme_stylebox_override("panel", hsb)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	header.add_child(hbox)

	var sub := Label.new()
	sub.text = "选择你的幸存者"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # 靠左 (与左上角标题/返回同左缘)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(sub)

	# 右上角: 当前选中序号 / 总数 (跟随选中变化)
	var prog := VBoxContainer.new()
	prog.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(prog)

	var prog_l := Label.new()
	prog_l.text = "%d / 5" % (CHAR_ORDER.find(_selected_id) + 1)
	prog_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog_l.add_theme_font_size_override("font_size", 22)
	prog_l.add_theme_color_override("font_color", Palette.LIGHT)
	prog.add_child(prog_l)
	_prog_label = prog_l

	var prog_s := Label.new()
	prog_s.text = "选择序号"
	prog_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog_s.add_theme_font_size_override("font_size", 11)
	prog_s.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	prog.add_child(prog_s)

	# 白色内容大卡
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_top = 280
	card.offset_bottom = -20
	card.offset_left = 16
	card.offset_right = -16
	# 关键: home 态下 card 透明(modulate 0)但默认 STOP 会拦截下方主按钮点击!
	# card 本体 IGNORE, 交互交给内部角色行(各自 STOP) — 透明时不挡, 显示时可点
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var csb := StyleBoxFlat.new()
	csb.bg_color = Palette.CARD_LIGHT_BG
	csb.set_corner_radius_all(24)
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	csb.content_margin_top = 18
	csb.content_margin_bottom = 14
	csb.shadow_color = Palette.SHADOW
	csb.shadow_size = 6
	csb.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", csb)
	root.add_child(card)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 10)
	cvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(cvbox)

	var card_title := Label.new()
	card_title.text = "选择幸存者"
	card_title.add_theme_font_size_override("font_size", 22)
	card_title.add_theme_color_override("font_color", Palette.DARK)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.add_child(card_title)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 列表自然高度 (5×80+间距), 剩余空间全给详情区
	cvbox.add_child(list)
	for i in CHAR_ORDER.size():
		var id: int = CHAR_ORDER[i]
		var row := _make_role_row(id, AVATAR_COLORS[i])
		_rows[id] = row
		list.add_child(row)

	# 详情区: 撑满列表下方剩余空间 (覆盖下面大部分区域), 字号加大
	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, 260)
	detail.add_theme_stylebox_override("panel", UiStyle.light_panel(14, 16))
	cvbox.add_child(detail)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(dv)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 26)
	_detail_title.add_theme_color_override("font_color", Palette.DARK)
	dv.add_child(_detail_title)

	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 15)
	_detail_status.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	dv.add_child(_detail_status)

	_detail_series = Label.new()
	_detail_series.add_theme_font_size_override("font_size", 16)
	_detail_series.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	dv.add_child(_detail_series)

	_detail_bg = Label.new()
	_detail_bg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_bg.add_theme_font_size_override("font_size", 15)
	_detail_bg.add_theme_color_override("font_color", Color(0.28, 0.32, 0.40))
	dv.add_child(_detail_bg)

	var qlabel := Label.new()
	qlabel.text = "主线任务"
	qlabel.add_theme_font_size_override("font_size", 16)
	qlabel.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	dv.add_child(qlabel)

	_detail_quest = VBoxContainer.new()
	_detail_quest.add_theme_constant_override("separation", 4)
	_detail_quest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_quest)

	# 橙色 FAB (开始游戏)
	_fab = Button.new()
	_fab.text = "▶"
	_fab.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fab.offset_left = -92
	_fab.offset_right = -32
	_fab.offset_top = -92
	_fab.offset_bottom = -32
	_fab.add_theme_font_size_override("font_size", 24)
	_fab.add_theme_color_override("font_color", Palette.LIGHT)
	_fab.mouse_filter = Control.MOUSE_FILTER_IGNORE  # home 态透明不拦截, 进入 select 由动画回调恢复
	_style_fab(_fab)
	_fab.pressed.connect(_on_start)
	root.add_child(_fab)

	_select(GameManager.CharacterID.SPECIAL_FORCE)


## 主页面 → 选择: 标题平移缩小到左上, 蓝色 header + 白色卡片从底部上移入场 (纯滑入无淡入),
##                 继续游戏隐藏, 返回按钮出现
func _transition_select() -> void:
	if _state == "select":
		return
	_state = "select"
	# select_root 从屏外下方 (y=180) 整体上移到位 — 无淡入, 纯滑入
	_select_root.visible = true
	_select_root.modulate.a = 1.0
	_select_root.position.y = 180.0
	_title.pivot_offset = _title.size / 2.0
	# select 态: 标题切白字 + 深描边 (在蓝色 header 上可见)
	_title.add_theme_color_override("font_color", Palette.LIGHT)
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.10, 0.8))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title, "position", TITLE_SELECT_POS, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "scale", Vector2(TITLE_SELECT_SCALE, TITLE_SELECT_SCALE), 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_home_btns, "modulate:a", 0.0, 0.28)
	# select_root (含 header 蓝头 + 白色卡) 从屏外下方上移到位
	tw.tween_property(_select_root, "position:y", 0.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_back_btn, "modulate:a", 1.0, 0.3)
	tw.chain().tween_callback(func() -> void:
		_home_btns.visible = false
		_back_btn.mouse_filter = Control.MOUSE_FILTER_STOP)


## 选择 → 主页面 (返回) — select_root 滑出屏外下方 (无淡出)
func _transition_home() -> void:
	if _state == "home":
		return
	_state = "home"
	_home_btns.visible = true
	_home_btns.modulate.a = 0.0
	_back_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# home 态: 标题切回配色深蓝
	_title.add_theme_color_override("font_color", Palette.BLUE)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title, "position", TITLE_HOME_POS, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_home_btns, "modulate:a", 1.0, 0.3)
	tw.tween_property(_select_root, "position:y", 180.0, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_back_btn, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func() -> void:
		_select_root.visible = false)


## 角色列表行: 圆形 avatar + 名字 + 系列 + 状态 tag + 整行可点击
func _make_role_row(id: int, avatar_color: Color) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 80)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_gui_input.bind(id))
	_apply_row_style(row, false)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hbox)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(52, 52)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var avsb := StyleBoxFlat.new()
	avsb.bg_color = avatar_color
	avsb.set_corner_radius_all(26)
	avatar.add_theme_stylebox_override("panel", avsb)
	hbox.add_child(avatar)

	var initial := Label.new()
	initial.text = GameManager.get_character_name(id).substr(0, 1)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 22)
	initial.add_theme_color_override("font_color", Palette.LIGHT)
	initial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	initial.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar.add_child(initial)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(tv)

	var name_l := Label.new()
	name_l.text = GameManager.get_character_name(id)
	name_l.add_theme_font_size_override("font_size", 17)
	name_l.add_theme_color_override("font_color", Palette.DARK)
	tv.add_child(name_l)

	var series_l := Label.new()
	series_l.text = GameManager.get_character_series(id)
	series_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	series_l.add_theme_font_size_override("font_size", 11)
	series_l.add_theme_color_override("font_color", Color(0.40, 0.45, 0.52))
	tv.add_child(series_l)

	# 状态用行底色区分 (无文字 tag): 已解锁=偏白 / 未解锁=偏一点蓝
	var unlocked: bool = GameManager.is_character_unlocked(id)
	row.set_meta("unlocked", unlocked)
	_apply_row_style(row, false, unlocked)

	return row


func _on_row_gui_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(id)


func _apply_row_style(row: PanelContainer, selected: bool, unlocked: bool = true) -> void:
	var sb := StyleBoxFlat.new()
	if selected:
		sb.bg_color = Palette.CARD_LIGHT_ROW_SEL
		sb.border_color = Palette.ORANGE
		sb.border_width_left = 4
	elif unlocked:
		# 已解锁: 偏白底色
		sb.bg_color = Palette.CARD_LIGHT_ROW
		sb.border_color = Color(0, 0, 0, 0)
		sb.border_width_left = 0
	else:
		# 未解锁: 偏一点点蓝的底色 (淡蓝 #E3EDF2)
		sb.bg_color = Color("#E3EDF2")
		sb.border_color = Color(0, 0, 0, 0)
		sb.border_width_left = 0
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	row.add_theme_stylebox_override("panel", sb)


func _style_fab(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		match state:
			"normal":
				sb.bg_color = Palette.ORANGE
			"hover":
				sb.bg_color = Color("#FFA070")
			"pressed":
				sb.bg_color = Color("#E3682C")
			"disabled":
				sb.bg_color = Color(0.30, 0.35, 0.42)
		sb.set_corner_radius_all(30)
		sb.shadow_color = Palette.SHADOW
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Palette.LIGHT)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.65))


func _select(id: int) -> void:
	_selected_id = id
	if _prog_label:
		_prog_label.text = "%d / 5" % (CHAR_ORDER.find(_selected_id) + 1)
	for cid in _rows.keys():
		var row: PanelContainer = _rows[cid]
		var unlocked: bool = bool(row.get_meta("unlocked", true))
		_apply_row_style(row, cid == _selected_id, unlocked)
	var profile: Dictionary = GameManager.get_character_profile(id)
	_detail_title.text = GameManager.get_character_name(id)
	_detail_series.text = GameManager.get_character_series(id)
	_detail_bg.text = GameManager.get_character_background(id)
	# 状态行: 已解锁=绿色文字"● 已解锁"; 未解锁=橙色文字"🔒 未解锁 — 条件"
	var unlocked: bool = GameManager.is_character_unlocked(id)
	if unlocked:
		_detail_status.text = "●  已解锁"
		_detail_status.add_theme_color_override("font_color", Color(0.30, 0.65, 0.40))
		_fab.text = "▶"
		_fab.disabled = false
	else:
		_detail_status.text = "🔒  未解锁 — " + GameManager.get_unlock_hint(id)
		_detail_status.add_theme_color_override("font_color", Palette.ORANGE)
		_fab.text = "🔒"
		_fab.disabled = true
	for c in _detail_quest.get_children():
		c.queue_free()
	var steps: Array = GameManager.get_character_quest(id)
	for i in mini(steps.size(), 4):
		var s := Label.new()
		s.text = "•  " + str(steps[i])
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", Color(0.28, 0.32, 0.40))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_detail_quest.add_child(s)


func _on_continue() -> void:
	GameManager.load_game()


func _on_start() -> void:
	if not GameManager.is_character_unlocked(_selected_id):
		return
	GameManager.start_new_game(_selected_id)