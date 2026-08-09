extends Node

# ============================================================
# WorldMapData — 世界地图格子数据层 + 场景路由 (autoload)
# ============================================================
# 主地图 = 战略层网格 (GRID×GRID), 每格是一种地形。
# 家 (HOME) 是其中一格, 走出院门 → 主地图; 点主地图的"家"格 → 回家园。
# 点其他地形格 → 进入对应室内副本 (dungeon_base), 掉落按地形加权。

enum TerrainType { HOME, ROAD, APARTMENT, HOSPITAL, SUPERMARKET, CLINIC, VILLA, PARK, LAB }

const GRID := 8

## 读取 dungeon_base 的 BuildingType 枚举 (仅取值, 不反向 preload 避免循环)
const DungeonScript := preload("res://scripts/dungeons/dungeon_base.gd")

var seed_val: int = 1337
## 扁平数组: GRID*GRID 个 TerrainType
var cells: Array = []
var home_cell: Vector2i = Vector2i.ZERO
## 上次进入副本的主地图格 (返回时标记"你从这里回来", 实现进出口对称: 从哪进从哪出)
var last_entry_cell: Vector2i = Vector2i.ZERO
var has_last_entry: bool = false
## 已探索 (idx -> true), 主地图格踩过/进过才亮
var explored: Dictionary = {}

const TERRAIN_NAMES := {
	TerrainType.HOME: "家",
	TerrainType.ROAD: "公路",
	TerrainType.APARTMENT: "公寓",
	TerrainType.HOSPITAL: "医院",
	TerrainType.SUPERMARKET: "超市",
	TerrainType.CLINIC: "诊所",
	TerrainType.VILLA: "别墅",
	TerrainType.PARK: "公园",
	TerrainType.LAB: "研究所",
}

const TERRAIN_COLORS := {
	TerrainType.HOME: Color(0.3, 0.7, 0.4),
	TerrainType.ROAD: Color(0.40, 0.40, 0.45),
	TerrainType.APARTMENT: Color(0.62, 0.52, 0.38),
	TerrainType.HOSPITAL: Color(0.90, 0.32, 0.36),
	TerrainType.SUPERMARKET: Color(0.30, 0.70, 0.80),
	TerrainType.CLINIC: Color(1.00, 0.50, 0.50),
	TerrainType.VILLA: Color(0.82, 0.70, 0.30),
	TerrainType.PARK: Color(0.40, 0.75, 0.40),
	TerrainType.LAB: Color(0.62, 0.42, 0.82),
}


func _ready() -> void:
	generate()


func _idx(x: int, y: int) -> int:
	return y * GRID + x


## 确定性生成世界格子 (同一种子永远同一张地图)
func generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	cells = []
	for i in GRID * GRID:
		cells.append(TerrainType.ROAD)
	home_cell = Vector2i(GRID / 2, GRID / 2)
	cells[_idx(home_cell.x, home_cell.y)] = TerrainType.HOME
	for y in GRID:
		for x in GRID:
			if Vector2i(x, y) == home_cell:
				continue
			cells[_idx(x, y)] = _random_terrain(rng)
	explored.clear()
	mark_explored(home_cell.x, home_cell.y)
	print("[WorldMapData] 生成世界网格 ", GRID, "x", GRID, " 家位于 ", home_cell)


## 按权重随机地形 (公路/公园常见, 别墅/研究所稀有)
func _random_terrain(rng: RandomNumberGenerator) -> int:
	var weights := [
		{"t": TerrainType.ROAD, "w": 22},
		{"t": TerrainType.PARK, "w": 18},
		{"t": TerrainType.APARTMENT, "w": 16},
		{"t": TerrainType.SUPERMARKET, "w": 14},
		{"t": TerrainType.HOSPITAL, "w": 10},
		{"t": TerrainType.CLINIC, "w": 8},
		{"t": TerrainType.LAB, "w": 7},
		{"t": TerrainType.VILLA, "w": 5},
	]
	var total := 0
	for e in weights:
		total += int(e["w"])
	var roll := rng.randi() % total
	for e in weights:
		roll -= int(e["w"])
		if roll < 0:
			return int(e["t"])
	return TerrainType.ROAD


func terrain_at(x: int, y: int) -> int:
	if x < 0 or x >= GRID or y < 0 or y >= GRID:
		return TerrainType.ROAD
	return int(cells[_idx(x, y)])


func terrain_name(t: int) -> String:
	return TERRAIN_NAMES.get(t, "未知")


func terrain_color(t: int) -> Color:
	return TERRAIN_COLORS.get(t, Color(0.5, 0.5, 0.5))


func is_explored(x: int, y: int) -> bool:
	return explored.has(_idx(x, y))


func mark_explored(x: int, y: int) -> void:
	if x < 0 or x >= GRID or y < 0 or y >= GRID:
		return
	explored[_idx(x, y)] = true


## 标记 (x,y) 自身 + 上下左右四邻居为已探索 (到某地即开一圈图, 不必进副本)
func reveal_neighbors(x: int, y: int) -> void:
	mark_explored(x, y)
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d: Vector2i in dirs:
		mark_explored(x + d.x, y + d.y)


## 是否已在地图上"显示": 自身已探索, 或上下左右四邻居任一已探索
func is_revealed(x: int, y: int) -> bool:
	if is_explored(x, y):
		return true
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for d: Vector2i in dirs:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and nx < GRID and ny >= 0 and ny < GRID:
			if is_explored(nx, ny):
				return true
	return false


## 地形 → 副本 BuildingType (供 dungeon_base 选敌人/掉落)
func terrain_to_dungeon_type(t: int) -> int:
	match t:
		TerrainType.ROAD: return DungeonScript.BuildingType.ROAD
		TerrainType.APARTMENT: return DungeonScript.BuildingType.APARTMENT
		TerrainType.HOSPITAL: return DungeonScript.BuildingType.HOSPITAL
		TerrainType.SUPERMARKET: return DungeonScript.BuildingType.SUPERMARKET
		TerrainType.CLINIC: return DungeonScript.BuildingType.CLINIC
		TerrainType.VILLA: return DungeonScript.BuildingType.VILLA
		TerrainType.PARK: return DungeonScript.BuildingType.PARK
		TerrainType.LAB: return DungeonScript.BuildingType.LAB
	return DungeonScript.BuildingType.APARTMENT


## 每个地点确定性种子 (同格永远同一副本布局)
func location_seed(x: int, y: int) -> int:
	return int(seed_val ^ ((x + 1) * 73856093) ^ ((y + 1) * 19349663)) & 0x7FFFFFFF


## 点格进入: HOME→家园, 其他→对应地形副本
func enter_location(x: int, y: int) -> void:
	last_entry_cell = Vector2i(x, y)
	has_last_entry = true
	var t: int = terrain_at(x, y)
	mark_explored(x, y)
	if t == TerrainType.HOME:
		GameManager.change_state(GameManager.GameState.EXPLORING)
		get_tree().change_scene_to_file("res://scenes/home_base.tscn")
		return
	GameManager.set_meta("pending_dungeon_type", terrain_to_dungeon_type(t))
	GameManager.set_meta("pending_dungeon_seed", location_seed(x, y))
	GameManager.set_meta("pending_dungeon_name", terrain_name(t))
	GameManager.change_state(GameManager.GameState.EXPLORING)
	get_tree().change_scene_to_file("res://scenes/dungeon_base.tscn")


func enter_home() -> void:
	last_entry_cell = home_cell
	has_last_entry = true
	get_tree().change_scene_to_file("res://scenes/home_base.tscn")


## 副本/家园的"出口"统一回到主地图
func return_to_world() -> void:
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")
