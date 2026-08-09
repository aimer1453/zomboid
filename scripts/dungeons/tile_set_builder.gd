class_name TileSetBuilder
extends RefCounted

# ============================================================
# TileSetBuilder — 代码构建占位 TileSet (无美术资源阶段)
# ============================================================
# atlas 布局 (tile 32x32):
#   (0,0)=地板  (1,0)=墙  (2,0)=门  (3,0)=出口  (4,0)=战利品  (5,0)=黑幕(迷雾)

const TILE_W := 32
const TILE_H := 32

enum Tiles { FLOOR = 0, WALL = 1, DOOR = 2, EXIT = 3, LOOT = 4, FOG = 5, STAIRS = 6 }

static func build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_W, TILE_H)

	var src := TileSetAtlasSource.new()
	var atlas := Image.create(TILE_W * 6, TILE_H, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.2, 0.18, 0.16))

	# 地板 (亮灰褐, 与墙拉开明度)
	_fill_tile(atlas, Tiles.FLOOR, Color(0.55, 0.5, 0.44), 0.28)
	# 墙 (亮砖红 + 砖缝纹理, 强对比: 既区别于地板, 也区别于移动范围蓝色叠加)
	_fill_tile(atlas, Tiles.WALL, Color(0.72, 0.25, 0.22), 0.0)
	_draw_wall_texture(atlas, Tiles.WALL)
	# 门 (木棕, 画门板纹理 → 与地板明显区分, 开口一眼可辨)
	_fill_tile(atlas, Tiles.DOOR, Color(0.55, 0.36, 0.18), 0.35)
	_draw_door_texture(atlas, Tiles.DOOR)
	# 出口 (亮绿)
	_fill_tile(atlas, Tiles.EXIT, Color(0.3, 0.62, 0.35), 0.3)
	# 战利品 (金)
	_fill_tile(atlas, Tiles.LOOT, Color(0.85, 0.7, 0.25), 0.3)
	# 黑幕 (未探索迷雾, 不透明纯黑)
	atlas.fill_rect(Rect2i(Tiles.FOG * TILE_W, 0, TILE_W, TILE_H), Color(0, 0, 0, 1.0))

	src.texture = ImageTexture.create_from_image(atlas)
	for i in 6:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)

	# 物理层: 只有墙是实心的
	ts.add_physics_layer()
	return ts


static func _fill_tile(atlas: Image, tile_id: int, color: Color, border_darken: float) -> void:
	var rect := Rect2i(tile_id * TILE_W, 0, TILE_W, TILE_H)
	atlas.fill_rect(rect, color)
	# 1px 边框让格子可辨识 (border_darken=0 表示不画边框, 留给墙纹理)
	if border_darken > 0.0:
		for x in range(TILE_W):
			atlas.set_pixel(tile_id * TILE_W + x, 0, color.darkened(border_darken))
			atlas.set_pixel(tile_id * TILE_W + x, TILE_H - 1, color.darkened(border_darken))
		for y in range(TILE_H):
			atlas.set_pixel(tile_id * TILE_W, y, color.darkened(border_darken))
			atlas.set_pixel(tile_id * TILE_W + TILE_W - 1, y, color.darkened(border_darken))


## 墙砖纹理: 顶部受光亮边 + 砖缝横线 + 上下排错缝竖线, 视觉上"实心墙"一眼可辨
static func _draw_wall_texture(atlas: Image, tile_id: int) -> void:
	var ox := tile_id * TILE_W
	var base := Color(0.72, 0.25, 0.22)
	# 顶部 5px 亮玫瑰边 (受光, 区别于蓝移动范围叠加)
	for y in range(5):
		var t := 1.0 - float(y) / 5.0
		for x in range(TILE_W):
			atlas.set_pixel(ox + x, y, base.lightened(0.25 * t))
	# 砖缝横线 (深红, 模拟砖块分界)
	for x in range(TILE_W):
		atlas.set_pixel(ox + x, 15, base.darkened(0.5))
		atlas.set_pixel(ox + x, 25, base.darkened(0.5))
	# 上下排错缝竖线 (砖块拼接)
	for y in range(5, 15):
		atlas.set_pixel(ox + 10, y, base.darkened(0.45))
		atlas.set_pixel(ox + 21, y, base.darkened(0.45))
	for y in range(16, 25):
		atlas.set_pixel(ox + 5, y, base.darkened(0.45))
		atlas.set_pixel(ox + 16, y, base.darkened(0.45))
		atlas.set_pixel(ox + 27, y, base.darkened(0.45))


## 门板纹理: 木棕底 + 双开中缝 + 门框 + 把手 (让"墙上的开口"一眼可辨)
static func _draw_door_texture(atlas: Image, tile_id: int) -> void:
	var ox := tile_id * TILE_W
	var base := Color(0.55, 0.36, 0.18)
	# 外框 (深木色)
	for x in range(TILE_W):
		atlas.set_pixel(ox + x, 1, base.darkened(0.55))
		atlas.set_pixel(ox + x, TILE_H - 2, base.darkened(0.55))
	for y in range(TILE_H):
		atlas.set_pixel(ox + 1, y, base.darkened(0.55))
		atlas.set_pixel(ox + TILE_W - 2, y, base.darkened(0.55))
	# 双开中缝 (竖向中线)
	for y in range(2, TILE_H - 2):
		atlas.set_pixel(ox + 15, y, base.darkened(0.6))
		atlas.set_pixel(ox + 16, y, base.darkened(0.6))
	# 门板横线 (木纹)
	for x in range(3, TILE_W - 3):
		atlas.set_pixel(ox + x, 11, base.darkened(0.3))
		atlas.set_pixel(ox + x, 21, base.darkened(0.3))
	# 门把手 (左右各一, 亮黄铜点)
	atlas.set_pixel(ox + 12, 16, Color(0.85, 0.7, 0.3))
	atlas.set_pixel(ox + 19, 16, Color(0.85, 0.7, 0.3))
