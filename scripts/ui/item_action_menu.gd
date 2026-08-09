class_name ItemActionMenu
extends CanvasLayer

# ============================================================
# ItemActionMenu — 通用物品格操作菜单 (基类组件)
# ============================================================
# 所有格子共用: 背包格 / 容器(尸体/箱子)格 / 装备槽。
# 按【物品类型 + 上下文 context】生成操作按钮:
#   context = "backpack"  背包格:   消耗品→食用; 装备→穿戴; 其他→丢弃/查看
#   context = "container" 容器格:   拿走 + 丢弃 (搜刮逻辑)
#   context = "equip"     装备槽:   卸下 + 查看详情
# 调用方传入 on_action(action_id, item_id) 回调执行实际逻辑。
# 与 ActionMenu(战斗) 分离: 战斗动作列表是 CombatAction, 这里是物品操作。

var _panel: PanelContainer = null
var _list: VBoxContainer = null
var _callback: Callable = Callable()
var _selected_item_id: String = ""
var _measure_gen: int = 0  # 代际守卫: 防止两次 show_at 同帧重叠时旧协程用旧内容锁尺寸


func _ready() -> void:
	# 弹出操作菜单: 层级必须高于所有其它 UI 面板 (hud=60 / build_menu&ability_tree=70 / container_ui&action_menu=100),
	# 否则作为 container_ui 子节点时会被同 layer 的容器面板盖在下面 (视觉上看不到但能点)
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.95)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_panel.add_child(_list)

	add_child(_panel)


## 在屏幕位置弹出物品操作菜单
## actions: Array[Dictionary]  {action_id, label} — 由 get_actions_for 生成
## on_action(action_id, item_id) 回调
func show_at(screen_pos: Vector2, item_id: String, context: String, on_action: Callable) -> void:
	_selected_item_id = item_id
	_callback = on_action

	# 同步清掉旧按钮 (不能 queue_free 延迟释放: 量尺寸时旧按钮可能还在,
	# 导致第二次弹出的面板把上一次按钮也算进去 → 列表叠加变长)
	for child in _list.get_children():
		_list.remove_child(child)
		child.free()

	var actions := get_actions_for(item_id, context)
	if actions.is_empty():
		var empty := Label.new()
		empty.text = "没有可用操作"
		empty.add_theme_font_size_override("font_size", 14)
		_list.add_child(empty)
	else:
		for a: Dictionary in actions:
			var btn := Button.new()
			btn.text = str(a.get("label", "操作"))
			# 自适应: 不固定宽度, 按钮横向填满面板, 面板宽度由最宽按钮文字决定
			# (用户反馈: 操作列表长度应按可选项按钮自动调节, 不再每个都生成固定 150px)
			# 字号/高度 2× (ItemActionMenu 是 CanvasLayer, 不继承 HUD 的 _ui_root.scale, 需手动放大到与 HUD 同档)
			btn.custom_minimum_size = Vector2(0, 44)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 15)
			btn.pressed.connect(_on_action_pressed.bind(str(a.get("action_id", ""))))
			_list.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(0, 38)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(hide_menu)
	_list.add_child(cancel)

	# 定位: 菜单显示在点击格子的上方 (用户反馈: 之前从格子下方展开, 像"在背包格子下面")
	# 先放屏幕左上测量面板真实尺寸, 再按尺寸摆放
	# 关键: 每次弹出前必须把上次锁定的 custom_minimum_size 清零,
	# 否则第二次(按钮更少)时面板被上次的锁定值撑住 → 量出来还是旧高度 → 下方留一长段空白
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.position = Vector2(-500, -500)
	_panel.visible = true

	# 代际守卫: show_at 被 pressed 信号直接调用(未 await), 两次弹窗可能同帧重叠。
	# 用递增代号标记本次调用, await 回来后若已被更新的调用覆盖则放弃本次测量,
	# 避免旧协程用旧内容(或叠加内容)把 custom_minimum_size 锁成错误的大尺寸。
	var gen: int = _measure_gen + 1
	_measure_gen = gen
	await get_tree().process_frame
	if gen != _measure_gen:
		return
	var panel_size: Vector2 = _panel.size
	# 硬锁定面板尺寸 = 内容尺寸, 杜绝任何布局把菜单拉伸成"长空白"
	_panel.custom_minimum_size = panel_size
	var viewport_size := get_viewport().get_visible_rect().size
	var pos := screen_pos + Vector2(0, -panel_size.y - 4)  # 紧贴格子上方
	if pos.y < 4:
		pos.y = screen_pos.y + 70  # 上方放不下 → 紧贴格子下方
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = maxf(viewport_size.x - panel_size.x - 4, 4)
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = maxf(viewport_size.y - panel_size.y - 4, 4)
	_panel.position = pos


## 核心: 按物品类型 + 上下文生成操作列表 (子类可覆写扩展)
## 返回 Array[Dictionary]  {action_id: String, label: String}
func get_actions_for(item_id: String, context: String) -> Array:
	var actions: Array = []
	var item := DataManager.get_item(item_id)
	if not item:
		return actions
	var type: int = int(item.type)
	var equippable: bool = item.equip_slot != ""

	match context:
		"backpack":
			# 背包格: 消耗品食用; 装备穿戴; 均可丢弃/查看
			if type == DataManager.ItemType.CONSUMABLE:
				actions.append({"action_id": "use", "label": "食用/饮用"})
			if equippable:
				actions.append({"action_id": "equip", "label": "穿戴"})
			actions.append({"action_id": "detail", "label": "查看详情"})
			actions.append({"action_id": "discard", "label": "丢弃"})
			actions.append({"action_id": "discard_all", "label": "丢弃全部"})
		"container":
			# 容器格: 拿走 + 丢弃 (搜刮)
			actions.append({"action_id": "take", "label": "拿走"})
			actions.append({"action_id": "detail", "label": "查看详情"})
			actions.append({"action_id": "discard", "label": "丢弃"})
		"equip":
			# 装备槽: 卸下 + 详情
			actions.append({"action_id": "unequip", "label": "卸下"})
			actions.append({"action_id": "detail", "label": "查看详情"})
		_:
			actions.append({"action_id": "detail", "label": "查看详情"})
	return actions


func _on_action_pressed(action_id: String) -> void:
	var cb := _callback
	var item_id := _selected_item_id
	hide_menu()
	if cb.is_valid():
		cb.call(action_id, item_id)


func hide_menu() -> void:
	_panel.visible = false
	_selected_item_id = ""


## 屏幕坐标是否在菜单面板内 (场景 _input 判断: 点在面板内交给按钮处理, 不关闭)
func is_point_on_panel(screen_pos: Vector2) -> bool:
	if not _panel or not _panel.visible:
		return false
	return _panel.get_global_rect().has_point(screen_pos)


func is_open() -> bool:
	return _panel != null and _panel.visible
