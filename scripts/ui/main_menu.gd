extends Control

# ============================================================
# MainMenu — 开始游戏界面 (手机 App 卡片化风格)
# ============================================================
# 设计参考: 顶部蓝色大圆角 Header + 白色内容大卡(内含彩色 tag 列表) + 橙色 FAB
# 配色/圆角/留白走 Palette 统一

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

var _selected_id: int = GameManager.CharacterID.SPECIAL_FORCE
var _rows: Dictionary = {}          # id -> PanelContainer (角色行)
var _detail_title: Label = null
var _detail_series: Label = null
var _detail_bg: Label = null
var _detail_tag: Label = null
var _fab: Button = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# 渐变背景 (深蓝顶 → 更深底)
	var bg := TextureRect.new()
	bg.texture = Palette.bg_gradient()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# === 顶部蓝色大圆角 Header (顶部超出屏不可见 → 只见底部圆角融入卡片) ===
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = -32   # 上沿出屏
	header.offset_bottom = 320
	header.offset_left = 0
	header.offset_right = 0
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Palette.HEADER_BG
	hsb.set_corner_radius_all(28)
	hsb.content_margin_left = 28
	hsb.content_margin_right = 28
	hsb.content_margin_top = 80
	hsb.content_margin_bottom = 24
	header.add_theme_stylebox_override("panel", hsb)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	header.add_child(hbox)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 4)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title_box)

	var t := Label.new()
	t.text = "末 日 生 存"
	t.add_theme_font_size_override("font_size", 38)
	t.add_theme_color_override("font_color", Palette.LIGHT)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	t.add_theme_constant_override("outline_size", 4)
	title_box.add_child(t)

	var sub := Label.new()
	sub.text = "选择你的幸存者"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	title_box.add_child(sub)

	# 右上角: 已解锁 X/5
	var prog := VBoxContainer.new()
	prog.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(prog)

	var prog_l := Label.new()
	prog_l.text = "%d / 5" % GameManager.unlocked_characters.size()
	prog_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog_l.add_theme_font_size_override("font_size", 22)
	prog_l.add_theme_color_override("font_color", Palette.LIGHT)
	prog.add_child(prog_l)

	var prog_s := Label.new()
	prog_s.text = "已解锁"
	prog_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prog_s.add_theme_font_size_override("font_size", 11)
	prog_s.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	prog.add_child(prog_s)

	# === 白色内容大卡 (与 header 底部圆角衔接) ===
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_top = 280   # 与 header 底部 ~280 重叠
	card.offset_bottom = -90 # 留底部导航栏
	card.offset_left = 16
	card.offset_right = -16
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
	add_child(card)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 10)
	cvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(cvbox)

	# 标题行 (左标题 + 右继续游戏按钮)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbox.add_child(top_row)

	var card_title := Label.new()
	card_title.text = "选择幸存者"
	card_title.add_theme_font_size_override("font_size", 22)
	card_title.add_theme_color_override("font_color", Palette.DARK)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(card_title)

	if GameManager.has_save():
		var cont := Button.new()
		cont.text = "继续游戏  ▶"
		cont.custom_minimum_size = Vector2(140, 36)
		cont.add_theme_font_size_override("font_size", 14)
		_style_pill(cont, Palette.BLUE)
		cont.pressed.connect(_on_continue)
		top_row.add_child(cont)

	# 角色列表 (每行一个 PanelContainer, 圆角 14, 可点击)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cvbox.add_child(list)
	for i in CHAR_ORDER.size():
		var id: int = CHAR_ORDER[i]
		var row := _make_role_row(id, AVATAR_COLORS[i])
		_rows[id] = row
		list.add_child(row)

	# 详情区 (选中行下方固定 ~130 高, 显示背景/任务)
	var detail := PanelContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, 130)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.93, 0.94, 0.96, 0.9)
	dsb.set_corner_radius_all(14)
	dsb.content_margin_left = 14
	dsb.content_margin_right = 14
	dsb.content_margin_top = 10
	dsb.content_margin_bottom = 10
	detail.add_theme_stylebox_override("panel", dsb)
	cvbox.add_child(detail)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(dv)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 16)
	_detail_title.add_theme_color_override("font_color", Palette.DARK)
	dv.add_child(_detail_title)

	_detail_series = Label.new()
	_detail_series.add_theme_font_size_override("font_size", 12)
	_detail_series.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	dv.add_child(_detail_series)

	_detail_bg = Label.new()
	_detail_bg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_bg.add_theme_font_size_override("font_size", 11)
	_detail_bg.add_theme_color_override("font_color", Color(0.30, 0.34, 0.42))
	dv.add_child(_detail_bg)

	# === 底部导航栏 ===
	var nav := PanelContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -76
	nav.offset_bottom = 0
	nav.offset_left = 0
	nav.offset_right = 0
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Palette.NAV_BG
	nsb.set_corner_radius_all(20)
	nsb.content_margin_left = 24
	nsb.content_margin_right = 24
	nsb.shadow_color = Palette.SHADOW
	nsb.shadow_size = 4
	nsb.shadow_offset = Vector2(0, -1)
	nav.add_theme_stylebox_override("panel", nsb)
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nav)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 0)
	nav_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_child(nav_hbox)
	for icon_name in ["日历", "时间", "角色"]:
		var icon_l := Label.new()
		icon_l.text = icon_name
		icon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_l.add_theme_font_size_override("font_size", 13)
		icon_l.add_theme_color_override("font_color", Palette.NAV_ICON_DIM)
		icon_l.custom_minimum_size = Vector2(120, 40)
		icon_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_hbox.add_child(icon_l)

	# === 橙色 FAB (右下角, 浮动在导航栏之上) ===
	_fab = Button.new()
	_fab.text = "▶"
	_fab.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fab.offset_left = -84
	_fab.offset_right = -24
	_fab.offset_top = -158
	_fab.offset_bottom = -98
	_fab.custom_minimum_size = Vector2(60, 60)
	_fab.add_theme_font_size_override("font_size", 24)
	_fab.add_theme_color_override("font_color", Palette.LIGHT)
	_style_fab(_fab)
	_fab.pressed.connect(_on_start)
	add_child(_fab)

	_select(GameManager.CharacterID.SPECIAL_FORCE)


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

	# Avatar 圆 (用 ColorRect 模拟)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(52, 52)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var avsb := StyleBoxFlat.new()
	avsb.bg_color = avatar_color
	avsb.set_corner_radius_all(26)
	avsb.content_margin_left = 0
	avsb.content_margin_right = 0
	avsb.content_margin_top = 0
	avsb.content_margin_bottom = 0
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

	# 文本 VBox
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

	# 状态 tag (胶囊)
	var tag := PanelContainer.new()
	tag.custom_minimum_size = Vector2(78, 28)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var unlocked: bool = GameManager.is_character_unlocked(id)
	var tag_sb := StyleBoxFlat.new()
	tag_sb.bg_color = Palette.ORANGE if unlocked else Palette.TAG_BG_LOCK
	tag_sb.set_corner_radius_all(14)
	tag_sb.content_margin_left = 12
	tag_sb.content_margin_right = 12
	tag_sb.content_margin_top = 4
	tag_sb.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", tag_sb)
	hbox.add_child(tag)

	var tag_l := Label.new()
	tag_l.text = "已解锁" if unlocked else "🔒"
	tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_l.add_theme_font_size_override("font_size", 12)
	tag_l.add_theme_color_override("font_color", Palette.LIGHT if unlocked else Palette.LIGHT)
	tag_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tag.add_child(tag_l)

	return row


func _on_row_gui_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(id)


## 行样式: 未选灰白, 选中浅橙白 + 左侧 4px 橙色条
func _apply_row_style(row: PanelContainer, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	if selected:
		sb.bg_color = Palette.CARD_LIGHT_ROW_SEL
		sb.border_color = Palette.ORANGE
		sb.border_width_left = 4
		sb.border_width_top = 0
		sb.border_width_right = 0
		sb.border_width_bottom = 0
	else:
		sb.bg_color = Palette.CARD_LIGHT_ROW
		sb.border_color = Color(0, 0, 0, 0)
		sb.border_width_left = 0
		sb.border_width_top = 0
		sb.border_width_right = 0
		sb.border_width_bottom = 0
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Palette.SHADOW
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 1)
	row.add_theme_stylebox_override("panel", sb)


## 胶囊按钮 (继续游戏): 透明底+蓝色边框
func _style_pill(b: Button, accent: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		match state:
			"normal":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = accent
			"hover":
				sb.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
			"pressed":
				sb.bg_color = Color(accent.r, accent.g, accent.b, 0.32)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(18)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", Palette.ORANGE)
	b.add_theme_color_override("font_pressed_color", Palette.ORANGE)


## FAB (主 CTA): 橙色填充, 圆 + 阴影
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
	# 刷新所有行样式
	for cid in _rows.keys():
		_apply_row_style(_rows[cid], cid == _selected_id)
	# 刷新详情
	var profile: Dictionary = GameManager.get_character_profile(id)
	_detail_title.text = GameManager.get_character_name(id) + " — " + str(profile.get("main_quest", []).size()) + " 步主线"
	_detail_series.text = GameManager.get_character_series(id)
	_detail_bg.text = GameManager.get_character_background(id)
	# FAB 启用条件
	_fab.disabled = not GameManager.is_character_unlocked(id)


func _on_continue() -> void:
	GameManager.load_game()


func _on_start() -> void:
	if not GameManager.is_character_unlocked(_selected_id):
		return
	GameManager.start_new_game(_selected_id)