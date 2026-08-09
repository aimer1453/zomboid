class_name AbilityTreeUI
extends CanvasLayer

# ============================================================
# AbilityTreeUI — 异能树界面 (Phase 5)
# ============================================================
# 右上角"异能"按钮 → 打开当前角色异能树:
#   - 技能点余额 + 吸收晶石按钮
#   - 异能按 tier 分组显示 (名称/描述/消耗/状态)
#   - 点击可学异能 → 学习 (消耗技能点)
# 学到的施放型异能自动出现在战斗动作菜单。

var _btn: Button = null
var _root: Control = null
var _bg: ColorRect = null
var _panel: PanelContainer = null
var _points_label: Label = null
var _list: VBoxContainer = null

## tier → 颜色
const TIER_COLORS := {
	1: Color(0.4, 0.8, 0.45),
	2: Color(0.4, 0.6, 0.9),
	3: Color(0.95, 0.8, 0.25),
}


func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 按钮已移到 HUD 底部按钮栏 (统一: 背包/异能/存档)
	_build_panel()


# --- 右上角按钮 (背包按钮左侧) ---

func _build_button() -> void:
	_btn = Button.new()
	_btn.text = "异能"
	_btn.custom_minimum_size = Vector2(84, 84)
	_btn.add_theme_font_size_override("font_size", 20)
	_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_btn.offset_left = -192
	_btn.offset_top = 16
	_btn.offset_right = -108
	_btn.offset_bottom = 100
	_btn.pressed.connect(_toggle)
	add_child(_btn)


# --- 异能树面板 ---

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
	# 完全居中 (屏幕正中): 四锚点都在 0.5, 上下/左右偏移都对称 → 水平和垂直都居中
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# 水平: 左右偏移对称 (offset_right = -offset_left) → 水平居中
	# 垂直: 上下偏移对称 (offset_bottom = -offset_top) → 垂直居中
	# 之前用 PRESET_CENTER_BOTTOM 只做了水平居中, 垂直仍贴底部 → 用户反馈"只左右居中没上下居中"
	_panel.offset_left = -200    # 面板宽 400 (左右对称 → 水平居中)
	_panel.offset_right = 200
	# 面板高 680 (上下对称 → 垂直居中); 必须 >= 内容最小高度(~628), 否则被 min_size 撑开导致居中偏移
	_panel.offset_top = -340
	_panel.offset_bottom = 340
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.97)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "异能树"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# 技能点 + 吸收
	var point_row := HBoxContainer.new()
	point_row.add_theme_constant_override("separation", 8)
	point_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_points_label = Label.new()
	_points_label.text = "技能点: 0"
	_points_label.add_theme_font_size_override("font_size", 18)
	point_row.add_child(_points_label)
	var absorb_btn := Button.new()
	absorb_btn.text = "吸收晶石"
	absorb_btn.custom_minimum_size = Vector2(140, 46)
	absorb_btn.add_theme_font_size_override("font_size", 14)
	absorb_btn.pressed.connect(_on_absorb)
	point_row.add_child(absorb_btn)
	vbox.add_child(point_row)

	# 提示
	var hint := Label.new()
	hint.text = "学习异能需要技能点 · 前置等级需先学"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	vbox.add_child(hint)

	# 异能列表 (可滚动)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	vbox.add_child(scroll)

	# 关闭
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(280, 52)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

	_panel.add_child(vbox)
	_root.add_child(_panel)


# --- 刷新异能列表 ---

func _refresh() -> void:
	var player := TurnManager.get_player()
	var points: int = player.get("skill_points") if player else 0
	_points_label.text = "技能点: %d" % points

	for c in _list.get_children():
		c.queue_free()

	if not player:
		return

	var abilities := DataManager.get_abilities_for_character(int(GameManager.current_character))
	for entry in abilities:
		var ability_id: String = entry["id"]
		var data: Dictionary = entry["data"]
		var learned: bool = player.has_ability(ability_id) if player.has_method("has_ability") else false
		var tier: int = int(data.get("tier", 1))
		var cost: int = int(data.get("cost", 1))
		var unlockable: bool = DataManager.ability_unlockable(ability_id, player.get_learned_ids()) if player.has_method("get_learned_ids") else false
		var can_afford: bool = points >= cost
		var passive: bool = bool(data.get("passive", false))

		var row := _make_ability_row(ability_id, data, tier, cost, passive, learned, unlockable, can_afford)
		_list.add_child(row)


func _make_ability_row(ability_id: String, data: Dictionary, tier: int, cost: int,
		passive: bool, learned: bool, unlockable: bool, can_afford: bool) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if learned:
		sb.bg_color = Color(0.12, 0.35, 0.15, 0.9)
		sb.border_color = Color(0.3, 0.85, 0.35)
	elif unlockable and can_afford:
		sb.bg_color = Color(0.15, 0.2, 0.32, 0.9)
		sb.border_color = TIER_COLORS.get(tier, Color.WHITE)
	else:
		sb.bg_color = Color(0.15, 0.15, 0.18, 0.9)
		sb.border_color = Color(0.32, 0.32, 0.38)
	sb.set_border_width_all(2)
	row.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name_l := Label.new()
	name_l.text = data.get("name", ability_id)
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", TIER_COLORS.get(tier, Color.WHITE))
	head.add_child(name_l)
	var tag := Label.new()
	var tag_text := "T%d" % tier
	if passive:
		tag_text += " · 被动"
	tag.text = tag_text
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	head.add_child(tag)
	head.add_child(Label.new())  # 占位
	var cost_l := Label.new()
	cost_l.text = "已学" if learned else "%d 点" % cost
	cost_l.add_theme_font_size_override("font_size", 13)
	cost_l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5) if learned else Color(0.95, 0.8, 0.3))
	head.add_child(cost_l)
	box.add_child(head)

	var desc_l := Label.new()
	desc_l.text = data.get("desc", "")
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.add_theme_font_size_override("font_size", 12)
	desc_l.add_theme_color_override("font_color", Color(0.82, 0.82, 0.86))
	box.add_child(desc_l)

	if not learned:
		var learn_btn := Button.new()
		if unlockable and can_afford:
			learn_btn.text = "学习"
			learn_btn.add_theme_font_size_override("font_size", 14)
			learn_btn.pressed.connect(_on_learn.bind(ability_id))
		else:
			learn_btn.text = "无法学习"
			learn_btn.disabled = true
			learn_btn.add_theme_font_size_override("font_size", 12)
		learn_btn.custom_minimum_size = Vector2(0, 40)
		box.add_child(learn_btn)

	row.add_child(box)
	return row


# --- 交互 ---

func _on_learn(ability_id: String) -> void:
	var player := TurnManager.get_player()
	if player and player.has_method("learn_ability"):
		player.learn_ability(ability_id)
	_refresh()


func _on_absorb() -> void:
	var player := TurnManager.get_player()
	if player and player.has_method("absorb_crystal"):
		player.absorb_crystal()
	_refresh()


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
