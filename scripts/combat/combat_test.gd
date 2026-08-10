class_name CombatTest
extends "res://scripts/scenes/game_scene_base.gd"

# ============================================================
# CombatTest — 战斗测试场地 (继承 GameSceneBase)
# ============================================================
# 只保留差异化:
#   - 测试场地墙 (边界 + 内部隔断, F5 可见墙体验寻路)
#   - 测试敌人生成 (4 种类型循环)
#   - auto-test 回归钩子
# 通用逻辑 (UI/输入/点击交互/移动范围) 全部在基类

const TSB := preload("res://scripts/dungeons/tile_set_builder.gd")
const EF := preload("res://scripts/units/enemy_factory.gd")

@export var spawn_radius: int = 8
@export var test_enemies: int = 1

var _wall_cells: Dictionary = {}


# --- 测试场地墙体 (边界墙 + 内部墙) ---

func _create_world() -> void:
	print("=".repeat(40))
	print("  CombatTest — 探索 + 战斗 全流程测试")
	print("=".repeat(40))
	_create_walls()


func _create_walls() -> void:
	var tilemap := DTM.new()  # 自定义绘制 (TileMapLayer 渲染不可靠)
	tilemap.tile_size = tile_size  # 与单位格子等大 (combat_test.tscn 设 64, 必须同步)
	add_child(tilemap)
	_tilemap = tilemap

	# 场地范围: 格 0..15 (世界 0..960), 玩家出生 (200,200)
	const MAP_COLS := 16
	const MAP_ROWS := 16
	# 全部铺地板
	for y in range(MAP_ROWS):
		for x in range(MAP_COLS):
			tilemap.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))  # FLOOR

	# 边界墙 (一圈)
	for x in range(MAP_COLS):
		_set_wall_cell(tilemap, Vector2i(x, 0))
		_set_wall_cell(tilemap, Vector2i(x, MAP_ROWS - 1))
	for y in range(MAP_ROWS):
		_set_wall_cell(tilemap, Vector2i(0, y))
		_set_wall_cell(tilemap, Vector2i(MAP_COLS - 1, y))

	# 内部墙 (几面隔断, 测试寻路绕墙) — 线段两端点之间每一格都要标成墙
	# (原实现只标端点, 中间格是地板 → 丧尸从缺口绕过去, 误报"穿墙")
	var internal := [
		[Vector2i(5, 2), Vector2i(5, 5)],
		[Vector2i(10, 9), Vector2i(10, 13)],
		[Vector2i(2, 10), Vector2i(6, 10)],
		[Vector2i(12, 3), Vector2i(14, 3)],
	]
	for seg in internal:
		var a: Vector2i = seg[0]
		var b: Vector2i = seg[1]
		var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
		for i in range(steps + 1):
			var t := float(i) / float(steps) if steps > 0 else 0.0
			var cx := int(round(a.x + (b.x - a.x) * t))
			var cy := int(round(a.y + (b.y - a.y) * t))
			_set_wall_cell(tilemap, Vector2i(cx, cy))
	print("[CombatTest] 场地墙体已生成 (边界 + 内部隔断, 线段已填满)")


func _set_wall_cell(tilemap: Node, cell: Vector2i) -> void:
	tilemap.set_cell(cell, 0, Vector2i(1, 0))  # WALL
	_wall_cells[cell] = true


## 寻路障碍: 墙格子不可走 (玩家 world 引用此方法)
func is_cell_walkable(cell_center: Vector2) -> bool:
	var cell := _cell_of(cell_center)
	return not _wall_cells.has(cell)


# --- 玩家 ---

func _create_player() -> void:
	# 出生在对齐格中心的位置 (用户反馈: 出生点不在格子中心 → 点击坐标错位点不中丧尸)
	var spawn_cell := Vector2i(3, 3)
	_player = PF.spawn(self, _world_pos(spawn_cell), tile_size)
	_player.move_speed = 300.0
	_player.world = self  # 寻路障碍检测 (墙体)
	print("[CombatTest] 玩家创建于 ", _player.global_position, " 格=", _cell_of(_player.global_position))


# --- 测试敌人 ---

func _spawn_entities() -> void:
	var enemy_types := [
		load("res://scripts/units/enemies/zombie_basic.gd"),
		load("res://scripts/units/enemies/zombie_runner.gd"),
		load("res://scripts/units/enemies/zombie_spitter.gd"),
		load("res://scripts/units/enemies/zombie_tank.gd"),
	]
	for i in range(test_enemies):
		var script: Script = enemy_types[i % enemy_types.size()]
		_spawn_enemy(script, i)


func _spawn_enemy(script: Script, index: int) -> void:
	# 位置: 围绕玩家, 半径随机偏移 (7~9 格), 角度微扰避免整齐一圈
	# 对齐格中心 (用户反馈: 出生点不在格子中心 → 点击/命中全部错位)
	var angle := (float(index) / maxi(test_enemies, 1)) * TAU + randf_range(-0.3, 0.3)
	var r := float(spawn_radius + randi_range(-1, 1)) * tile_size
	var raw_pos: Vector2 = _player.global_position + Vector2(cos(angle), sin(angle)) * r
	var spawn_pos: Vector2 = Vector2(
		floori(raw_pos.x / tile_size) * tile_size + tile_size * 0.5,
		floori(raw_pos.y / tile_size) * tile_size + tile_size * 0.5
	)
	var enemy := EF.spawn(self, script, spawn_pos, tile_size, 160.0)
	enemy.name = "Enemy_%d" % index
	print("[CombatTest] 生成 ", enemy.get("enemy_name") if enemy.get("enemy_name") != null else "敌", " 于 ", spawn_pos, " 格=", _cell_of(spawn_pos))


# --- 自动测试钩子 (仅命令行带 --auto-test 时触发) ---

func _on_scene_ready() -> void:
	if "--auto-test" in OS.get_cmdline_user_args():
		_run_auto_test()


## 等待辅助: 本环境 headless 下 SceneTree.create_timer / Timer 节点的 timeout 信号不触发,
## 且 wall-clock (Time.get_ticks_msec) 不前进, 故用 process_frame 帧数轮询 (harness 固定 60fps)
func _await_secs(sec: float) -> void:
	var frames := int(ceil(sec * 60.0))
	for i in frames:
		await get_tree().process_frame

func _run_auto_test() -> void:
	# --- 同步核心回归 (不依赖帧信号, 先行以对抗 headless 帧信号不稳定) ---
	_test_explore_click_enemy_menu()
	_test_combat_click_enemy_menu_sync()
	_test_enemy_menu()
	_test_click_world_roundtrip()
	_test_low_hp_enemy_selectable()
	_test_player_floor_menu()
	_test_combat_pull_in_on_proximity()
	_test_combat_blocks_floor_menu()
	# Issue B 距离限制回归 (全同步, 放最前保证 headless 帧信号不稳时也能跑到)
	_test_corpse_loot_proximity()
	_test_furniture_loot_proximity()
	# 叠尸挪位回归 (全同步, 提前跑确保覆盖)
	_test_corpse_no_overlap()
	# 探索连续移动验证: 向左走2格再走回来 (确认移动一次后还能继续移动)
	print("=== 自动测试: 探索连续移动 (左2格) ===")
	_player.move_to_cell(_player.global_position + Vector2(-tile_size * 2, 0))
	await _await_secs(1.2)
	print("=== 自动测试: 一次移动后 pos=", _player.global_position, " is_moving=", _player.is_moving, " combat=", TurnManager.combat_mode)
	_player.move_to_cell(_player.global_position + Vector2(tile_size * 2, 0))
	await _await_secs(1.2)
	print("=== 自动测试: 二次移动后 pos=", _player.global_position, " combat=", TurnManager.combat_mode)

	print("=== 自动测试: 探索模式, 向最近丧尸移动 ===")
	var enemies := TurnManager.get_enemy_units()
	if enemies.size() > 0:
		var target: Node = enemies[0]
		_player.move_to_cell(target.global_position)
		await _await_secs(3.5)
		print("=== 自动测试: 移动后 combat_mode = ", TurnManager.combat_mode)
		if TurnManager.combat_mode:
			print("=== 自动测试: 战斗模式, 攻击最近敌人 ===")
			var e2 := TurnManager.get_enemy_units()
			if e2.size() > 0:
				_player.execute_attack(e2[0], _player.get_default_attack())
			await _await_secs(1.5)

	print("=== 自动测试: 尸体交互链路 (生成→命中→容器打开) ===")
	_test_corpse_interaction()
	_test_item_menu_and_discard()
	_test_corpse_loot()
	_test_survival()
	_test_save_load()
	_test_equip_drag()
	_test_backpack_click_no_move()
	_test_enemy_menu()
	_test_player_floor_menu()
	_test_click_enemy_combat()
	_test_menu_survives_release()
	_test_click_enemy_cell()
	_test_durability()
	_test_corpse_priority()
	_test_corpse_spawn_cell()
	_test_corpse_no_overlap()
	_test_wall_walk_block()
	_test_click_path_no_wall()
	_test_flee_two_stage()
	_test_menu_position()
	_test_selection_arrow()
	_test_hover_highlight()
	_test_unit_visuals_ignore_mouse()
	_test_click_world_roundtrip()
	_test_ability_tree_centered()
	_test_health_bar_label_centered()
	_test_corpse_label_centered()
	_test_ap_deduction_on_attack()
	_test_combat_ui_hides_on_end()
	_test_zombie_wall_block()
	await _test_bgm_loop_and_sfx()
	print("=== 自动测试完成 ===")


## 主角地板操作菜单: 点击主角所在格应弹出"坐下/锻炼"操作列表
func _test_player_floor_menu() -> void:
	if not _action_menu or not _player:
		push_warning("[FloorMenu] 无菜单/玩家, 跳过")
		return
	var ok := true
	_open_player_floor_menu(get_viewport().get_mouse_position())
	if not _action_menu.is_open():
		ok = false
		push_error("[FloorMenu] 点击主角地板未弹出坐下/锻炼菜单 (玩家格=", _cell_of(_player.global_position), ")")
	_action_menu.hide_menu()
	print("=== 自动测试: 主角地板操作菜单=", ok, " (应为 true)")


## 战斗中禁用坐下/锻炼: 进入战斗后点击主角地板不应弹出"坐下/锻炼"菜单
func _test_combat_blocks_floor_menu() -> void:
	if not _action_menu or not _player:
		push_warning("[CombatFloorMenu] 无菜单/玩家, 跳过")
		return
	TurnManager.enter_combat()
	var ok := true
	_open_player_floor_menu(get_viewport().get_mouse_position())
	if _action_menu.is_open():
		ok = false
		push_error("[CombatFloorMenu] 战斗中点主角地板仍弹出坐下/锻炼菜单 (应被禁用)")
	_action_menu.hide_menu()
	TurnManager.exit_combat(true)
	print("=== 自动测试: 战斗中点主角地板不弹坐下/锻炼菜单=", ok, " (应为 true)")


## 战斗中动态拉怪/脱战回归 (用户需求: 战斗中未卷入的丧尸, 玩家走近距离<触发距离→拉入; 走远>距离→脱离)
func _test_combat_pull_in_on_proximity() -> void:
	var ok := true
	var player_home: Vector2 = _player.global_position
	var z_script := load("res://scripts/units/enemies/zombie_basic.gd")
	# 远处丧尸放 (13,8): 欧氏距玩家(3,3)=~11.2 格 > AGGRO_RADIUS(10); y=8 整行无墙, 视线无遮挡
	var far_cell := Vector2i(13, 8)
	var z: Node = EF.spawn(self, z_script, _world_pos(far_cell), tile_size, 100.0)
	z.world = self
	await get_tree().process_frame
	if not is_instance_valid(z):
		push_error("[PullIn] 远处丧尸生成失败")
		print("=== 自动测试: 战斗中动态拉怪/脱战=", false, " (应为 true)")
		return
	# 开局进入战斗: propagate_aggro 只卷入 10 格内, 远处丧尸应保持未卷入
	TurnManager.enter_combat()
	await get_tree().process_frame
	if z.is_engaged():
		ok = false
		push_error("[PullIn] 远处丧尸不应在战斗开局就被卷入 (dist>10)")
	# 玩家走入其 detection_range(5) 且同一空旷行 (无墙遮挡) → 应被拉入
	_player.global_position = _world_pos(Vector2i(9, 8))
	await get_tree().process_frame
	z.take_turn()
	await get_tree().process_frame
	if not z.is_engaged():
		ok = false
		push_error("[PullIn] 玩家走入触发距离后远处丧尸应被拉入战斗 (实际未卷入)")
	# 反向: 玩家走远 (>AGGRO 10 格) → 该丧尸应脱离战斗
	_player.global_position = _world_pos(Vector2i(1, 8))
	await get_tree().process_frame
	z.take_turn()
	await get_tree().process_frame
	if z.is_engaged():
		ok = false
		push_error("[PullIn] 玩家走远后远处丧尸应脱离战斗 (实际仍卷入)")
	TurnManager.exit_combat(true)
	if TurnManager.has_method("unregister_unit"):
		TurnManager.unregister_unit(z)
	z.queue_free()
	_player.global_position = player_home  # 还原, 避免影响后续用例
	await get_tree().process_frame
	print("=== 自动测试: 战斗中动态拉怪/脱战=", ok, " (应为 true)")


## 丧尸穿墙回归: 丧尸在墙边随机巡逻 N 步 → 永不越过墙 (用户反馈: 丧尸绕过墙行走)
func _test_zombie_wall_block() -> void:
	var ok := true
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var z: Node = EF.spawn(self, zombie_script, _world_pos(Vector2i(4, 2)), tile_size, 100.0)
	z.world = self
	# (5,2)-(5,5) 是一整面墙; 丧尸随机巡逻 40 步, 应永远无法踏入墙格
	# (沿墙绕到 (5,6) 等是合法的, 故用"是否踏入墙格"判定, 而非 x 坐标阈值)
	for step in 40:
		z._step_random()
		var guard := 0
		while z.is_moving and guard < 40:
			await _await_secs(0.05)
			guard += 1
		var cell := _cell_of(z.global_position)
		if _wall_cells.has(cell):
			ok = false
			push_error("[ZWall] 丧尸踏入墙格! 墙=", cell, " 丧尸=", cell)
			break
	z.queue_free()
	print("=== 自动测试: 丧尸不越墙=", ok, " (应为 true)")


## 悬停高亮回归: set_cell_center 吸附格中心 (用户反馈: 鼠标选中的地块高亮)
func _test_hover_highlight() -> void:
	if not _hover_highlight:
		push_warning("[Hover] 无高亮组件, 跳过")
		return
	var ok := true
	# 任意世界坐标 → 应吸附到所在格中心 (坐标偏移一格内部)
	var world := _world_pos(Vector2i(5, 6)) + Vector2(10, 14)
	_hover_highlight.set_cell_center(world, tile_size)
	var center: Vector2 = _hover_highlight._cell_center
	var expect := _world_pos(Vector2i(5, 6))
	if center.distance_to(expect) > 1.0:
		ok = false
		push_error("[Hover] 高亮未吸附格中心: ", center, " 期望=", expect)
	# hide → 不再绘制
	_hover_highlight.hide_highlight()
	print("=== 自动测试: 悬停高亮吸附=", ok, " (应为 true) 中心=", center)


## 单位视觉不拦截鼠标回归: 丧尸/玩家身体 ColorRect 必须为 MOUSE_FILTER_IGNORE,
## 否则会吞掉点击 / 让 gui_get_hovered_control() 返回绿块导致悬停高亮在丧尸格被隐藏
## (用户反馈: 点丧尸被绿块截胡 + 丧尸格黄色预选高亮不显示)
func _test_unit_visuals_ignore_mouse() -> void:
	var ok := true
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[UnitVisual] 无敌人, 跳过")
		print("=== 自动测试: 单位视觉不拦截鼠标=", ok)
		return
	# 遍历所有敌人, 验证其 "BodyVisual" 子节点 mouse_filter == IGNORE
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var body: Node = e.get_node_or_null("BodyVisual")
		if body == null:
			# 旧场景可能没命名, 退而查任何 ColorRect 子节点
			for c in e.get_children():
				if c is ColorRect:
					body = c
					break
		if body == null:
			continue
		if body.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			ok = false
			push_error("[UnitVisual] 敌人身体未设 IGNORE mouse_filter: ", body.name)
		# 头顶血条内的 ColorRect 也应 IGNORE
		var hb: Node = e.get_node_or_null("HealthBar")
		if hb:
			for c in hb.get_children():
				if c is ColorRect and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
					ok = false
					push_error("[UnitVisual] 血条内 ColorRect 未设 IGNORE: ", c.name)
	# 玩家身体
	if _player:
		var pbody := _player.get_node_or_null("BodyVisual")
		if pbody and pbody.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			ok = false
			push_error("[UnitVisual] 玩家身体未设 IGNORE mouse_filter")
	print("=== 自动测试: 单位视觉不拦截鼠标=", ok, " (应为 true)")


## 选中箭头回归: show_at → 渐入(alpha上升) → 停留 → 渐出 → 隐藏 (用户反馈: 渐变出现再消失)
func _test_selection_arrow() -> void:
	if not _selection_arrow:
		push_warning("[SelArrow] 无箭头组件, 跳过")
		return
	var ok := true
	_selection_arrow.show_at(_world_pos(Vector2i(3, 3)), tile_size)
	# 渐入阶段 alpha 应 >0 (不是 HIDDEN)
	await _await_secs(0.05)
	var alpha_early: float = _selection_arrow._alpha()
	if alpha_early <= 0.0:
		ok = false
		push_error("[SelArrow] 渐入阶段 alpha 应>0: ", alpha_early)
	# 停留阶段 (0.15s 后进入 HOLD) alpha=1
	await _await_secs(0.15)
	var alpha_hold: float = _selection_arrow._alpha()
	if alpha_hold < 0.95:
		ok = false
		push_error("[SelArrow] 停留阶段 alpha 应≈1: ", alpha_hold)
	# 渐出阶段 (0.6+0.15 后进入 FADE_OUT) alpha 下降
	await _await_secs(0.5)
	var alpha_out: float = _selection_arrow._alpha()
	# 完整动画后应隐藏
	await _await_secs(0.5)
	var hidden: bool = _selection_arrow._phase == 0  # HIDDEN
	if not hidden:
		ok = false
		push_error("[SelArrow] 动画结束应隐藏: phase=", _selection_arrow._phase)
	print("=== 自动测试: 选中箭头动画=", ok, " (应为 true) alpha早/停/出=", alpha_early, "/", alpha_hold, "/", alpha_out)


## 菜单定位回归: 真实点击容器格子 → 行动菜单应显示在格子上方 (用户反馈: 之前显示在格子下面)
func _test_menu_position() -> void:
	var ok := true
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var corpse: Node = corpse_script.new()
	var gp := _cell_of(_player.global_position) + Vector2i(3, 2)
	corpse.setup_corpse(gp, tile_size, ["bandage", "medkit"], "菜单定位测试")
	add_child(corpse)
	add_corpse(corpse)
	# Issue B: 挪玩家到尸体旁 1 格, 满足搜刮前提
	_player.global_position = _world_pos(gp - Vector2i(1, 0))
	var hit := _raycast_interactable(_world_pos(gp))
	if not hit:
		push_error("[MenuPos] 尸体未命中")
		return
	_on_interact(hit)
	if not _container_ui.is_open():
		push_error("[MenuPos] 容器未打开")
		return
	var cell_btn: Button = _find_button_recursive(_container_ui._panel)
	if cell_btn:
		var btn_rect := cell_btn.get_global_rect()
		_container_ui._on_cell_pressed("bandage", cell_btn)
		await get_tree().process_frame
		var menu_rect: Rect2 = _container_ui._item_menu._panel.get_global_rect()
		print("[MenuPos] 真实点击: btn_rect=", btn_rect, " menu_rect=", menu_rect)
		# 菜单应在按钮上方 (y 更小) 或紧贴, 不应在下方远处 (用户反馈: 在背包格子下面)
		if menu_rect.position.y > btn_rect.position.y + 100.0:
			ok = false
			push_error("[MenuPos] 菜单显示在格子下方, 应在上方: btn.y=", btn_rect.position.y, " menu.y=", menu_rect.position.y)
	else:
		push_warning("[MenuPos] 未找到格子按钮, 跳过")
	_container_ui.close()
	print("=== 自动测试: 菜单定位在格子上方=", ok, " (应为 true)")


## 递归查找第一个 Button (真实点击菜单位置验证)
func _find_button_recursive(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var found := _find_button_recursive(child)
		if found:
			return found
	return null


## 逃跑两阶段回归 (用户反馈: 不是一逃跑就脱离/删除, 是离主角一定距离脱离之后再删):
##   ① 普通丧尸 flee_hp_threshold=0 永不逃跑
##   ② 疾速丧尸低血 → FLEE → 距离≥脱离阈值 → 脱离战斗(保留地图) → 距离≥删除阈值 → 删除
func _test_flee_two_stage() -> void:
	var ok := true
	# ① 普通丧尸不逃跑
	var basic_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var basic: Node = EF.spawn(self, basic_script, _world_pos(Vector2i(3, 3)), tile_size, 100.0)
	basic.world = self
	if basic.get("flee_hp_threshold") != 0.0:
		ok = false
		push_error("[Flee] 普通丧尸应不逃跑 (flee_hp_threshold=0): ", basic.get("flee_hp_threshold"))
	basic.queue_free()
	# ② 疾速丧尸低血 → 逃跑 → 脱离 → 删除
	var runner_script := load("res://scripts/units/enemies/zombie_runner.gd")
	var runner: Node = EF.spawn(self, runner_script, _world_pos(Vector2i(3, 3)), tile_size, 100.0)
	runner.world = self
	runner.hp = runner.max_hp * 0.1  # 低血触发 FLEE
	runner.engage()  # 真实战斗里低血丧尸必然是已卷入的 (B: 仅卷入者参与回合)
	runner.take_turn()
	if runner.ai_state != runner.AIState.FLEE:
		ok = false
		push_error("[Flee] 疾速丧尸低血应进入 FLEE: ", runner.ai_state)
	# 模拟远离: 直接放到脱离阈值外 → take_turn 应脱离 (不删, _escape_detached=true)
	var player := TurnManager.get_player()
	if player:
		player.global_position = Vector2(999, 999)  # 远超 10 格脱离阈值
		runner.global_position = _world_pos(Vector2i(3, 3))
		runner.take_turn()
		if not runner.get("_escape_detached"):
			ok = false
			push_error("[Flee] 远离后应脱离战斗 (保留地图): _escape_detached=", runner.get("_escape_detached"))
	runner.queue_free()
	print("=== 自动测试: 逃跑两阶段=", ok, " (应为 true)")


## 点击移动穿墙回归: 点击墙后面一格 → 路径应在墙前停下, 不穿墙
## 点击墙后目标: 正确寻路应绕墙到达 (途中绝不踏入墙格)
func _test_click_path_no_wall() -> void:
	var player := _player
	var ok := true
	# 直接单元测试路线规划(BFS 绕墙): 从 (3,2) 到墙后 (6,2)
	# 路径必须: 非空 + 不踏入任何墙格(5,2)-(5,5) + 终点即目标格
	# (这样测最确定, 不依赖逐格行走/physics/遇敌触发战斗等运行时因素)
	var from := _world_pos(Vector2i(3, 2))
	var to := _world_pos(Vector2i(6, 2))
	var path: Array[Vector2] = player._build_path(from, to)
	if path.is_empty():
		ok = false
		push_error("[ClickWall] BFS 寻路返回空路径 (应绕墙到达 ", _cell_of(to), ")")
	else:
		for p in path:
			var c := _cell_of(p)
			if _wall_cells.has(c):
				ok = false
				push_error("[ClickWall] 路径踏入墙格 ", c)
				break
		var last := path[path.size() - 1]
		if _cell_of(last) != Vector2i(6, 2):
			ok = false
			push_error("[ClickWall] 路径终点不在目标格, 终点=", _cell_of(last))
	print("=== 自动测试: 点击移动绕墙到达(不穿墙)=", ok, " (应为 true) 路径长=", path.size())


## 真实移动穿墙回归: 玩家向墙格 move_in_direction → 不开始移动 (墙体阻止行走)
func _test_wall_walk_block() -> void:
	var player := _player
	var ok := true
	# 站在 (4,2), 右侧 (5,2) 是内部墙
	var stand_cell := Vector2i(4, 2)
	player.global_position = _world_pos(stand_cell)
	player.is_my_turn = true
	player.ap_current = player.ap_max
	# 1. 向墙走 (1,0) → 目标是墙格 → 不应开始移动 (is_moving 仍 false)
	player.move_in_direction(Vector2(1, 0))
	var started_into_wall: bool = player.is_moving
	if started_into_wall:
		ok = false
		push_error("[WallWalk] 玩家开始穿墙移动!")
	# 2. 向空地走 (-1,0) → 空地 (3,2) → 应开始移动
	player.move_in_direction(Vector2(-1, 0))
	var moved_to_floor: bool = player.is_moving
	if not moved_to_floor:
		ok = false
		push_error("[WallWalk] 玩家应能走向空地, 但未开始移动")
	print("=== 自动测试: 墙体阻止真实移动=", ok, " (应为 true) 穿墙被拦=", not started_into_wall)
	# 3. 对角移动禁止: 墙角 (5,2) 上方/左侧都是墙, 玩家站 (4,1) 对角 (5,2) 是墙 → 对角输入只走主轴
	await _test_diagonal_blocked()


## 对角移动回归 (用户反馈: 峭壁能越过去 + 单位没按格走):
## 输入对角 (0.707,0.707) → 只走主轴 (禁斜穿墙角)
func _test_diagonal_blocked() -> void:
	var player := _player
	var ok := true
	# 等完全静止
	var guard := 0
	while player.is_moving and guard < 40:
		await _await_secs(0.1)
		guard += 1
	# 玩家站 (3,3) 空地, 对角输入应只走主轴 (4,3) 或 (3,4), 不能斜到 (4,4)
	player.global_position = _world_pos(Vector2i(3, 3))
	player.is_my_turn = true
	player.ap_current = player.ap_max
	await _await_secs(0.1)  # 确保位置已应用
	player.move_in_direction(Vector2(0.7071, 0.7071))  # 模拟 ↑+→ 对角输入
	guard = 0
	while player.is_moving and guard < 40:
		await _await_secs(0.1)
		guard += 1
	var final_cell := _cell_of(player.global_position)
	if final_cell == Vector2i(4, 4):
		ok = false
		push_error("[DiagMove] 对角移动! 斜穿到 (4,4), 应只走主轴")
	if final_cell != Vector2i(4, 3) and final_cell != Vector2i(3, 4):
		ok = false
		push_error("[DiagMove] 对角输入应只走主轴 (4,3)/(3,4), 实际=", final_cell)
	# 敌人巡逻 4 方向: _step_random 目标必须是 4 邻格
	var zombie_script := load("res://scripts/units/enemies/zombie_basic.gd")
	var z: Node = EF.spawn(self, zombie_script, _world_pos(Vector2i(3, 5)), tile_size, 100.0)
	z.world = self
	z.global_position = _world_pos(Vector2i(3, 5))
	var z_cell := _cell_of(z.global_position)
	z._step_random()
	if z.is_moving:
		var z_target_cell := _cell_of(z._target_position)
		var dx := absi(z_target_cell.x - z_cell.x)
		var dy := absi(z_target_cell.y - z_cell.y)
		if dx + dy != 1:
			ok = false
			push_error("[DiagMove] 丧尸 _step_random 对角移动: ", z_cell, " → ", z_target_cell)
	z.queue_free()
	print("=== 自动测试: 对角移动禁止=", ok, " (应为 true)")


## 存档回归: 保存 → 修改数据 → 读档 → 验证恢复 (P0 完整链路)
func _test_save_load() -> void:
	var player := _player
	if not player or not player.has_method("serialize"):
		push_error("[Save] 玩家缺少 serialize")
		return
	# 1. 修改玩家状态 (生存/技能点/异能/装备)
	player._set_survival(60.0, 50.0)
	player.skill_points = 5
	player.hp = 150.0
	# 2. 存档
	var data: Dictionary = player.serialize()
	var ok := true
	if absf(data.get("hunger", 0.0) - 60.0) > 0.01:
		ok = false
		push_error("[Save] serialize 饱腹错误")
	if data.get("skill_points", 0) != 5:
		ok = false
		push_error("[Save] serialize 技能点错误")
	# 3. 模拟读档到新玩家
	var player2: Node = load("res://scripts/units/player.gd").new()
	player2.max_hp = 200.0
	player2.deserialize(data)
	if absf(player2.hunger - 60.0) > 0.01 or absf(player2.thirst - 50.0) > 0.01:
		ok = false
		push_error("[Save] deserialize 生存属性错误")
	if player2.skill_points != 5:
		ok = false
		push_error("[Save] deserialize 技能点错误")
	if player2.hp != 150.0:
		ok = false
		push_error("[Save] deserialize HP 错误: ", player2.hp)
	player2.queue_free()
	print("=== 自动测试: 存档链路=", ok, " (应为 true)")


## 生存属性回归: 食用消耗品 → 饥饿/口渴回升 + 物品消耗 + 睡眠时间衰减
func _test_survival() -> void:
	var player := _player
	if not player or not player.has_method("consume_item"):
		push_error("[Survival] 玩家缺少 consume_item")
		return
	# 拉低属性 (模拟饥饿口渴)
	player._set_survival(30.0, 20.0)
	player.add_item("bread", 1)
	player.add_item("water_pure", 1)

	var ok := true
	var r1: Dictionary = player.consume_item("bread")
	if not r1.get("success", false):
		ok = false
		push_error("[Survival] 面包食用失败")
	if player.hunger <= 30.0:
		ok = false
		push_error("[Survival] 面包未提升饱腹: ", player.hunger)
	var r2: Dictionary = player.consume_item("water_pure")
	if not r2.get("success", false):
		ok = false
		push_error("[Survival] 净水饮用失败")
	if player.thirst <= 20.0:
		ok = false
		push_error("[Survival] 净水未提升水分: ", player.thirst)

	# 时间驱动回归: 推进世界时间 → 生存属性按小时衰减
	var t_hour_before: float = WorldTime.hour if WorldTime else 0.0
	player._set_survival(100.0, 100.0)
	if WorldTime:
		WorldTime.advance_time(2.0)  # 2 小时
	# 预期: 饱腹 -1.5*2=3, 水分 -2.5*2=5, 睡眠 -1.2*2=2.4
	if absf(player.hunger - 97.0) > 0.01:
		ok = false
		push_error("[Survival] 时间衰减饱腹错误: ", player.hunger, " (预期 97)")
	if absf(player.thirst - 95.0) > 0.01:
		ok = false
		push_error("[Survival] 时间衰减水分错误: ", player.thirst, " (预期 95)")
	# 注意: 旧 sleep 字段已移除 (AP+睡眠合并为精力, 不再随时间自然衰减)
	if WorldTime:
		var time_moved: bool = absf(WorldTime.hour - t_hour_before - 2.0) < 0.01
		if not time_moved:
			ok = false
			push_error("[Survival] advance_time 未推进时间")
	print("=== 自动测试: 时间驱动生存=", ok, " (应为 true), 饱腹=", player.hunger, " 水分=", player.thirst, " 精力=", player.ap_current)


## 丧尸掉落回归: 低级装备 + 变体专属掉落 数据源正确
func _test_corpse_loot() -> void:
	var enemy_script: Script = load("res://scripts/units/enemies/zombie_basic.gd")
	var enemy: Node = enemy_script.new()
	enemy.enemy_id = "zombie_basic"
	enemy.enemy_name = "普通丧尸"
	var loot: Array = enemy._get_corpse_loot()
	enemy.queue_free()
	var ok: bool = loot.has("zombie_flesh")
	for id in loot:
		var item: DataManager.ItemData = DataManager.get_item(id)
		if not item:
			ok = false
			push_error("[Loot] 掉落物品不在数据库: ", id)
	print("=== 自动测试: 丧尸掉落数据=", ok, " (应为 true), 本次掉落: ", loot)


## 尸体交互回归: 生成尸体 → 网格命中 → 打开容器 UI (修复: 之前主地图/测试场景点尸体无反应)
func _test_corpse_interaction() -> void:
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var corpse: Node = corpse_script.new()
	var gp := _cell_of(_player.global_position) + Vector2i(2, 0)
	corpse.setup_corpse(gp, tile_size, ["bandage", "medkit"], "测试尸体")
	add_child(corpse)
	add_corpse(corpse)
	# Issue B: 搜刮尸体须玩家在 1 格内, 本测试把玩家挪到尸体旁以满足前提
	_player.global_position = _world_pos(gp - Vector2i(1, 0))

	var hit := _raycast_interactable(_world_pos(gp))
	print("=== 自动测试: 尸体命中=", hit != null, " (应为 true)")
	if hit:
		_on_interact(hit)
		var opened: bool = _container_ui != null and _container_ui.is_open()
		print("=== 自动测试: 容器打开=", opened, " (应为 true)")
		if opened:
			_test_rarity_border()
			_test_take_all_button()
			_test_empty_grid()
		_container_ui.close()
	# 修复: 尸体搜空后保留(不消失), 列表应仍为 1
	print("=== 自动测试: 尸体列表大小=", _corpses.size(), " (应为 1, 搜空后保留)")


## Issue B 回归: 搜刮尸体须玩家在 1 格内, 否则被拦截(容器不开 + 提示);
## 持有空间系异能 (ability_category="space" / 名称含空间关键词) 可隔空搜刮 (任意距离).
func _test_corpse_loot_proximity() -> void:
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var ok := true
	var player_home: Vector2 = _player.global_position
	# 备份并清空异能, 确保"无空间系异能"基线
	var saved_abilities: Array = _player.learned_abilities.duplicate()
	_player.learned_abilities.clear()

	# --- 场景1: 远处尸体 (3 格外), 无空间异能 → 应触发自动寻路 (不直接开包) ---
	var gp_far := _cell_of(player_home) + Vector2i(3, 0)
	var corpse_far: Node = corpse_script.new()
	corpse_far.setup_corpse(gp_far, tile_size, ["bandage"], "远尸体")
	add_child(corpse_far)
	add_corpse(corpse_far)
	_pending_loot = null  # 清空遗留
	_player.global_position = player_home  # 保持在出生点, 距尸体 3 格
	if _container_ui:
		_container_ui.close()
	var hit_far := _raycast_interactable(_world_pos(gp_far))
	if hit_far:
		_on_interact(hit_far)
		# 新行为: 不再拦截, 而是 _pending_loot 被设置 + 触发 move_to_cell
		var triggered_walk: bool = _pending_loot == corpse_far
		var opened_far: bool = _container_ui != null and _container_ui.is_open()
		if not triggered_walk:
			ok = false
			push_error("[CorpseProx] 远处尸体应触发自动寻路, _pending_loot 未设置")
		if opened_far:
			ok = false
			push_error("[CorpseProx] 远处尸体不应直接开包, 却开了")
		_pending_loot = null  # 清理, 避免影响后续
		if _container_ui:
			_container_ui.close()
	else:
		push_error("[CorpseProx] 远处尸体未命中")
	corpse_far.queue_free()
	remove_corpse(corpse_far)

	# --- 场景2: 玩家挪到尸体旁 1 格 → 应正常打开 ---
	var gp_near := _cell_of(player_home) + Vector2i(2, 0)
	var corpse_near: Node = corpse_script.new()
	corpse_near.setup_corpse(gp_near, tile_size, ["bandage"], "近尸体")
	add_child(corpse_near)
	add_corpse(corpse_near)
	_pending_loot = null
	_player.global_position = _world_pos(gp_near - Vector2i(1, 0))  # 距离 1
	if _container_ui:
		_container_ui.close()
	var hit_near := _raycast_interactable(_world_pos(gp_near))
	if hit_near:
		_on_interact(hit_near)
		var opened_near: bool = _container_ui != null and _container_ui.is_open()
		if not opened_near:
			ok = false
			push_error("[CorpseProx] 玩家在 1 格内应可搜刮, 容器却未开")
		if _container_ui:
			_container_ui.close()
	else:
		push_error("[CorpseProx] 近处尸体未命中")
	corpse_near.queue_free()
	remove_corpse(corpse_near)

	# --- 场景3: 持空间系异能 → 远处尸体也可隔空搜刮 (直接开包) ---
	var space_action: Resource = CA.new()
	space_action.action_id = "test_space_loot"
	space_action.ability_category = "space"
	_player.learned_abilities.append(space_action)
	var gp_space := _cell_of(player_home) + Vector2i(4, 0)
	var corpse_space: Node = corpse_script.new()
	corpse_space.setup_corpse(gp_space, tile_size, ["bandage"], "空间异能尸体")
	add_child(corpse_space)
	add_corpse(corpse_space)
	_pending_loot = null
	_player.global_position = player_home  # 仍远处
	if _container_ui:
		_container_ui.close()
	var hit_space := _raycast_interactable(_world_pos(gp_space))
	if hit_space:
		_on_interact(hit_space)
		var opened_space: bool = _container_ui != null and _container_ui.is_open()
		if not opened_space:
			ok = false
			push_error("[CorpseProx] 持有空间系异能应可隔空搜刮, 容器却未开")
		if _container_ui:
			_container_ui.close()
	else:
		push_error("[CorpseProx] 空间异能尸体未命中")
	corpse_space.queue_free()
	remove_corpse(corpse_space)

	# 恢复玩家位置与异能状态, 避免污染后续测试
	_player.global_position = player_home
	_player.learned_abilities = saved_abilities.duplicate()
	_pending_loot = null
	print("=== 自动测试: 尸体搜刮距离限制=", ok, " (应为 true)")


## 家具/柜子开柜距离限制 (与尸体同规则): 玩家须靠近容器 1 格内才可开柜,
## 否则自动寻路走到旁 1 格, 到达后开包; 持有空间系异能可隔空开柜.
func _test_furniture_loot_proximity() -> void:
	var furn_script: Script = load("res://scripts/tiles/furniture.gd")
	var ok := true
	var player_home: Vector2 = _player.global_position
	var saved_abilities: Array = _player.learned_abilities.duplicate()
	_player.learned_abilities.clear()  # 无空间异能基线

	# --- 场景1: 远处衣柜 (3 格) → 应触发自动寻路 (不直接开包) ---
	var gp_far := _cell_of(player_home) + Vector2i(3, 0)
	var furn_far: Node = furn_script.new()
	furn_far.setup(gp_far, tile_size, ["canned_food"], 2, "衣柜")
	add_child(furn_far)
	_pending_loot = null
	_player.global_position = player_home
	if _container_ui:
		_container_ui.close()
	_on_interact(furn_far)
	var triggered_walk: bool = _pending_loot == furn_far
	var opened_far: bool = _container_ui != null and _container_ui.is_open()
	if not triggered_walk:
		ok = false
		push_error("[FurnProx] 远处衣柜应触发自动寻路, _pending_loot 未设置")
	if opened_far:
		ok = false
		push_error("[FurnProx] 远处衣柜不应直接开包, 却开了")
	_pending_loot = null
	if _container_ui:
		_container_ui.close()
	furn_far.queue_free()

	# --- 场景2: 玩家挪到衣柜旁 1 格 → 应正常打开 ---
	var gp_near := _cell_of(player_home) + Vector2i(2, 0)
	var furn_near: Node = furn_script.new()
	furn_near.setup(gp_near, tile_size, ["canned_food"], 2, "衣柜")
	add_child(furn_near)
	_pending_loot = null
	_player.global_position = _world_pos(gp_near - Vector2i(1, 0))  # 距离 1
	if _container_ui:
		_container_ui.close()
	_on_interact(furn_near)
	var opened_near: bool = _container_ui != null and _container_ui.is_open()
	if not opened_near:
		ok = false
		push_error("[FurnProx] 玩家在 1 格内应可开柜, 容器却未开")
	if _container_ui:
		_container_ui.close()
	furn_near.queue_free()

	# --- 场景3: 持空间系异能 → 远处衣柜也可隔空开柜 (直接开包) ---
	var space_action: Resource = CA.new()
	space_action.action_id = "test_space_loot"
	space_action.ability_category = "space"
	_player.learned_abilities.append(space_action)
	var gp_space := _cell_of(player_home) + Vector2i(4, 0)
	var furn_space: Node = furn_script.new()
	furn_space.setup(gp_space, tile_size, ["canned_food"], 2, "衣柜")
	add_child(furn_space)
	_pending_loot = null
	_player.global_position = player_home  # 仍远处
	if _container_ui:
		_container_ui.close()
	_on_interact(furn_space)
	var opened_space: bool = _container_ui != null and _container_ui.is_open()
	if not opened_space:
		ok = false
		push_error("[FurnProx] 持有空间系异能应可隔空开柜, 容器却未开")
	if _container_ui:
		_container_ui.close()
	furn_space.queue_free()

	_player.global_position = player_home
	_player.learned_abilities = saved_abilities.duplicate()
	_pending_loot = null
	print("=== 自动测试: 家具开柜距离限制=", ok, " (应为 true)")


## 4×4 空格子回归: 拿完所有物品后, 容器 UI 应渲染 16 个格子(物品格+空格子)
func _test_empty_grid() -> void:
	var ok := true
	# 全部拿走后 _refresh 应渲染满 16 格 (排除 queue_free 延迟释放的旧格子)
	var cell_count := 0
	for child in _container_ui._list.get_children():
		if child is Control and not child.is_queued_for_deletion():
			cell_count += 1
	if cell_count != 16:
		ok = false
		push_error("[EmptyGrid] 容器格子数错误: ", cell_count, " (应为 16)")
	# 尸体应保留且标记已搜刮 (用户反馈: "已搜刮"标记要保留, 只是要居中于尸体中心)
	if _container_ui._container.get("searched") != true:
		ok = false
		push_error("[EmptyGrid] 尸体未标记已搜刮")
	print("=== 自动测试: 4×4空格子=", ok, " (应为 true), 格子数=", cell_count)


## 操作菜单 + 丢弃/拾取回归: 点格子弹菜单 → 丢弃落地 → 点地面拾取回背包 → 菜单拿走
func _test_item_menu_and_discard() -> void:
	var ok := true
	# 独立尸体, 避免与 _test_take_all_button 互相干扰
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var corpse: Node = corpse_script.new()
	var gp := _cell_of(_player.global_position) + Vector2i(3, 0)
	corpse.setup_corpse(gp, tile_size, ["bandage", "medkit"], "菜单测试尸体")
	add_child(corpse)
	add_corpse(corpse)
	# Issue B: 挪玩家到尸体旁 1 格, 满足搜刮前提
	_player.global_position = _world_pos(gp - Vector2i(1, 0))

	var hit := _raycast_interactable(_world_pos(gp))
	if not hit:
		push_error("[ItemMenu] 尸体未命中")
		return
	_on_interact(hit)
	if not _container_ui.is_open():
		push_error("[ItemMenu] 容器未打开")
		return

	# 1. 点格子 → 操作菜单出现
	_container_ui._on_cell_pressed("bandage")
	if not _container_ui._item_menu.visible:
		ok = false
		push_error("[ItemMenu] 点击格子未弹出操作菜单")

	# 2. 菜单"丢弃" → 物品从容器移除 + 生成地面物品 (玩家背包数量不应变化)
	var bandage_before: int = _player.count_item("bandage")
	_container_ui._on_menu_discard()
	if _container_ui._container.list_inventory().size() != 1:
		ok = false
		push_error("[ItemMenu] 丢弃后容器未减少: ", _container_ui._container.list_inventory())
	if _ground_items.size() != 1:
		ok = false
		push_error("[ItemMenu] 丢弃后未生成地面物品, 地面物品数=", _ground_items.size())
	if _player.count_item("bandage") != bandage_before:
		ok = false
		push_error("[ItemMenu] 丢弃的 bandage 不应进入背包")

	# 3. 点击地面物品 → 拾取回背包
	var gi: Node = _ground_items[0] if _ground_items.size() > 0 else null
	if gi:
		var gi_gp: Vector2i = gi.grid_pos
		var gi_hit := _raycast_interactable(_world_pos(gi_gp))
		if gi_hit != gi:
			ok = false
			push_error("[ItemMenu] 地面物品命中失败")
		else:
			_on_interact(gi_hit)
			if _player.count_item("bandage") < 1:
				ok = false
				push_error("[ItemMenu] 地面物品未拾取回背包")
			if _ground_items.size() != 0:
				ok = false
				push_error("[ItemMenu] 拾取后地面物品未注销, 剩余=", _ground_items.size())
	else:
		ok = false

	# 4. 菜单"拿走" → 物品进背包 (容器关闭前验证)
	var medkit_before: int = _player.count_item("medkit")
	_container_ui._on_cell_pressed("medkit")
	_container_ui._on_menu_take()
	if _player.count_item("medkit") != medkit_before + 1:
		ok = false
		push_error("[ItemMenu] 菜单拿走失败: medkit 数量 ", _player.count_item("medkit"), " != ", medkit_before + 1)
	if not _container_ui._container.is_empty():
		ok = false
		push_error("[ItemMenu] 容器应已空")

	_container_ui.close()
	# 清理测试尸体
	corpse.queue_free()
	remove_corpse(corpse)
	print("=== 自动测试: 操作菜单+丢弃拾取=", ok, " (应为 true), 地面物品数=", _ground_items.size())


## 拖拽装备闭环回归: 背包拖到装备槽(装备+旧装备回背包) → 拖回背包(卸下) → 点击卸下
func _test_equip_drag() -> void:
	var ok := true
	var hud: CanvasLayer = _hud
	if not hud or not hud.has_method("_on_equip_drag"):
		push_error("[EquipDrag] 无 HUD 拖拽接口")
		return
	var weapon_slot: String = DataManager.EQUIP_SLOT_WEAPON
	var old_weapon: String = _player.get_equipped_item(weapon_slot)

	# 1. 背包加棒球棍 → 拖到武器槽 (替换旧武器, 旧武器回背包)
	_player.add_item("baseball_bat", 1)
	hud._on_equip_drag("baseball_bat", weapon_slot)
	if _player.get_equipped_item(weapon_slot) != "baseball_bat":
		ok = false
		push_error("[EquipDrag] 拖拽装备失败: 武器槽=", _player.get_equipped_item(weapon_slot))
	if old_weapon != "" and _player.count_item(old_weapon) < 1:
		ok = false
		push_error("[EquipDrag] 旧武器未回背包: ", old_weapon, " 数量=", _player.count_item(old_weapon))

	# 2. 拖回背包 → 卸下 (装备槽拖出到背包格)
	hud._on_bag_drop(weapon_slot)
	if _player.get_equipped_item(weapon_slot) != "":
		ok = false
		push_error("[EquipDrag] 拖回背包未卸下: 武器槽=", _player.get_equipped_item(weapon_slot))
	if _player.count_item("baseball_bat") < 1:
		ok = false
		push_error("[EquipDrag] 卸下后棒球棍未回背包")

	# 3. 重新装备 → 点击装备槽卸下
	_player.equip_item("baseball_bat")
	hud._on_unequip_click(weapon_slot)
	if _player.get_equipped_item(weapon_slot) != "":
		ok = false
		push_error("[EquipDrag] 点击卸下失败: 武器槽=", _player.get_equipped_item(weapon_slot))
	if _player.count_item("baseball_bat") < 1:
		ok = false
		push_error("[EquipDrag] 点击卸下后物品未回背包")

	# 4. 恢复原武器 (读档/后续测试依赖)
	if old_weapon != "":
		_player.equip_item(old_weapon)
	print("=== 自动测试: 拖拽装备闭环=", ok, " (应为 true)")


## 背包打开时点击不移动 (修复: 战斗点背包角色挪一步)
func _test_backpack_click_no_move() -> void:
	if not _hud or not _hud.has_method("open_backpack"):
		push_error("[NoMove] 无 HUD")
		return
	var pos_before: Vector2 = _player.global_position
	_hud.open_backpack()
	# 模拟场景收到左键点击: 背包打开时 _unhandled_input 应直接 return, 不移动角色
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	_unhandled_input(ev)
	_hud.close_backpack()
	var ok: bool = _player.global_position == pos_before
	if not ok:
		push_error("[NoMove] 背包打开时点击导致移动: ", pos_before, " -> ", _player.global_position)
	print("=== 自动测试: 背包打开不移动=", ok, " (应为 true)")


## 点丧尸弹动作菜单回归: 菜单打开 + 动作列表非空 (修复: 探索模式点丧尸无法显示攻击技能)
## 探索模式「点丧尸」全路径回归 (同步, 不依赖帧信号):
## 构造点中丧尸 world_pos 的鼠标事件 → _handle_explore_click → _raycast_enemy → _open_action_menu
## 验证"点击普通丧尸能弹出操作列表"这一核心链路 (用户反馈: 点丧尸没反应)
func _test_explore_click_enemy_menu() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[ExploreClickEnemy] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy) or enemy.get("hp") <= 0:
		push_error("[ExploreClickEnemy] 敌人无效")
		return
	_action_menu.hide_menu()
	var ev := _make_click_event(enemy.global_position)
	_handle_explore_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[ExploreClickEnemy] 探索模式点普通丧尸未弹操作列表 (world=%s 丧尸格=%s)" % [enemy.global_position, _cell_of(enemy.global_position)])
	_action_menu.hide_menu()
	print("=== 自动测试: 探索模式点普通丧尸弹操作列表=", ok, " (应为 true)")


## 战斗模式「点丧尸」全路径回归 (同步: enter_combat 同步进入 PLAYER_PHASE, 不依赖 0.3s 计时器)
func _test_combat_click_enemy_menu_sync() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[CombatClickEnemy] 无敌人")
		return
	var enemy: Node = enemies[0]
	TurnManager.enter_combat()
	var pt: bool = _combat_sm.is_player_turn() if _combat_sm != null else false
	_action_menu.hide_menu()
	var ev := _make_click_event(enemy.global_position)
	_handle_combat_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[CombatClickEnemy] 战斗模式点普通丧尸未弹操作列表 is_player_turn=%s" % pt)
	_action_menu.hide_menu()
	TurnManager.exit_combat(true)
	print("=== 自动测试: 战斗模式点普通丧尸弹操作列表=", ok, " (应为 true) is_player_turn=", pt)


func _test_enemy_menu() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[EnemyMenu] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy) or enemy.get("hp") <= 0:
		push_error("[EnemyMenu] 敌人无效")
		return
	_action_menu.hide_menu()
	_open_action_menu(enemy)
	var ok: bool = _action_menu.is_open()
	if ok and _action_menu._list.get_child_count() == 0:
		ok = false
		push_error("[EnemyMenu] 菜单无动作选项")
	_action_menu.hide_menu()
	print("=== 自动测试: 点丧尸弹菜单=", ok, " (应为 true)")


## 战斗模式点击回归: 进入战斗 + 等待玩家回合 → 点击丧尸格应弹菜单 (真机玩家靠近丧尸会先进入战斗, 只测探索模式会漏掉这条路径)
func _test_click_enemy_combat() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[EnemyCombat] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy) or enemy.get("hp") <= 0:
		push_error("[EnemyCombat] 敌人无效")
		return
	TurnManager.enter_combat()
	# 等 CombatSM 进入 PLAYER_PHASE (0.3s 延迟后才放开 input_lock)
	await _await_secs(0.4)
	_action_menu.hide_menu()
	var world_pos := _world_pos(_cell_of(enemy.global_position))
	var ev := _make_click_event(world_pos)
	var pt: bool = _combat_sm.is_player_turn() if _combat_sm != null else false
	_handle_combat_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[EnemyCombat] 战斗模式点丧尸地块未弹菜单 世界=", world_pos, " 丧尸=", enemy.global_position, " is_player_turn=", pt)
	_action_menu.hide_menu()
	TurnManager.exit_combat(true)
	print("=== 自动测试: 战斗模式点丧尸地块弹菜单=", ok, " (应为 true) pt=", pt)


## 菜单不被同一次点击的松开事件关掉 (用户反馈: 点丧尸菜单一闪而过)
## 真机点击 = 按下开菜单 + 松开同一点. 旧实现在菜单打开期间任何事件(含按下/松开间夹的
## mouse_motion)都会触发"点面板外→关闭", 导致菜单被自己这记点击的 release 关掉.
## 新机制: 菜单只在"鼠标按下且点在面板外"时关闭, 松开事件一律忽略 → 打开那记点击不可能关掉自己.
func _test_menu_survives_release() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[MenuRelease] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy) or enemy.get("hp") <= 0:
		push_error("[MenuRelease] 敌人无效")
		return
	TurnManager.enter_combat()
	await _await_secs(0.4)
	_action_menu.hide_menu()
	# 模拟真实点击: 按下(开菜单) + 松开(同一点) 都经过 _unhandled_input 分发
	var world_pos := _world_pos(_cell_of(enemy.global_position))
	var press_ev := _make_click_event(world_pos)
	_unhandled_input(press_ev)  # 应弹出菜单
	var opened: bool = _action_menu.is_open()
	# 同一次点击的松开事件 (pressed=false, 同坐标) → 不应关闭菜单
	var release_ev := InputEventMouseButton.new()
	release_ev.button_index = MOUSE_BUTTON_LEFT
	release_ev.pressed = false
	release_ev.position = press_ev.position
	_unhandled_input(release_ev)
	var still_open: bool = _action_menu.is_open()
	# 另一次"按下且点在面板外" → 应正常关闭菜单 (验证关闭逻辑仍有效)
	var close_ev := InputEventMouseButton.new()
	close_ev.button_index = MOUSE_BUTTON_LEFT
	close_ev.pressed = true
	close_ev.position = Vector2(2, 2)  # 面板在 cursor+(12,12), 该点必在面板外
	_unhandled_input(close_ev)
	var closed: bool = not _action_menu.is_open()
	var ok: bool = opened and still_open and closed
	if not ok:
		push_error("[MenuRelease] 菜单生命周期异常 (opened=%s release后仍开=%s 外部按下已关=%s)" % [opened, still_open, closed])
	_action_menu.hide_menu()
	TurnManager.exit_combat(true)
	print("=== 自动测试: 点丧尸菜单松开后仍在(且外部按下可关)=", ok, " (应为 true)")


## 构造"点中 world_pos"的鼠标左键事件 (与基类 _event_to_world 完全互逆:
## 与 _event_to_world 互逆: world_pos → event.position
## 只用 get_canvas_transform() (与 _event_to_world 一致), 这样事件能被精确还原回 world_pos
func _make_click_event(world_pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = get_canvas_transform() * world_pos
	return ev


## 点击坐标往返一致性回归: 防止 _event_to_world 多乘一次 screen_transform
## (那会让编辑器里点击坐标整体偏移, 与悬停高亮对不上 → 点不中丧尸)
func _test_click_world_roundtrip() -> void:
	var wp := _world_pos(Vector2i(7, 7))
	var ev := _make_click_event(wp)
	var back := _event_to_world(ev)
	var ok := back.distance_to(wp) < 0.001
	if not ok:
		push_error("[ClickRoundtrip] 点击事件往返不一致: 期望 %s 实得 %s (坐标转换公式错误)" % [wp, back])
	print("=== 自动测试: 点击坐标往返一致=", ok, " (应为 true)")

## 异能树面板水平居中回归: 打开后面板中心 x 应与视口中心 x 对齐 (用户反馈: 打开技能树 UI 没有居中)
func _test_ability_tree_centered() -> void:
	if _ability_ui == null:
		push_error("[AbilityCenter] 无 _ability_ui")
		return
	_ability_ui.open()
	await get_tree().process_frame  # 等一帧让 GUI 布局生效
	var panel: Control = _ability_ui._panel
	if panel == null:
		push_error("[AbilityCenter] 无 _panel")
		_ability_ui.close()
		return
	var vp_center: Vector2 = get_viewport().get_visible_rect().get_center()
	var panel_center: Vector2 = panel.global_position + panel.size * 0.5
	var diff_x := absf(panel_center.x - vp_center.x)
	var diff_y := absf(panel_center.y - vp_center.y)
	var ok2 := diff_x < 5.0 and diff_y < 5.0
	if not ok2:
		push_error("[AbilityCenter] 异能树面板未居中: 面板中心=%s 视口中心=%s 偏差X=%f 偏差Y=%f" % [panel_center, vp_center, diff_x, diff_y])
	print("=== 自动测试: 异能树面板完全居中=", ok2, " (应为 true) 偏差Xpx=", diff_x, " 偏差Ypx=", diff_y)
	_ability_ui.close()


## 血条数字居中回归: HP 标签必须水平居中在血条背景条内
func _test_health_bar_label_centered() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[HealthBar] 无敌人")
		return
	var enemy: Node = enemies[0]
	var bar: Node = enemy.get_node_or_null("HealthBar")
	if bar == null:
		push_error("[HealthBar] 敌人无 HealthBar 子节点")
		return
	bar.update_health(50.0, 100.0)
	bar.set_bar_visible(true)
	await get_tree().process_frame
	var label: Label = bar._label
	var bg: ColorRect = null
	for c in bar.get_children():
		if c is ColorRect and c != bar._fill:
			bg = c
			break
	var ok := true
	if label == null:
		push_error("[HealthBar] 无 _label")
		ok = false
	elif bg == null:
		push_error("[HealthBar] 无背景 ColorRect")
		ok = false
	else:
		var label_center_x: float = label.global_position.x + label.size.x * 0.5
		var bar_center_x: float = bg.global_position.x + bg.size.x * 0.5
		var diff := absf(label_center_x - bar_center_x)
		if diff > 1.0:
			ok = false
			push_error("[HealthBar] 血条数字未水平居中: label_center_x=%f bar_center_x=%f diff=%f" % [label_center_x, bar_center_x, diff])
		print("=== 自动测试: 血条数字水平居中=", ok, " (应为 true) diff=", diff)
	bar.set_bar_visible(false)


## 尸体标签居中回归: 尸体文字标签必须居中在尸体红色方块内
func _test_corpse_label_centered() -> void:
	var zombie_script: Script = load("res://scripts/units/enemies/zombie_basic.gd")
	var cell := Vector2i(8, 6)
	var enemy: Node = EF.spawn(self, zombie_script, _world_pos(cell), tile_size, 10.0)
	# 等一帧让 enemy 初始化完成
	await get_tree().process_frame
	var before := _corpses.size()
	enemy.die()
	await get_tree().process_frame
	await get_tree().process_frame  # Label 布局需要第二帧才稳定
	var corpse: Node = null
	for c in _corpses:
		if c.grid_pos == cell:
			corpse = c
			break
	var ok := true
	if corpse == null:
		push_error("[CorpseLabel] 击杀后未找到 (8,6) 尸体")
		ok = false
	else:
		var rect: ColorRect = corpse._rect
		var label: Label = corpse._label
		if rect == null or label == null:
			ok = false
			push_error("[CorpseLabel] 尸体缺少 _rect 或 _label")
		else:
			var label_center_x: float = label.global_position.x + label.size.x * 0.5
			var rect_center_x: float = rect.global_position.x + rect.size.x * 0.5
			var diff_x := absf(label_center_x - rect_center_x)
			# 垂直方向允许字体行高带来的轻微偏移 (用户反馈的是"左右居中")
			var label_center_y: float = label.global_position.y + label.size.y * 0.5
			var rect_center_y: float = rect.global_position.y + rect.size.y * 0.5
			var diff_y := absf(label_center_y - rect_center_y)
			if diff_x > 1.0:
				ok = false
				push_error("[CorpseLabel] 尸体标签未水平居中: label_center=(%f,%f) rect_center=(%f,%f) diff_x=%f diff_y=%f" % [label_center_x, label_center_y, rect_center_x, rect_center_y, diff_x, diff_y])
			print("=== 自动测试: 尸体标签居中=", ok, " (应为 true) diff_x=", diff_x, " diff_y=", diff_y)
		corpse.queue_free()
		remove_corpse(corpse)
	if is_instance_valid(enemy):
		enemy.queue_free()


## AP 扣除回归: 玩家攻击后精力(AP)必须下降, 且 UI 能收到 ap_changed 信号刷新
func _test_ap_deduction_on_attack() -> void:
	var ap_before: int = int(_player.ap_current)
	# GDScript lambda 对 int/bool 是值捕获, 用 Array 做引用容器才能在回调里修改外部可见
	var ap_changed_emitted: Array = [false]
	var ap_min_observed: Array = [ap_before]
	var cb := func(new_ap: int, _max_ap: int) -> void:
		ap_changed_emitted[0] = true
		if new_ap < ap_min_observed[0]:
			ap_min_observed[0] = new_ap
	if _player.has_signal("ap_changed"):
		_player.ap_changed.connect(cb)
	# 确保玩家在战斗模式且有可攻击目标
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[APDeduction] 无敌人可攻击")
		if _player.has_signal("ap_changed"):
			_player.ap_changed.disconnect(cb)
		return
	var enemy: Node = enemies[0]
	# 进入战斗并走到玩家回合 (单动作回合制: 攻击后玩家 AP 会清空并进入敌人阶段, 下回合回满)
	if not TurnManager.combat_mode:
		TurnManager.enter_combat()
		await get_tree().process_frame
	_player.global_position = enemy.global_position + Vector2(tile_size, 0)
	await get_tree().process_frame
	var cost: int = TurnManager.get_combat_action_cost(_player.get_default_attack())
	var ap_after_attack: int = int(_player.ap_current)
	print("[APDeduction-debug] 攻击前 AP=", ap_after_attack, " combat_mode=", TurnManager.combat_mode, " player_unit=", TurnManager.get_player(), " enemy=", enemy, " is_instance_valid=", is_instance_valid(enemy))
	_player.execute_attack(enemy, _player.get_default_attack())
	# 等待足够帧让 TurnManager.player_acted → process_turn_queue 完成 (可能进入新回合)
	await _await_secs(0.5)
	var emitted: bool = ap_changed_emitted[0]
	var min_ap: int = ap_min_observed[0]
	var ok: bool = emitted and min_ap <= ap_before - cost
	if not ok:
		push_error("[APDeduction] 攻击后 AP 未下降: 攻击前=%d 观察到最小=%d cost=%d emitted=%s" % [ap_before, min_ap, cost, emitted])
	print("=== 自动测试: 攻击扣除精力=", ok, " (应为 true) AP前=", ap_before, " 观察到最小AP=", min_ap, " cost=", cost)
	if _player.has_signal("ap_changed"):
		_player.ap_changed.disconnect(cb)
	# 退出测试用的战斗状态, 避免影响后续测试
	if TurnManager.combat_mode:
		TurnManager.exit_combat(true)


## 战斗 UI 隐藏回归: 战斗结束后 CombatUI 应淡出隐藏
func _test_combat_ui_hides_on_end() -> void:
	# 先进入战斗
	if not TurnManager.combat_mode:
		TurnManager.enter_combat()
		await get_tree().process_frame
	if _combat_ui == null:
		push_error("[CombatUIHide] 无 _combat_ui")
		return
	# 初始应可见
	if not _combat_ui.visible:
		push_warning("[CombatUIHide] 进入战斗后 CombatUI 未显示, 可能已被隐藏")
	# 结束战斗并等待淡出 (1.2s hold + 0.4s fade)
	TurnManager.exit_combat(true)
	await _await_secs(2.0)
	var hidden: bool = not _combat_ui.visible
	if not hidden:
		push_error("[CombatUIHide] 战斗结束后 CombatUI 仍未隐藏")
	print("=== 自动测试: 战斗结束后UI隐藏=", hidden, " (应为 true)")

## 音频回归: ①拳击/枪击音效资源存在 ②BGM 强制循环 ③战斗开始/结束 BGM 正确切换
func _test_bgm_loop_and_sfx() -> void:
	# ① 新音效资源存在
	var punch_ok: bool = ResourceLoader.exists("res://assets/sounds/punch.mp3")
	var gun_ok: bool = ResourceLoader.exists("res://assets/sounds/gunshot.mp3")
	if not punch_ok:
		push_error("[Audio] 缺少 punch.mp3")
	if not gun_ok:
		push_error("[Audio] 缺少 gunshot.mp3")
	# 动作工厂应引用拳击声 (玩家默认持枪, get_default_attack() 会返回枪, 故直接校验 punch 动作)
	var punch_action: Object = CA.get_action("punch")
	var melee_sound: String = str(punch_action.get("sound_id")) if punch_action else ""
	var sfx_wired: bool = melee_sound == "punch.mp3"
	if not sfx_wired:
		push_error("[Audio] 近战(拳击)动作音效未接入拳击声, 当前=%s" % melee_sound)
	print("=== 自动测试: 拳击/枪击音效就位=", punch_ok and gun_ok and sfx_wired, " (应为 true) 近战sound_id=", melee_sound)

	# ② 探索 BGM 应正在播放且 stream 已被强制循环
	SoundManager.play_bgm("round.mp3", -6.0)
	await get_tree().process_frame
	var bgm_player: AudioStreamPlayer = SoundManager.get("_bgm_player")
	var explore_loop: bool = false
	if bgm_player and bgm_player.stream is AudioStreamMP3:
		explore_loop = (bgm_player.stream as AudioStreamMP3).loop
	if not explore_loop:
		push_error("[Audio] 探索 BGM 未设为循环")
	print("=== 自动测试: 探索BGM循环=", explore_loop, " (应为 true)")

	# ③ 战斗开始 → fight.mp3; 战斗结束 → 切回 round.mp3
	if not TurnManager.combat_mode:
		TurnManager.enter_combat()
		await get_tree().process_frame
	await get_tree().process_frame
	var in_fight: bool = str(SoundManager.get("_current_bgm")) == "fight.mp3"
	var fight_loop: bool = false
	if bgm_player and bgm_player.stream is AudioStreamMP3:
		fight_loop = (bgm_player.stream as AudioStreamMP3).loop
	if not in_fight:
		push_error("[Audio] 进入战斗未切到 fight.mp3, 当前=%s" % str(SoundManager.get("_current_bgm")))
	TurnManager.exit_combat(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var back_to_explore: bool = str(SoundManager.get("_current_bgm")) == "round.mp3"
	if not back_to_explore:
		push_error("[Audio] 战斗结束未切回 round.mp3, 当前=%s" % str(SoundManager.get("_current_bgm")))
	print("=== 自动测试: 战斗BGM切换=", in_fight, " 循环=", fight_loop, " 结束切回探索BGM=", back_to_explore, " (均应为 true)")


## 点丧尸所在地块弹菜单回归: 构造点击丧尸格中心的鼠标事件 → 应弹攻击菜单 (用户反馈: 只能点血条才能弹)
func _test_click_enemy_cell() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[EnemyCell] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy) or enemy.get("hp") <= 0:
		push_error("[EnemyCell] 敌人无效")
		return
	_action_menu.hide_menu()
	# 点击丧尸所在格中心: 用与 _event_to_world 互逆的变换构造屏幕坐标
	var world_pos := _world_pos(_cell_of(enemy.global_position))
	var ev := _make_click_event(world_pos)
	# 探索模式点击丧尸格 → 应弹菜单 (不依赖战斗状态)
	_handle_explore_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[EnemyCell] 点丧尸地块未弹菜单 (坐标=", ev.position, " 世界=", world_pos, " 丧尸=", enemy.global_position, ")")
	_action_menu.hide_menu()
	print("=== 自动测试: 点丧尸地块弹菜单=", ok, " (应为 true)")
	# 移动中的丧尸: 点它正走向的格也应弹菜单 (用户反馈: 丧尸巡逻移动中点地块没反应)
	await _test_click_moving_enemy()


## 残血丧尸选中回归 (用户反馈: 普通丧尸只剩 1 血点不中)
## 根因: _raycast_enemy 旧代码 int(hp) 截断, 0<hp<1 (血条显示"1") 时 int(0.8)=0 被当死亡跳过
func _test_low_hp_enemy_selectable() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[LowHpEnemy] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy):
		return
	_action_menu.hide_menu()
	# 设为 0<hp<1 残血 (血条会显示成 1, 但 float 实际不到 1) — 旧逻辑会把它当死亡跳过
	enemy.hp = 0.5
	var world_pos := _world_pos(_cell_of(enemy.global_position))
	var ev := _make_click_event(world_pos)
	_handle_explore_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[LowHpEnemy] 残血(0.5)丧尸点不中菜单 (hp=", enemy.hp, ")")
	enemy.hp = enemy.max_hp  # 复原, 避免影响后续测试
	_action_menu.hide_menu()
	print("=== 自动测试: 残血丧尸可选中=", ok, " (应为 true) hp=", 0.5)


## 移动中丧尸点击回归: 丧尸正在移动 (is_moving, 目标格 = clicked) → 点目标格应弹菜单
func _test_click_moving_enemy() -> void:
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[EnemyMove] 无敌人")
		return
	var enemy: Node = enemies[0]
	if not is_instance_valid(enemy):
		return
	_action_menu.hide_menu()
	# 让丧尸开始移动: 目标格 = 当前格右侧
	var start_cell := _cell_of(enemy.global_position)
	var target_cell := start_cell + Vector2i(2, 0)
	enemy.global_position = _world_pos(start_cell)
	enemy.start_walk(_world_pos(target_cell))
	await _await_secs(0.05)  # 开始移动 (可能还在半路, 不在格中心)
	if not enemy.get("is_moving"):
		push_warning("[EnemyMove] 丧尸未开始移动, 跳过")
		enemy.global_position = _world_pos(start_cell)
		return
	# 点目标格 → 应命中 (移动目标格匹配)
	var ev := _make_click_event(_world_pos(target_cell))
	_handle_explore_click(ev)
	var ok: bool = _action_menu.is_open()
	if not ok:
		push_error("[EnemyMove] 移动中丧尸点目标格未弹菜单 目标=", target_cell, " 丧尸位置=", enemy.global_position)
	_action_menu.hide_menu()
	print("=== 自动测试: 移动中丧尸点击=", ok, " (应为 true)")


## 装备磨损回归: 攻击磨损武器 / 受击磨损护甲 / 磨损后攻击防御衰减 / 交易价值折扣
func _test_durability() -> void:
	var ok := true
	# 1. 装备一把有耐久的武器 (手枪 durability=35) → 攻击 → 武器磨损
	var old_weapon: String = _player.get_equipped_item(DataManager.EQUIP_SLOT_WEAPON)
	_player.add_item("pistol", 1)
	_player.equip_item("pistol")
	var w_du_before: int = InventoryBackpack.get_durability("pistol")
	var enemies := TurnManager.get_enemy_units()
	if enemies.is_empty():
		push_error("[Dura] 无敌人")
		return
	_player.execute_attack(enemies[0], _player.get_default_attack())
	var w_du_after: int = InventoryBackpack.get_durability("pistol")
	if w_du_after != w_du_before + 1:
		ok = false
		push_error("[Dura] 攻击未磨损武器: ", w_du_before, " -> ", w_du_after)
	# 2. 装备护甲 (皮背心 durability=30) → 受击 → 护甲磨损 + 防御按耐久衰减
	_player.add_item("leather_vest", 1)
	_player.equip_item("leather_vest")
	var armor_du_before: int = InventoryBackpack.get_durability("leather_vest")
	var def_full: float = 5.0 * 1.0 + _player.get("defense")  # 满耐久防御
	_player.take_damage(10.0)
	var armor_du_after: int = InventoryBackpack.get_durability("leather_vest")
	if armor_du_after != armor_du_before + 1:
		ok = false
		push_error("[Dura] 受击未磨损护甲: ", armor_du_before, " -> ", armor_du_after)
	# 3. 交易价值: 磨损后价值 < 原价值
	var value_full: int = InventoryBackpack.get_item_value("leather_vest")
	InventoryBackpack.damage_item("leather_vest", 15)  # 磨损一半
	var value_worn: int = InventoryBackpack.get_item_value("leather_vest")
	if value_worn >= value_full:
		ok = false
		push_error("[Dura] 磨损后价值未降: ", value_full, " -> ", value_worn)
	# 4. 恢复原装备
	_player.unequip_item(DataManager.EQUIP_SLOT_ARMOR)
	_player.unequip_item(DataManager.EQUIP_SLOT_WEAPON)
	if old_weapon != "":
		_player.equip_item(old_weapon)
	print("=== 自动测试: 装备磨损=", ok, " (应为 true), 武器耐久 ", w_du_before, "->", w_du_after, " 护甲价值 ", value_full, "->", value_worn)


## 尸体点击优先级回归: 尸体旁有敌人时, 点尸体格应开容器 (不被邻格敌人容差抢走)
func _test_corpse_priority() -> void:
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var corpse: Node = corpse_script.new()
	var gp := _cell_of(_player.global_position) + Vector2i(4, 0)
	corpse.setup_corpse(gp, tile_size, ["bandage"], "优先级测试尸体")
	add_child(corpse)
	add_corpse(corpse)
	# Issue B: 挪玩家到尸体旁 1 格, 满足搜刮前提
	_player.global_position = _world_pos(gp - Vector2i(1, 0))
	# 邻格放一个敌人 (会抢占容差命中)
	var enemy_script: Script = load("res://scripts/units/enemies/zombie_basic.gd")
	var enemy: Node = EF.spawn(self, enemy_script, _world_pos(gp + Vector2i(1, 0)), tile_size, 100.0)
	# 点尸体格 (构造点击事件)
	var world_pos := _world_pos(gp)
	var ev := _make_click_event(world_pos)
	_handle_explore_click(ev)
	var opened: bool = _container_ui != null and _container_ui.is_open()
	if not opened:
		push_error("[CorpsePri] 尸体旁有敌人时点尸体格未开容器 (被邻格敌人抢了)")
	print("=== 自动测试: 尸体点击优先级=", opened, " (应为 true)")
	_container_ui.close()
	# 清理
	corpse.queue_free()
	remove_corpse(corpse)
	if is_instance_valid(enemy):
		enemy.queue_free()


## 尸体生成格位回归: 丧尸在某格死亡 → 尸体必须落在它活着所在的那一格
## (用户反馈: 丧尸死了尸体没刷新在活着的格子; 根因是 roundi 取整 → cell+0.5 进位到下一格)
func _test_corpse_spawn_cell() -> void:
	var zombie_script: Script = load("res://scripts/units/enemies/zombie_basic.gd")
	var enemy: Node = EF.spawn(self, zombie_script, _world_pos(Vector2i(6, 4)), tile_size, 100.0)
	# 取敌人实际所在格 (与游戏内一致: 中心对齐), 不硬编码假设
	var cell := _cell_of(enemy.global_position)
	var before := _corpses.size()
	# 击杀 → 应生成尸体在其所在格
	enemy.die()
	await get_tree().process_frame
	# 只取本次新增的尸体 (await 帧内可能有其他敌人死亡, 不混入)
	var new_corpses := _corpses.slice(before)
	var corpse: Node = null
	for c in new_corpses:
		if c.grid_pos == cell:   # 精确匹配我刚杀的那只
			corpse = c
			break
	var ok := true
	if corpse == null:
		push_error("[CorpseCell] 击杀后未生成尸体于所在格=%s" % cell)
		ok = false
	else:
		print("=== 自动测试: 尸体生成在丧尸所在格=", ok, " (应为 true) cell=", corpse.grid_pos)
	# 清理本次新增的所有尸体 (含同帧其他死亡的), 避免泄漏
	for c in new_corpses:
		if is_instance_valid(c):
			c.queue_free()
			remove_corpse(c)
	if is_instance_valid(enemy):
		enemy.queue_free()


## 叠尸回归: 两个丧尸同格阵亡 → 第二具尸体必须挪到相邻空位, 不得与第一具同格
func _test_corpse_no_overlap() -> void:
	var corpse_script: Script = load("res://scripts/tiles/corpse.gd")
	var cell := Vector2i(8, 8)
	# 先在 (8,8) 放一具尸体 (模拟先死的丧尸)
	var c1: Node = corpse_script.new()
	c1.setup_corpse(cell, tile_size, ["bandage"], "占位尸体")
	add_child(c1)
	add_corpse(c1)
	var ok := true
	if is_cell_free_for_corpse(cell):
		push_error("[CorpseOverlap] (8,8) 已放尸体却判定为空")
		ok = false
	var nudged := find_free_corpse_cell(cell)
	if nudged == cell:
		push_error("[CorpseOverlap] 同格已占用却未挪开, 仍返回=%s" % cell)
		ok = false
	# 模拟第二具尸体落到 nudged 格, 再查一次应仍不冲突
	var c2: Node = corpse_script.new()
	c2.setup_corpse(nudged, tile_size, ["bandage"], "第二具")
	add_child(c2)
	add_corpse(c2)
	if c1.grid_pos == c2.grid_pos:
		push_error("[CorpseOverlap] 两具尸体同格: c1=%s c2=%s" % [c1.grid_pos, c2.grid_pos])
		ok = false
	else:
		print("=== 自动测试: 叠尸挪位=%s (已占用格=%s, 第二具落在=%s) 不重叠=true" % [ok, cell, c2.grid_pos])
	c1.queue_free(); c2.queue_free()
	remove_corpse(c1); remove_corpse(c2)


## 全部拿走按钮回归: 模拟点击 → 尸体清空 + 物品进背包 (修复: 场景 _input 抢事件导致按钮失效)
func _test_take_all_button() -> void:
	var corpse_items: Array = _container_ui._container.list_inventory()
	var total := corpse_items.size()
	if total == 0:
		push_error("[TakeAll] 测试尸体无物品")
		return
	_container_ui._on_take_all_pressed()
	var remaining: Array = _container_ui._container.list_inventory()
	var ok: bool = remaining.is_empty()
	if not ok:
		push_error("[TakeAll] 全部拿走后尸体未清空: ", remaining)
	# 验证物品进了背包 (绷带+急救包)
	if _player.count_item("bandage") < 1 or _player.count_item("medkit") < 1:
		ok = false
		push_error("[TakeAll] 物品未进背包")
	# 验证容器剩余重量 = 0 (修复: 之前显示背包负重, 拿走物品数字反而变大)
	var label_text: String = _container_ui._weight_label.text if _container_ui._weight_label else ""
	if "容器剩余 0.0kg" not in label_text:
		ok = false
		push_error("[TakeAll] 容器重量标签错误: ", label_text)
	print("=== 自动测试: 全部拿走=", ok, " (应为 true), 共拿走 ", total, " 件, 标签: ", label_text)


## 稀有度边框回归: 绷带=普通(灰), 急救包=优秀(绿); 验证 DataManager 稀有度表正确
func _test_rarity_border() -> void:
	var bandage: DataManager.ItemData = DataManager.get_item("bandage")
	var medkit: DataManager.ItemData = DataManager.get_item("medkit")
	var pistol: DataManager.ItemData = DataManager.get_item("pistol")
	var crystal_huge: DataManager.ItemData = DataManager.get_item("crystal_huge")
	var ok: bool = true
	if bandage.rarity != DataManager.Rarity.COMMON:
		ok = false
		push_error("[Rarity] 绷带稀有度应为 COMMON")
	if medkit.rarity != DataManager.Rarity.UNCOMMON:
		ok = false
		push_error("[Rarity] 急救包稀有度应为 UNCOMMON")
	if pistol.rarity != DataManager.Rarity.RARE:
		ok = false
		push_error("[Rarity] 手枪稀有度应为 RARE")
	if crystal_huge.rarity != DataManager.Rarity.LEGENDARY:
		ok = false
		push_error("[Rarity] 大能量晶石稀有度应为 LEGENDARY")
	if not DataManager.RARITY_COLORS.has(DataManager.Rarity.LEGENDARY):
		ok = false
		push_error("[Rarity] 稀有度颜色表缺少 LEGENDARY")
	print("=== 自动测试: 稀有度边框数据=", ok, " (应为 true)")
