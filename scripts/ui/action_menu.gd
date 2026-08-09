class_name ActionMenu
extends CanvasLayer

# ============================================================
# ActionMenu — 点击敌人的弹出动作菜单
# ============================================================
# 手机友好: 点击敌人 → 在点击位置弹出动作列表 (攻击手段/异能/道具)
# 选择后执行回调, 或点"取消"关闭。点其他位置自动关闭。

var _panel: PanelContainer = null
var _list: VBoxContainer = null
var _selected_callback: Callable = Callable()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 0.94)
	sb.border_color = Color(0.55, 0.55, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_panel.add_child(_list)

	add_child(_panel)


## 在屏幕位置弹出动作菜单
## actions: Array[Resource] (CombatAction); on_selected(action) 回调
func show_at(screen_pos: Vector2, actions: Array, on_selected: Callable) -> void:
	_selected_callback = on_selected

	for child in _list.get_children():
		child.queue_free()

	if actions.is_empty():
		var empty := Label.new()
		empty.text = "没有可用动作"
		empty.add_theme_font_size_override("font_size", 15)
		_list.add_child(empty)
	else:
		for action in actions:
			var btn := Button.new()
			var action_name: String = action.get("action_name") if action.get("action_name") != null else "动作"
			var ap: int = int(action.get("ap_cost") if action.get("ap_cost") != null else 0)
			btn.text = "%s\n(AP %d)" % [action_name, ap]
			btn.custom_minimum_size = Vector2(170, 58)
			btn.add_theme_font_size_override("font_size", 15)
			btn.pressed.connect(_on_action_pressed.bind(action))
			_list.add_child(btn)

	# 取消按钮
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(170, 46)
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(hide_menu)
	_list.add_child(cancel)

	_position_panel(screen_pos)


## 通用操作列表 (label + callback), 用于主角地板"坐下/锻炼"等场景操作
func show_generic(screen_pos: Vector2, entries: Array) -> void:
	_selected_callback = Callable()  # 通用项自带 callback, 不用统一回调
	for child in _list.get_children():
		child.queue_free()
	for entry in entries:
		var btn := Button.new()
		var label: String = entry.get("label", "动作")
		var cb: Callable = entry.get("callback", Callable())
		btn.text = label
		btn.custom_minimum_size = Vector2(170, 52)
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_generic_pressed.bind(cb))
		_list.add_child(btn)
	_position_panel(screen_pos)


func _on_generic_pressed(cb: Callable) -> void:
	hide_menu()
	if cb.is_valid():
		cb.call()


## 面板定位 (避免出屏)
func _position_panel(screen_pos: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var pos := screen_pos + Vector2(12, 12)
	if pos.x + 190 > viewport_size.x:
		pos.x = maxf(viewport_size.x - 200, 4)
	if pos.y + 280 > viewport_size.y:
		pos.y = maxf(viewport_size.y - 300, 4)
	_panel.position = pos
	_panel.visible = true


func _on_action_pressed(action: Resource) -> void:
	var cb := _selected_callback
	hide_menu()
	if cb.is_valid():
		cb.call(action)


func hide_menu() -> void:
	_panel.visible = false


## 屏幕坐标是否在菜单面板内 (场景 _input 判断: 点在面板内交给按钮处理, 不关闭菜单)
func is_point_on_panel(screen_pos: Vector2) -> bool:
	if not _panel or not _panel.visible:
		return false
	return _panel.get_global_rect().has_point(screen_pos)


func is_open() -> bool:
	return _panel != null and _panel.visible
