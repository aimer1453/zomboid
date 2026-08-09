class_name Furniture
extends "res://scripts/tiles/tile.gd"

# 家具类型: 决定掉落表 (不同家具刷不同物品, 如医院药柜 vs 文件柜)
enum FurnType { WARDROBE, CABINET, MED_CABINET, FILE_CABINET, SHELF, FRIDGE, DESK, CRATE, SAFE, LOCKER }

# 家具类型 → 中文显示名
const FURN_NAMES := {
	FurnType.WARDROBE: "衣柜",
	FurnType.CABINET: "储物柜",
	FurnType.MED_CABINET: "药柜",
	FurnType.FILE_CABINET: "文件柜",
	FurnType.SHELF: "货架",
	FurnType.FRIDGE: "冰箱",
	FurnType.DESK: "书桌",
	FurnType.CRATE: "木箱",
	FurnType.SAFE: "保险箱",
	FurnType.LOCKER: "更衣柜",
}

# 家具类型 → 主体颜色 (视觉上区分不同家具)
const FURN_COLORS := {
	FurnType.WARDROBE: Color(0.72, 0.5, 0.24),
	FurnType.CABINET: Color(0.72, 0.5, 0.24),
	FurnType.MED_CABINET: Color(0.88, 0.34, 0.38),
	FurnType.FILE_CABINET: Color(0.58, 0.55, 0.50),
	FurnType.SHELF: Color(0.82, 0.70, 0.38),
	FurnType.FRIDGE: Color(0.68, 0.78, 0.85),
	FurnType.DESK: Color(0.66, 0.55, 0.42),
	FurnType.CRATE: Color(0.60, 0.46, 0.30),
	FurnType.SAFE: Color(0.50, 0.46, 0.30),
	FurnType.LOCKER: Color(0.50, 0.60, 0.55),
}

# ============================================================
# Furniture — 家具类格子 (衣柜/箱子)
# ============================================================
# 容器: 内部随机刷新的物品列表。玩家点击 → 打开容器界面 (ContainerUI),
# 点击物品 → 尝试放入角色背包, 负重不足弹超重提示。
# 阻挡通行。

var inventory: Array = []   # 内部物品 id 列表
var searched: bool = false
var furniture_name: String = "衣柜"
var furniture_type: int = FurnType.WARDROBE

var _rect: ColorRect = null
var _label: Label = null
var _tile_size: int = 32

signal opened(furniture: Furniture)
signal closed(furniture: Furniture)


func setup(gp: Vector2i, tile_size: int, pool: Array, count: int = 3, fname: String = "衣柜", ftype: int = -1) -> void:
	_tile_size = tile_size
	set_grid(gp, tile_size)
	tile_type = TileType.FURNITURE
	walkable = false
	if ftype >= 0:
		furniture_type = ftype
	render_color = FURN_COLORS.get(furniture_type, Color(0.72, 0.5, 0.24))
	furniture_name = fname if fname != "" else FURN_NAMES.get(furniture_type, "柜子")
	# 随机生成内部物品
	inventory.clear()
	for i in count:
		if pool.is_empty():
			break
		inventory.append(pool[randi() % pool.size()])
	_build_visual()


func _build_visual() -> void:
	# 主体 (原始尺寸, 用户要求还原衣柜等家具)
	_rect = ColorRect.new()
	_rect.size = Vector2(_tile_size * 0.75, _tile_size * 0.6)
	_rect.color = render_color
	_rect.position = Vector2(-_rect.size.x / 2, -_rect.size.y / 2)
	# 纯视觉: 不拦截鼠标 (否则会吞掉点击/让悬停高亮被隐藏)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	# 边框 (与地面区分)
	var border := ColorRect.new()
	border.size = _rect.size
	border.position = _rect.position
	border.color = Color(0.95, 0.85, 0.6, 1.0)
	border.size = Vector2(_rect.size.x, 3)
	border.position = Vector2(_rect.position.x, _rect.position.y - 2)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	_label = Label.new()
	_label.text = furniture_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	# 锚点居中 + 覆盖主体区域 → 文字真正居中 (用户反馈: 衣柜/雨水收集器/健身器材名字偏移)
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.size = _rect.size
	_label.position = _rect.position
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# 点击检测区域 (供场景射线检测)
	var area := Area2D.new()
	area.name = "ClickArea"
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = _tile_size * 0.5
	collision.shape = shape
	area.add_child(collision)
	add_child(area)


## 是否已清空
func is_empty() -> bool:
	return inventory.is_empty()


## 移除内部物品
func remove_internal_item(item_id: String) -> void:
	inventory.erase(item_id)
	if inventory.is_empty():
		searched = true
		_rect.color = Color(0.35, 0.28, 0.2)
		if _label:
			_label.text = "已空"


## 内部物品详情列表 (供 ContainerUI 展示, 含稀有度用于边框)
func list_inventory() -> Array:
	var result: Array = []
	for id in inventory:
		var item := DataManager.get_item(id)
		result.append({
			"item_id": id,
			"name": item.name if item else id,
			"weight": item.weight if item else 0.0,
			"value": item.value if item else 0,
			"type": item.type if item else 0,
			"description": item.description if item else "",
			"rarity": item.rarity if item else 0,
		})
	return result
