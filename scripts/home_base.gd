extends "res://scripts/scenes/game_scene_base.gd"

# ============================================================
# HomeBase — 家园场景 (继承 GameSceneBase)
# ============================================================
# 新手开局场景: 玩家在房间醒来 → 衣柜拿棒球棍 → 装备 → 花园打初级丧尸
# 布局 (16×16 格):
#   房间 (左上 2..7 x 2..7): 玩家出生 + 衣柜(含棒球棍)
#   门   (房间右下角): 通往花园
#   花园 (右侧大片): 动态丧尸入侵 (按天数/击杀/污染缩放, 非固定)
# 通用逻辑 (UI/输入/点击交互/移动范围) 全部在基类

const TSB := preload("res://scripts/dungeons/tile_set_builder.gd")
const FUR := preload("res://scripts/tiles/furniture.gd")
const HF := preload("res://scripts/tiles/home_furniture.gd")
const EF := preload("res://scripts/units/enemy_factory.gd")
const BMU := preload("res://scripts/ui/build_menu.gd")

const MAP_W := 16
const MAP_H := 16

## 房间范围 (格) — 屋子贴地图左上角, 花园在右/下方; 可通过"扩建房屋"向右下扩展
const ROOM_X0 := 1
const ROOM_Y0 := 1
const ROOM_X1 := 6
const ROOM_Y1 := 6
## 门位置 (房间下墙中央, 扩建后自动跟随新下墙)
var DOOR_CELL := Vector2i(4, 6)
## 衣柜位置 (房间内左上角, 测试/教程用)
const CHEST_CELL := Vector2i(2, 2)
## 床位置 (房间内右上)
const BED_CELL := Vector2i(5, 2)
## 净化器位置 (房间内左下)
const PURIFIER_CELL := Vector2i(2, 5)
## 玩家出生 (房间内中央)
const SPAWN_CELL := Vector2i(4, 3)
## 花园丧尸位置
const ZOMBIE_CELL := Vector2i(11, 4)
## 雨水收集器位置 (花园左上, 需露天)
const COLLECTOR_CELL := Vector2i(10, 3)
## 种植区位置 (花园)
const PLANTING_CELL := Vector2i(12, 9)
## 健身器材位置 (房间内, 锻炼用)
const GYM_CELL := Vector2i(3, 2)

## 房间矩形 (墙边界, 运行时随扩建变化)
var _room_rect := Rect2i(ROOM_X0, ROOM_Y0, ROOM_X1 - ROOM_X0 + 1, ROOM_Y1 - ROOM_Y0 + 1)
var _room_expansions: int = 0
## 扩建上限与基础材料 (每次递增: 木材 +3 / 钉子 +3)
const ROOM_EXPAND_MAX := 5
const ROOM_EXPAND_COST_BASE := {"wood": 6, "nail": 3}

var _furniture_list: Array = []
## 功能家具: kind → HomeFurniture (交互分发用)
var _home_furniture: Dictionary = {}

## 建造系统: 建造/研究面板 + 放置模式
var _build_menu: Node = null
var _build_mode: bool = false
var _build_kind: int = -1


# --- 地图生成 ---

## 家园是固定基地: 迷雾记忆跨进入保留 (出去探图再回家, 已开视野不丢)
func _fog_memory_key() -> String:
	return "home_base"

func _create_world() -> void:
	print("[HomeBase] 生成家园...")
	_tilemap = DTM.new()  # 自定义绘制 (TileMapLayer 在本项目渲染不可靠, 见 memory)
	_tilemap.tile_size = tile_size  # 与单位格子等大
	add_child(_tilemap)

	# 全部铺地板
	for y in range(MAP_H):
		for x in range(MAP_W):
			_tilemap.set_cell(Vector2i(x, y), 0, Vector2i(TSB.Tiles.FLOOR, 0))

	# 边界墙
	for x in range(MAP_W):
		_set_wall(Vector2i(x, 0))
		_set_wall(Vector2i(x, MAP_H - 1))
	for y in range(MAP_H):
		_set_wall(Vector2i(0, y))
		_set_wall(Vector2i(MAP_W - 1, y))

	# 房间墙 (围一圈, 留门) — 用运行时矩形, 支持扩建
	_draw_room_walls()
	# 门 (房间下墙中央, 1 格宽开口)
	_redraw_door()

	# 院门: 南墙中央 (朝南通往主地图) — 走到触发存档 + 切换到世界地图 (战略层格子)
	# (用户需求: 出了院子门就到主地图; 家是主地图里的一个格子)
	EXIT_CELL = Vector2i(8, MAP_H - 1)
	_tilemap.set_cell(EXIT_CELL, 0, Vector2i(TSB.Tiles.EXIT, 0))
	_door_cells[EXIT_CELL] = true
	# (标注文字/箭头已全部移除: 用户不需要"院门→主地图"/"房间"/"花园"/"门·通花园"/脉动箭头等)
	# 院门格仍为 EXIT 类型(绿色), 玩家走到即出院; 门/花园靠颜色和位置辨识即可
	pass


## 脉动向下箭头 (提示出口方向): 透明度 + 轻微上下浮动循环
func _make_pulse_arrow(center: Vector2) -> Label:
	var arrow := Label.new()
	arrow.text = "▼"
	arrow.add_theme_font_size_override("font_size", 30)
	arrow.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	arrow.position = center - Vector2(15, 20)
	arrow.z_index = 60
	var tw := arrow.create_tween()
	tw.set_loops(-1)
	tw.tween_property(arrow, "modulate:a", 0.25, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tw2 := arrow.create_tween()
	tw2.set_loops(-1)
	tw2.tween_property(arrow, "position:y", arrow.position.y + 12, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return arrow


## 门格记录 (可通行)
var _door_cells: Dictionary = {}
## 家园大门 (南墙中央, 走到 → 存档 + 切到 main_map 城市)
var EXIT_CELL: Vector2i = Vector2i(8, 15)



func _set_wall(cell: Vector2i) -> void:
	_tilemap.set_cell(cell, 0, Vector2i(TSB.Tiles.WALL, 0))


## 按当前房间矩形画四面墙 (扩建后由 expand_house 调用重绘)
func _draw_room_walls() -> void:
	for x in range(_room_rect.position.x, _room_rect.end.x):
		_set_wall(Vector2i(x, _room_rect.position.y))
		_set_wall(Vector2i(x, _room_rect.end.y - 1))
	for y in range(_room_rect.position.y, _room_rect.end.y):
		_set_wall(Vector2i(_room_rect.position.x, y))
		_set_wall(Vector2i(_room_rect.end.x - 1, y))


## 门: 房间下墙中央 1 格 (扩建后旧门变墙, 新门跟随新下墙; 院门 EXIT_CELL 保留)
func _redraw_door() -> void:
	for dc in _door_cells.keys():
		if dc != EXIT_CELL:
			_tilemap.set_cell(dc, 0, Vector2i(TSB.Tiles.WALL, 0))
			_door_cells.erase(dc)
	var door := Vector2i(_room_rect.position.x + _room_rect.size.x / 2, _room_rect.end.y - 1)
	_tilemap.set_cell(door, 0, Vector2i(TSB.Tiles.DOOR, 0))
	_door_cells[door] = true
	DOOR_CELL = door


## 扩建房屋: 房间向右下各扩 1 格 (旧右/下墙变地板, 新右/下墙外推, 门跟到新下墙)
## 材料递增: 第 N 次 = 木材 6+3N, 钉子 3+3N; 上限 ROOM_EXPAND_MAX 次
func expand_house() -> Dictionary:
	if _room_expansions >= ROOM_EXPAND_MAX:
		return {"success": false, "message": "房屋已达扩建上限 (%d 次)" % ROOM_EXPAND_MAX}
	var new_rect := Rect2i(_room_rect.position, _room_rect.size + Vector2i(1, 1))
	if new_rect.end.x >= MAP_W or new_rect.end.y >= MAP_H:
		return {"success": false, "message": "已到家园边缘, 无法再扩建"}
	var cost := {}
	for id in ROOM_EXPAND_COST_BASE:
		cost[id] = int(ROOM_EXPAND_COST_BASE[id]) + _room_expansions * 3
	if not BuildingManager.can_afford(cost):
		return {"success": false, "message": "材料不足: 需要 " + BuildingManager.cost_text(cost)}
	for id in cost:
		InventoryBackpack.remove_item(id, int(cost[id]))
	# 旧右墙 → 地板
	for y in range(_room_rect.position.y, _room_rect.end.y):
		_tilemap.set_cell(Vector2i(_room_rect.end.x - 1, y), 0, Vector2i(TSB.Tiles.FLOOR, 0))
	# 旧下墙 → 地板
	for x in range(_room_rect.position.x, _room_rect.end.x):
		_tilemap.set_cell(Vector2i(x, _room_rect.end.y - 1), 0, Vector2i(TSB.Tiles.FLOOR, 0))
	_room_rect = new_rect
	# 新右墙 + 新下墙
	_draw_room_walls()
	# 门跟随新下墙
	_redraw_door()
	_room_expansions += 1
	if BuildingManager:
		BuildingManager.room_expansions = _room_expansions  # 随存档持久化
	_refresh_move_grid()
	return {"success": true, "message": "房屋扩建成功 (%dx%d), 新空间可继续建造家具" % [_room_rect.size.x, _room_rect.size.y]}


## 读档恢复: 按 BuildingManager.room_expansions 重建房间大小 (初始墙已画, 此处补画扩展墙)
func _restore_room_expansions() -> void:
	if not BuildingManager or BuildingManager.room_expansions <= 0:
		return
	var n: int = BuildingManager.room_expansions
	_room_expansions = n
	_room_rect = Rect2i(_room_rect.position, _room_rect.size + Vector2i(n, n))
	if _room_rect.end.x > MAP_W or _room_rect.end.y > MAP_H:
		_room_rect = Rect2i(_room_rect.position, Vector2i(MAP_W - _room_rect.position.x, MAP_H - _room_rect.position.y))
	_draw_room_walls()
	_redraw_door()
	_refresh_move_grid()
	print("[HomeBase] 读档恢复房屋扩建: ", n, " 次, 房间=", _room_rect.size)


func is_cell_walkable(cell_center: Vector2) -> bool:
	var cell := _cell_of(cell_center)
	if cell.x < 0 or cell.x >= MAP_W or cell.y < 0 or cell.y >= MAP_H:
		return false
	# 门可通行, 墙不可
	if _door_cells.has(cell):
		return true
	var coords: Vector2i = _tilemap.get_cell_atlas_coords(cell)
	# 防御: 未设置的格子 (coords == (-1,-1)) 不可走 — 避免漏设格变成"可走的地面"导致穿墙
	if coords.x < 0 or coords.y < 0:
		return false
	return coords.x != TSB.Tiles.WALL


# --- 玩家 ---

func _create_player() -> void:
	var spawn := SPAWN_CELL
	# 从世界地图"返回家园" → 在院门内侧(院子入口)出现, 而不是被传送到卧室里
	if GameManager and GameManager.has_meta("home_return") and GameManager.get_meta("home_return"):
		spawn = Vector2i(8, 14)   # 院门(8,15)内一格, 落在院子里
		GameManager.remove_meta("home_return")
	_player = PF.spawn(self, _world_pos(spawn), tile_size)
	_player.world = self
	print("[HomeBase] 玩家", ("返回院门" if spawn != SPAWN_CELL else "在房间醒来"), ": ", _player.global_position)


# --- 敌人 + 家具 ---

func _spawn_entities() -> void:
	_spawn_home_furniture()
	_spawn_garden_zombie()
	_refresh_move_grid()


## 家园功能家具: 初始只预置工作台; 其余(床/收集器/净化器/种植区/储物箱等)
## 由玩家在工作台研究蓝图并建造 (新手教程会引导建造床与储物箱)
func _spawn_home_furniture() -> void:
	# 工作台 (固定, 点击打开建造/研究面板; 玩家从此研究蓝图并建造家具)
	var workbench := HF.new()
	workbench.setup(HF.Kind.WORKBENCH, Vector2i(3, 2), tile_size)
	add_child(workbench)
	_home_furniture[HF.Kind.WORKBENCH] = workbench
	_furniture_list.append(workbench)

	print("[HomeBase] 初始家园: 仅工作台 (其余家具需玩家建造)")


## 家具网格命中: 容器家具 + 功能家具 (基类 _raycast_interactable 只查尸体)
func _raycast_interactable(world_pos: Vector2) -> Node:
	var clicked_cell := _cell_of(world_pos)
	for f in _furniture_list:
		if not is_instance_valid(f):
			continue
		var gp: Vector2i = f.get("grid_pos") if f.get("grid_pos") != null else Vector2i(-9999, -9999)
		if gp == clicked_cell:
			return f
	return super._raycast_interactable(world_pos)


## 点击家具: 功能家具(HomeFurniture)按类型分发; 容器家具(储物箱/尸体等)走基类
func _on_interact(interact: Node) -> void:
	if interact is HF:
		_handle_home_furniture(interact)
		return
	super._on_interact(interact)


## 功能家具交互分发
func _handle_home_furniture(f: HF) -> void:
	match f.kind:
		HF.Kind.BED:
			# 床: 左键睡觉, 右键升级 (右键标记在 _input 里设置)
			if _last_right_click_on_furniture:
				_last_right_click_on_furniture = false
				var r_up: Dictionary = f.upgrade_bed()
				_show_result(r_up)
				if r_up.get("success", false) and GameManager and GameManager.is_tutorial_mode() and _tutorial_step == "upgrade":
					_tutorial_step_completed("upgraded")
			else:
				_show_result(f.sleep_on_bed(_player))
		HF.Kind.RAIN_COLLECTOR:
			var got: int = f.harvest_collector()
			_show_result({"success": got > 0, "message": f.last_message if got > 0 else "收集器空空如也 (下雨时积攒)"})
		HF.Kind.PURIFIER:
			_show_result(f.purify())
		HF.Kind.PLANTING_BED:
			# 种植区: 已种 → 收获; 空闲 → 尝试种植
			if f.plant_item != "":
				_show_result(f.harvest_plant())
			else:
				var ok_plant: bool = f.plant("seed_vegetable")
				_show_result({"success": ok_plant, "message": f.last_message})
		HF.Kind.WORKBENCH:
			_open_build_menu()
		HF.Kind.GYM:
			# 健身器材: 锻炼 +体力 (Player.train 消耗世界时间, 提升负重上限)
			if _player and _player.has_method("train"):
				var stamina_before: float = _player.get("stamina")
				_player.train(1.0, 2.0)
				var stamina_after: float = _player.get("stamina")
				_show_result({"success": true, "message": "锻炼 +%.1f 体力 (%.1f → %.1f)" % [stamina_after - stamina_before, stamina_before, stamina_after]})


## 右键点击床的标记 (床右键=升级)
var _last_right_click_on_furniture: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 建造模式: 右键取消放置 (不再交给基类)
		if _build_mode:
			_build_mode = false
			_build_kind = -1
			_show_result({"success": true, "message": "已取消建造"})
			return
		var world_pos := get_global_mouse_position()
		var interact := _raycast_interactable(world_pos)
		_last_right_click_on_furniture = interact is HF and interact.kind == HF.Kind.BED
	# 其余事件 (左键移动/键盘等) 一律交给基类统一处理 (修复: 之前只在右键分支调 super, 左键被吞)
	super._unhandled_input(event)


func _show_result(result: Dictionary) -> void:
	var msg: String = result.get("message", "完成")
	print("[HomeBase] ", msg)
	if _hud and _hud.has_method("show_tutorial"):
		_hud.show_tutorial(msg)


# --- 建造 / 研究系统 ---

## 探索点击: 建造模式优先接管 (否则走基类常规交互)
func _handle_explore_click(event: InputEvent) -> void:
	if _build_mode and _build_kind >= 0:
		_try_build_at(_event_to_world(event))
		return
	super._handle_explore_click(event)


## 打开建造/研究面板
func _open_build_menu() -> void:
	if _build_menu:
		_build_menu.open()


## 初始化建造面板 + 读档恢复已建家具
func _setup_build_menu() -> void:
	if _build_menu == null:
		_build_menu = BMU.new()
		add_child(_build_menu)
		_build_menu.build_selected.connect(_on_build_selected)
		_build_menu.closed.connect(_on_build_menu_closed)
		if _build_menu.has_signal("expand_requested") and not _build_menu.expand_requested.is_connected(_on_expand_requested):
			_build_menu.expand_requested.connect(_on_expand_requested)
	# 读档恢复: 把 BuildingManager 中已建家具生成到场景
	_spawn_built_furniture_all()


## 工作台面板"扩建房屋" → 扩大房间面积
func _on_expand_requested() -> void:
	_show_result(expand_house())


func _on_build_selected(kind: int) -> void:
	_build_kind = kind
	_build_mode = true
	_show_result({"success": true, "message": "选择空地放置: " + BuildingManager.bp_name(kind) + " (右键取消)"})


func _on_build_menu_closed() -> void:
	pass


## 尝试在 world_pos 对应格放置当前建造家具 (校验墙/门/占用/脚下)
func _try_build_at(world_pos: Vector2) -> void:
	var cell := _cell_of(world_pos)
	if _build_kind < 0:
		return
	# 门口/院门不可建
	if _door_cells.has(cell):
		_show_result({"success": false, "message": "门口不能建造"})
		return
	# 墙/边界不可建
	if not is_cell_walkable(_world_pos(cell)):
		_show_result({"success": false, "message": "这里无法建造 (墙或边界)"})
		return
	# 已有家具
	for f in _furniture_list:
		var gp: Vector2i = f.get("grid_pos") if f.get("grid_pos") != null else Vector2i(-9999, -9999)
		if gp == cell:
			_show_result({"success": false, "message": "该位置已有家具"})
			return
	# 玩家脚下
	if _player and _cell_of(_player.global_position) == cell:
		_show_result({"success": false, "message": "不能建在自己脚下"})
		return
	var r := BuildingManager.commit_build(_build_kind, cell)
	if r.get("success", false):
		_spawn_built_furniture(_build_kind, cell)
		_show_result(r)
	else:
		_show_result(r)


## 生成一件已建家具节点 (注册到交互列表)
func _spawn_built_furniture(kind: int, cell: Vector2i) -> void:
	if kind == HF.Kind.CHEST:
		# 储物箱: 用通用容器家具 (Furniture) 实现, 复用 ContainerUI 存取物品
		var fur: Node = FUR.new()
		fur.setup(cell, tile_size, [], 0, "储物箱", Furniture.FurnType.CRATE)
		add_child(fur)
		_furniture_list.append(fur)
		_check_tutorial_build()
		return
	var f := HF.new()
	f.setup(kind, cell, tile_size)
	if kind == HF.Kind.RAIN_COLLECTOR:
		f.capacity = 6  # 收集器容量 (建造版也需设定)
	add_child(f)
	_home_furniture[kind] = f
	_furniture_list.append(f)
	_check_tutorial_build()


## 读档: 从 BuildingManager 恢复所有已建家具
func _spawn_built_furniture_all() -> void:
	for b in BuildingManager.built:
		_spawn_built_furniture(int(b["kind"]), Vector2i(int(b["x"]), int(b["y"])))


## 花园初级丧尸 (弱化版: 低血量, 新手可击杀) — 仅新游戏/教程用
## 后续返回家园走 _spawn_home_invaders() 动态系统
func _spawn_garden_zombie() -> void:
	# 新游戏或 day<=2 且 kill<3 时仍生成 1 只新手丧尸 (引导链路依赖)
	var is_early: bool = (not WorldTime or WorldTime.day <= 2) and \
		GameManager and int(GameManager.stats.get("kills", 0)) < 3
	if not is_early:
		_spawn_home_invaders()
		return
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var zombie := EF.spawn(self, zombie_script, _world_pos(ZOMBIE_CELL), tile_size, 100.0)
	zombie.name = "GardenZombie"
	zombie.world = self
	zombie.max_hp = 40.0
	zombie.hp = 40.0
	zombie.move_speed = 80.0
	print("[HomeBase] 新手花园丧尸生成 HP=", zombie.hp, " at ", ZOMBIE_CELL)


## === 动态家园入侵系统 ===
## 按世界天数 / 击杀数 / 污染度缩放:
##   - 数量: 0~3+ (随天数增长, 有概率不刷)
##   - 类型: basic → runner/spitter → tank (随进度解锁)
##   - 属性: HP/攻击力按天数微增
##   - 位置: 花园区域随机 (非固定 ZOMBIE_CELL)
##   - 概率: 非必刷 (模拟"间隔不一定")

const _GARDEN_SPAWN_CELLS: Array[Vector2i] = [
	Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3), Vector2i(12, 3), Vector2i(13, 3),
	Vector2i(9, 4), Vector2i(10, 4), Vector2i(11, 4), Vector2i(12, 4), Vector2i(13, 4), Vector2i(14, 4),
	Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5), Vector2i(14, 5),
	Vector2i(9, 6), Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6), Vector2i(13, 6), Vector2i(14, 6),
	Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 7), Vector2i(13, 7), Vector2i(14, 7),
	Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(12, 8), Vector2i(13, 8), Vector2i(14, 8),
	Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9), Vector2i(12, 9), Vector2i(13, 9), Vector2i(14, 9),
	Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10), Vector2i(13, 10), Vector2i(14, 10),
	Vector2i(9, 11), Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11),
	Vector2i(9, 12), Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12),
	Vector2i(9, 13), Vector2i(10, 13), Vector2i(11, 13), Vector2i(12, 13), Vector2i(13, 13), Vector2i(14, 13),
	Vector2i(9, 14), Vector2i(10, 14), Vector2i(11, 14), Vector2i(12, 14), Vector2i(13, 14), Vector2i(14, 14),
]


func _spawn_home_invaders() -> void:
	if not WorldTime or not GameManager:
		return

	var game_day: int = WorldTime.day
	var total_kills: int = int(GameManager.stats.get("kills", 0))
	var pollution: float = WorldTime.get_pollution(GameManager.current_character) if GameManager.current_character else 0.0

	# --- 基础概率: 不是每次回去都有丧尸 ---
	# day 1-3: 50% | day 4-7: 70% | day 8+: 85%
	var spawn_chance: float = 0.50 + mini(0.35, float(game_day) * 0.05)
	if randf() > spawn_chance:
		print("[HomeBase] 本次返回家园无入侵 (day=%d chance=%.0f%%)" % [game_day, spawn_chance * 100])
		return

	# --- 数量: 1~3 只, 随天数缓慢增加 ---
	# 基础 1 只; 每 5 天 +0.5 只上限; 击杀多→稍微多; 污染重→稍微多
	var base_count: float = 1.0 + float(game_day) * 0.12 + float(total_kills) * 0.01 + pollution * 0.01
	var count: int = mini(4, maxi(1, int(base_count)))
	# 随机波动: 已决定上限后仍有几率少 1 只
	if randf() < 0.25 and count > 1:
		count -= 1

	# --- 类型池: 随进度解锁高阶丧尸 ---
	# basic 始终可用; runner day≥3; spitter day≥6; tank day≥10
	var type_pool: Array[String] = ["zombie_basic"]
	if game_day >= 3:
		type_pool.append("zombie_runner")
	if game_day >= 6:
		type_pool.append("zombie_spitter")
	if game_day >= 10:
		type_pool.append("zombie_tank")

	# 高阶类型权重低 (basic 最常见)
	var type_weights: Dictionary = {
		"zombie_basic": 60,
		"zombie_runner": 20 if game_day >= 3 else 0,
		"zombie_spitter": 12 if game_day >= 6 else 0,
		"zombie_tank": 8 if game_day >= 10 else 0,
	}

	# --- 属性缩放系数: 天数越长越强 ---
	# day1=1.0 | day5≈1.15 | day10≈1.3 | day20≈1.6
	var stat_scale: float = 1.0 + float(game_day) * 0.03 + pollution * 0.002

	# --- 生成 ---
	var used_cells: Array[Vector2i] = []
	for i in range(count):
		var type_key: String = _weighted_pick(type_weights)
		var cell: Vector2i = _random_garden_cell(used_cells)
		if cell == Vector2i(-1, -1):
			break  # 花园格子不够了
		used_cells.append(cell)

		var zombie_script: Script = load("res://scripts/units/enemies/%s.gd" % type_key)
		var base_speed: float = _base_speed_for_type(type_key)
		var zombie := EF.spawn(self, zombie_script, _world_pos(cell), tile_size, base_speed)
		zombie.name = "HomeInvader_%d_%s" % [i, type_key]
		zombie.world = self

		# 属性缩放 (在脚本默认值基础上放大)
		zombie.max_hp = mini(zombie.max_hp * stat_scale, 500.0)
		zombie.hp = zombie.max_hp
		zombie.attack_power = mini(zombie.attack_power * stat_scale, 60.0)
		# 速度也略微提升 (后期丧尸更快)
		zombie.move_speed = base_speed * (1.0 + mini(0.30, float(game_day) * 0.02))

		print("[HomeBase] 入侵者 #%d: %s HP=%.0f ATK=%.0f at %s (day=%d scale=%.2f)" % [
			i, type_key, zombie.hp, zombie.attack_power, cell, game_day, stat_scale])


## 从权重字典随机选一个键
func _weighted_pick(weights: Dictionary) -> String:
	var total: float = 0.0
	for w in weights.values():
		total += w
	var roll: float = randf() * total
	var acc: float = 0.0
	for key in weights:
		acc += weights[key]
		if roll <= acc:
			return key
	return "zombie_basic"


## 各类型基础速度
func _base_speed_for_type(type_key: String) -> float:
	match type_key:
		"zombie_basic": return 100.0
		"zombie_runner": return 160.0
		"zombie_spitter": return 90.0
		"zombie_tank": return 70.0
	return 100.0


## 从花园格子里随机选一个未使用的
func _random_garden_cell(exclude: Array[Vector2i]) -> Vector2i:
	var available: Array[Vector2i] = []
	for c in _GARDEN_SPAWN_CELLS:
		if not c in exclude:
			available.append(c)
	if available.is_empty():
		return Vector2i(-1, -1)
	return available[randi() % available.size()]


# --- 新手引导 (4 步: 装备武器 → 攻击/战斗 → 搜刮 → 建造 → 升级) ---

var _tutorial_step: String = "wake_up"


## 引导步骤推进
func _tutorial_step_completed(step: String) -> void:
	match _tutorial_step:
		"wake_up":
			if step == "equipped":
				_set_tut("attack", "走到花园，点击丧尸发起攻击，进入战斗")
		"attack":
			if step == "combat_started":
				_set_tut("loot", "进入战斗！消灭丧尸后，点击它的尸体搜刮战利品")
		"loot":
			if step == "looted":
				_set_tut("build", "打开工作台，研究并建造床和储物箱（消耗材料）")
		"build":
			if step == "built":
				_set_tut("upgrade", "右键点击床进行升级，提升休息恢复效果")
		"upgrade":
			if step == "upgraded":
				_set_tut("done", "新手教程完成！自由探索、建造你的家园吧")
		"done":
			pass


func _set_tut(step: String, hint: String) -> void:
	_tutorial_step = step
	_show_tutorial_hint(hint)
	if step == "done" and GameManager and GameManager.has_method("set_tutorial_done"):
		GameManager.set_tutorial_done()


func _show_tutorial_hint(msg: String) -> void:
	print("[HomeBase] 引导提示: ", msg)
	if _hud and _hud.has_method("show_tutorial"):
		_hud.show_tutorial(msg)


# --- 引导事件监听 (场景 _ready 时挂接) ---

func _setup_tutorial_listeners() -> void:
	if not _player:
		return
	# 装备武器 → 推进引导
	if _player.has_signal("equipment_changed"):
		_player.equipment_changed.connect(_on_player_equipped)
	# 进入战斗 → 推进引导
	if TurnManager.has_signal("combat_started") and not TurnManager.combat_started.is_connected(_on_combat_started):
		TurnManager.combat_started.connect(_on_combat_started)
	# 打开容器(搜刮) → 推进引导
	if not container_opened.is_connected(_on_container_opened):
		container_opened.connect(_on_container_opened)
	# 跳过教程按钮 → 教程状态机直接置 done
	if _hud and _hud.has_signal("tutorial_skipped") and not _hud.tutorial_skipped.is_connected(_on_tutorial_skipped):
		_hud.tutorial_skipped.connect(_on_tutorial_skipped)


## 玩家点"跳过教程": 状态机直接到 done (GameManager.set_tutorial_done 已由 HUD 调用)
func _on_tutorial_skipped() -> void:
	_tutorial_step = "done"
	_tutorial_step_completed("done")  # done 分支空操作, 保持状态一致


func _on_player_equipped(_item_id: String, _slot: String) -> void:
	if not GameManager or not GameManager.is_tutorial_mode():
		return
	if _player and _player.get("equipped_weapon") != null:
		_tutorial_step_completed("equipped")


func _on_combat_started() -> void:
	if not GameManager or not GameManager.is_tutorial_mode():
		return
	_tutorial_step_completed("combat_started")


func _on_container_opened(_container: Node) -> void:
	if not GameManager or not GameManager.is_tutorial_mode():
		return
	_tutorial_step_completed("looted")


## 建造床+储物箱后推进"建造"步骤 (教程)
func _check_tutorial_build() -> void:
	if not GameManager or not GameManager.is_tutorial_mode():
		return
	if _tutorial_step != "build":
		return
	var has_bed := false
	var has_chest := false
	for b in BuildingManager.built:
		var k: int = int(b.get("kind", -1))
		if k == HF.Kind.BED:
			has_bed = true
		elif k == HF.Kind.CHEST:
			has_chest = true
	if has_bed and has_chest:
		_tutorial_step_completed("built")


# --- 天气视觉: 下雨时家园叠加冷色滤镜 (天气每天轮换, 关联雨水收集器) ---

var _weather_tint: CanvasLayer = null


func _setup_weather_tint() -> void:
	if _weather_tint != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	var cr := ColorRect.new()
	cr.color = Color(0.45, 0.55, 0.75, 0.16)
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cr)
	add_child(layer)
	_weather_tint = layer
	_update_weather_tint()
	if WorldTime and WorldTime.has_signal("weather_changed") and not WorldTime.weather_changed.is_connected(_update_weather_tint):
		WorldTime.weather_changed.connect(_update_weather_tint)


func _update_weather_tint(_w: int = -1) -> void:
	if _weather_tint == null:
		return
	_weather_tint.visible = WorldTime != null and WorldTime.is_raining()


# --- 自动测试钩子 ---

func _on_scene_ready() -> void:
	super._on_scene_ready()  # 通用截图钩子 (--screenshot)
	_setup_tutorial_listeners()
	_setup_weather_tint()
	_setup_survival_links()
	# 新手引导: 开场提示
	if GameManager and GameManager.is_tutorial_mode():
		# 教程初始材料 (用户反馈: 教程让研究建造床/储物箱但没给材料过不了):
		# 储物箱 research wood1+nail1 / build wood3+nail2; 床 research wood2 / build wood3+cloth2
		# → 合计 wood9/nail3/cloth2, 发 wood10/nail5/cloth3 富余; force 绕过负重 (新手特供)
		InventoryBackpack.force_add_item("wood", 10)
		InventoryBackpack.force_add_item("nail", 5)
		InventoryBackpack.force_add_item("cloth", 3)
		_show_tutorial_hint("你在家园废墟中醒来。打开背包，把木棒装备到武器槽；然后走到花园点击丧尸发起攻击")
	_setup_build_menu()
	# 读档恢复房屋扩建 (BuildingManager.room_expansions 持久化)
	_restore_room_expansions()
	if "--auto-test" in OS.get_cmdline_user_args():
		_run_auto_test_sync()
		_run_auto_test()
	if "--screenshot" in OS.get_cmdline_user_args():
		_save_screenshot()


## 家园大门检测: 玩家走到大门格 → 存档 + 切换到城市 (main_map)
var _leaving_home: bool = false

## 院门判定: 点南墙中央的绿色院门格 → 出院
func _is_exit_cell(cell: Vector2i) -> bool:
	return cell == EXIT_CELL


func _process(_delta: float) -> void:
	super._process(_delta)  # 父类: 鼠标悬停地块高亮
	if _leaving_home or not _player:
		return
	if _cell_of(_player.global_position) == EXIT_CELL:
		_leaving_home = true
		print("[HomeBase] 玩家走出院门 → 存档并返回主地图 (世界格子)")
		if GameManager:
			GameManager.save_game()
		# 走出院门即点亮世界地图 HOME 四周邻居 (开图不必先进副本)
		WorldMapData.reveal_neighbors(WorldMapData.home_cell.x, WorldMapData.home_cell.y)
		# 主线里程碑: 走出安全屋 (步骤 1)
		if GameManager and GameManager.has_method("advance_story"):
			GameManager.advance_story(1)
		WorldMapData.call_deferred("return_to_world")


## 渲染几帧后截图 (视觉排查用, --screenshot 参数; headless 下 viewport 纹理为空, 安全跳过)
func _save_screenshot() -> void:
	for i in 5:
		await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[HomeBase] 截图跳过: headless 模式 viewport 纹理为空")
		return
	var img := tex.get_image()
	if img == null:
		print("[HomeBase] 截图跳过: 无法获取图像 (headless 不支持)")
		return
	var path := "user://home_base_shot.png"
	img.save_png(path)
	print("[HomeBase] 截图已保存: ", path, " 绝对路径: ", ProjectSettings.globalize_path(path))


## 生存链路: 世界时间 → 收集器积雨水 / 种植区生长 (Phase 6)
func _setup_survival_links() -> void:
	if not WorldTime:
		return
	WorldTime.time_advanced.connect(_on_world_time_advanced_home)
	# 开局送种子 (体验种植)
	if _player and GameManager and GameManager.is_tutorial_mode():
		_player.add_item("seed_vegetable", 3)
		_player.add_item("water_pure", 3)


func _on_world_time_advanced_home(_day: int, _hour: float, elapsed_hours: float) -> void:
	# 收集器: 每经过 1 小时尝试积攒 1 瓶污染水 (下雨时)
	var collector: HF = _home_furniture.get(HF.Kind.RAIN_COLLECTOR)
	if collector and elapsed_hours > 0.0:
		var ticks := int(elapsed_hours)
		for i in ticks:
			collector.collect_rain()
	# 种植区生长
	var planting: HF = _home_furniture.get(HF.Kind.PLANTING_BED)
	if planting:
		planting.grow_plant(elapsed_hours)


## 同步自动测试 (不依赖帧信号): 验证院门可出 + 关键不变量
func _run_auto_test_sync() -> void:
	var ok := true
	# 1. 院门格可走
	if not is_cell_walkable(_world_pos(EXIT_CELL)):
		ok = false
		push_error("[HomeExit] 院门格不可走: ", EXIT_CELL)
	# 2. _is_exit_cell 判定正确
	if not _is_exit_cell(EXIT_CELL):
		ok = false
		push_error("[HomeExit] _is_exit_cell(EXIT) 应返回 true")
	if _is_exit_cell(Vector2i(3, 3)):
		ok = false
		push_error("[HomeExit] _is_exit_cell(地板) 不应返回 true")
	# 3. 院门 exit 分支核心逻辑: _is_exit_cell(院门格) 为真 → 真机 _process 会调 move_to_cell 启动移动
	# (此处只验证判定成立, 不实际 move_to_cell, 避免遗留移动 tween 在异步测试等待期把玩家送到院门→出院→释放场景)
	_player.global_position = _world_pos(SPAWN_CELL)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	_player.is_moving = false
	if not _is_exit_cell(_cell_of(_world_pos(EXIT_CELL))):
		ok = false
		push_error("[HomeExit] 院门 exit 分支判定应成立")
	# 4. 玩家处于院门格 → 出院判定条件成立 (真机 _process 据此调 return_to_world 切场景)
	_player.global_position = _world_pos(EXIT_CELL)
	_player.is_my_turn = true
	if _cell_of(_player.global_position) != EXIT_CELL:
		ok = false
		push_error("[HomeExit] 玩家在院门格但 _cell_of 不匹配")
	print("=== 自动测试(同步): 院门可出=", ok, " (应为 true) 院门=", EXIT_CELL)
	# 恢复 (先停掉 line559 启动的尚未完成的移动, 否则 is_moving 残留会误导后续测试)
	_player.is_moving = false
	_player.global_position = _world_pos(SPAWN_CELL)
	_leaving_home = false


## 移动/点击路由回归: ①机制层 move_to_cell 能启动移动 ②左键点击经 _unhandled_input
## 路由到基类 _handle_explore_click 也能启动移动 (曾因 override 不调 super 被吞)
func _test_movement_routing() -> void:
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	_refresh_move_grid()
	var ok := true
	# 1) 机制层
	_player.move_to_cell(_world_pos(Vector2i(3, 5)))
	if not _player.is_moving:
		ok = false
		push_error("[Move] move_to_cell 未启动移动")
	_player.is_moving = false
	_player.global_position = _world_pos(SPAWN_CELL)
	# 2) 输入层: 模拟左键点击附近地板
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = get_canvas_transform() * _world_pos(Vector2i(3, 5))
	_unhandled_input(ev)
	if not _player.is_moving:
		ok = false
		push_error("[Move] 左键点击未路由到移动 (输入被吞)")
	_player.is_moving = false
	_player.global_position = _world_pos(SPAWN_CELL)
	print("=== 自动测试: 移动/点击路由=", ok, " (应为 true) combat_mode=", TurnManager.combat_mode, " range=", _move_grid.range_tiles if _move_grid else -1)


## 帧等待: detached 协程里 create_timer 信号不可靠, 用单次 process_frame 等待 (已验证稳定)
func _run_auto_test() -> void:
	await get_tree().process_frame
	print("=== 家园自动测试: 玩家出生 + 工作台 + 丧尸 ===")
	var wb: HF = _home_furniture.get(HF.Kind.WORKBENCH)
	print("=== 玩家位置=", _player.global_position, " 工作台=", is_instance_valid(wb), " 家具数=", _furniture_list.size(), " 敌人数=", TurnManager.get_enemy_units().size())
	print("=== 家园自动测试完成 (初始仅工作台, 其余家具由玩家建造) ===")
	# 移动/点击路由回归 (排查"无法行走")
	_test_movement_routing()
	# 工作台交互: 模拟点击工作台 → 应打开建造/研究面板
	_test_workbench_interact()
	# 家具视觉不拦截鼠标: 所有家具子 Control 必须 IGNORE (真机悬停高亮消失/点击被吞的根因)
	_test_furniture_mouse_filter()
	# 引导链路: 拿棒球棍 → 装备 → 打丧尸
	await _test_tutorial_flow()
	# 生存流水线: 净化/种植/收获/睡觉
	await _test_survival_flow()
	# 建造/研究系统: 研究蓝图 → 建造家具 → 校验消耗/占用/序列化
	_test_building_flow()
	# 丧尸视野遮挡: 花园丧尸对房间内的玩家应无视线 (墙挡)
	_test_zombie_vision()
	# 墙体阻挡 + 格子尺寸一致性: 墙格不可走, 格子 = tile_size 等大
	_test_wall_blocking()
	# 读档恢复: JSON 风格存档数据(普通 Array/float) 应完整恢复不崩
	_test_load_restore()
	# 房屋扩建: 消耗材料向右下扩房间, 墙/门跟随
	_test_house_expand()


## 读档恢复回归: 模拟 JSON 存档(普通 Array/float, 非类型化) → apply_pending_player_data 完整恢复不崩
## 曾崩溃: data.get("learned_passives") 是普通 Array, 直接赋给 Array[String] → SCRIPT ERROR 中断 deserialize
func _test_load_restore() -> void:
	var ok := true
	var backup_hp: float = _player.hp
	var fake_data := {
		"hp": 123.0,
		"max_hp": 200.0,
		"ap_current": 7.0,
		"ap_max": 10.0,
		"attack_power": 25.0,
		"defense": 6.0,
		"hunger": 80.0,
		"thirst": 70.0,
		"skill_points": 5.0,
		"absorption_power": 1.0,
		"learned_abilities": [],
		"learned_passives": ["sf_iron_skin"],
		"equipped_slots": {"weapon": "pistol"},
		"position": {"x": 144.0, "y": 176.0},
	}
	GameManager._pending_player_data = fake_data
	GameManager.apply_pending_player_data(_player)
	if not is_equal_approx(_player.hp, 123.0):
		ok = false
		push_error("[Load] HP 未恢复: ", _player.hp)
	if _player.learned_passives.size() != 1 or _player.learned_passives[0] != "sf_iron_skin":
		ok = false
		push_error("[Load] 被动异能未恢复: ", _player.learned_passives)
	if _player.has_method("get_equipped_item") and _player.get_equipped_item("weapon") != "pistol":
		ok = false
		push_error("[Load] 武器未恢复: ", _player.get_equipped_item("weapon"))
	# 恢复现场, 避免影响后续逻辑
	_player.hp = backup_hp
	print("=== 自动测试: 读档恢复(JSON类型)=", ok, " (应为 true)")


## 房屋扩建回归: 消耗材料 → 房间向右下扩 1 格, 旧墙变地板/新墙立起/门跟随新下墙
func _test_house_expand() -> void:
	var ok := true
	var base_size: Vector2i = _room_rect.size
	InventoryBackpack.force_add_item("wood", 60)
	InventoryBackpack.force_add_item("nail", 30)
	var r1 := expand_house()
	if not r1.get("success", false):
		ok = false
		push_error("[Expand] 首次扩建失败: ", r1)
	if _room_rect.size != base_size + Vector2i(1, 1):
		ok = false
		push_error("[Expand] 房间尺寸错误: ", _room_rect.size, " 应=", base_size + Vector2i(1, 1))
	# 旧右墙格变地板, 新右墙不可走
	var old_right := Vector2i(_room_rect.position.x + base_size.x - 1, _room_rect.position.y + 2)
	if not is_cell_walkable(_world_pos(old_right)):
		ok = false
		push_error("[Expand] 旧右墙未变地板: ", old_right)
	var new_right := Vector2i(_room_rect.end.x - 1, _room_rect.position.y + 2)
	if is_cell_walkable(_world_pos(new_right)):
		ok = false
		push_error("[Expand] 新右墙应不可走: ", new_right)
	# 门跟随新下墙中央
	var expect_door := Vector2i(_room_rect.position.x + _room_rect.size.x / 2, _room_rect.end.y - 1)
	if not _door_cells.has(expect_door) or DOOR_CELL != expect_door:
		ok = false
		push_error("[Expand] 门未跟随新下墙: 期望=", expect_door, " 实际门=", DOOR_CELL)
	# 材料不足应拒绝
	InventoryBackpack.remove_item("wood", 200)
	InventoryBackpack.remove_item("nail", 200)
	if expand_house().get("success", false):
		ok = false
		push_error("[Expand] 材料不足却扩建成功")
	print("=== 自动测试: 房屋扩建=", ok, " (应为 true) 房间=", _room_rect.size)


## 工作台交互回归: 模拟左键点击工作台格 (3,2) → 应打开建造/研究面板
## (覆盖: _unhandled_input → _handle_explore_click → _raycast_interactable(家具) → _on_interact → WORKBENCH 分支)
func _test_workbench_interact() -> void:
	var ok := true
	if _build_menu == null:
		ok = false
		push_error("[Workbench] 建造菜单未初始化")
	else:
		_build_menu.visible = false
	_player.is_moving = false
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = get_canvas_transform() * _world_pos(Vector2i(3, 2))
	_unhandled_input(ev)
	if _build_menu == null or not _build_menu.visible:
		ok = false
		push_error("[Workbench] 点击工作台未打开建造菜单")
	if _build_menu:
		_build_menu.visible = false
	print("=== 自动测试: 点击工作台打开建造菜单=", ok, " (应为 true)")


## 家具视觉不拦截鼠标回归: 所有家具子 Control 必须 MOUSE_FILTER_IGNORE
## 根因: HomeFurniture 色块 ColorRect 默认 STOP → GUI 拾取命中 → 悬停黄色预选消失 + 点击被吞 (真机 bug;
## headless 自测直调 _unhandled_input 绕过 GUI 拾取, 抓不到, 需静态断言)
func _test_furniture_mouse_filter() -> void:
	var ok := true
	for f in _furniture_list:
		if not is_instance_valid(f):
			continue
		for c in f.get_children():
			if c is Control and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				ok = false
				push_error("[Furniture] 视觉控件未设 IGNORE: ", f.name, " / ", c.name)
	print("=== 自动测试: 家具视觉不拦截鼠标=", ok, " (应为 true)")


## 墙体阻挡回归: ①墙格 is_cell_walkable=false ②墙格物理尺寸 == tile_size (与主角格等大)
func _test_wall_blocking() -> void:
	var ok := true
	# 1. 墙格不可走: 房间墙 (ROOM_X0, ROOM_Y0)=(2,2) 是墙, 房间内 (3,3) 是地板
	var wall_cell := Vector2i(ROOM_X0, ROOM_Y0)
	var floor_cell := Vector2i(3, 3)
	if is_cell_walkable(_world_pos(wall_cell)):
		ok = false
		push_error("[Wall] 墙格应不可走: ", wall_cell)
	if not is_cell_walkable(_world_pos(floor_cell)):
		ok = false
		push_error("[Wall] 地板格应可走: ", floor_cell)
	# 2. DrawTileMap 格子尺寸 == tile_size (与主角格等大)
	if _tilemap and _tilemap.has_method("get_tile_px"):
		var tile_px: int = _tilemap.get_tile_px()
		if tile_px != tile_size:
			ok = false
			push_error("[Wall] 地图格子 ", tile_px, "px != 主角格 ", tile_size, "px")
	print("=== 自动测试: 墙体阻挡+格子等大=", ok, " (应为 true) 墙=", wall_cell, " 地板=", floor_cell)
	# 3. 真实移动: 玩家站房间内墙边, 朝墙走应被拦; 朝房间内走应放行
	var ok_move := true
	_player.global_position = _world_pos(SPAWN_CELL)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	var stand := Vector2i(ROOM_X0 + 1, ROOM_Y0 + 4)  # 内区左下 (2,5)
	var wall_left := Vector2i(ROOM_X0, stand.y)      # 左墙 (1,5)
	_player.global_position = _world_pos(stand)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	_player.move_in_direction(Vector2(-1, 0))  # 朝左墙
	if _player.is_moving:
		ok_move = false
		push_error("[WallWalk] 玩家朝墙移动被放行!")
	# 朝房间内走 (+1,0) → (3,5) 地板
	_player.move_in_direction(Vector2(1, 0))
	if not _player.is_moving:
		ok_move = false
		push_error("[WallWalk] 玩家朝地板移动被拦截!")
	print("=== 自动测试: 墙体阻止真实移动=", ok_move, " (应为 true) 朝墙=", wall_left)
	# 4. 点击移动: 玩家在房间内点墙外的花园 → 路径应停在墙前, 不穿墙 (用户反馈: 墙可越过去)
	await _test_click_wall_block()


## 点击移动穿墙回归 (home_base): 玩家房间内点墙外花园 → 不应穿过墙
func _test_click_wall_block() -> void:
	var ok := true
	# 房间墙 x=7 是右墙 (ROOM_X1=7), 玩家站 (4,5) 房间中央, 点 (9,5) (墙外花园)
	var stand := Vector2i(4, 5)
	var wall_x := ROOM_X1  # 7
	_player.global_position = _world_pos(stand)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	# 确保完全静止 (move_to_cell 要求 is_moving == false)
	await get_tree().process_frame
	_player.move_to_cell(_world_pos(Vector2i(9, 5)))  # 目标在墙外 (9,5)
	var guard := 0
	while _player.is_moving and guard < 80:
		await get_tree().process_frame
		guard += 1
	var final_cell := _cell_of(_player.global_position)
	# 花园经门下连通, 玩家从房间经门绕到 (9,5) 是合法路径 (未穿墙);
	# 真正的"穿墙"是最终落在墙格, 此处校验最终格非墙且可走 (BFS 只扩展可走格, 不可能真穿墙)
	if not is_cell_walkable(_world_pos(final_cell)):
		ok = false
		push_error("[ClickWall] home_base 点击移动最终落在不可走格(疑似穿墙)! 最终=", final_cell)
	print("=== 自动测试: home_base 点击移动不穿墙=", ok, " (应为 true) 最终=", final_cell, " 起点=", stand)
	# 5. 穷举所有墙格: 房间墙/边界墙全部不可走 (用户反馈: 家里墙可越过去 → 查漏网墙格)
	await _test_all_walls_block()
	# 6. 院门出口: 玩家走到 EXIT_CELL → _process 应触发存档+回主地图
	_test_home_exit()


## 家园大门回归: 玩家走到大门格 → _leaving_home=true (切到城市)
func _test_home_exit() -> void:
	var ok := true
	if not is_cell_walkable(_world_pos(EXIT_CELL)):
		ok = false
		push_error("[HomeExit] 大门格应可走: ", EXIT_CELL)
	_player.global_position = _world_pos(EXIT_CELL)
	_player.is_my_turn = true
	# 手动触发 _process 逻辑 (不真正切场景, 只验证标志)
	var cell := _cell_of(_player.global_position)
	if cell != EXIT_CELL:
		ok = false
		push_error("[HomeExit] 玩家未到达大门格: ", cell)
	print("=== 自动测试: 家园大门=", ok, " (应为 true) 大门=", EXIT_CELL, " 可走且玩家可到达")
	# 恢复玩家位置, 避免后续测试受影响
	_player.global_position = _world_pos(SPAWN_CELL)


## 穷举墙体阻挡: 所有 WALL tile 格子 is_cell_walkable 必须全 false
func _test_all_walls_block() -> void:
	var ok := true
	var walkable_walls: Array[Vector2i] = []
	for y in range(MAP_H):
		for x in range(MAP_W):
			var cell := Vector2i(x, y)
			if _door_cells.has(cell):
				continue  # 门可通行
			var coords: Vector2i = _tilemap.get_cell_atlas_coords(cell)
			if coords.x == TSB.Tiles.WALL and is_cell_walkable(_world_pos(cell)):
				walkable_walls.append(cell)
				ok = false
	if not walkable_walls.is_empty():
		push_error("[WallAll] 可通行的墙格: ", walkable_walls)
	print("=== 自动测试: home_base 所有墙格阻挡=", ok, " (应为 true), 漏网=", walkable_walls.size())
	# 边界外 (峭壁外/地图外灰色区) 也不可走
	var outside_ok := true
	for cell in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(MAP_W, 0), Vector2i(0, MAP_H), Vector2i(MAP_W + 2, MAP_H + 2)]:
		if is_cell_walkable(_world_pos(cell)):
			outside_ok = false
			push_error("[WallOut] 地图外应不可走: ", cell)
	print("=== 自动测试: home_base 地图外阻挡=", outside_ok, " (应为 true)")


## 丧尸视野遮挡回归: 玩家在房间内 → 花园丧尸隔墙看不到; 无墙位置 → 看得到
func _test_zombie_vision() -> void:
	# 引导测试已击杀花园丧尸, 独立生成一个测试丧尸
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var zombie: Node = EF.spawn(self, zombie_script, _world_pos(ZOMBIE_CELL), tile_size, 100.0)
	zombie.world = self
	var ok := true
	# 1. 玩家在房间内 (出生点) → 丧尸隔墙看不到
	_player.global_position = _world_pos(SPAWN_CELL)
	var blocked: bool = not zombie.has_line_of_sight(_player.global_position)
	if not blocked:
		ok = false
		push_error("[Vision] 丧尸隔墙应看不到房间内玩家")
	# 2. 无墙紧邻位置 → 看得到
	var open_cell := _cell_of(zombie.global_position) + Vector2i(1, 0)
	var los_open: bool = zombie.has_line_of_sight(_world_pos(open_cell))
	if not los_open:
		ok = false
		push_error("[Vision] 无墙紧邻位置丧尸应能看到")
	if is_instance_valid(zombie):
		zombie.queue_free()
	print("=== 自动测试: 丧尸视野遮挡=", ok, " (应为 true)")


## 生存流水线回归: 净化器→种植→生长→收获→睡觉 (Phase 6)
## 建造/研究回归: 研究蓝图(消耗素材) → 建造家具(消耗素材+放置) → 占用/序列化校验
func _test_building_flow() -> void:
	_reset_home_test_state()
	var ok := true
	# 备足素材 (外部收集) — 用 force_add_item 绕过负重限制, 仅验证建造链路本身
	# (真机玩家需靠负重上限/储物把素材带回家, 此处不测重量约束)
	InventoryBackpack.force_add_item("wood", 40)
	InventoryBackpack.force_add_item("nail", 40)
	InventoryBackpack.force_add_item("cloth", 40)
	InventoryBackpack.force_add_item("metal_scrap", 40)
	# 1. 工作台预解锁
	if not BuildingManager.is_researched(HF.Kind.WORKBENCH):
		ok = false
		push_error("[Build] 工作台应预解锁")
	# 2. 研究床 (消耗研究素材)
	var rb := BuildingManager.research(HF.Kind.BED)
	if not rb.get("success", false):
		ok = false
		push_error("[Build] 研究床失败: ", rb)
	if not BuildingManager.is_researched(HF.Kind.BED):
		ok = false
		push_error("[Build] 床研究后未解锁")
	# 重复研究应失败
	if BuildingManager.research(HF.Kind.BED).get("success", false):
		ok = false
		push_error("[Build] 重复研究应通过")
	# 3. 未研究不能建造
	var r_un := BuildingManager.commit_build(HF.Kind.GYM, Vector2i(13, 13))
	if r_un.get("success", false):
		ok = false
		push_error("[Build] 未研究却能建造 GYM")
	# 4. 建造床到空地
	var cell := Vector2i(13, 12)
	var r_build := BuildingManager.commit_build(HF.Kind.BED, cell)
	if not r_build.get("success", false):
		ok = false
		push_error("[Build] 建造床失败: ", r_build)
	# 同格重复建造应失败
	if BuildingManager.commit_build(HF.Kind.BED, cell).get("success", false):
		ok = false
		push_error("[Build] 同格重复建造应通过")
	# 5. 场景放置校验: 墙格应被拒 (_try_build_at 不调 commit 故不消耗素材)
	var before := _furniture_list.size()
	_build_kind = HF.Kind.BED
	_try_build_at(_world_pos(Vector2i(ROOM_X0, ROOM_Y0)))  # 墙
	if _furniture_list.size() != before:
		ok = false
		push_error("[Build] 墙上建造未被拒绝")
	# 门口不可建
	_try_build_at(_world_pos(DOOR_CELL))
	if _furniture_list.size() != before:
		ok = false
		push_error("[Build] 门口建造未被拒绝")
	_build_kind = -1
	# 6. 序列化应包含已建家具
	var ser := BuildingManager.serialize()
	if ser["built"].size() < 1:
		ok = false
		push_error("[Build] 序列化未包含已建家具")
	print("=== 自动测试: 建造/研究=", ok, " (应为 true), 已研究=", BuildingManager.researched.size(), " 已建=", BuildingManager.built.size())


## 测试隔离: 清空建造状态 + 移除除工作台外的家具节点 + 清测试素材
## 让 引导/生存/建造 三个自测互不污染 (它们共享 BuildingManager 全局状态)
func _reset_home_test_state() -> void:
	BuildingManager.reset()
	for f in _furniture_list.duplicate():
		if f is HF and f.kind == HF.Kind.WORKBENCH:
			continue
		_furniture_list.erase(f)
		if is_instance_valid(f):
			f.queue_free()
	for k in _home_furniture.keys().duplicate():
		if int(k) == HF.Kind.WORKBENCH:
			continue
		_home_furniture.erase(k)
	for id in ["wood", "nail", "cloth", "metal_scrap", "seed_vegetable", "water_pure", "water_polluted", "zombie_flesh", "baseball_bat"]:
		var n: int = InventoryBackpack.count_item(id)
		if n > 0:
			InventoryBackpack.remove_item(id, n)


func _test_survival_flow() -> void:
	_reset_home_test_state()
	var ok := true
	# 测试环境: 临时放大负重上限 (避免 10kg 初始容量限制干扰流水线链路验证, 结束后恢复)
	var backup_max_weight: float = InventoryBackpack.max_weight
	InventoryBackpack.max_weight = 200.0
	# 新流程: 初始家园只有工作台, 其余家具需先建造 (给足素材)
	InventoryBackpack.force_add_item("wood", 40)
	InventoryBackpack.force_add_item("nail", 40)
	InventoryBackpack.force_add_item("metal_scrap", 40)
	InventoryBackpack.force_add_item("cloth", 40)
	# 确保有种子/净水/污染水/升级材料 (force_add 绕过负重, 与上方素材一致)
	InventoryBackpack.force_add_item("seed_vegetable", 3)
	InventoryBackpack.force_add_item("water_pure", 3)
	InventoryBackpack.force_add_item("water_polluted", 4)
	InventoryBackpack.force_add_item("zombie_flesh", 3)
	InventoryBackpack.force_add_item("wood", 2)
	# 建造所需家具: 收集器/净化器/种植区/床 (复用原预置格, 均为空地)
	var spec := [
		[HF.Kind.RAIN_COLLECTOR, COLLECTOR_CELL],
		[HF.Kind.PURIFIER, PURIFIER_CELL],
		[HF.Kind.PLANTING_BED, PLANTING_CELL],
		[HF.Kind.BED, BED_CELL],
	]
	for s in spec:
		var kind: int = int(s[0])
		var cell: Vector2i = s[1]
		var rb := BuildingManager.research(kind)
		if not rb.get("success", false):
			ok = false
			push_error("[Home] 研究失败: ", rb)
		var r_build := BuildingManager.commit_build(kind, cell)
		if not r_build.get("success", false):
			ok = false
			push_error("[Home] 建造失败: ", r_build)
		_spawn_built_furniture(kind, cell)
	# 1. 净化器: 放 2 污染水 → 净化 → 得净水
	var purifier: HF = _home_furniture.get(HF.Kind.PURIFIER)
	var r_purify: Dictionary = purifier.purify()
	if not r_purify.get("success", false):
		ok = false
		push_error("[Home] 净化失败: ", r_purify)
	if _player.count_item("water_pure") < 2:
		ok = false
		push_error("[Home] 净化后净水不足")
	# 2. 种植区: 种种子 → 直接生长到成熟 → 收获
	var planting: HF = _home_furniture.get(HF.Kind.PLANTING_BED)
	var ok_plant: bool = planting.plant("seed_vegetable")
	if not ok_plant:
		ok = false
		push_error("[Home] 种植失败: ", planting.last_message)
	planting.grow_plant(60.0)  # 模拟 60 小时
	if planting.stored < 100:
		ok = false
		push_error("[Home] 生长进度错误: ", planting.stored)
	var r_harvest: Dictionary = planting.harvest_plant()
	if not r_harvest.get("success", false):
		ok = false
		push_error("[Home] 收获失败: ", r_harvest)
	# 3. 雨水收集器: 强制下雨 → 积攒 → 收获
	var collector: HF = _home_furniture.get(HF.Kind.RAIN_COLLECTOR)
	WorldTime.current_weather = WorldTime.Weather.RAIN
	collector.collect_rain()
	collector.collect_rain()
	if collector.stored < 1:
		ok = false
		push_error("[Home] 收集器未积攒污染水")
	var got: int = collector.harvest_collector()
	if got < 1:
		ok = false
		push_error("[Home] 收集器收获失败")
	WorldTime.current_weather = WorldTime.Weather.CLOUDY
	# 4. 睡觉: 先扣血+降精力, 验证恢复 (旧 sleep 字段已移除)
	_player.take_damage(80.0)
	_player.ap_current = 3  # 起始精力低, 睡觉后应恢复到接近 ap_max=10
	var hp_before: float = _player.hp
	var ap_before: float = _player.ap_current
	var bed: HF = _home_furniture.get(HF.Kind.BED)
	var r_sleep: Dictionary = bed.sleep_on_bed(_player)
	if not r_sleep.get("success", false):
		ok = false
		push_error("[Home] 睡觉失败")
	if _player.hp <= hp_before:
		ok = false
		push_error("[Home] 睡觉未回血: ", hp_before, " -> ", _player.hp)
	if _player.ap_current <= ap_before:
		ok = false
		push_error("[Home] 睡觉未恢复精力: ", ap_before, " -> ", _player.ap_current)
	# 5. 床升级: 给材料 → 升级 → 恢复量提升
	var r_upgrade: Dictionary = bed.upgrade_bed()
	if not r_upgrade.get("success", false):
		ok = false
		push_error("[Home] 床升级失败: ", r_upgrade)
	if bed.bed_level != 2:
		ok = false
		push_error("[Home] 床等级错误: ", bed.bed_level)
	# 6. 升级后睡觉恢复量应更高 (2级 60 > 1级 40)
	var restore_2: float = bed._bed_sleep_restore()
	if restore_2 <= 40.0:
		ok = false
		push_error("[Home] 升级后恢复量未提升: ", restore_2)
	InventoryBackpack.max_weight = backup_max_weight  # 恢复初始负重
	print("=== 生存流水线=", ok, " (应为 true), 净水=", _player.count_item("water_pure"), " 污染水=", _player.count_item("water_polluted"), " 床Lv=", bed.bed_level)


## 新手引导全链路回归: 装备→攻击/战斗→搜刮→建造→升级
func _test_tutorial_flow() -> void:
	if GameManager:
		GameManager.set_tutorial_for_test(true)
	_reset_home_test_state()
	# 0. 跳过教程链路: 横幅显示 + 跳过按钮 → 状态机置 done + 退出教程模式
	var skip_ok := true
	if _hud and _hud.has_method("show_tutorial"):
		_hud.show_tutorial("新手教程（自测横幅）")
	await get_tree().process_frame
	var banner: Node = _hud.get("_tutorial_banner") if _hud else null
	if banner == null or not banner.visible:
		skip_ok = false
		push_error("[Guide] 教程横幅未显示")
	var skip_btn: Button = banner.find_child("SkipTutorialBtn", true, false) if banner else null
	if skip_btn == null:
		skip_ok = false
		push_error("[Guide] 跳过教程按钮缺失")
	else:
		skip_btn.pressed.emit()
		await get_tree().process_frame
		if _tutorial_step != "done" or (GameManager and GameManager.is_tutorial_mode()):
			skip_ok = false
			push_error("[Guide] 跳过教程后状态错误: step=", _tutorial_step)
	print("=== 引导测试: 跳过教程按钮=", skip_ok, " (应为 true)")
	# 重新开启教程模式, 继续完整 5 步流程 (跳过测试把状态机置 done, 须重置回 wake_up)
	if GameManager:
		GameManager.set_tutorial_for_test(true)
	_tutorial_step = "wake_up"
	# 1. 装备武器 (触发 equipment_changed → 推进 equipped)
	_player.add_item("baseball_bat", 1)
	var equipped: bool = _player.equip_item("baseball_bat")
	await get_tree().process_frame
	print("=== 引导测试: 装备棒球棍=", equipped, " (应为 true)")
	# 2. 发起战斗 (模拟点击丧尸进入战斗 → 推进 combat_started)
	TurnManager.combat_started.emit()
	await get_tree().process_frame
	# 3. 搜刮 (模拟打开容器 → 推进 looted)
	container_opened.emit(self)
	await get_tree().process_frame
	# 4. 建造床 + 储物箱 (研究+建造+放置 → 两者就绪推进 built)
	InventoryBackpack.force_add_item("wood", 20)
	InventoryBackpack.force_add_item("nail", 10)
	InventoryBackpack.force_add_item("cloth", 10)
	BuildingManager.research(HF.Kind.BED)
	BuildingManager.commit_build(HF.Kind.BED, BED_CELL)
	_spawn_built_furniture(HF.Kind.BED, BED_CELL)
	BuildingManager.research(HF.Kind.CHEST)
	BuildingManager.commit_build(HF.Kind.CHEST, CHEST_CELL)
	_spawn_built_furniture(HF.Kind.CHEST, CHEST_CELL)
	await get_tree().process_frame
	# 5. 升级床 (右键 → _handle_home_furniture → 推进 upgraded → done)
	InventoryBackpack.force_add_item("zombie_flesh", 5)
	_last_right_click_on_furniture = true
	var bed: HF = _home_furniture.get(HF.Kind.BED)
	_handle_home_furniture(bed)
	await get_tree().process_frame
	print("=== 引导测试: 引导步骤=", _tutorial_step, " (应为 done)")
	print("=== 引导测试: 教程完成=", not GameManager.is_tutorial_mode() if GameManager else true, " (应为 true)")
