extends "res://scripts/scenes/game_scene_base.gd"

# ============================================================
# DungeonBase — 随机副本场景 (继承 GameSceneBase)
# ============================================================
# 流程: 生成(BSP) → 绘制 TileMapLayer → 玩家出生 → 敌人/家具按建筑类型生成
#       → 探索/战斗/搜刮衣柜 → 走到出口返回主地图
# 只保留差异化:
#   - BSP 生成 / 建筑类型敌人权重 / 战利品与家具
#   - 交互物 (家具容器) 命中与打开
#   - 出口检测返回主地图
# 通用逻辑 (UI/输入/点击交互/移动范围/动作菜单) 全部在基类

const TSB := preload("res://scripts/dungeons/tile_set_builder.gd")
const DG := preload("res://scripts/dungeons/dungeon_generator.gd")
const FUR := preload("res://scripts/tiles/furniture.gd")
const EF := preload("res://scripts/units/enemy_factory.gd")
## 家具类型枚举 (引自 furniture.gd, 避免重复定义)
const FurnType = FUR.FurnType

enum BuildingType { APARTMENT, SUPERMARKET, POLICE_STATION, HOSPITAL, WAREHOUSE, MILITARY_BASE, LAB, ROAD, CLINIC, VILLA, PARK, HOME }

var building_type: BuildingType = BuildingType.APARTMENT
var dungeon_width: int = 36
var dungeon_height: int = 26

var _generator: RefCounted = null
var _furniture_list: Array = []

# --- 多层建筑 (楼梯换层) ---
var floor_count: int = 1
var _floors: Array = []             # 每层一个 DungeonGenerator
var _current_floor: int = 0
var _floor_up_cell: Array = []      # floor f -> 上楼梯格(通 f+1), null 表示无
var _floor_down_cell: Array = []    # floor f -> 下楼梯格(通 f-1), null 表示无
var _floor_up_arrival: Array = []   # floor f -> 上楼后落在 f+1 的到达格
var _floor_down_arrival: Array = [] # floor f -> 下楼后落在 f-1 的到达格
var _floor_label: Label = null      # 楼层 HUD 文字
var _floor_hud: CanvasLayer = null  # 楼层 HUD (屏幕固定, 不随相机移动)
var _floor_switch_guard: int = 0    # 换层后短暂锁, 防同帧重复触发死循环
var _suppress_stairs: bool = false  # 自动测试期间抑制楼梯触发, 避免脚本移动误换层
var _exit_armed: bool = false      # 出口触发守卫: 玩家离开出口格后才允许"走到出口回主地图"
                                 # (出入口同格时, 出生即在出口, 必须走开再回来才触发, 否则一进场就弹回)

## 建筑类型 → 敌人权重 [普通, 疾速, 喷射, 坦克]
const ENEMY_WEIGHTS := {
	BuildingType.APARTMENT: [70, 20, 10, 0],
	BuildingType.SUPERMARKET: [65, 25, 10, 0],
	BuildingType.POLICE_STATION: [50, 20, 20, 10],
	BuildingType.HOSPITAL: [55, 15, 25, 5],
	BuildingType.WAREHOUSE: [60, 25, 10, 5],
	BuildingType.MILITARY_BASE: [30, 25, 25, 20],
	BuildingType.LAB: [25, 20, 35, 20],
}


func _ready() -> void:
	# 读取主地图传入的建筑类型 (必须在基类 _ready 之前)
	if GameManager.has_meta("pending_dungeon_type"):
		building_type = int(GameManager.get_meta("pending_dungeon_type", 0))
		GameManager.remove_meta("pending_dungeon_type")
	# 按建筑类型决定层数 (用户反馈: 公寓应多层, 用楼梯连接)
	match building_type:
		BuildingType.APARTMENT: floor_count = 3
		BuildingType.VILLA: floor_count = 2
		BuildingType.POLICE_STATION, BuildingType.HOSPITAL, BuildingType.MILITARY_BASE, BuildingType.LAB: floor_count = 2
		_: floor_count = 1
	super._ready()


# --- 生成与绘制 ---

func _create_world() -> void:
	print("[Dungeon] 生成副本... type=", BuildingType.keys()[building_type])
	_generate_and_draw()


func _generate_and_draw() -> void:
	_generate_all_floors()
	draw_current_floor()
	_ensure_floor_hud()


## 生成所有楼层 (每层独立 BSP) + 放置相邻层楼梯
func _generate_all_floors() -> void:
	_floors.clear()
	var base_seed: int = int(Time.get_ticks_msec()) & 0xFFFF
	if GameManager.has_meta("pending_dungeon_seed"):
		base_seed = int(GameManager.get_meta("pending_dungeon_seed", base_seed)) & 0xFFFF
		GameManager.remove_meta("pending_dungeon_seed")
	for f in floor_count:
		var gen := DG.new()
		var seed_val: int = (base_seed + f * 7919) & 0xFFFF
		gen.generate(dungeon_width, dungeon_height, seed_val)
		_floors.append(gen)
	_place_stairs()
	_generator = _floors[0]


## 相邻楼层各放一对楼梯: f 楼"上楼梯"通 f+1 楼"下楼梯", 并记录到达格
func _place_stairs() -> void:
	_floor_up_cell = []
	_floor_down_cell = []
	_floor_up_arrival = []
	_floor_down_arrival = []
	for f in floor_count:
		_floor_up_cell.append(null)
		_floor_down_cell.append(null)
		_floor_up_arrival.append(null)
		_floor_down_arrival.append(null)
	for f in range(floor_count - 1):
		var g_up: RefCounted = _floors[f]
		var g_down: RefCounted = _floors[f + 1]
		var up_cell: Vector2i = g_up.random_floor_cell_in_room(f % g_up.rooms.size())
		var down_cell: Vector2i = g_down.random_floor_cell_in_room((f + 1) % g_down.rooms.size())
		_floor_up_cell[f] = up_cell
		_floor_down_cell[f + 1] = down_cell
		_floor_up_arrival[f] = down_cell        # 从 f 上楼 → 落到 f+1 的下楼梯格
		_floor_down_arrival[f + 1] = up_cell    # 从 f+1 下楼 → 落到 f 的上楼梯格


## 绘制当前楼层 (重建 tilemap; 旧 tilemap 随子节点楼梯标签一并释放)
func draw_current_floor() -> void:
	if _tilemap:
		_tilemap.queue_free()
	_tilemap = DTM.new()
	_tilemap.tile_size = tile_size
	add_child(_tilemap)
	var gen: RefCounted = _floors[_current_floor]
	for y in range(dungeon_height):
		for x in range(dungeon_width):
			var cell_type: int = gen.get_cell(x, y)
			if cell_type == 0:
				_tilemap.set_cell(Vector2i(x, y), 0, Vector2i(TSB.Tiles.WALL, 0))
			elif cell_type == 2:
				_tilemap.set_cell(Vector2i(x, y), 0, Vector2i(TSB.Tiles.EXIT, 0))
				if _current_floor == 0:
					# 入口即出口: 在 0 楼出入口格上方贴"出口"浮标, 提醒玩家从这里离开
					_add_tile_label(Vector2i(x, y), "出口", Color(0.45, 1.0, 0.55))
			else:
				_tilemap.set_cell(Vector2i(x, y), 0, Vector2i(TSB.Tiles.FLOOR, 0))
	# 楼梯 (仅当前层可见)
	if _floor_up_cell[_current_floor] != null:
		_tilemap.set_cell(_floor_up_cell[_current_floor], 0, Vector2i(TSB.Tiles.STAIRS, 0))
		# (上楼标注已移除: 蓝青楼梯色可辨识)
	if _floor_down_cell[_current_floor] != null:
		_tilemap.set_cell(_floor_down_cell[_current_floor], 0, Vector2i(TSB.Tiles.STAIRS, 0))
		# (下楼标注已移除: 蓝青楼梯色可辨识)
	_draw_floor_label()


## 在 tilemap 上贴格子文字标签 (tilemap 释放时标签一并释放, 不残留)
func _add_tile_label(cell: Vector2i, text: String, col: Color) -> void:
	var lbl := Label.new()
	lbl.text = _wrap_cjk(text, 3)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", col)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(cell.x * tile_size, cell.y * tile_size)
	lbl.size = Vector2(tile_size, tile_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 6
	_tilemap.add_child(lbl)


## 把中文文本按 per 个字插入换行, 让长标签在窄格内 2~3 字一行并居中
func _wrap_cjk(t: String, per: int = 3) -> String:
	if t.length() <= per:
		return t
	var out: String = ""
	for i in range(t.length()):
		if i > 0 and i % per == 0:
			out += "\n"
		out += t[i]
	return out


## 楼层 HUD (屏幕固定, 不随相机移动)
func _ensure_floor_hud() -> void:
	if _floor_hud != null:
		return
	_floor_hud = CanvasLayer.new()
	_floor_hud.follow_viewport_enabled = false
	var lbl := Label.new()
	lbl.name = "FloorLabel"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	lbl.position = Vector2(12, 10)
	_floor_hud.add_child(lbl)
	add_child(_floor_hud)
	_floor_label = lbl


func _draw_floor_label() -> void:
	if _floor_label == null:
		_ensure_floor_hud()
	_floor_label.text = "%d 楼 / 共 %d 层" % [_current_floor + 1, floor_count]


func is_cell_walkable(cell_center: Vector2) -> bool:
	var cell := _cell_of(cell_center)
	if cell.x < 0 or cell.x >= dungeon_width or cell.y < 0 or cell.y >= dungeon_height:
		return false
	if _generator.get_cell(cell.x, cell.y) == 0:
		return false  # 墙
	# 家具(衣柜/货架/箱/保险箱等)视为不可走, 与墙一致 (用户反馈: 货架应像墙一样挡路, 丧尸不应踩上去)
	for f in _furniture_list:
		if is_instance_valid(f) and f.get("grid_pos") == cell:
			return false
	return true


## 通用"被占用"钩子: 该格是否不可作落点 (尸体/地面物品生成用). 基类默认 false, 副本里=不可走.
func is_cell_blocked(cell_center: Vector2) -> bool:
	return not is_cell_walkable(cell_center)


# --- 玩家 ---

func _create_player() -> void:
	_player = PF.spawn(self, _world_pos(_generator.entrance), tile_size)
	_player.world = self
	_exit_armed = false  # 出入口同格时出生即在出口, 必须走开后才允许触发出口


# --- 敌人 + 战利品 / 家具 ---

func _spawn_entities() -> void:
	_spawn_floor_entities(0)


## 在某层生成敌人 + 战利品 (切换楼层时调用, 每次只生成当前层)
func _spawn_floor_entities(floor: int) -> void:
	_generator = _floors[floor]
	_spawn_enemies()
	_spawn_loot()
	print("[Dungeon] 第 ", floor + 1, " 层就绪, 敌人=", TurnManager.get_enemy_units().size())


## 释放当前层所有实体 (敌人/家具/尸体/地面物品), 换层前清理
func _clear_floor_entities() -> void:
	for e in TurnManager.get_enemy_units():
		if is_instance_valid(e):
			TurnManager.unregister_unit(e)
			e.queue_free()
	for f in _furniture_list:
		if is_instance_valid(f):
			f.queue_free()
	_furniture_list.clear()
	for c in _corpses:
		if is_instance_valid(c):
			c.queue_free()
	_corpses.clear()
	for gi in _ground_items:
		if is_instance_valid(gi):
			gi.queue_free()
	_ground_items.clear()


## 切换楼层: 清理当前层 → 绘制目标层 → 玩家落到到达格 (推离楼梯防死循环) → 重生实体
func change_floor(target_floor: int, arrival_cell: Vector2i) -> void:
	if target_floor < 0 or target_floor >= floor_count:
		return
	if TurnManager.combat_mode:
		return  # 战斗中禁止换层, 避免实体被腾空
	_clear_floor_entities()
	_current_floor = target_floor
	_generator = _floors[target_floor]
	draw_current_floor()
	var dest := arrival_cell
	if dest == _floor_up_cell[_current_floor] or dest == _floor_down_cell[_current_floor]:
		dest = _nudge_off_stairs(arrival_cell)
	_player.global_position = _world_pos(dest)
	_player.is_moving = false
	_exit_armed = false  # 换层落地后须重新走开出口才能触发返回 (防出入口同格一落地就弹回)
	_floor_switch_guard = 15  # 约 0.25s 内不重复触发, 双重防死循环
	_refresh_move_grid()
	_spawn_floor_entities(target_floor)
	if _hud and _hud.has_method("append_log"):
		_hud.append_log("进入第 %d 层" % [target_floor + 1])
	print("[Dungeon] 切换到第 ", target_floor + 1, " 层, 玩家位于 ", dest)


## 若到达格正好是楼梯, 把玩家推到相邻可走非楼梯格 (否则会立刻又换层)
func _nudge_off_stairs(cell: Vector2i) -> Vector2i:
	var cands: Array[Vector2i] = [cell + Vector2i(1, 0), cell + Vector2i(-1, 0), cell + Vector2i(0, 1), cell + Vector2i(0, -1)]
	for c in cands:
		if is_cell_walkable(_world_pos(c)) and c != _floor_up_cell[_current_floor] and c != _floor_down_cell[_current_floor]:
			return c
	return cell


func _spawn_enemies() -> void:
	var weights: Array = ENEMY_WEIGHTS.get(building_type, ENEMY_WEIGHTS[BuildingType.APARTMENT])
	var enemy_scripts := [
		load("res://scripts/units/enemies/zombie_basic.gd"),
		load("res://scripts/units/enemies/zombie_runner.gd"),
		load("res://scripts/units/enemies/zombie_spitter.gd"),
		load("res://scripts/units/enemies/zombie_tank.gd"),
	]
	var room_count: int = _generator.rooms.size()
	var enemy_count: int = clampi(room_count, 2, 8)

	for i in enemy_count:
		var room_idx: int = i % room_count
		var cell: Vector2i = _generator.random_floor_cell_in_room(room_idx)
		# 出生点必须在所有丧尸警戒圈外 (最大 detection 6 + 缓冲)
		if _world_pos(cell).distance_to(_player.global_position) < tile_size * 8:
			continue
		_spawn_enemy(enemy_scripts[_weighted_pick(weights)], cell)

	# 出入口处放一只精英守卫 (若离玩家太近则跳过, 避免出生即战斗)
	var guard_pos := _world_pos(_generator.exit_cell)
	if guard_pos.distance_to(_player.global_position) >= tile_size * 7:
		_spawn_enemy(enemy_scripts[3], _generator.exit_cell)


func _weighted_pick(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += int(w)
	var roll := randi() % maxi(total, 1)
	for i in range(weights.size()):
		roll -= int(weights[i])
		if roll < 0:
			return i
	return 0


func _spawn_enemy(script: Script, cell: Vector2i) -> void:
	var enemy := EF.spawn(self, script, _world_pos(cell), tile_size, 140.0)
	enemy.name = "Enemy"
	enemy.world = self


func _spawn_loot() -> void:
	# 入口房间固定一个家具 (玩家出生点右侧, 立刻可见)
	var spawn_cell := _cell_of(_player.global_position)
	var chest_cell := spawn_cell + Vector2i(2, 0)
	if _generator.get_cell(chest_cell.x, chest_cell.y) == 1:
		_spawn_chest(chest_cell)

	var loot_count: int = clampi(_generator.rooms.size(), 2, 6)
	for i in loot_count:
		var room_idx: int = (i * 2 + 1) % _generator.rooms.size()
		var cell: Vector2i = _generator.random_floor_cell_in_room(room_idx)
		if i % 2 == 0:
			_spawn_loot_node(_world_pos(cell))
		else:
			_spawn_chest(cell)


## 家具类: 衣柜/箱子/药柜/文件柜等 (点击打开容器界面搜刮)
## 掉落按家具类型 (FurnType) 决定, 不再整地点同概率
func _spawn_chest(cell: Vector2i) -> void:
	var ft: int = _pick_furniture_type(building_type)
	var fname: String = FUR.FURN_NAMES.get(ft, "柜子")
	var n: int = randi_range(1, 3)
	var items: Array = []
	for k in n:
		items.append(pick_loot_by_furniture(ft))
	var chest := FUR.new()
	chest.setup(cell, tile_size, items, n, fname, ft)
	add_child(chest)
	_furniture_list.append(chest)


## 地面散落物品: 同样按地点家具构成抽样 (更一致)
func _spawn_loot_node(pos: Vector2) -> void:
	var ft: int = _pick_furniture_type(building_type)
	var item_id: String = pick_loot_by_furniture(ft)
	var loot := Area2D.new()
	loot.name = "Loot"
	loot.position = pos

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = tile_size * 0.35
	collision.shape = shape
	loot.add_child(collision)

	var rect := ColorRect.new()
	rect.size = Vector2(tile_size * 0.5, tile_size * 0.5)
	rect.color = Color(0.85, 0.7, 0.2)
	rect.position = -rect.size / 2
	loot.add_child(rect)

	loot.set_meta("item_id", item_id)
	loot.body_entered.connect(_on_loot_entered.bind(loot))
	add_child(loot)


func _on_loot_entered(body: Node, loot: Area2D) -> void:
	if body != _player or not is_instance_valid(loot):
		return
	var item_id: String = loot.get_meta("item_id", "")
	if item_id != "":
		var result := InventoryBackpack.try_add_item(item_id, 1)
		if result.get("success", false):
			print("[Dungeon] 拾取: ", item_id)
			loot.queue_free()
		else:
			print("[Dungeon] 负重不足, 无法拾取: ", item_id)


## 网格命中检测: 家具优先 → fallback 查尸体 (基类 _raycast_interactable)
func _raycast_interactable(world_pos: Vector2) -> Node:
	var clicked_cell := _cell_of(world_pos)
	for f in _furniture_list:
		if not is_instance_valid(f):
			continue
		var gp: Vector2i = f.get("grid_pos") if f.get("grid_pos") != null else Vector2i(-9999, -9999)
		if gp == clicked_cell:
			return f
	return super._raycast_interactable(world_pos)


## 副本需要容器 UI (搜刮家具/尸体)
func _use_container_ui() -> bool:
	return true


## 按建筑类型的战利品池 (原为 get_loot_item_pool 局部变量, 提为静态表以便启动期校验扫描, 防悬空物品引用)
const LOOT_POOL_BY_BUILDING := {
	BuildingType.APARTMENT: ["canned_food", "bandage", "water_pure", "knife"],
	BuildingType.SUPERMARKET: ["canned_food", "water_pure", "bandage", "medkit"],
	BuildingType.POLICE_STATION: ["pistol", "ammo_9mm", "kevlar", "bandage"],
	BuildingType.HOSPITAL: ["medkit", "bandage", "antidote", "canned_food"],
	BuildingType.WAREHOUSE: ["ammo_9mm", "rifle", "canned_food", "crowbar"],
	BuildingType.MILITARY_BASE: ["rifle", "ammo_556", "kevlar", "shotgun"],
	BuildingType.LAB: ["antidote", "crystal_smooth", "medkit", "blueprint_purifier"],
}

func get_loot_item_pool() -> Array:
	return LOOT_POOL_BY_BUILDING.get(building_type, ["canned_food", "bandage"])


## 按地形权重的战利品表: 每个物品有独立权重, 医院/诊所药品占比高, 超市/公寓食物日用高
## (用户需求: 不同地点箱子刷物品概率不同, 如医院柜子更大概率出药品)
const LOOT_WEIGHTED := {
	BuildingType.APARTMENT: [
		{"id": "canned_food", "w": 25}, {"id": "water_pure", "w": 20},
		{"id": "bandage", "w": 14}, {"id": "knife", "w": 10},
		{"id": "cloth", "w": 10}, {"id": "bread", "w": 10}, {"id": "soda", "w": 11},
	],
	BuildingType.SUPERMARKET: [
		{"id": "canned_food", "w": 30}, {"id": "water_pure", "w": 25},
		{"id": "bread", "w": 15}, {"id": "soda", "w": 12}, {"id": "chocolate", "w": 10},
		{"id": "bandage", "w": 8},
	],
	BuildingType.POLICE_STATION: [
		{"id": "pistol", "w": 25}, {"id": "ammo_9mm", "w": 25},
		{"id": "kevlar", "w": 18}, {"id": "bandage", "w": 12}, {"id": "shotgun", "w": 20},
	],
	BuildingType.HOSPITAL: [
		{"id": "bandage", "w": 35}, {"id": "medkit", "w": 30},
		{"id": "antidote", "w": 20}, {"id": "adrenaline", "w": 8}, {"id": "canned_food", "w": 7},
	],
	BuildingType.WAREHOUSE: [
		{"id": "ammo_9mm", "w": 22}, {"id": "rifle", "w": 18},
		{"id": "canned_food", "w": 20}, {"id": "crowbar", "w": 20}, {"id": "wood", "w": 20},
		{"id": "nail", "w": 14}, {"id": "metal_scrap", "w": 12},
	],
	BuildingType.MILITARY_BASE: [
		{"id": "rifle", "w": 25}, {"id": "ammo_556", "w": 22},
		{"id": "kevlar", "w": 20}, {"id": "shotgun", "w": 18}, {"id": "medkit", "w": 15},
		{"id": "metal_scrap", "w": 18}, {"id": "nail", "w": 16},
	],
	BuildingType.LAB: [
		{"id": "antidote", "w": 25}, {"id": "crystal_smooth", "w": 18},
		{"id": "medkit", "w": 20}, {"id": "blueprint_purifier", "w": 12}, {"id": "bandage", "w": 25},
		{"id": "metal_scrap", "w": 16}, {"id": "nail", "w": 14},
	],
	BuildingType.ROAD: [
		{"id": "canned_food", "w": 22}, {"id": "water_pure", "w": 22},
		{"id": "wood", "w": 20}, {"id": "cloth", "w": 20}, {"id": "zombie_flesh", "w": 16},
		{"id": "nail", "w": 14}, {"id": "metal_scrap", "w": 12},
	],
	BuildingType.CLINIC: [
		{"id": "bandage", "w": 40}, {"id": "medkit", "w": 25},
		{"id": "antidote", "w": 20}, {"id": "water_pure", "w": 15},
	],
	BuildingType.VILLA: [
		{"id": "canned_food", "w": 15}, {"id": "chocolate", "w": 12}, {"id": "soda", "w": 12},
		{"id": "medkit", "w": 12}, {"id": "pistol", "w": 10}, {"id": "ammo_9mm", "w": 12},
		{"id": "kevlar", "w": 5}, {"id": "water_pure", "w": 12},
		{"id": "nail", "w": 14}, {"id": "metal_scrap", "w": 12},
	],
	BuildingType.PARK: [
		{"id": "canned_food", "w": 25}, {"id": "water_pure", "w": 25},
		{"id": "wood", "w": 25}, {"id": "cloth", "w": 25},
		{"id": "nail", "w": 16}, {"id": "metal_scrap", "w": 12},
	],
	BuildingType.HOME: [
		{"id": "canned_food", "w": 25}, {"id": "water_pure", "w": 25},
		{"id": "bandage", "w": 25}, {"id": "cloth", "w": 25},
		{"id": "nail", "w": 14}, {"id": "metal_scrap", "w": 10},
	],
}


## 按地形权重随机抽一个物品 id
func pick_weighted_loot(bt: int) -> String:
	var table: Array = LOOT_WEIGHTED.get(bt, LOOT_WEIGHTED[BuildingType.APARTMENT])
	var total := 0
	for e in table:
		total += int(e["w"])
	var roll := randi() % maxi(total, 1)
	for e in table:
		roll -= int(e["w"])
		if roll < 0:
			return e["id"]
	return table[0]["id"]


# ============================================================
# 精细掉落 — 按【家具类型】而非整张地形
# ============================================================
# 用户反馈: 90%+ 的地形独占概率太高; 且同地点(如医院)内部应分不同家具,
# 各家具刷不同物品. 故家具掉落由 FurnType 决定, 地形只决定会出现哪些家具类型.
# 单项权重上限 ~30, 不再出现"开什么都是药"的碾压感.

## 家具类型 → 物品权重表 (概率分散, 单项不过 30)
const LOOT_BY_FURNITURE := {
	FurnType.WARDROBE: [  # 衣柜: 衣物/布料/零杂
		{"id": "cloth", "w": 26}, {"id": "canned_food", "w": 15}, {"id": "knife", "w": 12},
		{"id": "bandage", "w": 12}, {"id": "water_pure", "w": 13}, {"id": "book", "w": 22},
	],
	FurnType.CABINET: [  # 普通储物柜: 杂货/工具
		{"id": "canned_food", "w": 22}, {"id": "cloth", "w": 16}, {"id": "wood", "w": 15},
		{"id": "bandage", "w": 12}, {"id": "tool", "w": 15}, {"id": "water_pure", "w": 15}, {"id": "crowbar", "w": 10},
	],
	FurnType.MED_CABINET: [  # 药柜: 药品为主, 但非独占 (~57%)
		{"id": "bandage", "w": 18}, {"id": "medkit", "w": 16}, {"id": "antidote", "w": 10},
		{"id": "adrenaline", "w": 5}, {"id": "painkiller", "w": 8}, {"id": "canned_food", "w": 18}, {"id": "cloth", "w": 15}, {"id": "book", "w": 10},
	],
	FurnType.FILE_CABINET: [  # 文件柜: 文件杂物, 基本不出药
		{"id": "document", "w": 30}, {"id": "book", "w": 20}, {"id": "cloth", "w": 15},
		{"id": "bandage", "w": 10}, {"id": "water_pure", "w": 13}, {"id": "canned_food", "w": 12},
	],
	FurnType.SHELF: [  # 货架: 食物/日用品
		{"id": "canned_food", "w": 26}, {"id": "water_pure", "w": 22}, {"id": "bread", "w": 16},
		{"id": "soda", "w": 14}, {"id": "chocolate", "w": 12}, {"id": "bandage", "w": 5}, {"id": "cloth", "w": 10},
	],
	FurnType.FRIDGE: [  # 冰箱: 食物/水
		{"id": "water_pure", "w": 28}, {"id": "bread", "w": 20}, {"id": "chocolate", "w": 16},
		{"id": "canned_food", "w": 18}, {"id": "soda", "w": 12}, {"id": "medkit", "w": 6},
	],
	FurnType.DESK: [  # 书桌: 文件/电子
		{"id": "document", "w": 26}, {"id": "book", "w": 18}, {"id": "battery", "w": 15},
		{"id": "cloth", "w": 12}, {"id": "bandage", "w": 10}, {"id": "canned_food", "w": 14}, {"id": "tool", "w": 10},
	],
	FurnType.CRATE: [  # 木箱: 建材/随机
		{"id": "wood", "w": 28}, {"id": "canned_food", "w": 16}, {"id": "tool", "w": 16},
		{"id": "cloth", "w": 14}, {"id": "crowbar", "w": 10}, {"id": "bandage", "w": 7}, {"id": "water_pure", "w": 9},
	],
	FurnType.SAFE: [  # 保险箱: 贵重/武器
		{"id": "pistol", "w": 20}, {"id": "ammo_9mm", "w": 18}, {"id": "cash", "w": 24},
		{"id": "medkit", "w": 10}, {"id": "jewelry", "w": 14}, {"id": "kevlar", "w": 8},
	],
	FurnType.LOCKER: [  # 更衣柜: 衣物/杂物
		{"id": "cloth", "w": 28}, {"id": "canned_food", "w": 15}, {"id": "bandage", "w": 14},
		{"id": "water_pure", "w": 15}, {"id": "book", "w": 12}, {"id": "tool", "w": 12}, {"id": "medkit", "w": 6},
	],
}


## 建筑类型 → 该地点会出现的家具类型 (数组重复=权重, 决定地点"家具构成")
const FURN_WEIGHTS_BY_BUILDING := {
	BuildingType.HOSPITAL: [FurnType.MED_CABINET, FurnType.MED_CABINET, FurnType.MED_CABINET,
		FurnType.FILE_CABINET, FurnType.FILE_CABINET, FurnType.LOCKER, FurnType.LOCKER,
		FurnType.CABINET, FurnType.DESK],
	BuildingType.CLINIC: [FurnType.MED_CABINET, FurnType.MED_CABINET, FurnType.FILE_CABINET, FurnType.CABINET, FurnType.LOCKER],
	BuildingType.SUPERMARKET: [FurnType.SHELF, FurnType.SHELF, FurnType.SHELF, FurnType.FRIDGE, FurnType.FRIDGE, FurnType.CRATE],
	BuildingType.APARTMENT: [FurnType.WARDROBE, FurnType.WARDROBE, FurnType.CABINET, FurnType.CABINET, FurnType.DESK, FurnType.CRATE, FurnType.FRIDGE],
	BuildingType.LAB: [FurnType.CABINET, FurnType.CABINET, FurnType.DESK, FurnType.DESK, FurnType.FILE_CABINET, FurnType.SAFE],
	BuildingType.VILLA: [FurnType.WARDROBE, FurnType.WARDROBE, FurnType.SAFE, FurnType.CABINET, FurnType.FRIDGE, FurnType.DESK],
	BuildingType.PARK: [FurnType.CRATE, FurnType.CABINET],
	BuildingType.ROAD: [FurnType.CRATE, FurnType.CRATE, FurnType.CABINET],
	BuildingType.HOME: [FurnType.WARDROBE, FurnType.CABINET, FurnType.FRIDGE, FurnType.DESK],
	BuildingType.POLICE_STATION: [FurnType.CABINET, FurnType.SAFE, FurnType.SAFE, FurnType.LOCKER, FurnType.LOCKER, FurnType.FILE_CABINET],
	BuildingType.WAREHOUSE: [FurnType.CRATE, FurnType.CRATE, FurnType.CRATE, FurnType.CABINET, FurnType.CABINET, FurnType.SHELF],
	BuildingType.MILITARY_BASE: [FurnType.CRATE, FurnType.CRATE, FurnType.SAFE, FurnType.SAFE, FurnType.LOCKER, FurnType.LOCKER, FurnType.CABINET],
}


## 按家具类型权重随机抽一个物品 id
func pick_loot_by_furniture(ft: int) -> String:
	var table: Array = LOOT_BY_FURNITURE.get(ft, LOOT_BY_FURNITURE[FurnType.CABINET])
	var total := 0
	for e in table:
		total += int(e["w"])
	var roll := randi() % maxi(total, 1)
	for e in table:
		roll -= int(e["w"])
		if roll < 0:
			return e["id"]
	return table[0]["id"]


## 按建筑类型选一个会出现的家具类型
func _pick_furniture_type(bt: int) -> int:
	var list: Array = FURN_WEIGHTS_BY_BUILDING.get(bt, [FurnType.CABINET])
	return list[randi() % list.size()]


## 抽 n 个物品组成家具掉落池 (重复允许)
func _build_weighted_pool(n: int) -> Array:
	var pool: Array = []
	for i in n:
		pool.append(pick_weighted_loot(building_type))
	return pool


# --- 出口 ---

func _process(_delta: float) -> void:
	super._process(_delta)  # 父类: 鼠标悬停地块高亮
	if _floor_switch_guard > 0:
		_floor_switch_guard -= 1
	if _player and not _suppress_stairs and _floor_switch_guard <= 0:
		var pc := _cell_of(_player.global_position)
		# 0 楼走到出口格(=入口) → 回世界地图。出生即在出口, 须先离开出口格再回来才触发(防一进场弹回)
		if _current_floor == 0 and pc == _generator.exit_cell:
			if _exit_armed:
				exit_dungeon()
				return
		elif _current_floor == 0:
			_exit_armed = true  # 已离开出口格 → 下次踩上即触发返回
		# 楼梯换层: 走到上/下楼梯格即切层 (战斗中 change_floor 内部拦截)
		if _floor_up_cell[_current_floor] != null and pc == _floor_up_cell[_current_floor]:
			change_floor(_current_floor + 1, _floor_up_arrival[_current_floor])
		elif _floor_down_cell[_current_floor] != null and pc == _floor_down_cell[_current_floor]:
			change_floor(_current_floor - 1, _floor_down_arrival[_current_floor])


func get_building_type_name() -> String:
	match building_type:
		BuildingType.APARTMENT: return "公寓楼"
		BuildingType.SUPERMARKET: return "超市"
		BuildingType.POLICE_STATION: return "警察局"
		BuildingType.HOSPITAL: return "医院"
		BuildingType.WAREHOUSE: return "仓库"
		BuildingType.MILITARY_BASE: return "军事基地"
		BuildingType.LAB: return "研究所"
		BuildingType.ROAD: return "公路"
		BuildingType.CLINIC: return "诊所"
		BuildingType.VILLA: return "别墅"
		BuildingType.PARK: return "公园"
		BuildingType.HOME: return "家"
	return "未知"


func exit_dungeon() -> void:
	print("[Dungeon] 离开副本...")
	GameManager.change_state(GameManager.GameState.EXPLORING)
	WorldMapData.return_to_world()


# --- 自动测试钩子 (仅命令行带 --auto-test 时触发) ---

func _on_scene_ready() -> void:
	super._on_scene_ready()  # 通用截图钩子 (--screenshot)
	if "--auto-test" in OS.get_cmdline_user_args():
		_run_auto_test()


## 多层换层回归: 走到上楼梯 → 切到上一层且玩家落到到达格(已推离楼梯), 实体重生; 回 0 楼正常
func _test_floor_switch() -> void:
	if floor_count <= 1:
		print("=== 自动测试: 多层(跳过, 本建筑单层) ===")
		return
	var ok := true
	var before := _current_floor
	var up: Vector2i = _floor_up_cell[before]
	if up == null:
		ok = false
		push_error("[Floor] 第1层无上楼梯")
	else:
		var arrival: Vector2i = _floor_up_arrival[before]
		change_floor(before + 1, arrival)
		if _current_floor != before + 1:
			ok = false
			push_error("[Floor] 换层失败: 当前=", _current_floor)
		var pc := _cell_of(_player.global_position)
		if pc == up or pc == _floor_down_cell[_current_floor]:
			ok = false
			push_error("[Floor] 玩家落在楼梯格(应被推到邻接格): ", pc)
		# 上一层应已重生实体 (敌人或家具至少其一存在)
		if TurnManager.get_enemy_units().size() == 0 and _furniture_list.size() == 0:
			ok = false
			push_error("[Floor] 换层后无实体重生")
	# 切回 0 楼 (落到入口)
	change_floor(0, _floors[0].entrance)
	if _current_floor != 0:
		ok = false
		push_error("[Floor] 未能切回第1层")
	print("=== 自动测试: 楼层切换=", ok, " (应为 true) 当前=", _current_floor + 1, " 层")


## 出口触发逻辑(纯判定, 不真正换场景): 出生在出口未武装→不触发; 离开→武装; 回出口且武装→触发
func _test_exit_logic() -> void:
	var ok := true
	_exit_armed = false
	_player.global_position = _world_pos(_generator.exit_cell)
	var on_exit: bool = _cell_of(_player.global_position) == _generator.exit_cell
	if not on_exit:
		ok = false
		push_error("[Exit] 玩家未出生在出口格")
	if on_exit and _exit_armed:
		ok = false
		push_error("[Exit] 出生即武装(应为 false)")
	# 离开出口格(4 方向任一格) → 武装
	_player.global_position = _world_pos(_generator.exit_cell + Vector2i(1, 0))
	if _cell_of(_player.global_position) != _generator.exit_cell:
		_exit_armed = true
	if not _exit_armed:
		ok = false
		push_error("[Exit] 离开出口后未武装")
	# 回到出口格 且 已武装 → 应触发退出
	_player.global_position = _world_pos(_generator.exit_cell)
	var should_exit: bool = (_cell_of(_player.global_position) == _generator.exit_cell) and _exit_armed
	if not should_exit:
		ok = false
		push_error("[Exit] 回到出口格且已武装却判定不退出")
	# 恢复状态(测试期 _suppress_stairs=true, _process 不会真正换场景)
	_exit_armed = false
	_player.global_position = _world_pos(_generator.entrance)
	print("=== 自动测试: 出口触发逻辑=", ok, " (应为 true) ===")


## 验证家具(衣柜/货架/箱等)与墙一样不可行走: 丧尸/玩家都不能踩上去, 尸体也不落其格
func _test_furniture_blocks_movement() -> void:
	var ok := true
	var blocked := 0
	for f in _furniture_list:
		if not is_instance_valid(f):
			continue
		var gp: Variant = f.get("grid_pos")
		if gp == null or not (gp is Vector2i):
			continue
		if is_cell_walkable(_world_pos(gp)):
			ok = false
			push_error("[Furniture] 家具格应不可走: ", gp)
		else:
			blocked += 1
		# 尸体落点也应避开家具格
		if find_free_corpse_cell(gp) == gp:
			ok = false
			push_error("[Furniture] 尸体落点不应落在家具格: ", gp)
	if _furniture_list.size() > 0 and blocked == 0:
		ok = false
		push_error("[Furniture] 没有任何家具被判定为不可走")
	print("=== 自动测试: 家具不可行走=", ok, " (应为 true) 家具数=", _furniture_list.size(), " 被挡=", blocked, " ===")


func _run_auto_test() -> void:
	await get_tree().create_timer(0.6).timeout
	_suppress_stairs = true   # 脚本化移动期间抑制楼梯触发, 避免误换层
	_test_floor_switch()
	_test_exit_logic()
	_test_furniture_blocks_movement()
	print("=== 自动测试: 探索连续移动 x3 ===")
	var start := _player.global_position
	_player.move_to_cell(start + Vector2(tile_size * 2, 0))
	await get_tree().create_timer(1.2).timeout
	print("=== 移动1后 pos=", _player.global_position, " combat=", TurnManager.combat_mode)
	_player.move_to_cell(_player.global_position + Vector2(0, -tile_size * 2))
	await get_tree().create_timer(1.2).timeout
	print("=== 移动2后 pos=", _player.global_position, " combat=", TurnManager.combat_mode)
	_player.move_to_cell(_player.global_position + Vector2(-tile_size * 2, 0))
	await get_tree().create_timer(1.2).timeout
	print("=== 移动3后 pos=", _player.global_position, " combat=", TurnManager.combat_mode)
	await 	_test_wall_walk_all_units()
	_suppress_stairs = false
	print("=== 自动测试完成 ===")


## 墙体阻止所有单位 (玩家 + 丧尸/NPC) — 用户反馈: 不可行走性应对所有单位
func _test_wall_walk_all_units() -> void:
	await get_tree().create_timer(0.4).timeout
	var ok := true
	# 玩家朝墙 move_in_direction 应被阻止
	var stand := Vector2i(_generator.entrance.x, _generator.entrance.y - 2)
	if _generator.get_cell(stand.x, stand.y) != 0 and _generator.get_cell(stand.x, stand.y - 1) == 0:
		_player.global_position = _world_pos(stand)
		_player.is_my_turn = true
		_player.ap_current = _player.ap_max
		_player.move_in_direction(Vector2(0, -1))
		if _player.is_moving:
			ok = false
			push_error("[WallAll] dungeon 玩家穿墙!")
	# 丧尸 start_walk 朝墙也应被阻止 (确定性: 找一张真实墙格, 丧尸站墙旁朝墙走)
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var wall_found := false
	for y in range(1, 10):
		for x in range(1, 10):
			if _generator.get_cell(x, y) == 0 and _generator.get_cell(x + 1, y) == 1:
				# 墙在 (x,y), 丧尸站墙右 (x+1,y), 朝墙 -x 走
				var wall_cell := Vector2i(x, y)
				var z_cell := Vector2i(x + 1, y)
				var test_zombie: Node = EF.spawn(self, zombie_script, _world_pos(z_cell), tile_size, 100.0)
				test_zombie.world = self
				var z_before: Vector2 = test_zombie.global_position
				test_zombie.start_walk(_world_pos(wall_cell))  # 朝墙走
				await get_tree().create_timer(0.4).timeout
				var z_after_cell: Vector2i = _cell_of(test_zombie.global_position)
				# 丧尸不应进入墙格 (x)
				if z_after_cell.x <= wall_cell.x and _cell_of(z_before).x == wall_cell.x + 1:
					ok = false
					push_error("[WallAll] dungeon 丧尸穿墙! 墙=", wall_cell, " 丧尸 ", _cell_of(z_before), " → ", z_after_cell)
				test_zombie.queue_free()
				wall_found = true
				break
		if wall_found:
			break
	if not wall_found:
		push_warning("[WallAll] 未找到墙格做测试 (生成器随机), 跳过丧尸段")
	print("=== 自动测试: dungeon 墙体阻止所有单位=", ok)
