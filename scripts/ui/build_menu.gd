extends CanvasLayer
class_name BuildMenu

# ============================================================
# BuildMenu — 建造/研究面板 (点击工作台打开)
# ============================================================
# 研究区: 未解锁蓝图 + 研究成本 + [研究] 按钮
# 建造区: 已解锁蓝图 + 建造成本 + [建造] 按钮 (点击进入放置模式)
# 信号 build_selected(kind) 交给场景进入建造放置模式

const HF := preload("res://scripts/tiles/home_furniture.gd")

signal build_selected(kind: int)
signal closed()

var _panel: Panel
var _research_box: VBoxContainer
var _build_box: VBoxContainer
var _hint: Label

func _ready() -> void:
	layer = 70
	visible = false

	# 透明根容器 (点面板外不拦截地图)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -400
	_panel.offset_top = 24
	_panel.offset_right = -16
	_panel.offset_bottom = 580
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "建造 / 研究"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	vbox.add_child(title)

	_hint = Label.new()
	_hint.text = "研究解锁蓝图, 建造消耗素材放置家具"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(_hint)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)
	var rl := Label.new()
	rl.text = "— 研究 (消耗素材解锁蓝图) —"
	rl.add_theme_font_size_override("font_size", 13)
	rl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(rl)
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rscroll)
	_research_box = VBoxContainer.new()
	_research_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_box.add_theme_constant_override("separation", 4)
	rscroll.add_child(_research_box)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)
	var bl := Label.new()
	bl.text = "— 建造 (已解锁, 点击放置) —"
	bl.add_theme_font_size_override("font_size", 13)
	bl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	vbox.add_child(bl)
	var bscroll := ScrollContainer.new()
	bscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bscroll)
	_build_box = VBoxContainer.new()
	_build_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_box.add_theme_constant_override("separation", 4)
	bscroll.add_child(_build_box)

	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0, 34)
	close.pressed.connect(_close)
	vbox.add_child(close)


func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	s.border_color = Color(0.4, 0.45, 0.55, 0.8)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(10)
	return s


func _make_row(name: String, cost: Dictionary, button_text: String, affordable: bool, on_press: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := Label.new()
	n.text = name
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	info.add_child(n)
	var c := Label.new()
	c.text = BuildingManager.cost_text(cost)
	c.add_theme_font_size_override("font_size", 10)
	c.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	info.add_child(c)
	row.add_child(info)
	var btn := Button.new()
	btn.text = button_text
	btn.disabled = not affordable
	btn.custom_minimum_size = Vector2(70, 30)
	btn.pressed.connect(on_press)
	row.add_child(btn)
	return row


func open() -> void:
	visible = true
	refresh()


func _close() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	for c in _research_box.get_children():
		c.queue_free()
	for c in _build_box.get_children():
		c.queue_free()
	for kind in BuildingManager.BLUEPRINTS:
		var def: Dictionary = BuildingManager.BLUEPRINTS[kind]
		if BuildingManager.is_researched(kind):
			# 已研究 → 建造区
			var cost: Dictionary = BuildingManager.build_cost(kind)
			var row := _make_row(def["name"], cost, "建造",
				BuildingManager.can_afford(cost), _on_build_pressed.bind(kind))
			_build_box.add_child(row)
		else:
			# 未研究 → 研究区
			var cost: Dictionary = BuildingManager.research_cost(kind)
			var row := _make_row(def["name"], cost, "研究",
				BuildingManager.can_afford(cost), _on_research_pressed.bind(kind))
			_research_box.add_child(row)
	if _research_box.get_child_count() == 0:
		var done := Label.new()
		done.text = "(全部蓝图已研究)"
		done.add_theme_font_size_override("font_size", 11)
		done.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_research_box.add_child(done)


func _on_research_pressed(kind: int) -> void:
	var r: Dictionary = BuildingManager.research(kind)
	_set_hint(r.get("message", ""))
	refresh()


func _on_build_pressed(kind: int) -> void:
	_close()
	build_selected.emit(kind)


func _set_hint(msg: String) -> void:
	if _hint:
		_hint.text = msg if msg != "" else "研究解锁蓝图, 建造消耗素材放置家具"
