extends "res://scripts/scenes/game_scene_base.gd"

# ============================================================
# MainMap — 主地图 (程序化城市废墟) (继承 GameSceneBase)
# ============================================================
# 只保留差异化:
#   - 城市生成 (道路网格 + 建筑地块 + 安全屋)
#   - 游荡丧尸 / 建筑入口 → 进副本
# 通用逻辑 (UI/输入/点击交互/移动范围) 全部在基类

const TSB := preload("res://scripts/dungeons/tile_set_builder.gd")
const EF := preload("res://scripts/units/enemy_factory.gd")

const MAP_W := 40
const MAP_H := 28
const TILE := 32

## 建筑类型定义: id → {name, dungeon_type}
const BUILDINGS := [
	{"name": "公寓楼", "dungeon": 0},
	{"name": "超市", "dungeon": 1},
	{"name": "警察局", "dungeon": 2},
	{"name": "医院", "dungeon": 3},
	{"name": "仓库", "dungeon": 4},
	{"name": "军事基地", "dungeon": 5},
	{"name": "研究所", "dungeon": 6},
]

## 建筑入口: 入口格 → 建筑索引
var _building_entries: Dictionary = {}
## 地块占用: cell → building index
var _lot_owner: Dictionary = {}
var _home_lot: Vector2i = Vector2i.ZERO


# --- 城市生成 ---

func _create_world() -> void:
	print("[MainMap] 生成城市废墟...")
	tile_size = TILE
	_generate_city()


func _generate_city() -> void:
	_tilemap = DTM.new()  # 自定义绘制 (TileMapLayer 在本项目渲染不可靠, 见 memory)
	_tilemap.tile_size = tile_size  # 与单位格子等大
	add_child(_tilemap)

	# 1. 全部铺地板 (道路地基)
	for y in range(MAP_H):
		for x in range(MAP_W):
			_tilemap.set_cell(Vector2i(x, y), 0, Vector2i(TSB.Tiles.FLOOR, 0))

	# 2. 地图边界墙
	for x in range(MAP_W):
		_set_wall(Vector2i(x, 0))
		_set_wall(Vector2i(x, MAP_H - 1))
	for y in range(MAP_H):
		_set_wall(Vector2i(0, y))
		_set_wall(Vector2i(MAP_W - 1, y))

	# 3. 建筑地块: 3x3 网格布局, 每格 5x4 地块 + 道路隔开
	var grid_cols := 3
	var grid_rows := 3
	var lot_w := 5
	var lot_h := 4
	var road_gap := 2
	var start_x := 3
	var start_y := 2

	var building_idx := 0
	for gy in range(grid_rows):
		for gx in range(grid_cols):
			if building_idx >= BUILDINGS.size():
				break
			var lot_origin := Vector2i(
				start_x + gx * (lot_w + road_gap),
				start_y + gy * (lot_h + road_gap)
			)
			_build_lot(lot_origin, lot_w, lot_h, building_idx)
			building_idx += 1

	# 4. 安全屋: 地图中心附近一块特殊区域
	_home_lot = Vector2i((MAP_W - 4) / 2, (MAP_H - 4) / 2)
	_build_lot(_home_lot, 4, 4, 0, true)


func _build_lot(origin: Vector2i, w: int, h: int, building_idx: int, is_home: bool = false) -> void:
	for y in range(h):
		for x in range(w):
			var cell := origin + Vector2i(x, y)
			_lot_owner[cell] = building_idx
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				_set_wall(cell)
			else:
				_tilemap.set_cell(cell, 0, Vector2i(TSB.Tiles.FLOOR, 0))

	# 入口: 建筑南墙中央开洞 (朝南, 对着道路)
	# 修复: 之前用 h (墙外一行) → 门在墙圈外, 墙圈无开口, 玩家从内部到不了门
	var entrance_cell := origin + Vector2i(w / 2, h - 1)
	if is_home:
		_tilemap.set_cell(entrance_cell, 0, Vector2i(TSB.Tiles.EXIT, 0))
	else:
		_tilemap.set_cell(entrance_cell, 0, Vector2i(TSB.Tiles.DOOR, 0))
		_building_entries[entrance_cell] = building_idx

	# 建筑名标签 (建筑顶部)
	var name_label := Label.new()
	name_label.text = BUILDINGS[building_idx]["name"]
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.position = Vector2(origin.x * TILE + 2, origin.y * TILE - 22)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	add_child(name_label)


func _set_wall(cell: Vector2i) -> void:
	_tilemap.set_cell(cell, 0, Vector2i(TSB.Tiles.WALL, 0))


func is_cell_walkable(cell_center: Vector2) -> bool:
	var cell := _cell_of(cell_center)
	if cell.x < 0 or cell.x >= MAP_W or cell.y < 0 or cell.y >= MAP_H:
		return false
	var data: int = _tilemap.get_cell_source_id(cell)
	if data == -1:
		# 防御: 未设置的格子不可走 (避免漏设格变成可走地面导致穿墙)
		return false
	var coords: Vector2i = _tilemap.get_cell_atlas_coords(cell)
	return coords.x != TSB.Tiles.WALL


## 建筑入口格判断 (Character 用: 非玩家单位不可走入口 → 丧尸不会穿进建筑"绕过墙")
func is_building_entry(cell_center: Vector2) -> bool:
	var cell := _cell_of(cell_center)
	return _building_entries.has(cell)


# --- 玩家 ---

func _create_player() -> void:
	# 出生在安全屋内部地板 (修复: 之前 _home_lot+(2,0) 是北墙格, 玩家出生在墙上 → "墙没挡住单位")
	var spawn_cell := _home_lot + Vector2i(2, 2)
	_player = PF.spawn(self, _world_pos(spawn_cell), TILE)
	_player.world = self


# --- 城市丧尸 ---

func _spawn_entities() -> void:
	_spawn_wandering_zombies()
	print("[MainMap] 城市就绪, 点击建筑入口进入副本")


func _spawn_wandering_zombies() -> void:
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	for i in 3:
		var cell := _random_road_cell()
		if cell == Vector2i.ZERO:
			continue
		var pos := _world_pos(cell)
		# 离出生点远一点
		if pos.distance_to(_player.global_position) < TILE * 6:
			continue
		var zombie := EF.spawn(self, zombie_script, pos, TILE, 120.0)
		zombie.name = "CityZombie_%d" % i
		zombie.world = self


func _random_road_cell() -> Vector2i:
	for attempt in 30:
		var cell := Vector2i(randi_range(2, MAP_W - 3), randi_range(2, MAP_H - 3))
		if not _lot_owner.has(cell):
			return cell
	return Vector2i.ZERO


# --- 建筑入口检测 ---

func _on_scene_ready() -> void:
	super._on_scene_ready()  # 通用截图钩子 (--screenshot)
	if "--auto-test" in OS.get_cmdline_user_args():
		_test_wall_walk()


## 真实移动穿墙回归 (main_map): 玩家在安全屋, 朝墙走应被阻止; 出生点应是地板
func _test_wall_walk() -> void:
	await get_tree().create_timer(0.4).timeout
	var ok := true
	# 安全屋 4×4: home_lot 左上角是墙, 内部是地板
	var wall_cell := _home_lot  # (x, y) 左边界墙
	var inside_cell := _home_lot + Vector2i(2, 2)  # 安全屋内部
	if is_cell_walkable(_world_pos(wall_cell)):
		ok = false
		push_error("[WallWalk] main_map 墙格应不可走: ", wall_cell)
	if not is_cell_walkable(_world_pos(inside_cell)):
		ok = false
		push_error("[WallWalk] main_map 内部地板应可走: ", inside_cell)
	# 出生点应是地板 (修复: 之前 _home_lot+(2,0) 是北墙 → 玩家出生在墙上, 表现像穿墙)
	if not is_cell_walkable(_world_pos(_cell_of(_player.global_position))):
		ok = false
		push_error("[WallWalk] main_map 玩家出生点不可走 (出生在墙上?): ", _cell_of(_player.global_position))
	# 真实移动: 玩家站墙内侧, 朝墙走
	_player.global_position = _world_pos(_home_lot + Vector2i(1, 1))
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	var start_cell := _cell_of(_player.global_position)
	_player.move_in_direction(Vector2(-1, 0))  # 朝左墙
	if _player.is_moving:
		ok = false
		push_error("[WallWalk] main_map 玩家朝墙移动被放行!")
	print("=== 自动测试: main_map 墙体阻止移动=", ok, " (应为 true) 墙=", wall_cell, " 出生点=", _cell_of(_player.global_position))
	# 点击移动: 安全屋内点墙外 → 不穿墙 (用户反馈: 家里墙可越过去)
	await _test_click_wall()
	# 建筑入口: 玩家可走 (进副本), 丧尸不可走 (不会穿进建筑"绕过墙")
	await _test_entry_block()


## 建筑入口回归: 玩家可走入口, 丧尸不可走 (用户反馈: 丧尸绕过墙行走 → 穿进建筑)
func _test_entry_block() -> void:
	var ok := true
	if _building_entries.is_empty():
		push_warning("[Entry] 无建筑入口, 跳过")
		return
	var entry: Vector2i = _building_entries.keys()[0]
	# 玩家可走 (is_cell_walkable 直接查世界, 玩家视角)
	if not is_cell_walkable(_world_pos(entry)):
		ok = false
		push_error("[Entry] 玩家应可走建筑入口: ", entry)
	# 丧尸不可走: 走 Character._is_cell_walkable (带 is_player_unit 判定)
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var z: Node = EF.spawn(self, zombie_script, _world_pos(entry + Vector2i(0, -2)), TILE, 100.0)
	z.world = self
	z.is_player_unit = false
	if z._is_cell_walkable(_world_pos(entry)):
		ok = false
		push_error("[Entry] 丧尸不应可走建筑入口: ", entry)
	z.queue_free()
	print("=== 自动测试: main_map 建筑入口阻挡丧尸=", ok, " (应为 true) 入口=", entry)


## 点击移动穿墙回归 (main_map 安全屋): 玩家在安全屋内点墙外 → 不应穿过墙
func _test_click_wall() -> void:
	var ok := true
	# 安全屋 4×4: home_lot=(18,12), 内部 (19,13), 左墙 x=18, 点墙外 (15,13)
	var stand := _home_lot + Vector2i(1, 1)
	var wall_x := _home_lot.x  # 18
	_player.global_position = _world_pos(stand)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	if _player.is_moving:
		await get_tree().create_timer(0.3).timeout
	_player.move_to_cell(_world_pos(Vector2i(_home_lot.x - 3, _home_lot.y + 1)))  # 点墙外
	var guard := 0
	while _player.is_moving and guard < 60:
		await get_tree().create_timer(0.1).timeout
		guard += 1
	var final_cell := _cell_of(_player.global_position)
	if final_cell.x < wall_x:
		ok = false
		push_error("[ClickWall] main_map 点击移动穿墙! 最终 x=", final_cell.x, " 不应越过墙 x=", wall_x)
	print("=== 自动测试: main_map 点击移动不穿墙=", ok, " (应为 true) 最终=", final_cell)


func _process(_delta: float) -> void:
	super._process(_delta)  # 父类: 鼠标悬停地块高亮
	if not _player or TurnManager.combat_mode:
		return
	var cell := _cell_of(_player.global_position)
	if _building_entries.has(cell):
		var building_idx: int = _building_entries[cell]
		enter_dungeon(building_idx)


func enter_dungeon(building_idx: int) -> void:
	var info: Dictionary = BUILDINGS[building_idx]
	print("[MainMap] 进入副本: ", info["name"])
	GameManager.change_state(GameManager.GameState.COMBAT)
	GameManager.set_meta("pending_dungeon_type", int(info["dungeon"]))
	get_tree().change_scene_to_file("res://scenes/dungeon_base.tscn")
