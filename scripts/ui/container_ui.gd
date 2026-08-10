class_name ContainerUI
extends CanvasLayer

# ============================================================
# ContainerUI — 容器(衣柜/箱子/尸体)物品界面
# ============================================================
# 打开容器: 4×4 网格展示内部物品 (与玩家背包一致)。
# 每个物品格带【稀有度边框】: 普通灰 / 优秀绿 / 稀有蓝 / 史诗紫 / 传说金。
# 点击格子 → 弹出【操作菜单】(拿走 / 丢弃), 与点击丧尸弹动作菜单同一交互模式。
# 拿走 → 尝试放入角色背包 (超重弹提示); 丢弃 → 掉落到地面 (场景生成 GroundItem, 可再捡起)。
# 手机友好: 格子 ≥ 60px。

signal item_discarded(item_id: String, count: int)

var _panel: PanelContainer = null
var _title_label: Label = null
var _list: GridContainer = null
var _overflow_label: Label = null
var _weight_label: Label = null
var _overflow_timer: float = 0.0
var _empty_hint: Label = null
var _item_menu: ItemActionMenu = null
var _selected_item_id: String = ""

var _container: Node = null  # Furniture / Corpse

const OVERFLOW_DURATION := 2.0
const GRID_COLS := 4
const GRID_ROWS := 4
const CELL_SIZE := 70

## 稀有度 → 边框色 (数据层 DataManager.RARITY_COLORS, 此处只做取值兜底)
const FALLBACK_RARITY_COLOR := Color(0.62, 0.62, 0.62)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.96)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 13)
	_weight_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_weight_label)

	# 4×4 网格 (与玩家背包一致)
	_list = GridContainer.new()
	_list.columns = GRID_COLS
	_list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_list.add_theme_constant_override("h_separation", 6)
	_list.add_theme_constant_override("v_separation", 6)
	vbox.add_child(_list)

	# 空容器提示 (默认隐藏)
	_empty_hint = Label.new()
	_empty_hint.text = "里面空空如也..."
	_empty_hint.add_theme_font_size_override("font_size", 14)
	_empty_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.visible = false
	vbox.add_child(_empty_hint)

	_overflow_label = Label.new()
	_overflow_label.text = "⚠ 负重不足！"
	_overflow_label.add_theme_font_size_override("font_size", 16)
	_overflow_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	_overflow_label.visible = false
	_overflow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_overflow_label)

	# 操作行: 全部拿走 + 关闭
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var take_all_btn := Button.new()
	take_all_btn.text = "全部拿走"
	take_all_btn.custom_minimum_size = Vector2(150, 50)
	take_all_btn.add_theme_font_size_override("font_size", 15)
	take_all_btn.pressed.connect(_on_take_all_pressed)
	action_row.add_child(take_all_btn)

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(150, 50)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(close)
	action_row.add_child(close_btn)

	vbox.add_child(action_row)

	_panel.add_child(vbox)
	add_child(_panel)

	# 通用物品操作菜单 (与背包格/装备槽共用 ItemActionMenu 组件)
	_item_menu = ItemActionMenu.new()
	add_child(_item_menu)


func _process(delta: float) -> void:
	if _overflow_label.visible:
		_overflow_timer -= delta
		if _overflow_timer <= 0:
			_overflow_label.visible = false


## 打开容器
func open(container: Node, title: String) -> void:
	_container = container
	_title_label.text = title
	_panel.visible = true
	_refresh()


func close() -> void:
	_panel.visible = false
	_hide_item_menu()
	if _container and _container.has_signal("closed"):
		_container.closed.emit(_container)


func is_open() -> bool:
	return _panel.visible


## 鼠标是否在容器面板内 (场景 _input 用它判断"点面板内不关闭, 点外部才关闭")
## 修复: 之前场景 _input 对任何左键都 close(), 导致"全部拿走"按钮/格子点击被抢
func is_point_on_panel(screen_pos: Vector2) -> bool:
	if not _panel or not _panel.visible:
		return false
	return _panel.get_global_rect().has_point(screen_pos)


## 稀有度 → 边框颜色 (统一取 DataManager, 兜底灰色)
func _rarity_color(rarity: int) -> Color:
	var colors: Dictionary = DataManager.RARITY_COLORS if DataManager else {}
	return colors.get(int(rarity), FALLBACK_RARITY_COLOR)


## 刷新物品网格 (始终渲染 4×4=16 格: 有物品显示物品格, 空位显示空格子)
func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	if not _container:
		return
	var container_items: Array = _container.list_inventory()

	# 容器剩余重量 (拿走一件数字变小, 符合直觉) + 背包负重 (跟随变化)
	var container_weight: float = 0.0
	for info in container_items:
		container_weight += float(info.get("weight", 0.0))
	_weight_label.text = "容器剩余 %.1fkg · 背包 %d/%dkg" % [
		container_weight,
		int(InventoryBackpack.get_total_weight()),
		int(InventoryBackpack.get_max_weight())]

	# 始终渲染 16 格: 前 N 个是物品, 其余为空位
	for index in range(GRID_COLS * GRID_ROWS):
		if index < container_items.size():
			_list.add_child(_make_item_cell(container_items[index]))
		else:
			_list.add_child(_make_empty_cell())


## 物品格: 稀有度边框 + 名称/数量 + 左键/右键均拿走
func _make_item_cell(info: Dictionary) -> Control:
	var item_id: String = info.get("item_id", "")
	var name: String = info.get("name", item_id)
	var rarity: int = int(info.get("rarity", 0))
	var rarity_color := _rarity_color(rarity)
	var desc: String = info.get("description", "")

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	btn.add_theme_font_size_override("font_size", 11)
	btn.tooltip_text = "%s  %.1fkg  价值%d  [%s]\n%s\n(点击: 拿走 / 丢弃)" % [
		name, float(info.get("weight", 0)), int(info.get("value", 0)),
		DataManager.RARITY_NAMES.get(rarity, "普通") if DataManager else "普通",
		desc]

	# 稀有度边框: 用 StyleBoxFlat border 上色 (2px), 空内背景深色
	var cell_style := StyleBoxFlat.new()
	cell_style.bg_color = Color(0.16, 0.16, 0.2, 0.9)
	cell_style.border_color = rarity_color
	cell_style.set_border_width_all(2)
	cell_style.set_corner_radius_all(6)
	# 废料档: 更薄更暗的低级框 (与背包格同一套显示规则)
	var is_trash: bool = DataManager != null and rarity == DataManager.Rarity.TRASH
	if is_trash:
		cell_style.set_border_width_all(1)
		cell_style.set_corner_radius_all(3)
		cell_style.bg_color = Color(0.13, 0.13, 0.16, 0.9)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_stylebox_override("normal", cell_style)
	btn.add_theme_stylebox_override("hover", cell_style)
	btn.add_theme_stylebox_override("pressed", cell_style)

	# 文本: 名称 (换行截断) + 数量
	btn.text = "%s" % name
	if name.length() > 5:
		btn.text = name.substr(0, 5) + "…"

	# 左键点击 → 弹操作菜单 (与点击丧尸弹动作菜单同一模式)
	btn.pressed.connect(_on_cell_pressed.bind(item_id, btn))
	# 右键点击 → 同样弹操作菜单 (手机无右键, 左键为主路径)
	btn.gui_input.connect(_on_cell_gui_input.bind(item_id, btn))
	return btn


## 空格子 (4×4 网格空位, 不可交互)
func _make_empty_cell() -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15, 0.5)
	sb.border_color = Color(0.25, 0.25, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	cell.add_theme_stylebox_override("panel", sb)
	return cell


## 格子输入: 右键也弹操作菜单 (手机无右键, 保留左键为主路径)
func _on_cell_gui_input(event: InputEvent, item_id: String, btn: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_cell_pressed(item_id, btn)


## 点击物品格 → 弹通用操作菜单 (拿走 / 详情 / 丢弃)
func _on_cell_pressed(item_id: String, btn: Control = null) -> void:
	_selected_item_id = item_id
	var pos: Vector2 = _panel.position + Vector2(120, 120)
	if btn:
		pos = btn.get_global_rect().position
	_item_menu.show_at(pos, item_id, "container", _on_item_menu_action)


## 隐藏操作菜单
func _hide_item_menu() -> void:
	if _item_menu:
		_item_menu.hide_menu()
	_selected_item_id = ""


## 通用菜单回调 (容器 context: 拿走 / 详情 / 丢弃)
func _on_item_menu_action(action_id: String, item_id: String) -> void:
	match action_id:
		"take":
			_on_menu_take_for(item_id)
		"discard":
			_on_menu_discard_for(item_id)
		"detail":
			# 查看详情: 复用 HUD 的详情面板 (HUD 是场景节点, 通过树查找)
			var hud := get_tree().root.find_child("HUD", true, false)
			if hud and hud.has_method("_show_item_detail"):
				hud._show_item_detail(item_id)
			_hide_item_menu()


## 菜单: 拿走
func _on_menu_take() -> void:
	_on_menu_take_for(_selected_item_id)


func _on_menu_take_for(item_id: String) -> void:
	_hide_item_menu()
	if item_id != "":
		_on_item_pressed(item_id)


## 菜单: 丢弃 → 从容器移除 + 通知场景生成地面物品 (可再捡起)
func _on_menu_discard() -> void:
	_on_menu_discard_for(_selected_item_id)


func _on_menu_discard_for(item_id: String) -> void:
	_hide_item_menu()
	if item_id == "" or not _container:
		return
	_container.remove_internal_item(item_id)
	item_discarded.emit(item_id, 1)
	print("[ContainerUI] 丢弃 ", item_id, " → 地面")
	_refresh()


## 全部拿走: 逐个尝试拾取, 直到容器清空或背包超重
func _on_take_all_pressed() -> void:
	if not _container:
		return
	_hide_item_menu()
	var any_failed := false
	while not _container.is_empty() and not any_failed:
		var remaining: Array = _container.list_inventory()
		if remaining.is_empty():
			break
		var item_id: String = remaining[0].get("item_id", "")
		if item_id == "":
			break
		var result := InventoryBackpack.try_add_item(item_id, 1)
		if result.get("success", false):
			_container.remove_internal_item(item_id)
		else:
			any_failed = true  # 背包满/超重 → 停止, 保留剩余
	if _container.is_empty():
		print("[ContainerUI] 全部拿走完毕")
	else:
		_show_overflow()
		print("[ContainerUI] 部分拿走, 背包已满/超重")
	_refresh()


func _on_item_pressed(item_id: String) -> void:
	if not _container:
		return
	var result := InventoryBackpack.try_add_item(item_id, 1)
	if result.get("success", false):
		_container.remove_internal_item(item_id)
		print("[ContainerUI] 拾取 ", item_id, " → 背包")
		_refresh()
	else:
		_show_overflow()


## 超重提示
func _show_overflow() -> void:
	_overflow_label.visible = true
	_overflow_timer = OVERFLOW_DURATION
