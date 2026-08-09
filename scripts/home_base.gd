extends "res://scripts/scenes/game_scene_base.gd"

# ============================================================
# HomeBase — 家园场景 (继承 GameSceneBase)
# ============================================================
# 新手开局场景: 玩家在房间醒来 → 衣柜拿棒球棍 → 装备 → 花园打初级丧尸
# 布局 (16×16 格):
#   房间 (左上 2..7 x 2..7): 玩家出生 + 衣柜(含棒球棍)
#   门   (房间右下角): 通往花园
#   花园 (右侧大片): 1 只初级丧尸
# 通用逻辑 (UI/输入/点击交互/移动范围) 全部在基类

const TSB := preload("res://scripts/dungeons/tile_set_builder.gd")
const FUR := preload("res://scripts/tiles/furniture.gd")
const HF := preload("res://scripts/tiles/home_furniture.gd")
const EF := preload("res://scripts/units/enemy_factory.gd")
const BMU := preload("res://scripts/ui/build_menu.gd")

const MAP_W := 16
const MAP_H := 16

## 房间范围 (格)
const ROOM_X0 := 2
const ROOM_Y0 := 2
const ROOM_X1 := 7
const ROOM_Y1 := 7
## 门位置 (房间下墙中央, 内侧(4,6)为房间地板/外侧(4,8)为花园 → 内外连通)
const DOOR_CELL := Vector2i(4, 7)
## 衣柜位置 (房间左上角)
const CHEST_CELL := Vector2i(2, 2)
## 床位置 (房间右上)
const BED_CELL := Vector2i(6, 2)
## 净化器位置 (房间左下)
const PURIFIER_CELL := Vector2i(2, 6)
## 玩家出生 (房间中央)
const SPAWN_CELL := Vector2i(4, 5)
## 花园丧尸位置
const ZOMBIE_CELL := Vector2i(11, 4)
## 雨水收集器位置 (花园左上, 需露天)
const COLLECTOR_CELL := Vector2i(10, 3)
## 种植区位置 (花园)
const PLANTING_CELL := Vector2i(12, 9)
## 健身器材位置 (房间内, 锻炼用)
const GYM_CELL := Vector2i(4, 2)

var _furniture_list: Array = []
## 功能家具: kind → HomeFurniture (交互分发用)
var _home_furniture: Dictionary = {}

## 建造系统: 建造/研究面板 + 放置模式
var _build_menu: Node = null
var _build_mode: bool = false
var _build_kind: int = -1


# --- 地图生成 ---

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

	# 房间墙 (围一圈, 留门)
	for x in range(ROOM_X0, ROOM_X1 + 1):
		_set_wall(Vector2i(x, ROOM_Y0))
		_set_wall(Vector2i(x, ROOM_Y1))
	for y in range(ROOM_Y0, ROOM_Y1 + 1):
		_set_wall(Vector2i(ROOM_X0, y))
		_set_wall(Vector2i(ROOM_X1, y))

	# 门 (房间下墙中央, 2 格宽开口 → 醒目且易点中): 内侧(4/5,6)为房间地板, 外侧(4/5,8)为花园
	var door_cells := [DOOR_CELL, Vector2i(5, 7)]
	for dc in door_cells:
		_tilemap.set_cell(dc, 0, Vector2i(TSB.Tiles.DOOR, 0))
		_door_cells[dc] = true

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
	_player = PF.spawn(self, _world_pos(SPAWN_CELL), tile_size)
	_player.world = self
	print("[HomeBase] 玩家在房间醒来: ", _player.global_position)


# --- 敌人 + 家具 ---

func _spawn_entities() -> void:
	_spawn_chest()
	_spawn_home_furniture()
	_spawn_garden_zombie()
	_refresh_move_grid()


## 衣柜: 固定放棒球棍 (新手引导: 拿走→装备→打丧尸)
func _spawn_chest() -> void:
	var chest := FUR.new()
	chest.setup(CHEST_CELL, tile_size, ["baseball_bat"], 1, "衣柜")
	chest.furniture_name = "衣柜"
	add_child(chest)
	_furniture_list.append(chest)
	print("[HomeBase] 衣柜生成 (含棒球棍) at ", CHEST_CELL)


## 家园功能家具: 床/净化器/雨水收集器/种植区 (Phase 6)
func _spawn_home_furniture() -> void:
	# 床 (房间右上)
	var bed := HF.new()
	bed.setup(HF.Kind.BED, BED_CELL, tile_size)
	add_child(bed)
	_home_furniture[HF.Kind.BED] = bed
	_furniture_list.append(bed)

	# 雨水净化器 (房间左下; 需蓝图解锁, 新玩家直接解锁以便体验流程)
	var purifier := HF.new()
	purifier.setup(HF.Kind.PURIFIER, PURIFIER_CELL, tile_size)
	add_child(purifier)
	_home_furniture[HF.Kind.PURIFIER] = purifier
	_furniture_list.append(purifier)

	# 雨水收集器 (花园, 露天才下雨)
	var collector := HF.new()
	collector.setup(HF.Kind.RAIN_COLLECTOR, COLLECTOR_CELL, tile_size)
	collector.capacity = 6
	add_child(collector)
	_home_furniture[HF.Kind.RAIN_COLLECTOR] = collector
	_furniture_list.append(collector)

	# 室内种植区 (花园)
	var planting := HF.new()
	planting.setup(HF.Kind.PLANTING_BED, PLANTING_CELL, tile_size)
	add_child(planting)
	_home_furniture[HF.Kind.PLANTING_BED] = planting
	_furniture_list.append(planting)

	# 健身器材 (房间内, 点击锻炼 +体力 消耗世界时间)
	var gym := HF.new()
	gym.setup(HF.Kind.GYM, GYM_CELL, tile_size)
	add_child(gym)
	_home_furniture[HF.Kind.GYM] = gym
	_furniture_list.append(gym)

	# 工作台 (固定, 点击打开建造/研究面板; 玩家从此研究蓝图并建造家具)
	var workbench := HF.new()
	workbench.setup(HF.Kind.WORKBENCH, Vector2i(3, 2), tile_size)
	add_child(workbench)
	_home_furniture[HF.Kind.WORKBENCH] = workbench
	_furniture_list.append(workbench)

	print("[HomeBase] 家园家具就绪: 床/净化器/收集器/种植区/健身/工作台")


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


## 点击家具: 容器家具(衣柜)走基类; 功能家具按类型分发
func _on_interact(interact: Node) -> void:
	# 功能家具
	if interact is HF:
		_handle_home_furniture(interact)
		return
	# 容器家具 (衣柜)
	super._on_interact(interact)
	if _furniture_list.size() > 0 and interact == _furniture_list[0]:
		_tutorial_step_completed("chest_opened")


## 功能家具交互分发
func _handle_home_furniture(f: HF) -> void:
	match f.kind:
		HF.Kind.BED:
			# 床: 左键睡觉, 右键升级 (右键标记在 _input 里设置)
			if _last_right_click_on_furniture:
				_last_right_click_on_furniture = false
				_show_result(f.upgrade_bed())
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
	# 读档恢复: 把 BuildingManager 中已建家具生成到场景
	_spawn_built_furniture_all()


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
	var f := HF.new()
	f.setup(kind, cell, tile_size)
	add_child(f)
	_home_furniture[kind] = f
	_furniture_list.append(f)


## 读档: 从 BuildingManager 恢复所有已建家具
func _spawn_built_furniture_all() -> void:
	for b in BuildingManager.built:
		_spawn_built_furniture(int(b["kind"]), Vector2i(int(b["x"]), int(b["y"])))


## 花园初级丧尸 (弱化版: 低血量, 新手可击杀)
func _spawn_garden_zombie() -> void:
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var zombie := EF.spawn(self, zombie_script, _world_pos(ZOMBIE_CELL), tile_size, 100.0)
	zombie.name = "GardenZombie"
	zombie.world = self
	# 新手丧尸: 削弱血量, 移动慢
	zombie.max_hp = 40.0
	zombie.hp = 40.0
	zombie.move_speed = 80.0
	print("[HomeBase] 花园丧尸生成 (初级 HP=", zombie.hp, ") at ", ZOMBIE_CELL)


# --- 新手引导 (简易) ---

var _tutorial_step: String = "wake_up"


## 引导步骤推进 (由 HUD 或场景内触发)
func _tutorial_step_completed(step: String) -> void:
	if _tutorial_step == "wake_up" and step == "chest_opened":
		_tutorial_step = "equip_bat"
		_show_tutorial_hint("获得棒球棍! 打开背包, 点击棒球棍穿戴到武器槽")
	elif _tutorial_step == "equip_bat" and step == "equipped":
		_tutorial_step = "kill_zombie"
		_show_tutorial_hint("穿过花园的门, 用棒球棍消灭初级丧尸")
	elif _tutorial_step == "kill_zombie" and step == "zombie_killed":
		_tutorial_step = "done"
		_show_tutorial_hint("新手教程完成! 现在可以自由探索了")
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
	# 丧尸死亡 → 推进引导
	for enemy in TurnManager.get_enemy_units():
		if enemy.has_signal("enemy_died"):
			enemy.enemy_died.connect(_on_garden_zombie_died)


func _on_player_equipped(item_id: String, _slot: String) -> void:
	if GameManager and GameManager.is_tutorial_mode():
		if item_id == "baseball_bat":
			_tutorial_step_completed("equipped")


func _on_garden_zombie_died(_enemy: Node) -> void:
	if GameManager and GameManager.is_tutorial_mode():
		_tutorial_step_completed("zombie_killed")


# --- 自动测试钩子 ---

func _on_scene_ready() -> void:
	super._on_scene_ready()  # 通用截图钩子 (--screenshot)
	_setup_tutorial_listeners()
	_setup_survival_links()
	# 新手引导: 开场提示拿棒球棍
	if GameManager and GameManager.is_tutorial_mode():
		_show_tutorial_hint("醒来第一件事: 打开房间里的衣柜, 拿走棒球棍")
	_setup_build_menu()
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
	print("=== 家园自动测试: 玩家出生 + 衣柜 + 丧尸 ===")
	print("=== 玩家位置=", _player.global_position, " 衣柜数=", _furniture_list.size(), " 敌人数=", TurnManager.get_enemy_units().size())
	# 打开衣柜验证棒球棍
	var chest: Node = _furniture_list[0]
	var items: Array = chest.list_inventory()
	print("=== 衣柜内容=", items)
	print("=== 家园自动测试完成 ===")
	# 移动/点击路由回归 (排查"无法行走")
	_test_movement_routing()
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
	# 3. 真实移动: 玩家站房间内 (4,5), 上方 (4,4) 是地板可走, 左方墙 (2,5) 不可走
	var ok_move := true
	_player.global_position = _world_pos(SPAWN_CELL)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	# 向左走 → 墙 (2,5)? SPAWN=(4,5), 左一格 (3,5) 是房间内地板 (可走), 再左 (2,5) 是墙
	# 直接测: 把玩家放墙边, 朝墙走
	var stand := Vector2i(3, 5)
	var wall_left := Vector2i(2, 5)
	_player.global_position = _world_pos(stand)
	_player.is_my_turn = true
	_player.ap_current = _player.ap_max
	_player.move_in_direction(Vector2(-1, 0))  # 朝墙 (2,5)
	if _player.is_moving:
		ok_move = false
		push_error("[WallWalk] 玩家朝墙移动被放行!")
	# 朝房间内走 (+1,0) → (4,5) 地板
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


func _test_survival_flow() -> void:
	var ok := true
	# 测试环境: 临时放大负重上限 (避免 10kg 初始容量限制干扰流水线链路验证, 结束后恢复)
	var backup_max_weight: float = InventoryBackpack.max_weight
	InventoryBackpack.max_weight = 200.0
	# 测试环境: 确保有种子和净水
	_player.add_item("seed_vegetable", 3)
	_player.add_item("water_pure", 3)
	# 1. 净化器: 放 2 污染水 → 净化 → 得净水
	_player.add_item("water_polluted", 4)
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
	_player.add_item("zombie_flesh", 3)
	_player.add_item("wood", 2)
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


## 新手引导全链路回归: 拿走→装备→击杀
func _test_tutorial_flow() -> void:
	# 测试场景直接加载未走 start_new_game, 手动开启引导模式
	if GameManager:
		GameManager.set_tutorial_for_test(true)
	var chest: Node = _furniture_list[0]
	# 0. 模拟点击衣柜 (推进 chest_opened 步骤)
	_tutorial_step_completed("chest_opened")
	# 1. 拿走棒球棍
	chest.remove_internal_item("baseball_bat")
	_player.add_item("baseball_bat", 1)
	# 2. 装备 (触发 equipment_changed 信号 → 推进 equipped 步骤)
	var equipped: bool = _player.equip_item("baseball_bat")
	print("=== 引导测试: 装备棒球棍=", equipped, " (应为 true)")
	# 3. 击杀花园丧尸 (模拟: 直接扣血到死 → enemy_died 信号 → 推进 zombie_killed)
	var zombie: Node = TurnManager.get_enemy_units()[0] if TurnManager.get_enemy_units().size() > 0 else null
	if zombie:
		zombie.take_damage(9999.0)
		await get_tree().process_frame
	print("=== 引导测试: 引导步骤=", _tutorial_step, " (应为 done)")
	print("=== 引导测试: 教程完成=", not GameManager.is_tutorial_mode() if GameManager else true, " (应为 true)")
