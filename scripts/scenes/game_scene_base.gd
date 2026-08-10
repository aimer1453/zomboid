extends Node2D

# ============================================================
# GameSceneBase — 所有游戏场景基类 (通用层)
# ============================================================
# 抽取三个场景 (combat_test / main_map / dungeon_base) 的重复代码:
#   - UI 工厂: CombatUI / MoveGrid / ActionMenu / HUD / 异能树 / 容器UI
#   - 战斗信号: 开战 / 结束 / 玩家回合 / 移动停止 → 统一刷新移动范围
#   - 输入分发 + 点击情境交互 (探索连续移动 / 战斗动作菜单 / 空地走1格)
#   - 动作收集 (武器+拳击兜底+异能+绷带) / 网格命中 / 坐标工具
#
# 子类只负责差异化, 覆写以下钩子:
#   _create_world()         生成地图 (TileMapLayer/墙体)
#   _create_player()        生成玩家 (默认 PlayerFactory.spawn)
#   _spawn_entities()       生成敌人/家具/战利品
#   _use_container_ui()     是否需要容器 UI (dungeon = true)
#   _raycast_interactable() 交互物命中 (家具等), 默认 null
#   _on_interact(node)      点击交互物后的行为
#   is_cell_walkable()      寻路障碍检测 (墙)
#   _on_scene_ready()       场景初始化完成钩子 (挂 auto-test)

const CSM := preload("res://scripts/combat/combat_state_machine.gd")
const CUI := preload("res://scripts/ui/combat_ui.gd")
const AM := preload("res://scripts/ui/action_menu.gd")
const CA := preload("res://scripts/combat/combat_actions.gd")
const HUDG := preload("res://scripts/ui/hud.gd")
const ATU := preload("res://scripts/ui/ability_tree_ui.gd")
const QP := preload("res://scripts/ui/quest_panel.gd")
const SLP := preload("res://scripts/ui/save_load_panel.gd")
const CIU := preload("res://scripts/ui/container_ui.gd")
const GI := preload("res://scripts/tiles/ground_item.gd")
const CP := preload("res://scripts/tiles/corpse.gd")
const PF := preload("res://scripts/units/player_factory.gd")
const DTM := preload("res://scripts/scenes/draw_tile_map.gd")
const FOW := preload("res://scripts/scenes/fog_of_war.gd")

## 格子尺寸 (px)。combat_test.tscn 显式设 64, 其余场景默认 32
@export var tile_size: int = 32

## 探索模式固定可移动格数 (视野稳定, 不随 AP 变化)
const EXPLORE_MOVE_TILES := 5

var _player: CharacterBody2D = null
var _combat_sm: Node = null
var _combat_ui: Control = null
var _move_grid: Node2D = null
var _action_menu: CanvasLayer = null
var _hud: CanvasLayer = null
var _ability_ui: CanvasLayer = null
var _container_ui: CanvasLayer = null
var _tilemap: Node = null  # DrawTileMap (preload DTM)
## 选中地块指示箭头 (渐变出现→消失, 用户反馈: 表明选择的是这个地块)
var _selection_arrow: Node2D = null
## 鼠标悬停地块高亮 (用户反馈: 对鼠标选中的地块高亮标记, 不是点击后显示标)
var _hover_highlight: Node2D = null
## 全场景尸体列表 (enemy_base._spawn_corpse 自动注册, 战斗/探索都生效)
var _corpses: Array = []
## 全场景地面物品列表 (容器丢弃/背包丢出生成, 可拾取)
var _ground_items: Array = []
## 待搜刮的远处尸体: 玩家走到旁边后自动打开其背包 (Issue B 自动寻路)
var _pending_loot: Node = null
## 战争迷雾层 (场景内视野遮蔽, 主角醒来仅视野内可见)
var _fog: FOW = null

## 小地图 (CanvasLayer, 屏幕右上角, 复用迷雾探索状态)
var _minimap: CanvasLayer = null


func _ready() -> void:
	TurnManager.reset_scene()
	_create_world()
	_create_player()
	# P0 存档: 读档后把主角数据应用到刚创建的 Player 节点
	if _player:
		GameManager.apply_pending_player_data(_player)
	_spawn_entities()
	_setup_combat()
	_setup_move_grid()
	_create_action_menu()
	_setup_selection_arrow()
	_setup_hover_highlight()
	if _use_container_ui():
		_create_container_ui()
	_create_hud()
	_create_ability_ui()
	# 连接玩家移动完成信号 (用于"走到尸体旁自动开包")
	if _player and _player.has_signal("move_completed"):
		_player.move_completed.connect(_on_player_move_completed)
	_refresh_move_grid()
	_on_scene_ready()
	_init_fog_of_war()
	_init_minimap()
	# 进场景先播探索 BGM (战斗时会被 fight.mp3 顶掉, 战斗结束再切回)
	if SoundManager and not TurnManager.combat_mode:
		SoundManager.play_bgm("round.mp3", -6.0)


## 创建选中地块指示箭头 (渐变出现→消失)
func _setup_selection_arrow() -> void:
	var arrow_script := preload("res://scripts/ui/selection_arrow.gd")
	_selection_arrow = Node2D.new()
	_selection_arrow.set_script(arrow_script)
	_selection_arrow.name = "SelectionArrow"
	_selection_arrow.z_index = 5  # 画在角色之上
	add_child(_selection_arrow)


## 创建鼠标悬停地块高亮 (半透明覆盖, 跟随鼠标)
func _setup_hover_highlight() -> void:
	var hover_script := preload("res://scripts/ui/hover_highlight.gd")
	_hover_highlight = Node2D.new()
	_hover_highlight.set_script(hover_script)
	_hover_highlight.name = "HoverHighlight"
	_hover_highlight.z_index = 4  # 画在角色之上、箭头之下
	add_child(_hover_highlight)


## 每帧: 鼠标悬停格高亮 (UI 打开时隐藏, 避免遮挡面板)
func _process(_delta: float) -> void:
	if not _hover_highlight:
		return
	# 鼠标悬停在 UI 控件上 (面板/按钮) → 不显示地块高亮
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered:
		_hover_highlight.hide_highlight()
		return
	var mouse_world := get_global_mouse_position()
	_hover_highlight.set_cell_center(mouse_world, tile_size)


## 战争迷雾: 主角视野半径内全亮, 看过/走过的格保留半亮记忆, 其余被迷雾覆盖
func _init_fog_of_war() -> void:
	_fog = FOW.new()
	_fog.name = "FogOfWar"
	_fog.vision_radius = 7
	add_child(_fog)
	var tm: Node = _tilemap
	if tm == null:
		for ch in get_children():
			if ch is DTM:
				tm = ch
				break
	_fog.setup(tm, tile_size)
	# 子类可 override 返回固定键(如 "home_base")让该场景视野跨进入保留; 默认空=每次重置
	_fog.set_memory_key(_fog_memory_key())
	if _player != null:
		_fog.reveal_from(_cell_of(_player.global_position))


## 迷雾记忆键: 默认空(不持久化, 每次进入重置); 子类 override 可让特定场景视野跨进入保留
func _fog_memory_key() -> String:
	return ""


## 小地图: CanvasLayer(layer=50, 在 HUD layer=60 之下) 内放一个 FULL_RECT Control 自绘
## 复用 FogOfWar 探索/可见状态 + DrawTileMap 地形 + TurnManager 敌人
func _init_minimap() -> void:
	if _tilemap == null or _player == null:
		return
	var mm_script := preload("res://scripts/ui/mini_map.gd")
	_minimap = CanvasLayer.new()
	_minimap.name = "MiniMap"
	_minimap.layer = 50
	var panel := Control.new()
	panel.set_script(mm_script)
	panel.name = "MiniMapPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(panel)
	add_child(_minimap)
	panel.setup(_tilemap, _fog, _player)


func _physics_process(_delta: float) -> void:
	if _fog != null and _player != null:
		var pc: Vector2i = _cell_of(_player.global_position)
		if pc != _fog.last_cell:
			_fog.last_cell = pc
			_fog.reveal_from(pc)


## 在目标格中心显示选中箭头 (探索/战斗点击移动时调用)
func _show_selection_arrow(world_pos: Vector2) -> void:
	if _selection_arrow and _selection_arrow.has_method("show_at"):
		_selection_arrow.show_at(world_pos, tile_size)


# --- 子类钩子 (默认空实现) ---

func _create_world() -> void:
	pass

func _create_player() -> void:
	pass

func _spawn_entities() -> void:
	pass

func _use_container_ui() -> bool:
	return true

## 默认交互物命中: 查尸体列表 (dungeon 覆写先查家具再 super 查尸体)
func _raycast_interactable(world_pos: Vector2) -> Node:
	var clicked_cell := _cell_of(world_pos)
	for c in _corpses:
		if not is_instance_valid(c):
			continue
		var gp: Vector2i = c.get("grid_pos") if c.get("grid_pos") != null else Vector2i(-9999, -9999)
		if gp == clicked_cell:
			return c
	# 地面物品 (容器丢弃/丢出后掉落, 可拾取)
	for gi in _ground_items:
		if not is_instance_valid(gi):
			continue
		var g_gp: Vector2i = gi.get("grid_pos") if gi.get("grid_pos") != null else Vector2i(-9999, -9999)
		if g_gp == clicked_cell:
			return gi
	return null

## 战斗/探索中由 enemy_base._spawn_corpse 调用, 注册尸体供玩家搜刮
func add_corpse(c: Node) -> void:
	_corpses.append(c)

## 移除尸体 (搜刮清空后由 Corpse 自动调用)
func remove_corpse(c: Node) -> void:
	_corpses.erase(c)

## 某格是否无其它尸体占用 (避免叠尸): 丧尸死后落点已有一具尸体时, 应挪到旁边空位
func is_cell_free_for_corpse(cell: Vector2i) -> bool:
	for c in _corpses:
		if is_instance_valid(c) and c.has_method("get_grid_pos") and c.get_grid_pos() == cell:
			return false
	return true

## 通用"被占用"钩子: 该格是否不可作落点 (尸体/地面物品生成用). 默认 false, 子类(副本)按家具/地形覆写.
func is_cell_blocked(cell_center: Vector2) -> bool:
	return false


## 找一个靠近 cell 的可放尸体格: 优先原地, 其次 4 向, 再 8 向; 优先可通行且非家具格 (挤满则原地)
func find_free_corpse_cell(cell: Vector2i) -> Vector2i:
	if is_cell_free_for_corpse(cell) and not _cell_blocked_for_corpse(cell):
		return cell
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var any_fallback: Vector2i = cell
	for off in offsets:
		var c: Vector2i = cell + off
		if not is_cell_free_for_corpse(c):
			continue
		if _cell_blocked_for_corpse(c):
			if any_fallback == cell:
				any_fallback = c
			continue
		return c
	return any_fallback


## 尸体落点是否被占用(墙/家具/越界): 统一走子类钩子 is_cell_blocked
func _cell_blocked_for_corpse(cell: Vector2i) -> bool:
	if has_method("is_cell_blocked"):
		return is_cell_blocked(_world_pos(cell))
	return false


## 注册地面物品 (ContainerUI 丢弃 / 拾取后移除)
func add_ground_item(gi: Node) -> void:
	_ground_items.append(gi)


func remove_ground_item(gi: Node) -> void:
	_ground_items.erase(gi)


## 公开: 容器/背包丢弃物品 → 生成地面物品 (落在玩家附近空地, 可再捡起)
## UI 层统一通过此公开方法调用 (背包丢弃曾误调 _spawn_ground_item 私有方法并传错参数 → 掉落失效)
func spawn_ground_item(item_id: String, count: int = 1) -> void:
	_spawn_ground_item(item_id, count)


## 容器/背包丢弃物品 → 生成地面物品 (落在玩家相邻空位, 找不到就玩家脚下)
func _spawn_ground_item(item_id: String, count: int = 1) -> void:
	if not _player:
		return
	var player_cell := _cell_of(_player.global_position)
	# 候选落点: 玩家自身格 + 四邻, 优先"可走 且 未被其他地面物品占用", 避免多件全堆在同一格
	var candidates: Array[Vector2i] = [player_cell,
		player_cell + Vector2i(1, 0), player_cell + Vector2i(-1, 0),
		player_cell + Vector2i(0, 1), player_cell + Vector2i(0, -1)]
	var target_cell := player_cell
	for c in candidates:
		if is_cell_walkable(_world_pos(c)) and not _cell_has_ground_item(c):
			target_cell = c
			break
	var gi: Node = GI.new()
	gi.setup(target_cell, tile_size, item_id, count)
	add_child(gi)
	_ground_items.append(gi)
	print("[场景] 丢弃 ", item_id, " ×", count, " → 地面 (", target_cell, ")")


## 某格是否已有地面物品 (掉落分散用)
func _cell_has_ground_item(cell: Vector2i) -> bool:
	for gi in _ground_items:
		if is_instance_valid(gi) and gi.get("grid_pos") == cell:
			return true
	return false

## 玩家打开任意容器(尸体/衣柜/箱子/货架等)时发出 — 教程"搜刮"步骤据此推进
signal container_opened(container: Node)

## 通用交互物行为: 地面物品 → 拾取; 可搜刮物(家具/尸体) → 打开容器 UI
## (修复: 之前是空实现, 主地图/测试场景点尸体无反应; 子类可覆写扩展)
func _on_interact(interact: Node) -> void:
	if interact.has_method("is_ground_item") and interact.is_ground_item():
		var result: Dictionary = interact.pick_up()
		if result.get("success", false):
			print("[场景] 拾取地面物品: ", result.get("item_id"), " ×", result.get("count"))
		else:
			print("[场景] 拾取失败: 背包已满或超重")
		return
	if _container_ui and interact.has_method("list_inventory"):
		# 搜刮/开柜距离限制: 玩家须靠近容器至少 1 格(切比雪夫), 除非持有空间系异能可隔空搜刮.
		# 适用于所有容器: 尸体 / 衣柜 / 储物柜 / 箱子 / 保险箱 / 货架 等.
		if not _player_can_loot(interact):
			# 不在范围内 → 自动寻路走到容器旁 1 格内, 到达后由 _on_player_move_completed 开包
			_walk_to_loot(interact)
			return
		var name_str: String = interact.get("furniture_name") if interact.get("furniture_name") != null else interact.name
		_container_ui.open(interact, name_str)
		container_opened.emit(interact)


## 玩家是否可搜刮/开柜: 默认须距离容器切比雪夫 ≤1 格 (同格或八方相邻);
## 持有"空间系异能"可隔空搜刮 (任意距离). 缺信息时不误杀正常交互.
func _player_can_loot(container: Node) -> bool:
	if _has_space_ability():
		return true
	if not _player or not container.has_method("get_grid_pos"):
		return true
	var player_cell := _cell_of(_player.global_position)
	var container_cell: Vector2i = container.get_grid_pos()
	var d := player_cell - container_cell
	return max(abs(d.x), abs(d.y)) <= 1


## 是否持有空间系异能: learned_abilities 中任一 CombatAction 标记为 space 分类,
## 或名称/ID 含 空间/space/维度/storage/dimension 关键字.
func _has_space_ability() -> bool:
	if not _player:
		return false
	for ability in _player.get("learned_abilities"):
		if ability == null or not is_instance_of(ability, CA):
			continue
		if str(ability.get("ability_category")) == "space":
			return true
		if _is_space_keyword(str(ability.get("action_id"))) or _is_space_keyword(str(ability.get("name"))):
			return true
	return false


func _is_space_keyword(s: String) -> bool:
	s = s.to_lower()
	return "空间" in s or "space" in s or "维度" in s or "storage" in s or "dimension" in s


# --- 尸体自动寻路搜刮 (Issue B) ---

## 玩家走到容器旁后回调: 若有待搜刮容器且已在 1 格内 → 自动开包
func _on_player_move_completed() -> void:
	if not _pending_loot or not is_instance_valid(_pending_loot):
		_pending_loot = null
		return
	if _player_can_loot(_pending_loot):
		var container := _pending_loot
		_pending_loot = null  # 先清空, 避免递归
		if _container_ui and container.has_method("list_inventory"):
			var name_str: String = container.get("furniture_name") if container.get("furniture_name") != null else container.name
			_container_ui.open(container, name_str)
			container_opened.emit(container)
			print("[场景] 到达容器旁, 自动打开背包: ", name_str)


## 规划路径 → 走到容器旁边 (1 格内), 到达后由 _on_player_move_completed 自动开包
func _walk_to_loot(container: Node) -> void:
	if not _player or not container.has_method("get_grid_pos"):
		return
	var target_cell := _find_adjacent_walkable_cell(container.get_grid_pos())
	if target_cell == Vector2i(-1, -1):
		var msg := "容器周围没有可通行的位置"
		print("[场景] ", msg)
		if _hud and _hud.has_method("append_log"):
			_hud.append_log(msg)
		return
	_pending_loot = container
	_show_selection_arrow(_world_pos(target_cell))
	_player.move_to_cell(_world_pos(target_cell))
	print("[场景] 自动走向容器: ", target_cell)


## 找到目标格最近的可行走邻格 (八方 + 自身, 优先距离玩家当前位置最近).
## 返回 (-1,-1) 表示全部不可走.
func _find_adjacent_walkable_cell(target: Vector2i) -> Vector2i:
	if not _player:
		return Vector2i(-1, -1)
	var player_cell := _cell_of(_player.global_position)
	var best_cell := Vector2i(-1, -1)
	var best_dist := 999999
	# 候选: 目标自身格 + 八方邻格 (尸体所在格通常不可走, 但 BFS 会跳过)
	var candidates: Array[Vector2i] = [target,
		target + Vector2i(1, 0), target + Vector2i(-1, 0),
		target + Vector2i(0, 1), target + Vector2i(0, -1),
		target + Vector2i(1, 1), target + Vector2i(1, -1),
		target + Vector2i(-1, 1), target + Vector2i(-1, -1)]
	for c in candidates:
		if is_cell_walkable(_world_pos(c)):
			var d := c - player_cell
			var dist: int = absi(d.x) + absi(d.y)  # 曼哈顿距离 (与 BFS 代价一致)
			if dist < best_dist:
				best_dist = dist
				best_cell = c
	return best_cell


func _on_scene_ready() -> void:
	if "--screenshot" in OS.get_cmdline_user_args():
		_save_scene_screenshot()


## 通用截图钩子 (视觉排查用, --screenshot 参数, 所有场景共用)
func _save_scene_screenshot() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	if _hud and _hud.has_method("_log_panel"):
		pass
	var img := get_viewport().get_texture().get_image()
	var path := "user://scene_shot.png"
	img.save_png(path)
	print("[Screenshot] 已保存: ", path)

## 寻路障碍检测: 子类按各自地图实现 (墙格子不可走)
func is_cell_walkable(_cell_center: Vector2) -> bool:
	return true


# --- UI 工厂 ---

func _setup_combat() -> void:
	_combat_sm = CSM.new()
	_combat_sm.name = "CombatStateMachine"
	add_child(_combat_sm)

	_combat_ui = CUI.new()
	_combat_ui.name = "CombatUI"
	# 面板视觉已删除 (回合/AP/阶段/结束提示), 仅保留警报横幅 + _input 选靶
	_combat_ui.set_combat_state_machine(_combat_sm)
	add_child(_combat_ui)

	TurnManager.player_turn_started.connect(_refresh_move_grid)
	TurnManager.combat_started.connect(_on_combat_started)
	TurnManager.combat_ended.connect(_on_combat_ended)
	if _player:
		_player.movement_stopped.connect(_on_player_stopped)


func _setup_move_grid() -> void:
	var grid_script := load("res://scripts/combat/move_grid.gd")
	_move_grid = Node2D.new()
	_move_grid.set_script(grid_script)
	_move_grid.tile_size = tile_size
	add_child(_move_grid)


func _create_action_menu() -> void:
	_action_menu = AM.new()
	_action_menu.name = "ActionMenu"
	add_child(_action_menu)


func _create_container_ui() -> void:
	_container_ui = CIU.new()
	_container_ui.name = "ContainerUI"
	add_child(_container_ui)
	# 容器丢弃物品 → 场景生成地面物品 (可再捡起)
	if _container_ui.has_signal("item_discarded"):
		_container_ui.item_discarded.connect(_spawn_ground_item)


func _create_hud() -> void:
	_hud = HUDG.new()
	_hud.name = "HUD"
	add_child(_hud)
	# 战斗状态机日志 → HUD.CombatLog (日志迁移到 HUD, 不再焊死在 CombatUI 底部)
	if _combat_sm and _hud.has_method("append_log"):
		_combat_sm.combat_log_updated.connect(_hud.append_log)


func _create_ability_ui() -> void:
	_ability_ui = ATU.new()
	_ability_ui.name = "AbilityTreeUI"
	add_child(_ability_ui)
	# 任务面板 (与异能树同级, 由 HUD "任务" 按钮切换)
	var quest_ui: Node = QP.new()
	quest_ui.name = "QuestPanel"
	add_child(quest_ui)
	# 存档读档面板 (由 HUD "存档读档" 按钮打开, 多槽位管理)
	var slp_ui: Node = SLP.new()
	slp_ui.name = "SaveLoadPanel"
	add_child(slp_ui)


# --- 战斗信号 ---

func _on_combat_started() -> void:
	if _move_grid:
		_move_grid.hide_grid()
	# 仅"被惊动(范围内)"的丧尸头上亮感叹号; 范围外的不卷入
	var engaged_count := 0
	for enemy in TurnManager.get_enemy_units():
		if enemy.has_method("is_engaged") and enemy.is_engaged() and enemy.has_method("show_alert"):
			enemy.show_alert()
			engaged_count += 1
	# 战斗 BGM
	if SoundManager:
		SoundManager.play_bgm("fight.mp3", -4.0)
	print("[", name, "] 进入战斗! 被惊动丧尸=", engaged_count, " (仅范围内, 非全层)")


func _on_combat_ended(victory: bool) -> void:
	# 探索 BGM
	if SoundManager:
		SoundManager.play_bgm("round.mp3", -6.0)
	print("[", name, "] 战斗结束 (胜利=", victory, ")")
	_refresh_move_grid.call_deferred()


func _on_player_stopped() -> void:
	if not TurnManager.combat_mode:
		_refresh_move_grid()


# --- 移动范围 ---

func _refresh_move_grid() -> void:
	if not _player or not _move_grid:
		return
	if TurnManager.combat_mode and _combat_sm and not _combat_sm.is_player_turn():
		_move_grid.hide_grid()
		return
	# 探索模式: 固定可移动范围(5格, 视野稳定); 战斗模式: 按 AP 算
	var tiles: int
	if TurnManager.combat_mode:
		tiles = maxi(int(_player.get("ap_current")), 0) / maxi(TurnManager.get_action_cost("move"), 1)
	else:
		tiles = EXPLORE_MOVE_TILES
	_move_grid.set_range(_player.global_position, tiles, false)  # 不显示红色格子, 只保留移动范围逻辑 (迷雾体现视野)


# --- 输入分发 ---

## 战场点击用 _unhandled_input: GUI 按钮 consume 事件后场景收不到,
## 从根上避免"点背包按钮/存档按钮同时触发战场移动" (修复: 战斗点背包角色挪一步)
func _unhandled_input(event: InputEvent) -> void:
	# 背包/异能界面打开时: 忽略地图操作
	if (_hud and _hud.is_open()) or (_ability_ui and _ability_ui.is_open()):
		return
	# 容器界面打开时: 点面板外关闭; 点面板内交给 GUI (按钮/格子正常响应)
	if _container_ui and _container_ui.is_open():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _container_ui.is_point_on_panel(get_viewport().get_mouse_position()):
				_container_ui.close()
		return
	# 菜单(敌人动作 / 主角地板操作)打开时:
	# 点面板内 → 交给按钮(GUI 已 consume, 不会进此分支);
	# 点面板外且为"鼠标按下" → 关闭菜单. 只在按下时关(忽略松开),
	# 否则打开菜单那记点击的 release 会把自己刚弹出的菜单关掉 (编辑器按下/松开间夹 mouse_motion 时尤其明显).
	if _action_menu and _action_menu.is_open():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _action_menu.is_point_on_panel(get_viewport().get_mouse_position()):
				_action_menu.hide_menu()
		return

	# 键盘调试: End = 强制结束回合, Space = 攻击最近敌人
	if event.is_action_pressed("wait_turn"):
		if _combat_sm and _combat_sm.is_player_turn():
			_combat_sm.skip_turn()
		return
	if event.is_action_pressed("ui_accept"):
		if _combat_sm and _combat_sm.is_player_turn() and _player:
			_player.attack_nearest_enemy()
		return

	# 鼠标左键: 用事件坐标 (更精确, 避免 get_global_mouse_position 滞后)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if TurnManager.combat_mode:
			if _combat_sm and _combat_sm.is_player_turn():
				_handle_combat_click(event)
		else:
			_handle_explore_click(event)


# --- 点击交互 ---

## 虚拟钩子: 子类声明"某格是出口/院门"时重写. 点击该格 → 无视移动范围直接走向 (到达后触发出院).
func _is_exit_cell(_cell: Vector2i) -> bool:
	return false

## 探索模式: 点击优先级 = 精确格敌人 > 精确格交互物(尸体/家具) > 容差敌人 > 空地移动
## (修复: 尸体被邻格丧尸的容差命中抢走 → "点尸体没反应")
func _handle_explore_click(event: InputEvent) -> void:
	var world_pos := _event_to_world(event)
	# 1. 精确格敌人 (点中丧尸所在格 → 主动开战)
	var enemy := _raycast_enemy(world_pos, true)
	if enemy:
		_open_action_menu(enemy)
		return
	# 2. 精确格交互物 (点中尸体/家具/地面物品 → 搜刮/拾取)
	var interact := _raycast_interactable(world_pos)
	if interact:
		_on_interact(interact)
		return
	# 点击主角所在格 → 弹出坐下/锻炼菜单 (优先于移动)
	if _is_player_cell(world_pos):
		_open_player_floor_menu(get_viewport().get_mouse_position())
		return
	# 院门/出口: 点出院门 → 无视移动范围限制, 一路走过去, 到达后 _process 触发出院
	if _is_exit_cell(_cell_of(world_pos)):
		if _player and not _player.get_is_moving():
			_player.move_to_cell(world_pos)
		return
	# (用户反馈: 没点丧尸所在格不应弹操作菜单 → 移除 2 格容差命中, 只认精确格)
	if _move_grid and _player:
		if _move_grid.is_cell_in_range(world_pos):
			# 选中地块指示箭头 (用户反馈)
			_show_selection_arrow(world_pos)
			_player.move_to_cell(world_pos)
		else:
			print("[", name, "] 超出移动范围")


## 战斗模式: 点击优先级 = 精确格敌人 > 精确格交互物 > 容差敌人 > 空地走1格
func _handle_combat_click(event: InputEvent) -> void:
	var world_pos := _event_to_world(event)
	# 1. 精确格敌人 (点中丧尸所在格)
	var enemy := _raycast_enemy(world_pos, true)
	if enemy:
		_open_action_menu(enemy)
		return
	# 2. 精确格交互物 (点中尸体/家具 → 搜刮; 修复尸体被邻格丧尸容差抢走)
	var interact := _raycast_interactable(world_pos)
	if interact:
		_on_interact(interact)
		return
	# 点击主角所在格 → 弹出坐下/锻炼菜单 (优先于移动)
	if _is_player_cell(world_pos):
		_open_player_floor_menu(get_viewport().get_mouse_position())
		return
	# (用户反馈: 没点丧尸所在格不应弹操作菜单 → 移除 2 格容差命中, 只认精确格)
	# 3. 空地 → 走1格
	_try_move_one_step(world_pos)


## 事件坐标 → 世界坐标
## event.position 在 Godot 4 里是**视口坐标**, 直接用 get_canvas_transform() 还原即可,
## 这与 get_global_mouse_position() (悬停高亮用的同一函数) 完全一致 → 点击与悬停必定命中同一格。
## 注意: 不能多乘 get_screen_transform()! 它含"视口→屏幕窗口"变换, 只在视口==窗口时
## (全屏/headless) 才恒等; 编辑器内运行游戏时视口被缩放/嵌入, 该变换非单位矩阵 →
## 点击坐标被整体偏移数格 → _cell_of 取整到错误格 → 点不中丧尸 (headless 全过、真机失败的根因)
func _event_to_world(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return get_canvas_transform().affine_inverse() * mb.position
	return get_global_mouse_position()


## 朝点击方向走 1 格 (单动作回合制, 走完即结束回合)
func _try_move_one_step(world_pos: Vector2) -> void:
	if not _player or _player.get_is_moving() or _player.get_ap() <= 0:
		return
	var delta := world_pos - _player.global_position
	var dir := Vector2.ZERO
	if absf(delta.x) >= absf(delta.y):
		dir = Vector2(signf(delta.x), 0)
	else:
		dir = Vector2(0, signf(delta.y))
	if dir != Vector2.ZERO:
		# 选中地块指示箭头 (用户反馈)
		_show_selection_arrow(world_pos)
		_player.move_in_direction(dir)


# --- 动作菜单 ---

## 弹出敌人动作菜单 (攻击手段/异能/道具)
func _open_action_menu(enemy: Node) -> void:
	if not _action_menu or not _player:
		return
	var actions := _collect_actions()
	if actions.is_empty():
		return
	var screen_pos := get_viewport().get_mouse_position()
	_action_menu.show_at(screen_pos, actions, func(action: Resource): _on_action_selected(enemy, action))


## 主角所在地板: 弹出"坐下/锻炼"操作列表
## (战斗中禁用: 被丧尸围攻时不能坐地休息/锻炼, 见用户需求)
func _open_player_floor_menu(screen_pos: Vector2) -> void:
	if TurnManager.combat_mode:
		return
	if not _action_menu or not _player:
		return
	var entries := [
		{"label": "坐下", "callback": func(): _player.sit()},
		{"label": "锻炼", "callback": func(): _player.train()},
	]
	_action_menu.show_generic(screen_pos, entries)


## 点击坐标是否落在主角当前所在格
func _is_player_cell(world_pos: Vector2) -> bool:
	if not _player:
		return false
	return _cell_of(world_pos) == _cell_of(_player.global_position)


## 收集当前可用动作 (武器攻击 + 拳击兜底 + 异能 + 绷带)
func _collect_actions() -> Array:
	var actions: Array = []
	if not _player:
		return actions
	var default_action: Resource = _player.get_default_attack()
	actions.append(default_action)
	# 空手近战兜底 (与远程武器并存, 避免菜单里只有远程)
	if default_action.get("action_id") != "punch":
		actions.append(CA.get_action("punch"))
	# 异能
	for ability in _player.get("learned_abilities"):
		if ability != null and is_instance_of(ability, CA):
			actions.append(ability)
	# 道具 (有绷带就显示使用)
	if InventoryBackpack.count_item("bandage") > 0:
		actions.append(CA.create_item_action("use_bandage", "使用绷带"))
	return actions


func _on_action_selected(enemy: Node, action: Resource) -> void:
	if not _player:
		return
	var action_type: int = int(action.get("action_type") if action.get("action_type") != null else 0)
	if action_type == CA.ActionType.USE_ITEM:
		_player.use_item_on_self("bandage")
	elif action_type == CA.ActionType.ABILITY:
		_player.execute_ability(action, enemy)
	else:
		_player.execute_attack(enemy, action)


# --- 网格命中 ---

## 网格命中检测:
##   - 精确格匹配 (静止时准)
##   - 移动目标格匹配 (丧尸正走向该格也算点中)
##   - 亚格容差 (0.6 格半径): 覆盖相机缩放/平滑/视口缩放导致的点击坐标微小偏移, 让"点丧尸地块"更宽容
##     容差 < 1 格, 不会抢走相邻尸体/家具 (它们距敌人 ≥1 格)
func _raycast_enemy(world_pos: Vector2, exact_only: bool = false) -> Node:
	var clicked_cell := _cell_of(world_pos)
	var hit_radius_sq := (tile_size * 0.6) * (tile_size * 0.6)  # 0.6 格半径容差 (< 1 格, 安全不抢相邻尸体)
	for enemy in TurnManager.get_enemy_units():
		if not is_instance_valid(enemy):
			continue
		# 注意: hp 是 float, 不能用 int() 截断! 0<hp<1 (血条显示"1") 时 int(0.8)=0 会被误判为死亡而跳过,
		# 导致"残血丧尸点不中". 直接用 float 比较 (死亡逻辑 character.gd 也是 hp<=0.0).
		var hp_raw = enemy.get("hp")
		if hp_raw == null or float(hp_raw) <= 0.0:
			continue
		var e_pos: Vector2 = enemy.global_position
		# 当前格匹配 (静止时准)
		if _cell_of(e_pos) == clicked_cell:
			return enemy
		# 移动目标格匹配: 丧尸正走向 clicked_cell → 也算点中 (用户反馈: 移动中点丧尸地块没反应)
		if enemy.get("is_moving") and enemy.get("_target_position") != null:
			var tgt: Vector2 = enemy.get("_target_position")
			if _cell_of(tgt) == clicked_cell:
				return enemy
		# 亚格容差: 覆盖坐标转换/移动/缩放偏移 (exact_only 不再完全跳过, 0.6 格足够小不会抢相邻尸体)
		if e_pos.distance_squared_to(world_pos) <= hit_radius_sq:
			return enemy
	return null


# --- 坐标工具 ---

## 格子坐标 → 世界坐标 (格子中心)
func _world_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile_size + tile_size * 0.5, cell.y * tile_size + tile_size * 0.5)


## 世界坐标 → 格子坐标
func _cell_of(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))
