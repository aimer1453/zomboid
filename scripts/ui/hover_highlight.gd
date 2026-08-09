extends Node2D

# ============================================================
# HoverHighlight — 鼠标悬停地块高亮 (选中地块标记)
# ============================================================
# 用户反馈: "对鼠标选中的地块高亮一下或者标记出来" (悬停高亮, 不是点击标记)
# 用法: hover.set_cell_center(world_cell_center, tile_size)  每帧更新; hide_highlight() 隐藏

var tile_size: int = 32
var _cell_center: Vector2 = Vector2.ZERO
var _visible_flag: bool = false

## 高亮颜色 (亮黄半透明 + 亮边框)
const FILL_COLOR := Color(1.0, 0.9, 0.3, 0.28)
const BORDER_COLOR := Color(1.0, 0.95, 0.4, 0.9)


## 设置悬停格中心 (世界坐标), 未对齐时自动吸附
func set_cell_center(world_pos: Vector2, t_size: int = 32) -> void:
	tile_size = t_size
	_cell_center = Vector2(
		floor(world_pos.x / tile_size) * tile_size + tile_size * 0.5,
		floor(world_pos.y / tile_size) * tile_size + tile_size * 0.5
	)
	_visible_flag = true
	queue_redraw()


func hide_highlight() -> void:
	_visible_flag = false
	queue_redraw()


func _draw() -> void:
	if not _visible_flag:
		return
	var half := tile_size * 0.5
	var rect := Rect2(_cell_center - Vector2(half, half), Vector2(tile_size, tile_size))
	draw_rect(rect, FILL_COLOR, true)
	draw_rect(rect, BORDER_COLOR, false, 2.0)
