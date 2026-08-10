class_name FogOfWar
extends Node2D

# ============================================================
# FogOfWar — 场景内战争迷雾
# ============================================================
# 行为 (符合需求: 主角醒来只有视野内点亮, 走过/看过的地方保留记忆, 其余被迷雾覆盖):
#   - 主角圆形视野半径内 (vision_radius) -> 全亮 (不绘制, 透明)
#   - 看过/走过的格 -> 半透明黑覆盖 (记忆, 永久可见但变暗)
#   - 从未探索的格   -> 不透明黑覆盖 (战争迷雾)
# 渲染: 纯 Node2D._draw, 跟随世界坐标 (与 tile 同层, 不进 CanvasLayer, 故不遮挡 HUD/菜单)
#       z_index=50 盖住 tile/角色/敌人, 但 CanvasLayer 的 UI 始终在其上.

const FOG_BLACK := Color(0.0, 0.0, 0.0, 0.97)
const FOG_MEMORY := Color(0.0, 0.0, 0.0, 0.55)

## 视野半径 (格), 圆形 (欧氏距离 <= radius)
@export var vision_radius: int = 7

var tile_size: int = 32
## 供基类 _physics_process 比较主角是否换格
var last_cell: Vector2i = Vector2i(-9999, -9999)

var _tilemap: Node = null
var _map_min: Vector2i = Vector2i.ZERO
var _map_max: Vector2i = Vector2i.ZERO
var _explored: Dictionary = {}   # "x,y" -> true (永久记忆)
var _visible: Dictionary = {}    # "x,y" -> true (当前视野内)
var _mem_key: String = ""        # 该场景在全局记忆中的键; 空=不持久化(每次进入重置)
# 全局常驻记忆: key -> { "x,y": true }; 跨场景进入(回家再进家园)保留, 进程内常驻
static var _memories: Dictionary = {}
var _ready_init: bool = false
var _last_count: int = -1
var _last_tilemap: Node = null


func setup(tilemap: Node, ts: int) -> void:
	tile_size = ts
	_tilemap = tilemap
	_recompute_bounds()
	_ready_init = true


## 设置记忆键并从全局常驻记忆恢复该场景已探索格 (跨进入保留视野)
func set_memory_key(k: String) -> void:
	_mem_key = k
	if k != "" and _memories.has(k):
		_explored = _memories[k].duplicate()


## 把当前探索记忆写回全局常驻字典 (离开场景前调用, 或每次 reveal 后)
func persist_memory() -> void:
	if _mem_key != "":
		_memories[_mem_key] = _explored.duplicate()


## --- 全局记忆的存档接口 (常驻进程内, 随存档序列化) ---
static func serialize_memories() -> Dictionary:
	return _memories.duplicate(true)


static func deserialize_memories(d: Dictionary) -> void:
	if d is Dictionary:
		_memories = d.duplicate(true)
	else:
		_memories.clear()


static func clear_memories() -> void:
	_memories.clear()


## 依据 _tilemap 的 used_cells 重算地图包围盒 (换层/重建地图时调用)
func _recompute_bounds() -> void:
	if _tilemap == null or not _tilemap.has_method("get_used_cells"):
		return
	var cells: Array = _tilemap.get_used_cells()
	if cells.is_empty():
		return
	var first: Vector2i = cells[0]
	_map_min = first
	_map_max = first
	for c in cells:
		var cc: Vector2i = c
		_map_min.x = mini(_map_min.x, cc.x)
		_map_min.y = mini(_map_min.y, cc.y)
		_map_max.x = maxi(_map_max.x, cc.x)
		_map_max.y = maxi(_map_max.y, cc.y)
	_last_count = cells.size()
	_last_tilemap = _tilemap


func _ready() -> void:
	z_index = 50   # 盖住世界节点; CanvasLayer(UI) 在其上, 不被遮盖


## 以 player_cell 为中心刷新视野; 看过的格永久记忆
func reveal_from(player_cell: Vector2i) -> void:
	if not _ready_init:
		return
	# 地图可能被重建/换层 (dungeon 多层) -> 边界变化则重算
	if _tilemap != _last_tilemap or (_tilemap != null and _tilemap.has_method("get_used_cells") and _tilemap.get_used_cells().size() != _last_count):
		_recompute_bounds()
	var r: int = vision_radius
	var new_visible: Dictionary = {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var cx: int = player_cell.x + dx
			var cy: int = player_cell.y + dy
			if cx < _map_min.x or cx > _map_max.x or cy < _map_min.y or cy > _map_max.y:
				continue
			var key: String = "%d,%d" % [cx, cy]
			new_visible[key] = true
			_explored[key] = true
	_visible = new_visible
	queue_redraw()
	persist_memory()


## 调试/特殊场景: 显示全图 (取消迷雾)
func reveal_all() -> void:
	if not _ready_init:
		return
	_visible.clear()
	for y in range(_map_min.y, _map_max.y + 1):
		for x in range(_map_min.x, _map_max.x + 1):
			_explored["%d,%d" % [x, y]] = true
	queue_redraw()
	persist_memory()


## 公开查询: 供小地图复用探索/可见状态
func get_map_min() -> Vector2i:
	return _map_min

func get_map_max() -> Vector2i:
	return _map_max

func get_tile_size() -> int:
	return tile_size

func is_explored_cell(cx: int, cy: int) -> bool:
	return _explored.has("%d,%d" % [cx, cy])

func is_visible_cell(cx: int, cy: int) -> bool:
	return _visible.has("%d,%d" % [cx, cy])


func _draw() -> void:
	if not _ready_init:
		return
	var size_v := Vector2(float(tile_size), float(tile_size))
	for y in range(_map_min.y, _map_max.y + 1):
		for x in range(_map_min.x, _map_max.x + 1):
			var key: String = "%d,%d" % [x, y]
			var col: Color
			if _visible.has(key):
				continue
			elif _explored.has(key):
				col = FOG_MEMORY
			else:
				col = FOG_BLACK
			draw_rect(Rect2(Vector2(float(x * tile_size), float(y * tile_size)), size_v), col)
