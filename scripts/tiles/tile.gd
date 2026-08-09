class_name Tile
extends Node2D

# ============================================================
# Tile — 格子基类 (所有格子元素的概念统一)
# ============================================================
# 格子体系:
#   Tile (本类: 格子坐标 + 类型 + 可走性)
#   ├── 地形类 Terrain  → TileMapLayer 数据 (WALL/GROUND/STAIR/ELEVATOR)
#   ├── 角色类 Character → CharacterBody2D 实现同一格子接口 (get_grid_pos)
#   └── 家具类 Furniture → 箱子/柜子等 (本类直接继承, 可交互搜刮)
#
# 蓝色格子(玩家移动范围) / 红色格子(丧尸警戒) / 单位格子(角色/家具)
# 全部以 32px 格子为单位对齐, 视觉与逻辑统一。

## 格子大类
enum TileType { TERRAIN, CHARACTER, FURNITURE }

## 地形子类 (TERRAIN 时使用)
enum TerrainKind { GROUND, WALL, STAIR, ELEVATOR }

var tile_type: TileType = TileType.TERRAIN
var terrain_kind: TerrainKind = TerrainKind.GROUND

## 格子坐标 (以 0,0 为地图原点)
var grid_pos: Vector2i = Vector2i.ZERO
## 是否可站立/通过
var walkable: bool = true

## 所属世界 (提供 is_cell_walkable 等)
var world: Node = null

## 占位渲染色 (无美术资源阶段)
var render_color: Color = Color(0.5, 0.5, 0.5)


## 设置格子坐标并定位到格子中心
func set_grid(gp: Vector2i, tile_size: int) -> void:
	grid_pos = gp
	position = Vector2(gp.x * tile_size + tile_size * 0.5, gp.y * tile_size + tile_size * 0.5)


## 世界坐标 → 格子坐标 (静态工具)
static func world_to_grid(world_pos: Vector2, tile_size: int) -> Vector2i:
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


## 格子坐标 → 世界坐标 (格子中心, 静态工具)
static func grid_to_world(gp: Vector2i, tile_size: int) -> Vector2:
	return Vector2(gp.x * tile_size + tile_size * 0.5, gp.y * tile_size + tile_size * 0.5)


func is_walkable() -> bool:
	return walkable


func get_grid_pos() -> Vector2i:
	return grid_pos


func get_tile_type() -> TileType:
	return tile_type
