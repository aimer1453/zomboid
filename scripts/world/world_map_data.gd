extends Node

# ============================================================
# WorldMapData — 无限程序化世界地图数据层 + 场景路由 (autoload)
# ============================================================
# 主地图 = 无限战略层网格, 每格是一种地形。
# 家 (HOME) 固定在原点 (0,0); 其余格子按需(懒)确定性生成:
#   主角走到一个新格子 → 生成该格 + 其 8 邻居 → 视野(迷雾)向外扩展。
# 已生成的地形 + 已探索(视野)状态都记录在字典里, 并随存档持久化,
# 因此地图既是无限的, 又不会丢失已探索过的部分。
# 点 ROAD/PARK(纯路程) → 仅旅行; 点建筑(公寓/医院/超市/...) → 进入对应副本。

enum TerrainType { HOME, ROAD, APARTMENT, HOSPITAL, SUPERMARKET, CLINIC, VILLA, PARK, LAB }

const SEED: int = 1337

## 读取 dungeon_base 的 BuildingType 枚举 (仅取值, 不反向 preload 避免循环)
const DungeonScript := preload("res://scripts/dungeons/dungeon_base.gd")

## 地形 → 是否"可进入的地点"(进副本); ROAD/PARK 为纯路程, 不进副本
const BUILDING_TERRAINS := {
	TerrainType.APARTMENT: true,
	TerrainType.HOSPITAL: true,
	TerrainType.SUPERMARKET: true,
	TerrainType.CLINIC: true,
	TerrainType.VILLA: true,
	TerrainType.LAB: true,
}

## 已生成地形: key="x,y" -> TerrainType
var tiles: Dictionary = {}
## 已探索(视野): key="x,y" -> true
var explored: Dictionary = {}
## 家固定在原点
var home_cell: Vector2i = Vector2i.ZERO
## 主角当前所在世界格 (主地图旅行用)
var player_cell: Vector2i = Vector2i.ZERO
## 上次进入副本的主地图格 (返回时标记"你从这里回来", 进出口对称)
var last_entry_cell: Vector2i = Vector2i.ZERO
var has_last_entry: bool = false

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

## 去饱和调色板: 相近明度, 不刺眼; 公路=深中性灰(路程), 家=柔绿, 其余柔色
const TERRAIN_COLORS := {
	TerrainType.HOME: Color(0.30, 0.60, 0.48),
	TerrainType.ROAD: Color(0.26, 0.28, 0.32),
	TerrainType.APARTMENT: Color(0.52, 0.44, 0.33),
	TerrainType.HOSPITAL: Color(0.64, 0.36, 0.38),
	TerrainType.SUPERMARKET: Color(0.30, 0.54, 0.58),
	TerrainType.CLINIC: Color(0.70, 0.46, 0.46),
	TerrainType.VILLA: Color(0.62, 0.54, 0.32),
	TerrainType.PARK: Color(0.33, 0.50, 0.33),
	TerrainType.LAB: Color(0.48, 0.40, 0.60),
}

## 地形生成权重 (公路占多数→形成路网; 建筑/公园散布其中)
const _TILE_WEIGHTS := [
	{"t": TerrainType.ROAD, "w": 38},
	{"t": TerrainType.PARK, "w": 14},
	{"t": TerrainType.APARTMENT, "w": 16},
	{"t": TerrainType.SUPERMARKET, "w": 10},
	{"t": TerrainType.HOSPITAL, "w": 7},
	{"t": TerrainType.CLINIC, "w": 6},
	{"t": TerrainType.VILLA, "w": 4},
	{"t": TerrainType.LAB, "w": 5},
]


func _ready() -> void:
	reset_map()


func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


## 新游戏/重置: 家在原点, 生成家 + 邻居, 主角站在家, 家四周已探索
func reset_map() -> void:
	tiles.clear()
	explored.clear()
	home_cell = Vector2i.ZERO
	player_cell = home_cell
	has_last_entry = false
	last_entry_cell = home_cell
	# 显式放置家, 并生成其 8 邻居
	tiles[_key(home_cell.x, home_cell.y)] = TerrainType.HOME
	reveal_neighbors(home_cell.x, home_cell.y)
	print("[WorldMapData] 重置无限地图, 家位于 ", home_cell)


## 确定性地形哈希 (同 (x,y) 永远同一种子 → 同地形)
func _hash(x: int, y: int) -> int:
	var h: int = int(SEED)
	h = (h ^ (x * 73856093)) & 0x7FFFFFFF
	h = (h ^ (y * 19349663)) & 0x7FFFFFFF
	return h


## 单格确定性地形 (家固定返回 HOME)
func gen_tile(x: int, y: int) -> int:
	if Vector2i(x, y) == home_cell:
		return TerrainType.HOME
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(x, y)
	var total := 0
	for e in _TILE_WEIGHTS:
		total += int(e["w"])
	var roll := rng.randi() % total
	for e in _TILE_WEIGHTS:
		roll -= int(e["w"])
		if roll < 0:
			return int(e["t"])
	return TerrainType.ROAD


## 确保某格地形已生成 (懒生成)
func ensure_tile(x: int, y: int) -> void:
	var k := _key(x, y)
	if not tiles.has(k):
		tiles[k] = gen_tile(x, y)


func terrain_at(x: int, y: int) -> int:
	ensure_tile(x, y)
	return int(tiles[_key(x, y)])


func terrain_name(t: int) -> String:
	return TERRAIN_NAMES.get(t, "未知")


func terrain_color(t: int) -> Color:
	return TERRAIN_COLORS.get(t, Color(0.4, 0.4, 0.4))


## 该地形是否为"可进入地点"(进副本); ROAD/PARK 不是
func is_building(t: int) -> bool:
	return BUILDING_TERRAINS.get(t, false)


func is_explored(x: int, y: int) -> bool:
	return explored.has(_key(x, y))


func mark_explored(x: int, y: int) -> void:
	explored[_key(x, y)] = true


## 标记 (x,y) 自身 + 8 邻居为已探索并生成其地形 (到某地即开一圈图)
func reveal_neighbors(x: int, y: int) -> void:
	mark_explored(x, y)
	ensure_tile(x, y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			ensure_tile(x + dx, y + dy)
			mark_explored(x + dx, y + dy)


## 是否已在地图上"显示": 自身已探索, 或 8 邻居任一已探索
func is_revealed(x: int, y: int) -> bool:
	if is_explored(x, y):
		return true
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if is_explored(x + dx, y + dy):
				return true
	return false


## 主角移动到世界格: 记录位置 + 生成该格与 8 邻居(视野扩展)
func move_player_to(x: int, y: int) -> void:
	player_cell = Vector2i(x, y)
	reveal_neighbors(x, y)


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
	return int(SEED ^ ((x + 1) * 73856093) ^ ((y + 1) * 19349663)) & 0x7FFFFFFF


## 点格进入: HOME→家园, 建筑→对应地形副本, ROAD/PARK→仅移动(不应到这)
func enter_location(x: int, y: int) -> void:
	player_cell = Vector2i(x, y)
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
	# 主线里程碑: 探索一处副本 (步骤 2)
	if GameManager and GameManager.has_method("advance_story"):
		GameManager.advance_story(2)
	get_tree().change_scene_to_file("res://scenes/dungeon_base.tscn")


func enter_home() -> void:
	player_cell = home_cell
	last_entry_cell = home_cell
	has_last_entry = true
	get_tree().change_scene_to_file("res://scenes/home_base.tscn")


## 副本/家园的"出口"统一回到主地图
func return_to_world() -> void:
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")


# --- 存档持久化 (无限地图可序列化: 仅存已生成/已探索的部分) ---

func serialize() -> Dictionary:
	return {
		"home": [home_cell.x, home_cell.y],
		"player": [player_cell.x, player_cell.y],
		"tiles": tiles.duplicate(),
		"explored": explored.duplicate(),
		"last_entry": [last_entry_cell.x, last_entry_cell.y],
		"has_last_entry": has_last_entry,
	}


func deserialize(d: Dictionary) -> void:
	if d.is_empty():
		return
	var h: Array = d.get("home", [0, 0])
	home_cell = Vector2i(int(h[0]), int(h[1]))
	var p: Array = d.get("player", [home_cell.x, home_cell.y])
	player_cell = Vector2i(int(p[0]), int(p[1]))
	tiles = d.get("tiles", {})
	explored = d.get("explored", {})
	var le: Array = d.get("last_entry", [home_cell.x, home_cell.y])
	last_entry_cell = Vector2i(int(le[0]), int(le[1]))
	has_last_entry = bool(d.get("has_last_entry", false))
	print("[WorldMapData] 读档恢复地图: 已生成 ", tiles.size(), " 格, 已探索 ", explored.size(), " 格, 主角位于 ", player_cell)
