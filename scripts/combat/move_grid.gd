class_name MoveGrid
extends Node2D

# ============================================================
# MoveGrid — 可移动范围高亮显示
# ============================================================
# 以玩家位置为中心, 用曼哈顿距离绘制可移动格子。
# 纯绘制组件, 不处理输入; 点击逻辑由 CombatTest 统一处理。

var tile_size: int = 64
var center_pos: Vector2 = Vector2.ZERO
var range_tiles: int = 0
var show: bool = false

## 高亮颜色 (红色: 可移动范围, 用户反馈不要蓝色)
const FILL_COLOR := Color(0.9, 0.25, 0.25, 0.22)
const BORDER_COLOR := Color(1.0, 0.4, 0.4, 0.55)


## 设置移动范围数据; 默认不画红色格子 (用户反馈: 视觉范围用战争迷雾体现, 不需要红色格子标注)
## 仅保留 is_cell_in_range 逻辑判断
func set_range(center: Vector2, tiles: int, show_visual: bool = false) -> void:
	center_pos = center
	range_tiles = maxi(tiles, 0)
	show = show_visual and range_tiles > 0
	queue_redraw()


func hide_grid() -> void:
	show = false
	queue_redraw()


## 世界坐标是否在可移动范围内 (逻辑判断, 不依赖视觉 show)
func is_cell_in_range(world_pos: Vector2) -> bool:
	if range_tiles <= 0:
		return false
	var delta: Vector2 = world_pos - center_pos
	var cell := Vector2i(roundi(delta.x / tile_size), roundi(delta.y / tile_size))
	return absi(cell.x) + absi(cell.y) <= range_tiles


func _draw() -> void:
	if not show or range_tiles <= 0:
		return
	for y in range(-range_tiles, range_tiles + 1):
		for x in range(-range_tiles, range_tiles + 1):
			if absi(x) + absi(y) > range_tiles:
				continue
			var cell_center: Vector2 = center_pos + Vector2(x, y) * tile_size
			var rect := Rect2(
				cell_center - Vector2(tile_size, tile_size) * 0.5,
				Vector2(tile_size, tile_size)
			)
			draw_rect(rect, FILL_COLOR, true)
			draw_rect(rect, BORDER_COLOR, false, 1.5)
