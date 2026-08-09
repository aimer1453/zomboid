class_name Corpse
extends "res://scripts/tiles/furniture.gd"

# ============================================================
# Corpse — 丧尸尸体 (继承 Furniture, 兼容 ContainerUI)
# ============================================================
# 死亡时由 enemy_base._spawn_corpse 生成, 躺在地上半透明色块.
# 玩家点击 → 走基类 _raycast_interactable → 场景 _on_interact → ContainerUI.open
# 内部物品由 enemy_base 按类型生成, 搜空后【保留】为"已搜刮"尸体 (标签居中显示"已搜刮", 提示翻过).

## 尸体半透明 + 暗红边框 (视觉上区别于活体敌人和家具)
const CORPSE_ALPHA := 0.78
const CORPSE_BORDER := Color(0.4, 0.08, 0.06, 1.0)
## 尸体标签颜色 (暗红亮字)
const CORPSE_LABEL_COLOR := Color(0.95, 0.7, 0.65)
## 已搜刮尸体的颜色 (更暗, 提示已翻过)
const CORPSE_SEARCHED_COLOR := Color(0.28, 0.15, 0.15)


## 自定义初始化: 用指定物品列表 (不是 Furniture.setup 的随机池)
func setup_corpse(gp: Vector2i, tile_size: int, loot: Array, display_name: String = "尸体") -> void:
	_tile_size = tile_size
	set_grid(gp, tile_size)
	tile_type = TileType.FURNITURE
	walkable = false
	render_color = Color(0.45, 0.22, 0.22)  # 暗红尸体主色
	furniture_name = display_name
	inventory = loot.duplicate()
	_build_visual()
	_apply_corpse_look()


## 在 Furniture._build_visual 基础上改外观 (半透明 + 暗红边框 + 尸体名标签居中在方块中心)
func _apply_corpse_look() -> void:
	if _rect:
		var c: Color = _rect.color
		c.a = CORPSE_ALPHA
		_rect.color = c
	# 边框: 第二个 ColorRect 是顶部亮边 (Furniture._build_visual 顺序: _rect, border, _label)
	for child in get_children():
		if child is ColorRect and child != _rect:
			child.color = CORPSE_BORDER
	# 显示尸体名标签 (如 "丧尸尸体"), 用暗红亮色区分普通家具; 居中在尸体方块中心
	if _label:
		_label.text = furniture_name
		_label.add_theme_color_override("font_color", CORPSE_LABEL_COLOR)
		_label.visible = true
		_center_label()


## 标签居中于方块中心: 文字可能比方块大(如 "普通丧尸\n(尸体)" 两行约 40×28 > 方块 24×19),
## 不能硬塞成方块尺寸——content min size 会把标签撑大且仍按左上角对齐 → 中心偏移。
## 正确做法: 取标签真实尺寸, 把【标签中心】对齐到方块中心 (双 CENTER 保证文字自身也居中)。
func _center_label() -> void:
	if not _label or not _rect:
		return
	var label_size: Vector2 = _label.get_combined_minimum_size()
	_label.size = label_size
	_label.position = _rect.position + (_rect.size - label_size) * 0.5
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## 搜空后保留为"已搜刮"尸体 (不消失): 变暗 + 标签居中显示"已搜刮", 玩家可再次打开看空格子
func remove_internal_item(item_id: String) -> void:
	super.remove_internal_item(item_id)
	if inventory.is_empty():
		_apply_searched_look()


## 已搜刮外观: 变暗 + 标签改"已搜刮" (居中显示)
func _apply_searched_look() -> void:
	searched = true
	if _rect:
		var c: Color = CORPSE_SEARCHED_COLOR
		c.a = CORPSE_ALPHA * 0.8
		_rect.color = c
	if _label:
		_label.text = "已搜刮"
		_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
		_center_label()
