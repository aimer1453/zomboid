extends Node2D

# ============================================================
# UnitHealthBar — 单位头顶血条 (战斗时显示)
# ============================================================
# 背景条 + 按 HP 比例变色的填充条 + "80/100" 文字。
# 挂在 Character 上 (局部坐标), 由 TurnManager.combat_started/ended 控制显隐,
# hp_changed 信号驱动实时更新。
#
# 用法:
#   var bar := UHB.new()
#   bar.setup(tile_size)
#   add_child(bar)
#   bar.update_health(hp, max_hp)

var _fill: ColorRect = null
var _label: Label = null
var _width: float = 56.0
var _height: float = 7.0


func setup(tile_size: int) -> void:
	_width = maxf(tile_size * 0.95, 48.0)
	_height = maxf(tile_size * 0.12, 6.0)
	# 位置: 单位头顶上方
	position = Vector2(-_width / 2.0, -tile_size * 0.85)

	# 背景 (最底)
	var bg := ColorRect.new()
	bg.size = Vector2(_width, _height)
	bg.color = Color(0.08, 0.08, 0.1, 0.9)
	# 纯视觉: 不拦截鼠标 (否则会吞掉点击/让悬停高亮被隐藏)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 填充 (盖在背景上, 左对齐, 宽度按比例)
	_fill = ColorRect.new()
	_fill.size = Vector2(_width, _height)
	_fill.color = Color(0.3, 0.85, 0.35)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	# HP 文字 "80/100" 居中显示在血条内部 (用户反馈: 数字放在血条正中间)
	# label 高度 14px 让 11px 字号+outline 4px 装得下; y 起点 -3.5 使 label 中心对齐血条中心 y=3.5
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = Vector2(_width, 14.0)
	# label 水平范围与血条背景完全重合 (0 ~ _width), 文字在范围内居中;
	# 之前 x=-_width/2 导致文字相对血条整体偏左
	_label.position = Vector2(0.0, -3.5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	visible = false
	z_index = 40


## 抵消父节点走路倾斜, 保持血条水平
func _process(_delta: float) -> void:
	var p := get_parent()
	if p and p.rotation != 0.0:
		rotation = -p.rotation
	elif rotation != 0.0:
		rotation = 0.0


func update_health(hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	_fill.size = Vector2(_width * ratio, _height)
	# 绿 → 黄 → 红
	if ratio > 0.5:
		_fill.color = Color(0.3, 0.85, 0.35)
	elif ratio > 0.25:
		_fill.color = Color(0.95, 0.8, 0.2)
	else:
		_fill.color = Color(0.9, 0.3, 0.25)
	_label.text = "%d/%d" % [int(ceil(hp)), int(ceil(max_hp))]


func set_bar_visible(show: bool) -> void:
	visible = show
