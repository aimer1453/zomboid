class_name GroundItem
extends "res://scripts/tiles/tile.gd"

# ============================================================
# GroundItem — 地面物品 (从容器/背包丢弃后掉落在地上)
# ============================================================
# 玩家在容器界面选"丢弃"或从背包丢出 → 场景生成此节点, 落在玩家附近地面.
# 玩家点击 → 场景 _raycast_interactable 命中 → _on_interact → pick_up() 拾回背包.
# 视觉: 黄褐色底 + 稀有度色顶边 (一眼看出品质) + 物品名标签.
# 不阻挡通行 (walkable = true).

var item_id: String = ""
var count: int = 1

var _rect: ColorRect = null
var _label: Label = null
var _tile_size: int = 32


## 初始化: 指定物品与数量, 落点由场景传入
func setup(gp: Vector2i, tile_size: int, p_item_id: String, p_count: int = 1) -> void:
	_tile_size = tile_size
	item_id = p_item_id
	count = p_count
	set_grid(gp, tile_size)
	tile_type = Tile.TileType.FURNITURE
	walkable = true  # 地面物品不阻挡通行
	_build_visual()


## 供场景识别: 这是地面物品 (非容器)
func is_ground_item() -> bool:
	return true


func _build_visual() -> void:
	var item = DataManager.get_item(item_id) if DataManager else null
	var rarity: int = item.rarity if item else 0
	var rarity_color: Color = DataManager.RARITY_COLORS.get(rarity, Color(0.9, 0.85, 0.4)) if DataManager else Color(0.9, 0.85, 0.4)
	var display_name: String = item.name if item else item_id

	# 主体: 黄褐色半透明方块 (地面上显眼)
	_rect = ColorRect.new()
	_rect.size = Vector2(_tile_size * 0.55, _tile_size * 0.55)
	_rect.color = Color(0.78, 0.74, 0.5, 0.85)
	_rect.position = Vector2(-_rect.size.x / 2, -_rect.size.y / 2)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	# 顶边 = 稀有度色 (品质一眼可辨)
	var border := ColorRect.new()
	border.size = Vector2(_rect.size.x, 2)
	border.position = Vector2(_rect.position.x, _rect.position.y - 2)
	border.color = rarity_color
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	# 物品名标签 (多件显示 ×N)
	_label = Label.new()
	_label.text = display_name + (" ×%d" % count if count > 1 else "")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_label.position = Vector2(-_tile_size * 0.7, -_tile_size * 0.5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## 拾取: 尝试放入背包 → 成功则从场景注销并移除; 失败 (超重/满) 留在原地
func pick_up() -> Dictionary:
	var result: Dictionary = InventoryBackpack.try_add_item(item_id, count)
	if result.get("success", false):
		var world := get_parent()
		if world and world.has_method("remove_ground_item"):
			world.remove_ground_item(self)
		queue_free()
		return {"success": true, "item_id": item_id, "count": count}
	return result
