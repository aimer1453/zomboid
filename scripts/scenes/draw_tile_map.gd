class_name DrawTileMap
extends Node2D

# ============================================================
# DrawTileMap — TileMapLayer 的可靠替代 (Node2D 自定义绘制)
# ============================================================
# 背景: 本项目里 TileMapLayer 渲染不可靠 (迷雾 TileMap 和地图 tile
# 都不显示, 见 2026-08-05 记忆) — cell 数据/atlas 像素全对, 但屏幕上看不到。
# 方案: Node2D._draw() 一次绘制所有格子, 渲染保证可见, 且只有 1 个 draw call,
#       性能比几百个 ColorRect 更好。
# 接口与 TileMapLayer 兼容 (set_cell/get_cell_source_id/get_cell_atlas_coords/
# get_used_cells), 替换时只需改创建语句。

## 格子像素 — 从场景 tile_size 传入 (用户反馈: combat_test tile_size=64 但 TILE_SIZE 硬编码 32 → 墙是主角一半)
## 创建后必须设置: dtm.tile_size = <场景 tile_size>
var tile_size: int = 32

## tile index → 颜色 (与 tile_set_builder.gd Tiles 枚举颜色保持一致!)
##   FLOOR=0 灰褐 / WALL=1 石墙灰(不再用白色方块) / DOOR=2 高亮金橙(一眼可辨的出口) / EXIT=3 亮绿 / LOOT=4 金 / STAIRS=6 蓝青(楼梯)
const TILE_COLORS := {
	0: Color(0.55, 0.5, 0.44),
	1: Color(0.32, 0.33, 0.38),
	2: Color(0.98, 0.78, 0.22),
	3: Color(0.3, 0.62, 0.35),
	4: Color(0.85, 0.7, 0.25),
	6: Color(0.24, 0.52, 0.62),
}
## 格子 z_index (负值画在主角/敌人之下, 避免格子线盖在角色方块上)
## (用户反馈: 网格线穿过主角让格子看起来比主角小很多)
const TILE_Z := -1
## 格子边界线颜色 (浅灰, 画在格子之间, 让每个格子边界清晰可见 → 视觉上与主角一格等大)
## DrawTileMap z=-1 在主角之下, 边界线不会穿过主角方块
const GRID_LINE := Color(0.62, 0.62, 0.65, 0.35)
const GRID_LINE_W := 1.0

var _cells: Dictionary = {}  # Vector2i -> tile_index


## 当前格子像素 (供场景断言: 地图格 == 单位格大小, 单位 tile_size)
func get_tile_px() -> int:
	return tile_size


## 设置格子 (source=-1 表示清除; coords.x 是 tile index, 兼容 TileMapLayer 签名)
func set_cell(cell: Vector2i, source: int = -1, coords: Vector2i = Vector2i.ZERO) -> void:
	if source == -1:
		_cells.erase(cell)
	else:
		_cells[cell] = coords.x
	queue_redraw()


func get_cell_source_id(cell: Vector2i) -> int:
	return 0 if _cells.has(cell) else -1


func get_cell_atlas_coords(cell: Vector2i) -> Vector2i:
	if not _cells.has(cell):
		return Vector2i(-1, -1)
	return Vector2i(_cells[cell], 0)


func get_used_cells() -> Array:
	return _cells.keys()


func _ready() -> void:
	z_index = TILE_Z  # 画在主角/敌人之下, 避免格子线盖在角色方块上


func _draw() -> void:
	var size_v := Vector2(tile_size, tile_size)
	for cell: Vector2i in _cells:
		var idx: int = _cells[cell]
		var color: Color = TILE_COLORS.get(idx, Color(0.5, 0.5, 0.5))
		var rect := Rect2(Vector2(cell.x * tile_size, cell.y * tile_size), size_v)
		draw_rect(rect, color)
		# 门 / 院门: 画门框+门缝, 让"墙上的开口"一眼可辨 (区别于纯色块墙)
		# idx 2 = TSB.Tiles.DOOR, 3 = TSB.Tiles.EXIT
		if idx == 2:
			_draw_door_decoration(rect, size_v)
		elif idx == 3:
			_draw_exit_decoration(rect, size_v)
		elif idx == 6:
			_draw_stairs_decoration(rect, size_v)
		# 格子边界线 (浅灰半透明): 画在格与格之间, 让每个格子边界可见
		# (用户反馈: 墙连成一片白看不出"一格"; DrawTileMap z=-1 在主角下, 线不会穿过角色)
		draw_rect(rect, GRID_LINE, false, GRID_LINE_W)


## 门: 深棕门框 + 内嵌门板 + 中央门缝 + 黄铜把手 → 在灰墙里清楚是"出口"
## (用户反馈: 门框太粗会溢出墙的范围 → fw 调细, 框收在门洞内)
func _draw_door_decoration(rect: Rect2, size_v: Vector2) -> void:
	var frame := Color(0.30, 0.18, 0.05)
	var fw := maxf(size_v.x * 0.06, 1.5)
	draw_rect(rect, frame, false, fw)                       # 门框
	var inner := Color(0.80, 0.58, 0.16)
	draw_rect(Rect2(rect.position + Vector2(fw, fw), size_v - Vector2(fw, fw) * 2.0), inner)  # 门板
	var seam_x := rect.position.x + size_v.x * 0.5
	draw_rect(Rect2(seam_x - 1.0, rect.position.y + fw, 2.0, size_v.y - fw * 2.0), frame)      # 门缝
	draw_circle(Vector2(rect.position.x + size_v.x * 0.68, rect.position.y + size_v.y * 0.5), maxf(size_v.x * 0.07, 2.0), Color(0.95, 0.85, 0.3))  # 把手


## 院门: 绿底 + 白框 + 向上箭头 (出口标记)
## (用户反馈: 门框太粗会溢出墙的范围 → fw 调细)
func _draw_exit_decoration(rect: Rect2, size_v: Vector2) -> void:
	var frame := Color(0.1, 0.4, 0.15)
	var fw := maxf(size_v.x * 0.06, 1.5)
	draw_rect(rect, frame, false, fw)
	var cx := rect.position.x + size_v.x * 0.5
	var top := rect.position.y + size_v.y * 0.22
	var bot := rect.position.y + size_v.y * 0.74
	var tri := Color(0.85, 1.0, 0.85)
	draw_rect(Rect2(cx - 3.0, top, 6.0, bot - top), tri)    # 竖杆
	draw_polygon(PackedVector2Array([Vector2(cx, top - 7.0), Vector2(cx - 8.0, top + 3.0), Vector2(cx + 8.0, top + 3.0)]), [tri])  # 箭头


## 楼梯: 蓝青底 + 阶梯横线 (上下楼一目了然)
func _draw_stairs_decoration(rect: Rect2, size_v: Vector2) -> void:
	var frame := Color(0.12, 0.34, 0.42)
	var fw := maxf(size_v.x * 0.14, 2.5)
	draw_rect(rect, frame, false, fw)
	var inner := Color(0.30, 0.62, 0.74)
	draw_rect(Rect2(rect.position + Vector2(fw, fw), size_v - Vector2(fw, fw) * 2.0), inner)
	# 阶梯横线 (3 条)
	var lines := 3
	for i in range(1, lines + 1):
		var y := rect.position.y + size_v.y * float(i) / float(lines + 1)
		draw_rect(Rect2(rect.position.x + fw, y - 1.0, size_v.x - fw * 2.0, 2.0), Color(0.1, 0.28, 0.36))
