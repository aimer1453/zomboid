class_name HUD
extends CanvasLayer

# ============================================================
# HUD — 手机 HUD (右上角背包按钮 + 双页面: 背包 / 装备)
# ============================================================
# 背包页: 4x4=16 格, 每种物品占 1 格(可堆叠)。装备类物品可拖拽。
# 装备页: 武器 / 防具 / 背包 三个装备槽, 拖拽穿戴, 点击卸下。
# 负重条 + 物品色块网格 + 关闭。点全屏遮罩或关闭按钮退出。

# --- 内部类: 背包格 (可拖拽) ---

class InvSlot extends PanelContainer:
	var item_id: String = ""
	var item_count: int = 0
	var hud: CanvasLayer = null  # 拖放回调引用 (HUD 本体)

	func _get_drag_data(at_position: Vector2) -> Variant:
		if item_id == "":
			return null
		# 拖拽预览
		var preview := Label.new()
		preview.text = str(item_count) if item_count > 1 else item_id
		preview.add_theme_font_size_override("font_size", 14)
		preview.custom_minimum_size = Vector2(70, 40)
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var panel := PanelContainer.new()
		panel.add_child(preview)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.3, 0.3, 0.4, 0.9)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		set_drag_preview(panel)
		return {"type": "inv_item", "item_id": item_id}

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		# 接收拖放: 装备槽拖回的物品 (卸下), 或普通背包物品 (无操作兜底)
		return data is Dictionary and data.get("type", "") == "inv_item"

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		# 装备槽拖回背包 → 卸下
		var from_slot: String = data.get("from_slot", "")
		if from_slot != "" and hud and hud.has_method("_on_bag_drop"):
			hud._on_bag_drop(from_slot)

	## 点击背包格子 → 弹通用操作菜单 (食用/穿戴/详情/丢弃, 按物品类型生成)
	## 与容器格子共用 ItemActionMenu, 架构统一
	func _gui_input(event: InputEvent) -> void:
		if item_id == "":
			return
		if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			if hud and hud.has_method("_open_inv_menu"):
				hud._open_inv_menu(item_id, self)

	## 更新格子内容 (icon + 名称 + 数量 垂直堆叠, 边框色 = 稀有度)
	func update_view(info: Dictionary, is_empty: bool, color: Color) -> void:
		for c in get_children():
			c.queue_free()
		var cell_style := StyleBoxFlat.new()
		cell_style.set_corner_radius_all(6)
		if is_empty:
			item_id = ""
			item_count = 0
			cell_style.bg_color = Color(0.18, 0.18, 0.22, 0.6)
			cell_style.border_color = Color(0.3, 0.3, 0.35)
			cell_style.set_border_width_all(1)
		else:
			item_id = info.get("item_id", "")
			item_count = int(info.get("count", 1))
			# 背景: 统一深色 (与尸体/容器搜刮界面完全一致), 边框=稀有度颜色 → 两套格子同一套显示规则
			cell_style.bg_color = Color(0.16, 0.16, 0.2, 0.9)
			# 边框 = 稀有度颜色 (2px, 与容器搜刮界面一致)
			var rarity: int = int(info.get("rarity", 0))
			var rarity_color: Color = DataManager.RARITY_COLORS.get(rarity, Color(0.62, 0.62, 0.62)) if DataManager else Color(0.62, 0.62, 0.62)
			cell_style.border_color = rarity_color
			cell_style.set_border_width_all(2)
			var is_trash: bool = DataManager != null and rarity == DataManager.Rarity.TRASH
			if is_trash:
				# 废料档: 更薄更暗的低级框 + 更平的背景, 视觉上明显"低人一等"
				cell_style.set_border_width_all(1)
				cell_style.set_corner_radius_all(3)
				cell_style.bg_color = Color(0.13, 0.13, 0.16, 0.9)

			# 消耗品提示: 右键可直接食用
			var item := DataManager.get_item(item_id)
			if item and item.type == DataManager.ItemType.CONSUMABLE:
				tooltip_text = "%s\n[右键食用/饮用]" % tooltip_text

			var vbox := VBoxContainer.new()
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			vbox.add_theme_constant_override("separation", 1)

			# 物品 icon (按 [id].jpg 约定查, 不存在则跳过)
			var item_id_str: String = info.get("item_id", "")
			var icon_path: String = DataManager.get_icon_path(item_id_str) if item_id_str != "" else ""
			if icon_path != "" and ResourceLoader.exists(icon_path):
				var icon_tex: Texture2D = load(icon_path)
				if icon_tex:
					var icon_rect := TextureRect.new()
					icon_rect.texture = icon_tex
					icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					icon_rect.custom_minimum_size = Vector2(26 if is_trash else 34, 26 if is_trash else 34)
					icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
					vbox.add_child(icon_rect)

			var name_l := Label.new()
			name_l.text = info.get("name", item_id)
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_l.add_theme_font_size_override("font_size", 10 if is_trash else 11)
			vbox.add_child(name_l)

			var count_l := Label.new()
			count_l.text = "x%d" % item_count if item_count > 1 else ""
			count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_l.add_theme_font_size_override("font_size", 12)
			vbox.add_child(count_l)

			# 废料档: 加一个小角标, 与边框一起凸显"低档"
			if is_trash:
				var tag_l := Label.new()
				tag_l.text = "废料"
				tag_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tag_l.add_theme_font_size_override("font_size", 9)
				tag_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
				vbox.add_child(tag_l)

			add_child(vbox)
			var rarity_name: String = DataManager.RARITY_NAMES.get(int(info.get("rarity", 0)), "普通") if DataManager else "普通"
			tooltip_text = "%s  [%s]  重量%.1f千克  售价%d\n%s" % [
				info.get("name", ""), rarity_name, float(info.get("unit_weight", 0)), int(info.get("value", 0)),
				info.get("description", "")] + ("\n（可拖到上方装备栏穿戴）" if info.get("equippable", false) else "")
		add_theme_stylebox_override("panel", cell_style)


# --- 内部类: 装备槽 (接受拖放, 点击卸下) ---

class EquipSlot extends PanelContainer:
	var slot: String = ""
	var hud: CanvasLayer = null
	var _item_id: String = ""
	var _title: String = "装备"  # 中文槽位名 (用户反馈: 装备栏名称显示英文)

	func setup(slot_name: String, hud_ref: CanvasLayer, title: String) -> void:
		slot = slot_name
		hud = hud_ref
		_title = title
		custom_minimum_size = Vector2(200, 56)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.24, 0.3, 0.9)
		sb.border_color = Color(0.5, 0.5, 0.6)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		add_theme_stylebox_override("panel", sb)
		_update_text(_title, "空")

	func _update_text(title: String, value: String) -> void:
		for c in get_children():
			c.queue_free()
		var box := VBoxContainer.new()
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
		box.add_child(t)
		var v := Label.new()
		v.text = value
		v.add_theme_font_size_override("font_size", 14)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(v)
		add_child(box)

	func update_view(item_id: String) -> void:
		_item_id = item_id
		if item_id == "":
			_update_text(_title, "空")
			return
		var item := DataManager.get_item(item_id)
		# 显示耐久度 (有耐久定义的装备: 名称 (耐久 cur/max))
		var max_du := InventoryBackpack.get_max_durability(item_id)
		if max_du > 0:
			var cur := InventoryBackpack.get_durability(item_id)
			_update_text(_title, "%s (%d/%d)" % [item.name if item else item_id, max_du - cur, max_du])
		else:
			_update_text(_title, item.name if item else item_id)

	## 拖出已装备物品 (拖回背包 = 卸下; 拖到同类型槽 = 更换)
	func _get_drag_data(at_position: Vector2) -> Variant:
		if _item_id == "":
			return null
		var preview := Label.new()
		preview.text = _item_id
		preview.add_theme_font_size_override("font_size", 14)
		preview.custom_minimum_size = Vector2(110, 40)
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var panel := PanelContainer.new()
		panel.add_child(preview)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.35, 0.3, 0.45, 0.9)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		set_drag_preview(panel)
		return {"type": "inv_item", "item_id": _item_id, "from_slot": slot}

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.get("type", "") == "inv_item":
			var item := DataManager.get_item(data.get("item_id", ""))
			return item != null and item.equip_slot == slot
		return false

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if hud and hud.has_method("_on_equip_drag"):
			hud._on_equip_drag(data.get("item_id", ""), slot)

	func _gui_input(event: InputEvent) -> void:
		# 点击已装备物品 → 弹通用操作菜单 (卸下 / 查看详情)
		if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT) and _item_id != "":
			if hud and hud.has_method("_open_equip_menu"):
				hud._open_equip_menu(_item_id, slot, self)


# --- 主 HUD ---

var _backpack_btn: Button = null
var _load_btn: Button = null
var _root: Control = null
var _bg: ColorRect = null
var _panel: PanelContainer = null
var _weight_bar: ProgressBar = null
var _weight_label: Label = null
var _slots: Array[InvSlot] = []
var _equip_slots: Dictionary = {}  # slot -> EquipSlot
var _tab_bag: Button = null
var _tab_status: Button = null
var _bag_page: VBoxContainer = null
var _status_page: VBoxContainer = null
var _train_btn: Button = null
var _stat_labels: Dictionary = {}  # key -> Label
## 战斗日志 (挂在 HUD 上, 随 HUD 布局而非固定在战斗面板)
var _log_panel: RichTextLabel = null
var _log_container: PanelContainer = null
## 通用物品操作菜单 (背包格/装备槽共用, 与容器 UI 的实例同架构)
var _item_menu: ItemActionMenu = null

const GRID_COLS := 4
const GRID_ROWS := 4
const CELL_SIZE := 70  # 容纳 icon(34) + 名称(11) + 数量(12)

## 物品类型 → 色块颜色
const TYPE_COLORS := {
	0: Color(0.4, 0.75, 0.45),   # 消耗品 绿
	1: Color(0.85, 0.4, 0.4),    # 武器 红
	2: Color(0.4, 0.55, 0.85),   # 护甲 蓝
	3: Color(0.6, 0.5, 0.35),    # 材料 棕
	4: Color(0.9, 0.75, 0.3),    # 关键 金
	5: Color(0.9, 0.6, 0.3),     # 弹药 橙
	6: Color(0.7, 0.5, 0.85),    # 蓝图 紫
	7: Color(0.3, 0.7, 0.7),     # 背包 青
}


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_button()
	_build_log()       # 先建日志, 状态栏再下移日志位置
	_build_status_bar()
	_build_panel()
	# 通用物品操作菜单 (背包格/装备槽), 与容器 UI 共用架构
	_item_menu = ItemActionMenu.new()
	add_child(_item_menu)
	InventoryBackpack.inventory_changed.connect(_on_inventory_changed)
	TurnManager.combat_started.connect(_on_combat_started)
	TurnManager.combat_ended.connect(_on_combat_ended)
	TurnManager.unit_action_executed.connect(_on_unit_action_log)
	if WorldTime:
		WorldTime.time_changed.connect(_on_world_time_changed)
	_connect_player_signals()


## 游戏内时间 → 状态栏时间标签
func _on_world_time_changed(day_num: int, hour_val: float) -> void:
	if _time_label:
		var hh: int = int(hour_val)
		var mm: int = int((hour_val - hh) * 60)
		_time_label.text = "Day %d  %02d:%02d" % [day_num, hh, mm]


## 连接玩家状态信号 (HP/AP/生存属性 → 状态栏)
func _connect_player_signals() -> void:
	var player := TurnManager.get_player()
	if not player:
		return
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_update_hp_bar)
	if player.has_signal("ap_changed"):
		player.ap_changed.connect(_update_ap_bar)
	if player.has_signal("survival_updated"):
		player.survival_updated.connect(_update_survival_bars)
	# 立即同步一次
	_update_hp_bar(player.get("hp"), player.get("max_hp"))
	_update_ap_bar(player.get("ap_current"), player.get("ap_max"))
	if player.has_method("get_survival"):
		var s: Dictionary = player.get_survival()
		_update_survival_bars(s.get("hunger", 100.0), s.get("thirst", 100.0))


# --- 主角状态栏 (红条 HP / 蓝条 AP / 饥饿 / 口渴 / 睡眠 + 游戏内时间) ---

var _hp_bar_status: ProgressBar = null
var _ap_bar_status: ProgressBar = null
var _hunger_bar: ProgressBar = null
var _thirst_bar: ProgressBar = null
var _sleep_bar: ProgressBar = null
var _time_label: Label = null


func _build_status_bar() -> void:
	var bar_root := VBoxContainer.new()
	bar_root.name = "StatusBar"
	bar_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar_root.offset_left = 12
	bar_root.offset_top = 12
	bar_root.offset_right = 600
	bar_root.offset_bottom = 96
	bar_root.add_theme_constant_override("separation", 4)
	bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 第一行: HP 红条 + AP 蓝条
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 13)
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	row1.add_child(hp_label)

	_hp_bar_status = ProgressBar.new()
	_hp_bar_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar_status.max_value = 100
	_hp_bar_status.value = 100
	_hp_bar_status.show_percentage = false
	_hp_bar_status.custom_minimum_size = Vector2(0, 16)
	row1.add_child(_hp_bar_status)

	var ap_label := Label.new()
	ap_label.text = "精力"  # AP+睡眠合并为精力
	ap_label.add_theme_font_size_override("font_size", 13)
	ap_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.95))
	row1.add_child(ap_label)

	_ap_bar_status = ProgressBar.new()
	_ap_bar_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ap_bar_status.max_value = 10
	_ap_bar_status.value = 10
	_ap_bar_status.show_percentage = false
	_ap_bar_status.custom_minimum_size = Vector2(0, 16)
	row1.add_child(_ap_bar_status)

	bar_root.add_child(row1)

	# 第二行: 饥饿 / 口渴 + 时间 (睡眠条已移除, 精力走 AP 条)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_hunger_bar = _make_survival_bar(row2, "饱食", Color(0.95, 0.7, 0.3))
	_thirst_bar = _make_survival_bar(row2, "饮水", Color(0.4, 0.7, 0.95))

	# 游戏内时间 (Day X HH:MM)
	_time_label = Label.new()
	_time_label.text = "Day 1  06:00"
	_time_label.add_theme_font_size_override("font_size", 12)
	_time_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	_time_label.custom_minimum_size = Vector2(110, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row2.add_child(_time_label)

	bar_root.add_child(row2)
	add_child(bar_root)

	# 战斗日志下移, 避开状态栏
	if _log_container:
		_log_container.offset_top = 104
		_log_container.offset_bottom = 312


func _make_survival_bar(parent: HBoxContainer, label_text: String, color: Color) -> ProgressBar:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.add_theme_stylebox_override("fill", _make_fill_style(color))
	parent.add_child(bar)
	return bar


func _make_fill_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	return sb


func _update_hp_bar(new_hp: float, max_hp_val: float) -> void:
	if _hp_bar_status:
		_hp_bar_status.max_value = maxf(max_hp_val, 1.0)
		_hp_bar_status.value = new_hp
		var red: float = clampf(1.0 - new_hp / maxf(max_hp_val, 1.0), 0.0, 1.0)
		_hp_bar_status.add_theme_stylebox_override("fill", _make_fill_style(Color(0.85 - red * 0.3, 0.25, 0.25)))


func _update_ap_bar(new_ap: int, max_ap_val: int) -> void:
	if _ap_bar_status:
		_ap_bar_status.max_value = maxf(max_ap_val, 1.0)
		_ap_bar_status.value = new_ap
		_ap_bar_status.add_theme_stylebox_override("fill", _make_fill_style(Color(0.3, 0.5, 0.95)))


func _update_survival_bars(h: float, t: float) -> void:
	if _hunger_bar:
		_hunger_bar.value = h
	if _thirst_bar:
		_thirst_bar.value = t


# --- 战斗日志 (随 HUD 布局, 左上角常驻, 可滚动查看) ---
# 修复: 原日志焊死在 CombatUI 底部面板 (PRESET_BOTTOM_WIDE), 改挂 HUD 层。

func _build_log() -> void:
	_log_container = PanelContainer.new()
	_log_container.name = "CombatLog"
	_log_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_log_container.offset_left = 12
	_log_container.offset_top = 12
	_log_container.offset_right = 380
	_log_container.offset_bottom = 220
	_log_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.11, 0.78)
	sb.border_color = Color(0.45, 0.45, 0.55, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_log_container.add_theme_stylebox_override("panel", sb)

	_log_panel = RichTextLabel.new()
	_log_panel.bbcode_enabled = true
	_log_panel.scroll_following = true
	_log_panel.custom_minimum_size = Vector2(0, 0)
	_log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_panel.add_theme_font_size_override("normal_font_size", 13)
	_log_container.add_child(_log_panel)
	add_child(_log_container)


func append_log(msg: String) -> void:
	if _log_panel:
		_log_panel.append_text(msg + "\n")


## 战斗开始: 清空旧日志 + 禁用休息类按钮
func _on_combat_started() -> void:
	if _log_panel:
		_log_panel.clear()
	_update_rest_buttons()


## 战斗结束: 恢复休息类按钮
func _on_combat_ended(_victory: bool) -> void:
	_update_rest_buttons()


## 战斗中禁用"锻炼"按钮 (坐下/锻炼只能在非战斗时做)
func _update_rest_buttons() -> void:
	if _train_btn == null:
		return
	var in_combat: bool = TurnManager.combat_mode
	_train_btn.disabled = in_combat
	_train_btn.modulate = Color(1, 1, 1, 0.4) if in_combat else Color(1, 1, 1, 1)
	_train_btn.tooltip_text = "战斗中无法锻炼" if in_combat else ""


## 新手引导提示 (顶部横幅, 可点击关闭)
var _tutorial_banner: PanelContainer = null
var _tutorial_label: Label = null

func show_tutorial(msg: String) -> void:
	if _tutorial_banner == null:
		_build_tutorial_banner()
	_tutorial_label.text = msg
	_tutorial_banner.visible = true
	_tutorial_banner.modulate.a = 1.0


func _build_tutorial_banner() -> void:
	_tutorial_banner = PanelContainer.new()
	_tutorial_banner.name = "TutorialBanner"
	_tutorial_banner.visible = false
	_tutorial_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tutorial_banner.offset_left = 40
	_tutorial_banner.offset_right = -40
	_tutorial_banner.offset_top = 100
	_tutorial_banner.offset_bottom = 150
	_tutorial_banner.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.2, 0.92)
	sb.border_color = Color(0.5, 0.6, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_tutorial_banner.add_theme_stylebox_override("panel", sb)

	_tutorial_label = Label.new()
	_tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_label.add_theme_font_size_override("font_size", 17)
	_tutorial_label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_tutorial_banner.add_child(_tutorial_label)

	# 点击横幅关闭
	_tutorial_banner.gui_input.connect(_on_tutorial_banner_input)
	add_child(_tutorial_banner)


func _on_tutorial_banner_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_tutorial_banner.visible = false


## 隐藏引导 (可手动调用)
func hide_tutorial() -> void:
	if _tutorial_banner:
		_tutorial_banner.visible = false


## 玩家动作/敌人行动 → 写日志 (战斗动作日志统一走这里)
func _on_unit_action_log(unit: Node, action: String, ap_cost: int) -> void:
	if not TurnManager.combat_mode:
		return
	var unit_name: String = unit.get_display_name() if unit.has_method("get_display_name") else unit.name
	append_log("%s · %s (AP %d)" % [unit_name, action, ap_cost])


# --- 底部按钮栏 (背包 + 存档, 用户反馈: 按钮放屏幕下方) ---

func _build_button() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -160
	bar.offset_right = 160
	bar.offset_top = -104
	bar.offset_bottom = -16
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)

	_backpack_btn = Button.new()
	_backpack_btn.text = "背包"
	_backpack_btn.custom_minimum_size = Vector2(94, 88)
	_backpack_btn.add_theme_font_size_override("font_size", 20)
	_backpack_btn.pressed.connect(_toggle_backpack)
	bar.add_child(_backpack_btn)

	# 异能按钮 (替代 AbilityTreeUI 原右上角的 _btn, 统一放底部)
	var ability_btn := Button.new()
	ability_btn.text = "异能"
	ability_btn.custom_minimum_size = Vector2(94, 88)
	ability_btn.add_theme_font_size_override("font_size", 20)
	ability_btn.pressed.connect(_toggle_ability)
	bar.add_child(ability_btn)

	var save_btn := Button.new()
	save_btn.text = "存档"
	save_btn.custom_minimum_size = Vector2(94, 88)
	save_btn.add_theme_font_size_override("font_size", 20)
	save_btn.pressed.connect(_on_save_pressed)
	bar.add_child(save_btn)

	_load_btn = Button.new()
	_load_btn.text = "读档"
	_load_btn.custom_minimum_size = Vector2(94, 88)
	_load_btn.add_theme_font_size_override("font_size", 20)
	_load_btn.pressed.connect(_on_load_pressed)
	# 无存档时禁用 (有档才能读)
	if GameManager:
		_load_btn.disabled = not GameManager.has_save()
	bar.add_child(_load_btn)

	# 任务按钮 (打开当前角色主线任务面板)
	var quest_btn := Button.new()
	quest_btn.text = "任务"
	quest_btn.custom_minimum_size = Vector2(94, 88)
	quest_btn.add_theme_font_size_override("font_size", 20)
	quest_btn.pressed.connect(_toggle_quest)
	bar.add_child(quest_btn)


## 存档: 硬核单槽保存 (P0)
func _on_save_pressed() -> void:
	if GameManager:
		GameManager.save_game()
		# 存档成功后, 读档按钮可用
		if _load_btn:
			_load_btn.disabled = not GameManager.has_save()
	if _log_panel:
		_log_panel.append_text("[存档成功]\n")


## 读档: 加载最后一次存档 (场景切到 world_map, 由 game_scene_base 应用主角数据)
func _on_load_pressed() -> void:
	if GameManager and GameManager.has_save():
		GameManager.load_game()


## 底部"异能"按钮: 切换异能树面板 (从场景树找 ATU)
func _toggle_ability() -> void:
	var root := get_tree().current_scene
	var atu := root.find_child("AbilityTreeUI", true, false) if root else null
	if atu and atu.has_method("_toggle"):
		atu._toggle()


func _toggle_quest() -> void:
	var root := get_tree().current_scene
	var qp := root.find_child("QuestPanel", true, false) if root else null
	if qp and qp.has_method("_toggle"):
		qp._toggle()


## 装备详情面板 (点击 EquipSlot 触发): 显示属性/磨损/价值 + 卸下按钮
## 从 InvSlot (背包物品) 或 EquipSlot (已装备) 调用, item_id 必填
var _detail_panel: PanelContainer = null
var _detail_overlay: ColorRect = null
var _detail_slot: String = ""  # 装备槽位 (卸下用)

func _show_item_detail(item_id: String, slot: String = "") -> void:
	_clear_detail_panel()
	var item: DataManager.ItemData = DataManager.get_item(item_id)
	if not item:
		return
	_detail_slot = slot

	# 半透明遮罩背景 (点遮罩关闭面板)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _clear_detail_panel())
	_detail_overlay = overlay
	_detail_panel = PanelContainer.new()
	_detail_panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.11, 0.97)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_detail_panel.add_theme_stylebox_override("panel", sb)
	add_child(overlay)
	add_child(_detail_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "%s  (%s)" % [item.name, "已装备" if slot != "" else "背包"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", DataManager.RARITY_COLORS.get(int(item.rarity), Color.WHITE) if DataManager else Color.WHITE)
	vbox.add_child(title)

	# 描述
	if item.description != "":
		var desc := Label.new()
		desc.text = item.description
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 13)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(360, 0)
		vbox.add_child(desc)

	# 提供的属性 (解析 properties)
	var prop_labels: Array[String] = []
	if item.properties.has("defense"):
		prop_labels.append("防御 +%d" % int(item.properties["defense"]))
	if item.properties.has("ammo_type"):
		prop_labels.append("弹药类型: %s" % item.properties["ammo_type"])
	if item.properties.has("vision_bonus"):
		prop_labels.append("视野 +%d 格" % int(item.properties["vision_bonus"]))
	if item.properties.has("range_bonus"):
		prop_labels.append("射程 +%d 格" % int(item.properties["range_bonus"]))
	if item.properties.has("accuracy_bonus"):
		prop_labels.append("命中率 +%d%%" % int(float(item.properties["accuracy_bonus"]) * 100))
	if item.properties.has("crit_bonus"):
		prop_labels.append("暴击率 +%d%%" % int(float(item.properties["crit_bonus"]) * 100))
	if item.properties.has("luck_bonus"):
		prop_labels.append("幸运 +%d" % int(item.properties["luck_bonus"]))
	if item.properties.has("weight_bonus"):
		prop_labels.append("负重 +%dkg" % int(item.properties["weight_bonus"]))
	if item.properties.has("heal"):
		prop_labels.append("生命回复 +%d" % int(item.properties["heal"]))
	if item.properties.has("water"):
		prop_labels.append("水分 +%d" % int(item.properties["water"]))
	if item.properties.has("food"):
		prop_labels.append("饱腹 +%d" % int(item.properties["food"]))
	if item.properties.has("energy_restore"):
		prop_labels.append("精力回复 +%d" % int(item.properties["energy_restore"]))

	if not prop_labels.is_empty():
		var prop_title := Label.new()
		prop_title.text = "—— 属性 ——"
		prop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prop_title.add_theme_font_size_override("font_size", 14)
		prop_title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		vbox.add_child(prop_title)
		for pl in prop_labels:
			var lab := Label.new()
			lab.text = "  " + pl
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			lab.add_theme_font_size_override("font_size", 14)
			vbox.add_child(lab)

	# 磨损 (耐久)
	var max_du: int = InventoryBackpack.get_max_durability(item_id)
	if max_du > 0:
		var cur: int = InventoryBackpack.get_durability(item_id)
		var ratio: float = InventoryBackpack.get_durability_ratio(item_id)
		var dlab := Label.new()
		dlab.text = "—— 耐久 ——"
		dlab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dlab.add_theme_font_size_override("font_size", 14)
		dlab.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		vbox.add_child(dlab)
		var dbar := ProgressBar.new()
		dbar.max_value = max_du
		dbar.value = max_du - cur
		dbar.show_percentage = false
		dbar.custom_minimum_size = Vector2(320, 18)
		var durability_color: Color = Color(0.3, 0.85, 0.35) if ratio > 0.5 else (Color(0.95, 0.75, 0.2) if ratio > 0.2 else Color(0.9, 0.3, 0.3))
		dbar.add_theme_stylebox_override("fill", _make_fill_style(durability_color))
		vbox.add_child(dbar)
		var dlabel := Label.new()
		dlabel.text = "%d / %d  (%.0f%% 完整)" % [max_du - cur, max_du, ratio * 100]
		dlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dlabel.add_theme_font_size_override("font_size", 13)
		vbox.add_child(dlabel)

	# 价值
	var vlab := Label.new()
	vlab.text = "—— 交易价值 ——"
	vlab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlab.add_theme_font_size_override("font_size", 14)
	vlab.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	vbox.add_child(vlab)
	var vvalue := Label.new()
	var worn: int = InventoryBackpack.get_durability(item_id)
	var full_value: int = item.value
	var actual_value: int = InventoryBackpack.get_item_value(item_id)
	if worn > 0 and full_value != actual_value:
		vvalue.text = "%d  (原价 %d, 磨损 -%d)" % [actual_value, full_value, full_value - actual_value]
	else:
		vvalue.text = "%d" % actual_value
	vvalue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vvalue.add_theme_font_size_override("font_size", 15)
	vvalue.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(vvalue)

	# 卸下按钮 (仅装备槽有 slot)
	if slot != "":
		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 10)
		var unequip_btn := Button.new()
		unequip_btn.text = "卸下"
		unequip_btn.custom_minimum_size = Vector2(120, 44)
		unequip_btn.add_theme_font_size_override("font_size", 15)
		unequip_btn.pressed.connect(_on_detail_unequip.bind(slot))
		btn_row.add_child(unequip_btn)
		vbox.add_child(btn_row)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(280, 44)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_clear_detail_panel)
	vbox.add_child(close_btn)


func _on_detail_unequip(slot: String) -> void:
	_on_unequip_click(slot)
	_refresh_stats()
	# 卸下后刷新详情面板 (item_id 可能变空)
	var player := TurnManager.get_player()
	var item_id: String = player.get_equipped_item(slot) if player else ""
	if item_id:
		_show_item_detail(item_id, slot)
	else:
		_clear_detail_panel()


func _clear_detail_panel() -> void:
	if _detail_panel:
		_detail_panel.queue_free()
		_detail_panel = null
	if _detail_overlay:
		_detail_overlay.queue_free()
		_detail_overlay = null
	_detail_slot = ""


# --- 背包面板 (双页) ---

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
	_panel.offset_top = -80  # 居中偏上 (用户反馈: 背包 UI 在正中心偏上一点)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.97)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", sb)

	# 内容包 ScrollContainer: 面板内容高 (装备栏+Tab+4×4+状态页) 会超出屏幕底部
	# (用户反馈: 关闭按钮在最下面超出界面范围), 限制可视高度可滚动
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# (用户反馈: 不需要"行囊"标题文字, 仅保留「背包 / 状态」两个 Tab 切换)
	# 负重条
	var weight_hbox := HBoxContainer.new()
	weight_hbox.add_theme_constant_override("separation", 8)
	weight_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_weight_bar = ProgressBar.new()
	_weight_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_bar.max_value = InventoryBackpack.get_max_weight()
	_weight_bar.value = InventoryBackpack.get_total_weight()
	_weight_bar.show_percentage = false
	weight_hbox.add_child(_weight_bar)
	_weight_label = Label.new()
	_weight_label.text = "0/50 kg"
	_weight_label.custom_minimum_size = Vector2(96, 0)
	_weight_label.add_theme_font_size_override("font_size", 14)
	weight_hbox.add_child(_weight_label)
	vbox.add_child(weight_hbox)

	# 装备栏 (在上): 武器 / 防具 / 背包 三槽
	var equip_box := VBoxContainer.new()
	equip_box.add_theme_constant_override("separation", 4)
	equip_box.add_child(_make_hint("装备栏 — 拖背包物品上来穿戴, 拖已装备回背包卸下"))
	var weapon_slot := EquipSlot.new()
	weapon_slot.setup(DataManager.EQUIP_SLOT_WEAPON, self, "武器")
	equip_box.add_child(weapon_slot)
	_equip_slots[DataManager.EQUIP_SLOT_WEAPON] = weapon_slot
	var armor_slot := EquipSlot.new()
	armor_slot.setup(DataManager.EQUIP_SLOT_ARMOR, self, "防具")
	equip_box.add_child(armor_slot)
	_equip_slots[DataManager.EQUIP_SLOT_ARMOR] = armor_slot
	var backpack_slot := EquipSlot.new()
	backpack_slot.setup(DataManager.EQUIP_SLOT_BACKPACK, self, "背包")
	equip_box.add_child(backpack_slot)
	_equip_slots[DataManager.EQUIP_SLOT_BACKPACK] = backpack_slot
	var trinket_slot := EquipSlot.new()
	trinket_slot.setup(DataManager.EQUIP_SLOT_TRINKET, self, "饰品")
	equip_box.add_child(trinket_slot)
	_equip_slots[DataManager.EQUIP_SLOT_TRINKET] = trinket_slot

	# Tab 栏: 背包 / 角色状态
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 6)
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bag = _make_tab_button("背包", true)
	_tab_status = _make_tab_button("状态", false)
	tab_bar.add_child(_tab_bag)
	tab_bar.add_child(_tab_status)
	vbox.add_child(tab_bar)

	# 背包页 (上装备栏 + 下 4×4 网格)
	_bag_page = VBoxContainer.new()
	_bag_page.add_child(equip_box)
	var bag_box := VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in GRID_COLS * GRID_ROWS:
		var cell := InvSlot.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.hud = self
		_slots.append(cell)
		grid.add_child(cell)
	bag_box.add_child(grid)
	bag_box.add_child(_make_hint("点击消耗品直接食用 · 装备类拖到上方装备栏穿戴"))
	_bag_page.add_child(bag_box)
	vbox.add_child(_bag_page)

	# 状态页: 命中率/暴击率/幸运/体力/负重 + 锻炼按钮
	_status_page = VBoxContainer.new()
	_status_page.add_theme_constant_override("separation", 6)
	_status_page.add_child(_make_hint("角色状态 — 命中率/暴击率/幸运/体力/负重"))
	_stat_labels = {}
	const STAT_KEYS: Array[String] = ["accuracy", "crit", "luck", "stamina", "carry", "vision", "range", "attack", "defense"]
	for key in STAT_KEYS:
		var lab := Label.new()
		lab.add_theme_font_size_override("font_size", 15)
		_status_page.add_child(lab)
		_stat_labels[key] = lab
	# 锻炼按钮: +体力, 消耗 2 小时世界时间
	_train_btn = Button.new()
	_train_btn.text = "锻炼 (+1 体力, 耗时 2 小时)"
	_train_btn.custom_minimum_size = Vector2(280, 44)
	_train_btn.add_theme_font_size_override("font_size", 14)
	_train_btn.pressed.connect(_on_train_pressed)
	_status_page.add_child(_train_btn)
	_status_page.visible = false
	vbox.add_child(_status_page)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(280, 52)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(close_backpack)
	vbox.add_child(close_btn)

	_root.add_child(_panel)


func _make_hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	return l


# --- Tab 切换: 背包 / 角色状态 ---

func _make_tab_button(text: String, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.toggle_mode = true
	b.pressed.connect(_on_tab_pressed.bind(text))
	b.set_pressed_no_signal(active)
	return b


func _on_tab_pressed(text: String) -> void:
	_show_tab(text == "背包")
	_tab_bag.set_pressed_no_signal(text == "背包")
	_tab_status.set_pressed_no_signal(text == "状态")


func _show_tab(bag: bool) -> void:
	if _bag_page:
		_bag_page.visible = bag
	if _status_page:
		_status_page.visible = not bag


# --- 状态面板刷新: 命中率/暴击率/幸运/体力/负重 等 ---

func _refresh_stats() -> void:
	if _stat_labels.is_empty():
		return
	var player := _get_player()
	if not player:
		return
	# 命中率 = 武器基础(80%) + 饰品加成(accuracy_bonus)
	var weapon_acc: float = 0.0
	var weapon_crit: float = 0.0
	var default_action: Resource = player.get_default_attack()
	if default_action:
		weapon_acc = float(default_action.get("accuracy") if default_action.get("accuracy") != null else 0.8)
		weapon_crit = float(default_action.get("crit_chance") if default_action.get("crit_chance") != null else 0.05)
	var acc_total: float = weapon_acc + player.get_accuracy_bonus()
	var crit_total: float = weapon_crit + player.get_crit_bonus()
	var luck_total: float = float(player.get("luck")) + float(player.get_luck_bonus())
	var stamina_val: float = float(player.get("stamina"))
	var vision_total: int = 5 + player.get_vision_bonus()  # 5 = 白天基础(常量), 实际用 _vision_radius 但状态页简单显示加成
	var range_total: int = player.get_range_bonus()
	_stat_labels["accuracy"].text = "命中率: %d%%  (武器 %d%% + 饰品 +%d%%)" % [int(acc_total * 100), int(weapon_acc * 100), int(player.get_accuracy_bonus() * 100)]
	_stat_labels["crit"].text = "暴击率: %d%%  (武器 %d%% + 饰品 +%d%%)" % [int(crit_total * 100), int(weapon_crit * 100), int(player.get_crit_bonus() * 100)]
	_stat_labels["luck"].text = "幸运值: %d  (基础 %.0f + 饰品 +%d)" % [int(luck_total), float(player.get("luck")), player.get_luck_bonus()]
	_stat_labels["stamina"].text = "体力值: %d  (锻炼可增加, 每点 +0.5kg 负重)" % int(stamina_val)
	_stat_labels["carry"].text = "负重: %d / %d kg  (基础 10 + 体力 +%.1f + 背包装备)" % [
		int(InventoryBackpack.get_total_weight()),
		int(InventoryBackpack.get_max_weight()),
		stamina_val * 0.5]
	_stat_labels["vision"].text = "视野加成: +%d 格  (饰品效果)" % player.get_vision_bonus()
	_stat_labels["range"].text = "射程加成: +%d 格  (饰品效果)" % range_total
	_stat_labels["attack"].text = "攻击力: %d  ·  防御力: %d" % [int(player.get("attack_power")), int(player.get("defense"))]
	_stat_labels["defense"].text = "幸运值: %d  (含饰品 +%d)" % [int(luck_total), player.get_luck_bonus()]


# --- 锻炼按钮回调: +1 体力, 消耗 2 小时世界时间 ---
func _on_train_pressed() -> void:
	if TurnManager.combat_mode:
		return  # 战斗中禁止锻炼
	var player := _get_player()
	if not player or not player.has_method("train"):
		return
	if player.train(1.0, 2.0):
		_refresh_stats()
		if _log_panel:
			_log_panel.append_text("[锻炼] +1 体力, 耗时 2 小时\n")


# --- 拖拽/卸下回调 ---

## 背包格点击 → 弹通用物品操作菜单 (context=backpack)
func _open_inv_menu(item_id: String, btn: Control) -> void:
	if _item_menu:
		var pos: Vector2 = btn.get_global_rect().position if btn else get_viewport().get_visible_rect().size * 0.5
		_item_menu.show_at(pos, item_id, "backpack", _on_item_menu_action)


## 装备槽点击 → 弹通用物品操作菜单 (context=equip: 卸下/详情)
func _open_equip_menu(item_id: String, slot: String, btn: Control) -> void:
	if _item_menu:
		var pos: Vector2 = btn.get_global_rect().position if btn else get_viewport().get_visible_rect().size * 0.5
		_item_menu.show_at(pos, item_id, "equip", _on_item_menu_action.bind(slot))


## 通用菜单回调: 按 action_id 分发到对应逻辑
## (equip 上下文额外绑定 slot 参数, 卸下需要知道槽位)
func _on_item_menu_action(action_id: String, item_id: String, extra: Variant = null) -> void:
	match action_id:
		"use":
			_consume_backpack_item(item_id)
		"equip":
			var player := _get_player()
			if player and player.has_method("equip_item"):
				player.equip_item(item_id)
			_refresh()
		"detail":
			_show_item_detail(item_id)
		"unequip":
			var slot: String = str(extra) if extra != null else ""
			_on_unequip_click(slot)
			_refresh()
		"discard":
			_discard_backpack_item(item_id)
		"discard_all":
			_discard_backpack_item_all(item_id)


## 食用/饮用背包消耗品 (点击操作菜单"食用/饮用")
func _consume_backpack_item(item_id: String) -> void:
	var player := _get_player()
	if not player:
		return
	if player.has_method("consume_item"):
		var result: Dictionary = player.consume_item(item_id)
		if result.get("success", false):
			InventoryBackpack.inventory_changed.emit()
	elif player.has_method("use_item_on_self"):
		player.use_item_on_self(item_id)


## 丢弃背包物品 → 生成地面物品 (可再捡起)
func _discard_backpack_item(item_id: String) -> void:
	if not InventoryBackpack.remove_item(item_id, 1):
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("spawn_ground_item"):
		scene.spawn_ground_item(item_id, 1)
	InventoryBackpack.inventory_changed.emit()
	var item := DataManager.get_item(item_id) if DataManager else null
	_log_panel.append_text("[丢弃] %s\n" % (item.name if item else item_id))


## 丢弃背包格全部数量 → 生成地面物品 (可再捡回)
## (用户反馈: 点背包格弹菜单的"丢弃全部" = 丢这一个格子的所有数量, 不是清空整个背包)
func _discard_backpack_item_all(item_id: String) -> void:
	var cnt: int = InventoryBackpack.count_item(item_id)
	if cnt <= 0:
		return
	if not InventoryBackpack.remove_item(item_id, cnt):
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("spawn_ground_item"):
		scene.spawn_ground_item(item_id, cnt)
	InventoryBackpack.inventory_changed.emit()
	var item := DataManager.get_item(item_id) if DataManager else null
	_log_panel.append_text("[丢弃全部] %s ×%d (丢到脚下地面)\n" % [(item.name if item else item_id), cnt])


func _on_equip_drag(item_id: String, slot: String) -> void:
	var player := _get_player()
	if player and player.has_method("equip_item"):
		player.equip_item(item_id)
	_refresh()


func _on_unequip_click(slot: String) -> void:
	var player := _get_player()
	if player and player.has_method("unequip_item"):
		player.unequip_item(slot)
	_refresh()


## 装备槽拖回背包 → 卸下
func _on_bag_drop(from_slot: String) -> void:
	var player := _get_player()
	if player and player.has_method("unequip_item"):
		player.unequip_item(from_slot)
	_refresh()


func _get_player() -> Node:
	return TurnManager.get_player()


# --- 开关 ---

func _toggle_backpack() -> void:
	if _root.visible:
		close_backpack()
	else:
		open_backpack()


func open_backpack() -> void:
	_root.visible = true
	_show_tab(true)
	_refresh()
	_refresh_stats()


func close_backpack() -> void:
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close_backpack()


func _on_inventory_changed() -> void:
	if is_open():
		_refresh()


# --- 刷新 ---

func _refresh() -> void:
	_weight_bar.max_value = InventoryBackpack.get_max_weight()
	_weight_bar.value = InventoryBackpack.get_total_weight()
	_weight_label.text = "%d/%d kg" % [int(InventoryBackpack.get_total_weight()), int(InventoryBackpack.get_max_weight())]

	var item_list := InventoryBackpack.list_items()
	for i in range(_slots.size()):
		var slot := _slots[i]
		if i < item_list.size():
			var info: Dictionary = item_list[i]
			var item := DataManager.get_item(info.get("item_id", ""))
			info["equippable"] = item != null and item.equip_slot != ""
			info["unit_weight"] = item.weight if item else 0.0
			# 背景/边框规则已统一到 update_view 内部 (深色背景 + 稀有度边框, 与尸体一致), 此处不再传类型色
			slot.update_view(info, false, Color.WHITE)
		else:
			slot.update_view({}, true, Color.WHITE)

	# 装备页
	var player := _get_player()
	for slot_name in _equip_slots:
		var es: EquipSlot = _equip_slots[slot_name]
		var item_id: String = player.get_equipped_item(slot_name) if player else ""
		es.update_view(item_id)
