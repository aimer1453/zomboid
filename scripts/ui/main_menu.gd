extends Control

# ============================================================
# MainMenu — 开始游戏界面 (手机竖屏, 用户配色 + 渐变)
# ============================================================

const CHAR_ORDER := [
	GameManager.CharacterID.SPECIAL_FORCE,
	GameManager.CharacterID.HUNTER,
	GameManager.CharacterID.DOCTOR,
	GameManager.CharacterID.ELECTRICIAN,
	GameManager.CharacterID.PSYCHIC,
]

var _selected_id: int = GameManager.CharacterID.SPECIAL_FORCE
var _cards: Dictionary = {}
var _detail_title: Label = null
var _detail_series: Label = null
var _detail_bg: Label = null
var _detail_quest: VBoxContainer = null
var _start_btn: Button = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# 渐变背景: 深蓝顶 → 更深底 (呼应 Palette.BG_TOP/BG_BOTTOM)
	var bg := TextureRect.new()
	bg.texture = Palette.bg_gradient()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 顶部强调条: 橙→浅蓝 渐变, 提升视觉重量
	var accent := TextureRect.new()
	accent.texture = Palette.accent_gradient()
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.offset_left = 0
	accent.offset_right = 0
	accent.offset_top = 0
	accent.offset_bottom = 5
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 40
	vbox.offset_right = -40
	vbox.offset_top = 36
	vbox.offset_bottom = -32
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	# 标题: 橙色 (Palette.ORANGE) 大字 + 描边
	var title := Label.new()
	title.text = "末 日 生 存"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Palette.TITLE_FONT)
	title.add_theme_color_override("font_color", Palette.ORANGE)
	title.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.12, 0.9))
	title.add_theme_constant_override("outline_size", 5)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "选择你的幸存者"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", Palette.SUBTITLE_FONT)
	sub.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(sub)

	# 继续游戏 (有档时): 圆角 + 蓝色边框 + hover 变亮
	if GameManager.has_save():
		var cont := Button.new()
		cont.text = "继续游戏"
		cont.custom_minimum_size = Vector2(220, 44)
		cont.add_theme_font_size_override("font_size", Palette.BUTTON_FONT)
		_style_button_secondary(cont)
		cont.pressed.connect(_on_continue)
		vbox.add_child(cont)

	# 角色卡片 2 列网格
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)
	for id in CHAR_ORDER:
		var card := _make_card(id)
		_cards[id] = card
		grid.add_child(card)

	# 详情面板: 圆角 + 蓝色边框 + 半透明深色背景
	var detail := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Palette.PANEL_BG
	dsb.border_color = Palette.PANEL_BORDER
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(14)
	dsb.content_margin_left = 18
	dsb.content_margin_right = 18
	dsb.content_margin_top = 14
	dsb.content_margin_bottom = 14
	detail.add_theme_stylebox_override("panel", dsb)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(detail)

	var dvbox := VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 6)
	dvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(dvbox)

	_detail_title = Label.new()
	_detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_title.add_theme_font_size_override("font_size", Palette.DETAIL_TITLE_FONT)
	_detail_title.add_theme_color_override("font_color", Palette.LIGHT)
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_title)

	_detail_series = Label.new()
	_detail_series.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_series.add_theme_font_size_override("font_size", 13)
	_detail_series.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	_detail_series.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_series)

	_detail_bg = Label.new()
	_detail_bg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_bg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_bg.add_theme_font_size_override("font_size", Palette.DETAIL_TEXT_FONT)
	_detail_bg.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
	_detail_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_bg)

	var qlabel := Label.new()
	qlabel.text = "主线任务"
	qlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	qlabel.add_theme_font_size_override("font_size", 14)
	qlabel.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	qlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(qlabel)

	_detail_quest = VBoxContainer.new()
	_detail_quest.add_theme_constant_override("separation", 3)
	_detail_quest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_detail_quest)

	# 开始按钮: 橙色填充 (CTA 强视觉) + 深色字 + 大字号
	_start_btn = Button.new()
	_start_btn.text = "开始游戏"
	_start_btn.custom_minimum_size = Vector2(240, 54)
	_start_btn.add_theme_font_size_override("font_size", Palette.BUTTON_BIG_FONT)
	_style_button_primary(_start_btn)
	_start_btn.pressed.connect(_on_start)
	vbox.add_child(_start_btn)

	_select(GameManager.CharacterID.SPECIAL_FORCE)


## 主按钮: 橙色填充 + 深色文字 (CALL TO ACTION)
func _style_button_primary(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		match state:
			"normal":
				sb.bg_color = Palette.ORANGE
				sb.border_color = Color("#FFB07A")
			"hover":
				sb.bg_color = Color("#FFA070")
				sb.border_color = Palette.LIGHT
			"pressed":
				sb.bg_color = Color("#E3682C")
				sb.border_color = Palette.LIGHT
			"disabled":
				sb.bg_color = Color(0.30, 0.35, 0.42)
				sb.border_color = Color(0.20, 0.25, 0.30)
			_:
				sb.bg_color = Palette.ORANGE
				sb.border_color = Color("#FFB07A")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Palette.DARK)
	b.add_theme_color_override("font_hover_color", Palette.DARK)
	b.add_theme_color_override("font_pressed_color", Palette.LIGHT)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.65))


## 次按钮 (继续游戏): 透明填充 + 蓝色边框 + 浅色文字 + hover 浅蓝填充
func _style_button_secondary(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		match state:
			"normal":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = Palette.BLUE
			"hover":
				sb.bg_color = Color(Palette.BLUE.r, Palette.BLUE.g, Palette.BLUE.b, 0.18)
				sb.border_color = Palette.LIGHT
			"pressed":
				sb.bg_color = Color(Palette.BLUE.r, Palette.BLUE.g, Palette.BLUE.b, 0.30)
				sb.border_color = Palette.LIGHT
			_:
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = Color(0.32, 0.42, 0.55)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Palette.LIGHT)
	b.add_theme_color_override("font_hover_color", Palette.ORANGE)
	b.add_theme_color_override("font_pressed_color", Palette.ORANGE)


func _make_card(id: int) -> Button:
	var unlocked: bool = GameManager.is_character_unlocked(id)
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_font_size_override("font_size", 15)
	card.pressed.connect(_select.bind(id))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_l := Label.new()
	name_l.text = GameManager.get_character_name(id)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", Palette.CARD_NAME_FONT)
	name_l.add_theme_color_override("font_color", Palette.LIGHT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(name_l)

	var series_l := Label.new()
	series_l.text = GameManager.get_character_series(id)
	series_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	series_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	series_l.add_theme_font_size_override("font_size", Palette.CARD_SERIES_FONT)
	series_l.add_theme_color_override("font_color", Palette.TEXT_SECONDARY)
	series_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(series_l)

	if unlocked:
		var tag := Label.new()
		tag.text = "● 已解锁"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", Palette.CARD_TAG_FONT)
		tag.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55))
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(tag)
	else:
		var lock := Label.new()
		lock.text = "🔒 未解锁"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.add_theme_font_size_override("font_size", Palette.CARD_TAG_FONT)
		lock.add_theme_color_override("font_color", Palette.ORANGE)
		lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(lock)
		var hint := Label.new()
		hint.text = GameManager.get_unlock_hint(id)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(hint)

	card.add_child(col)
	return card


func _select(id: int) -> void:
	_selected_id = id
	# 刷新卡片边框: 选中=橙边+亮蓝背景, 其他=暗蓝边+深蓝背景
	for cid in _cards.keys():
		var card: Button = _cards[cid]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		if cid == _selected_id:
			sb.bg_color = Palette.CARD_BG_SEL
			sb.border_color = Palette.CARD_BORDER_SEL
			sb.set_border_width_all(3)
		else:
			sb.bg_color = Palette.CARD_BG_UNSEL
			sb.border_color = Palette.CARD_BORDER_UNSEL
			sb.set_border_width_all(1)
		card.add_theme_stylebox_override("normal", sb)
		# hover/pressed 也用相近 (选中橙边 hover 略亮)
		var hsb := sb.duplicate()
		if cid == _selected_id:
			hsb.bg_color = Color(0.22, 0.30, 0.42, 0.98)
			hsb.border_color = Color("#FFB07A")
		else:
			hsb.bg_color = Color(0.16, 0.20, 0.30, 0.92)
			hsb.border_color = Color(0.40, 0.52, 0.68)
		card.add_theme_stylebox_override("hover", hsb)
		var psb := sb.duplicate()
		if cid == _selected_id:
			psb.bg_color = Color(0.14, 0.20, 0.28, 1.0)
		else:
			psb.bg_color = Color(0.08, 0.10, 0.16, 0.95)
		card.add_theme_stylebox_override("pressed", psb)
	# 详情
	var profile: Dictionary = GameManager.get_character_profile(id)
	_detail_title.text = GameManager.get_character_name(id)
	_detail_series.text = GameManager.get_character_series(id)
	_detail_bg.text = GameManager.get_character_background(id)
	for c in _detail_quest.get_children():
		c.queue_free()
	var steps: Array = GameManager.get_character_quest(id)
	for i in steps.size():
		var s := Label.new()
		s.text = "%d. %s" % [i + 1, steps[i]]
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		s.add_theme_font_size_override("font_size", 13)
		s.add_theme_color_override("font_color", Palette.TEXT_PRIMARY)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_detail_quest.add_child(s)
	_start_btn.disabled = not GameManager.is_character_unlocked(id)


func _on_continue() -> void:
	GameManager.load_game()


func _on_start() -> void:
	if not GameManager.is_character_unlocked(_selected_id):
		return
	GameManager.start_new_game(_selected_id)